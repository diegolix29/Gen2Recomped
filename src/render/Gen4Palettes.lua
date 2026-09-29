-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE COLOURS A GEN 4 SCREEN PRINTS TEXT IN, out of the cartridge.
--
-- A composed screen picture cannot contain a colour that appears NOWHERE BUT
-- IN TEXT.  Platinum's font sheet carries roles, not colours -- every pixel is
-- 0 for nothing, 1 for the letter, 2 for its shadow -- and each printer call
-- names which entries of which sub-palette those roles take:
-- `TEXT_COLOR(1, 2, 0)` on BG palette 3 in the bag, on BG palette 15 on the
-- trainer card.  Neither number is anywhere in the picture.
--
-- So until the graphics stage published them, every gen4 screen that printed
-- anything had its ink WRITTEN DOWN BY HAND.  That is not merely inelegant:
-- it was wrong.  Five of the six colours in `Gen4BagMenu` and one of the two
-- in `Gen4TrainerCard` were a unit low in at least one channel, because they
-- had been read off a decoder that FLOORED the 5-bit-to-8-bit conversion
-- where `Gen4Graphics` ROUNDS it -- 20 of 31 is 164.5, and the composed
-- pictures beside the text had 165 in them the whole time.  Nothing on screen
-- could show it, and nothing was ever going to.
--
-- Now the cache carries `gen4_graphics.palettes`, one hex string per palette
-- FILE (146 of them across the fifteen UI archives, shared by 394 screens),
-- and every screen record carries the `paletteKey` that names its own.  This
-- module is the reading end.
--
-- WHAT THE INDICES MEAN.  `slot` is the sixteen-colour bank the cartridge
-- names.  Within a bank the numbering is the cartridge's: entry 0 is the
-- transparent one, so `TEXT_COLOR(1, 2, 0)` is entries 1 and 2 and
-- `text(screens, key, 3, 1, 2)` reads exactly that.

local Gen4Palettes = {}

-- The hex string for a screen's palette, or nil when this cache predates the
-- graphics stage publishing them.
function Gen4Palettes.hexFor(data, screenKey)
  local g = (data or {}).gen4_graphics
  if type(g) ~= "table" then return nil end
  local screens, palettes = g.screens, g.palettes
  if type(screens) ~= "table" or type(palettes) ~= "table" then return nil end
  local rec = screens[screenKey]
  if type(rec) ~= "table" then return nil end
  local hex = palettes[rec.paletteKey]
  return (type(hex) == "string" and #hex > 0) and hex or nil
end

-- One colour, as the 0-1 triple LOVE draws with: bank `slot`, entry `index`
-- within it, both in the cartridge's own numbering.
function Gen4Palettes.colour(data, screenKey, slot, index)
  local hex = Gen4Palettes.hexFor(data, screenKey)
  if not hex then return nil end
  local at = (((tonumber(slot) or 0) * 16) + (tonumber(index) or 0)) * 6
  if at < 0 or at + 6 > #hex then return nil end
  return {
    tonumber(hex:sub(at + 1, at + 2), 16) / 255,
    tonumber(hex:sub(at + 3, at + 4), 16) / 255,
    tonumber(hex:sub(at + 5, at + 6), 16) / 255,
  }
end

-- A whole `TEXT_COLOR(letter, shadow, background)` pair, as
-- `{ letterColour, shadowColour }` -- the shape `Font.pushStyle` wants.
--
-- Returns nil rather than a partial pair, so a caller can fall back to its own
-- written-down constants in ONE test instead of two.
function Gen4Palettes.text(data, screenKey, slot, letter, shadow)
  local a = Gen4Palettes.colour(data, screenKey, slot, letter)
  local b = Gen4Palettes.colour(data, screenKey, slot, shadow)
  if not (a and b) then return nil end
  return { a, b }
end

return Gen4Palettes
