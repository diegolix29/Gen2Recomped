-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S MAIL STATIONERY, out of /graphic/mail_gra.narc.
--
-- Reported from play: Mail answered Rowan's refusal.  The bag's USE on a
-- Mail (UseMailFromMenu) opens the mail app in its "check" mode on a blank
-- letter of that design (MailAppArgs_New_Check); MailViewer_DrawMail loads
-- the stationery from this archive, laid out by res/graphics/mail/mail.order:
--
--   member  0..11   the twelve palettes (grass, flame, bubble, bloom,
--                   tunnel, steel, heart, snow, space, air, mosaic, brick)
--   member 12..23   their tiles
--   member 24..35   their screens (main BG3)
--   member 36       the write mode's interface
--
-- The sub screen is tile 1 in palette 2 throughout (Bg_FillTilemapRect on
-- BG_LAYER_SUB_0), written here as one 256x192 picture per design.

local Gen4Graphics = require("src.import.Gen4Graphics")

local M = {}

M.PATH = "/graphic/mail_gra.narc"
M.NAMES = { "grass", "flame", "bubble", "bloom", "tunnel", "steel", "heart", "snow", "space", "air",
            "mosaic", "brick" }

local function member(arc, i)
  local b = arc and arc:get(i)
  if b and Gen4Graphics.isCompressed(b) then b = Gen4Graphics.decompress(b) end
  return b
end

function M.extract(ex)
  local arc = ex:archiveAt(M.PATH)
  if not arc then return nil, M.PATH .. " missing" end
  local out = { source = "ROM:mail_gra.narc (MailViewer_DrawMail)", designs = {} }
  for t = 0, #M.NAMES - 1 do
    local palette = Gen4Graphics.palette(member(arc, t))
    local sheet = Gen4Graphics.tiles(member(arc, 12 + t))
    local map = Gen4Graphics.tilemap(member(arc, 24 + t))
    local rec = { name = M.NAMES[t + 1] }
    if palette and sheet and map then
      local top = Gen4Graphics.compose(map, sheet, palette)
      rec.top = top and ex:saveImage(("mail/%s_mail"):format(M.NAMES[t + 1]), top) or nil
      local cells = {}
      for i = 1, 32 * 24 do cells[i] = { tile = 1, palette = 2 } end
      local sub = Gen4Graphics.compose({ width = 256, height = 192, cells = cells }, sheet, palette)
      rec.sub = sub and ex:saveImage(("mail/%s_mail_sub"):format(M.NAMES[t + 1]), sub) or nil
    else
      rec.refused = "palette, tiles or screen did not decode"
    end
    out.designs[t + 1] = rec
  end
  return out
end

return M
