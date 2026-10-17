-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- VOLTORB FLIP, HeartGold / SoulSilver's Game Corner machine (scrcmd 780
-- `CasinoGame`, pokeheartgold src/voltorb_flip/voltorb_flip.c). The rules are
-- src/pokemon/VoltorbFlipGame.lua; the art is Gen4VoltorbFlip's import; the
-- text is message bank 39.
--
-- The cartridge plays it on the TOUCH screen -- the board, the memo, the
-- text -- with the top screen showing the level, the coins and the tutorial
-- pages. With a second screen the board goes there and the top stays here;
-- on one screen the board is shown and SELECT holds the top screen up.
--
-- The flow is the app's workflows (VF.c 596-1335): the 50,000-coin gate, a new
-- round (with the level-up / level-down line), the Play / Game Info / Quit
-- menu, the board, a flip (suspense line, flip animation, sparkle or
-- explosion, payout count-up), the win, the coin award, the reveal and the
-- quit prompt -- and the memo, by touch or by buttons.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Game = require("src.pokemon.VoltorbFlipGame")

local V = {}
V.__index = V
V.isOpaque = true

local W, H = 256, 192
function V:uiSize() return W, H end
function V:wantsFillScale() return true end

local MEMO_BITS = { 1, 2, 4, 8 }     -- Voltorb, 1, 2, 3
local MEMO_TILES = { { 0, 0, 0x21 }, { 2, 0, 0x22 }, { 0, 2, 0x23 }, { 2, 2, 0x24 } }
local FACE_UP = { [1] = { 0x14, 0x74 }, [2] = { 0x11, 0x71 }, [3] = { 0x0E, 0x6E }, [4] = { 0x0B, 0x6B } }
local FACE_DOWN, BACK45, EDGE = 0x17, 0x77, 0x1A
local MEMO_RECTS = { { 200, 80 }, { 224, 80 }, { 200, 104 }, { 224, 104 }, { 224, 128 } }
local TOGGLE_ANIMS = { { 12, 8 }, { 15, 11 }, { 14, 10 }, { 13, 9 } } -- off / on

-- --------------------------------------------------------------- helpers

local function se(self, name)
  local data = self.game and self.game.data
  pcall(function() require("src.core.Sound").playSe(data, name) end)
end

local function text(self, n)
  local t = self.game.data and self.game.data.text
  local s = t and t[("TEXT_B0039_%05d"):format(n)] or ""
  return s
end

local function fill(self, s)
  local Commands = require("src.script.Commands")
  s = s:gsub("{ALN_CENTER}", "")
  return Commands.gen4Markup and Commands.gen4Markup(s, self.game) or s
end

local function buffers(self, ...)
  self.game.stringBuffers = self.game.stringBuffers or {}
  for i, v in ipairs({ ... }) do self.game.stringBuffers[i] = tostring(v) end
end

local function coins(self)
  return require("src.import.Gen4GameCorner").coins(self.game.save)
end

local function addCoins(self, n)
  require("src.import.Gen4GameCorner").add(self.game.save, n)
end

function V.available(game)
  local rec = game and game.data and game.data.gen4_voltorb_flip
  return rec ~= nil and rec.board ~= nil
end

function V.new(game, onDone)
  local rec = game.data and game.data.gen4_voltorb_flip or {}
  local self = setmetatable({ game = game, rec = rec, onDone = onDone, clock = 0,
                              st = Game.new(), cursor = 1, memoOpen = false, memoFocus = false,
                              memoButton = 1, sprites = {}, phase = "start" }, V)
  self.images = {}
  local function img(entry)
    if not (entry and entry.path) then return nil end
    if self.images[entry.path] == nil then
      local ok, i = pcall(Assets.image, entry.path)
      if ok and i then i:setFilter("nearest", "nearest") end
      self.images[entry.path] = (ok and i) or false
    end
    return self.images[entry.path] or nil
  end
  self.img = img
  self.board = img(rec.board)
  self.atlas = img(rec.mainAtlas)
  self.subAtlas = img(rec.subAtlas)
  self.quads = {}
  -- GameStats_AddScore(SCORE_EVENT_VOLTORB_FLIP) on every launch
  self:enter()
  return self
end

-- ---------------------------------------------------------------- tiles

function V:tile(atlas, id, x, y)
  if not atlas then return end
  local key = tostring(atlas) .. ":" .. id
  local q = self.quads[key]
  if not q then
    q = love.graphics.newQuad((id % 32) * 8, math.floor(id / 32) * 8, 8, 8, atlas:getDimensions())
    self.quads[key] = q
  end
  love.graphics.draw(atlas, q, x, y)
end

function V:card3(base, x, y)
  for i = 0, 8 do
    self:tile(self.atlas, base + math.floor(i / 3) * 32 + i % 3, x + (i % 3) * 8, y + math.floor(i / 3) * 8)
  end
end

-- a sprite animation: { anim, t, x, y, pal }
function V:sprite(name, anim, x, y, pal, sub)
  self.sprites[name] = { anim = anim, t = 0, x = x, y = y, pal = pal, sub = sub, shown = true }
end

function V:spriteDone(name)
  local s = self.sprites[name]
  if not s then return true end
  local set = s.sub and self.rec.subSprites or self.rec.mainSprites
  local an = set and set.anims and set.anims[s.anim + 1]
  if not an or an.mode ~= 1 then return false end
  local total = 0
  for _, f in ipairs(an.frames) do total = total + f.duration end
  return s.t >= total
end

function V:drawSprite(s)
  if not (s and s.shown) then return end
  local set = s.sub and self.rec.subSprites or self.rec.mainSprites
  local an = set and set.anims and set.anims[s.anim + 1]
  if not an or #an.frames == 0 then return end
  local total = 0
  for _, f in ipairs(an.frames) do total = total + math.max(1, f.duration) end
  local t = s.t
  if an.mode ~= 1 then t = t % total elseif t >= total then t = total - 1 end
  local cell = an.frames[#an.frames].cell
  for _, f in ipairs(an.frames) do
    if t < math.max(1, f.duration) then cell = f.cell; break end
    t = t - math.max(1, f.duration)
  end
  local entry
  if s.pal and set.palette and set.palette[s.pal] then entry = set.palette[s.pal][cell + 1] end
  entry = entry or (set.cells and set.cells[cell + 1])
  local image = entry and self.img(entry)
  if image then love.graphics.draw(image, s.x - (entry.ox or 0), s.y - (entry.oy or 0)) end
end

-- -------------------------------------------------------------- messages

-- say(n or string, after, opts): the bottom text box; pages break on the
-- cartridge's wait (0x0B) and scroll (0x0C) codes
function V:say(msg, after, opts)
  local s = type(msg) == "number" and fill(self, text(self, msg)) or tostring(msg)
  local pages = {}
  for page in (s .. "\011"):gmatch("(.-)[\011\012]") do
    if page:gsub("%s", "") ~= "" then pages[#pages + 1] = page end
  end
  if #pages == 0 then pages[1] = s end
  self.msg = { pages = pages, page = 1, chars = 0, after = after, small = opts and opts.small,
               noWait = opts and opts.noWait, menu = opts and opts.menu, yesno = opts and opts.yesno,
               menuIndex = 1 }
end

local function pressed(self, k) return self.game.input and self.game.input:wasPressed(k) end

function V:updateMessage()
  local m = self.msg
  local page = m.pages[m.page]
  if m.chars < #page then
    m.chars = math.min(#page, m.chars + 2)
    if pressed(self, "a") or pressed(self, "b") or self.tapped then m.chars = #page end
    return
  end
  if m.menu or m.yesno then
    local items = m.menu or { "YES", "NO" }
    if pressed(self, "up") then m.menuIndex = (m.menuIndex - 2) % #items + 1; se(self, "SEQ_SE_DP_SELECT") end
    if pressed(self, "down") then m.menuIndex = m.menuIndex % #items + 1; se(self, "SEQ_SE_DP_SELECT") end
    local pick
    if pressed(self, "a") then pick = m.menuIndex end
    if pressed(self, "b") then pick = #items end
    if self.tapped and self.tapX then
      local x0, y0 = self:menuOrigin(#items)
      if self.tapX >= x0 and self.tapY >= y0 then
        local i = math.floor((self.tapY - y0) / (m.yesno and 16 or 24)) + 1
        if items[i] then pick = i end
      end
    end
    if pick then
      se(self, "SEQ_SE_DP_SELECT")
      self.msg = nil
      if m.after then m.after(pick) end
    end
    return
  end
  if m.noWait then
    self.msg = nil
    if m.after then m.after() end
    return
  end
  if pressed(self, "a") or pressed(self, "b") or self.tapped then
    se(self, "SEQ_SE_DP_SELECT")
    if m.page < #m.pages then
      m.page, m.chars = m.page + 1, 0
    else
      self.msg = nil
      if m.after then m.after() end
    end
  end
end

function V:menuOrigin(n)
  local m = self.msg
  if m and m.yesno then return 200, 80 end
  return 136, (17 - 3 * n) * 8
end

-- ------------------------------------------------------------- the flow

function V:enter()
  if coins(self) >= Game.MAX_COINS then
    return self:say(14, function() self:close() end)
  end
  self:newRound()
end

function V:newRound()
  Game.newBoard(self.st)
  self.phase = "menu"
  self.cursor = 1
  self.revealAll = false
  local change = self.st.levelChange or 0
  local function menu()
    buffers(self, self.st.level)
    self:say(self.st.rounds == 0 and 15 or 16, function(pick)
      if pick == 1 then self:play()
      elseif pick == 2 then self:info()
      else self:close() end
    end, { menu = { fill(self, text(self, 17)), fill(self, text(self, 18)), fill(self, text(self, 19)) } })
  end
  if change > 0 then
    se(self, "SEQ_SE_GS_SLOT01")
    buffers(self, self.st.level)
    self:say(41, function()
      if not self.st.firstLevelUp then
        self.st.firstLevelUp = true
        self:say(42, menu)
      else menu() end
    end)
  elseif change < 0 then
    se(self, "SEQ_SE_GS_SLOT03")
    buffers(self, self.st.level)
    self:say(43, menu)
  else
    menu()
  end
end

function V:info()
  self:say(20, function(pick)
    local pages = { { 25, "howTo" }, { 26, "hint" }, { 27, "memo" } }
    local p = pages[pick]
    if not p then return self:newMenu() end
    self.topPage = p[2]
    if p[2] == "memo" then
      self:sprite("about1", 0, 72, 56, nil, true)
      self:sprite("about2", 0, 136, 40, nil, true)
      self.sprites.about2.t = -32
    end
    self:say(p[1], function()
      self.topPage = nil
      self.sprites.about1, self.sprites.about2 = nil, nil
      self:info()
    end)
  end, { menu = { fill(self, text(self, 21)), fill(self, text(self, 22)), fill(self, text(self, 23)),
                  fill(self, text(self, 24)) } })
end

function V:newMenu()
  buffers(self, self.st.level)
  self:say(self.st.rounds == 0 and 15 or 16, function(pick)
    if pick == 1 then self:play()
    elseif pick == 2 then self:info()
    else self:close() end
  end, { menu = { fill(self, text(self, 17)), fill(self, text(self, 18)), fill(self, text(self, 19)) } })
end

function V:play()
  self.phase = "board"
  self.focus = 1
  self.flips = {}
end

function V:close()
  if self.closed then return end
  self.closed = true
  local G = self.game
  if G.stack:top() == self then G.stack:pop() end
  if self.onDone then self.onDone() end
end

-- the flip of one card
function V:flip(id)
  local st = self.st
  if st.flipped[id] then se(self, "SEQ_SE_DP_BOX03") return end
  self.phase = "flipping"
  self.sprites.effect = nil
  local function go()
    se(self, "SEQ_SE_GS_PANERU_MEKURU")
    self.anim = { ids = { id }, step = 0, t = 0, up = true, after = function() self:afterFlip(id) end }
  end
  if Game.risky(st, id) then
    se(self, "SEQ_ME_CARDGAME1")
    self:say(29, go, { small = true })
  else
    go()
  end
end

function V:afterFlip(id)
  local st = self.st
  local first = st.payout == 0
  local v = Game.flip(st, id)
  local x, y = ((id - 1) % 5) * 32 + 20, math.floor((id - 1) / 5) * 32 + 20
  if v == Game.VOLTORB then
    self:sprite("effect", 1, x, y)
    se(self, "SEQ_SE_GS_COIN_HAZURE")
    self.wait = { sprite = "effect", after = function()
      se(self, "SEQ_ME_CARDGAME2")
      self.payoutShown = 0
      self:say(32, function() self:reveal() end, { small = true })
    end }
    return
  end
  self:sprite("effect", 0, x, y)
  local function finish()
    if st.outcome == Game.WON then return self:win() end
    self.phase = "board"
  end
  if v == 1 and not first then
    self.payoutShown = st.payout
    return finish()
  end
  if first then buffers(self, v, v); self:say(30, nil, { small = true, stay = true })
  else buffers(self, v, st.payout); self:say(31, nil, { small = true, stay = true }) end
  self.msg.after = function() finish() end
  self.count = { to = st.payout }
end

function V:win()
  se(self, "SEQ_ME_MUSHITORI3")
  self:say(33, function()
    self.st.outcome = Game.WON
    self:award()
  end)
end

function V:award()
  local n = self.st.payout
  buffers(self, self.game.save.player and self.game.save.player.name or "", n)
  self.awarding = { left = n, t = 0 }
  se(self, "SEQ_SE_GS_COIN_PAYOUT_ONE")
  self:say(40, function()
    if self.awarding then addCoins(self, self.awarding.left); self.awarding = nil end
    self:reveal()
  end)
end

function V:quit()
  local st = self.st
  buffers(self, st.payout)
  self:say(st.payout == 0 and 37 or 34, function(pick)
    if pick == 1 then
      st.outcome = Game.QUIT
      if st.payout > 0 then self:award() else self:reveal() end
    else
      self.phase = "board"
    end
  end, { yesno = true })
end

-- REVEAL_BOARD: every card face up, a press, then the board clears
function V:reveal()
  self.phase = "reveal"
  self.memoOpen = false
  local ids = {}
  for id = 1, 25 do if not self.st.flipped[id] then ids[#ids + 1] = id end end
  se(self, "SEQ_SE_GS_PANERU_MEKURU")
  self.anim = { ids = ids, step = 0, t = 0, up = true, after = function()
    self.revealAll = true
    self.waitPress = function()
      se(self, "SEQ_SE_GS_PANERU_MEKURU")
      self.anim = { ids = "all", step = 0, t = 0, up = false, after = function()
        Game.endRound(self.st)
        self.revealAll = false
        self.payoutShown = 0
        if coins(self) >= Game.MAX_COINS then
          return self:say(14, function() self:close() end)
        end
        self:newRound()
      end }
    end
  end }
end

-- --------------------------------------------------------------- update

function V:cardAt(x, y)
  for id = 1, 25 do
    local cx, cy = 8 + ((id - 1) % 5) * 32, 8 + math.floor((id - 1) / 5) * 32
    if x >= cx and x < cx + 24 and y >= cy and y < cy + 24 then return id end
  end
  return nil
end

function V:moveFocus(dir)
  local f = self.focus or 1
  if f <= 25 then
    local r, c = math.floor((f - 1) / 5), (f - 1) % 5
    if dir == "up" then r = (r - 1) % 5 elseif dir == "down" then r = (r + 1) % 5 end
    if dir == "left" then
      if c == 0 then self.lastRow = r; f = r <= 2 and 26 or 27 else c = c - 1 end
    elseif dir == "right" then
      if c == 4 then self.lastRow = r; f = r <= 2 and 26 or 27 else c = c + 1 end
    end
    if f <= 25 then f = r * 5 + c + 1 end
  else
    local r = self.lastRow or 0
    if dir == "up" then f = 26 elseif dir == "down" then f = 27
    elseif dir == "left" then f = r * 5 + 5 elseif dir == "right" then f = r * 5 + 1 end
  end
  if f ~= self.focus then se(self, "SEQ_SE_DP_SELECT") end
  self.focus = f
end

function V:toggleMemo(open)
  self.memoOpen = open
  self.memoFocus = false
  se(self, "SEQ_SE_DP_CARD2")
  self:sprite("memoPanel", open and 20 or 21, 128, 96)
end

function V:boardInput()
  local st = self.st
  if self.memoFocus then
    local b = self.memoButton
    if pressed(self, "right") and b % 2 == 1 and b < 5 then b = b + 1 end
    if pressed(self, "left") and b % 2 == 0 and b < 5 then b = b - 1 end
    if pressed(self, "down") then b = math.min(5, b + 2) end
    if pressed(self, "up") then b = (b == 5) and (self.lastMemoButton or 4) or math.max(1, b - 2) end
    if b ~= self.memoButton then se(self, "SEQ_SE_DP_SELECT"); if b <= 4 then self.lastMemoButton = b end end
    self.memoButton = b
    if pressed(self, "a") then
      if b == 5 then self.memoFocus = false; se(self, "SEQ_SE_DP_BUTTON3")
      elseif Game.toggleMemo(st, self.focus, MEMO_BITS[b]) then se(self, "SEQ_SE_DP_BOX01")
      else se(self, "SEQ_SE_DP_BOX03") end
    elseif pressed(self, "b") then self.memoFocus = false; se(self, "SEQ_SE_DP_BUTTON3")
    elseif pressed(self, "x") then self:toggleMemo(false) end
    return
  end
  for _, d in ipairs({ "up", "down", "left", "right" }) do
    if pressed(self, d) then self:moveFocus(d) end
  end
  if self.tapped and self.tapX then
    local x, y = self.tapX, self.tapY
    local id = self:cardAt(x, y)
    if self.memoOpen then
      for i = 1, 5 do
        local r = MEMO_RECTS[i]
        if x >= r[1] and x < r[1] + 24 and y >= r[2] and y < r[2] + 24 then
          if i == 5 then self:toggleMemo(false)
          elseif Game.toggleMemo(st, self.focus or 1, MEMO_BITS[i]) then se(self, "SEQ_SE_DP_BOX01")
          else se(self, "SEQ_SE_DP_BOX03") end
          return
        end
      end
      if id then self.focus = id; return end
    elseif id then
      self.focus = id
      return self:flip(id)
    end
    if x >= 192 and y >= 8 and y < 72 then self:toggleMemo(not self.memoOpen); return end
    if x >= 192 and y >= 160 then se(self, "SEQ_SE_DP_DECIDE"); return self:quit() end
    return
  end
  if pressed(self, "x") then
    if (self.focus or 1) > 25 then self.focus = 1 end
    se(self, "SEQ_SE_DP_SELECT")
    return self:toggleMemo(not self.memoOpen)
  end
  if pressed(self, "b") then
    if self.memoOpen then return self:toggleMemo(false) end
    se(self, "SEQ_SE_DP_DECIDE")
    return self:quit()
  end
  if pressed(self, "a") then
    local f = self.focus or 1
    if f == 26 then
      self.focus = 1
      self:toggleMemo(true)
      self.memoFocus = true
      return
    elseif f == 27 then
      se(self, "SEQ_SE_DP_DECIDE")
      return self:quit()
    end
    if self.memoOpen then
      self.memoFocus = true
      return
    end
    return self:flip(f)
  end
end

function V:update()
  if self.closed then return end
  self.clock = self.clock + 1
  for _, s in pairs(self.sprites) do s.t = s.t + 1 end
  -- the top screen held up on one screen
  self.peek = self.game.input and self.game.input.isDown and self.game.input:isDown("select") or (os.getenv and os.getenv("VFTOP") ~= nil)
  -- a flip in progress: one step every frame where frame % 3 ~= 0
  local a = self.anim
  if a then
    a.t = a.t + 1
    if a.t % 3 ~= 0 then a.step = a.step + 1 end
    if a.step >= 4 then
      self.anim = nil
      if a.after then a.after() end
    end
    self.tapped = nil
    return
  end
  if self.wait then
    if self:spriteDone(self.wait.sprite) then
      local w = self.wait
      self.wait = nil
      w.after()
    end
    self.tapped = nil
    return
  end
  -- the payout counting up (1 a frame, OKOZUKAI every fourth)
  if self.count then
    self.payoutShown = math.min(self.count.to, (self.payoutShown or 0) + 1)
    if self.payoutShown % 4 == 0 then se(self, "SEQ_SE_GS_OKOZUKAI") end
    if pressed(self, "a") or self.tapped then self.payoutShown = self.count.to end
    if self.payoutShown >= self.count.to then self.count = nil; se(self, "SEQ_SE_GS_OKOZUKAI") end
    self.tapped = nil
    return
  end
  -- the coins paid out one a frame
  local aw = self.awarding
  if aw and self.msg and self.msg.chars >= #self.msg.pages[self.msg.page] then
    local step = 1
    if pressed(self, "a") or self.tapped or coins(self) >= Game.MAX_COINS then step = aw.left end
    step = math.min(step, aw.left)
    addCoins(self, step)
    aw.left = aw.left - step
    self.payoutShown = aw.left
    aw.t = aw.t + 1
    if aw.t % 4 == 0 then se(self, "SEQ_SE_GS_COIN_PAYOUT_ONE") end
    if aw.left <= 0 then
      self.awarding = nil
      se(self, "SEQ_SE_GS_COIN_PAYOUT_LAST")
    end
    self.tapped = nil
    return
  end
  if self.msg then
    self:updateMessage()
    self.tapped = nil
    return
  end
  if self.waitPress then
    if pressed(self, "a") or pressed(self, "b") or self.tapped then
      local f = self.waitPress
      self.waitPress = nil
      f()
    end
    self.tapped = nil
    return
  end
  if self.phase == "board" then self:boardInput() end
  self.tapped = nil
end

-- -------------------------------------------------------------- pointer

function V:boardPoint(px, py)
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if okS then
    local mode = SS.mode(self.game)
    if require("src.ui.SecondScreen").separateMode(mode) and not SS.stowed(self.game) then
      return SS.toLocal(self.game, px, py)
    end
  end
  local r = require("src.render.Renderer").uiPresentation
  if not r or px < r.x or py < r.y or px >= r.x + r.w or py >= r.y + r.h then return nil end
  return (px - r.x) / r.scaleX, (py - r.y) / r.scaleY
end

function V:touchpressed(id, px, py)
  local x, y = self:boardPoint(px, py)
  if not x then return false end
  self.tapped, self.tapX, self.tapY = true, x, y
  return true
end

function V:mousepressed(x, y, button)
  if button == 1 then return self:touchpressed("mouse", x, y) end
end

-- -------------------------------------------------------------- drawing

function V:dualScreen()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS then return false end
  local mode = SS.mode(self.game)
  return require("src.ui.SecondScreen").separateMode(mode) and not SS.stowed(self.game), SS
end

function V:drawBoard()
  local g = love.graphics
  local st = self.st
  local bd = self.rec.backdrop
  g.clear(bd and bd[1] / 255 or 0.2, bd and bd[2] / 255 or 0.7, bd and bd[3] / 255 or 0.5, 1)
  g.setColor(1, 1, 1, 1)
  if self.board then g.draw(self.board, 0, 0) end
  -- the cards
  local a = self.anim
  for id = 1, 25 do
    local x, y = 8 + ((id - 1) % 5) * 32, 8 + math.floor((id - 1) / 5) * 32
    local v = st.cards[id] or 1
    local up = st.flipped[id] or self.revealAll
    local base = up and FACE_UP[v][1] or FACE_DOWN
    if a then
      local mine = a.ids == "all"
      if not mine then for _, i in ipairs(a.ids) do if i == id then mine = true end end end
      if mine and (a.ids ~= "all" or up) then
        local seq = a.up and { BACK45, EDGE, FACE_UP[v][2], FACE_UP[v][1] }
                         or { FACE_UP[v][2], EDGE, BACK45, FACE_DOWN }
        base = seq[math.min(4, a.step + 1)]
      end
    end
    self:card3(base, x, y)
    -- the memo marks, at the card's corners
    if not up then
      for i, m in ipairs(MEMO_TILES) do
        if Game.hasMemo(st, id, MEMO_BITS[i]) then
          self:tile(self.atlas, m[3], x + m[1] * 8, y + m[2] * 8)
        end
      end
    end
  end
  -- the totals along the rows and columns
  if self.phase ~= "menu" or st.rounds > 0 or true then
    for i = 0, 4 do
      local p, v = st.rowPoints and st.rowPoints[i] or 0, st.rowV and st.rowV[i] or 0
      if self.phase == "menu" then p, v = 0, 0 end
      self:tile(self.atlas, math.floor(p / 10) + 1, 176, 8 + 32 * i)
      self:tile(self.atlas, p % 10 + 1, 184, 8 + 32 * i)
      self:tile(self.atlas, v + 203, 184, 16 + 32 * i)
      self:tile(self.atlas, v + 235, 184, 24 + 32 * i)
      p, v = st.colPoints and st.colPoints[i] or 0, st.colV and st.colV[i] or 0
      if self.phase == "menu" then p, v = 0, 0 end
      self:tile(self.atlas, math.floor(p / 10) + 1, 16 + 32 * i, 168)
      self:tile(self.atlas, p % 10 + 1, 24 + 32 * i, 168)
      self:tile(self.atlas, v + 203, 24 + 32 * i, 176)
      self:tile(self.atlas, v + 235, 24 + 32 * i, 184)
    end
  end
  -- the memo / quit buttons and their labels
  self:drawSprite({ anim = 5, t = self.clock, x = 224, y = 40, shown = true })
  self:drawSprite({ anim = 2, t = self.clock, x = 224, y = 176, shown = true })
  g.setColor(0.13, 0.13, 0.13, 1)
  local label = fill(self, text(self, self.memoOpen and 7 or 6))
  local ly = 32
  for line in (label .. "\n"):gmatch("(.-)\n") do
    Font.draw(line, 224 - math.floor(Font.width(line) / 2), ly); ly = ly + 16
  end
  local q = fill(self, text(self, 8))
  Font.draw(q, 224 - math.floor(Font.width(q) / 2), 168)
  g.setColor(1, 1, 1, 1)
  -- the memo panel and its toggles
  if self.memoOpen then
    self:drawSprite(self.sprites.memoPanel)
    local f = self.focus or 1
    for i = 1, 4 do
      local on = f <= 25 and Game.hasMemo(st, f, MEMO_BITS[i])
      local r = MEMO_RECTS[i]
      self:drawSprite({ anim = TOGGLE_ANIMS[i][on and 2 or 1], t = 0, x = r[1], y = r[2], shown = true })
    end
    self:drawSprite({ anim = 16, t = 0, x = 224, y = 128, shown = true })
    if self.memoFocus then
      local r = MEMO_RECTS[self.memoButton]
      self:drawSprite({ anim = 18, t = self.clock, x = r[1], y = r[2], pal = 4, shown = true })
    end
  end
  -- the cursor
  if self.phase == "board" and not self.msg then
    local f = self.focus or 1
    local x, y, an = 224, 40, 7
    if f <= 25 then
      x, y = 8 + ((f - 1) % 5) * 32, 8 + math.floor((f - 1) / 5) * 32
      an = self.memoFocus and 24 or (self.memoOpen and 23 or 18)
    elseif f == 27 then x, y, an = 224, 176, 4 end
    self:drawSprite({ anim = an, t = self.clock, x = x, y = y, pal = self.memoOpen and 4 or 2, shown = true })
  end
  self:drawSprite(self.sprites.effect)
  self:drawMessage()
end

function V:drawMessage()
  local m = self.msg
  if not m then return end
  local g = love.graphics
  local page = m.pages[m.page] or ""
  local shown = page:sub(1, m.chars)
  -- DimLayersExceptBG3: the board darkens (brightness -8) under the menus,
  -- the prompts and the level lines; the in-game captions leave it lit
  if not m.small then
    g.setColor(0, 0, 0, 0.5)
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end
  if m.small then
    Font.drawBox(1, 20, 29, 3)
  else
    Font.drawBox(1, 18, 29, 6)
  end
  g.setColor(0.13, 0.13, 0.13, 1)
  local y = m.small and 168 or 152
  for line in (shown .. "\n"):gmatch("(.-)\n") do
    Font.draw(line, 16, y); y = y + 16
  end
  g.setColor(1, 1, 1, 1)
  if (m.menu or m.yesno) and m.chars >= #page then
    local items = m.menu or { "YES", "NO" }
    local x0, y0 = self:menuOrigin(#items)
    local step = m.yesno and 16 or 24
    Font.drawBox(x0 / 8 - 1, y0 / 8 - 1, (m.yesno and 6 or 13) + 2, #items * step / 8 + 2)
    g.setColor(0.13, 0.13, 0.13, 1)
    for i, it in ipairs(items) do
      local yy = y0 + (i - 1) * step + (step - 16) / 2
      -- the theme's own cursor glyph, as ChoiceBox draws it
      if i == m.menuIndex then
        local Theme = require("src.ui.Theme")
        if Theme.cursor then Font.drawCode(Theme.cursor, x0, yy) end
      end
      Font.draw(it, x0 + 10, yy)
    end
    g.setColor(1, 1, 1, 1)
  end
end

-- the top screen: the level, the two coin counters, or a tutorial page
function V:drawTop()
  local g = love.graphics
  g.clear(0, 0, 0, 1)
  g.setColor(1, 1, 1, 1)
  local top = self.rec.top or {}
  local page = self.topPage
  local image = self.img(top[page or "coins"] or top.coins)
  if image then g.draw(image, 0, 0) end
  g.setColor(0.13, 0.13, 0.13, 1)
  local function center(s, y)
    s = fill(self, s)
    for line in (s .. "\n"):gmatch("(.-)\n") do
      Font.draw(line, 128 - math.floor(Font.width(line) / 2), y); y = y + 16
    end
  end
  if not page then
    buffers(self, self.st.level)
    -- the title band is the light ink on the dark green
    g.setColor(1, 1, 1, 1)
    center(text(self, 0), 8)
    center(text(self, 1), 24)
    g.setColor(0.13, 0.13, 0.13, 1)
    Font.draw(fill(self, text(self, 2)), 104, 48)
    Font.draw(fill(self, text(self, 3)), 104, 80)
    buffers(self, self.game.save.player and self.game.save.player.name or "")
    local s4 = fill(self, text(self, 4))
    local y = 112
    for line in (s4 .. "\n"):gmatch("(.-)\n") do Font.draw(line, 8, y); y = y + 16 end
    y = 152
    for line in (fill(self, text(self, 5)) .. "\n"):gmatch("(.-)\n") do Font.draw(line, 8, y); y = y + 16 end
    g.setColor(1, 1, 1, 1)
    -- the coin counters: five digits, 2 x 4 tiles each, 0xA0 + 2d
    local function digits(n, ty)
      n = math.max(0, math.min(99999, math.floor(n)))
      local s = ("%05d"):format(n)
      for i = 1, 5 do
        local d = tonumber(s:sub(i, i))
        for r = 0, 3 do
          for c = 0, 1 do
            self:tile(self.subAtlas, 0xA0 + 2 * d + r * 32 + c, (21 + (i - 1) * 2 + c) * 8, (ty + r) * 8)
          end
        end
      end
    end
    digits(coins(self), 14)
    digits(self.payoutShown or self.st.payout or 0, 19)
  elseif page == "memo" then
    g.setColor(1, 1, 1, 1)
    self:drawSprite(self.sprites.about1)
    self:drawSprite(self.sprites.about2)
  end
  g.setColor(1, 1, 1, 1)
end

function V:draw()
  local dual, SS = self:dualScreen()
  if dual then
    self:drawTop()
    SS.draw(self.game, function() self:drawBoard() end)
  elseif self.peek then
    self:drawTop()
  else
    self:drawBoard()
  end
end

return V
