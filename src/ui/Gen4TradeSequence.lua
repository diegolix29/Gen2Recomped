-- THE IN-GAME TRADE CUTSCENE: Platinum's trade sequence, and HeartGold /
-- SoulSilver's, which is the same program on the same art.
--
-- A transcription of pokeplatinum src/cutscenes/trade_sequence/*.c, phase by
-- phase and frame by frame, drawn from `gen4_trade_art` (src/import/
-- Gen4TradeArt.lua). main.c's sTradePhaseTable runs seven phases for an
-- ordinary trade (TRADE_TYPE_NORMAL is 1, and every row's flags include it):
--
--   1 SEND        send_phase.c       your Pokemon on the black stage, "X will
--                                    be sent to Y." / "Bye-bye, X!" and its
--                                    cry, the flash, the 3D ball bouncing
--   2 TUBE        tube_phase.c       zoom out of the DS picture, the ball
--                                    spiralling up the beam, the running
--                                    lights, the beam scrolling, the sparks
--   3 FLY-BY      ball_flyby_phase.c the ball crossing the sky, the twinkle
--   4 WORMHOLE    wormhole_phase.c   the two Pokemon passing each other
--   5 ARRIVAL     receive_ball_phase.c the twinkle, the ball falling through
--                                    the sky
--   6 REVEAL      pokemon_reveal_phase.c the ball coming down the beam into
--                                    the other DS, the lights the other way,
--                                    the zoom into its screen
--   7 RECEIVE     receive_phase.c    the ball dropping, bouncing white, the
--                                    new Pokemon, "Y sent over X." with the
--                                    fanfare, "Take good care of X!"
--
-- HeartGold's overlay 71 (TradeSequence_Init / _Main / _Exit, assembly in
-- pokeheartgold) is the same machine: the same seven-row table with the same
-- flags (3,3,3,1,5,5,5), the same archive (/a/0/8/9 is byte-identical to
-- demo_trade.narc), the same sound effects at the same call sites
-- (SEQ_SE_DP_KOUKAN01..10, SEQ_SE_DP_KON), the same RNG seed 0x035947D1 for
-- the sparks and the same literals for every speed and position checked
-- (0x2F60 bounce, 0xEBE0 tube camera, 0x18E3 / 0x1150 sky camera, 0x0FA4 /
-- 0x07D2 fields of view). What differs is read from the art's index:
--   * the music, SEQ_GS_KOUKAN (1012) for SEQ_KOUKAN, and the fanfare,
--     SEQ_ME_SHINKAOME (1188) for SEQ_FANFA5;
--   * the words, message bank 179 for 350 (the same six lines);
--   * the platform tilemaps, members 266 / 267 of /a/0/0/7 for 262 / 263;
--   * ONE SPEED: the fly-by's centre climbs 0x134C4 (79044) a frame in
--     HeartGold's ov71_022499A4, where Platinum's compiles
--     (BALL_TARGET_CENTER_Y - BALL_INITIAL_CENTER_Y) / 60 = 79027.
--
-- THE TWO SCREENS. Each phase sets up both display engines and the
-- cartridge moves the main one (the 3D layer) between screens with
-- GX_SetDispSelect -- the send starts on the BOTTOM screen and the ball
-- crosses to the top one. Both engines are drawn here; with a second screen
-- the top shows whichever engine the cartridge would show there and the
-- bottom the other. On ONE screen the main engine is the one shown, which is
-- where the ball and the Pokemon always are.
--
-- WHAT IS APPROXIMATED, all of it small:
--   * the Pokemon's sprite animation (PokemonSprite_InitAnim) -- the cry
--     plays, the picture stays on its first frame -- and the cry's per-species
--     delay (PokemonSprite_LoadCryDelay) is not applied;
--   * GFXBoxTest_IsModelInView is a frustum test of the model's own box,
--     which is what the hardware box test answers;
--   * a model at polygon alpha 0 is not drawn (the DS draws such polygons as
--     wireframe); edge marking is drawn as a one-pixel outline in the edge
--     colour where the ball meets the clear colour, and toon shading is the
--     renderer's ordinary lighting;
--   * the message window is the engine's own Gen 4 box, printed at once
--     (TEXT_SPEED_NO_TRANSFER) and never waiting for a button, as here;
--   * screen fades are linear over their step count.

local Gen4Model = require("src.render.Gen4Model")
local Assets = require("src.render.Assets")
local Strings = require("src.core.Strings")
local Logger = require("src.core.Logger")
local bit = require("bit")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local W, H = 256, 192
local floor = math.floor

-- --------------------------------------------------------------- numbers --

-- C's integer division, which truncates toward zero
local function idiv(a, b)
  local q = a / b
  if q >= 0 then return floor(q) end
  return -floor(-q)
end
local function asr12(v) return floor(v / 4096) end         -- fx32 >> 12
local function s16(v) v = v % 65536; return v >= 32768 and v - 65536 or v end
local function u16(v) return v % 65536 end
local function fxMul(a, b) return floor((a * b + 2048) / 4096) end
local TAU = math.pi * 2
local function sinIdx(a) return math.sin(u16(a) / 65536 * TAU) end
local function cosIdx(a) return math.cos(u16(a) / 65536 * TAU) end
-- CalcSineDegrees / CalcCosineDegrees: the fx32 table
local function sinDeg(d) return floor(math.sin(math.rad(d)) * 4096 + 0.5) end
local function cosDeg(d) return floor(math.cos(math.rad(d)) * 4096 + 0.5) end

-- MTRNG (math_util.c): MT19937, which the tube seeds with 56182737 before it
-- scatters its twenty sparks, so their places are the cartridge's own.
local function mulMod32(a, x)
  local hi, lo = floor(a / 65536), a % 65536
  return (lo * x + ((hi * x) % 65536) * 65536) % 4294967296
end
local function u32(v) return v % 4294967296 end
local function newMT(seed)
  local mt = { [0] = u32(seed) }
  for i = 1, 623 do
    local prev = mt[i - 1]
    local x = u32(bit.bxor(prev, bit.rshift(prev, 30)))
    mt[i] = (mulMod32(1812433253, x) + i) % 4294967296
  end
  local index = 624
  local MAG = { [0] = 0, [1] = 0x9908B0DF }
  return function()
    if index >= 624 then
      for i = 0, 623 do
        local y = u32(bit.bor(bit.band(mt[i], 0x80000000), bit.band(mt[(i + 1) % 624], 0x7FFFFFFF)))
        mt[i] = u32(bit.bxor(mt[(i + 397) % 624], bit.rshift(y, 1), MAG[y % 2]))
      end
      index = 0
    end
    local y = mt[index]
    index = index + 1
    y = u32(bit.bxor(y, bit.rshift(y, 11)))
    y = u32(bit.bxor(y, bit.band(bit.lshift(y, 7), 0x9D2C5680)))
    y = u32(bit.bxor(y, bit.band(bit.lshift(y, 15), 0xEFC60000)))
    y = u32(bit.bxor(y, bit.rshift(y, 18)))
    return y
  end
end
Screen._newMT = newMT

-- ----------------------------------------------------------------- words --

local function speciesName(data, species)
  local def = data and data.pokemon and data.pokemon[species]
  return def and (def.name or def.displayName) or ("#" .. tostring(species))
end

local function monName(data, mon)
  if not mon then return "" end
  return mon.nickname or speciesName(data, mon.species)
end

-- message `index` of the trade bank, its {STRVAR_1 _ slot _} filled from the
-- three buffers TradeSequence_Init sets: 0 the Pokemon sent, 1 the Pokemon
-- received, 2 the other trainer
local FALLBACK = {
  [0] = Strings.source("{STRVAR_1 0 0 0} will be\nsent to {STRVAR_1 3 2 0}."),
  [1] = "Bye-bye, {STRVAR_1 0 0 0}!",
  [2] = Strings.source("{STRVAR_1 3 2 0} sent over\n{STRVAR_1 0 1 0}."),
  [3] = "Take good care of {STRVAR_1 0 1 0}!",
}
function Screen.text(data, bank, index, buffers)
  local key = ("TEXT_B%04d_%05d"):format(bank or 350, index)
  local s = ((data or {}).text or {})[key] or Strings(FALLBACK[index] or "")
  -- the buffers go in through the shared Gen 4 template (slot 0 up) and
  -- gen4Markup expands the {STRVAR_1 _ slot _} tokens from them
  buffers = buffers or {}
  local ctx = {}
  require("src.import.Gen4Text").buffer(ctx, buffers[0] or "", buffers[1] or "", buffers[2] or "")
  local ok, Commands = pcall(require, "src.script.Commands")
  if ok and Commands and Commands.gen4Markup then
    local okM, plain = pcall(Commands.gen4Markup, s, ctx)
    if okM and type(plain) == "string" then s = plain end
  end
  s = s:gsub("{WAIT %d+}", ""):gsub("{[^}]*}", ""):gsub("[\r\011]", "")
  return s
end

-- ----------------------------------------------------------------- sound --

local function se(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe and self.data then pcall(Sound.playSe, self.data, name) end
end

local function cry(self, mon)
  if not mon or mon.isEgg then return end
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playCry then pcall(Sound.playCry, self.data, mon.species) end
  -- PokemonSprite_InitAnim beside the cry (send_phase.c 337, receive_phase.c
  -- 345): the species' two-frame script (src/pokemon/PicAnim.lua)
  local okA, anim = pcall(require("src.pokemon.PicAnim").forMon, self.data, mon, "front")
  if okA and anim then
    pcall(anim.start, anim)
    self.monAnims = self.monAnims or {}
    self.monAnims[mon] = anim
  end
end

-- ---------------------------------------------------------------- pictures --

local function image(path)
  if type(path) == "table" then path = path.path end
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then img:setFilter("nearest", "nearest") return img end
  return nil
end

function Screen:pic(key)
  self.pics = self.pics or {}
  if self.pics[key] == nil then
    self.pics[key] = image(self.art[key]) or false
  end
  return self.pics[key] or nil
end

-- ------------------------------------------------------------ OBJ sprites --
--
-- A cell-animated sprite (TradeSequence_AddSprite): animating at FX32_ONE, so
-- one tick a frame, advanced in the VBlank callback (SpriteList_Update).

local Sprite = {}
Sprite.__index = Sprite

local function newSprite(screen, set, x, y, priority)
  return setmetatable({ screen = screen, set = set, x = x, y = y, priority = priority or 0,
                        visible = false, seq = 0, t = 0 }, Sprite)
end

function Sprite:setAnim(seq) self.seq, self.t = seq, 0 end

function Sprite:frames()
  local s = self.set and self.set.sequences and self.set.sequences[self.seq]
  return s and s.frames or {}
end

function Sprite:length()
  local n = 0
  for _, f in ipairs(self:frames()) do n = n + (f.duration or 0) end
  return n
end

-- Sprite_IsAnimated: a one-shot sequence (playbackMode 1) stops on its last
-- frame
function Sprite:isAnimated() return self.t < self:length() end

function Sprite:tick() if self.t < self:length() then self.t = self.t + 1 end end

function Sprite:cell()
  local frames = self:frames()
  local at = 0
  for _, f in ipairs(frames) do
    at = at + (f.duration or 0)
    if self.t < at then return f.cell end
  end
  local last = frames[#frames]
  return last and last.cell
end

function Sprite:draw(prefix)
  if not self.visible then return end
  local cell = self:cell()
  local rec = cell and self.set.cells and self.set.cells[cell]
  if not rec then return end
  local img = self.screen:cellImage(rec)
  if not img then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, floor(self.x) - (rec.originX or 0), floor(self.y) - (rec.originY or 0))
end

function Screen:cellImage(rec)
  self.cellPics = self.cellPics or {}
  local p = rec.path
  if self.cellPics[p] == nil then self.cellPics[p] = image(p) or false end
  return self.cellPics[p] or nil
end

-- ------------------------------------------------------------- the 3D scene --
--
-- 3d_scene.c: one camera (Camera_InitWithTarget, distance 1228800 = 300
-- units, angle zero, fovY 4004 -- a HALF angle -- perspective, clip 0..1000)
-- and one model, drawn at position * rotation (Z, then Y, then X) * scale.

local DIST = 1228800 / 4096
local FLIP_Y = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
local multiply = Gen4Model.multiply

local function newScene(screen)
  local sc = { screen = screen, target = { 0, 0, 0 }, angle = { 0, 0, 0 }, fov = 4004,
               projection = 0, model = nil }
  -- Camera_AdjustPositionAroundTarget
  function sc:place()
    local ax, ay = self.angle[1], self.angle[2]
    self.pos = { self.target[1] + sinIdx(ay) * DIST * cosIdx(ax),
                 self.target[2] + sinIdx(-ax) * DIST,
                 self.target[3] + cosIdx(ay) * DIST * cosIdx(ax) }
  end
  function sc:setAngle(x, y, z) self.angle = { u16(x), u16(y or 0), u16(z or 0) }; self:place() end
  -- Camera_AdjustAngleAroundSelf: the camera stays, the target swings
  function sc:adjustAngle(dx)
    local a = self.angle
    a[1] = u16(a[1] + dx)
    local ax, ay = a[1], a[2]
    self.target = { self.pos[1] - sinIdx(ay) * DIST * cosIdx(ax),
                    self.pos[2] - sinIdx(-ax) * DIST,
                    self.pos[3] - cosIdx(ay) * DIST * cosIdx(ax) }
  end
  function sc:viewProjection()
    local view = Gen4Model.lookAt(self.pos, self.target, { 0, 1, 0 })
    local proj
    if self.projection == 1 then
      -- Camera_ComputeProjectionMatrix's orthographic box: top =
      -- tan(fovY) * distance, right = top * 4/3
      proj = Gen4Model.orthographic(sinIdx(self.fov) / cosIdx(self.fov) * DIST, 4 / 3, 0, 1000)
    else
      proj = Gen4Model.perspective(2 * u16(self.fov) / 65536 * TAU, 4 / 3, 1, 1000)
    end
    return multiply(FLIP_Y, multiply(proj, view)), multiply(proj, view)
  end
  sc:place()
  return sc
end

-- Trade3DModel_Load: member 27, at a place in fx32, enabled or not
function Screen:loadModel(scene, x, y, z, enabled)
  local m = { pos = { x, y, z }, rot = { 0, 0, 0 }, scale = 4096, alpha = 31, enabled = enabled and true or false }
  scene.model = m
  return m
end

local function rotation(r)
  local cx, sx = cosIdx(r[1]), sinIdx(r[1])
  local cy, sy = cosIdx(r[2]), sinIdx(r[2])
  local cz, sz = cosIdx(r[3]), sinIdx(r[3])
  local Rx = { 1, 0, 0, 0, 0, cx, -sx, 0, 0, sx, cx, 0, 0, 0, 0, 1 }
  local Ry = { cy, 0, sy, 0, 0, 1, 0, 0, -sy, 0, cy, 0, 0, 0, 0, 1 }
  local Rz = { cz, -sz, 0, 0, sz, cz, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
  return multiply(Rx, multiply(Ry, Rz))
end

local function modelMatrix(m)
  local s = m.scale / 4096
  local R = rotation(m.rot)
  local T = { 1, 0, 0, m.pos[1] / 4096, 0, 1, 0, m.pos[2] / 4096, 0, 0, 1, m.pos[3] / 4096, 0, 0, 0, 1 }
  local S = { s, 0, 0, 0, 0, s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1 }
  return multiply(T, multiply(R, S))
end

-- Trade3DModel_IsInView (GFXBoxTest_IsModelInView): is any of the model's box
-- inside the view volume? Outside only when every corner is beyond the same
-- clip plane.
function Screen:inView(scene)
  local m = scene.model
  local box = (self.art.model or {}).box or { -5, -5, -5, 5, 5, 5 }
  local _, vp = scene:viewProjection()
  local mvp = multiply(vp, modelMatrix(m))
  local out = { 0, 0, 0, 0, 0, 0 }
  for i = 0, 7 do
    local x = (i % 2 == 0) and box[1] or box[4]
    local y = (floor(i / 2) % 2 == 0) and box[2] or box[5]
    local z = (floor(i / 4) % 2 == 0) and box[3] or box[6]
    local cx = mvp[1] * x + mvp[2] * y + mvp[3] * z + mvp[4]
    local cy = mvp[5] * x + mvp[6] * y + mvp[7] * z + mvp[8]
    local cz = mvp[9] * x + mvp[10] * y + mvp[11] * z + mvp[12]
    local cw = mvp[13] * x + mvp[14] * y + mvp[15] * z + mvp[16]
    if cx < -cw then out[1] = out[1] + 1 end
    if cx > cw then out[2] = out[2] + 1 end
    if cy < -cw then out[3] = out[3] + 1 end
    if cy > cw then out[4] = out[4] + 1 end
    if cz < -cw then out[5] = out[5] + 1 end
    if cz > cw then out[6] = out[6] + 1 end
  end
  for _, n in ipairs(out) do if n == 8 then return false end end
  return true
end

-- -------------------------------------------------------------- shaders --

local layerShader
local function shaderFor()
  if layerShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern number bright;
      extern number edge;
      extern vec2 texel;
      extern vec3 edgeColour;
      vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        if (edge > 0.5 && p.a > 0.0) {
          float n = Texel(tex, uv + vec2(texel.x, 0.0)).a * Texel(tex, uv - vec2(texel.x, 0.0)).a
                  * Texel(tex, uv + vec2(0.0, texel.y)).a * Texel(tex, uv - vec2(0.0, texel.y)).a;
          if (n == 0.0) p.rgb = edgeColour * p.a;
        }
        if (bright > 0.0) p.rgb = mix(p.rgb, vec3(p.a), bright);
        else if (bright < 0.0) p.rgb = mix(p.rgb, vec3(0.0), -bright);
        return p * colour;
      }
    ]])
    layerShader = ok and sh or false
    if not ok then Logger.warn("gen4 trade: layer shader failed: %s", tostring(sh)) end
  end
  return layerShader or nil
end

-- draw a premultiplied canvas with a brightness (-16..16) and edge marking
local function drawLayer(canvas, bright, edge)
  local g = love.graphics
  local sh = shaderFor()
  g.setBlendMode("alpha", "premultiplied")
  if sh then
    sh:send("bright", (bright or 0) / 16)
    sh:send("edge", edge and 1 or 0)
    sh:send("texel", { 1 / W, 1 / H })
    -- G3X_SetEdgeColorTable: GX_RGB(4, 4, 4) for every polygon id
    sh:send("edgeColour", { 4 / 31, 4 / 31, 4 / 31 })
    g.setShader(sh)
  end
  g.setColor(1, 1, 1, 1)
  g.draw(canvas, 0, 0)
  g.setShader()
  g.setBlendMode("alpha", "alphamultiply")
end
Screen._drawLayer = drawLayer

-- ------------------------------------------------------------ the screen --

function Screen:uiSize() return W, H end
function Screen:wantsFillScale() return true end

-- opts: sending, receiving (the two Pokemon), otName (the other trainer),
-- background (0 day / 1 evening / 2 night), onDone
function Screen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Screen)
  self.game = game
  self.data = game and game.data or {}
  self.art = self.data.gen4_trade_art
  self.onDone = opts.onDone
  self.sending, self.receiving = opts.sending, opts.receiving
  self.background = math.max(0, math.min(2, tonumber(opts.background) or Screen.backgroundNow()))
  self.buffers = { [0] = monName(self.data, self.sending), [1] = monName(self.data, self.receiving),
                   [2] = opts.otName or "" }
  self.frame = 0
  self.tasks = {}
  self.bright = { main = -16, sub = -16 }     -- the field faded out to black
  self.bg0 = 0                                -- G2_SetBlendBrightness on BG0
  self.disp = "SUB_MAIN"
  self.phaseIndex = 1
  self.phase = nil
  if type(self.art) ~= "table" then
    Logger.warn("gen4 trade: this cache carries no `gen4_trade_art` -- re-import to see the trade cutscene")
    self.unavailable = true
    return self
  end
  -- HeartGold's fly-by step (see the header)
  self.hgss = self.art.bgm == "SEQ_GS_KOUKAN"
  -- TradeSequence_Init: Sound_SetSceneAndPlayBGM(SOUND_SCENE_3, SEQ_KOUKAN, 1)
  local okM, Music = pcall(require, "src.core.Music")
  if okM and Music.play then pcall(Music.play, self.data, self.art.bgm or "SEQ_KOUKAN") end
  return self
end

-- NPCTrade_FillAnimationTemplate: morning and day are DAY, twilight is
-- EVENING, night and late night are NIGHT
function Screen.backgroundNow()
  local okC, C = pcall(require, "src.script.Gen4Commands")
  local tod = okC and C.timeOfDayValue and C.timeOfDayValue(tonumber(os.date("%H")))
  if tod == 0 or tod == 1 then return 0 end
  if tod == 2 then return 1 end
  return 2
end

-- --------------------------------------------------------------- tasks --
-- SysTask_Start / _ExecuteOnVBlank / _ExecuteAfterVBlank, all run once a
-- frame after the phase's own step, in the order they were made.
local taskId = 0
function Screen:task(fn)
  taskId = taskId + 1
  local t = { fn = fn, alive = true, id = taskId }
  self.tasks[#self.tasks + 1] = t
  return t
end

-- each live task once; a task made while they run waits for the next frame
function Screen:runTasks()
  local list = self.tasks
  local n = #list
  for i = 1, n do
    local t = list[i]
    if t.alive then t.fn(t) end
  end
  local keep = {}
  for _, t in ipairs(self.tasks) do if t.alive then keep[#keep + 1] = t end end
  self.tasks = keep
end

-- -------------------------------------------------------------- fades --
-- StartScreenFade with a brightness type: the master brightness of one or
-- both engines from black (-16) / white (16) to zero, or the other way.
function Screen:startFade(engines, dir, colour, steps)
  local edge = colour == "white" and 16 or -16
  local from, to = 0, edge
  if dir == "in" then from, to = edge, 0 end
  self.fade = { engines = engines, from = from, to = to, n = math.max(1, steps), t = 0 }
  for _, e in ipairs(engines) do self.bright[e] = from end
end
local BOTH, MAIN = { "main", "sub" }, { "main" }

function Screen:fadeDone() return self.fade == nil end

function Screen:tickFade()
  local f = self.fade
  if not f then return end
  f.t = f.t + 1
  local v = f.from + (f.to - f.from) * f.t / f.n
  v = v < 0 and -floor(-v) or floor(v)
  for _, e in ipairs(f.engines) do self.bright[e] = v end
  if f.t >= f.n then
    for _, e in ipairs(f.engines) do self.bright[e] = f.to end
    self.fade = nil
  end
end

-- ------------------------------------------------------- shared effects --

-- PaletteShimmerEffect (main.c): the tube's running lights. A spark every 30
-- frames (with SEQ_SE_DP_KOUKAN08), each lighting one colour of BG3's
-- extended palette white and moving on every two frames.
function Screen:newShimmer(direction)
  local sh = { lit = {}, alive = true, stopping = false, spawnTimer = 0, sparks = 0,
               slots = {}, nextSlot = 0, direction = direction }
  self.blendLights = true     -- G2_SetBlendAlpha(BG2, BG2 | BG3, 16, 8)
  local screen = self
  local function setEntry(clear, set, on)
    if clear >= 0 and clear < 96 then sh.lit[clear] = nil end
    if set >= 0 and set < 96 then sh.lit[set] = on or nil end
  end
  local function freeSpark(slot)
    local t = sh.slots[slot]
    if t then t.alive = false; sh.slots[slot] = nil; sh.sparks = sh.sparks - 1 end
  end
  sh.freeSpark = freeSpark
  local function spawn()
    if sh.slots[sh.nextSlot] then return end
    local spark = { index = (direction == 1) and -1 or 15, counter = 0, slot = sh.nextSlot }
    local t = screen:task(function(task)
      spark.counter = spark.counter + 1
      if spark.counter >= 2 then
        spark.counter = 0
        if direction == 1 then
          if spark.index + 1 >= 15 then
            setEntry(spark.index, spark.index + 1, false)
            freeSpark(spark.slot)
          else
            setEntry(spark.index, spark.index + 1, true)
            spark.index = spark.index + 1
          end
        else
          if spark.index < 0 then
            setEntry(spark.index, spark.index + 1, false)
            freeSpark(spark.slot)
          else
            setEntry(spark.index + 1, spark.index, true)
            spark.index = spark.index - 1
          end
        end
      end
    end)
    sh.slots[sh.nextSlot] = t
    sh.sparks = sh.sparks + 1
    sh.nextSlot = (sh.nextSlot + 1) % 8
  end
  sh.task = self:task(function(task)
    if not sh.stopping then
      sh.spawnTimer = sh.spawnTimer - 1
      if sh.spawnTimer <= 0 then
        se(screen, "SEQ_SE_DP_KOUKAN08")
        sh.spawnTimer = 30
        spawn()
      end
    elseif sh.sparks == 0 then
      sh.alive = false
      task.alive = false
    end
  end)
  return sh
end

function Screen:freeShimmer(sh)
  if not (sh and sh.alive) then return end
  for slot in pairs(sh.slots) do sh.freeSpark(slot) end
  sh.alive = false
  if sh.task then sh.task.alive = false end
end

-- BgScaleAnimation (main.c): BG2 of both engines scaled about (128, 144) or
-- (128, 56), the step growing by `acceleration` a frame.
local CENTER_Y = { [0] = 144, [1] = 56 }
function Screen:newBgScale(layers, current, target, rate, accel, center)
  local st = { done = false }
  local dir = current < target and 0 or 1
  local function apply()
    for _, l in ipairs(layers) do l.scale, l.cx, l.cy = current, 128, CENTER_Y[center] end
  end
  self:task(function(task)
    local step = idiv(asr12(current * rate), 32)
    if dir == 0 then
      if current + step < target then current = current + step else current = target; st.done = true end
    else
      if current - step > target then current = current - step else current = target; st.done = true end
    end
    apply()
    if st.done then task.alive = false else rate = rate + accel end
  end)
  return st
end

-- Bg_SetOffset on an affine layer resets its matrix to identity about (0, 0)
local function setOffset(layer, x, y)
  layer.ox, layer.oy = x or layer.ox, y or layer.oy
  if layer.affine then layer.scale, layer.cx, layer.cy = 4096, 0, 0 end
end

local function newLayer(key, affine)
  return { key = key, ox = 0, oy = 0, scale = 4096, cx = 0, cy = 0, affine = affine, visible = true }
end

-- ONE QUAD PER PICTURE, re-aimed each draw rather than made anew: a fresh
-- Quad for every layer of every frame is tens of thousands of GPU-side objects
-- left to the collector over one trade
function Screen:quad(img, x, y, w, h)
  self.quadFor = self.quadFor or {}
  local q = self.quadFor[img]
  if not q then
    q = love.graphics.newQuad(x, y, w, h, img:getWidth(), img:getHeight())
    self.quadFor[img] = q
  else
    q:setViewport(x, y, w, h, img:getWidth(), img:getHeight())
  end
  return q
end

-- an affine BG (G2_SetBG2Affine): texture = M * (screen + offset - centre)
-- + centre, the 1024x1024 map repeating (areaOver)
function Screen:drawAffine(layer)
  if not layer.visible then return end
  local img = self:pic(layer.key)
  if not img then return end
  local g = love.graphics
  local k = layer.scale / 4096
  local tx0 = k * (0 + layer.ox - layer.cx) + layer.cx
  local ty0 = k * (0 + layer.oy - layer.cy) + layer.cy
  img:setWrap("repeat", "repeat")
  local q = self:quad(img, tx0, ty0, W * k, H * k)
  g.setColor(1, 1, 1, 1)
  g.draw(img, q, 0, 0, 0, 1 / k, 1 / k)
end

-- a text BG: the map repeats in both directions
function Screen:drawText(layer)
  if not layer.visible then return end
  local img = self:pic(layer.key)
  if not img then return end
  local g = love.graphics
  img:setWrap("repeat", "repeat")
  local q = self:quad(img, layer.ox, layer.oy, W, H)
  g.setColor(1, 1, 1, 1)
  g.draw(img, q, 0, 0)
end

-- BG3 under the tube: every lit colour, white, added at half strength
-- through BG2 (the alpha blend's EVB of 8/16)
function Screen:drawLights(layer, shimmer)
  if not (layer and layer.visible and shimmer and self.blendLights) then return end
  local g = love.graphics
  g.setBlendMode("add", "alphamultiply")
  g.setColor(0.5, 0.5, 0.5, 1)
  for index in pairs(shimmer.lit) do
    local rec = self.art.lights and self.art.lights[index]
    local img = rec and self:cellImage(rec)
    if img then
      img:setWrap("repeat", "repeat")
      g.draw(img, self:quad(img, layer.ox, layer.oy, W, H), 0, 0)
    end
  end
  g.setBlendMode("alpha", "alphamultiply")
  g.setColor(1, 1, 1, 1)
end

-- -------------------------------------------------- the Pokemon pictures --

function Screen:monImage(mon)
  self.monPics = self.monPics or {}
  if not mon then return nil end
  if self.monPics[mon] == nil then
    local ok, path = pcall(function()
      return require("src.pokemon.Sprites").path(self.data, mon.species, "front", { mon = mon })
    end)
    self.monPics[mon] = (ok and image(path)) or false
  end
  return self.monPics[mon] or nil
end

-- BoxPokemon_SpriteYOffset (height.narc), which the import keeps as
-- gen4_species_sprites.species[id].frontOffset
function Screen:monYOffset(mon)
  local rec = mon and ((self.data.gen4_species_sprites or {}).species or {})[tonumber(mon.species)]
  return type(rec) == "table" and tonumber(rec.frontOffset) or 0
end

-- the 80x80 first frame, its top-left at (x, y), mirrored or not
function Screen:drawMonAt(mon, x, y, mirror)
  local img = self:monImage(mon)
  if not img then return end
  local anim = self.monAnims and self.monAnims[mon]
  if anim then
    local okF, frame = pcall(anim.image, anim, mon)
    if okF and frame then img = frame end
  end
  local g = love.graphics
  local w, h = img:getDimensions()
  self.monQuads = self.monQuads or {}
  local q = self.monQuads[img]
  if not q then q = g.newQuad(0, 0, math.min(w, 80), math.min(h, 80), w, h); self.monQuads[img] = q end
  g.setColor(1, 1, 1, 1)
  if mirror then g.draw(img, q, x + 80, y, 0, -1, 1) else g.draw(img, q, x, y) end
end

-- PokemonSpriteManager_CreateSprite(.., 128, y): centred there
function Screen:drawMonCentred(mon)
  self:drawMonAt(mon, 128 - 40, (100 - 20) + self:monYOffset(mon) - 40, false)
end

-- ------------------------------------------------------------ the window --
-- Window 1 at (2, 19), 27 x 4, Window_DrawMessageBox: the engine's own box,
-- printed at once.
function Screen:say(index)
  local TextBox = require("src.render.TextBox")
  local text = Screen.text(self.data, self.art.bank, index, self.buffers)
  local ok, box = pcall(TextBox.new, self.game, text, nil, { stay = {} })
  if not ok then Logger.warn("gen4 trade: text box failed: %s", tostring(box)) self.box = nil return end
  for _ = 1, 600 do
    if box.done then break end
    pcall(box.update, box, 1 / 60)
  end
  self.box = box
end

function Screen:eraseBox() self.box = nil end

-- ----------------------------------------------------------- the phases --

local Phases = {}

-- Run(): the step table, one step a frame; TRUE the frame after the last
local function runSteps(self, phase)
  local steps = phase.steps
  if phase.state <= #steps then
    if steps[phase.state](self, phase) then
      phase.state = phase.state + 1
      phase.sub = 0
    end
    if phase.tick then phase.tick(self, phase) end
    return false
  end
  return true
end

-- the brightness of BG0 (BrightnessAnimState, send / receive): G2_SetBlend-
-- Brightness from `from` to `to` over `frames`, a VBlank task
function Screen:brightnessAnim(phase, from, to, frames)
  local cur, target = from * 4096, to * 4096
  local step = idiv(target - cur, frames)
  local left = frames
  self.bg0 = from
  phase.brightTask = self:task(function(task)
    left = left - 1
    if left > 0 then
      cur = cur + step
      self.bg0 = asr12(cur)
    else
      self.bg0 = to
      task.alive = false
      phase.brightTask = nil
    end
  end)
end

-- 1 ----------------------------------------------------------------- SEND --
Phases[1] = function(self)
  local p = { state = 1, sub = 0, timer = 0 }
  p.steps = {
    -- TradeSendPhase_InitGraphics
    function(s, p)
      s.disp = "SUB_MAIN"
      s.bg0 = 0                                   -- G2_BlendNone
      p.scene = newScene(s)
      p.monVisible = true
      p.model = s:loadModel(p.scene, 0, 147456 + (4294928384 - 4294967296), 245760 + 227328, false)
      p.model.rot = { 0, 0xF000, 0 }
      p.sprites = { newSprite(s, s.art.ball, 128, 100, 2), newSprite(s, s.art.ball, 128, 90, 1) }
      s:startFade(BOTH, "in", "black", 16)
      return true
    end,
    -- TradeSendPhase_RevealSprite: the shadow under where the ball will land
    function(s, p)
      if s:fadeDone() then
        p.sprites[1]:setAnim(1); p.sprites[1].visible = true
        return true
      end
    end,
    -- TradeSendPhase_ShowPokemonInfo
    function(s, p)
      if p.sub == 0 then p.timer = 0; p.sub = 1
      elseif p.sub == 1 then
        p.timer = p.timer + 1
        if p.timer > 10 then
          s:say(0)                                -- pl_msg_00000350_00000
          p.timer = 0; p.sub = 2
        end
      elseif p.sub == 2 then
        p.timer = p.timer + 1
        if p.timer > 60 then
          s:say(1)                                -- "Bye-bye, X!"
          cry(s, s.sending)
          p.timer = 0; p.sub = 3
        end
      elseif p.sub == 3 then
        p.timer = p.timer + 1
        if p.timer > 60 then s:eraseBox(); p.timer = 0; p.sub = 4 end
      elseif p.sub == 4 then
        p.timer = p.timer + 1
        if p.timer > 20 then return true end
      end
    end,
    -- TradeSendPhase_ThrowBall
    function(s, p)
      if p.sub == 0 then
        se(s, "SEQ_SE_DP_KOUKAN01")
        s:brightnessAnim(p, 0, 16, 12)
        p.sub = 1
      elseif p.sub == 1 then
        if not p.brightTask then
          p.monVisible = false
          p.sprites[2]:setAnim(0); p.sprites[2].visible = true
          p.sub = 2
        end
      elseif p.sub == 2 then
        if not p.sprites[2]:isAnimated() then
          p.model.enabled = true
          s:brightnessAnim(p, 16, 0, 16)
          s:ballBounce(p)
          p.sub = 3
        end
      elseif p.sub == 3 then
        if (p.bounce and p.bounce.count >= 2) or p.bounceDone then
          s:startFade(BOTH, "out", "black", 24)
          p.sub = 4
        end
      elseif p.sub == 4 then
        if s:fadeDone() and p.bounceDone then return true end
      end
    end,
  }
  -- the main engine: BG2 the stage (2), the shadow OBJ (2), BG0 the 3D with
  -- the Pokemon (1), the flash OBJ (1), BG1 the window (0); the sub engine's
  -- BG2 is the same stage
  p.draw = function(s, p, engine)
    s:drawText(p.stage)
    if engine ~= "main" then return end
    p.sprites[1]:draw()
    s:draw3D(p, function() if p.monVisible then s:drawMonCentred(s.sending) end end, s.bg0, false)
    p.sprites[2]:draw()
    s:drawBox()
  end
  p.stage = newLayer("stage")
  return p
end

-- BallBounceState (send_phase.c)
function Screen:ballBounce(p)
  local b = { pos = { p.model.pos[1], p.model.pos[2], p.model.pos[3] },
              rot = { p.model.rot[1], p.model.rot[2], p.model.rot[3] },
              vy = 12128, count = 0, spin = 0, settled = false, settle = 0 }
  p.bounce = b
  local s = self
  self:task(function(task)
    if not b.settled then
      b.pos[2] = b.pos[2] + b.vy
      if b.vy >= 0 then
        b.vy = b.vy - 1920
      else
        b.vy = b.vy - 1920
        if b.pos[2] <= -16384 then
          b.pos[2] = -16384
          b.vy = -idiv(b.vy * 44, 100)
          if b.vy < 4000 then b.settled = true end
          se(s, "SEQ_SE_DP_KON")
          b.count = b.count + 1
          if b.count == 1 then b.spin = 176 elseif b.count == 3 then b.spin = b.spin + 80 end
        end
      end
    end
    b.rot[1] = u16(b.rot[1] + b.spin)
    b.rot[3] = u16(b.rot[3] - b.spin)
    p.model.rot = { b.rot[1], b.rot[2], b.rot[3] }
    b.pos[1] = b.pos[1] + b.spin * 5
    b.pos[3] = b.pos[3] + b.spin * 5
    p.model.pos = { b.pos[1], b.pos[2], b.pos[3] }
    if b.settled then
      b.spin = s16(b.spin - 14)
      b.settle = b.settle + 1
      if b.settle > 30 then task.alive = false; p.bounce = nil; p.bounceDone = true end
    end
  end)
end

-- 2 ----------------------------------------------------------------- TUBE --
Phases[2] = function(self)
  local p = { state = 1, sub = 0, timer = 0, swapPending = false }
  p.main2 = newLayer("tube_" .. self.background, true)
  p.sub2 = newLayer("tube_" .. self.background, true)
  p.main3 = newLayer("lights", true)
  p.sub3 = newLayer("lights", true)
  -- TradeTubePhase_New: the screen swap waits from the start
  self:task(function(task)
    if p.swapPending then
      p.swapPending = false
      setOffset(p.main2, nil, -256)
      setOffset(p.sub2, nil, 0)
      p.main3.visible = false
      p.sub3.visible = true
      self.disp = "MAIN_SUB"
      task.alive = false
    end
  end)
  p.steps = {
    -- TradeTubePhase_Setup
    function(s, p)
      s.disp = "SUB_MAIN"
      s.bg0 = 0
      setOffset(p.sub2, nil, -256)
      p.sub3.visible = false
      setOffset(p.main3, nil, 0)
      p.shimmer = s:newShimmer(1)
      p.scale = s:newBgScale({ p.main2, p.sub2 }, 1152, 0x1000, 1, 296, 0)
      -- Init3DScene: edge marking on, the model at (0, -55.5, 0) scaled 1.75,
      -- the camera tilted 60384 about the target
      p.scene = newScene(s)
      p.edge = true
      p.model = s:loadModel(p.scene, 0, -122880 + (0xFFFE6800 - 4294967296), 0, false)
      p.scene:setAngle(60384, 0, 0)
      p.model.scale = 7168
      -- CreateSprites: twenty pairs of sparks scattered by MTRNG
      local rng = newMT(56182737)
      p.sparks = {}
      for i = 1, 20 do
        local x = 12 + (rng() % 232)
        local y = -28 + (rng() % 452)
        local a = newSprite(s, s.art.spark, x, y, 1); a:setAnim(0)
        local b = newSprite(s, s.art.spark, x, y + 56, 1); b:setAnim(1)
        p.sparks[i] = { a, b }
      end
      s:startFade(BOTH, "in", "black", 8)
      return true
    end,
    -- TradeTubePhase_WaitForAnimation
    function(s, p)
      if p.sub == 0 then
        if s:fadeDone() then p.sub = 1 end
      elseif p.scale.done then return true end
    end,
    -- TradeTubePhase_AnimateBall
    function(s, p)
      if p.sub == 0 then p.timer = 0; p.sub = 1
      elseif p.sub == 1 then
        p.timer = p.timer + 1
        if p.timer > 8 then
          s:modelFade(p, p.model, 0, 31, 24)
          p.path = s:ballPath(p)
          p.model.alpha = 0
          p.model.enabled = true
          p.sub = 2
        end
      elseif p.sub == 2 then
        if p.path.midpoint then p.sub = 3 end
      elseif p.sub == 3 then
        if p.path.exited then p.sub = 4 end
      elseif p.sub == 4 then
        p.swapPending = true
        return true
      end
    end,
    -- TradeTubePhase_Exit
    function(s, p)
      if p.sub == 0 then
        s:ballPathReturn(p)
        p.timer = 0; p.sub = 1
      elseif p.sub == 1 then
        p.timer = p.timer + 1
        if p.timer > 2 then
          p.timer = 0
          p.shimmer.stopping = true
          p.sub = 2
        end
      elseif p.sub == 2 then
        if not p.shimmer.alive then s:tubeScroll(p); p.sub = 3 end
      elseif p.sub == 3 then
        if p.timer < 40 then
          p.timer = p.timer + 1
          if p.timer == 40 then se(s, "SEQ_SE_DP_KOUKAN10") end
        end
        if p.path.exited then
          s:startFade(BOTH, "out", "white", 4)
          p.sub = 4
        end
      elseif p.sub == 4 then
        if s:fadeDone() then return true end
      end
    end,
  }
  -- BG3 the lights (3), BG2 the tube (2) with the lights added through it,
  -- the sparks (OBJ 1, main only), BG0 the 3D (0)
  p.draw = function(s, p, engine)
    local l2, l3 = p.main2, p.main3
    if engine == "sub" then l2, l3 = p.sub2, p.sub3 end
    s:drawAffine(l2)
    if p.shimmer and p.shimmer.alive then s:drawLights(l3, p.shimmer) end
    if engine ~= "main" then return end
    for _, pair in ipairs(p.sparks or {}) do pair[1]:draw(); pair[2]:draw() end
    s:draw3D(p, nil, 0, p.edge)
  end
  p.sprites = {}
  return p
end

-- ModelFadeState: the model's polygon alpha from `from` to `to`
function Screen:modelFade(p, model, from, to, frames)
  local cur, target = from * 4096, to * 4096
  local step = idiv(target - cur, frames)
  local left = frames
  model.alpha = from
  local t = self:task(function(task)
    left = left - 1
    if left > 0 then
      cur = cur + step
      model.alpha = asr12(cur)
    else
      model.alpha = to
      task.alive = false
      p.fadeTask = nil
    end
  end)
  p.fadeTask = t
  return t
end

-- BallPathState (tube_phase.c): the ball's spiral up the beam and, after the
-- screens swap, back down it and away
function Screen:ballPath(p)
  local m = p.model
  local b = {
    center = { m.pos[1], m.pos[2], m.pos[3] }, cur = { m.pos[1], m.pos[2], m.pos[3] },
    rot = { m.rot[1], m.rot[2], m.rot[3] }, y = m.pos[2],
    yStep = idiv((-8 * 4096) - m.pos[2], 30), entry = 30, yAccel = 0,
    rx = 0, rz = 0, rxStep = 0, rzStep = 0, trx = 0, trz = 0, orbitFrames = 0,
    angle = 0, speed = 16384, targetSpeed = 0, speedStep = 0, speedFrames = 0,
    axis = { { v = 0, step = 0, target = 0, n = 0 }, { v = 0, step = 0, target = 0, n = 0 },
             { v = 0, step = 0, target = 0, n = 0 } },
    exited = false, midpoint = false,
  }
  local function setSpeed(target, frames)
    if frames ~= 0 then
      b.speedStep = s16(idiv(target - b.speed, frames))
      b.speed = s16(b.speed + b.speedStep)
    else b.speed = s16(target) end
    b.targetSpeed = s16(target); b.speedFrames = frames
  end
  local function setOrbit(tx, tz, frames)
    if frames ~= 0 then
      b.rxStep = idiv(tx - b.rx, frames); b.rzStep = idiv(tz - b.rz, frames)
      b.rx = b.rx + b.rxStep; b.rz = b.rz + b.rzStep
      b.trx, b.trz = tx, tz
    end
    b.orbitFrames = frames
  end
  local function setAxis(i, target, frames)
    local a = b.axis[i]
    if frames ~= 0 then a.step = s16(idiv(target - a.v, frames)) end
    a.target = s16(target); a.n = frames
  end
  b.setOrbit, b.setAxis = setOrbit, setAxis
  -- BallPathState_Tick
  local function tick()
    if b.speedFrames ~= 0 then
      b.speedFrames = b.speedFrames - 1
      if b.speedFrames ~= 0 then b.speed = s16(b.speed + b.speedStep) else b.speed = b.targetSpeed end
    end
    b.angle = s16(b.angle + b.speed)
    local deg = floor(u16(b.angle) / 182)
    if deg >= 360 then deg = deg - 360 end
    if b.orbitFrames ~= 0 then
      b.rx = b.rx + b.rxStep; b.rz = b.rz + b.rzStep
      b.orbitFrames = b.orbitFrames - 1
      if b.orbitFrames == 0 then b.rx, b.rz = b.trx, b.trz end
    end
    b.cur[1] = b.center[1] + fxMul(cosDeg(deg), b.rx)
    b.cur[3] = b.center[3] + fxMul(sinDeg(deg), b.rz)
    b.rot[2] = u16(b.rot[2] + b.speed)
    for _, a in ipairs(b.axis) do
      if a.n ~= 0 then
        a.n = a.n - 1
        if a.n == 0 then a.v = a.target else a.v = s16(a.v + a.step) end
      end
    end
    b.rot[1] = u16(b.rot[1] + b.axis[1].v)
    b.rot[2] = u16(b.rot[2] + b.axis[2].v)
    b.rot[3] = u16(b.rot[3] + b.axis[3].v)
  end
  local function place()
    m.pos = { b.cur[1], b.cur[2], b.cur[3] }
    m.rot = { b.rot[1], b.rot[2], b.rot[3] }
  end
  b.tick, b.place = tick, place
  setSpeed(3328, 30)
  setOrbit(167936, 81920, 30)
  local s = self
  b.mode = "entry"
  b.task = self:task(function(task)
    if b.mode == "entry" then
      if b.entry ~= 0 then
        b.y = b.y + b.yStep
        b.cur[2] = b.y
        b.entry = b.entry - 1
        if b.entry <= 0 then
          b.yAccel = 512
          b.yStep = 0
          setOrbit(0x4000, 0x4000, 60)
          setAxis(1, -0x800, 30)
          b.midpoint = true
          b.mode = "exit"
        end
      end
      tick(); place()
    elseif b.mode == "exit" then
      if not b.exited then
        b.yStep = b.yStep + b.yAccel
        b.y = b.y + b.yStep
        b.cur[2] = b.y
        tick(); place()
        if not s:inView(p.scene) then
          m.enabled = false
          b.exited = true
        end
      end
    elseif b.mode == "approach" then
      tick()
      if b.entry ~= 0 then
        b.y = b.y + b.yStep; b.cur[2] = b.y
        b.entry = b.entry - 1
        if b.entry == 0 then b.mode = "coast" end
      end
      place()
    elseif b.mode == "coast" then
      tick()
      b.entry = b.entry + 1
      if b.entry > 110 then
        b.yStep = idiv(-239616 - b.y, 53)
        b.entry = 53
        b.mode = "final"
      end
      place()
    elseif b.mode == "final" then
      tick()
      if b.entry ~= 0 then
        b.y = b.y + b.yStep; b.cur[2] = b.y
        b.entry = b.entry - 1
        if b.entry == 0 then b.mode = "coast2" end
      end
      place()
    elseif b.mode == "coast2" then
      tick()
      b.entry = b.entry + 1
      if b.entry > 1 then b.yStep = 131072; b.mode = "away" end
      place()
    elseif b.mode == "away" then
      if not b.exited then
        tick()
        b.y = b.y + b.yStep; b.cur[2] = b.y
        place()
        if not s:inView(p.scene) then b.exited = true end
      end
    end
  end)
  return b
end

-- BallPathState_StartReturn: the camera square-on and orthographic, the
-- ball back from below at scale 2
function Screen:ballPathReturn(p)
  local b = p.path
  b.exited = false
  p.scene.projection = 1
  p.scene:setAngle(0, 0, 0)
  b.yStep = idiv(-69632 - (-128 * 4096), 20)
  b.y = -128 * 4096 + b.yStep
  b.entry = 20
  b.cur[2] = b.y
  b.setOrbit(0, 0, 20)
  b.setAxis(2, -b.speed, 30)
  b.setAxis(3, 0x100, 50)
  p.model.scale = 8192
  p.model.enabled = true
  b.mode = "approach"
end

-- TubeBgScrollState and TubeParticleScrollState
function Screen:tubeScroll(p)
  local mainStart = (p.main2.oy or 0) * 4096
  local subStart = (p.sub2.oy or 0) * 4096
  local accel, total = 0, 0
  local particles
  local s = self
  self:task(function(task)
    if total < 512 * 4096 then
      accel = accel + 288
      total = total + accel
      setOffset(p.main2, nil, asr12(mainStart - total))
      setOffset(p.sub2, nil, asr12(subStart - total))
      if total >= 128 * 4096 and not particles then
        particles = { timer = 0, nextIndex = 1, active = {}, pos = {} }
        for i, pair in ipairs(p.sparks) do particles.pos[i] = pair[1].y * 4096 end
        s:task(function()
          particles.timer = particles.timer + 1
          if particles.timer > 12 then
            particles.timer = 0
            if particles.nextIndex <= 20 then
              particles.active[particles.nextIndex] = true
              particles.nextIndex = particles.nextIndex + 1
            end
          end
          for i, pair in ipairs(p.sparks) do
            local y = particles.pos[i] + 135168
            if y >= 424 * 4096 then
              y = -114688 + (y - 1736704)
              if particles.active[i] then pair[1].visible = true; pair[2].visible = true end
            end
            particles.pos[i] = y
            pair[1].y = y / 4096
            pair[2].y = (y + 229376) / 4096
          end
        end)
      end
    end
  end)
end

-- 3 --------------------------------------------------------------- FLY-BY --
Phases[3] = function(self)
  local p = { state = 1, sub = 0, timer = 0, swapPending = false }
  p.main3 = newLayer("sky_" .. self.background)
  p.sub3 = newLayer("sky_" .. self.background)
  p.steps = {
    -- TradeBallFlybyPhase_Setup
    function(s, p)
      s.disp = "SUB_MAIN"
      s.bg0 = 0
      p.main3.oy, p.sub3.oy = 256, 0
      p.scene = newScene(s)
      p.edge = true
      p.model = s:loadModel(p.scene, 0, 0, 0, false)
      p.scene:setAngle(6371, 0, 0)
      p.scene.fov = 2002                       -- ((22 * 0xffff) / 360) / 2
      p.sprite = newSprite(s, s.art.ball, 128, 96, 0)
      p.swapPending = false
      s:task(function(task)
        if p.swapPending then
          p.swapPending = false
          p.scene:adjustAngle(4432)
          p.main3.oy, p.sub3.oy = 0, 256
          s.disp = "MAIN_SUB"
          task.alive = false
        end
      end)
      s:startFade(BOTH, "in", "white", 3)
      return true
    end,
    -- TradeBallFlybyPhase_Animate
    function(s, p)
      if p.sub == 0 then p.timer = 0; p.sub = 1
      elseif p.sub == 1 then
        p.timer = p.timer + 1
        if p.timer > 10 then
          se(s, "SEQ_SE_DP_KOUKAN06")
          s:ballOrbit(p)
          p.model.enabled = true
          p.sub = 2
        end
      elseif p.sub == 2 then
        if p.orbitDone then
          se(s, "SEQ_SE_DP_KOUKAN07")
          p.sprite:setAnim(3); p.sprite.visible = true
          p.sub = 3
        end
      elseif p.sub == 3 then
        if not p.sprite:isAnimated() then
          s:startFade(BOTH, "out", "white", 16)
          p.sub = 4
        end
      elseif p.sub == 4 then
        if s:fadeDone() then return true end
      end
    end,
  }
  -- BG3 the sky (3), BG0 the 3D (0), the twinkle (OBJ 0, over BG0)
  p.draw = function(s, p, engine)
    s:drawText(engine == "main" and p.main3 or p.sub3)
    if engine ~= "main" then return end
    s:draw3D(p, nil, 0, p.edge)
    if p.sprite then p.sprite:draw() end
  end
  p.sprites = {}
  return p
end

-- BallOrbitState (ball_flyby_phase.c)
function Screen:ballOrbit(p)
  local m = p.model
  local o = { center = { 0, 0xFFF50E00 - 4294967296, 925696 }, angle = s16(55408), speed = s16(62800),
              state = 0, timer = 0, frames = 0, rot = { 8192, 0xE000, 0 }, scale = 4096,
              rx = 75776, ry = 101376, n = 0 }
  -- the centre's climb: Platinum's quotient, HeartGold's own literal
  o.yStep = self.hgss and 0x134C4 or idiv(4025344 - (0xFFF50E00 - 4294967296), 60)
  o.zStep = idiv(-1818624 - 925696, 60)
  m.rot = { o.rot[1], o.rot[2], o.rot[3] }
  local function tick()
    local deg = floor(u16(o.angle) / 182)
    if deg >= 360 then deg = deg - 360 end
    o.angle = s16(o.angle + o.speed)
    if o.n ~= 0 then
      o.rx = o.rx + o.rxStep; o.ry = o.ry + o.ryStep
      o.scale = o.scale + o.scaleStep
      m.scale = o.scale
      o.n = o.n - 1
    end
    o.rot[1] = u16(o.rot[1] + 0x300)
    m.rot = { o.rot[1], o.rot[2], o.rot[3] }
    o.cur = { o.center[1] + fxMul(cosDeg(deg), o.rx), o.center[2] + fxMul(sinDeg(deg), o.ry), o.center[3] }
  end
  tick()
  m.pos = { o.cur[1], o.cur[2], o.cur[3] }
  local s = self
  local function move()
    o.center[2] = o.center[2] + o.yStep
    o.center[3] = o.center[3] + o.zStep
    tick()
    m.pos = { o.cur[1], o.cur[2], o.cur[3] }
  end
  self:task(function(task)
    if o.frames < 60 then o.frames = o.frames + 1 end
    if o.state == 0 then
      move()
      if s:inView(p.scene) then o.state = 1 end
    elseif o.state == 1 then
      if not s:inView(p.scene) then
        p.swapPending = true
        o.state = 2
      else move() end
    elseif o.state == 2 then
      move()
      if o.frames >= 60 then
        -- BallOrbitState_SetOrbitRadius(2048, 2048, 512, 12)
        o.rxStep = idiv(2048 - o.rx, 12); o.ryStep = idiv(2048 - o.ry, 12)
        o.scaleStep = idiv(512 - o.scale, 12); o.n = 12
        o.timer = 0
        o.state = 3
      end
    elseif o.state == 3 then
      tick()
      m.pos = { o.cur[1], o.cur[2], o.cur[3] }
      o.timer = o.timer + 1
      if o.timer >= 12 then m.enabled = false; o.timer = 0; o.state = 4 end
    elseif o.state == 4 then
      o.timer = o.timer + 1
      if o.timer > 8 then p.orbitDone = true; task.alive = false end
    end
  end)
end

-- 4 -------------------------------------------------------------- WORMHOLE --
Phases[4] = function(self)
  local p = { state = 1, sub = 0 }
  local function setScroll(s, bg1, bg2)
    bg2 = bg2 % 512
    bg1 = bg1 % 512
    p.mainBg2, p.mainBg1, p.subBg1 = bg2, bg1, bg1 + 192
  end
  p.steps = {
    function(s, p)
      s.disp = "MAIN_SUB"
      s.bg0 = 0
      -- TradeSequence_LoadPokemonPlatform: the receiving Pokemon is mirrored
      -- when its species' flip bit is clear (DoesMonSpeciesFlipsSprite)
      local def = s.receiving and (s.data.pokemon or {})[s.receiving.species]
      local flip = not (def and def.flipSprite)
      local plat = s.art.platforms or {}
      p.sendMirror = plat[0] and plat[0].mirror or false
      p.receiveMirror = (flip and plat[1] or plat[0] or {}).mirror or false
      -- (the first call passes the two start values the wrong way round;
      -- the scroll task puts them right a frame later)
      setScroll(s, 80, -384)
      s:startFade(BOTH, "in", "white", 8)
      return true
    end,
    function(s, p)
      if p.sub == 0 then
        if s:fadeDone() then
          local b1, b2 = -384 * 4096, 80 * 4096
          local st1 = idiv((-48 - -384) * 4096, 60)
          local st2 = idiv((-48 - 80) * 4096, 60)
          local left = 60
          p.scrollDone = false
          s:task(function(task)
            if left ~= 0 then
              left = left - 1
              b1 = b1 + st1; b2 = b2 + st2
              setScroll(s, asr12(b1), asr12(b2))
            else
              setScroll(s, -48, -48)
              p.scrollDone = true
              task.alive = false
            end
          end)
          p.sub = 1
        end
      elseif p.sub == 1 then
        if p.scrollDone then
          se(s, "SEQ_SE_DP_KOUKAN03")
          s:startFade(BOTH, "out", "white", 16)
          p.sub = 2
        end
      elseif p.sub == 2 then
        if s:fadeDone() then return true end
      end
    end,
  }
  -- BG3 the wormhole (3), BG2 the received Pokemon at tile (2, 0) (main
  -- only), BG1 the one sent at tile (20, 0); a 256x512 map, so each picture
  -- shows wherever its row lands mod 512
  p.draw = function(s, p, engine)
    local img = s:pic("wormhole")
    if img then love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(img, 0, 0) end
    local function at(mon, x, offset, mirror)
      local y = (-offset) % 512
      s:drawMonAt(mon, x, y, mirror)
      s:drawMonAt(mon, x, y - 512, mirror)
    end
    if engine == "main" then
      at(s.receiving, 16, p.mainBg2, p.receiveMirror)
      at(s.sending, 160, p.mainBg1, p.sendMirror)
    else
      at(s.sending, 160, p.subBg1, p.sendMirror)
    end
  end
  p.sprites = {}
  return p
end

-- 5 --------------------------------------------------------------- ARRIVAL --
Phases[5] = function(self)
  local p = { state = 1, sub = 0, swapPending = false }
  p.main3 = newLayer("sky_" .. self.background)
  p.sub3 = newLayer("sky_" .. self.background)
  p.steps = {
    function(s, p)
      s.disp = "MAIN_SUB"
      s.bg0 = 0
      p.main3.oy, p.sub3.oy = 0, 256
      p.scene = newScene(s)
      p.edge = true
      p.model = s:loadModel(p.scene, 0, 0, 0, false)
      p.scene:setAngle(0x18E3, 0, 0)
      p.scene:adjustAngle(0x1150)
      p.scene.fov = 2002
      p.sprite = newSprite(s, s.art.ball, 128, 96, 1)
      s:startFade(BOTH, "in", "white", 8)
      return true
    end,
    function(s, p)
      if p.sub == 0 then
        if s:fadeDone() then p.sprite:setAnim(3); p.sprite.visible = true; p.sub = 1 end
      elseif p.sub == 1 then
        if not p.sprite:isAnimated() then
          se(s, "SEQ_SE_DP_KOUKAN05")
          s:ballArrival(p)
          p.model.enabled = true
          p.sub = 2
        end
      elseif p.sub == 2 then
        if p.arrivalDone then s:startFade(BOTH, "out", "white", 16); p.sub = 3 end
      elseif p.sub == 3 then
        if s:fadeDone() then return true end
      end
    end,
  }
  -- ReceiveBall_VBlankCallback: the swap back when the ball leaves the top
  p.vblank = function(s, p)
    if p.swapPending then
      p.scene:adjustAngle(-0x1150)
      p.main3.oy, p.sub3.oy = 256, 0
      s.disp = "SUB_MAIN"
      p.swapPending = false
    end
  end
  -- BG3 the sky (3), the twinkle (OBJ 1), BG0 the 3D (0)
  p.draw = function(s, p, engine)
    s:drawText(engine == "main" and p.main3 or p.sub3)
    if engine ~= "main" then return end
    if p.sprite then p.sprite:draw() end
    s:draw3D(p, nil, 0, p.edge)
  end
  p.sprites = {}
  return p
end

-- BallArrivalPathState (receive_ball_phase.c)
function Screen:ballArrival(p)
  local m = p.model
  local o = { center = { 0, 4025344, 0xFFE44000 - 4294967296 }, angle = s16(55408), speed = s16(62800),
              sub = 0, exit = 0, frames = 0, rot = { 8192, 0xE000, 0 }, scale = 512,
              rx = 2048, ry = 2048, n = 0 }
  o.yStep = idiv((0xFFF3CE00 - 4294967296) - 4025344, 70)
  -- BALL_INITIAL_ORBIT_CENTER_Z is an unsigned literal, so the quotient is
  -- taken over the wrapped difference (0x936D in HeartGold's pool)
  o.zStep = idiv(823296 - (0xFFE44000 - 4294967296), 70)
  m.rot = { o.rot[1], o.rot[2], o.rot[3] }
  -- BeginTransition(75776, 101376, FX32_ONE, 12)
  o.rxStep = idiv(75776 - o.rx, 12); o.ryStep = idiv(101376 - o.ry, 12)
  o.scaleStep = idiv(4096 - o.scale, 12)
  o.trx, o.try, o.tscale, o.n = 75776, 101376, 4096, 12
  local function tick()
    local deg = floor(u16(o.angle) / 182)
    if deg >= 360 then deg = deg - 360 end
    o.angle = s16(o.angle - o.speed)
    if o.n ~= 0 then
      o.n = o.n - 1
      if o.n ~= 0 then
        o.rx = o.rx + o.rxStep; o.ry = o.ry + o.ryStep; o.scale = o.scale + o.scaleStep
      else
        o.rx, o.ry, o.scale = o.trx, o.try, o.tscale
      end
      m.scale = o.scale
    end
    o.rot[1] = u16(o.rot[1] - 0x300)
    m.rot = { o.rot[1], o.rot[2], o.rot[3] }
    o.cur = { o.center[1] + fxMul(cosDeg(deg), o.rx), o.center[2] + fxMul(sinDeg(deg), o.ry), o.center[3] }
  end
  tick()
  m.pos = { o.cur[1], o.cur[2], o.cur[3] }
  local s = self
  self:task(function(task)
    if o.frames < 70 then o.frames = o.frames + 1 end
    if o.sub == 0 then
      tick(); m.pos = { o.cur[1], o.cur[2], o.cur[3] }
      o.frames = o.frames + 1
      if o.frames >= 12 then o.frames = 0; o.sub = 1 end
    elseif o.sub == 1 then
      if not s:inView(p.scene) then
        p.swapPending = true
        o.sub = 2
      else
        o.center[2] = o.center[2] + o.yStep; o.center[3] = o.center[3] + o.zStep
        tick(); m.pos = { o.cur[1], o.cur[2], o.cur[3] }
      end
    elseif o.sub == 2 then
      o.center[2] = o.center[2] + o.yStep; o.center[3] = o.center[3] + o.zStep
      tick(); m.pos = { o.cur[1], o.cur[2], o.cur[3] }
      if o.frames >= 70 then m.enabled = false; o.exit = 0; o.sub = 3 end
    elseif o.sub == 3 then
      o.exit = o.exit + 1
      if o.exit > 8 then p.arrivalDone = true; task.alive = false end
    end
  end)
end

-- 6 ---------------------------------------------------------------- REVEAL --
Phases[6] = function(self)
  local p = { state = 1, sub = 0, timer = 0 }
  p.main2 = newLayer("reveal_" .. self.background, true)
  p.sub2 = newLayer("reveal_" .. self.background, true)
  p.main3 = newLayer("lights", true)
  p.steps = {
    function(s, p)
      s.disp = "MAIN_SUB"
      s.bg0 = 0
      s.blendLights = false
      setOffset(p.main2, nil, -384)
      setOffset(p.sub2, nil, -192)
      setOffset(p.main3, nil, 67)
      p.scene = newScene(s)
      p.edge = true
      p.model = s:loadModel(p.scene, 0, 140 * 4096, 0, true)
      p.scene:setAngle(0, 0, 0)
      p.scene.projection = 1
      p.model.scale = 0x2000
      p.modelRot = { 0, 0, 0 }
      s:startFade(BOTH, "in", "white", 8)
      return true
    end,
    function(s, p)
      if p.sub == 0 then
        if s:fadeDone() then
          p.timer = 0
          -- ModelSlideState: down to 204800 over 16 frames
          local m = p.model
          local y = m.pos[2]
          local step = idiv(204800 - y, 16)
          local left = 16
          p.slide = s:task(function(task)
            if left ~= 0 then
              y = y + step
              m.pos = { m.pos[1], y, m.pos[3] }
              left = left - 1
            else
              m.pos = { m.pos[1], 204800, m.pos[3] }
              task.alive = false
              p.slide = nil
            end
          end)
          p.sub = 1
        end
      elseif p.sub == 1 then
        p.timer = p.timer + 1
        if p.timer > 8 then
          -- BgSlideState: BG2 down 384 pixels over 40 frames
          local mainY, subY = -384 * 4096, -192 * 4096
          local step = idiv(384 * 4096, 40)
          local left = 40
          p.bgSlide = s:task(function(task)
            if left ~= 0 then
              mainY = mainY + step; subY = subY + step
              setOffset(p.main2, nil, asr12(mainY))
              setOffset(p.sub2, nil, asr12(subY))
              left = left - 1
            else
              setOffset(p.main2, nil, 0)
              setOffset(p.sub2, nil, 192)
              task.alive = false
              p.bgSlide = nil
            end
          end)
          p.sub = 2
        end
      elseif p.sub == 2 then
        if not p.bgSlide and not p.slide then p.sub = 3 end
      elseif p.sub == 3 then
        p.shimmer = s:newShimmer(-1)
        p.timer = 0
        p.sub = 4
      elseif p.sub == 4 then
        p.timer = p.timer + 1
        if p.timer > 30 then s:modelFade(p, p.model, 31, 0, 40); p.sub = 5 end
      elseif p.sub == 5 then
        if not p.fadeTask then p.shimmer.stopping = true; p.sub = 6 end
      elseif p.sub == 6 then
        if not p.shimmer.alive then return true end
      end
    end,
    function(s, p)
      if p.sub == 0 then
        p.scale = s:newBgScale({ p.main2, p.sub2 }, 0x1000, 1024, 1, 296, 1)
        p.timer = 0
        p.sub = 1
      elseif p.sub == 1 then
        p.timer = p.timer + 1
        if p.timer > 13 then s:startFade(BOTH, "out", "black", 8); p.sub = 2 end
      elseif p.sub == 2 then
        if s:fadeDone() and p.scale.done then return true end
      end
    end,
  }
  -- TradePokemonRevealPhase_Tick: the ball turns 0x1000 a frame
  p.tick = function(s, p)
    if p.scene then
      p.modelRot[2] = u16(p.modelRot[2] + 0x1000)
      p.model.rot = { p.modelRot[1], p.modelRot[2], p.modelRot[3] }
    end
  end
  p.draw = function(s, p, engine)
    if engine == "main" then
      s:drawAffine(p.main2)
      if p.shimmer and p.shimmer.alive then s:drawLights(p.main3, p.shimmer) end
      s:draw3D(p, nil, 0, p.edge)
    else
      s:drawAffine(p.sub2)
    end
  end
  p.sprites = {}
  return p
end

-- 7 --------------------------------------------------------------- RECEIVE --
Phases[7] = function(self)
  local p = { state = 1, sub = 0, timer = 0 }
  p.stage = newLayer("stage")
  p.steps = {
    -- TradeReceivePhase_InitGraphics
    function(s, p)
      s.disp = "MAIN_SUB"
      s.bg0 = 0
      p.subBlack = true                      -- the sub engine is not set up
      p.scene = newScene(s)
      p.monVisible = false
      p.model = s:loadModel(p.scene, 0, 77824, 491520, false)
      p.model.rot = { 0, 0xF000, 0 }
      p.sprites = { newSprite(s, s.art.ball, 128, 100, 2), newSprite(s, s.art.ball, 128, 90, 1) }
      s:startFade(MAIN, "in", "black", 16)
      return true
    end,
    function(s, p)
      if s:fadeDone() then
        p.sprites[1]:setAnim(1); p.sprites[1].visible = true
        return true
      end
    end,
    -- TradeReceivePhase_RevealPokemon
    function(s, p)
      if p.sub == 0 then
        s:ballOpen(p)
        p.sub = 1
      end
      if p.sub == 1 then
        if not p.open then
          p.sprites[2]:setAnim(2); p.sprites[2].visible = true
          p.model.enabled = false
          p.timer = 0
          p.sub = 2
        end
      elseif p.sub == 2 then
        p.timer = p.timer + 1
        if p.timer > 10 then
          p.monVisible = true
          s:brightnessAnim(p, 16, 0, 12)
          p.sub = 3
        end
      elseif p.sub == 3 then
        if not p.brightTask then
          cry(s, s.receiving)
          p.timer = 0
          p.sub = 4
        end
      elseif p.sub == 4 then
        p.timer = p.timer + 1
        if p.timer > 30 then return true end
      end
    end,
    -- TradeReceivePhase_ShowMessage
    function(s, p)
      local function waited(target)
        if p.fanfare then p.fanfare = s:fanfarePlaying() end
        if p.timer < target then p.timer = p.timer + 1 return false end
        return not p.fanfare
      end
      if p.sub == 0 then p.timer = 0; p.sub = 1
      elseif p.sub == 1 then
        p.timer = p.timer + 1
        if p.timer > 10 then
          s:say(2)                                -- "Y sent over X."
          s:playFanfare()
          p.timer = 0
          p.fanfare = true
          p.sub = 2
        end
      elseif p.sub == 2 then
        if waited(60) then s:say(3); p.timer = 0; p.sub = 3 end
      elseif p.sub == 3 then
        if waited(60) then s:eraseBox(); p.timer = 0; p.sub = 4 end
      elseif p.sub == 4 then
        p.timer = p.timer + 1
        if p.timer > 10 then s:startFade(MAIN, "out", "black", 16); p.sub = 5 end
      elseif p.sub == 5 then
        if s:fadeDone() then return true end
      end
    end,
  }
  p.draw = function(s, p, engine)
    if engine ~= "main" then return end
    s:drawText(p.stage)
    p.sprites[1]:draw()
    s:draw3D(p, function() if p.monVisible then s:drawMonCentred(s.receiving) end end, s.bg0, false)
    p.sprites[2]:draw()
    s:drawBox()
  end
  return p
end

-- BallOpenState (receive_phase.c)
function Screen:ballOpen(p)
  local m = p.model
  local o = { sub = 0, timer = 0, alpha = 0, alphaStep = idiv(31 * 4096, 20), alphaFrames = 20,
              speed = 4096, rotFrames = 0, pos = { m.pos[1], m.pos[2], m.pos[3] },
              rot = { m.rot[1], m.rot[2], m.rot[3] }, vy = 0 }
  m.alpha = 0
  m.enabled = true
  p.open = o
  local s = self
  self:task(function(task)
    -- BallOpenState_UpdateRotation
    if o.rotFrames ~= 0 then
      o.speed = s16(o.speed + o.speedStep)
      o.rotFrames = o.rotFrames - 1
      if o.rotFrames == 0 then o.speed = o.target end
    end
    o.rot[2] = u16(o.rot[2] + o.speed)
    m.rot = { o.rot[1], o.rot[2], o.rot[3] }
    if o.sub == 0 then
      if o.alphaFrames ~= 0 then
        o.alpha = o.alpha + o.alphaStep
        o.alphaFrames = o.alphaFrames - 1
        m.alpha = asr12(o.alpha)
      else
        m.alpha = 31
        o.sub = 1
      end
    elseif o.sub == 1 then
      o.speedStep = s16(idiv(384 - o.speed, 30)); o.rotFrames = 30; o.target = 384
      o.timer = 0
      o.sub = 2
    elseif o.sub == 2 then
      o.timer = o.timer + 1
      if o.timer > 10 then o.vy = 0; o.sub = 3 end
    elseif o.sub == 3 then
      o.pos[2] = o.pos[2] + o.vy
      o.vy = o.vy - 1920
      m.pos = { o.pos[1], o.pos[2], o.pos[3] }
      if o.pos[2] < (0xFFFF5000 - 4294967296) then
        se(s, "SEQ_SE_DP_KON")
        o.vy = -o.vy
        s:brightnessAnim(p, 0, 16, 8)
        o.sub = 4
      end
    elseif o.sub == 4 then
      o.pos[2] = o.pos[2] + o.vy
      if o.pos[2] >= 77824 then o.pos[2] = 77824 end
      m.pos = { o.pos[1], o.pos[2], o.pos[3] }
      if o.pos[2] == 77824 then o.sub = 5 end
    elseif o.sub == 5 then
      if not p.brightTask then task.alive = false; p.open = nil end
    end
  end)
end

function Screen:playFanfare()
  local okM, Music = pcall(require, "src.core.Music")
  if okM and Music.playOnce then pcall(Music.playOnce, self.data, self.art.fanfare or "SEQ_FANFA5") end
end

-- Sound_IsBGMPausedByFanfare
function Screen:fanfarePlaying()
  local okM, Music = pcall(require, "src.core.Music")
  if okM and Music.oneShotPlaying then
    local ok, v = pcall(Music.oneShotPlaying)
    return ok and v and true or false
  end
  return false
end

-- ------------------------------------------------------------- the frame --

-- THE SCREEN'S OWN CANVASES GO BACK EXPLICITLY when it ends: five render
-- targets (two engines, a layer, the 3D colour and depth) otherwise wait for
-- the collector, which may get to them only as the program closes
function Screen:releaseTargets()
  for _, c in pairs(self.canvases or {}) do pcall(c.release, c) end
  if self.colour3d then pcall(self.colour3d.release, self.colour3d) end
  if self.depth3d then pcall(self.depth3d.release, self.depth3d) end
  for _, q in pairs(self.quadFor or {}) do pcall(q.release, q) end
  self.canvases, self.colour3d, self.depth3d, self.quadFor = nil, nil, nil, nil
  self.released = true
end

function Screen:finish()
  if self.finished then return end
  self.finished = true
  self:releaseTargets()
  local okM, Music = pcall(require, "src.core.Music")
  if okM and Music.restoreMap then pcall(Music.restoreMap, self.data) end
  if self.game and self.game.stack and self.game.stack.top and self.game.stack:top() == self then
    self.game.stack:pop()
  end
  if self.onDone then self.onDone() end
end

function Screen:update()
  if self.unavailable then return self:finish() end
  self.frame = self.frame + 1
  for _, anim in pairs(self.monAnims or {}) do pcall(anim.update, anim, 1 / 60) end
  -- TradeSequence_Main
  if self.phaseIndex <= #Phases then
    if not self.phase then
      self.tasks = self.tasks or {}
      self.phase = Phases[self.phaseIndex](self)
    end
    if runSteps(self, self.phase) then
      self:freePhase()
      self.phaseIndex = self.phaseIndex + 1
    end
  else
    return self:finish()
  end
  -- the frame's tasks, then the VBlank callback's sprite update
  self:runTasks()
  if self.phase and self.phase.vblank then self.phase.vblank(self, self.phase) end
  if self.phase then
    for _, sp in ipairs(self.phase.sprites or {}) do sp:tick() end
    if self.phase.sprite then self.phase.sprite:tick() end
    for _, pair in ipairs(self.phase.sparks or {}) do pair[1]:tick(); pair[2]:tick() end
  end
  self:tickFade()
end

-- a phase's Free: its tasks stop, its window goes
function Screen:freePhase()
  for _, t in ipairs(self.tasks) do t.alive = false end
  self.tasks = {}
  self.box = nil
  self.blendLights = false
  self.phase = nil
end

-- --------------------------------------------------------------- drawing --

function Screen:targets()
  if self.canvases then return true end
  local g = love.graphics
  self.canvases = { main = g.newCanvas(W, H), sub = g.newCanvas(W, H), layer = g.newCanvas(W, H) }
  for _, c in pairs(self.canvases) do c:setFilter("nearest", "nearest") end
  self.colour3d, self.depth3d = Gen4Model.newTarget(W, H)
  return true
end

-- BG0: the Pokemon (a software sprite) and the 3D scene, brightened toward
-- white by `bright` sixteenths, edge-marked or not
function Screen:draw3D(p, drawMon, bright, edge)
  local g = love.graphics
  if not self.colour3d then
    if drawMon then drawMon() end
    return
  end
  -- push("all")/pop restores the bound canvas: setCanvas(getCanvas()) drops
  -- (or chokes on) a depth set a mod has bound around the screen
  g.push("all")
  g.setCanvas({ self.colour3d, depthstencil = self.depth3d })
  g.clear(0, 0, 0, 0, true, true)
  if drawMon then drawMon() end
  local m = p.scene and p.scene.model
  if m and m.enabled and m.alpha > 0 then
    self.ballModel = self.ballModel or Screen.ballFor(self.art.model) or false
    if self.ballModel then
      local vp = p.scene:viewProjection()
      if m.alpha < 31 then Gen4Model.drawTint = { 1, 1, 1, m.alpha / 31 } end
      pcall(self.ballModel.draw, self.ballModel, multiply(vp, modelMatrix(m)))
      Gen4Model.drawTint = nil
    end
  end
  g.pop()
  drawLayer(self.colour3d, bright or 0, edge and (not m or m.alpha >= 31))
end

-- the Poke Ball's meshes, built once per art record and kept for the next
-- trade rather than left to the collector with every screen
local ballCache = setmetatable({}, { __mode = "k" })
function Screen.ballFor(record)
  if type(record) ~= "table" then return nil end
  if ballCache[record] == nil then
    local ok, m = pcall(Gen4Model.new, record)
    ballCache[record] = ok and m or false
  end
  return ballCache[record] or nil
end

function Screen:drawBox()
  if self.box then pcall(self.box.draw, self.box) end
end

function Screen:renderEngine(engine)
  local g = love.graphics
  local canvas = self.canvases[engine]
  g.setCanvas(canvas)
  g.clear(0, 0, 0, 1)
  local p = self.phase
  if p and p.draw and not (engine == "sub" and p.subBlack) then p.draw(self, p, engine) end
  g.setCanvas()
end

-- which engine the top screen shows
function Screen:topEngine()
  return self.disp == "MAIN_SUB" and "main" or "sub"
end

function Screen:draw()
  local g = love.graphics
  if self.unavailable or self.released or not self:targets() then
    g.setColor(0, 0, 0, 1); g.rectangle("fill", 0, 0, W, H)
    return
  end
  g.push("all")
  g.origin()
  g.setScissor()
  self:renderEngine("main")
  self:renderEngine("sub")
  g.pop()

  local SS = require("src.ui.SecondScreen")
  local dual = SS.mode and SS.mode(self.game) ~= "off" and SS.draw
  local top = dual and self:topEngine() or "main"
  local bottom = top == "main" and "sub" or "main"
  g.setColor(1, 1, 1, 1)
  drawLayer(self.canvases[top], self.bright[top], false)
  if dual then
    SS.draw(self.game, function()
      g.setColor(1, 1, 1, 1)
      drawLayer(self.canvases[bottom], self.bright[bottom], false)
    end)
  end
end

-- for the harness: which phase, which step
function Screen:describe()
  local p = self.phase
  return ("phase %d step %s sub %s disp %s"):format(self.phaseIndex, tostring(p and p.state),
    tostring(p and p.sub), self.disp)
end

Screen.PHASE_NAMES = { "send", "tube", "flyby", "wormhole", "arrival", "reveal", "receive" }

return Screen
