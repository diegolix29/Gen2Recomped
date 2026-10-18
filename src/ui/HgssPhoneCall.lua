-- HEARTGOLD / SOULSILVER: A SCRIPTED POKEGEAR CALL (`RunPhoneCall`).
--
-- The overworld's `PhoneCall who, 2, n` (std_phone_call, scr_seq_0003) rings
-- twice, fades to black and launches the Pokegear on its phone with the call
-- already connected (PokegearPhone_LaunchApp, isScriptedLaunch 1). What runs
-- then is overlay 101's call engine, followed here state for state:
--
--   PhoneCall_InitContext       incoming, so mainState starts at 1 -- no
--                               outgoing "......" ring
--   PhoneCall_GetCallScriptId   the contact's phonebook TYPE picks the
--                               handler; a scripted call (isScriptedCall 2)
--                               answers from the code below (Elm: his
--                               map-script table at the third operand; Oak:
--                               082; Baoba: 141; Mom: her own handler)
--   GearPhoneCall_Simple        scriptDef.msgIds[gender] from the contact's
--                               bank (sPhoneMessageGmm), after a bank-640
--                               greeting when the phonebook row has one
--   GearPhoneCall_Mother        (scripted) 22, the savings menu (271 8/9),
--                               25 or 26, FLAG_SYS_MOMS_SAVINGS
--   PhoneCall_WaitButtonBeforeHangup   A or B, SEQ_SE_DP_SELECT
--   PhoneCall_HangupTone        SEQ_SE_GS_PHONE_OFF, "Click!" / "Click!\n......"
--                               / "Click!\n...... ......", ten frames apart
--   PhoneCall_Exit              undim, back to the contact list -- the
--                               Pokegear stays open and the player closes it
--
-- THE TWO SCREENS. The call is printed on the SUB engine (the DS's top
-- screen; windows 0 and 1 on GF_BG_LYR_SUB_2: name at tiles 4,16 9x2, the
-- message at 2,19 27x4), while the MAIN engine (the touch screen) shows the
-- contact list dimmed 8/16 toward black (PokegearPhone_SetTouchscreenDimState).
-- Here the top screen is the window and the touch screen is SecondScreen.
--
-- Data: data.gen4_hgss_phone_call (src/import/Gen4HgssPhoneCall.lua) and the
-- Pokegear pictures and contact banks of data.gen4_hgss_pokegear_art.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")
local Logger = require("src.core.Logger")

local Call = {}
Call.__index = Call
Call.isOpaque = true

local SE_SELECT, SE_PHONE_OFF = 1500, 2170
local FLAG_TALKED_TO_MOM_AFTER_NAMING_RIVAL, FLAG_SYS_MOMS_SAVINGS = 0xA7, 0x986
-- PokegearPhone phonebook TYPEs (gear_phone.h PHONECALLTYPE_*)
local TYPE_MOM, TYPE_ELM, TYPE_OAK, TYPE_BAOBA = 1, 2, 3, 13
-- the call windows, in sub-screen pixels (sWindowTemplates 0 and 1)
local MSG_X, MSG_Y, MSG_W, LINE_H = 16, 152, 216, 16
local NAME_X, NAME_Y = 32, 128
local FADE_FRAMES, HANGUP_GAP = 6, 10

function Call:uiSize() return 256, 192 end
function Call:wantsFillScale() return true end
function Call:wantsEdgeBleed() return false end

function Call.available(game)
  local d = game and game.data
  return d and type(d.gen4_hgss_phone_call) == "table" and d.gen4_hgss_phone_call.scripts ~= nil
end

local function textOf(game, bank, index)
  local T = require("src.import.Gen4Text")
  return T.resolve(game.data, bank, index, game)
end

-- PhoneCall_GetCallScriptId for a scripted call (isScriptedCall 2) of the
-- contacts the overworld scripts ring. Answers { kind = "simple", script } or
-- { kind = "mother" }. Any other contact or call kind goes the way every
-- handler's incoming branch does: the script id as given.
function Call.choose(data, caller, kind, id)
  local pc = data.gen4_hgss_phone_call
  local entry = pc.book and pc.book[caller]
  local t = entry and entry.type
  if kind == 2 then
    if t == TYPE_ELM then
      local row = pc.elmMapScripts and pc.elmMapScripts[id]
      if row then return { kind = row.scriptType == 0 and "simple" or "unsupported", script = row.script } end
    elseif t == TYPE_OAK then
      return { kind = "simple", script = 82 }
    elseif t == TYPE_BAOBA then
      return { kind = "simple", script = 141 }
    elseif t == TYPE_MOM then
      return { kind = "mother", sets = { FLAG_TALKED_TO_MOM_AFTER_NAMING_RIVAL } }
    end
  end
  return { kind = "simple", script = id }
end

function Call.new(game, call, onDone, ctx)
  local self = setmetatable({ game = game, call = call, onDone = onDone, ctx = ctx,
    cache = {}, t = 0, phase = "fadein", queue = {}, lines = {}, menuIndex = 1, scroll = 0 }, Call)
  local data = game.data
  self.pc = data.gen4_hgss_phone_call
  self.skin = (tonumber((game.save.hgssPokegear or {}).skin) or 0) % 6
  self.girl = game.save.player and game.save.player.gender == "girl"
  local contact = ((data.gen4_hgss_pokegear_art or {}).contacts or {})[call.caller]
  self.bank = contact and contact.bank
  self.name = (self.bank and textOf(game, self.bank, 0)) or (contact and contact.name) or ""
  self.plan = Call.choose(data, call.caller, call.kind, call.id)
  local ok, Gear = pcall(require, "src.ui.HgssPokegear")
  if ok then self.gear = Gear.new(game, {}) end
  self:script()
  return self
end

-- the message's lines from the contact's bank, with the call's own string
-- template (PhoneCall_InitMsgDataAndBufferNames: 0 the player, 1 the
-- contact) -- spliced into a copy of the buffers, so the script's own slots
-- are what they were when the call ends
function Call:message(bank, index)
  local game = self.game
  local saved = game.stringBuffers
  game.stringBuffers = {}
  for k, v in pairs(saved or {}) do game.stringBuffers[k] = v end
  game.stringBuffers[1] = tostring(game.save.player and game.save.player.name or "")
  game.stringBuffers[2] = self.name
  local text = textOf(game, bank, index)
  game.stringBuffers = saved
  if not text then
    Logger.warn("hgss phone: bank %s entry %s is not in this cache", tostring(bank), tostring(index))
  end
  return text or ""
end

function Call:say(bank, index) self.queue[#self.queue + 1] = { say = self:message(bank, index) } end
function Call:step(fn) self.queue[#self.queue + 1] = { run = fn } end

-- the handler's script, as a queue of lines and actions
function Call:script()
  local plan, pc = self.plan, self.pc
  if plan.kind == "mother" then
    for _, f in ipairs(plan.sets or {}) do self:flag(f, true) end
    -- scripted: straight to MomCallGetSaveMoneyPromptMsg's 22, then the menu
    self:say(self.bank, 22)
    self.queue[#self.queue + 1] = { menu = { pc.texts and pc.texts[8] or "", pc.texts and pc.texts[9] or "" },
      choose = function(i)
        self:flag(FLAG_SYS_MOMS_SAVINGS, i == 1)
        table.insert(self.queue, self.at + 1, { say = self:message(self.bank, i == 1 and 25 or 26) })
      end }
    return
  end
  local def = pc.scripts and pc.scripts[plan.script]
  if plan.kind ~= "simple" or not def then
    Logger.warn("hgss phone: no script %s for contact %s (%s, %s)", tostring(plan.script),
      tostring(self.call.caller), tostring(self.call.kind), tostring(self.call.id))
    return
  end
  -- PhoneCall_ApplyGenericNPCcallSideEffect: of its kinds only the flag one
  -- (1, 2) means anything without the rematch / gift / word machinery
  if def.kind == 1 or def.kind == 2 then self:flag(def.param1, def.param0 ~= 0) end
  local entry = pc.book and pc.book[self.call.caller]
  local greet = entry and entry.greeting
  if greet and greet ~= 0xFF and pc.greetings and pc.greetings[greet] then
    -- PhoneCall_PrintGreeting: timeOfDay * 2 + incoming * 6, Ethan / Lyra
    -- GF_RTC_GetTimeOfDayWildParamByHour: morning 0, day / evening 1, night 2
    local band = require("src.import.Gen4Encounters").timeOfDayForHour(tonumber(os.date("%H")))
    local tod = (band == 0 and 0) or ((band == 1 or band == 2) and 1) or 2
    local row = pc.greetings[greet]
    local k = tod * 2 + 6 + (self.girl and 1 or 0)
    if row[k] then self:say(640, row[k]) end
  end
  self:say(self.bank, def[self.girl and 2 or 1])
end

function Call:flag(id, on)
  local ctx = self.ctx or { save = self.game.save, game = self.game }
  local C = require("src.script.Commands")
  local name = ("FLAG_G4_%04X"):format(id)
  if on then C.set_flag(ctx, name) else C.clear_flag(ctx, name) end
end

-- ---------------------------------------------------------------- printing
local function speed(game)
  local d = game.save.options and game.save.options.textSpeed or 3
  if d ~= 1 and d ~= 3 and d ~= 5 then d = 3 end
  return d
end

function Call:begin(text)
  self.spans = Font.split(text)
  self.text, self.pos, self.timer = text, 0, 0
  self.lines, self.row = { "" }, 1
  self.wait, self.scroll = nil, 0
end

-- one glyph; answers false when the message is done
function Call:advance()
  self.pos = self.pos + 1
  local span = self.spans[self.pos]
  if not span then return false end
  local ch = self.text:sub(span.from, span.to)
  if ch == "\n" then
    self.row = self.row + 1
    self.lines[self.row] = ""
  elseif ch == "\v" then
    self.wait = "clear"       -- 0x25BC: wait, clear, back to the top
  elseif ch == "\f" then
    self.wait = "scroll"      -- 0x25BD: wait, scroll one line, same row
  else
    self.lines[self.row] = (self.lines[self.row] or "") .. ch
  end
  return true
end

-- answers true when the current message has printed through
function Call:printing()
  local input = self.game.input
  if self.scroll > 0 then
    -- ScrollWindow 4 pixels a frame
    self.scroll = self.scroll - 4
    if self.scroll <= 0 then
      -- everything moved up a line; printing goes on at the same row
      self.scroll = 0
      table.remove(self.lines, 1)
      for i = #self.lines, self.row, -1 do self.lines[i] = nil end
      self.lines[self.row] = ""
    end
    return false
  end
  if self.wait then
    if input:wasPressed("a") or input:wasPressed("b") then
      require("src.core.Sound").play(self.game.data, SE_SELECT)
      if self.wait == "clear" then self.lines, self.row = { "" }, 1
      else self.scroll = LINE_H end
      self.wait = nil
    end
    return false
  end
  local delay = speed(self.game)
  if input:isDown("a") or input:isDown("b") then delay = 1 end
  self.timer = self.timer + 1
  while self.timer >= delay do
    self.timer = self.timer - delay
    if not self:advance() then return true end
    if self.wait then return false end
  end
  return false
end

-- ---------------------------------------------------------------- the beat
function Call:update(dt)
  self.t = self.t + 1
  local input = self.game.input
  if self.phase == "fadein" then
    if self.t >= FADE_FRAMES then self.phase, self.at = "run", 0; self:next() end
  elseif self.phase == "say" then
    if self:printing() then self:next() end
  elseif self.phase == "menu" then
    local item = self.queue[self.at]
    if input:wasPressed("up") or input:wasPressed("down") then
      self.menuIndex = 3 - self.menuIndex
    elseif input:wasPressed("a") or input:wasPressed("b") then
      require("src.core.Sound").play(self.game.data, SE_SELECT)
      local pick = input:wasPressed("a") and self.menuIndex or 2
      self.menu = nil
      item.choose(pick)
      self:next()
    end
  elseif self.phase == "hangupwait" then
    if input:wasPressed("a") or input:wasPressed("b") then
      require("src.core.Sound").play(self.game.data, SE_SELECT)
      require("src.core.Sound").play(self.game.data, SE_PHONE_OFF)
      self.phase, self.t, self.click = "hangup", 0, 0
      self.lines = { self.pc.texts and self.pc.texts[33] or "Click!" }
    end
  elseif self.phase == "hangup" then
    if self.t > HANGUP_GAP then
      self.t = 0
      self.click = self.click + 1
      if self.click >= 3 then return self:finish() end
      self.lines = {}
      for line in ((self.pc.texts and self.pc.texts[33 + self.click]) or "Click!"):gmatch("[^\n]+") do
        self.lines[#self.lines + 1] = line
      end
    end
  end
end

function Call:next()
  self.at = self.at + 1
  local item = self.queue[self.at]
  if not item then
    self.phase = "hangupwait"
    return
  end
  if item.say then
    self.phase = "say"
    self:begin(item.say)
  elseif item.menu then
    self.phase, self.menu, self.menuIndex = "menu", item.menu, 1
  elseif item.run then
    item.run(self)
    return self:next()
  end
end

-- PhoneCall_Exit: back to the contact list, which is the Pokegear itself
function Call:finish()
  if self.done then return end
  self.done = true
  local game, onDone = self.game, self.onDone
  game.stack:pop()
  local ok, Gear = pcall(require, "src.ui.HgssPokegear")
  if ok and Gear then
    game.stack:push(Gear.new(game, { onCancel = onDone }))
  elseif onDone then
    onDone()
  end
end

-- ---------------------------------------------------------------- drawing
function Call:picture(key)
  local rec = (self.game.data.gen4_hgss_pokegear_art or {})[key .. "_" .. self.skin]
  if not rec then return end
  local path = type(rec) == "table" and rec.path or rec
  if self.cache[path] == nil then self.cache[path] = Assets.image(path) or false end
  if self.cache[path] then love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(self.cache[path], 0, 0) end
end

local function rgb(c, fallback)
  if type(c) ~= "table" then return fallback end
  return { (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255 }
end

function Call:ink()
  local ink = self.pc.ink and self.pc.ink[self.skin] or {}
  return { text = rgb(ink.text, { 1, 1, 1 }), shadow = rgb(ink.shadow, { 0.48, 0.48, 0.48 }) }
end

function Call:drawMenu(x, y)
  local g = love.graphics
  local items = self.menu
  local w, h = 176, #items * 16 + 8
  g.setColor(1, 1, 1, 1); g.rectangle("fill", x, y, w, h)
  g.setColor(0.2, 0.2, 0.2, 1); g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.75, 0.75, 0.75 } })
  for i, label in ipairs(items) do
    Font.draw(label, x + 14, y + 4 + (i - 1) * 16)
  end
  Font.popStyle()
  local cy = y + 4 + (self.menuIndex - 1) * 16 + 4
  g.setColor(0.25, 0.25, 0.25, 1)
  g.polygon("fill", x + 5, cy, x + 5, cy + 8, x + 10, cy + 4)
  g.setColor(1, 1, 1, 1)
end

-- the sub engine: the call
function Call:subPanel()
  local g = love.graphics
  g.setColor(1, 1, 1, 1); g.rectangle("fill", 0, 0, 256, 192)
  self:picture("frame_bottom")
  self:picture("phone_bottom")
  Font.pushStyle(self:ink())
  if self.phase ~= "fadein" then Font.draw(self.name, NAME_X, NAME_Y) end
  g.setScissor(MSG_X, MSG_Y, MSG_W, LINE_H * 2)
  local lift = (self.scroll > 0) and (LINE_H - self.scroll) or 0
  for i = 1, 2 do
    local line = self.lines and self.lines[i]
    if line and line ~= "" then Font.draw(line, MSG_X, MSG_Y + (i - 1) * LINE_H - lift) end
  end
  g.setScissor()
  Font.popStyle()
  if self.phase == "say" and self.wait and math.floor(self.t / 8) % 2 == 0 then
    local ink = self:ink().text
    g.setColor(ink[1], ink[2], ink[3], 1)
    local ax, ay = MSG_X + MSG_W - 10, MSG_Y + LINE_H + 5
    g.polygon("fill", ax, ay, ax + 7, ay, ax + 3.5, ay + 5)
    g.setColor(1, 1, 1, 1)
  end
end

-- the main engine: the contact list, dimmed while the call is up
function Call:mainPanel(withMenu)
  local g = love.graphics
  if self.gear then self.gear:panel(false) else g.setColor(0, 0, 0, 1); g.rectangle("fill", 0, 0, 256, 192) end
  g.setColor(0, 0, 0, 0.5); g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  if withMenu and self.menu then self:drawMenu(7 * 8, 11 * 8) end
end

function Call:draw()
  local g = love.graphics
  local dual = SecondScreen.separate(self.game)
  self:subPanel()
  if dual then
    SecondScreen.draw(self.game, function() self:mainPanel(true) end)
  elseif self.menu then
    -- no touch screen in view: the savings menu comes up over the call
    self:drawMenu(40, 88)
  end
  if self.phase == "fadein" then
    g.setColor(0, 0, 0, 1 - math.min(1, self.t / FADE_FRAMES))
    g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(1, 1, 1, 1)
  end
end

return Call
