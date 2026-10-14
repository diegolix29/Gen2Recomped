-- THE SUPER CONTEST, RUN (`runcontestapplication`): the rounds of
-- FieldTask_RunContest in order -- Visual, its scoring, Dance, Acting, final
-- scoring -- for the competition type the contest was made with
-- (src/pokemon/Gen4Contest.lua holds the rules and the numbers).
--
-- Built: the Visual round's two scores (the condition score's stars and the
-- dress-up score's hearts, from ov17_0223F374 / ov17_02252A70, opponents
-- wearing their contest_data dress-ups for the drawn theme), the Dance
-- competition (src/ui/Gen4ContestDance.lua, danced to the song), the Acting
-- competition (src/ui/Gen4ContestActing.lua, played turn by turn), and the
-- final scoring's bars and placement.
-- Before the Visual round, the player's sixty seconds of dress-up
-- (src/ui/Gen4ContestDressUp.lua, overlay022) -- what ends up ON the Pokemon
-- is what the dress-up score counts, and it is worn on stage.
--
-- THE PICTURES ARE THE CARTRIDGE'S (src/import/Gen4ContestArt.lua): the
-- Visual round on its stage (contest_bg 23/22, ov17_0223CB1C) with each entry
-- brought on in entry order and announced in bank 209's words; the results on
-- ov17_02250744's board (27/25) with the bars on its 192-pixel tracks and
-- bank 218's announcements; the audience (19/20) on the bottom screen when
-- there is one. Messages go in pl_winframe's window, where the overlay puts
-- them (tile 2, 19, 27 x 4).
--
-- THE SOUNDS are the cartridge's: the Visual round's door and applause
-- (ov17_0223CB1C), each entry's curtain, spotlight and rating pops
-- (ov17_02247A48 / ov17_022476F8); the results board's applause, each
-- round's bars rising (ov17_02252858) and the places stamped
-- (ov17_02252580), then the winner's applause (ov17_0225266C). The
-- fanfare and results songs are BGM, not effects, and are not played here.

local Font = require("src.render.Font")
local C = require("src.pokemon.Gen4Contest")
local T = require("src.import.Gen4Text")
local Art = require("src.ui.Gen4ContestArt")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

-- a cartridge sound effect (src/core/Sound.playSe), nothing when headless
local function se(self, name, opts)
  local data = self.game and self.game.data or self.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playSe and data then return Sound.playSe(data, name, opts) end
end

local function stopSe(self, name)
  local data = self.game and self.game.data or self.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.stopSe and data then return Sound.stopSe(data, name) end
end

-- a sound (or a stop, when `stop`) `delay` frames from now
function Screen:later(delay, name, stop)
  self.timers[#self.timers + 1] = { at = self.clock + delay, name = name, stop = stop }
end

function Screen:tickSounds()
  self.clock = self.clock + 1
  for i = #self.timers, 1, -1 do
    local t = self.timers[i]
    if self.clock >= t.at then
      table.remove(self.timers, i)
      if t.stop then stopSe(self, t.name) else se(self, t.name) end
    end
  end
end

-- the sounds a message page brings with it, the first frame it is up
function Screen:shown(item)
  local page, c = self.pages[self.page], self.c
  if page == "visual" then
    if item.stage then
      -- ov17_02249014: the curtain (30 frames, or at once on A);
      -- ov17_02247C5C: the spotlight; ov17_02247F8C: applause, then after
      -- 15 frames a pop (ov17_022477B8) every 4 for each star and heart,
      -- and applause again once they are all up
      self.sawEntry = true
      se(self, "SEQ_SE_DP_CON_020")
      self:later(4, "SEQ_SE_DP_CON_019")
      self:later(8, "SEQ_SE_DP_CON_007")
      local n = C.stars(c, item.rate) + C.hearts(c, item.rate)
      for k = 0, n - 1 do self:later(8 + 15 + 4 * k, "SEQ_SE_DP_CON_003") end
      self:later(n > 0 and 8 + 4 * n + 12 or 8, "SEQ_SE_DP_CON_007")
    elseif self.sawEntry then
      -- ov17_0223D99C: the round's closing applause
      self.sawEntry = false
      se(self, "SEQ_SE_DP_CON_007")
    end
  elseif page == "final" then
    if item.final then
      -- ov17_02252580: the four places stamped, fourth to first, 32 frames
      -- apart (ov17_0225131C); ov17_0225266C: the winner's applause
      for k = 0, 3 do self:later(1 + 32 * k, "SEQ_SE_DP_DECIDE") end
      self:later(1 + 32 * 4, "SEQ_SE_DP_CON_007")
    elseif item.reveal then
      -- ov17_02252858: the drum roll, 45 frames, then the bars' rising
      -- sound while they grow a pixel a frame, and the cymbal at the top
      se(self, "SEQ_SE_DP_CON_033")
      local longest = 0
      for id = 0, 3 do longest = math.max(longest, c.bars[id][item.reveal] or 0) end
      if longest > 0 then
        self:later(46, "SEQ_SE_DP_CON_034")
        self:later(46 + longest + 1, "SEQ_SE_DP_CON_032")
        self:later(46 + longest + 1, "SEQ_SE_DP_CON_034", true)
      end
    end
  end
end

Screen.VISUAL_TEXT = 209       -- contest_visual_competition
Screen.RESULTS_TEXT = 218      -- contest_results

function Screen:uiSize() return 256, 192 end
function Screen:wantsFillScale() return true end

local function name(e, data)
  if e.mon and e.mon.nickname then return e.mon.nickname end
  local def = data.pokemon and data.pokemon[e.mon and e.mon.species]
  return def and def.name or "?"
end

function Screen.new(game, contest, onDone)
  local self = setmetatable({ game = game, c = contest, onDone = onDone, page = 1, queue = {},
    timers = {}, clock = 0 }, Screen)
  local t = contest.competition
  local visual = t == C.OFFICIAL or t == C.ACTING_ONLY_UNK0 or t == C.DANCE_ONLY_UNK1
      or t == C.VISUAL or t == C.PRACTICE_VISUAL
  local dance = t == C.OFFICIAL or t == C.DANCE_ONLY_UNK1 or t == C.DANCE or t == C.PRACTICE_DANCE
  local acting = t == C.OFFICIAL or t == C.ACTING_ONLY_UNK0 or t == C.ACTING or t == C.PRACTICE_ACTING
  self.rounds = { visual = visual, dance = dance, acting = acting }
  self.pages = {}
  if visual then
    -- the dress-up first, when the cache has its art; the Visual round is
    -- scored on arrival, once the player's Accessories are known
    if (game.data.gen4_dressup or {}).accessories then self.pages[#self.pages + 1] = "dressup" end
    self.pages[#self.pages + 1] = "visual"
  end
  for id = 0, 3 do
    contest.scores[id].dance = 0
    contest.scores[id].acting = 0
  end
  self.hadDance = dance
  if dance then self.pages[#self.pages + 1] = "dance" end
  if acting then self.pages[#self.pages + 1] = "acting" end
  self.pages[#self.pages + 1] = "final"
  self:enter()
  return self
end

-- a cartridge line, its {STRVAR_1 kind slot pad} slots filled from `slots`
-- (by slot, from zero), split into its pages; `extra` rides on every page
function Screen:say(bank, index, slots, extra)
  local values = {}
  for slot = 0, 4 do values[slot + 1] = slots and slots[slot] or "" end
  T.buffer(self.game, (table.unpack or unpack)(values))
  local text = T.resolve(self.game.data, bank, index, self.game)
  if not text then return end
  for page in (text .. "\f"):gmatch("([^\v\f\r]*)[\v\f\r]") do
    page = page:gsub("^%s+", ""):gsub("%s+$", "")
    if page ~= "" then
      local item = { text = page }
      for k, v in pairs(extra or {}) do item[k] = v end
      self.queue[#self.queue + 1] = item
    end
  end
end

-- what a page needs on arrival
function Screen:enter()
  local page = self.pages[self.page]
  local c, data = self.c, self.game.data
  self.queue, self.stage, self.revealed, self.final = {}, nil, 0, false
  self.timers, self.shownItem = {}, nil
  if page == "dressup" then
    self.dressup = require("src.ui.Gen4ContestDressUp").new(self.game, c, {
      onDone = function() self.dressupDone = true end,
    })
  elseif page == "visual" then
    -- ov17_0223CB1C: the door as the stage opens, the applause once it has
    -- faded in
    se(self, "SEQ_SE_DP_DOOR_OPEN")
    self:later(1, "SEQ_SE_DP_CON_007")
    C.scoreVisual(c, data)
    -- ov17_0223CB1C: the MC's welcome, then each entry in entry order
    -- (entry n is contestant 3 - n), then the next round's call
    self:say(Screen.VISUAL_TEXT, C.isPractice(c.competition) and 17 or 0)
    for entry = 0, 3 do
      local id = C.entryToId(entry)
      local e = c.contestants[id]
      self:say(Screen.VISUAL_TEXT, 1 + entry, { [0] = e.trainer or "", name(e, data) }, { stage = id, rate = id })
    end
    if self.rounds.dance then self:say(Screen.VISUAL_TEXT, 5) end
  elseif page == "dance" then
    self.dance = require("src.ui.Gen4ContestDance").new(self.game, c, {
      onDone = function() self.danceDone = true end,
    })
  elseif page == "acting" then
    self.acting = require("src.ui.Gen4ContestActing").new(self.game, c, {
      hadDance = self.hadDance,
      onDone = function() self.actingDone = true end,
    })
  elseif page == "final" then
    -- ContestFinalScoring_Init: the applause as the board comes up
    se(self, "SEQ_SE_DP_CON_007")
    C.place(c)
    -- ov17_02250744: the announcement, each round's bars in turn, the winner
    self:say(Screen.RESULTS_TEXT, 0)
    local round = 0
    for _, r in ipairs({ { "visual", 1 }, { "dance", 2 }, { "acting", 3 } }) do
      round = round + 1
      if self.rounds[r[1]] then self:say(Screen.RESULTS_TEXT, r[2], nil, { reveal = round }) end
    end
    local w = C.winner(c)
    local e = c.contestants[w]
    self:say(Screen.RESULTS_TEXT, 4, { [0] = tostring(C.idToEntry(w) + 1), e.trainer or "", name(e, data) },
      { reveal = 3, final = true })
  end
end

function Screen:advance()
  if self.pages[self.page] == "visual" and self.sawEntry then
    -- ov17_0223D99C's applause, with no next-round call to carry it
    self.sawEntry = false
    se(self, "SEQ_SE_DP_CON_007")
  end
  if self.pages[self.page] == "final" then stopSe(self, "SEQ_SE_DP_CON_034") end
  self.page = self.page + 1
  if self.page > #self.pages then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
    return
  end
  self:enter()
end

function Screen:update(dt)
  local input = self.game.input
  if self.pages[self.page] == "dressup" and self.dressup then
    if self.dressupDone then
      self.dressup = nil
      return self:advance()
    end
    return self.dressup:update(dt)
  end
  if self.pages[self.page] == "dance" and self.dance then
    if self.danceDone then
      self.dance = nil
      return self:advance()
    end
    return self.dance:update(dt)
  end
  if self.pages[self.page] == "acting" and self.acting then
    if self.actingDone then
      self.acting = nil
      return self:advance()
    end
    return self.acting:update(dt)
  end
  self:tickSounds()
  if self.queue[1] and self.queue[1] ~= self.shownItem then
    self.shownItem = self.queue[1]
    self:shown(self.shownItem)
  end
  if input:wasPressed("a") or input:wasPressed("b") then
    if #self.queue > 1 then table.remove(self.queue, 1) else self:advance() end
  end
end

-- pl_winframe's window at the overlay's own tiles, the text inside it
function Screen:drawMessage(text)
  if not text then return end
  local g = love.graphics
  if Font.hasDialogueFrame and Font.hasDialogueFrame() then
    Font.drawDialogueBox(1, 18, 29, 6)
  else
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 8, 144, 240, 44)
  end
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
  local y = 152
  for l in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
  Font.popStyle()
end

function Screen:monSprite(id)
  self.sprites = self.sprites or {}
  if self.sprites[id] == nil then
    local mon = self.c.contestants[id].mon
    local path = require("src.pokemon.Sprites").path(self.game.data, mon.species, "front", { mon = mon, kind = "contest" })
    local ok, img = false, nil
    if path then ok, img = pcall(require("src.render.Assets").image, path) end
    self.sprites[id] = ok and img or false
  end
  return self.sprites[id] or nil
end

function Screen:drawAudience()
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  local mode = ok and SS.mode(self.game) or "off"
  if (mode == "display" or mode == "inset") and not SS.stowed(self.game) then
    SS.draw(self.game, function() Art.draw(self.game, "audience", 0, 0) end)
  end
end

function Screen:drawVisual(item)
  local g, game, c = love.graphics, self.game, self.c
  Art.draw(game, "visual_stage", 0, 0)
  local id = item and item.stage
  if id then
    local img = self:monSprite(id)
    if img then
      local w, h = img:getDimensions()
      g.draw(img, 128, 96, 0, 1, 1, w / 2, h / 2)
    end
    -- what the player put on it, where they put it
    if id == 0 then
      local D = require("src.ui.Gen4ContestDressUp")
      local d = self.wornArt or setmetatable({ data = game.data, images = {} }, D)
      self.wornArt = d
      for _, a in ipairs(c.contestants[0].accessories or {}) do
        local art = d:image(a.accessory)
        if art and a.x then g.draw(art, 128 + a.x, 96 + a.y) end
      end
    end
  end
  if item and item.rate then
    -- the round's two scores for the entry on stage: the condition's stars
    -- and the dress-up's hearts (C.stars / C.hearts)
    for k = 0, C.stars(c, item.rate) - 1 do Art.draw(game, "flying_star", 20 + k * 16, 20) end
    for k = 0, C.hearts(c, item.rate) - 1 do Art.draw(game, "small_heart_0", 24 + k * 10, 38) end
  else
    Art.draw(game, "visual_curtain", 0, 0)
  end
  self:drawMessage(item and item.text)
end

-- the results board: rows at y 8 + 32k, each bar on its 192-pixel track
-- from x 48 (the cartridge's own bar length, 192 x weight)
function Screen:drawResults(item)
  local g, game, c, data = love.graphics, self.game, self.c, self.game.data
  Art.draw(game, "results_bg", 0, 0)
  local reveal = item and item.reveal or 0
  local colours = { { 1, 0.85, 0.3 }, { 0.4, 0.8, 1 }, { 1, 0.45, 0.45 } }
  for entry = 0, 3 do
    local id = C.entryToId(entry)
    local y0 = 8 + 32 * entry
    local e, b = c.contestants[id], c.bars[id]
    Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.85, 0.85, 0.85 } })
    Font.draw(name(e, data), 48, y0 + 3)
    Font.popStyle()
    local x = 48
    for r = 1, math.min(3, reveal) do
      if b[r] > 0 then
        g.setColor(colours[r][1], colours[r][2], colours[r][3], 1)
        g.rectangle("fill", x, y0 + 20, b[r], 4)
        x = x + b[r]
      end
    end
    g.setColor(1, 1, 1, 1)
    if item and item.final then
      Font.pushStyle({ text = { 1, 1, 1 }, shadow = { 0.2, 0.4, 0.2 } })
      local place = tostring(c.placement[id] + 1)
      Font.draw(place, 231 - math.floor(Font.width(place) / 2), y0 + 3)
      Font.popStyle()
    end
  end
  self:drawMessage(item and item.text)
end

function Screen:drawPlain(page)
  local g = love.graphics
  local c, data = self.c, self.game.data
  g.setColor(0.18, 0.12, 0.3, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  Font.pushStyle({ text = { 1, 1, 1 }, shadow = { 0, 0, 0 } })
  if page == "visual" then
    Font.draw("VISUAL COMPETITION", 8, 8)
    for id = 0, 3 do
      local e = c.contestants[id]
      local y = 32 + id * 36
      Font.draw(name(e, data), 8, y)
      Font.draw(e.trainer or "", 8, y + 14)
      Font.draw(("*"):rep(C.stars(c, id)), 120, y)
      Font.draw(("<3 "):rep(C.hearts(c, id)), 120, y + 14)
    end
  else
    Font.draw("RESULTS", 8, 8)
    local byPlace = {}
    for id = 0, 3 do byPlace[c.placement[id] + 1] = id end
    for row, id in ipairs(byPlace) do
      local e, b = c.contestants[id], c.bars[id]
      local y = 32 + (row - 1) * 36
      Font.draw(("%d. %s"):format(c.placement[id] + 1, name(e, data)), 8, y)
      g.rectangle("fill", 8, y + 16, (b[1] + b[2] + b[3]) * 232 / 192, 8)
    end
  end
  Font.popStyle()
end

-- the dress-up takes the touch screen / mouse
function Screen:touchpressed(id, x, y)
  if self.dressup then return self.dressup:touchpressed(id, x, y) end
  return false
end
function Screen:touchmoved(id, x, y)
  if self.dressup then return self.dressup:touchmoved(id, x, y) end
  return false
end
function Screen:touchreleased(id, x, y)
  if self.dressup then return self.dressup:touchreleased(id, x, y) end
  return false
end

function Screen:draw()
  local g = love.graphics
  local page = self.pages[self.page]
  if page == "dressup" and self.dressup then return self.dressup:draw() end
  if page == "acting" and self.acting then return self.acting:draw() end
  if page == "dance" and self.dance then return self.dance:draw() end
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  local item = self.queue[1]
  if not Art.available(self.game) then
    self:drawPlain(page)
  elseif page == "visual" then
    self:drawVisual(item)
    self:drawAudience()
  else
    self:drawResults(item)
    self:drawAudience()
  end
  g.setColor(1, 1, 1, 1)
end

return Screen
