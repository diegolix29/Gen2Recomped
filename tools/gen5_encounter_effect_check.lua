-- Run:  python tools/run_lua_check.py tools/gen5_encounter_effect_check.lua <black .nds>
--
-- BLACK AND WHITE'S INTO-BATTLE EFFECTS (src/import/Gen5EncounterEffects.lua,
-- src/render/Gen5BattleTransition.lua): ov21's choice of effect, the six
-- ee_* models baked out of /a/1/2/9, and the one fact the camera has to get
-- right -- frame 0 seen through arm9 0x0202E688's camera is the screen,
-- 0..256 x 0..192, so the effect starts on the field untouched. Then a whole
-- run of the program: two flashes, the model, the fade to white.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local rom = arg and arg[1] or './Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds'

-- nothing reaches the disk: the scenes' textures are PNGs
local IW = require('src.import.ImageWriter')
IW.save = function() return true end
IW.fromRGBA8 = function(w, h) return { width = w, height = h } end

local T = require('src.render.Gen5BattleTransition')
-- the choice (ov21 0x021CF5D8 / 0x021CF748)
check(T.effectFor({ grass = true }) == 0, 'wild in grass is effect 0')
check(T.effectFor({ grass = true, darkGrass = true }) == 1, 'wild in dark grass is effect 1')
check(T.effectFor({ species = 571, grass = true }) == 35, 'Zoroark is effect 35')
check(T.effectFor({ species = 494 }) == 31, 'Victini is effect 31')
check(T.effectFor({ species = 643 }) == 32 and T.effectFor({ species = 641 }) == 33
      and T.effectFor({ species = 638 }) == 34, 'the legends take 32 / 33 / 34')
check(T.effectFor({ water = true }) == 2, 'wild on water is effect 2')
check(T.effectFor({ behaviour = 0x0C }) == 4, 'wild on sand is effect 4')
check(T.effectFor({ behaviour = 0x0A }) == 3, 'wild on a cave floor is effect 3')
check(T.effectFor({ trainer = true }) == 5, 'a trainer is effect 5')
check(T.effectFor({ trainer = true, water = true }) == 6, 'a trainer on water is effect 6')
check(T.played(0) == 'ee_yasei1' and T.played(6) == 'ee_trmizu' and T.played(33) == 'cutin_33'
      and T.played(2) == 'mesh_2' and T.played(8, true) == 'mesh_8' and T.played(15, true) == 'cutin_15',
      'what each id plays')

-- the mesh wipes (src/render/Gen5MeshWipes.lua), run to the end
local W = require('src.render.Gen5MeshWipes')
for id, want in pairs({ [2] = { 55, 70 }, [36] = { 60, 80 }, [7] = { 70, 80 }, [9] = { 95, 105 }, [8] = { 30, 70 } }) do
  local S = W.new(id)
  local fading, level, n, done = false, 0, 0, false
  while not done and n < 400 do
    n = n + 1
    if fading then level = math.min(16, level + 2) end
    done = W.step(S, function() fading = true end, function() return level >= 16 end)
  end
  check(done and n >= want[1] and n <= want[2], ('mesh wipe %d ends in %d ticks'):format(id, n))
end
local R = W.new(2)
for _ = 1, 2 do W.step(R, function() end, function() return false end) end
check(R.h[12 * 33 + 15] ~= 0 and R.h[0] == 0, 'the ripple spreads from the centre and the border stays still')

local X = require('src.import.RomExtractorGen5')
local x = X.new(rom, 'black')
check(x ~= nil, 'the cartridge opens')
if x then
  local E = require('src.import.Gen5EncounterEffects')
  local rec = E.build(x)
  check(rec ~= nil, 'the effects build')
  local want = { ee_yasei1 = 30, ee_yasei2 = 30, ee_trnor = 30, ee_trmizu = 40, ee_symbol = 35, ee_zoroark = 55 }
  for name, frames in pairs(want) do
    local eff = rec and rec.effects[name]
    check(eff and eff.frames == frames, name .. ' runs ' .. frames .. ' frames')
    eff = eff and E.unpack(eff)
    if eff then
      -- frame 0 through the camera
      local cam = rec.camera
      local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
      local pos = eff.pos[1]
      for i = 1, #pos, 3 do
        local d = cam.eyeZ - pos[i + 2]
        local sx = 128 + 128 * pos[i] / (d * cam.tanHalfY * cam.aspect)
        local sy = 96 - 96 * pos[i + 1] / (d * cam.tanHalfY)
        x0, x1, y0, y1 = math.min(x0, sx), math.max(x1, sx), math.min(y0, sy), math.max(y1, sy)
      end
      -- ee_symbol and ee_zoroark carry pieces past the plane's edge (the
      -- ribbon, the slashes), so theirs covers the screen rather than fits it
      local exact = name ~= 'ee_symbol' and name ~= 'ee_zoroark'
      local fits = exact and (math.abs(x0) < 2.5 and math.abs(x1 - 256) < 2.5 and math.abs(y0) < 2.5 and math.abs(y1 - 192) < 2.5)
                   or (not exact and x0 < 2.5 and x1 > 253.5 and y0 < 2.5 and y1 > 189.5)
      check(fits, ('%s frame 0 is the screen (%.1f..%.1f x %.1f..%.1f)'):format(name, x0, x1, y0, y1))
      check(#eff.uv / 2 == #pos / 3 and #eff.tris % 3 == 0, name .. ' lists agree')
    end
  end
  -- the ov73 scenes (effects 3 and 4)
  check(rec.scenes and rec.scenes.cave_ci and rec.scenes.cave_ci.frames == 21
        and rec.scenes.sand_ci and rec.scenes.sand_ci.frames == 46, 'cave_ci and sand_ci bake')
  check(T.played(3) == 'cave_ci' and T.played(4) == 'sand_ci', 'effects 3 and 4 play the scenes')
  local cave = rec.scenes and E.unpack(rec.scenes.cave_ci)
  if cave then
    -- the curtain starts above the view and ends covering it
    local function rangeY(f)
      local lo, hi = math.huge, -math.huge
      for i = 2, #cave.pos[f], 3 do lo = math.min(lo, cave.pos[f][i]); hi = math.max(hi, cave.pos[f][i]) end
      return lo, hi
    end
    local lo0 = rangeY(1)
    local loN, hiN = rangeY(cave.frames)
    local half = rec.scenes.view.halfY
    check(lo0 > half and loN < -half and hiN > half, 'the curtain drops from above the view to cover it')
  end
  -- the cut-ins (src/import/Gen5EncounterCutIns.lua)
  local cut = rec.cutins
  check(cut and cut.effects[14] and cut.effects[14].scene == 13 and cut.names[cut.effects[14].name] == 'Cilan',
        'Cilan plays rival_ci with his own name')
  check(cut and cut.scenes[13] and cut.scenes[13].frames == 111 and #cut.scenes[13].models == 2, 'rival_ci: two models, 111 frames')
  check(cut and cut.scenes[14] and cut.scenes[14].frames == 121, 'shiten: 121 frames')
  local faces = 0
  for n = 0, 21 do if cut and cut.faces[n] then faces = faces + 1 end end
  check(faces == 22, 'the 22 cut-in faces')
  check(T.effectFor({ trainer = true, trainerClass = 11 }) == 14 and T.effectFor({ trainer = true, trainerClass = 82 }) == 29
        and T.effectFor({ trainer = true, trainerClass = 39, water = true }) == 30, 'the special classes come before the terrain')
  local roles = {}
  for _, m in ipairs(cut and cut.scenes[13].models or {}) do for _, sh in ipairs(m.shapes) do if sh.role then roles[sh.role] = true end end end
  check(roles.face and roles.hero and roles.name and roles.heroName, 'rival_ci wears the face, the hero and both names')
  -- the particles (SPA 70: one emitter, a 32 x 32 texture), and a burst run
  local sp = cut and cut.scenes[13].particles
  check(sp and #sp.emitters == 1 and sp.emitters[1].header.particleLife == 18 and sp.delays[1] == 8, 'rival_ci: SPA 70, emitter 0 after 8 frames')
  if sp then
    local P = require('src.render.Gen5Particles')
    local em = P.new(sp.emitters[1], { 0, 0, 64 }, P.newRandom(1))
    local most = 0
    for _ = 1, 40 do em:step(); most = math.max(most, #em.particles) end
    check(most == 12 and em:done(), ('the burst: 3 frames of 4, then gone (%d at most)'):format(most))
  end
  -- the program, start to finish
  local grass = { inBounds = function() return true end, cellBehaviour = function() return 0x04 end }
  local game = { data = { gen5_encounter_effects = rec },
                 stack = { top = function() return { map = grass, player = { cellX = 0, cellY = 0 } } end } }
  local t = T.new(game, nil, { trainer = false })
  local maxTop, sawModel = 0, false
  local n = 0
  while not t.finished and n < 500 do
    t:step(); n = n + 1
    maxTop = math.max(maxTop, t.top.level)
    if t.state == 4 then sawModel = true end
  end
  check(t.finished and sawModel and maxTop == 16 and t.flashes == 2, 'two flashes, the model, the end')
  check(t.both.level == 16, 'it ends white')
  check(n > 50 and n < 90, ('it takes %d ticks'):format(n))
end

print(('gen5 encounter effects: %d passed, %d failed'):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
