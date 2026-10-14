-- tools/trailer/editor_tour.lua -- MAP EDITOR SHOWCASE FOOTAGE, recorded from
-- the real editor with a drawn cursor clicking the real buttons.
--
-- A POKEPORT_DRIVER: the game boots (POKEPORT_VERSION=crystal or platinum),
-- then the driver hands the frame loop to the map editor (tools/save-editor
-- App in "map" mode) and plays a scripted tour, streaming segments to MP4:
--
--   crystal:  ed_crystal_browse, ed_crystal_3d, ed_crystal_tiles,
--             ed_crystal_walkable, ed_crystal_npcs, ed_crystal_world
--   platinum: ed_plat_browse, ed_plat_place, ed_plat_change
--
-- Clicks are real: the pointer is faked (love.mouse.getPosition / isDown) and
-- buttons are found by wrapping Kit.button/chip/stepper/text/textfield, which
-- record where each label was drawn this frame. Map cells are located by the
-- editor's own projection (3D: Viewport3D.pick swept over the viewport; 2D:
-- the inverse of Preview's cellAtScreen).
--
-- NOTHING IS SAVED: the tour never presses SAVE EDITS, so the edits live only
-- in this run's memory.
--
-- Env: OUT (required), FFMPEG, WIDTH/HEIGHT (default 1920x1080).

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local OUT = assert(os.getenv("OUT"), "set OUT")
  local version = require("src.core.GameVersion").get()
  local W, H = tonumber(os.getenv("WIDTH") or "1920"), tonumber(os.getenv("HEIGHT") or "1080")
  pcall(love.window.setMode, W, H, { resizable = true, vsync = 0 })
  U.wait(10)

  -- ------------------------------------------------------------- the pointer
  local mx, my, down = W * 0.55, H * 0.55, false
  love.mouse.getPosition = function() return mx, my end
  love.mouse.getX = function() return mx end
  love.mouse.getY = function() return my end
  love.mouse.isDown = function(b) return down and b == 1 end
  love.mouse.setRelativeMode = function() end
  love.mouse.setGrabbed = function() end

  -- ------------------------------------------------------ the editor, hosted
  local fs = love.filesystem
  fs.setRequirePath("tools/save-editor/?.lua;tools/save-editor/panels/?.lua;" .. fs.getRequirePath())
  local Kit = require("Kit")
  local cur = { rects = {}, texts = {}, fields = {} }
  local last = cur
  local function wrapLabelled(name, argIndex)
    local orig = Kit[name]
    Kit[name] = function(...)
      local a = { ... }
      local label = a[argIndex]
      if type(label) == "string" then
        local l = cur.rects[label] or {}
        l[#l + 1] = { a[1], a[2], a[3], a[4] }
        cur.rects[label] = l
      end
      return orig(...)
    end
  end
  wrapLabelled("button", 5); wrapLabelled("chip", 5); wrapLabelled("stepper", 5)
  do
    local orig = Kit.text
    Kit.text = function(fontName, str, x, y, ...)
      if type(str) == "string" then cur.texts[#cur.texts + 1] = { str, x, y } end
      return orig(fontName, str, x, y, ...)
    end
    local origP = Kit.press
    Kit.press = function(x, y, w, h, ...)
      cur.presses = cur.presses or {}
      cur.presses[#cur.presses + 1] = { x, y, w, h }
      return origP(x, y, w, h, ...)
    end
    local origF = Kit.textfield
    Kit.textfield = function(id, x, y, w, h, ...)
      cur.fields[id] = { x, y, w, h }
      return origF(id, x, y, w, h, ...)
    end
  end

  local App = require("App")
  App.load(nil, { version = version, mode = "map", embedded = true, onClose = function() end })
  local S = App.getState()
  local Preview = require("tools.map-editor.panels.Preview")
  local Viewport3D = require("tools.map-editor.Viewport3D")
  local History = require("tools.map-editor.History")
  -- the 3D viewport's real rectangle: Preview only records its own for the
  -- flat view, so take it from the draw call
  local view3D = nil
  do
    local orig = Viewport3D.draw
    Viewport3D.draw = function(S_, built, x, y, w, h, ...)
      view3D = { x, y, w, h }
      return orig(S_, built, x, y, w, h, ...)
    end
  end
  local function viewRect()
    if S.pv3DActive and view3D then return view3D[1], view3D[2], view3D[3], view3D[4] end
    return S._pvViewX, S._pvViewY, S._pvViewW, S._pvViewH
  end

  -- ------------------------------------------------------------- the overlay
  local ripple, toast, toastT = nil, nil, 0
  local toastFont = love.graphics.newFont(30)
  local function drawCursor()
    local G = love.graphics
    if ripple then
      local t = ripple.t / 18
      G.setColor(1, 1, 1, 0.75 * (1 - t))
      G.setLineWidth(4)
      G.circle("line", ripple.x, ripple.y, 10 + 34 * t)
      G.setLineWidth(1)
    end
    G.push()
    G.translate(mx, my)
    G.scale(1.25)
    local pts = { 0, 0, 0, 26, 7, 20, 12, 31, 17, 29, 12, 18, 21, 18 }
    G.setColor(0, 0, 0, 0.35); G.push(); G.translate(2, 3); G.polygon("fill", { 0, 0, 0, 26, 7, 20, 12, 18, 21, 18 }); G.pop()
    G.setColor(1, 1, 1, 1)
    G.polygon("fill", { 0, 0, 0, 26, 7, 20, 12, 18, 21, 18 })
    G.polygon("fill", { 7, 20, 12, 31, 17, 29, 12, 18 })
    G.setColor(0, 0, 0, 1); G.setLineWidth(1.6)
    G.polygon("line", pts)
    G.setLineWidth(1)
    G.pop()
    if toast and toastT > 0 then
      local a = math.min(1, toastT / 12)
      local tw = toastFont:getWidth(toast) + 56
      local x, y = (W - tw) / 2, H - 150
      G.setColor(0.04, 0.06, 0.12, 0.88 * a)
      G.rectangle("fill", x, y, tw, 60, 14, 14)
      G.setColor(0.97, 0.82, 0.19, a)
      G.setLineWidth(3); G.rectangle("line", x, y, tw, 60, 14, 14); G.setLineWidth(1)
      G.setColor(1, 1, 1, a)
      G.setFont(toastFont)
      G.print(toast, x + 28, y + 12)
    end
    G.setColor(1, 1, 1, 1)
  end
  game.update = function(self, dt) App.update(dt) end
  game.draw = function(self)
    cur = { rects = {}, texts = {}, fields = {}, presses = {} }
    App.draw()
    last = cur
    drawCursor()
  end

  -- ------------------------------------------------------------- recording
  local Rec = dofile("tools/trailer/recorder.lua")({ out = OUT, ffmpeg = os.getenv("FFMPEG") })
  -- a camera the tour has framed stays framed: an edit rebuilds the 3D view,
  -- and the rebuild would otherwise re-centre it behind the drawer
  local camLock = nil
  local function tick()
    if camLock and camLock.flat then
      S.pvCamX, S.pvCamY, S.pvZoom = camLock.x, camLock.y, camLock.z
      S._pvCenteredFor = S.mapId
    elseif camLock and S.pv3DActive then
      S.pvFocus = { x = camLock.f.x, y = camLock.f.y, z = camLock.f.z }
      S.pvDist, S.pvYaw, S.pvAngle = camLock.d, camLock.yaw, camLock.angle
    end
    if ripple then ripple.t = ripple.t + 1; if ripple.t > 18 then ripple = nil end end
    if toastT > 0 then toastT = toastT - 1 end
    Rec.frame()
    coroutine.yield()
  end
  local function wait(n) for _ = 1, n do tick() end end
  local function say(text, frames) toast, toastT = text, frames or 90 end

  -- ------------------------------------------------------------- gestures
  local function ease(t) return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2 end
  local function moveTo(x, y, frames)
    frames = frames or 24
    local x0, y0 = mx, my
    for i = 1, frames do
      local t = ease(i / frames)
      mx, my = x0 + (x - x0) * t, y0 + (y - y0) * t
      tick()
    end
  end
  local function find(label, pick)
    local list = last.rects[label]
    if not list or #list == 0 then return nil end
    if pick then
      for _, r in ipairs(list) do if pick(r) then return r end end
      return nil
    end
    return list[1]
  end
  -- a UI click: the editor reads Kit.mouseClicked on the next draw
  local function clickHere()
    ripple = { x = mx, y = my, t = 0 }
    App.mousepressed(mx, my, 1)
    tick(); tick()
  end
  local function click(label, pick, settle)
    local r = find(label, pick)
    if not r then U.log("no button " .. label); return false end
    moveTo(r[1] + r[3] / 2, r[2] + r[4] / 2)
    wait(6)
    clickHere()
    wait(settle or 20)
    return true
  end
  -- a click on the map: Preview polls the button and acts on a still release
  local function mapClick(x, y, travel)
    moveTo(x, y, travel or 18)
    wait(4)
    ripple = { x = mx, y = my, t = 0 }
    down = true; tick(); tick(); tick()
    down = false; tick(); tick()
  end
  local function typeText(str, per)
    for ch in str:gmatch(".") do App.textinput(ch); wait(per or 5) end
  end
  local function clickField(id)
    local r = last.fields[id]
    if not r then U.log("no field " .. id); return false end
    moveTo(r[1] + 60, r[2] + r[4] / 2)
    wait(5); clickHere(); wait(8)
    return true
  end
  local function textAt(pattern)
    for _, t in ipairs(last.texts) do
      if t[1]:find(pattern) then return t end
    end
  end

  -- where a cell is on screen
  local cellPos = {}
  local function sweep(maxX)
    cellPos = {}
    local vx, vy, vw, vh = viewRect()
    if not vx then return end
    maxX = maxX or (vx + vw)
    if S.pv3DActive and S.pv3D then
      local acc = {}
      for y = vy + 6, vy + vh - 6, 8 do
        for x = vx + 6, math.min(vx + vw, maxX) - 6, 8 do
          local ok, cx, cy = pcall(Viewport3D.pick, S, S.pv3D, x, y, vx, vy, vw, vh)
          if ok and cx then
            local k = cx .. "," .. cy
            local e = acc[k] or { 0, 0, 0, x, x, y, y }
            e[1], e[2], e[3] = e[1] + x, e[2] + y, e[3] + 1
            e[4], e[5] = math.min(e[4], x), math.max(e[5], x)
            e[6], e[7] = math.min(e[6], y), math.max(e[7], y)
            acc[k] = e
          end
        end
      end
      -- the ray also lands on the empty ground plane around the map: only
      -- cells of the map itself count
      local def = S.data.maps[S.mapId]
      local wc = (version == "platinum") and def.width or def.width * 2
      local hc = (version == "platinum") and def.height or def.height * 2
      -- and a pick off the edge of the map comes back CLAMPED to an edge
      -- cell, which then owns a smear of screen: keep cells whose samples
      -- span about one cell's worth of screen
      local spans = {}
      for _, e in pairs(acc) do spans[#spans + 1] = math.max(e[5] - e[4], e[7] - e[6]) end
      table.sort(spans)
      local typical = spans[math.max(1, math.floor(#spans / 2))] or 40
      for k, e in pairs(acc) do
        local cx, cy = k:match("(-?%d+),(-?%d+)")
        cx, cy = tonumber(cx), tonumber(cy)
        local span = math.max(e[5] - e[4], e[7] - e[6])
        if e[3] >= 2 and cx >= 0 and cy >= 0 and cx < wc and cy < hc and span <= typical * 1.8 + 8 then
          cellPos[k] = { e[1] / e[3], e[2] / e[3] }
        end
      end
    else
      local def = S.data.maps[S.mapId]
      local z = S.pvZoom or 2
      local wc = (version == "platinum") and def.width or def.width * 2
      local hc = (version == "platinum") and def.height or def.height * 2
      for cy = 0, hc - 1 do
        for cx = 0, wc - 1 do
          local x = vx + (cx * 16 + 8 - (S.pvCamX or 0)) * z
          local y = vy + Preview.groundY(S, cy * 16 + 8 - (S.pvCamY or 0)) * z
          if x > vx + 8 and x < math.min(vx + vw, maxX) - 8 and y > vy + 8 and y < vy + vh - 8 then
            cellPos[cx .. "," .. cy] = { x, y }
          end
        end
      end
    end
  end
  local function cellXY(cx, cy) return cellPos[cx .. "," .. cy] end
  -- visible cells nearest a screen point
  local function mapMiddle()
    local sx, sy, n = 0, 0, 0
    for _, p in pairs(cellPos) do sx, sy, n = sx + p[1], sy + p[2], n + 1 end
    if n == 0 then return W / 2, H / 2 end
    return sx / n, sy / n
  end
  local function cellsNear(px, py, n)
    local all = {}
    for k, p in pairs(cellPos) do
      local cx, cy = k:match("(-?%d+),(-?%d+)")
      all[#all + 1] = { tonumber(cx), tonumber(cy), p[1], p[2], (p[1] - px) ^ 2 + (p[2] - py) ^ 2 }
    end
    table.sort(all, function(a, b) return a[5] < b[5] end)
    local out = {}
    for i = 1, math.min(n, #all) do out[i] = all[i] end
    return out
  end
  local function drawerLeft()
    local xs = find("x", function(r) return r[2] > 150 end)
    local chip = find("WARPS", function(r) return r[3] < 160 end)
    -- the drawer's chip row starts ~80px in from the drawer's own edge
    if chip then return chip[1] - 100 end
    if xs then return xs[1] - 800 end
    return W
  end

  -- glide the 3D camera so the whole map sits in what the drawer leaves
  -- visible: frame it, push back by the hidden fraction, pan it across
  local function fitVisible(frames)
    if not (S.pv3DActive and S.pv3D and view3D) then return end
    local vx, _, vw, vh = viewRect()
    local f0 = S.pvFocus and { x = S.pvFocus.x, y = S.pvFocus.y, z = S.pvFocus.z }
    local d0 = S.pvDist
    Viewport3D.frame(S, S.pv3D)
    local visW = math.max(200, math.min(vx + vw, drawerLeft()) - vx)
    S.pvDist = S.pvDist * (vw / visW) * 0.95
    Viewport3D.pan(S, S.pv3D, (vx + visW / 2) - (vx + vw / 2), 0, vh)
    local f1, d1 = S.pvFocus, S.pvDist
    camLock = nil
    local function lock() camLock = { f = f1, d = d1, yaw = S.pvYaw, angle = S.pvAngle } end
    if not (f0 and d0) then lock(); return end
    for i = 1, frames or 30 do
      local t = ease(i / (frames or 30))
      S.pvFocus = { x = f0.x + (f1.x - f0.x) * t, y = f0.y + (f1.y - f0.y) * t, z = f0.z + (f1.z - f0.z) * t }
      S.pvDist = d0 + (d1 - d0) * t
      tick()
    end
    lock()
  end

  local function orbit(frames, dyaw, dpitch)
    camLock = nil
    local y0, a0 = S.pvYaw or 0, S.pvAngle or 35
    for i = 1, frames do
      local t = ease(i / frames)
      S.pvYaw = y0 + dyaw * t
      S.pvAngle = a0 + (dpitch or 0) * math.sin(t * math.pi)
      S.pvViewName = nil
      tick()
    end
  end

  -- first frame: the editor, settled
  S.pvDiag = false
  wait(20)

  -- swatches, in palette order: one press per block at BLOCK grain,
  -- four (one per quadrant) at CELL grain
  local function swatch(idx, quadrant)
    local dl = drawerLeft()
    local sq = {}
    local head = textAt("^%d+ blocks%s+%-")
    local top = head and head[3] + 8 or 0
    for _, r in ipairs(last.presses or {}) do
      if r[1] > dl and r[2] > top and math.abs(r[3] - r[4]) < 1 and r[3] >= 16 then sq[#sq + 1] = r end
    end
    -- the palette may be scrolled: count a row's swatches, skip scrolled rows
    local cols = 0
    for _, q in ipairs(sq) do if sq[1] and math.abs(q[2] - sq[1][2]) < 2 then cols = cols + 1 end end
    local per = (S.tileGrain == "cell") and 4 or 1
    cols = math.max(1, cols / ((S.tileGrain == "cell") and 2 or 1))
    local at = idx - (S.tileScroll or 0) * cols
    local r
    if at >= 0 then
      if S.tileGrain == "cell" then r = sq[at * 4 + (quadrant or 0) + 1] else r = sq[at + 1] end
    end
    local _ = per
    if r then return r[1] + r[3] / 2, r[2] + r[4] / 2 end
  end
  local function pickSwatch(idx, quadrant, travel)
    local x, y = swatch(idx, quadrant)
    if not x then U.log("no swatch " .. idx); return end
    moveTo(x, y, travel or 22); wait(6); clickHere(); wait(14)
  end


  -- ================================================================ CRYSTAL
  if version ~= "platinum" then
    Rec.start("ed_crystal_browse")
    wait(30)
    if clickField("pv-q") then typeText("NewBark", 6) end
    wait(20)
    local row = textAt("^NewBark") or textAt("NewBark")
    if row then moveTo(row[2] + 60, row[3] + 8, 20) else moveTo(225, 400, 20) end
    wait(4); ripple = { x = mx, y = my, t = 0 }
    Preview.select(S, "NEW_BARK_TOWN")
    S.pvDiag = false
    wait(60)
    click("+", function(r) return r[2] < 300 and r[1] > 1100 end, 40)
    click("-", function(r) return r[2] < 300 and r[1] > 1100 end, 40)
    click("3D", nil, 10)
    S.pvDiag = false
    wait(70)
    Rec.stop()

    Rec.start("ed_crystal_3d")
    say("3D VIEW  -  orbit, tilt, fly", 120)
    moveTo(W * 0.42, H * 0.6, 20)
    orbit(150, 0.9, 18)
    orbit(120, -0.9, -10)
    -- more room for the map: fold the area list away
    click("<", function(r) return r[1] < 450 end, 30)
    App.keypressed("home"); wait(20)
    Rec.stop()

    Rec.start("ed_crystal_tiles")
    click("TILES", nil, 30)
    say("TILES  -  paint the ground itself", 100)
    fitVisible(30)
    wait(10)

    -- the map's own blocks, to aim at real ground rather than empty space
    local Map = require("src.world.Map")
    local def = S.data.maps[S.mapId]
    local blocks = Map.blockArray(def) or {}
    local bw, bh = def.width, def.height
    local function blockAt(bx, by) return blocks[by * bw + bx + 1] end
    local function blockScreen(bx, by)
      local sx, sy, n = 0, 0, 0
      for dy = 0, 1 do for dx = 0, 1 do
        local p = cellXY(bx * 2 + dx, by * 2 + dy)
        if p then sx, sy, n = sx + p[1], sy + p[2], n + 1 end
      end end
      if n < 4 then return nil end
      return sx / n, sy / n
    end
    local function cellScreen(cx, cy) local p = cellXY(cx, cy); if p then return p[1], p[2] end end
    local counts = {}
    for _, id in ipairs(blocks) do counts[id] = (counts[id] or 0) + 1 end
    -- the path is the commonest block INSIDE the town (not the border)
    local inner = {}
    for by = 2, bh - 3 do for bx = 2, bw - 3 do
      local id = blockAt(bx, by); inner[id] = (inner[id] or 0) + 1
    end end
    local pathId, best = nil, 0
    for id, n in pairs(inner) do if n > best then pathId, best = id, n end end
    -- the border's commonest block: the tree line
    local edge = {}
    for bx = 0, bw - 1 do for _, by in ipairs({ 0, bh - 1 }) do
      local id = blockAt(bx, by); edge[id] = (edge[id] or 0) + 1
    end end
    local treeId, tb = nil, 0
    for id, n in pairs(edge) do if n > tb then treeId, tb = id, n end end

    sweep(drawerLeft())

    -- the palette's own zoom
    click("-", function(r) return r[1] > drawerLeft() and r[3] < 40 end, 18)
    click("+", function(r) return r[1] > drawerLeft() and r[3] < 40 end, 18)

    -- BLOCK 32px: flowers along the path
    click("BLOCK 32px", nil, 15)
    click("PAINT", nil, 10)
    say("PAINT  -  32px blocks", 90)
    pickSwatch(4)
    local run = {}
    for by = math.floor(bh / 2), bh - 3 do
      run = {}
      for bx = 2, bw - 3 do
        if blockAt(bx, by) == pathId and blockScreen(bx, by) then run[#run + 1] = { bx, by } else
          if #run >= 4 then break end
          run = {}
        end
      end
      if #run >= 4 then break end
    end
    for i = 1, math.min(4, #run) do
      local x, y = blockScreen(run[i][1], run[i][2])
      mapClick(x, y, i == 1 and 24 or 12)
    end
    wait(20)

    -- CELL 16px: a quarter of a block at a time
    click("CELL 16px", nil, 15)
    say("CELL  -  16px detail, a quarter block at a time", 100)
    pickSwatch(5, 0)
    local usedRow = run[1] and run[1][2] or math.floor(bh / 2)
    local cellsDone = 0
    for bx = 2, bw - 3 do
      local by = usedRow - 2
      if by >= 1 and blockAt(bx, by) == pathId and cellsDone < 3 then
        local x, y = cellScreen(bx * 2, by * 2 + 1)
        if x then cellsDone = cellsDone + 1; mapClick(x, y, cellsDone == 1 and 24 or 12) end
      end
    end
    wait(20)

    -- PICK: the eyedropper, then stamp what it picked
    click("BLOCK 32px", nil, 10)
    click("PICK", nil, 15)
    say("PICK  -  grab any block straight off the map", 100)
    local tx, ty
    for by = 0, bh - 1 do
      for bx = 0, bw - 1 do
        if not tx and blockAt(bx, by) == treeId then tx, ty = blockScreen(bx, by) end
      end
    end
    if tx then mapClick(tx, ty, 24) end
    wait(15)
    click("PAINT", nil, 10)
    local stamped = 0
    for by = 2, bh - 3 do
      for bx = 2, bw - 3 do
        if stamped < 2 and blockAt(bx, by) == pathId and by ~= usedRow and by ~= usedRow - 2 and (bx + by) % 3 == 0 then
          local x, y = blockScreen(bx, by)
          if x then stamped = stamped + 1; mapClick(x, y, 20) end
        end
      end
    end
    wait(20)

    -- FILL: flood a lawn with water
    click("FILL", nil, 15)
    say("FILL  -  flood a whole area in one click", 100)
    pickSwatch(7)
    -- a lawn: a connected patch of one non-path block, 3 to 30 blocks big
    local seen, lawn = {}, nil
    for by = 1, bh - 2 do
      for bx = 1, bw - 2 do
        local id = blockAt(bx, by)
        local k = by * bw + bx
        if not seen[k] and id ~= pathId and id ~= treeId then
          local stack, size, members = { { bx, by } }, 0, {}
          seen[k] = true
          while #stack > 0 do
            local c = table.remove(stack)
            size = size + 1; members[#members + 1] = c
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
              local nx, ny = c[1] + d[1], c[2] + d[2]
              local nk = ny * bw + nx
              if nx >= 0 and ny >= 0 and nx < bw and ny < bh and not seen[nk] and blockAt(nx, ny) == id then
                seen[nk] = true; stack[#stack + 1] = { nx, ny }
              end
            end
          end
          if size >= 3 and size <= 30 and (not lawn or size > lawn.size) then
            lawn = { size = size, at = members[math.ceil(#members / 2)] }
          end
        end
      end
    end
    if lawn then
      local x, y = blockScreen(lawn.at[1], lawn.at[2])
      if x then mapClick(x, y, 24) end
    end
    wait(60)
    say("Ctrl+Z  -  undo", 70)
    wait(15); pcall(History.undo, S); wait(50)
    say("Ctrl+Y  -  redo", 70)
    wait(15); pcall(History.redo, S); wait(50)

    -- FROM: any tileset in the game, added to this map
    say("FROM  -  borrow blocks from any tileset", 110)
    local own = S.tileSource
    local srcBtn = find(tostring(own))
    if srcBtn then
      moveTo(srcBtn[1] + srcBtn[3] / 2, srcBtn[2] + srcBtn[4] / 2, 22); wait(6); clickHere(); wait(25)
    end
    local other
    for label, list in pairs(last.rects) do
      if not other and label:find("^Tileset") and label ~= own and not label:find("this map") then
        if label:find("Kanto") or label:find("Port") or label:find("Lab") or label:find("Ruins") then other = label end
      end
    end
    if not other then
      for label in pairs(last.rects) do
        if not other and label:find("^Tileset") and label ~= own and not label:find("this map") then other = label end
      end
    end
    if other then
      click(other, nil, 30)
      local add = nil
      for label in pairs(last.rects) do if label:find("^ADD ") then add = label end end
      if add then click(add, nil, 30) end
      click("PAINT", nil, 10)
      pickSwatch(9)
      for by = 2, bh - 3 do
        for bx = bw - 3, 2, -1 do
          if not tx or true then
            if blockAt(bx, by) == pathId and by ~= usedRow and (bx + by) % 4 == 1 and stamped < 3 then
              local x, y = blockScreen(bx, by)
              if x then stamped = stamped + 1; mapClick(x, y, 22) end
            end
          end
        end
      end
      wait(20)
      click("MINE", nil, 25)
    end

    -- COLOURS: every palette mode, previewed live
    say("COLOURS  -  preview every colour mode", 110)
    local colBtn
    for label, list in pairs(last.rects) do
      local r = list[1]
      local ct = textAt("^COLOURS")
      if ct and math.abs(r[2] - ct[3] + 7) < 14 and r[1] > ct[2] then colBtn = label end
    end
    local okPF, PaletteFX = pcall(require, "src.render.PaletteFX")
    local startMode = okPF and PaletteFX.mode
    if colBtn then
      for _ = 1, 3 do
        local r = find(colBtn) or find(colBtn)
        if not r then break end
        moveTo(r[1] + r[3] / 2, r[2] + r[4] / 2, 16); wait(6); clickHere(); wait(40)
        for label, list in pairs(last.rects) do
          local ct = textAt("^COLOURS")
          if ct and math.abs(list[1][2] - ct[3] + 7) < 14 and list[1][1] > ct[2] then colBtn = label end
        end
      end
      -- back to how it was, the way the button itself applies a mode
      if okPF and startMode and PaletteFX.mode ~= startMode then
        PaletteFX.mode = startMode
        pcall(function() require("src.render.Assets").invalidate() end)
        pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
        pcall(function() Preview.forgetSprites() end)
        S.pv3DKey, S._pvCenteredFor = nil, S.mapId
      end
      local okP, PaletteFX = false, nil
      if okP and PaletteFX.MODES then
        for _ = 1, #PaletteFX.MODES do
          if PaletteFX.mode == startMode then break end
          local r = find(colBtn); if not r then break end
          mx, my = r[1] + r[3] / 2, r[2] + r[4] / 2
          clickHere(); wait(4)
          for label, list in pairs(last.rects) do
            local ct = textAt("^COLOURS")
            if ct and math.abs(list[1][2] - ct[3] + 7) < 14 and list[1][1] > ct[2] then colBtn = label end
          end
        end
      end
    end
    wait(30)
    Rec.stop()

    Rec.start("ed_crystal_walkable")
    click("x", function(r) return r[2] > 150 end, 20)
    -- the walkable overlay is drawn for the flat view: show it there
    camLock = nil
    click("2D", nil, 30)
    click("WALKABLE", nil, 30)
    wait(20)
    say("WALKABLE  -  paint where the player can go", 110)
    S.collMode = "wall"
    sweep(drawerLeft())
    local centerX, centerY = mapMiddle()
    local wv = cellsNear(centerX, centerY - 30, 30)
    table.sort(wv, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
    local wrow = wv[math.floor(#wv / 2)] and wv[math.floor(#wv / 2)][2]
    local n = 0
    for _, t in ipairs(wv) do
      if t[2] == wrow and n < 5 then n = n + 1; mapClick(t[3], t[4], n == 1 and 22 or 10) end
    end
    wait(40)
    -- the walls overlay off again before the 3D view
    click("SHOW WALLS", nil, 20)
    Rec.stop()

    Rec.start("ed_crystal_npcs")
    click("x", function(r) return r[2] > 150 end, 20)
    click("3D", nil, 20)
    click("NPCs & ITEMS", nil, 20)
    S.collShow = false
    fitVisible(30)
    say("NPCs & ITEMS  -  every person, sign and item", 110)
    wait(100)
    click("x", function(r) return r[2] > 150 end, 20)
    click("WARPS", function(r) return r[3] > 150 end, 40)
    say("WARPS  -  doors, stairs and map links", 100)
    wait(100)
    Rec.stop()

    Rec.start("ed_crystal_world")
    click("x", function(r) return r[2] > 150 end, 20)
    click("WORLD", nil, 30)
    say("WORLD  -  every map, stitched together", 120)
    wait(170)
    Rec.stop()

    -- ----------------------------------------- IMPORT A MAP FROM ANOTHER GAME
    local MapLoader = require("src.world.MapLoader")
    local function findBy(test)
      for label, list in pairs(last.rects) do
        for _, r in ipairs(list) do if test(label, r) then return r, label end end
      end
    end
    local function clickRect(r, settle)
      if not r then return false end
      moveTo(r[1] + r[3] / 2, r[2] + r[4] / 2, 22); wait(6); clickHere(); wait(settle or 20)
      return true
    end
    local function settleField(key, str) wait(4); if S[key] ~= str then S[key] = str end end

    Rec.start("ed_crystal_import")
    camLock = nil
    -- out of the world view first: it floats over everything
    if find("BACK TO MAP") then click("BACK TO MAP", nil, 25) end
    S.pvWorld = false
    -- the area list back out, for its NEW AREA button
    clickRect(findBy(function(l, r) return l == ">" and r[1] < 120 end), 25)
    click("+ NEW AREA", nil, 30)
    say("NEW AREA  -  or copy one from another game", 120)
    wait(20)
    -- one button per imported game, sharing the row: with many games the
    -- labels ellipsize away, so find RED's slot from the importer's own list
    local RMI = require("tools.map-editor.RomMapImport")
    local ready = RMI.readySources(S)
    local slot
    for i, r in ipairs(ready) do if r.version == "red" then slot = i end end
    local create, cancel = find("CREATE"), find("CANCEL")
    local copyT = textAt("^COPY A MAP FROM")
    if slot and create and cancel and copyT then
      local sc = Kit.scale or 1
      local left = create[1]
      local inner = (cancel[1] + cancel[3]) - left
      local n = #ready
      local bw = (inner - (n - 1) * 6 * sc) / n
      local bx = left + (slot - 1) * (bw + 6 * sc)
      local by = copyT[3] + 16 * sc
      clickRect({ bx, by, bw, 30 * sc }, 30)
    end
    if not S.romImport then
      local session = RMI.open(S, "red")
      if session then S.romImport, S.romQuery, S.romScroll, S.romRows, S.romRowsFor = session, "", 0, nil, nil end
      wait(10)
    end
    if clickField("rom-q") then typeText("cerulean_cave_1f", 4); settleField("romQuery", "cerulean_cave_1f") end
    wait(25)
    -- the list rows are wide presses under the search field
    local fieldR = last.fields["rom-q"]
    local rowR
    for _, r in ipairs(last.presses or {}) do
      if fieldR and math.abs(r[1] - fieldR[1]) < 4 and r[2] > fieldR[2] + fieldR[4]
         and (not rowR or r[2] < rowR[2]) then rowR = r end
    end
    local before = S.mapId
    say("CERULEAN CAVE  -  straight out of Pokemon Red", 130)
    clickRect(rowR, 40)
    local caveId = (S.mapId ~= before) and S.mapId or nil
    U.log("imported: " .. tostring(caveId) .. "  notice: " .. tostring(S.warpNotice))
    wait(60)
    Rec.stop()

    if caveId then
      Rec.start("ed_crystal_cave3d")
      say("Red's cave, inside Crystal  -  in 3D", 140)
      if not S.pv3DActive then click("3D", nil, 30) end
      S.pvDiag = false
      App.keypressed("home"); wait(10)
      fitVisible(30)
      camLock = nil
      orbit(150, 0.8, 14)
      wait(20)
      Rec.stop()

      -- ------------------------------------- A DOOR INTO IT FROM CERULEAN CITY
      Rec.start("ed_crystal_link")
      camLock = nil
      click("2D", nil, 25)
      say("LINK IT  -  a door in Cerulean City", 120)
      S.pvQuery = ""
      if clickField("pv-q") then typeText("Cerulean", 5); settleField("pvQuery", "Cerulean") end
      wait(15)
      local cityRow = textAt("^CeruleanCity$") or textAt("^CeruleanCity")
      if cityRow then moveTo(cityRow[2] + 60, cityRow[3] + 8, 20) end
      wait(4); ripple = { x = mx, y = my, t = 0 }
      Preview.select(S, "CERULEAN_CITY")
      S.pvDiag = false
      wait(40)
      S.newMapOpen = false
      -- ---- the cave mouth: painted into a wall the player can walk up to
      local cmap = MapLoader.load(S.data, "CERULEAN_CITY")
      local cdef = S.data.maps.CERULEAN_CITY
      local Map = require("src.world.Map")
      local cblocks = Map.blockArray(cdef) or {}
      local warpAt = {}
      for _, w in ipairs(cdef.warps or {}) do warpAt[w.x .. "," .. w.y] = true end
      local CAVE = 6     -- TilesetKanto: its bottom-left cell is a cave entrance
      click("x", function(r) return r[2] > 150 end, 15)
      -- the palette back on this map's own tileset, top of the list
      S.tileSource, S.tileScroll, S.tileNotice, S.tilePickSrc = nil, 0, nil, nil
      click("TILES", nil, 25)
      wait(10)
      sweep(drawerLeft())
      local cxm, cym = mapMiddle()
      local best, bestD
      for by = 1, cdef.height - 2 do
        for bx = 1, cdef.width - 2 do
          local cx, cy = bx * 2, by * 2 + 1          -- the block's bottom-left cell
          local solid = not cmap:isWalkableCell(cx, cy) and not cmap:isWalkableCell(cx + 1, cy)
            and not cmap:isWalkableCell(cx, cy - 1)
          local approach = cmap:isWalkableCell(cx, cy + 1) and cmap:isWalkableCell(cx + 1, cy + 1)
          local p = cellXY(cx, cy)
          if solid and approach and p and not warpAt[cx .. "," .. cy] then
            local dd = (p[1] - cxm) ^ 2 + (p[2] - cym) ^ 2
            if not bestD or dd < bestD then best, bestD = { bx, by }, dd end
          end
        end
      end
      local caveCell
      if best then
        say("PAINT A CAVE MOUTH  -  carved into the rocks", 120)
        click("BLOCK 32px", nil, 10)
        click("PAINT", nil, 10)
        S.tileScroll = 0
        wait(4)
        pickSwatch(CAVE)
        if S.tilePick ~= CAVE then U.log("picked " .. tostring(S.tilePick) .. ", wanted " .. CAVE); S.tilePick, S.tilePickSrc = CAVE, nil end
        local sx, sy = 0, 0
        for dy = 0, 1 do for dx = 0, 1 do
          local p = cellXY(best[1] * 2 + dx, best[2] * 2 + dy); sx, sy = sx + p[1] / 4, sy + p[2] / 4
        end end
        mapClick(sx, sy, 24)
        wait(40)
        caveCell = { best[1] * 2, best[2] * 2 + 1 }
      else
        U.log("no spot for a cave mouth")
      end
      -- ---- the warp, on the cave cell
      click("x", function(r) return r[2] > 150 end, 15)
      click("WARPS", function(r) return r[3] > 150 end, 25)
      S.newMapOpen = false
      sweep(drawerLeft())
      if caveCell then
        local p = cellXY(caveCell[1], caveCell[2])
        if p then mapClick(p[1], p[2], 22); wait(12) end
      end
      say("+ WARP  -  on the cave mouth, into Red's cave", 120)
      click("+ WARP", nil, 25)
      clickRect(find("-- none --"), 20)
      if clickField("wp-map") then typeText("cerulean_cave", 4); settleField("warpMapQuery", "cerulean_cave") end
      wait(20)
      clickRect(find(caveId, function(r) return r[1] > drawerLeft() end), 30)
      say("LINK BACK  -  and the cave's exit leads here", 120)
      click("LINK BACK", nil, 50)
      U.log("door: " .. tostring(S.warpNotice))
      wait(40)
      Rec.stop()
    end

    -- ------------------------------------------------------------ MAP PACKS
    Rec.start("ed_crystal_pack")
    say("EXPORT  -  every edit becomes a map pack mod", 130)
    click("EXPORT", function(r) return r[2] < 90 end, 30)
    U.log("export: " .. tostring(S.pvNotice))
    say("exported  ->  MAP_EDITS_CRYSTAL.zip   (drop it in mods/ to share)", 150)
    wait(60)
    wait(40)
    click("PACKS", function(r) return r[2] < 90 end, 30)
    say("PACKS  -  install, stack and share map packs", 130)
    wait(110)
    click("DONE", nil, 30)
    wait(20)
    Rec.stop()
  end

  -- =============================================================== PLATINUM
  if version == "platinum" then
    local Models = require("tools.map-editor.panels.Models")
    local MapLoader = require("src.world.MapLoader")
    -- typing into a field: the keystrokes, and the value itself in case the
    -- field took focus a frame late
    local function typeInto(field, key, str)
      clickField(field)
      for ch in str:gmatch(".") do App.textinput(ch); wait(6) end
      wait(4)
      -- a field that took focus a frame late missed some keys: settle it
      if S[key] ~= str then S[key] = str end
    end
    -- drawn is not the same as on screen: the drawer clips its body, so a
    -- control below the fold is reported but cannot be clicked
    local function onScreen(pattern)
      for _, t in ipairs(last.texts) do
        if t[1]:find(pattern) and t[3] > 160 and t[3] < H - 118 then return t end
      end
    end
    local function scrollDrawerTo(pattern)
      local dl = drawerLeft()
      if mx < dl then moveTo(dl + 300, H * 0.7, 14) end
      -- down first, then back up: the drawer keeps whatever scroll the last
      -- view of it left, which can be past the control as easily as short of it
      for _, dir in ipairs({ -1, 1 }) do
        for _ = 1, 16 do
          if onScreen(pattern) then return onScreen(pattern) end
          App.wheelmoved(0, dir); wait(5)
        end
      end
      return onScreen(pattern)
    end
    local function stepField(key, sign, times)
      local label = scrollDrawerTo("^" .. key .. ": ")
      if not label then U.log("no field " .. key); return end
      local r = find(sign, function(rr) return rr[1] > drawerLeft() and math.abs((rr[2] + rr[4] / 2) - (label[3] + 7)) < 9 end)
      if not r then U.log("no stepper for " .. key); return end
      moveTo(r[1] + r[3] / 2, r[2] + r[4] / 2, 20)
      for _ = 1, times do wait(9); clickHere() end
      wait(15)
    end

    Rec.start("ed_plat_browse")
    wait(30)
    if clickField("pv-q") then typeText("Jubilife", 6) end
    wait(20)
    local row = textAt("^Jubilife City") or textAt("Jubilife")
    if row then moveTo(row[2] + 60, row[3] + 8, 20) end
    wait(4); ripple = { x = mx, y = my, t = 0 }
    Preview.select(S, "C01")
    S.pvDiag = false
    wait(50)
    click("<", function(r) return r[1] < 450 end, 25)
    say("Jubilife City, drawn the way the cartridge draws it", 140)
    -- the view's own zoom, the rightmost + in the map header
    local function zoomPlus()
      local best
      for _, r in ipairs(last.rects["+"] or {}) do
        if r[2] < 300 and (not best or r[1] > best[1]) then best = r end
      end
      return best
    end
    for _ = 1, 1 do
      local r = zoomPlus()
      if r then moveTo(r[1] + r[3] / 2, r[2] + r[4] / 2, 22); wait(6); clickHere(); wait(40) end
    end
    wait(40)
    Rec.stop()

    Rec.start("ed_plat_place")
    click("3D PROPS", nil, 25)
    say("3D PROPS  -  the real Platinum models", 110)
    -- an open plaza: walkable, no props, near the middle of the city
    local map = MapLoader.load(S.data, S.mapId)
    local def = S.data.maps[S.mapId]
    local function open(cx, cy)
      for dy = -3, 3 do for dx = -3, 3 do
        local x, y = cx + dx, cy + dy
        if not (map:inBounds(x, y) and map:isWalkableCell(x, y)) then return false end
        local okP, hits = pcall(Models.propsInCell, S, x, y)
        if okP and hits and #hits > 0 then return false end
      end end
      return true
    end
    local spot
    local mcx, mcy = math.floor(def.width / 2), math.floor(def.height / 2)
    for r = 0, 24 do
      for dy = -r, r do for dx = -r, r do
        if not spot and (math.abs(dx) == r or math.abs(dy) == r) and open(mcx + dx, mcy + dy) then spot = { mcx + dx, mcy + dy } end
      end end
      if spot then break end
    end
    spot = spot or { mcx, mcy }
    -- centre the plaza in what the drawer leaves visible, gliding there
    camLock = nil
    local vx, vy, vw, vh = viewRect()
    local z = S.pvZoom or 2
    local visW = math.max(200, math.min(vx + vw, drawerLeft()) - vx)
    local tx = spot[1] * 16 + 8 - visW / (2 * z)
    local ty = spot[2] * 16 + 8 - Preview.groundUn(S, vh / (2 * z))
    local x0, y0 = S.pvCamX or tx, S.pvCamY or ty
    for i = 1, 40 do
      local t = ease(i / 40)
      S.pvCamX, S.pvCamY = x0 + (tx - x0) * t, y0 + (ty - y0) * t
      S._pvCenteredFor = S.mapId
      tick()
    end
    camLock = { flat = true, x = tx, y = ty, z = z }
    wait(15)

    -- pick a tree from the model list
    click("Add model...", nil, 8)
    pcall(function() require("tools.map-editor.BodyFill").reset(S, "models") end)
    wait(15)
    typeInto("model-q", "modelQuery", "tree")
    wait(25)
    local pickRow = textAt("%d+  tree01") or textAt("%d+  tree")
    if pickRow then moveTo(pickRow[2] + 80, pickRow[3] + 8, 22); wait(8); clickHere(); wait(20) end
    if not Models.armed(S) then
      local ground = map.renderer and map.renderer.gen4Ground
      local m = ground and (Models.catalogueMatching(ground, "tree01")[1] or Models.catalogueMatching(ground, "tree")[1])
      if m then Models.arm(S, m.member) end
      S.modelPickerOpen = false
    end
    say("click the map to place it", 100)
    sweep(drawerLeft())
    local targets = { { spot[1] - 2, spot[2] }, { spot[1] + 2, spot[2] - 1 }, { spot[1], spot[2] + 2 } }
    local placedIdx = {}
    for i, t in ipairs(targets) do
      local p = cellXY(t[1], t[2])
      if p then
        mapClick(p[1], p[2], i == 1 and 24 or 16)
        placedIdx[#placedIdx + 1] = S.modelPick
        wait(24)
      end
    end
    Models.disarm(S)
    wait(30)
    Rec.stop()

    Rec.start("ed_plat_change")
    -- select the first tree by clicking it
    local first = targets[1]
    local p1 = cellXY(first[1], first[2])
    if p1 then mapClick(p1[1], p1[2], 22); wait(20) end
    if placedIdx[1] and S.modelPick ~= placedIdx[1] then S.modelPick = placedIdx[1] end
    -- a new prop starts at y = 0; this city's ground is y = 32
    say("Y  -  lift it up onto the ground", 110)
    stepField("y", "+", 4)
    wait(20)
    say("X and Z  -  slide it across the plaza", 110)
    stepField("x", "+", 5)
    stepField("z", "+", 4)
    wait(20)
    say("CHANGE  -  swap it for any of 590 models", 120)
    local ch = scrollDrawerTo("^model: ")
    local chb = ch and find("Change...", function(r) return r[2] > 160 and r[2] < H - 60 end)
    if chb then
      S.modelQuery = ""
      moveTo(chb[1] + chb[3] / 2, chb[2] + chb[4] / 2, 22); wait(6); clickHere(); wait(6)
      -- the picker opens at the drawer's old scroll: back to its top
      pcall(function() require("tools.map-editor.BodyFill").reset(S, "models") end)
      wait(18)
      typeInto("model-q", "modelQuery", "pc")
      wait(25)
      local r2 = onScreen("%d+  pc$") or onScreen("%d+  pc")
      if r2 then moveTo(r2[2] + 80, r2[3] + 8, 22); wait(8); clickHere(); wait(40) end
    end
    say("SCALE  -  any size", 90)
    stepField("scaleX", "+", 3)
    stepField("scaleY", "+", 3)
    wait(40)
    do
      local vals = {}
      for _, k in ipairs({ "model", "x", "y", "z", "scaleX", "scaleY" }) do
        local t = textAt("^" .. k .. ": ")
        vals[#vals + 1] = t and t[1] or (k .. ":?")
      end
      U.log("prop now: " .. table.concat(vals, " | "))
    end
    -- and take one of the trees away again
    if placedIdx[2] then
      say("REMOVE  -  and take one away again", 120)
      -- back up to the list, pick the second tree's row, remove it
      for _ = 1, 16 do
        if onScreen("^%s*" .. placedIdx[2] .. "  model") and find("Remove prop", function(r) return r[2] > 160 end) then break end
        App.wheelmoved(0, 1); wait(5)
      end
      local rowT = onScreen("^%s*" .. placedIdx[2] .. "  model")
      if rowT then moveTo(rowT[2] + 120, rowT[3] + 8, 22); wait(6); clickHere(); wait(15) end
      if S.modelPick ~= placedIdx[2] then S.modelPick = placedIdx[2] end
      click("Remove prop", function(r) return r[2] > 160 end, 50)
    end
    wait(40)
    Rec.stop()
  end

  wait(6)
  Rec.finish()
  love.event.quit()
end
