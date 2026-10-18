-- The Gen 1 cable-trade cinematic (engine/movie/trade.asm), used by in-game
-- NPC trades and by link trades:
--
--   InternalClockTradeAnim  the player's Game Boy on the left -- in-game
--                           trades and the internally clocked side of a link
--   ExternalClockTradeAnim  the partner's Game Boy on the left -- the
--                           externally clocked side (opts.externalClock)
--
-- Each runs its TradeFuncSequence in order, and this file runs the same
-- functions in the same order, one coroutine resume per 60 Hz frame, with the
-- cartridge's own DelayFrames counts (see TradeAnimKit).  The screen is
-- modelled as the hardware draws it rather than as pictures: a 32x32-tile BG
-- map on a 256-pixel SCX ring, the window layer at WX/WY, wTileMap with its
-- automatic transfer to whichever map is at $9C00, OAM, and rBGP / rOBP0 /
-- rOBP1 -- so the scroll that carries the mon from one Game Boy to the other
-- is the same SCX walk over the same wrapped map, and the cable's flashing is
-- the same `rBGP xor $3c`.
--
-- The art is the ROM's (src/import/Gen1TradeArt.lua writes field.tradeArt:
-- the 49 BG tiles at $31, the 6x8 / 12x3 tilemaps out of
-- TileIDListPointerTable, the cable ball and the bubble).  The ball's drop,
-- shake, tilt and poof are the battle animations they are on the cartridge
-- (TRADE_BALL_*_ANIM through MoveAnimation; src/battle/AnimPlayer.lua plays
-- the subanimations) plus their DoSpecialEffectByAnimationId routines
-- (TradeHidePokemon / TradeShakePokeball / TradeJumpPokeball), which are
-- trade-only and live here.
--
-- Without extracted art (a cache from before Gen1TradeArt, or the ROM-free
-- test fixtures) the same program runs over drawn stand-ins.
--
-- Colour: the movie runs SET_PAL_POKEMON_WHOLE_SCREEN for the mon on show
-- (Trade_LoadMonSprite) and SET_PAL_GENERIC (PAL_MEWMON) for everything else
-- (Trade_DrawOpenEndOfLinkCable); sgbPalettes follows whichever ran last.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Logger = require("src.core.Logger")
local Kit = require("src.ui.TradeAnimKit")

local TradeAnim = {}
TradeAnim.__index = TradeAnim
TradeAnim.isOpaque = true

local CABLE = 0x5E        -- horizontal cable
local CABLE_JOIN = 0x5D   -- cable meeting a Game Boy's link port
local CABLE_CORNER = 0x5F
local CABLE_END = 0x60
local CABLE_DOWN = 0x61

-- ------------------------------------------------------------------ helpers

local function speciesName(game, mon)
  local def = game.data.pokemon[mon.species]
  return (def and def.name) or tostring(mon.species)
end

local function dexOf(game, mon)
  local def = game.data.pokemon[mon.species]
  return def and def.dex or 0
end

local function frontSprite(game, mon)
  local path, trueColor = require("src.pokemon.Sprites").path(
    game.data, mon.species, "front", { mon = mon, kind = "trade" })
  if not path then return nil, false end
  local ok, img = pcall(love.graphics.newImage, path)
  if not ok then return nil, false end
  return img, trueColor or false
end

-- The species' party icon as WriteMonPartySpriteOAMBySpecies lays it out
-- (the same table walk PartyMenu's drawIcon does): image, built-in name.
local function iconOf(game, mon)
  local icons = game.data.icons
  if not (icons and mon) then return nil end
  local def = game.data.pokemon[mon.species]
  local entry = (icons.bySpecies and icons.bySpecies[mon.species])
    or (def and def.icon)
  local name, path
  if type(entry) == "string" then
    name, path = entry, icons.icons and icons.icons[entry]
  elseif type(entry) == "table" then
    path = entry.image
  end
  if not path then
    name = def and def.dex and icons.byDex and icons.byDex[def.dex]
    path = name and icons.icons and icons.icons[name]
  end
  path = require("src.pokemon.Sprites").iconPath(game.data, mon, path,
                                                 { name = name })
  if not path then return nil end
  local ok, img = pcall(function()
    return love.graphics.newImage(require("src.render.Assets").resolve(path))
  end)
  return ok and img or nil, name
end

-- The Super Game Boy is what SetAnimationPalette / LoadTradingGFXAndMonNames
-- test wOnSGB for: SGB colourings write OBP0 = $f0, everything else $e4.
local function onSGB()
  local mode = require("src.render.PaletteFX").mode
  return mode == "gbc" or mode == "gbc_inv" or mode == "redpp"
end

-- ------------------------------------------------------------------ layers
--
-- A map is { cells = { [row * 32 + col] = tile id }, items = { ... } }.
-- Cells are the trade's own BG tiles ($31-$61); items are what the
-- cartridge prints with the font (TextBoxBorder, PlaceString, PrintNumber)
-- and the mon pic, kept as draw records in tile coordinates.

local function newMap() return { cells = {}, items = {} } end

local function mapClear(map)
  map.cells, map.items = {}, {}
end

-- copy wTileMap's 20x18 into a 32x32 map's top-left, as the BG transfer does
local function mapCopyScreen(dst, src)
  for row = 0, 17 do
    for col = 0, 19 do dst.cells[row * 32 + col] = src.cells[row * 32 + col] end
  end
  dst.items = {}
  for i, item in ipairs(src.items) do dst.items[i] = item end
end

-- ------------------------------------------------------------------ new

function TradeAnim.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, TradeAnim)
  self.game = game
  self.sent = opts.sent
  self.received = opts.received
  self.onDone = opts.onDone
  self.external = opts.externalClock and true or false
  self.enemyName = opts.enemyName or (self.received and self.received.ot)
    or "TRAINER"
  self.playerName = (game.save.player and game.save.player.name) or "RED"
  self.playerOt = opts.playerOt or self.playerName
  self.playerOtId = opts.playerOtId
    or (self.sent and self.sent.otId)
    or (game.save.player and game.save.player.id)
    or 0
  self.enemyOtId = opts.enemyOtId
    or (self.received and self.received.otId)
    or love.math.random(0, 65535)
  -- wPlayerName / wLinkEnemyTrainerName, which Trade_SwapNames trades places
  self.nameLeft, self.nameRight = self.playerName, self.enemyName

  local art = game.data.field and game.data.field.tradeArt
  if type(art) == "table" and art.format == 2 then
    self.art = art
    self.img = {
      tiles = Kit.image(art.tiles),
      ball = Kit.image(art.cableBall),
      bubble = Kit.image(art.bubble),
    }
  else
    self.img = {}
  end
  self.sentPic, self.sentPicTrue = frontSprite(game, self.sent)
  self.recvPic, self.recvPicTrue = frontSprite(game, self.received)

  -- the hardware.  hAutoBGTransferEnabled always sends wTileMap to
  -- vBGMap1 ($9C00); which LAYER that is depends on rLCDC: the trade's own
  -- setting (BG $9C00, window $9800) or LCDC_DEFAULT (BG $9800, window $9C00)
  -- that Trade_ShowClearedWindow switches to.
  self.tm = newMap()            -- wTileMap (20x18 used)
  self.v98 = newMap()           -- vBGMap0
  self.v9C = newMap()           -- vBGMap1
  self.lcdcDefault = false
  self.scx = 0
  self.wx, self.wy = 7, 0x90    -- window off-screen until a function shows it
  self.winOn = false
  self.auto = false
  self.bgp, self.obp0, self.obp1 = 0xE4, 0xE4, 0xD0
  self.anim = nil               -- MoveAnimation sprites still in OAM
  self.cableBall = nil          -- the bulge riding the open cable end
  self.circle = nil             -- the mon in its bubble
  self.text = nil               -- the PrintText box, on the window
  self.palSpecies = self.sent and self.sent.species
  self.phase = "show_player"
  self.frame = 0
  self.co = coroutine.create(function() self:run() end)
  return self
end

function TradeAnim:enter() end

-- ------------------------------------------------------------------ frames

function TradeAnim:wait(n)
  for _ = 1, n or 1 do
    if self.auto then self:autoTransfer() end
    Kit.stepText(self.text)
    coroutine.yield()
  end
end

function TradeAnim:autoTransfer()
  mapCopyScreen(self.v9C, self.tm)
end

function TradeAnim:bgMap() return self.lcdcDefault and self.v98 or self.v9C end
function TradeAnim:winMap() return self.lcdcDefault and self.v9C or self.v98 end

-- CopyScreenTileBufferToVRAM: wTileMap to an explicit map, in three thirds
function TradeAnim:copyScreenTo98()
  mapCopyScreen(self.v98, self.tm)
  self:wait(3)
end

function TradeAnim:update()
  if self.finished then return end
  self.frame = self.frame + 1
  local ok, err = coroutine.resume(self.co)
  if not ok then
    Logger.warn("trade animation stopped: %s", tostring(err))
    self:finish()
    return
  end
  if coroutine.status(self.co) == "dead" then self:finish() end
end

function TradeAnim:finish()
  if self.finished then return end
  self.finished = true
  self.phase = "done"
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.onDone then self.onDone() end
end

-- InternalClockTradeFuncSequence / ExternalClockTradeFuncSequence
local INTERNAL = {
  "loadTradingGFX", "showPlayerMon", "drawOpenEndOfLinkCable",
  "animateBallEnteringLinkCable", "animLeftToRight", "delay100",
  "showClearedWindow", "printWentToText", "printForSendsText",
  "printFarewellText", "animRightToLeft", "showClearedWindow",
  "drawOpenEndOfLinkCable", "showEnemyMon", "delay100", "cleanup",
}
local EXTERNAL = {
  "loadTradingGFX", "showClearedWindow", "printWillTradeText",
  "printFarewellText", "swapNames", "animLeftToRight", "swapNames",
  "showClearedWindow", "drawOpenEndOfLinkCable", "showEnemyMon",
  "slideTextBoxOffScreen", "showPlayerMon", "drawOpenEndOfLinkCable",
  "animateBallEnteringLinkCable", "swapNames", "animRightToLeft", "swapNames",
  "delay100", "showClearedWindow", "printWentToText", "cleanup",
}

function TradeAnim:run()
  for _, name in ipairs(self.external and EXTERNAL or INTERNAL) do
    self[name](self)
  end
end

-- ------------------------------------------------------------------ text

function TradeAnim:line(key)
  local game = self.game
  return Kit.expand(game, key, {
    ["RAM:wStringBuffer"] = speciesName(game, self.sent),
    ["RAM:wNameBuffer"] = speciesName(game, self.received),
    ["RAM:wLinkEnemyTrainerName"] = self.enemyName,
    -- Gen 3's own trade lines name the same three things
    sent = speciesName(game, self.sent), trainer = self.enemyName,
    received = speciesName(game, self.received),
  })
end

-- PrintText: with BIT_NO_TEXT_DELAY set the whole box is there at once.  A
-- line the dataset lacks still clears the box, as an empty PrintText would.
function TradeAnim:printText(key)
  self.text = Kit.textBox(self.game, self:line(key) or "", true)
end

-- ------------------------------------------------------------------ funcs

function TradeAnim:delay100() self:wait(100) end

function TradeAnim:loadTradingGFX()
  mapClear(self.tm)
  mapClear(self.v98)
  mapClear(self.v9C)
  -- LoadTradingGFXAndMonNames: OBP0 $f0 on the SGB, $e4 elsewhere
  self.obp0 = onSGB() and 0xF0 or 0xE4
end

function TradeAnim:swapNames()
  self.nameLeft, self.nameRight = self.nameRight, self.nameLeft
end

function TradeAnim:cleanup()
  self.phase = "cleanup"
end

-- ClearScreen: blank wTileMap, Delay3 (for whichever transfer is on)
function TradeAnim:clearScreen()
  mapClear(self.tm)
  self:wait(3)
end

-- Trade_CopyTileMapToVRAM: one auto transfer, Delay3
function TradeAnim:copyTileMapToVRAM()
  self.auto = true
  self:wait(3)
  self.auto = false
end

-- Trade_PrintPlayerMonInfoText / Trade_PrintEnemyMonInfoText into wTileMap,
-- under a TextBoxBorder at (4, row) of 12x8
function TradeAnim:monInfo(mon, ot, otId, row)
  local items = self.tm.items
  items[#items + 1] = { kind = "box", tx = 4, ty = row, tw = 12, th = 8 }
  items[#items + 1] = { kind = "info", tx = 5, ty = row, mon = mon,
                        ot = ot, otId = otId }
end

-- Trade_LoadMonSprite: palette to the mon, its pic flipped at (7,2) in
-- wTileMap (the transfer is toggled on), 10 frames
function TradeAnim:loadMonSprite(mon, pic, trueColor)
  self.palSpecies = mon and mon.species
  local items = self.tm.items
  items[#items + 1] = { kind = "pic", tx = 7, ty = 2, img = pic,
                        trueColor = trueColor }
  self.auto = not self.auto
  self:wait(10)
end

function TradeAnim:clearMonPic()
  local kept = {}
  for _, item in ipairs(self.tm.items) do
    if item.kind ~= "pic" then kept[#kept + 1] = item end
  end
  self.tm.items = kept
end

function TradeAnim:cry(species)
  -- PlayCry ends in WaitForSoundToFinish
  local src = Sound.playCry(self.game.data, species)
  for _ = 1, 150 do
    if not (src and src.isPlaying and src:isPlaying()) then break end
    self:wait(1)
  end
end

-- Trade_ShowAnimation: MoveAnimation of one TRADE_BALL_* id, including its
-- DoSpecialEffectByAnimationId routine
function TradeAnim:ballAnimation(id)
  local AnimPlayer = require("src.battle.AnimPlayer")
  local data = self.game.data.battle_anims
  local player = AnimPlayer.new(data)
  player:start(id, true)
  -- SetAnimationPalette: the trade balls run on OBP0 $f0 on the SGB
  local reg = onSGB() and 0xF0 or 0xE4
  local hidden = false
  local blocks = 0
  if not player:isDone() then
    self.anim = { player = player, reg = reg }
    while not player:isDone() do
      self:wait(1)
      player:update()
      blocks = player.stepIndex
      -- TradeHidePokemon: after the first frame block, the pic is wiped
      if id == "TRADE_BALL_DROP_ANIM" and not hidden and blocks >= 2 then
        hidden = true
        self:clearMonPic()
      end
    end
    -- what the last frame block leaves in OAM: the DROP / SHAKE / TILT balls
    -- end on FRAMEBLOCKMODE_03 and stay put; POOF's blocks are mode 00, each
    -- wiped by AnimationCleanOAM, so it leaves nothing
    local final = id ~= "TRADE_BALL_POOF_ANIM" and player:finalSprites()
    self.anim = final and #final > 0 and { sprites = final, player = player,
                                           reg = self.obp0, dy = 0 } or nil
  end
  if id == "TRADE_BALL_DROP_ANIM" and not hidden then self:clearMonPic() end
  if id == "TRADE_BALL_SHAKE_ANIM" then
    -- TradeShakePokeball: the resting ball hops up -12, -12, -8 (Delay3
    -- each), AnimationCleanOAM, SFX_TRADE_MACHINE
    for _, dy in ipairs({ -12, -12, -8 }) do
      if self.anim then self.anim.dy = self.anim.dy + dy end
      self:wait(3)
    end
    self:wait(1)
    self.anim = nil
    Sound.play(self.game.data, "Trade_Machine")
  elseif id == "TRADE_BALL_TILT_ANIM" then
    -- TradeJumpPokeball: eight hops, 5 frames each, the BG scrolling 8px
    -- left under the ball every hop, SFX_SWAP before a 12 and at the end
    local hops = { 11, 12, -12, -7, 7, 12, -8, 8 }
    for i, dy in ipairs(hops) do
      if self.anim then self.anim.dy = self.anim.dy + dy end
      local nextHop = hops[i + 1]
      if nextHop == 12 or nextHop == nil then
        Sound.play(self.game.data, "Swap")
      end
      self:wait(5)
      self.scx = (self.scx - 8) % 256
    end
    -- ClearScreen; the ball stays in OAM until the next animation
    self:clearScreen()
  end
end

-- Trade_ShowPlayerMon
function TradeAnim:showPlayerMon()
  self.phase = "show_player"
  -- the info box on the window ($9800), WY $50, WX = SCX = $86
  mapClear(self.tm)
  self:monInfo(self.sent, self.playerOt, self.playerOtId, 0)
  self.lcdcDefault = false
  self.wy, self.wx, self.scx = 0x50, 0x86, 0x86
  self.winOn = true
  self.auto = false
  self:copyScreenTo98()                  -- the box, to the window
  self:clearScreen()
  self:loadMonSprite(self.sent, self.sentPic, self.sentPicTrue)
  -- the window and the BG slide in together from $7e to 2
  for a = 0x7E, 2, -2 do
    self:wait(1)
    self.wx, self.scx = a, a
  end
  self:wait(80)
  self:ballAnimation("TRADE_BALL_POOF_ANIM")
  self:ballAnimation("TRADE_BALL_DROP_ANIM")
  self:cry(self.sent.species)
  self.auto = false
end

-- Trade_DrawOpenEndOfLinkCable
function TradeAnim:drawOpenEndOfLinkCable()
  self.phase = self.sawCable and "open_cable2" or "open_cable"
  self.sawCable = true
  mapClear(self.tm)
  self:copyScreenTo98()                  -- blank to vBGMap0
  self.palSpecies = nil                  -- SET_PAL_GENERIC
  -- the "pointless" copy: blank rows 4-5 over $9C00 columns 12-31, which
  -- after a right-to-left transfer still hold the cable it parked there
  self:copyCableTilesOffScreen(12)
  self.scx = 0xA0
  self:wait(1)
  self.lcdcDefault = false               -- BG $9C00, window off
  self.winOn = false
  self:placeTilemap(self.art and self.art.linkCable, 6, 2)
  self:copyTileMapToVRAM()
  Sound.play(self.game.data, "Heal_HP")
  -- twenty `add 4` with no DelayFrame between them: the cable does not
  -- slide, it lands at SCX $f0
  self.scx = 0xF0
end

function TradeAnim:placeTilemap(list, tx, ty)
  if not list then
    -- stand-in when the cache has no art: mark the area
    self.tm.items[#self.tm.items + 1] = { kind = "stub", tx = tx, ty = ty,
      tw = list and list.w or 0, th = list and list.h or 0 }
    return
  end
  for i, id in ipairs(list.ids) do
    local col = tx + (i - 1) % list.w
    local row = ty + math.floor((i - 1) / list.w)
    self.tm.cells[row * 32 + col] = id
  end
end

-- Trade_AnimateBallEnteringLinkCable
function TradeAnim:animateBallEnteringLinkCable()
  self.phase = "ball_enter"
  self:ballAnimation("TRADE_BALL_SHAKE_ANIM")
  self:wait(10)
  self.obp0 = 0xE4
  local bulge = 0
  local x = 0x60
  while true do
    -- WriteOAMBlock at (y $20, x), tile $7e/$7f alternating
    bulge = 1 - bulge
    self.cableBall = { x = x, y = 0x20, tile = 2 + bulge }
    self:wait(3)
    x = x + 4
    if x >= 0xA0 then break end
    Sound.play(self.game.data, "Tink")
  end
  self.cableBall = nil                   -- ClearSprites
  self.auto = true
  self:clearScreen()
  self:copyScreenTo98()
  self:wait(3)
  self.auto = false
end

-- Trade_InitGameboyTransferGfx
function TradeAnim:initGameboyTransferGfx()
  self.auto = true
  self:clearScreen()
  self.auto = false
  self.obp1 = 0xD0                       -- Trade_LoadMonPartySpriteGfx
  self:wait(1)
  self.lcdcDefault = false
  self.winOn = true
  self.scx = 0
  self.wy = 0x90                         -- window parked below the screen
end

-- Trade_WriteCircledMonOAM at wBaseCoord
function TradeAnim:writeCircledMonOAM(mon, baseX, baseY)
  local img, name = iconOf(self.game, mon)
  self.circle = { x = baseX, y = baseY, alt = false, mon = mon,
                  icon = img, iconName = name }
end

-- Trade_AnimCircledMon: rBGP xor $3c (the cable flashes) and every one of
-- the 20 OAM tiles xor ICONOFFSET (icon and bubble change frame)
function TradeAnim:animCircledMon()
  self.bgp = require("bit").bxor(self.bgp, 0x3C)
  if self.circle then self.circle.alt = not self.circle.alt end
end

function TradeAnim:moveHorizontal(units)
  for _ = 1, units do
    for _ = 1, 8 do
      self.scx = (self.scx + (self.movingRight and 2 or -2)) % 256
      self:wait(1)
    end
    self:animCircledMon()
  end
end

-- Trade_AnimMonMoveVertical
function TradeAnim:moveVertical()
  local function step(dx, dy)
    for _ = 1, 4 do
      self.circle.x = self.circle.x + dx
      self.circle.y = self.circle.y + dy
      self:animCircledMon()
      self:wait(8)
    end
  end
  if self.movingRight then
    step(4, 0)
    step(0, 10)
  else
    step(0, -10)
    step(-4, 0)
  end
end

function TradeAnim:drawLeftGameboy()
  mapClear(self.tm)
  local cells = self.tm.cells
  cells[4 * 32 + 11] = CABLE_JOIN
  for col = 12, 19 do cells[4 * 32 + col] = CABLE end
  self:placeTilemap(self.art and self.art.gameBoy, 5, 3)
  local items = self.tm.items
  items[#items + 1] = { kind = "box", tx = 4, ty = 12, tw = 9, th = 4 }
  items[#items + 1] = { kind = "text", tx = 5, ty = 14, text = self.nameLeft }
  self:wait(1)
end

function TradeAnim:drawRightGameboy()
  mapClear(self.tm)
  local cells = self.tm.cells
  for col = 0, 13 do cells[4 * 32 + col] = CABLE end
  cells[4 * 32 + 14] = CABLE_CORNER
  for row = 5, 8 do cells[row * 32 + 14] = CABLE_DOWN end
  cells[9 * 32 + 14] = CABLE_END
  cells[9 * 32 + 13] = CABLE_JOIN
  self:placeTilemap(self.art and self.art.gameBoy, 7, 8)
  local items = self.tm.items
  items[#items + 1] = { kind = "box", tx = 6, ty = 0, tw = 9, th = 4 }
  items[#items + 1] = { kind = "text", tx = 7, ty = 2, text = self.nameRight }
  self:wait(1)
end

function TradeAnim:drawCableAcrossScreen()
  mapClear(self.tm)
  for col = 0, 19 do self.tm.cells[4 * 32 + col] = CABLE end
end

-- Trade_CopyCableTilesOffScreen: wTileMap rows 4-5 into vBGMap1 from
-- column `col` (RedrawRowOrColumn wraps inside the 32-tile row), 10 frames
function TradeAnim:copyCableTilesOffScreen(col)
  for r = 4, 5 do
    for i = 0, 19 do
      self.v9C.cells[r * 32 + (col + i) % 32] = self.tm.cells[r * 32 + i]
    end
  end
  self:wait(10)
end

function TradeAnim:animLeftToRight()
  self.phase = "transfer_lr"
  self:initGameboyTransferGfx()
  self.movingRight = true
  self.obp0 = 0xE4
  local leftMon = self.external and self.received or self.sent
  self:writeCircledMonOAM(leftMon, 0x54, 0x1C)
  self:drawLeftGameboy()
  self:copyTileMapToVRAM()
  self:drawCableAcrossScreen()
  self:copyCableTilesOffScreen(12)       -- vBGMap1 + $8c
  self:moveHorizontal(6)
  self.auto = true
  self:drawCableAcrossScreen()
  self:moveHorizontal(4)
  self:drawRightGameboy()
  self:moveHorizontal(6)
  self.auto = false
  self:moveVertical()
  self.circle = nil                      -- ClearSprites
end

function TradeAnim:animRightToLeft()
  self.phase = "transfer_rl"
  self:initGameboyTransferGfx()
  self.movingRight = false
  local rightMon = self.external and self.sent or self.received
  self:writeCircledMonOAM(rightMon, 0x64, 0x44)
  self:drawRightGameboy()
  self:copyTileMapToVRAM()
  self:drawCableAcrossScreen()
  self:copyCableTilesOffScreen(20)       -- vBGMap1 + $94
  self:moveVertical()
  self:moveHorizontal(6)
  self.auto = true
  self:drawCableAcrossScreen()
  self:moveHorizontal(4)
  self:drawLeftGameboy()
  self:moveHorizontal(6)
  self.auto = false
  self.circle = nil
  self.bgp = 0xE4
end

-- Trade_ShowClearedWindow: the window ($9C00, where wTileMap now goes)
-- covers the whole screen
function TradeAnim:showClearedWindow()
  self.auto = true
  self.text = nil
  self:clearScreen()
  self.lcdcDefault = true                -- BG $9800, window $9C00
  self.winOn = true
  self.wx, self.wy = 7, 0
  self.scx = 0x90
  self.bgp = 0xE4
end

-- Trade_SlideTextBoxOffScreen
function TradeAnim:slideTextBoxOffScreen()
  self:wait(50)
  repeat
    self:wait(1)
    self.wx = self.wx + 2
  until self.wx == 0xA1
  mapClear(self.tm)                      -- Trade_ClearTileMap
  self.text = nil
  self:wait(10)
  self.wx = 7
end

function TradeAnim:printWentToText()
  self.phase = "went_to"
  self:printText("_TradeWentToText")
  self:wait(200)
  self:slideTextBoxOffScreen()
end

function TradeAnim:printForSendsText()
  self.phase = "for_sends"
  self:printText("_TradeForText")
  self:wait(80)
  self:printText("_TradeSendsText")
  self:wait(80)
end

function TradeAnim:printFarewellText()
  self.phase = "farewell"
  self:printText("_TradeWavesFarewellText")
  self:wait(80)
  self:printText("_TradeTransferredText")
  self:wait(80)
  self:slideTextBoxOffScreen()
end

function TradeAnim:printWillTradeText()
  self.phase = "will_trade"
  self:printText("_TradeWillTradeText")
  self:wait(80)
  self:printText("_TradeforText")
  self:wait(80)
end

-- Trade_ShowEnemyMon
function TradeAnim:showEnemyMon()
  self.phase = "show_enemy"
  self:ballAnimation("TRADE_BALL_TILT_ANIM")
  self:showClearedWindow()
  self:monInfo(self.received, self.enemyName, self.enemyOtId, 10)
  self:copyTileMapToVRAM()
  -- the transfer goes back on and Trade_LoadMonSprite flips it straight off
  -- again, so the pic only reaches the screen after the poof
  self.auto = true
  self:loadMonSprite(self.received, self.recvPic, self.recvPicTrue)
  self:ballAnimation("TRADE_BALL_POOF_ANIM")
  self.auto = true
  self:cry(self.received.species)
  self:wait(100)
  -- ClearScreenArea over the info box, then the take-care line
  local kept = {}
  for _, item in ipairs(self.tm.items) do
    if item.kind == "pic" then kept[#kept + 1] = item end
  end
  self.tm.items = kept
  self:printText("_TradeTakeCareText")
  self:wait(80)
end

-- ------------------------------------------------------------------ colour

function TradeAnim:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  local zones
  if self.palSpecies then
    local c = P.monPal(game.data, self.palSpecies)
    if c then zones = { P.whole(c) } end
  end
  zones = zones or P.wholeNamed(game.data, "MEWMON")
  -- a true-colour pic (a mod's art) keeps its own colours
  local rect = self.trueColorRect
  if rect and zones then
    zones[#zones + 1] = { colors = false, x = rect[1], y = rect[2],
                          w = rect[3], h = rect[4] }
  end
  return zones
end

-- ------------------------------------------------------------------ draw

function TradeAnim:drawItem(item, ox, oy)
  local x, y = ox + item.tx * 8, oy + item.ty * 8
  if item.kind == "box" then
    love.graphics.push()
    love.graphics.translate(ox, oy)
    Font.drawBox(item.tx, item.ty, item.tw, item.th)
    love.graphics.pop()
  elseif item.kind == "text" then
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(item.text or "", x, y)
    love.graphics.setColor(1, 1, 1, 1)
  elseif item.kind == "info" then
    self:drawInfo(item, ox, oy)
  elseif item.kind == "pic" then
    if item.img then
      -- LoadUncompressedSpriteData seats a w x h pic in the 7x7 box
      -- (8 - w) / 2 tiles in and 7 - h tiles down, and
      -- LoadFlippedFrontSpriteByMonIndex mirrors the whole box: the pic
      -- faces right
      local w, h = item.img:getDimensions()
      local wt, ht = math.ceil(w / 8), math.ceil(h / 8)
      local left = math.floor((8 - wt) / 2) * 8
      local px = x + 56 - left - w
      local py = y + (7 - ht) * 8
      love.graphics.draw(item.img, px + w, py, 0, -1, 1)
      if item.trueColor then
        self.trueColorRect = { px, py, w, h }
      end
    else
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, 55, 55)
      love.graphics.setColor(1, 1, 1, 1)
    end
  elseif item.kind == "stub" then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, 47, 63)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- Trade_MonInfoText: "──№<DOT>" across the top border, the species, "OT/"
-- and the name, "<ID>№<DOT>" and the number, on rows +0/+2/+4/+6
function TradeAnim:drawInfo(item, ox, oy)
  local HudTiles = require("src.render.HudTiles")
  local x, y = ox + item.tx * 8, oy + item.ty * 8
  -- "──" over the border's own ─ tiles; the rest replaces border tiles
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x + 16, y, 40, 8)
  pcall(HudTiles.statusTile, 0x74, x + 16, y)     -- №
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawCode(0xF2, x + 24, y)                  -- <DOT>
  Font.draw(Kit.digits(dexOf(self.game, item.mon), 3), x + 32, y)
  Font.draw(speciesName(self.game, item.mon), x, y + 16)
  Font.draw(Strings("OT/"), x, y + 32)
  Font.draw(item.ot or "", x + 24, y + 32)
  love.graphics.setColor(1, 1, 1, 1)
  pcall(HudTiles.statusTile, 0x73, x, y + 48)     -- <ID>
  pcall(HudTiles.statusTile, 0x74, x + 8, y + 48) -- №
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawCode(0xF2, x + 16, y + 48)
  Font.draw(Kit.digits(item.otId, 5), x + 24, y + 48)
  love.graphics.setColor(1, 1, 1, 1)
end

-- one map: cells through rBGP, items over them
function TradeAnim:drawMap(map, ox, oy, ring)
  local tiles = self.img.tiles
  local base = self.art and self.art.tileBase or 0x31
  local perRow = self.art and self.art.tilesPerRow or 8
  Kit.withRegister(self.bgp, function()
    for key, id in pairs(map.cells) do
      local row, col = math.floor(key / 32), key % 32
      local px = col * 8 + ox
      local xs = ring and { Kit.wrapX(px) } or { px }
      for _, x in ipairs(xs) do
        if x and row * 8 + oy < 144 then
          if tiles then
            love.graphics.draw(tiles, Kit.tileQuad(tiles, id - base, perRow),
                               x, row * 8 + oy)
          else
            -- stand-in cable: a dark bar through the cell
            love.graphics.setColor(1 / 3, 1 / 3, 1 / 3, 1)
            love.graphics.rectangle("fill", x, row * 8 + oy + 2, 8, 4)
            love.graphics.setColor(1, 1, 1, 1)
          end
        end
      end
    end
  end)
  for _, item in ipairs(map.items) do
    if ring then
      -- an item can straddle the ring's seam: draw it at both images
      local x0 = (item.tx * 8 + ox) % 256
      self:drawItem(item, x0 - item.tx * 8, oy)
      self:drawItem(item, x0 - 256 - item.tx * 8, oy)
    else
      self:drawItem(item, ox, oy)
    end
  end
end

function TradeAnim:drawSprites()
  -- MoveAnimation's sprites (the trade balls)
  local a = self.anim
  if a then
    Kit.withRegister(a.reg, function()
      if a.sprites then
        love.graphics.push()
        love.graphics.translate(0, a.dy or 0)
        a.player:drawSprites(a.sprites)
        love.graphics.pop()
      elseif a.player then
        a.player:draw()
      end
    end)
  end
  -- the ball bulging through the open cable end: tile $7e/$7f four times,
  -- flipped into a circle (Trade_BallInsideLinkCableOAMBlock)
  local cb = self.cableBall
  if cb then
    if self.img.ball then
      Kit.withRegister(self.obp0, function()
        local img = self.img.ball
        Kit.drawObjTile(img, cb.tile, cb.x, cb.y, false, false, 4)
        Kit.drawObjTile(img, cb.tile, cb.x + 8, cb.y, true, false, 4)
        Kit.drawObjTile(img, cb.tile, cb.x, cb.y + 8, false, true, 4)
        Kit.drawObjTile(img, cb.tile, cb.x + 8, cb.y + 8, true, true, 4)
      end)
    else
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.circle("fill", cb.x, cb.y - 8, 6)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
  local c = self.circle
  if c then self:drawCircledMon(c) end
end

-- the party icon at (+16,+16) inside the four Trade_CircleOAMBlocks.  The
-- icon is OAM 0-3 and the bubble 4-19, and a lower OAM entry wins where two
-- overlap, so the icon is drawn last: the bubble's inside is colour 1, which
-- OBP1 $d0 shows as opaque white.
function TradeAnim:drawCircledMon(c)
  local x, y = c.x, c.y
  -- the bubble: OBP1 ($d0), quadrant tiles 0-3 (4-7 on the other frame)
  -- mirrored into the four corners
  local img = self.img.bubble
  if img then
    local f = c.alt and 4 or 0
    Kit.withRegister(self.obp1, function()
      local blocks = {
        { 8, 8, false, false }, { 24, 8, true, false },
        { 8, 24, false, true }, { 24, 24, true, true },
      }
      for _, b in ipairs(blocks) do
        local bx, by, xf, yf = x + b[1], y + b[2], b[3], b[4]
        -- WriteOAMBlock order: UL, UR, LL, LR; a flipped block reads the
        -- quadrant's tiles mirrored, which is drawing the quadrant flipped
        local order = { 0, 1, 2, 3 }
        if xf then order = { order[2], order[1], order[4], order[3] } end
        if yf then order = { order[3], order[4], order[1], order[2] } end
        Kit.drawObjTile(img, f + order[1], bx, by, xf, yf, 8)
        Kit.drawObjTile(img, f + order[2], bx + 8, by, xf, yf, 8)
        Kit.drawObjTile(img, f + order[3], bx, by + 8, xf, yf, 8)
        Kit.drawObjTile(img, f + order[4], bx + 8, by + 8, xf, yf, 8)
      end
    end)
  else
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", x + 16, y + 8, 15)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("line", x + 16, y + 8, 15)
    love.graphics.setColor(1, 1, 1, 1)
  end
  -- the icon: OBP0 ($e4 here), the frame ICONOFFSET picks
  if c.icon then
    Kit.withRegister(self.obp0, function()
      local PartyMenu = require("src.ui.PartyMenu")
      local icon = c.icon
      local iw, ih = icon:getDimensions()
      local frame = ih > 16 and PartyMenu.frameFor(c.iconName, c.alt, ih) or 0
      local sx, sy = x + 16 - 8, y + 16 - 16
      if c.alt and (c.iconName == "BALL" or c.iconName == "HELIX") then
        frame = 0
      end
      if PartyMenu.mirrorsIcon(c.iconName) then
        local half = love.graphics.newQuad(0, frame * 16, 8, 16, iw, ih)
        love.graphics.draw(icon, half, sx, sy)
        love.graphics.draw(icon, half, sx + 16, sy, 0, -1, 1)
      else
        love.graphics.draw(icon, love.graphics.newQuad(0, frame * 16,
                           math.min(16, iw), 16, iw, ih), sx, sy)
      end
    end)
  else
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", x + 12, y + 4, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function TradeAnim:draw()
  self.trueColorRect = nil
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  self:drawMap(self:bgMap(), -self.scx, 0, true)
  if self.text and not self.lcdcDefault then self.text:draw() end
  if self.winOn then
    local wx, wy = self.wx - 7, self.wy
    if wy < 144 and wx < 160 then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", math.max(0, wx), wy, 160, 144)
      self:drawMap(self:winMap(), wx, wy, false)
      -- PrintText's box went into wTileMap -> $9C00, the window here
      if self.text and self.lcdcDefault then
        love.graphics.push()
        love.graphics.translate(wx, wy)
        self.text:draw()
        love.graphics.pop()
      end
    end
  end
  if self.trueColorRect then
    local r = self.trueColorRect
    require("src.render.PaletteFX").markTrueColor(r[1], r[2], r[3], r[4])
  end
  self:drawSprites()
end

return TradeAnim
