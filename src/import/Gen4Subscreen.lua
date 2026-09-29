-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/import/Gen4Subscreen.lua -- PLATINUM'S BATTLE BOTTOM SCREEN.
--
-- Reported from play: *"the art for the text box, fight, pokemon, run and bag
-- buttons arent proper either make it match the color and style that would be
-- in the bottom screen"*. They were the engine's own words in the engine's own
-- box, because nothing had ever extracted the cartridge's buttons -- and the
-- reason nothing had is that they are not sprites. THE WHOLE BOTTOM SCREEN IS
-- SEVEN TILEMAPS OVER ONE TILE SHEET, which the graphics stage's sprite-shaped
-- machinery had no reason to look for.
--
-- EVERYTHING BELOW IS IN pl_batt_bg.narc -- the SAME archive the battle
-- backgrounds come from, which is why it was hiding in plain sight.
--
--   tiles      member 28   (169 in the Battle Frontier)
--   palette    member 242  (340 in the Frontier)
--   tilemaps   members 49, 42, 47, 43, 44, 48, 45, in the order
--              `sBgScreenNarcIndices` lists them (battle_subscreen.c)
--
-- WHAT EACH TILEMAP IS. The cartridge names none of them -- it copies all
-- seven into buffers and swaps them onto the four sub BG layers as the menu
-- changes -- so these names are this port's, given after composing each one
-- and looking at it. The composition is the cartridge's; the labels are mine,
-- and that split is said out loud rather than implied:
--
--   49  base           the pale panel with the Poke Ball watermark
--   42  action         the big red FIGHT button, with orange BAG, blue RUN and
--                      green POKeMON beneath it -- and their positions agree
--                      with sActionMenuTouchRects to the pixel
--   47  moves_idle     four grey move slots, the empty state
--   43  moves          four move buttons with type-coloured frames, over the
--                      blue cancel bar
--   44  moves_pressed  the pressed states of the same four
--   48  cursor         the purple selection outlines
--   45  panel          the target-select / message panel
--
-- !! THE PER-BACKGROUND PALETTE REPLACES SUB-PALETTE ZERO, NOT ONE.
--
-- BattleSubscreen_New loads member 242 whole, then loads
-- `sSubscreenBgPlttIndices[bg].bgPlttIndex` with srcSize = PALETTE_SIZE_BYTES
-- and destStart = PLTT_DEST(0) -- thirty-two bytes into destination zero. That
-- is ONE sub-palette, over the FIRST one.
--
-- Reading it as sub-palette 1 is not a harmless slip: I tried it first and the
-- FIGHT button came out cream-on-black instead of red, because the action
-- layer's cells are on sub-palettes 1 to 4 and every one of them was being
-- overwritten. MEASURED, which is what settled it -- the sub-palettes each
-- tilemap's cells actually name:
--
--   base 0 only | action 1,2,3,4 | moves_idle 13 | moves 0,3,4,8,9,10,11
--   moves_pressed 0,2,3,4,5,6,12,13 | cursor 0 | panel 0,1,4
--
-- So the ACTION MENU IS THE SAME RED, ORANGE, BLUE AND GREEN IN EVERY BATTLE,
-- and what recolours with the backdrop is the panel behind it. Which is the
-- right way round: you learn where BAG is once.

local Gen4Subscreen = {}

Gen4Subscreen.PATH = "/battle/graphic/pl_batt_bg.narc"

Gen4Subscreen.TILES = 28
Gen4Subscreen.FRONTIER_TILES = 169
Gen4Subscreen.PALETTE = 242
Gen4Subscreen.FRONTIER_PALETTE = 340
Gen4Subscreen.MOVE_SLOT_PALETTE = 267

-- The DS screen. The tilemaps are 256x256 because that is the smallest BG
-- size that holds a screen; only the top 192 rows are ever shown.
Gen4Subscreen.WIDTH, Gen4Subscreen.HEIGHT = 256, 192
Gen4Subscreen.MAP_HEIGHT = 256

-- In `sBgScreenNarcIndices` order, so the list and the cartridge's table can
-- be read against each other.
Gen4Subscreen.LAYERS = {
  { name = "base",          member = 0x31 },
  { name = "action",        member = 0x2A },
  { name = "moves_idle",    member = 0x2F },
  { name = "moves",         member = 0x2B },
  { name = "moves_pressed", member = 0x2C },
  { name = "cursor",        member = 0x30 },
  { name = "panel",         member = 0x2D },
}

-- `sSubscreenBgPlttIndices` -- one row per battle background, { the palette
-- that replaces sub-palette 0, the move-slot palette }. The last five rows of
-- the cartridge's table are 0xFFFF pairs (the Frontier backgrounds, which set
-- their own), and they are left out rather than carried as sentinels.
Gen4Subscreen.BACKGROUND_PALETTES = {
  [0]  = { 0xF3,  0x10B }, [1]  = { 0xF4,  0x10C }, [2]  = { 0xF5,  0x10D },
  [3]  = { 0xF6,  0x10E }, [4]  = { 0xF7,  0x10F }, [5]  = { 0xF8,  0x110 },
  [6]  = { 0xF9,  0x111 }, [7]  = { 0xFA,  0x112 }, [8]  = { 0xFB,  0x113 },
  [9]  = { 0xFC,  0x114 }, [10] = { 0xFD,  0x115 }, [11] = { 0xFE,  0x116 },
  [12] = { 0xFF,  0x117 }, [13] = { 0x100, 0x118 }, [14] = { 0x101, 0x119 },
  [15] = { 0x102, 0x11A }, [16] = { 0x103, 0x11B }, [17] = { 0x11C, 0x11D },
}
Gen4Subscreen.BACKGROUND_COUNT = 18

-- Which layers change with the battle background, worked out from the cells
-- rather than assumed: a layer recolours exactly when some cell of it names
-- sub-palette 0. Measured over all seven, it is five of them; the action
-- menu and the empty move slots are the two that do not.
Gen4Subscreen.RECOLOURS = {
  base = true, moves = true, moves_pressed = true, cursor = true, panel = true,
}

function Gen4Subscreen.recolours(name)
  return Gen4Subscreen.RECOLOURS[name] and true or false
end

-- The name a composed layer is written under. A layer that does not recolour
-- is written once; one that does gets a copy per background, so the screen can
-- pick without knowing any of the above.
function Gen4Subscreen.imageName(layer, background)
  if not Gen4Subscreen.recolours(layer) then
    return "battle/subscreen/" .. layer
  end
  return ("battle/subscreen/%s_%02d"):format(layer, background)
end


-- ---------------------------------------------------------------------------
-- WHERE EACH BUTTON IS DRAWN, and how to redraw it at another size
--
-- The touch rectangles in Gen4Battle are the cartridge's HIT areas. These are
-- the drawn ART, measured off the composed tilemaps as the opaque bounding box
-- inside each hit rect -- which is a different question and gives slightly
-- different numbers (BAG's button is 78x47 inside a hit rect 81 wide).
--
-- `inset` is the corner: how far in the rounded shape has settled. Measured by
-- walking the first rows of each button and watching the opaque run move in --
--
--     BAG    9, 8, 3, 2, 1, 1, 0, 0 ...
--     FIGHT  13, 12, 3, 2, 1, 1, 0, 0 ...
--     MOVE   8, 7, 3, 2, 1, 1, 0, 0 ...
--
-- -- so the curve is done by the sixth row and the widest overhang is the
-- first. The inset is that first number, which is the smallest nine-slice that
-- contains the whole corner AND the bevel above it.
--
-- WHY A NINE-SLICE AT ALL. The bottom strip of the main screen is 256x48 and
-- the FIGHT button is 216x93; scaling it would squash the bevel and the
-- highlight with everything else. A nine-slice keeps the corners and the top
-- and bottom bands at their own size and stretches only the flat middle, which
-- is how this engine already redraws the dialogue frame at any width.
Gen4Subscreen.ACTION_BUTTONS = {
  fight = { x = 20,  y = 34,  w = 216, h = 93, inset = 14 },
  item  = { x = 1,   y = 144, w = 78,  h = 47, inset = 9 },
  party = { x = 177, y = 144, w = 78,  h = 47, inset = 9 },
  run   = { x = 89,  y = 152, w = 78,  h = 40, inset = 9 },
}

-- The four move buttons are IDENTICAL in size and sit on an exact half-screen
-- split, which is the same 128-of-256 the touch rects state.
Gen4Subscreen.MOVE_BUTTONS = {
  [1] = { x = 2,   y = 24, w = 124, h = 55, inset = 8 },
  [2] = { x = 130, y = 24, w = 124, h = 55, inset = 8 },
  [3] = { x = 2,   y = 88, w = 124, h = 55, inset = 8 },
  [4] = { x = 130, y = 88, w = 124, h = 55, inset = 8 },
}
Gen4Subscreen.MOVE_CANCEL_BUTTON = { x = 9, y = 152, w = 238, h = 40, inset = 8 }

-- The empty slot is two pixels shorter than a filled one -- 53 against 55 --
-- because it carries no type frame. Kept as its own number rather than reused.
Gen4Subscreen.MOVE_SLOT_IDLE = { w = 124, h = 53, inset = 8 }

return Gen4Subscreen
