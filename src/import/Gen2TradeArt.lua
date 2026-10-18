-- Gold / Silver / Crystal's own trade cinematic, out of the player's ROM
-- (engine/movie/trade_animation.asm TradeAnimation; src/ui/Gen2TradeAnim.lua
-- plays it).
--
-- Gen 2 did not keep Red's trade movie.  It has its own art, its own layout
-- (a link TUBE rather than a cable, a stats window that scrolls in under the
-- frontpic, the two names under the tube), its own sprite-anim objects and
-- CGB palettes, and every one of those is a table or a blob in the ROM:
--
--   TradeGameBoyLZ        -> vTiles2 tile $31   LZ3: the Game Boy + tube tiles
--   TradeGameBoyTilemap   6x8   the Game Boy, absolute tile ids
--   TradeLinkTubeTilemap  12x3  the open end of the tube
--   TradeArrowRight/LeftGFX     vTiles0 '▶' / '▼' ($ed / $ee): the arrows
--                               under the tube point the way the mon goes
--   TradeBallGFX (6)  TradePoofGFX (12)  TradeCableGFX (4)
--                         -> vTiles0 $62 / $68 / $74   LoadTradeBallAndCableGFX
--   TradeBubbleGFX (4)    -> vTiles0 $72               LoadTradeBubbleGFX, with
--                            the species' menu icon at $62 (MONICON_TRADE)
--   SpriteAnimFrameData.Frameset_Trade*  + SpriteAnimOAMData
--                            the five objects' framesets and OAM sets
--   Sprites_Sine's table     the ball's rocking / bouncing arcs
--   PalPacket_TradeTube -> PredefPals   the tube's BG pal 0 and OB pal 7
--   PartyMenuOBPals[0]                  OB pal 0 while the tube is up
--   MapObjectPals[0] (per time of day)  OB pal 0 on the frontpic screens,
--                                       still the overworld's when the
--                                       cinematic starts from a field NPC
--
-- Everything is written as DMG shades (OBJ colour 0 transparent); the screen
-- applies the CGB palettes itself, through the cartridge's own DmgToCgb*
-- shade permutations, so the tube's flashing (rBGP xor %00111100) is the
-- same palette data permuted, as on hardware.
--
-- Answers nil when the cartridge does not carry the vanilla layout (Prism and
-- Polished Crystal rename or merge these blobs); the trade then keeps the
-- Gen 1 movie it always had.

local ImageWriter = require("src.import.ImageWriter")

local Gen2TradeArt = {}

local BG_TILE_BASE = 0x31
local OBJ_BASE = 0x62     -- SPRITE_ANIM_DICT_DEFAULT -> vTiles0 tile $62

Gen2TradeArt.PATHS = {
  tiles = "trade/gen2_tiles.png",
  arrows = "trade/gen2_arrows.png",
  obj = "trade/gen2_obj.png",
  bubble = "trade/gen2_bubble.png",
  iconDir = "trade/gen2_icons/",
}

-- the six framesets the five trade objects use (data/sprite_anims/framesets.asm)
local FRAMESETS = {
  "TradePokeBall", "TradePokeBallWobble", "TradePoof", "TradeTubeBulge",
  "TrademonIcon", "TrademonBubble",
}

local COMMANDS = { [0xff] = "end", [0xfe] = "restart", [0xfd] = "wait",
                   [0xfc] = "delete" }

local function sym(extractor, name)
  return extractor:symbol(name)
end

local function bytesAt(extractor, name, count, offset)
  local s = sym(extractor, name)
  if not s then return nil end
  return extractor.rom:bytes(s.bank, s.address + (offset or 0), count)
end

-- `count` tiles of 2bpp, `perRow` to a row
local function sheet(raw, count, perRow, transparent)
  local rows = math.ceil(count / perRow)
  local padded = {}
  for i = 1, perRow * rows * 16 do padded[i] = raw[i] or 0 end
  return ImageWriter.decode2bpp(padded, perRow * 8, rows * 8, transparent)
end

local function concat(...)
  local out = {}
  for _, part in ipairs({ ... }) do
    for _, b in ipairs(part) do out[#out + 1] = b end
  end
  return out
end

-- RGB555 -> 0..255, the same rounding RomExtractorGen2's gen2Rgb5 uses
local function rgb(value)
  local function channel(shift)
    return math.floor((math.floor(value / shift) % 32) * 255 / 31 + 0.5)
  end
  return { channel(1), channel(32), channel(1024) }
end

local function palette(rom, bank, address)
  local pal = {}
  for c = 0, 3 do pal[c + 1] = rgb(rom:word(bank, address + c * 2)) end
  return pal
end

-- one frameset: { frames = { { oam =, dur =, xflip =, yflip = } }, tail = }
local function frameset(extractor, name)
  local s = sym(extractor, "SpriteAnimFrameData.Frameset_" .. name)
  if not s then return nil end
  local rom = extractor.rom
  local frames, at = {}, s.address
  for _ = 1, 32 do
    local id = rom:byte(s.bank, at)
    if COMMANDS[id] then
      return { frames = frames, tail = COMMANDS[id] }
    end
    local flags = rom:byte(s.bank, at + 1)
    frames[#frames + 1] = {
      oam = id,
      -- oamframe shifts the flip bits up one (B_OAM_XFLIP + 1 = bit 6) so
      -- they clear the duration; GetSpriteAnimFrame masks them back off
      dur = flags % 0x40,
      xflip = math.floor(flags / 0x40) % 2 == 1,
      yflip = math.floor(flags / 0x80) % 2 == 1,
    }
    at = at + 2
  end
  return nil
end

-- the 32-entry quarter-wave Sprites_Sine multiplies against (calc_sine_wave:
-- `dw sin(x * 0.5 / 32)` under -Q8, i.e. 8.8 fixed point)
local function sineTable(extractor)
  local found
  for name in pairs(extractor.symbols or {}) do
    if name:find("^Sprites_Sine%.sinetable") then found = name break end
  end
  local s = found and sym(extractor, found)
  if not s then return nil end
  local out = {}
  for i = 0, 31 do out[i] = extractor.rom:word(s.bank, s.address + i * 2) end
  return out
end

-- The species' menu icon in raw shades, once per distinct icon (Crystal's
-- MonMenuIcons -> IconPointers indirection, Gold's identical table).  The
-- party menu's own icons are baked in each species' menu colours; here the
-- icon is an OBJ on PAL_OW_RED like every other tube object.
local function icons(extractor)
  local menu = sym(extractor, "MonMenuIcons")
  local ptr = sym(extractor, "IconPointers")
  if not (menu and ptr) then return nil end
  local speciesOrder = extractor:constants().speciesOrder or {}
  local rom = extractor.rom
  local indices = rom:bytes(menu.bank, menu.address, #speciesOrder)
  local written, bySpecies = {}, {}
  for i, id in ipairs(speciesOrder) do
    local icon = indices[i]
    if icon then
      local path = Gen2TradeArt.PATHS.iconDir .. ("%02x.png"):format(icon)
      if written[icon] == nil then
        local ok = pcall(function()
          local address = rom:word(ptr.bank, ptr.address + icon * 2)
          extractor:saveImage(sheet(rom:bytes(ptr.bank, address, 8 * 16),
                                    8, 8, true), path)
        end)
        written[icon] = ok
      end
      if written[icon] then bySpecies[id] = "assets/generated/" .. path end
    end
  end
  return bySpecies
end

function Gen2TradeArt.extract(extractor)
  local rom = extractor.rom
  if not rom then return nil end
  for _, name in ipairs({
    "TradeGameBoyLZ", "TradeGameBoyTilemap", "TradeLinkTubeTilemap",
    "TradeArrowRightGFX", "TradeArrowLeftGFX", "TradeBallGFX", "TradePoofGFX",
    "TradeCableGFX", "TradeBubbleGFX", "SpriteAnimOAMData",
    "PalPacket_TradeTube", "PredefPals", "PartyMenuOBPals", "MapObjectPals",
  }) do
    if not sym(extractor, name) then return nil end
  end

  local gb = extractor:gen2Lz("TradeGameBoyLZ")
  assert(gb and #gb >= 49 * 16, "TradeGameBoyLZ did not decompress")
  local tileCount = math.floor(#gb / 16)
  local gameBoy = bytesAt(extractor, "TradeGameBoyTilemap", 6 * 8)
  local tube = bytesAt(extractor, "TradeLinkTubeTilemap", 12 * 3)
  for _, list in ipairs({ gameBoy, tube }) do
    for _, id in ipairs(list) do
      assert(id >= BG_TILE_BASE and id < BG_TILE_BASE + tileCount,
        ("trade tilemap names tile $%02X outside the TradeGameBoyLZ tiles")
          :format(id))
    end
  end

  local sets = {}
  for _, name in ipairs(FRAMESETS) do
    local fs = frameset(extractor, name)
    if not fs then return nil end
    sets[name] = fs
  end
  local oam = {}
  for _, fs in pairs(sets) do
    for _, frame in ipairs(fs.frames) do
      if not oam[frame.oam] then
        local set = extractor:gen2OamSet(frame.oam)
        assert(set, ("SpriteAnimOAMData[%d] unreadable"):format(frame.oam))
        oam[frame.oam] = set
      end
    end
  end
  local sine = sineTable(extractor)
  if not sine then return nil end

  local P = Gen2TradeArt.PATHS
  extractor:saveImage(sheet(gb, tileCount, 8, false), P.tiles)
  extractor:saveImage(sheet(concat(
    bytesAt(extractor, "TradeArrowRightGFX", 16),
    bytesAt(extractor, "TradeArrowLeftGFX", 16)), 2, 2, false), P.arrows)
  -- vTiles0 $62..$77 as LoadTradeBallAndCableGFX leaves them: ball (6),
  -- poof (12), cable (4)
  extractor:saveImage(sheet(concat(
    bytesAt(extractor, "TradeBallGFX", 6 * 16),
    bytesAt(extractor, "TradePoofGFX", 12 * 16),
    bytesAt(extractor, "TradeCableGFX", 4 * 16)), 22, 8, true), P.obj)
  extractor:saveImage(sheet(bytesAt(extractor, "TradeBubbleGFX", 4 * 16),
                            4, 4, true), P.bubble)

  -- _CGB_TradeTube: CopyFourPalettes from PalPacket_TradeTube + 1 (the
  -- packet's first predef id is BG pal 0, the only one WipeAttrmap leaves in
  -- use), PartyMenuOBPals' first palette as OB pal 0, PREDEFPAL_TRADE_TUBE
  -- as OB pal 7
  local packet = sym(extractor, "PalPacket_TradeTube")
  local predef = sym(extractor, "PredefPals")
  local tubeId = rom:byte(packet.bank, packet.address + 1)
  local tubePal = palette(rom, predef.bank, predef.address + tubeId * 8)
  local party = sym(extractor, "PartyMenuOBPals")
  local mapObj = sym(extractor, "MapObjectPals")
  local mapPal0 = {}
  for i, tod in ipairs({ "MORN", "DAY", "NITE" }) do
    mapPal0[tod] = palette(rom, mapObj.bank, mapObj.address + (i - 1) * 64)
  end

  -- the WRAM buffers the trade's lines splice in, by the token the text
  -- table carries for each (gen2RamName picks a name per address, and the
  -- pick is not always the trade's own -- Crystal's wOTTrademonSenderName
  -- prints as {RAM:wc719})
  local function token(name)
    local s = extractor.symbols[name]
    local at = type(s) == "table" and tonumber(s[2])
    if not at then return nil end
    return "RAM:" .. (extractor:gen2RamName(at) or ("%04X"):format(at))
  end
  local tokens = {
    playerSpeciesName = token("wPlayerTrademonSpeciesName"),
    otSpeciesName = token("wOTTrademonSpeciesName"),
    playerSenderName = token("wPlayerTrademonSenderName"),
    otSenderName = token("wOTTrademonSenderName"),
  }

  local version = extractor.version
  return {
    format = 1,
    variant = (version == "gold" or version == "silver") and "gold"
      or "crystal",
    tiles = "assets/generated/" .. P.tiles,
    tileBase = BG_TILE_BASE,
    tileCount = tileCount,
    tilesPerRow = 8,
    arrows = "assets/generated/" .. P.arrows,
    obj = "assets/generated/" .. P.obj,
    objBase = OBJ_BASE,
    bubble = "assets/generated/" .. P.bubble,
    icons = icons(extractor),
    gameBoy = { w = 6, h = 8, ids = gameBoy },
    linkTube = { w = 12, h = 3, ids = tube },
    framesets = sets,
    oam = oam,
    sine = sine,
    palettes = {
      tube = tubePal,
      partyOb0 = palette(rom, party.bank, party.address),
      mapOb0 = mapPal0,
    },
    tokens = tokens,
    source = "ROM:TradeGameBoyLZ + Trade*GFX + SpriteAnimFrameData + "
      .. "PalPacket_TradeTube (engine/movie/trade_animation.asm)",
  }
end

return Gen2TradeArt
