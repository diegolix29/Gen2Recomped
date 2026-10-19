-- FireRed's TEACHY TV key-item screen.
--
-- The cartridge's teachy_tv.c presents four always-available lessons and,
-- once the TM CASE exists, two more about TMs and registering key items.
-- RomExtractorGen3 supplies this screen's real gTeachyTv_* background and the
-- cartridge's own menu/tutorial strings from the player's ROM.  The four
-- POKé DUDE battle demonstrations are driven by BattleState's dedicated
-- BATTLE_TYPE_POKEDUDE controller; the two remaining lessons drive the actual
-- FireRed Bag/TM Case screens with synthetic input, matching teachy_tv.c's
-- temporary tutorial data without touching the player's real inventory.

local Font = require("src.render.Font")
local Music = require("src.core.Music")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local TeachyTV = {}
TeachyTV.__index = TeachyTV
TeachyTV.isOpaque = true

local GBA_W, GBA_H = 240, 160
local ROW_PITCH = 16
local HOST_SPRITE = "SPRITE_G3_090" -- OBJ_EVENT_GFX_TEACHY_TV_HOST
local BG3_INITIAL_X, BG3_INITIAL_Y = -16, 40
local BG3_POST_BATTLE_X, BG3_POST_BATTLE_Y = 32, -8

-- teachy_tv.c's opening cluster, in frames:
--   64  noisy BG2 wipe
--   134 title card with the host at (8, 56), walking east in place
--   35  beat before the host starts crossing the screen
-- then one pixel per frame until x == 120.
local INTRO_WIPE_FRAMES = 64
local INTRO_TITLE_FRAMES = 134
local INTRO_BEAT_FRAMES = 35
local HOST_BATTLE_WALK_FRAMES = 48
local END_CARD_FRAMES = 127
local RETURN_WIPE_FRAMES = 64

local LESSONS = {
  {
    key = "battle", textKey = "battle", label = "Teach me how to battle.",
    text = "POKéDUDE: Welcome!\fIn battle, choose FIGHT, then pick a move.\nLower the foe's HP to win.\fWatch your own HP, too. If every POKéMON faints,\nyou'll black out.",
  },
  {
    key = "status", textKey = "status", label = "What are status problems?",
    text = "POKéDUDE: Status problems can change a battle.\fPOISON and BURN drain HP. PARALYSIS can stop a move.\nSLEEP and FREEZE keep a POKéMON from acting.\fItems and POKéMON CENTERS can cure these conditions.",
  },
  {
    key = "matchups", textKey = "matchups", label = "What are type matchups?",
    text = "POKéDUDE: Every move has a type.\fSome types are super effective, some are not very effective,\nand some do nothing at all.\fTry different moves and learn which matchups give you the edge!",
  },
  {
    key = "catch", textKey = "catch", label = "I want to catch POKéMON.",
    text = "POKéDUDE: First weaken a wild POKéMON without knocking it out.\fThen open the BAG and throw a POKé BALL.\nStatus problems can make a catch easier, too.",
  },
  {
    key = "tms", textKey = "tms", label = "Teach me about TMs.", needsTMCase = true,
    text = "POKéDUDE: TMs teach moves to compatible POKéMON.\fOpen the TM CASE, choose a TM, then choose the POKéMON.\nA TM is used up after teaching; HMs are kept.",
  },
  {
    key = "register", textKey = "register", label = "How do I register an item?", needsTMCase = true,
    text = "POKéDUDE: Important KEY ITEMS can be registered for quick use.\fIn the BAG, choose a KEY ITEM and select REGISTER.\nYou can change the registered item whenever you like.",
  },
}

function TeachyTV:uiSize() return GBA_W, GBA_H end
function TeachyTV:wantsFillScale() return true end

function TeachyTV:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

local function record(data)
  local r = data and data.constants and data.constants.gen3TeachyTV
  return type(r) == "table" and r or nil
end

local function romLabel(data, key, fallback)
  local r = record(data)
  local label = r and r.labels and r.labels[key]
  return type(label) == "string" and label ~= "" and label or fallback
end

local function romLesson(data, lesson)
  local r = record(data)
  local texts = r and r.texts
  if type(texts) ~= "table" then return lesson.text, nil end
  local before = texts[lesson.textKey .. "Before"]
  local after = texts[lesson.textKey .. "After"]
  if type(before) == "string" and before ~= "" then
    return before, (type(after) == "string" and after ~= "" and after or nil)
  end
  return lesson.text, nil
end

local function rgb(c, fallback)
  if type(c) ~= "table" then return fallback end
  return { (tonumber(c[1]) or 0) / 255,
           (tonumber(c[2]) or 0) / 255,
           (tonumber(c[3]) or 0) / 255, 1 }
end

local function musicByName(data, name)
  local songs = data and data.audio and data.audio.songs
  if type(songs) ~= "table" then return nil end
  for id, def in pairs(songs) do
    if type(def) == "table" and def.musName == name then return id end
  end
  return nil
end

-- teachy_tv.c does NOT use the field dialogue box here.  Window 0 is a raw
-- 26x4 tile window at (2,15), filled with palette-bank-3 colour $C, and its
-- FONT_MALE printer starts at (0,0) with fg/shadow indices 1/3.  Keeping the
-- ordinary TextBox state gives us the cartridge's page/CONT behaviour, but
-- supplies this screen's own exact geometry and colours instead of drawing a
-- generic bordered box over it.
function TeachyTV:messageBox(text, onDone)
  local TextBox = require("src.render.TextBox")
  local r = record(self.game.data) or {}
  local m = r.message or {}
  local c = r.colors and r.colors.message or {}
  local x = math.floor((tonumber(m.x) or 16) / 8)
  local y = math.floor((tonumber(m.y) or 120) / 8)
  local w = math.floor((tonumber(m.width) or 208) / 8)
  local h = math.floor((tonumber(m.height) or 32) / 8)
  -- FireRed text.c scrolls a CHAR_PROMPT_SCROLL by
  -- maxLetterHeight + lineSpacing (14 + 1 here), at 1/2/4 px per frame for
  -- SLOW/MID/FAST.  This port stores those options as 5/3/1 frame glyph
  -- delays, so translate that representation back to the GBA scroll speed.
  local textSpeed = self.game.save and self.game.save.options
                    and self.game.save.options.textSpeed or 3
  local scrollStep = ({ [5] = 1, [3] = 2, [1] = 4 })[textSpeed] or 2
  local scrollDistance = 15
  return TextBox.new(self.game, Strings(text or ""), onDone, {
    box = { tx = x, ty = y, tw = w, th = h, maxCols = w },
    maxCols = w,
    maxPixels = tonumber(m.width) or 208,
    -- These are verbatim gTeachyTvText_* strings from the cartridge.  Their
    -- line/scroll/page control codes are already laid out for this exact
    -- window; AddTextPrinter does not word-wrap them a second time.  Generic
    -- TextBox soft-wrap was splitting those authored lines again, producing
    -- 3-7-line "pages" and the long post-battle text overflow the user saw.
    softWrap = false,
    -- AddTextPrinterParameterized2 stores letterSpacing=1, but text.c only
    -- adds that field for Japanese glyphs.  English FONT_MALE advances by the
    -- cartridge width table alone (currentX += gGlyphInfo.width).
    letterSpacing = 0,
    scrollDistance = scrollDistance,
    scrollStep = scrollStep,
    scrollHoldFrames = math.ceil(scrollDistance / scrollStep),
    textX = tonumber(m.x) or 16,
    -- The GBA printer starts at y=1. FONT_MALE's maxLetterHeight is 14 and
    -- Teachy TV overrides lineSpacing to 1, so the second row begins 15px
    -- later: absolute y+1 and y+16.
    line1Y = (tonumber(m.y) or 120) + 1,
    line2Y = (tonumber(m.y) or 120) + 16,
    drawFrame = false,
    -- A real Window pixel buffer clips glyphs and shadows to 208x32.  The
    -- shared immediate-mode renderer did not, which is why long Teachy text
    -- could visibly bleed past its box even when the string itself was valid.
    clipToBox = true,
    fillColor = rgb(c.background, { 1, 1, 1, 1 }),
    style = {
      text = rgb(c.foreground, { 0, 0, 0, 1 }),
      shadow = rgb(c.shadow, { 0.75, 0.75, 0.75, 1 }),
    },
    uiWidth = GBA_W, uiHeight = GBA_H,
  })
end

function TeachyTV.entries(save, data)
  local hasCase = save and save.inventory and save.inventory.TM_CASE
  local out = {}
  for _, lesson in ipairs(LESSONS) do
    if not lesson.needsTMCase or hasCase then
      local before, after = romLesson(data, lesson)
      out[#out + 1] = {
        key = lesson.key,
        textKey = lesson.textKey,
        needsTMCase = lesson.needsTMCase,
        label = romLabel(data, lesson.key, lesson.label),
        before = before,
        after = after,
        -- Kept for callers/tests written against the first implementation.
        text = after and (before .. "\f" .. after) or before,
      }
    end
  end
  out[#out + 1] = { key = "cancel", label = romLabel(data, "cancel", "CANCEL") }
  return out
end

function TeachyTV.new(game)
  local self = setmetatable({}, TeachyTV)
  self.game = game
  self.rows = TeachyTV.entries(game.save, game.data)
  self.index, self.top = 1, 1
  self.presentation = "menu"
  -- TeachyTvSetupBg starts BG3 at ChangeBgX(..., $1000, SUB) and
  -- ChangeBgY(..., $2800, ADD).  Mode-0 BG coordinates are 8.8 fixed point.
  self.bg3X, self.bg3Y = BG3_INITIAL_X, BG3_INITIAL_Y
  self.previousMusic = Music.current()
  self.menuMusic = musicByName(game.data, "TEACHY_TV_MENU")
  self.followMusic = musicByName(game.data, "FOLLOW_ME")
  if self.menuMusic then
    pcall(Music.play, game.data, self.menuMusic, true,
          { reason = "teachy-tv-menu" })
  end
  return self
end

function TeachyTV:close()
  Sound.play(self.game.data, "Press_AB")
  self.game.stack:pop()
  if self.previousMusic then
    pcall(Music.play, self.game.data, self.previousMusic, true,
          { reason = "teachy-tv-return" })
  end
end

function TeachyTV:move(delta)
  self.index = (self.index - 1 + delta) % #self.rows + 1
  local visible = self:visibleRows()
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + visible - 1 then self.top = self.index - visible + 1 end
  Sound.play(self.game.data, "Press_AB")
end

function TeachyTV:visibleRows()
  local r = record(self.game.data)
  local L = r and r.list or {}
  local hasCase = self.game.save and self.game.save.inventory
                  and self.game.save.inventory.TM_CASE
  return math.max(1, math.floor(tonumber(hasCase and L.maxShowed
                                         or L.noCaseMaxShowed)
                                 or (hasCase and 6 or 5)))
end

function TeachyTV:choose()
  local row = self.rows[self.index]
  if not row or row.key == "cancel" then return self:close() end
  Sound.play(self.game.data, "Press_AB")
  self.pendingRow = row
  self.presentation = "transition"
  self.presentationPhase = "wipe"
  self.presentationTick = 0
  self.titleVisible = false
  self.hostVisible = false
  self.hostX, self.hostY = 8, 0x38
  self.hostAnim = 7 -- ANIM_STD_GO_EAST
  self.hostAnimTick = 0
end

function TeachyTV:showAfter(row)
  if not (row and type(row.after) == "string" and row.after ~= "") then
    return self:beginReturnToMenu()
  end
  self.presentation = "lesson"
  self.titleVisible = false
  self.hostVisible = true
  self.hostX, self.hostY = 0x78, 0x38
  self.hostAnim, self.hostAnimTick = 0, 0 -- face south
  -- The four battle demos return with BG3 at exactly the viewport reached by
  -- DudeMoveUp + DudeMoveRight.  TM/REGISTER never perform that walk and keep
  -- the initial viewport.  TeachyTvSetupPostBattleWindowAndObj creates the
  -- mode=1 grass object in BOTH cases, so it must not be battle-only here.
  if row.key == "tms" or row.key == "register" then
    self.bg3X, self.bg3Y = BG3_INITIAL_X, BG3_INITIAL_Y
  else
    self.bg3X, self.bg3Y = BG3_POST_BATTLE_X, BG3_POST_BATTLE_Y
  end
  self:spawnGrass(self.hostX, self.hostY, 0, 0, true)
  self.game.stack:push(self:messageBox(row.after, function()
    self:beginReturnToMenu()
  end))
end

function TeachyTV:showBeforeLesson(row)
  local r = record(self.game.data) or {}
  local hello = r.texts and r.texts.hello
  if type(hello) ~= "string" or hello == "" then
    hello = "POKé DUDE: Hey, all you TRAINERS out there!"
  end
  self.presentation = "lesson"
  self.game.stack:push(self:messageBox(hello, function()
    self.game.stack:push(self:messageBox(row.before or row.text, function()
      self:beginLessonDeparture(row)
    end))
  end))
end

function TeachyTV:beginLessonDeparture(row)
  self.pendingRow = row
  if row.key == "tms" or row.key == "register" then
    self.hostVisible = false
    return self:runLesson(row)
  end
  self.presentation = "depart"
  self.presentationPhase = "north"
  self.presentationTick = 0
  self.hostVisible = true
  self.hostX, self.hostY = 0x78, 0x38
  self.hostAnim, self.hostAnimTick = 5, 0 -- ANIM_STD_GO_NORTH
end

function TeachyTV:beginReturnToMenu()
  self.presentation = "return"
  self.presentationPhase = "hostExit"
  self.presentationTick = 0
  self.titleVisible = false
  self.endVisible = false
  self.hostVisible = true
  self.hostX, self.hostY = 0x78, 0x38
  self.hostAnim, self.hostAnimTick = 6, 0 -- ANIM_STD_GO_WEST
end

function TeachyTV:updatePresentation()
  self.presentationTick = (self.presentationTick or 0) + 1
  self.hostAnimTick = (self.hostAnimTick or 0) + 1
  self:updateGrass()

  if self.presentation == "transition" then
    if self.presentationPhase == "wipe" then
      if self.presentationTick >= INTRO_WIPE_FRAMES then
        self.presentationPhase = "title"
        self.presentationTick = 0
        self.titleVisible = true
        self.hostVisible = true
        self.hostX, self.hostY = 8, 0x38
        self.hostAnim, self.hostAnimTick = 7, 0
        if self.followMusic then
          pcall(Music.play, self.game.data, self.followMusic, true,
                { reason = "teachy-tv-show" })
        end
      end
      return
    end
    if self.presentationPhase == "title" then
      if self.presentationTick >= INTRO_TITLE_FRAMES then
        -- TTVcmd_ClearBg2TeachyTvGraphic clears the 26x12 title area here.
        self.titleVisible = false
        self.presentationPhase = "beat"
        self.presentationTick = 0
      end
      return
    end
    if self.presentationPhase == "beat" then
      if self.presentationTick >= INTRO_BEAT_FRAMES then
        self.presentationPhase = "hostEnter"
        self.presentationTick = 0
        self.hostAnim, self.hostAnimTick = 7, 0
      end
      return
    end
    if self.presentationPhase == "hostEnter" then
      if self.hostX < 0x78 then
        self.hostX = self.hostX + 1
      else
        local row = self.pendingRow
        self.hostAnim, self.hostAnimTick = 0, 0
        self.presentationPhase = "text"
        self.presentationTick = 0
        if row then self:showBeforeLesson(row) end
      end
      return
    end
  elseif self.presentation == "depart" then
    if self.presentationPhase == "north" then
      -- TTVcmd_DudeMoveUp changes BG3 Y by $100 SUB each frame.  PokéDude
      -- himself stays at (120,56); the moving Route 1 background is the walk.
      self.bg3Y = (self.bg3Y or BG3_INITIAL_Y) - 1
      if self.presentationTick % 16 == 0 then
        self:spawnGrass(self.hostX, self.hostY, 0, 1)
      end
      if self.presentationTick >= HOST_BATTLE_WALK_FRAMES then
        self.presentationPhase = "east"
        self.presentationTick = 0
        self.hostAnim, self.hostAnimTick = 7, 0
      end
      return
    end
    if self.presentationPhase == "east" then
      -- TTVcmd_DudeMoveRight changes BG3 X by $100 ADD each frame.
      self.bg3X = (self.bg3X or BG3_INITIAL_X) + 1
      if (self.presentationTick + 8) % 16 == 0 then
        self:spawnGrass((self.hostX or 0) + 8, self.hostY, -1, 0)
      end
      if self.presentationTick >= HOST_BATTLE_WALK_FRAMES then
        local row = self.pendingRow
        self.hostVisible = false
        self.presentation = "lesson"
        self.presentationPhase = nil
        self.presentationTick = 0
        if row then self:runLesson(row) end
      end
      return
    end
  elseif self.presentation == "return" then
    if self.presentationPhase == "hostExit" then
      if self.hostX > 8 then
        if self.hostX % 16 == 0 then
          self:spawnGrass(self.hostX - 8, self.hostY, 0, 0)
        end
        self.hostX = self.hostX - 1
      else
        self.presentationPhase = "ending"
        self.presentationTick = 0
        self.endVisible = true
      end
      return
    end
    if self.presentationPhase == "ending" then
      if self.presentationTick >= END_CARD_FRAMES then
        self.presentationPhase = "wipe"
        self.presentationTick = 0
        self.endVisible = false
        if self.menuMusic then
          pcall(Music.play, self.game.data, self.menuMusic, true,
                { reason = "teachy-tv-menu" })
        end
      end
      return
    end
    if self.presentationPhase == "wipe"
       and self.presentationTick >= RETURN_WIPE_FRAMES then
      self.presentation = "menu"
      self.presentationPhase = nil
      self.presentationTick = 0
      self.pendingRow = nil
      self.hostVisible = false
      self.grassParticles = {}
      -- TTVcmd_End resets BG3 and reapplies the initial -16,+40 viewport.
      self.bg3X, self.bg3Y = BG3_INITIAL_X, BG3_INITIAL_Y
      self.index = math.min(self.index, #self.rows)
      return
    end
  end
end

local function demoBagRow(game, id, qty)
  local def = game.data.items and game.data.items[id]
  return {
    id = id, label = (def and def.name) or id, qty = qty,
    important = def and (tonumber(def.importance) or 0) ~= 0 or nil,
    description = def and (def.description or def.desc),
  }
end

function TeachyTV:scriptedContext(entries, columns, index, onPick)
  local Gen3ItemMenu = require("src.ui.Gen3ItemMenu")
  local menu = Gen3ItemMenu.new(self.game, {
    entries = entries,
    columns = columns or 1,
    noInput = true,
    script = function(m)
      if m.tick == 48 and index then m.index = index end
      if m.tick > 96 and not m._pokedudePicked then
        m._pokedudePicked = true
        local e = m.entries[m.index]
        m:close(e and e.kind or "cancel")
      end
    end,
    onPick = onPick,
  })
  self.game.stack:push(menu)
end

local function demoTMRows(game)
  local rows = {}
  for _, id in ipairs({ "TM01", "TM03", "TM09", "TM35" }) do
    local def = game.data.items and game.data.items[id]
    local machine = def and def.machine
    if def and machine then
      local move = game.data.moves and game.data.moves[machine.move]
      rows[#rows + 1] = {
        id = id, def = def,
        prefix = ("%s%02d"):format(machine.kind or "TM",
                                  tonumber(machine.number) or 0),
        label = (move and move.name) or machine.move or id,
        qty = 1,
        description = def.description or def.desc,
      }
    end
  end
  rows[#rows + 1] = { close = true, label = Strings("CLOSE") }
  return rows
end

function TeachyTV:runTMCaseDemo(onDone)
  local TMCase = require("src.ui.Gen3TMCase")
  local texts = (record(self.game.data) or {}).texts or {}
  local typeText = texts.tmTypes or
    "POKé DUDE: TMs also come in types.\fCheck the type and teach it to a POKéMON that matches up well."
  local descText = texts.tmDescription or
    "Don't just look at the type, read the description, too.\fIt contains hints about what POKéMON might learn the move."

  local tm
  tm = TMCase.new(self.game, {
    rows = demoTMRows(self.game),
    noInput = true,
    onCancel = onDone,
    script = function(screen)
      screen._pdStage = screen._pdStage or 1
      screen._pdBase = screen._pdBase or screen.tick
      local elapsed = screen.tick - screen._pdBase
      local stage = screen._pdStage
      local moveAt = { 102, 204, 306, 408, 510, 612 }
      local deltas = { 1, 1, 1, -1, -1, -1 }
      screen._pdMove = screen._pdMove or 1
      local i = screen._pdMove
      if i <= #moveAt and elapsed >= moveAt[i] then
        screen:moveCursor(deltas[i])
        screen._pdMove = i + 1
        return
      end
      if i <= #moveAt then return end

      if elapsed >= 714 and not screen._pdMessage then
        screen._pdMessage = true
        local message = stage == 1 and typeText or descText
        self.game.stack:push(self:messageBox(message, function()
          if stage == 1 then
            screen._pdStage = 2
            screen._pdBase = screen.tick
            screen._pdMove = 1
            screen._pdMessage = nil
          else
            screen._pdStage = 3
            screen._pdBase = screen.tick
          end
        end))
        return
      end
      if stage == 3 and elapsed > 90 and not screen._pdClosed then
        screen._pdClosed = true
        screen:close()
      end
    end,
  })
  self.game.stack:push(tm)
end

function TeachyTV:runBagDemo(kind, onDone)
  local BagMenu = require("src.ui.Gen3BagMenu")
  local oldRegistered = self.game.save.registeredItem
  local rows = {
    demoBagRow(self.game, "TEACHY_TV", 1),
    demoBagRow(self.game, "TM_CASE", 1),
  }
  local bag
  bag = BagMenu.new(self.game, {
    pocket = "KEY_ITEM",
    rows = rows,
    noInput = true,
    script = function(screen)
      local t = screen.tick or 0
      if kind == "tms" then
        if t == 96 then screen.index = math.min(2, #screen.rows) end
        if t > 192 and not screen._pokedudeContext then
          screen._pokedudeContext = true
          self:scriptedContext({ { label = "OPEN", kind = "use" },
                                 { label = "CANCEL", kind = "cancel" } },
            1, 1, function(chosen)
              if chosen ~= "use" then return end
              if self.game.stack:top() == bag then bag:close() end
              self:runTMCaseDemo(onDone)
            end)
        end
      else
        if t > 150 and not screen._pokedudeContext then
          screen._pokedudeContext = true
          local actions = screen:actionsFor("TEACHY_TV")
          local entries = actions and actions.entries or {
            { label = "USE", kind = "use" },
            { label = "REGISTER", kind = "register" },
            { label = "", kind = "blank" },
            { label = "CANCEL", kind = "cancel" },
          }
          self:scriptedContext(entries, (actions and actions.columns) or 2,
            2, function(chosen)
              if chosen == "register" then
                self.game.save.registeredItem = "TEACHY_TV"
                screen._pokedudeRegistered = true
              end
            end)
        end
        if screen._pokedudeRegistered and t > 420 and not screen._pokedudeDone then
          screen._pokedudeDone = true
          self.game.save.registeredItem = oldRegistered
          screen:close()
          if onDone then onDone() end
        end
      end
    end,
  })
  self.game.stack:push(bag)
end

function TeachyTV:runLesson(row)
  if not row then return end
  local done = function() self:showAfter(row) end
  if row.key == "tms" or row.key == "register" then
    return self:runBagDemo(row.key, done)
  end
  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newPokedudeDemo(self.game, row.key)
  battle.onFinish = function() done() end
  self.game.stack:push(battle)
end

function TeachyTV:background()
  local r = record(self.game.data)
  local path = r and r.images and r.images.screen
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  return ok and img or nil
end

function TeachyTV:title()
  local r = record(self.game.data)
  local path = r and r.images and r.images.title
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  return ok and img or nil
end

function TeachyTV:route1()
  if self._route1Image ~= nil then return self._route1Image or nil end
  local r = record(self.game.data)
  local path = r and r.images and r.images.route1
  if type(path) ~= "string" then self._route1Image = false return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  self._route1Image = ok and img or false
  return ok and img or nil
end

function TeachyTV:drawRoute1()
  local image = self:route1()
  if not image then return end
  local iw, ih = image:getDimensions()
  if iw <= 0 or ih <= 0 then return end
  -- Mode-0 BG3 wraps. REG_BG3HOFS/VOFS select the source coordinate shown at
  -- screen (0,0), so draw a tiled 256x256 map at negative scroll offsets.
  local sx = (self.bg3X or BG3_INITIAL_X) % iw
  local sy = (self.bg3Y or BG3_INITIAL_Y) % ih
  local x0, y0 = -sx, -sy
  love.graphics.setColor(1, 1, 1, 1)
  for y = y0, GBA_H - 1, ih do
    for x = x0, GBA_W - 1, iw do
      love.graphics.draw(image, x, y)
    end
  end
end

function TeachyTV:noise()
  if self._noiseImage ~= nil then return self._noiseImage or nil end
  local r = record(self.game.data)
  local path = r and r.images and r.images.noise
  if type(path) ~= "string" then self._noiseImage = false return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  self._noiseImage = ok and img or false
  return ok and img or nil
end

function TeachyTV:endGraphic()
  if self._endImage ~= nil then return self._endImage or nil end
  local r = record(self.game.data)
  local path = r and r.images and r.images.endGraphic
  if type(path) ~= "string" then self._endImage = false return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  self._endImage = ok and img or false
  return ok and img or nil
end

function TeachyTV:tallGrass()
  if self._grassImage ~= nil then return self._grassImage or nil end
  local c = self.game.data and self.game.data.constants
  local rec = c and c.gen3TallGrass
  local path = rec and rec.image
  if type(path) ~= "string" then self._grassImage = false return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  self._grassImage = ok and img or false
  return ok and img or nil
end

function TeachyTV:spawnGrass(x, y, dx, dy, sticky)
  if not self:tallGrass() then return end
  self.grassParticles = self.grassParticles or {}
  self.grassParticles[#self.grassParticles + 1] = {
    x = x or 0, y = y or 0, dx = dx or 0, dy = dy or 0,
    age = sticky and 40 or 0, sticky = sticky or false,
  }
end

function TeachyTV:updateGrass()
  local list = self.grassParticles
  if type(list) ~= "table" then return end
  for i = #list, 1, -1 do
    local p = list[i]
    p.age = (p.age or 0) + 1
    p.x = p.x + (p.dx or 0)
    p.y = p.y + (p.dy or 0)
    if p.sticky then
      -- The post-battle grass object stays on its last frame until the host
      -- walks far enough away (TeachyTvGrassAnimationObjCallback).
      if math.abs((p.x or 0) - (self.hostX or 0)) >= 16
         or math.abs((p.y or 0) - (self.hostY or 0)) >= 24 then
        table.remove(list, i)
      end
    elseif p.age >= 50 then
      table.remove(list, i)
    end
  end
end

function TeachyTV:drawGrass(front)
  local image = self:tallGrass()
  local list = self.grassParticles
  if not image or type(list) ~= "table" then return end
  local iw, ih = image:getDimensions()
  if not self._grassQuads then
    self._grassQuads = {}
    self._grassTopQuads = {}
    self._grassBottomQuads = {}
    for frame = 0, 4 do
      self._grassQuads[frame] = love.graphics.newQuad(
        0, frame * 16, 16, 16, iw, ih)
      self._grassTopQuads[frame] = love.graphics.newQuad(
        0, frame * 16, 16, 8, iw, ih)
      self._grassBottomQuads[frame] = love.graphics.newQuad(
        0, frame * 16 + 8, 16, 8, iw, ih)
    end
  end
  local sequence = { 1, 2, 3, 4, 0 }
  love.graphics.setColor(1, 1, 1, 1)
  for _, p in ipairs(list) do
    local frame
    if p.sticky and p.age >= 40 then
      frame = 0
    else
      frame = sequence[math.min(5, math.floor((p.age or 0) / 10) + 1)]
    end
    local x = math.floor((p.x or 0) - 8)
    local y = math.floor(p.y or 0)
    if p.sticky then
      -- Post-battle TeachyTvGrassAnimationMain(..., mode=1) gives the whole
      -- grass sprite priority 2.  The host was created at subpriority 8 while
      -- this grass uses subpriority 0, so it sits IN FRONT of the host and
      -- covers his feet.  Drawing it behind him made the POKé DUDE look like
      -- he was standing on a loose grass tile.
      if front then
        love.graphics.draw(image, self._grassQuads[frame], x, y)
      end
    else
      -- Normal Teachy grass uses two subsprites: the upper 8px is priority 3
      -- (behind the host), the lower 8px is priority 2 (in front).  Reproduce
      -- that split explicitly in immediate-mode rendering.
      if front then
        love.graphics.draw(image, self._grassBottomQuads[frame], x, y + 8)
      else
        love.graphics.draw(image, self._grassTopQuads[frame], x, y)
      end
    end
  end
end

function TeachyTV:drawNoise()
  local image = self:noise()
  if not image then return end
  local r = record(self.game.data) or {}
  local n = r.transition and r.transition.noise or {}
  local x0, y0 = tonumber(n.x) or 16, tonumber(n.y) or 8
  local cols, rows = tonumber(n.cols) or 26, tonumber(n.rows) or 12
  local iw, ih = image:getDimensions()
  if not self._noiseQuads then
    self._noiseQuads = {}
    for bank = 0, 3 do
      self._noiseQuads[bank] = love.graphics.newQuad(
        bank * 8, 0, 8, 8, iw, ih)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  local tick = self.presentationTick or 0
  for ty = 0, rows - 1 do
    for tx = 0, cols - 1 do
      -- Deterministic equivalent of Random() & 3: every frame changes the
      -- palette choice without perturbing gameplay/tutorial RNG.
      local bank = (tx * 3 + ty * 5 + tick * 7 + tx * ty) % 4
      love.graphics.draw(image, self._noiseQuads[bank],
                         x0 + tx * 8, y0 + ty * 8)
    end
  end
end

function TeachyTV:drawEndGraphic()
  if not self.endVisible then return end
  local image = self:endGraphic()
  if not image then return end
  local r = record(self.game.data) or {}
  local e = r.transition and r.transition.ending or {}
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, tonumber(e.x) or 160, tonumber(e.y) or 80)
end

function TeachyTV:host()
  if self._hostSprite ~= nil then return self._hostSprite or nil end
  local def = self.game.data and self.game.data.sprites
              and self.game.data.sprites[HOST_SPRITE]
  if type(def) ~= "table" then
    self._hostSprite = false
    return nil
  end
  local ok, sprite = pcall(require("src.render.SpriteRenderer").new, def,
                           "teachy-tv-host")
  self._hostSprite = ok and sprite or false
  return ok and sprite or nil
end

local HOST_ANIMS = {
  [0] = { frames = { 0 } },                        -- face south
  [3] = { frames = { 2 }, flip = true },           -- face east
  [5] = { frames = { 5, 1, 6, 1 }, step = 8 },    -- go north
  [6] = { frames = { 7, 2, 8, 2 }, step = 8 },    -- go west
  [7] = { frames = { 7, 2, 8, 2 }, step = 8,
          flip = true },                            -- go east
}

function TeachyTV:drawHost()
  if not self.hostVisible then return end
  local sprite = self:host()
  if not sprite then return end
  local anim = HOST_ANIMS[self.hostAnim or 0] or HOST_ANIMS[0]
  local step = anim.step or 999999
  local frameIndex = math.floor((self.hostAnimTick or 0) / step)
                     % #anim.frames + 1
  local frame = anim.frames[frameIndex]
  local image, redraw = sprite:resolveModeImage(
    (self.hostX or 0) - 8, (self.hostY or 0) - 16)
  local quad = sprite.frames and sprite.frames[frame]
  if not (image and quad) then return end
  love.graphics.setColor(1, 1, 1, 1)
  local x, y = (self.hostX or 0) - 8, (self.hostY or 0) - 16
  if anim.flip then
    love.graphics.draw(image, quad, x + 16, y, 0, -1, 1)
  else
    love.graphics.draw(image, quad, x, y)
  end
end

function TeachyTV:update()
  if self.presentation ~= "menu" then
    return self:updatePresentation()
  end
  local input = self.game.input
  if not input then return end
  if input:wasPressed("down") then self:move(1)
  elseif input:wasPressed("up") then self:move(-1)
  elseif input:wasPressed("a") then self:choose()
  elseif input:wasPressed("b") then self:close() end
end

function TeachyTV:keypressed(key)
  if key == "down" then return self:move(1) end
  if key == "up" then return self:move(-1) end
  if key == "a" then return self:choose() end
  if key == "b" then return self:close() end
end

function TeachyTV:draw()
  -- BG3 is the lowest-priority Teachy layer.  The cartridge's BG0/BG1/BG2
  -- shell/title images then mask it, leaving the cropped Route 1 world visible
  -- only where teachy_tv.c exposes BG3.
  self:drawRoute1()
  local bg = self:background()
  if bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bg, 0, 0)
  else
    love.graphics.setColor(0.12, 0.18, 0.20, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
    love.graphics.setColor(0.84, 0.91, 0.88, 1)
    love.graphics.rectangle("fill", 8, 8, 224, 136)
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(2, 1, 26, 3)
    Font.draw("TEACHY TV", 16, 16)
    Font.drawBox(2, 4, 26, 14)
  end
  love.graphics.setColor(1, 1, 1, 1)

  local r = record(self.game.data)
  -- Once an option is chosen the cartridge destroys the list, clears its
  -- window and, after the TV wipe, copies gTeachyTvTitle_Tilemap onto BG2.
  -- Keeping the menu text under every tutorial message was the source of much
  -- of the visual clutter reported here.  The title layer is cartridge art,
  -- so draw it only while a lesson is being presented.
  if self.presentation ~= "menu" then
    if self.presentationPhase == "wipe" then
      self:drawNoise()
    end
    if self.titleVisible then
      local title = self:title()
      if title then love.graphics.draw(title, 0, 0) end
    end
    self:drawGrass(false)
    self:drawHost()
    self:drawGrass(true)
    self:drawEndGraphic()
    return
  end
  local L = r and r.list or {}
  local hasCase = self.game.save and self.game.save.inventory
                  and self.game.save.inventory.TM_CASE
  local x = (tonumber(L.x) or 32) + (tonumber(L.itemX) or 8)
  local cursorX = (tonumber(L.x) or 32) + (tonumber(L.cursorX) or 0)
  local y0 = (tonumber(L.y) or 8)
             + (tonumber(hasCase and L.upTextY or L.noCaseUpTextY)
                or (hasCase and 6 or 14))
  local visible = self:visibleRows()
  local colors = r and r.colors and r.colors.list or {}
  local bgc = rgb(colors.background, nil)
  if bgc then
    love.graphics.setColor(bgc)
    love.graphics.rectangle("fill", tonumber(L.x) or 32, tonumber(L.y) or 8,
                            tonumber(L.width) or 176, tonumber(L.height) or 96)
  end
  Font.pushStyle({
    text = rgb(colors.foreground, { 0, 0, 0, 1 }),
    shadow = rgb(colors.shadow, { 0.75, 0.75, 0.75, 1 }),
  })
  local oldScissor = { love.graphics.getScissor() }
  love.graphics.setScissor(tonumber(L.x) or 32, tonumber(L.y) or 8,
                           tonumber(L.width) or 176, tonumber(L.height) or 96)
  for i = 0, visible - 1 do
    local rowIndex = self.top + i
    local row = self.rows[rowIndex]
    if not row then break end
    local y = y0 + i * (tonumber(L.rowHeight) or ROW_PITCH)
    if rowIndex == self.index then Font.drawCode(Theme.cursor, cursorX, y) end
    Font.draw(row.label, x, y)
  end
  -- Retail only installs the pair when the TM Case exists.  With seven rows
  -- and six visible, scrollOffset can only be 0 or 1: down is shown at the
  -- first page, up at the second, at the exact sScrollIndicatorArrowPair
  -- coordinates (120,12)/(120,100).
  if hasCase then
    local ax = tonumber(L.arrowX) or 0x78
    love.graphics.setColor(rgb(colors.foreground, { 1, 1, 1, 1 }))
    if self.top > 1 then
      local ay = tonumber(L.arrowUpY) or 0x0C
      love.graphics.polygon("fill", ax, ay - 3, ax - 4, ay + 2, ax + 4, ay + 2)
    end
    if self.top + visible - 1 < #self.rows then
      local ay = tonumber(L.arrowDownY) or 0x64
      love.graphics.polygon("fill", ax, ay + 3, ax - 4, ay - 2, ax + 4, ay - 2)
    end
  end
  if oldScissor[1] ~= nil then
    love.graphics.setScissor(oldScissor[1], oldScissor[2], oldScissor[3], oldScissor[4])
  else
    love.graphics.setScissor()
  end
  Font.popStyle()
  love.graphics.setColor(1, 1, 1, 1)
end

return TeachyTV
