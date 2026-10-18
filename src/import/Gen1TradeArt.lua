-- The cable-trade cinematic's art, out of the player's own Red / Blue /
-- Yellow ROM (engine/movie/trade.asm InternalClockTradeAnim).
--
-- LoadTradingGFXAndMonNames copies TWO blobs and the transfer scenes load a
-- third:
--
--   TradingAnimationGraphics  -> vChars2 tile $31   game_boy.2bpp (built with
--                                --remove-duplicates) + link_cable.2bpp, 49
--                                BG tiles; every tilemap below names them by
--                                their ABSOLUTE id $31..$61
--   TradingAnimationGraphics2 -> vSprites tile $7c  cable_ball.2bpp, the four
--                                OBJ tiles of the ball riding the cable ($7e /
--                                $7f are the two bulge frames)
--   TradeBubbleIconGFX        -> ICON_TRADEBUBBLE   bubble.2bpp, eight tiles:
--                                the circle's top-left quadrant in both of
--                                its frames (LoadMonPartySpriteGfx copies
--                                tiles 0-3 to the icon slot and 4-7 to the
--                                +ICONOFFSET slot)
--
-- and Trade_DrawLeftGameboy / Trade_DrawOpenEndOfLinkCable lay the Game Boy
-- and the open cable end out with CopyTileIDsFromList, through rows 6 and 7
-- of TileIDListPointerTable (data/tilemaps.asm: `dw list`, `dn height,
-- width`) -- read here rather than assumed, so the 6x8 and 12x3 come off the
-- cartridge too.
--
-- Everything is written as raw DMG shades: the trade screen is a Game Boy
-- screen, and the PaletteFX zone pass colours it exactly as it colours the
-- rest of a Gen 1 game (SET_PAL_POKEMON_WHOLE_SCREEN / SET_PAL_GENERIC, see
-- TradeAnim:sgbPalettes).  OBJ sheets keep colour 0 transparent.

local ImageWriter = require("src.import.ImageWriter")

local Gen1TradeArt = {}

local BG_TILE_BASE = 0x31
local TILEMAP_GAME_BOY = 6
local TILEMAP_LINK_CABLE = 7

Gen1TradeArt.PATHS = {
  tiles = "trade/gen1_tiles.png",
  cableBall = "trade/gen1_cable_ball.png",
  bubble = "trade/gen1_bubble.png",
}

-- the extractor's symbol table, without RomExtractor:symbol's hard error:
-- a manifest from before these were added must still import (the trade then
-- runs on TradeAnim's drawn fallbacks), it just cannot produce this art
local function sym(extractor, name)
  local location = extractor.symbols and extractor.symbols[name]
  if type(location) ~= "table" then return nil end
  return { bank = location[1], address = location[2] }
end

-- `count` 8x8 tiles laid out `perRow` to a row
local function sheet(raw, count, perRow, transparent)
  local rows = math.ceil(count / perRow)
  local padded = {}
  for i = 1, perRow * rows * 16 do padded[i] = raw[i] or 0 end
  -- decode2bpp walks tiles in row-major order across `width / 8` columns,
  -- which is exactly the sheet order wanted here
  return ImageWriter.decode2bpp(padded, perRow * 8, rows * 8, transparent)
end

-- TileIDListPointerTable row `index`: { w, h, ids = { row-major } }
local function tileIdList(extractor, table_, index)
  local rom = extractor.rom
  local entry = table_.address + index * 3
  local pointer = rom:word(table_.bank, entry)
  local dims = rom:byte(table_.bank, entry + 2)
  local h, w = math.floor(dims / 16), dims % 16
  local ids = rom:bytes(table_.bank, pointer, w * h)
  return { w = w, h = h, ids = ids }
end

function Gen1TradeArt.extract(extractor)
  local gfx = sym(extractor, "TradingAnimationGraphics")
  local gfxEnd = sym(extractor, "TradingAnimationGraphicsEnd")
  local ball = sym(extractor, "TradingAnimationGraphics2")
  local ballEnd = sym(extractor, "TradingAnimationGraphics2End")
  local bubble = sym(extractor, "TradeBubbleIconGFX")
  local lists = sym(extractor, "TileIDListPointerTable")
  if not (gfx and gfxEnd and ball and ballEnd and bubble and lists) then
    return nil
  end
  local rom = extractor.rom

  local bgBytes = gfxEnd.address - gfx.address
  local ballBytes = ballEnd.address - ball.address
  -- 49 BG tiles ($31..$61) and four OBJ tiles ($7c..$7f) on every release;
  -- anything else means the symbols point somewhere they should not
  assert(gfxEnd.bank == gfx.bank and bgBytes == 49 * 16,
    ("TradingAnimationGraphics: expected 784 bytes, got %d"):format(bgBytes))
  assert(ballEnd.bank == ball.bank and ballBytes == 4 * 16,
    ("TradingAnimationGraphics2: expected 64 bytes, got %d"):format(ballBytes))
  local tileCount = bgBytes / 16

  local gameBoy = tileIdList(extractor, lists, TILEMAP_GAME_BOY)
  local linkCable = tileIdList(extractor, lists, TILEMAP_LINK_CABLE)
  assert(gameBoy.w == 6 and gameBoy.h == 8,
    ("TILEMAP_GAME_BOY: expected 6x8, got %dx%d"):format(gameBoy.w, gameBoy.h))
  assert(linkCable.w == 12 and linkCable.h == 3,
    ("TILEMAP_LINK_CABLE: expected 12x3, got %dx%d")
      :format(linkCable.w, linkCable.h))
  for _, list in ipairs({ gameBoy, linkCable }) do
    for _, id in ipairs(list.ids) do
      assert(id >= BG_TILE_BASE and id < BG_TILE_BASE + tileCount,
        ("trade tilemap names tile $%02X outside $31-$61"):format(id))
    end
  end

  local P = Gen1TradeArt.PATHS
  extractor:save(sheet(rom:bytes(gfx.bank, gfx.address, bgBytes),
                       tileCount, 8, false), P.tiles)
  extractor:save(sheet(rom:bytes(ball.bank, ball.address, ballBytes),
                       4, 4, true), P.cableBall)
  extractor:save(sheet(rom:bytes(bubble.bank, bubble.address, 8 * 16),
                       8, 8, true), P.bubble)

  return {
    format = 2,
    tiles = "assets/generated/" .. P.tiles,
    tileBase = BG_TILE_BASE,
    tileCount = tileCount,
    tilesPerRow = 8,
    cableBall = "assets/generated/" .. P.cableBall,  -- OBJ tiles $7c-$7f
    bubble = "assets/generated/" .. P.bubble,        -- frame 0: 0-3, 1: 4-7
    gameBoy = gameBoy,
    linkCable = linkCable,
    source = "ROM:TradingAnimationGraphics(+2) + TradeBubbleIconGFX + "
      .. "TileIDListPointerTable[6..7] (engine/movie/trade.asm)",
  }
end

return Gen1TradeArt
