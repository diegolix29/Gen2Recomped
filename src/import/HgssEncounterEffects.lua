-- HEARTGOLD / SOULSILVER'S BATTLE-TRANSITION PICTURES, out of /a/1/0/9 (the
-- NARC ov01_021EFC94 opens for every effect; Platinum's is
-- /graphic/field_encounteffect.narc, src/import/Gen4EncounterEffects.lua).
--
-- Written into the same cache module, `gen4_encounter_effects`, in the same
-- shape (indices + palettes, see that file), under keys of HGSS's own:
--
--   hgss_ball        pal 0, char 4, cell 6, anim 5    effects 6, 8, 10, 11, 38
--   hgss_ball_split  pal 0, char 7, cell 9, anim 8    effects 7, 9, 37 (seqs 1/2: the halves)
--   hgss_red         pal 1, char 10, cell 12, anim 11 effect 46
--   hgss_water_bg1   pal 160, char 161, scrn 162      effects 2, 3 (256x512)
--   hgss_water_bg3   pal 160, char 164, scrn 165
--
-- Palettes are stored as "hgss/<member>".

local H = {}

H.PATH = "/a/1/0/9"

H.OBJS = {
  { "hgss_ball", 0, 4, 6, 5 },
  { "hgss_ball_split", 0, 7, 9, 8 },
  { "hgss_red", 1, 10, 12, 11 },
}
H.BGS = {
  { "hgss_water_bg1", 160, 161, 162 },
  { "hgss_water_bg3", 160, 164, 165 },
}

function H.paletteName(member) return "hgss/" .. member end

-- 12-28, the gym leaders and the rival (ov115 tables 022603B0.., 02260374):
-- the mugshot is pal / char / cell / anim 0x3F + 4 (id - 12) on; the band
-- slot is (id - 12) % 8 -- Kanto's leaders reuse Johto's -- or 8 for the
-- rival, at pal / char / scrn 0x15 / 0x14 / 0x16 + 3 slot. Written as
-- "hgss_leader_<id>/mugshot" and "hgss_band_<slot>/banner", with palettes
-- under the names Gen4BattleTransition looks them up by (<key>.NCLR).
function H.leader(id)
  local m = 0x3F + 4 * (id - 12)
  local slot = id == 28 and 8 or (id - 12) % 8
  return { mug = { m, m + 1, m + 2, m + 3 }, slot = slot,
           band = { 0x15 + 3 * slot, 0x14 + 3 * slot, 0x16 + 3 * slot } }
end
H.VS = { "hgss_vs", 0x3B, 0x3C, 0x3D, 0x3E }
H.NAME_PALETTE = 0x10

local IDENTITY = {}
for i = 0, 255 do IDENTITY[i + 1] = { i, 0, 0 } end

local function hexOf(image)
  local out = {}
  local rgba = image.rgba
  for p = 0, image.width * image.height - 1 do
    local r, a = rgba:byte(p * 4 + 1), rgba:byte(p * 4 + 4)
    out[p + 1] = ("%02x"):format(a == 0 and 0 or r)
  end
  return table.concat(out)
end

-- extract(rom, into) -> the record (into, when given, gains the keys)
function H.extract(rom, into)
  local Narc = require("src.import.NarcArchive")
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local raw = rom and rom:read(H.PATH)
  if not raw then return nil, "no " .. H.PATH end
  local arc = Narc.parse(raw)
  if not arc then return nil, H.PATH .. " did not parse" end
  local function member(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local out = into or { images = {}, palettes = {}, anims = {} }
  out.images, out.palettes, out.anims = out.images or {}, out.palettes or {}, out.anims or {}

  local function palette(i)
    local name = H.paletteName(i)
    if out.palettes[name] == nil then
      local b = member(i)
      out.palettes[name] = b and G.palette(b) or nil
    end
    return out.palettes[name]
  end

  for _, o in ipairs(H.OBJS) do
    local key, pal, tiles, cell, anim = o[1], o[2], o[3], o[4], o[5]
    local sheet = member(tiles) and G.tiles(member(tiles))
    local bank = member(cell) and Cells.parse(member(cell), G)
    if sheet and bank then
      local list = {}
      for i, c in ipairs(bank.cells) do
        local image = Cells.assemble(c, sheet, IDENTITY, bank, G)
        if image then
          local x, y = Cells.extent(c)
          list[i] = { w = image.width, h = image.height, x = x, y = y, idx = hexOf(image) }
        end
      end
      out.images[key] = list
      palette(pal)
      local a = member(anim) and Anim.parse(member(anim), G)
      if a then
        local seqs = {}
        for s, seq in ipairs(a.sequences or {}) do
          local frames = {}
          for f, fr in ipairs(seq.frames or {}) do
            frames[f] = { cell = fr.cell, duration = fr.duration, x = fr.x, y = fr.y }
          end
          seqs[s] = frames
        end
        out.anims[key] = seqs
      end
    end
  end

  -- the leaders' mugshots, the VS, and the bands (cropped to their drawn rows)
  local function objInto(key, palName, pal, tiles, cell, anim)
    local sheet = member(tiles) and G.tiles(member(tiles))
    local bank = member(cell) and Cells.parse(member(cell), G)
    if not (sheet and bank) then return end
    local list = {}
    for i, c in ipairs(bank.cells) do
      local image = Cells.assemble(c, sheet, IDENTITY, bank, G)
      if image then
        local x, y = Cells.extent(c)
        list[i] = { w = image.width, h = image.height, x = x, y = y, idx = hexOf(image) }
      end
    end
    out.images[key] = list
    local pb = member(pal)
    out.palettes[palName] = pb and G.palette(pb) or out.palettes[palName]
    local a = member(anim) and Anim.parse(member(anim), G)
    if a then
      local seqs = {}
      for si, seq in ipairs(a.sequences or {}) do
        local frames = {}
        for f, fr in ipairs(seq.frames or {}) do
          frames[f] = { cell = fr.cell, duration = fr.duration, x = fr.x, y = fr.y }
        end
        seqs[si] = frames
      end
      out.anims[key] = seqs
    end
  end
  for id = 12, 28 do
    local L = H.leader(id)
    local key = ("hgss_leader_%d/mugshot"):format(id)
    pcall(objInto, key, key .. ".NCLR", L.mug[1], L.mug[2], L.mug[3], L.mug[4])
    local band = ("hgss_band_%d/banner"):format(L.slot)
    if not out.images[band] then
      local sheet = member(L.band[2]) and G.tiles(member(L.band[2]))
      local m = member(L.band[3]) and G.tilemap(member(L.band[3]))
      local image = sheet and m and G.compose(m, sheet, IDENTITY)
      if image then
        -- the drawn rows only, and where they start (rows 43..100)
        local w, top, bottom = image.width, nil, nil
        for y = 0, image.height - 1 do
          for x = 0, w - 1 do
            if image.rgba:byte((y * w + x) * 4 + 4) ~= 0 then top = top or y; bottom = y; break end
          end
        end
        if top then
          local band8 = { width = w, height = bottom - top + 1,
                          rgba = image.rgba:sub(top * w * 4 + 1, (bottom + 1) * w * 4) }
          out.images[band] = { { w = w, h = band8.height, x = 0, y = top, idx = hexOf(band8) } }
          local pb = member(L.band[1])
          out.palettes[band .. ".NCLR"] = pb and G.palette(pb) or nil
        end
      end
    end
  end
  pcall(objInto, H.VS[1], H.paletteName(H.VS[2]), H.VS[2], H.VS[3], H.VS[4], H.VS[5])
  -- 39's "R" (pal 3, char 0x9C, cell 0x9E, anim 0x9D) and 40-44's mugshots
  -- (0xDE + 4 (id - 40) on: Petrel, Proton, Archer, Ariana, Giovanni)
  pcall(objInto, "hgss_rocket_r", H.paletteName(3), 3, 0x9C, 0x9E, 0x9D)
  for id = 40, 44 do
    local m = 0xDE + 4 * (id - 40)
    local key = ("hgss_exec_%d/mugshot"):format(id)
    pcall(objInto, key, key .. ".NCLR", m, m + 1, m + 2, m + 3)
  end
  -- 40-44's backgrounds (chars 0xD8, palettes 0xD7: speed lines 0xD9, the
  -- dark panel with the R outline 0xDA, the rails and filled R 0xDD) and
  -- 45's shoji door (pal 0xA6, char 0xA7, scrn 0xA8) -- the right door is
  -- BG3's copy, its top 96 rows mirrored per 128 px half (ov01_021F0500's
  -- short loop)
  local function bgInto(key, palMember, tiles, scrn, mirrorTop)
    local sheet = member(tiles) and G.tiles(member(tiles))
    local m = member(scrn) and G.tilemap(member(scrn))
    local image = sheet and m and G.compose(m, sheet, IDENTITY)
    if not image then return end
    if mirrorTop then
      local w, rows = image.width, {}
      for y = 0, image.height - 1 do
        local row = image.rgba:sub(y * w * 4 + 1, (y + 1) * w * 4)
        if y < mirrorTop then
          local px = {}
          for x = 0, w - 1 do
            local half = math.floor(x / 128) * 128
            local sx = half + 127 - (x - half)
            px[x + 1] = row:sub(sx * 4 + 1, sx * 4 + 4)
          end
          row = table.concat(px)
        end
        rows[#rows + 1] = row
      end
      image = { width = w, height = image.height, rgba = table.concat(rows) }
    end
    out.images[key] = { { w = image.width, h = image.height, x = 0, y = 0, idx = hexOf(image) } }
    local pb = member(palMember)
    out.palettes[H.paletteName(palMember)] = out.palettes[H.paletteName(palMember)]
                                              or (pb and G.palette(pb)) or nil
  end
  pcall(bgInto, "hgss_rocket_lines", 0xD7, 0xD8, 0xD9)
  pcall(bgInto, "hgss_rocket_panel", 0xD7, 0xD8, 0xDA)
  pcall(bgInto, "hgss_rocket_rails", 0xD7, 0xD8, 0xDD)
  pcall(bgInto, "hgss_kimono", 0xA6, 0xA7, 0xA8)
  pcall(bgInto, "hgss_kimono_mirror", 0xA6, 0xA7, 0xA8, 96)
  -- 29-33: the player's mugshot (0xCF.. boy, 0xD3.. girl), the opponents'
  -- (0x83 + 4 (id - 29) on: Will, Koga, Bruno, Karen, Lance), and the flame
  -- streak (char 0x30, cell 0x31, anim 0x32; 24 cells whose OAM palette is
  -- cell % 12) under each member's twelve-palette set
  pcall(objInto, "hgss_player_male/mugshot", "hgss_player_male/mugshot.NCLR", 0xCF, 0xD0, 0xD1, 0xD2)
  pcall(objInto, "hgss_player_female/mugshot", "hgss_player_female/mugshot.NCLR", 0xD3, 0xD4, 0xD5, 0xD6)
  for id = 29, 33 do
    local m = 0x83 + 4 * (id - 29)
    local key = ("hgss_e4_%d/mugshot"):format(id)
    pcall(objInto, key, key .. ".NCLR", m, m + 1, m + 2, m + 3)
  end
  pcall(objInto, "hgss_streak", H.paletteName(0x2F), 0x2F, 0x30, 0x31, 0x32)
  for _, pm in ipairs({ 0x33, 0x34, 0x35, 0x36 }) do
    local pb = member(pm)
    out.palettes[H.paletteName(pm)] = pb and G.palette(pb) or nil
  end
  -- the name's colours (BG palette 2 = member 0x10: 1 white, 2 #4A5252),
  -- where the shared name drawing reads Platinum's enc_fade (2*16+2, +3)
  local np = member(H.NAME_PALETTE) and G.palette(member(H.NAME_PALETTE))
  if np and not out.palettes[".shared/enc_fade.NCLR"] then
    local fake = {}
    for i = 1, 256 do fake[i] = { 0, 0, 0 } end
    fake[2 * 16 + 2], fake[2 * 16 + 3] = np[2], np[3]
    out.palettes[".shared/enc_fade.NCLR"] = fake
  end

  for _, b in ipairs(H.BGS) do
    local key, pal, tiles, scrn = b[1], b[2], b[3], b[4]
    local sheet = member(tiles) and G.tiles(member(tiles))
    local m = member(scrn) and G.tilemap(member(scrn))
    local image = sheet and m and G.compose(m, sheet, IDENTITY)
    if image then
      out.images[key] = { { w = image.width, h = image.height, x = 0, y = 0, idx = hexOf(image) } }
      palette(pal)
    end
  end
  return out
end

return H
