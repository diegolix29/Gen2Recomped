-- tools/trailer/capture.lua -- TRAILER FOOTAGE, recorded from the real game.
--
-- A POKEPORT_DRIVER script: it plays scripted shots (walks through towns, day
-- and night, battles, the voxel diorama, first and third person, Platinum on
-- the cartridge camera, single screen) and streams every other rendered frame
-- into ffmpeg, so each shot comes out as one 30 fps MP4:
--
--   <OUT>/<version>_<shot>.mp4
--
-- One run records the shots for ONE game (POKEPORT_VERSION). Every Gen 2 and
-- Gen 3 shot is recorded with DramaticShapes' voxel diorama ON, except the
-- "voxel_reveal" shot that starts flat and switches the voxels on mid-walk.
-- tools/trailer/capture_all.ps1 runs every game.
--
-- CAMERA CRAFT: strolls keep to open ground (no tree line between the lens
-- and the player), voxel cameras settle before the first frame, and first /
-- third person steer the free camera's look along a planned path, easing
-- through each corner, so the view turns the way the player walks.
--
-- SMOOTH FOOTAGE ON A SLOW RUN: the logic steps a fixed 1/60 per frame, the
-- wall clock (love.timer.getTime, which water and shaders animate from) is
-- replaced by a frame clock, and encoding happens off the main thread in
-- ffmpeg. The window may crawl while recording; the video does not.
--
-- Env: OUT (required), FFMPEG (path, default "ffmpeg"), CRF (default 14),
-- FORMAT (mp4 | png), VOXEL (level, default 4), WIDTH/HEIGHT (default
-- 1920x1080), ONLY (comma list of shot names), FPS_STEP (default 2 = 30 fps),
-- WRITERS (PNG threads when FORMAT=png, default 4).

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local OUT = assert(os.getenv("OUT"), "set OUT to the footage folder")
  local VOX = tonumber(os.getenv("VOXEL") or "4") or 4
  local STEP = tonumber(os.getenv("FPS_STEP") or "2") or 2
  local ONLY = {}
  for name in (os.getenv("ONLY") or ""):gmatch("[^,]+") do ONLY[name] = true end
  local GameVersion = require("src.core.GameVersion")
  local version = GameVersion.get()
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  -- a 1080p window, so the frames are trailer-sized
  local W, H = tonumber(os.getenv("WIDTH") or "1920"), tonumber(os.getenv("HEIGHT") or "1080")
  pcall(love.window.setMode, W, H, { resizable = true, vsync = 0 })
  U.wait(10)

  -- THE CLOCK: Gen 2's day and night come from the wall clock, so a shot pins
  -- the hour by answering os.date("%H") itself
  local realDate = os.date
  local pinnedHour = nil
  os.date = function(fmt, t)
    if pinnedHour and fmt == "%H" then return ("%02d"):format(pinnedHour) end
    if pinnedHour and fmt == "*t" then
      local r = realDate("*t", t); r.hour = pinnedHour; return r
    end
    return realDate(fmt, t)
  end

  -- THE FRAME CLOCK: one 1/60 tick per logic step, whatever the wall says
  local realGetTime = love.timer.getTime
  local clock = realGetTime()
  local realUpdate = love.update
  love.update = function(dt) clock = clock + 1 / 60; return realUpdate(dt) end
  love.timer.getTime = function() return clock end

  -- THE WRITER: captureScreenshot hands the frame to a channel and ONE worker
  -- thread streams it, raw RGBA, into an ffmpeg process per shot -- an MP4
  -- comes out, no PNGs touch the disk, and ffmpeg's own threads do the
  -- encoding. FORMAT=png keeps the old image-sequence output instead.
  local FORMAT = os.getenv("FORMAT") or "mp4"
  local FFMPEG = os.getenv("FFMPEG") or "ffmpeg"
  local CRF = os.getenv("CRF") or "14"
  local WRITER = [[
    local ch, format, ffmpeg, crf, fps = ...
    require("love.image")
    local pipe, current
    local function close()
      if pipe then pipe:close(); pipe = nil end
      current = nil
    end
    while true do
      local job = ch:demand()
      if job == "stop" then close(); return end
      if format == "png" then
        local fd = job.img:encode("png")
        local f = io.open(("%s/%05d.png"):format(job.dir, job.n), "wb")
        if f then f:write(fd:getString()); f:close() end
      else
        if job.dir ~= current then
          close()
          local w, h = job.img:getDimensions()
          local cmd = ('"%s" -y -loglevel error -f rawvideo -pix_fmt rgba -s %dx%d -r %d -i - '
            .. '-c:v libx264 -preset slow -crf %s -pix_fmt yuv420p -movflags +faststart "%s.mp4"')
            :format(ffmpeg, w, h, fps, crf, job.dir)
          if package.config:sub(1, 1) == "\\" then cmd = '"' .. cmd .. '"' end
          pipe = io.popen(cmd, "wb")
          current = job.dir
        end
        if pipe then pipe:write(job.img:getString()) end
      end
      job.img:release()
    end
  ]]
  local queue = love.thread.getChannel("trailer_frames")
  local writers = {}
  for i = 1, (FORMAT == "png") and (tonumber(os.getenv("WRITERS") or "4") or 4) or 1 do
    writers[i] = love.thread.newThread(WRITER)
    writers[i]:start(queue, FORMAT, FFMPEG, CRF, math.floor(60 / STEP))
  end
  local function capture(dir, n)
    -- back-pressure: 1080p frames are 8 MB each in the queue
    while queue:getCount() > 24 do realGetTime(); love.timer.sleep(0.004) end
    love.graphics.captureScreenshot(function(img) queue:push({ dir = dir, n = n, img = img }) end)
  end

  -- the fit zoom, not whatever survey zoom the player's options hold
  local Zoom = require("src.render.Zoom")

  -- the save: a fresh one with the player's own options kept
  local kept = game.save and game.save.options
  U.freshSave(game)
  if kept then game.save.options = kept end
  game.save.options.zoom = 0
  Zoom.offset = 0
  game.save.player.name = (version == "platinum") and "LUCAS" or "GOLD"

  local function speciesByName(name)
    for id, def in pairs(game.data.pokemon or {}) do
      if type(def) == "table" and type(def.name) == "string" and def.name:upper() == name then return id end
    end
    return nil
  end
  local function mon(name, level)
    local id = speciesByName(name)
    return id and Pokemon.new(game.data, id, level) or nil
  end
  local party = {}
  for _, pick in ipairs({ { "TYPHLOSION", 40 }, { "CHARIZARD", 42 }, { "INFERNAPE", 40 }, { "PIKACHU", 30 } }) do
    local m = mon(pick[1], pick[2])
    if m then party[#party + 1] = m end
    if #party >= 2 then break end
  end
  game.save.party = party

  -- where a shot goes: <OUT>/<version>_<shot>.mp4, or a folder of PNGs
  local function newShotDir(shot)
    local dir = OUT .. "/" .. version .. "_" .. shot
    if FORMAT == "png" then
      if love._os == "Windows" then os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
      else os.execute('mkdir -p "' .. dir .. '"') end
    end
    return dir
  end

  -- one frame of footage every STEP frames
  local function record(shot, frames)
    local dir = newShotDir(shot)
    local n = 0
    for f = 1, frames do
      if f % STEP == 0 then
        n = n + 1
        capture(dir, n)
      end
      coroutine.yield()
    end
    U.log(("recorded %s: %d frames -> %s"):format(shot, n, dir))
  end

  -- OPEN GROUND: the diorama camera looks north from the south, so whatever
  -- stands in the rows just below the player (a tree line, a roof) stands
  -- between it and the lens. A cell is open when that strip is walkable.
  local function openScore(cx, cy)
    local map = game.overworld and game.overworld.map
    if not map then return 9 end
    local n = 0
    for dy = 1, 3 do
      for dx = -1, 1 do
        local x, y = cx + dx, cy + dy
        if map:inBounds(x, y) and map:isWalkableCell(x, y) then n = n + 1 end
      end
    end
    return n
  end
  local strict = 7          -- openScore a walked cell needs; 0 = anywhere
  -- the nearest cell the player can stand on, from the map's middle outwards
  local function standable(mapId, x, y)
    U.teleport(game, mapId, x, y, "down")
    local ow = game.overworld
    local map = ow and ow.map
    if not (map and map.isWalkableCell) then return x, y end
    if map:isWalkableCell(x, y) then return x, y end
    for r = 1, 24 do
      for dy = -r, r do
        for dx = -r, r do
          if math.abs(dx) == r or math.abs(dy) == r then
            local cx, cy = x + dx, y + dy
            if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy) then return cx, cy end
          end
        end
      end
    end
    return x, y
  end
  local function goTo(mapId, x, y, facing)
    if not game.data.maps[mapId] then U.log("no map " .. tostring(mapId)); return false end
    local m = game.data.maps[mapId]
    x = x or math.floor((m.width or 20) / 2)
    y = y or math.floor((m.height or 18) / 2)
    local sx, sy = standable(mapId, x, y)
    -- then the nearest cell with open ground in front of the camera
    local map = game.overworld and game.overworld.map
    if map then
      local best, bestD
      for dy = -14, 14 do
        for dx = -14, 14 do
          local cx, cy = sx + dx, sy + dy
          if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy) and openScore(cx, cy) >= 9 then
            local d = math.abs(dx) + math.abs(dy)
            if not bestD or d < bestD then best, bestD = { cx, cy }, d end
          end
        end
      end
      if best then sx, sy = best[1], best[2] end
    end
    U.teleport(game, mapId, sx, sy, facing or "down")
    U.wait(60)
    return true
  end
  -- ------------------------------------------------- walking that knows the map
  --
  -- A breadth-first search over the cells the player can stand on (and that
  -- nobody stands on), so a stroll goes AROUND houses and trees instead of
  -- into them. The tour picks a far cell, then a second leg in another
  -- direction, and walks it one tile at a time, re-planning when something
  -- (a wandering NPC) blocks the way.
  local Pipelines = require("src.render.Pipelines")
  local function voxel(level) pcall(Pipelines.setLevel, "voxel", level) end
  local function tiltshift(level) pcall(Pipelines.setLevel, "tiltshift", level) end
  local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local Collision = require("src.world.Collision")
  local function free(cx, cy)
    local ow = game.overworld
    local map = ow and ow.map
    if not (map and map:inBounds(cx, cy) and map:isWalkableCell(cx, cy)) then return false end
    local okO, occ = pcall(Collision.occupied, ow.entities or ow.npcs or {}, cx, cy, ow.player)
    return not (okO and occ)
  end
  -- strict: 0 anywhere, a number = that much open ground in front, "wide" =
  -- all four neighbours walkable too (a free camera's eye clears the walls)
  local function cellOK(cx, cy)
    if strict == 0 then return true end
    if strict == "wide" then
      local map = game.overworld.map
      for _, v in pairs(DIRS) do
        if not (map:inBounds(cx + v[1], cy + v[2]) and map:isWalkableCell(cx + v[1], cy + v[2])) then return false end
      end
      return true
    end
    return openScore(cx, cy) >= strict
  end
  local function bfs(sx, sy)
    local dist, prev, queue, head = { [sx .. "," .. sy] = 0 }, {}, { { sx, sy } }, 1
    while head <= #queue do
      local c = queue[head]; head = head + 1
      local d = dist[c[1] .. "," .. c[2]]
      if d < 60 then
        for name, v in pairs(DIRS) do
          local nx, ny = c[1] + v[1], c[2] + v[2]
          local k = nx .. "," .. ny
          if dist[k] == nil and free(nx, ny) and cellOK(nx, ny) then
            dist[k], prev[k] = d + 1, { c[1], c[2], name }
            queue[#queue + 1] = { nx, ny }
          end
        end
      end
    end
    return dist, prev
  end
  local function pathTo(prev, sx, sy, tx, ty)
    local steps, k = {}, tx .. "," .. ty
    while prev[k] do
      local p = prev[k]
      table.insert(steps, 1, p[3])
      k = p[1] .. "," .. p[2]
    end
    return steps
  end
  -- a far cell around `want` steps away, away from `avoid` if given
  local function pickTarget(dist, sx, sy, want, avoid)
    local best, bestScore
    for k, d in pairs(dist) do
      if d >= want - 4 and d <= want + 4 then
        local x, y = k:match("(-?%d+),(-?%d+)")
        x, y = tonumber(x), tonumber(y)
        local score = math.abs(x - sx) + math.abs(y - sy)
        if avoid then score = score + 0.5 * (math.abs(x - avoid[1]) + math.abs(y - avoid[2])) end
        if not bestScore or score > bestScore then best, bestScore = { x, y }, score end
      end
    end
    return best
  end
  local rec = { dir = nil, f = 0, n = 0 }
  local function tick()
    rec.f = rec.f + 1
    if rec.dir and rec.f % STEP == 0 then
      rec.n = rec.n + 1
      capture(rec.dir, rec.n)
    end
    coroutine.yield()
  end
  local function hold(btn, frames)
    for _ = 1, frames do
      table.insert(game.input.pressQueue, btn)
      game.input.state[btn] = true
      tick()
    end
    game.input.state[btn] = false
  end
  -- walk to (tx, ty) along the planned path, one tile at a time
  local function walkTo(tx, ty, budget)
    local p = game.overworld.player
    local tries = 0
    while budget > 0 and (p.cellX ~= tx or p.cellY ~= ty) and tries < 6 do
      local _, prev = bfs(p.cellX, p.cellY)
      local steps = pathTo(prev, p.cellX, p.cellY, tx, ty)
      if #steps == 0 then return budget end
      tries = tries + 1
      for _, d in ipairs(steps) do
        local wx, wy = p.cellX + DIRS[d][1], p.cellY + DIRS[d][2]
        local t = 0
        while (p.cellX ~= wx or p.cellY ~= wy) and t < 48 and budget > 0 do
          table.insert(game.input.pressQueue, d)
          game.input.state[d] = true
          tick(); t = t + 1; budget = budget - 1
        end
        game.input.state[d] = false
        if p.cellX ~= wx or p.cellY ~= wy then break end   -- blocked: plan again
        if budget <= 0 then return 0 end
      end
    end
    return budget
  end
  -- a tour of about `frames` frames: a far cell, then a second leg elsewhere
  local function strollRecord(shot, frames)
    rec.dir, rec.f, rec.n = newShotDir(shot), 0, 0
    frames = frames or 420
    local p = game.overworld.player
    local start = { p.cellX, p.cellY }
    local budget = frames
    strict = 7
    local n = 0
    for _ in pairs(bfs(p.cellX, p.cellY)) do n = n + 1 end
    if n < 40 then strict = 5 end
    n = 0
    for _ in pairs(bfs(p.cellX, p.cellY)) do n = n + 1 end
    if n < 40 then strict = 0 end
    for leg = 1, 3 do
      if budget <= 0 then break end
      local dist = bfs(p.cellX, p.cellY)
      local target = pickTarget(dist, p.cellX, p.cellY, leg == 1 and 14 or 10, start)
      if not target then break end
      budget = walkTo(target[1], target[2], budget)
    end
    while budget > 0 do tick(); budget = budget - 1 end
    U.log(("recorded %s: %d frames -> %s"):format(shot, rec.n, rec.dir))
    rec.dir = nil
  end
  -- first / third person: the free camera takes its yaw from the player's
  -- facing at the moment the mode engages, and "up" then means forward. So
  -- face the longest clear straight line FIRST, switch the mode on, and hold
  -- forward.
  local function longestLine()
    local p = game.overworld.player
    local bestDir, bestLen = "up", 0
    for name, v in pairs(DIRS) do
      local len = 0
      while len < 30 and free(p.cellX + v[1] * (len + 1), p.cellY + v[2] * (len + 1)) do len = len + 1 end
      if len > bestLen then bestDir, bestLen = name, len end
    end
    return bestDir, bestLen
  end
  local function forwardRecord(shot, frames, level)
    local V = rawget(_G, "__DRAMATIC_SHAPE_V")
    local okF, FP = pcall(function() return V and V.require("FirstPerson") end)
    local okM, FM = pcall(function() return V and V.require("FreeMove") end)
    if not (okF and FP and okM and FM) then U.log("no free camera for " .. shot); return end
    local p = game.overworld.player
    -- a route with corners in it: a far open cell, then a second leg, kept
    -- to cells with room on every side so the eye never brushes a wall
    strict = "wide"
    local reach = 0
    for _ in pairs(bfs(p.cellX, p.cellY)) do reach = reach + 1 end
    if reach < 30 then strict = 5 end
    local dist, prev = bfs(p.cellX, p.cellY)
    local t1 = pickTarget(dist, p.cellX, p.cellY, 12)
    local cells = {}
    if t1 then
      local cx, cy = p.cellX, p.cellY
      for _, d in ipairs(pathTo(prev, cx, cy, t1[1], t1[2])) do
        cx, cy = cx + DIRS[d][1], cy + DIRS[d][2]
        cells[#cells + 1] = { cx, cy }
      end
      local dist2, prev2 = bfs(cx, cy)
      local t2 = pickTarget(dist2, cx, cy, 10, { p.cellX, p.cellY })
      if t2 then
        for _, d in ipairs(pathTo(prev2, cx, cy, t2[1], t2[2])) do
          cx, cy = cx + DIRS[d][1], cy + DIRS[d][2]
          cells[#cells + 1] = { cx, cy }
        end
      end
    end
    strict = 7
    -- only the corners: a straight run is one waypoint
    local wps = {}
    for i, c in ipairs(cells) do
      local nx = cells[i + 1]
      local pv = cells[i - 1] or { p.cellX, p.cellY }
      if not nx or (nx[1] - c[1]) ~= (c[1] - pv[1]) or (nx[2] - c[2]) ~= (c[2] - pv[2]) then
        wps[#wps + 1] = { c[1] * 16 + 8, c[2] * 16 + 8 }
      end
    end
    -- face the first leg before the mode engages, so it starts looking ahead
    if wps[1] then
      local dx, dy = wps[1][1] - (p.px + 8), wps[1][2] - (p.py + 8)
      p.facing = math.abs(dx) > math.abs(dy) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
    end
    voxel(level)
    U.wait(90)
    -- a pre-roll: the camera starts behind the player, which can be inside
    -- whatever they were standing in front of; record once they are walking
    local pre = (level == 7) and 75 or 30
    rec.dir, rec.f, rec.n = nil, 0, 0
    local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
    local wi, stuck, lastX, lastZ = 1, 0, nil, nil
    while rec.f < frames + pre do
      if not rec.dir and rec.f >= pre then rec.dir, rec.n = newShotDir(shot), 0 end
      local pos = FM._pos()
      local x = pos and pos.x or (p.px + 8)
      local z = pos and pos.z or (p.py + 8)
      local w = wps[wi]
      if w and math.abs(w[1] - x) + math.abs(w[2] - z) < 5 then wi = wi + 1; w = wps[wi] end
      local walking = false
      if w then
        -- ease the look toward the next corner: fast enough to round it,
        -- slow enough to read as a person turning their head
        local want = math.atan2(w[1] - x, w[2] - z)
        local diff = wrap(want - FP.yaw)
        local turn = diff * 0.1
        local maxTurn = 2.4 / 60
        if turn > maxTurn then turn = maxTurn elseif turn < -maxTurn then turn = -maxTurn end
        FP.yaw = wrap(FP.yaw + turn)
        walking = math.abs(diff) < 0.45    -- a corner turns first, then goes
        -- a body that has not moved in a second is stuck: skip the corner
        if lastX and math.abs(x - lastX) + math.abs(z - lastZ) < 0.05 and walking then stuck = stuck + 1 else stuck = 0 end
        if stuck > 60 then wi = wi + 1; stuck = 0 end
      end
      lastX, lastZ = x, z
      game.input.state.up = walking
      if walking then table.insert(game.input.pressQueue, "up") end
      tick()
    end
    game.input.state.up = false
    U.log(("recorded %s: %d frames (%d corners) -> %s"):format(shot, rec.n, #wps, rec.dir))
    rec.dir = nil
  end
  local WALK = 420

  local function battleShot(shot, species, level, opts, extraFrames)
    local id = speciesByName(species) or species
    local ok, battle = pcall(BattleState.newWild, game, id, level, opts)
    if not ok or not battle then U.log("battle failed: " .. tostring(battle)); return end
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    -- the wipe and the send-out, then a turn: A every 40 frames
    local dir = newShotDir(shot)
    local n = 0
    for f = 1, extraFrames or 900 do
      if f > 200 and f % 40 == 0 then table.insert(game.input.pressQueue, "a") end
      if f % STEP == 0 then
        n = n + 1
        capture(dir, n)
      end
      coroutine.yield()
      if f % 40 == 1 then game.input.state.a = false end
    end
    U.log(("recorded %s: %d frames -> %s"):format(shot, n, dir))
    while game.stack:top() and game.stack:top() ~= game.overworld do game.stack:pop() end
    U.wait(20)
  end


  -- ------------------------------------------------------------- the shots
  local SHOTS = {}
  local function shot(name, fn) SHOTS[#SHOTS + 1] = { name = name, fn = fn } end

  -- flat for the first half, then the voxels switch on mid-walk
  local function revealRecord(shotName, frames)
    voxel(0)
    rec.dir, rec.f, rec.n = newShotDir(shotName), 0, 0
    local p = game.overworld.player
    local dist = bfs(p.cellX, p.cellY)
    local target = pickTarget(dist, p.cellX, p.cellY, 18)
    local half = math.floor(frames / 2)
    local function step(n) while n > 0 do tick(); n = n - 1 end end
    if target then
      -- walk the first half flat, then switch and keep walking
      local left = walkTo(target[1], target[2], half)
      step(left)
      voxel(VOX)
      local dist2 = bfs(p.cellX, p.cellY)
      local t2 = pickTarget(dist2, p.cellX, p.cellY, 10)
      left = t2 and walkTo(t2[1], t2[2], frames - half) or (frames - half)
      step(left)
    else
      step(half); voxel(VOX); step(frames - half)
    end
    U.log(("recorded %s: %d frames -> %s"):format(shotName, rec.n, rec.dir))
    rec.dir = nil
  end
  -- every ordinary shot: voxels on at the chosen level, then the stroll
  local function town(name, mapId, x, y, hour, level)
    shot(name, function()
      pinnedHour = hour or 12
      goTo(mapId, x, y)
      if version ~= "platinum" then voxel(level or VOX); U.wait(150) end
      strollRecord(name, WALK)
    end)
  end
  local function fight(name, mapId, species, level, opts, frames, hour)
    shot(name, function()
      pinnedHour = hour or 12
      goTo(mapId)
      if version ~= "platinum" then voxel(VOX); U.wait(150) end
      battleShot(name, species, level, opts, frames)
    end)
  end
  local function person(name, mapId, level, hour)
    shot(name, function()
      pinnedHour = hour or 12
      goTo(mapId, mapId == "NEW_BARK_TOWN" and 9 or nil, mapId == "NEW_BARK_TOWN" and 8 or nil)
      forwardRecord(name, 420, level)
    end)
  end

  if version == "crystal" or version == "gold" or version == "silver" then
    shot("voxel_reveal", function() pinnedHour = 12; goTo("NEW_BARK_TOWN", 9, 8); revealRecord("voxel_reveal", 480) end)
    town("newbark_day", "NEW_BARK_TOWN", 9, 8, 12)
    town("newbark_night", "NEW_BARK_TOWN", 9, 8, 21)
    town("cherrygrove_tiltshift", "CHERRYGROVE_CITY", nil, nil, 12, 3)
    town("violet", "VIOLET_CITY", nil, nil, 10)
    town("ecruteak_dusk", "ECRUTEAK_CITY", nil, nil, 18)
    town("goldenrod", "GOLDENROD_CITY", nil, nil, 14)
    town("overview", "VIOLET_CITY", nil, nil, 12, 1)
    fight("battle_shiny", "ROUTE_29", "GYARADOS", 30, { shiny = true }, 1000, 12)
    fight("battle_dusk", "ROUTE_29", "PIDGEOTTO", 18, nil, 1200, 17)
    person("first_person", "NEW_BARK_TOWN", 6, 12)
    person("third_person", "CHERRYGROVE_CITY", 7, 16)
  elseif version == "firered" then
    shot("voxel_reveal", function() pinnedHour = 12; goTo("MAP_G03_N00"); revealRecord("voxel_reveal", 480) end)
    town("pallet", "MAP_G03_N00")
    town("cerulean", "MAP_G03_N03")
    fight("battle", "MAP_G03_N00", "PIDGEY", 12, nil, 1000)
    person("third_person", "MAP_G03_N03", 7)
  elseif version == "emerald" then
    town("littleroot", "MAP_G00_N09")
    town("slateport", "MAP_G00_N01")
    town("lilycove", "MAP_G00_N05")
    fight("battle", "MAP_G00_N09", "ZIGZAGOON", 10, nil, 1000)
    person("first_person", "MAP_G00_N05", 6)
  elseif version == "platinum" then
    -- natively 3D; single screen, the bottom screen off
    game.save.options.secondScreenMode = "off"
    pcall(function() game:applyOptions() end)
    -- the camera rung: 1 is the cartridge's own; 9 third person, 10 first
    local Gen4Camera = require("src.render.Gen4Camera")
    local function rung(i) game.save.options.gen4CameraTilt = i; pcall(Gen4Camera.setTilt, i) end
    rung(1)
    shot("third_person", function() goTo("C01"); rung(9); U.wait(60); strollRecord("third_person", WALK); rung(1) end)
    town("twinleaf", "T01")
    town("jubilife", "C01")
    town("snowpoint", "C09")
    town("eterna", "C04")
    town("hearthome", "C05")
    fight("battle", "R201", "STARLY", 8, nil, 1100)
  end

  for _, s in ipairs(SHOTS) do
    if next(ONLY) == nil or ONLY[s.name] then
      local ok, err = pcall(s.fn)
      if not ok then U.log("shot " .. s.name .. " failed: " .. tostring(err)) end
      voxel(0)
    end
  end
  os.date = realDate
  love.timer.getTime, love.update = realGetTime, realUpdate
  -- let the last screenshots land, then drain the writers
  U.wait(4)
  for _ in ipairs(writers) do queue:push("stop") end
  for _, t in ipairs(writers) do t:wait() end
  U.log("done")
  love.event.quit()
end
