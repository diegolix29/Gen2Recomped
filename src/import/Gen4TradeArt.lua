-- THE IN-GAME TRADE CUTSCENE'S ART -- Platinum's /graphic/demo_trade.narc and
-- HeartGold / SoulSilver's /a/0/8/9, which is the SAME ARCHIVE BYTE FOR BYTE
-- (all 28 members compare equal across the two cartridges), plus the two
-- "Pokemon standing on a platform" tilemaps each borrows from its battle
-- background archive.
--
-- pokeplatinum src/cutscenes/trade_sequence/*.c names every member it loads
-- (NARC_INDEX_GRAPHIC__DEMO_TRADE is NarcID 93, which is why half the calls
-- say `93` instead of the name); HeartGold's overlay 71 (TradeSequence_Init /
-- _Main / _Exit, still assembly in pokeheartgold) loads NARC 0x59 -- /a/0/8/9
-- -- with the same member numbers at the same call sites:
--
--   21 / 22 / 23   the send and receive phases' BG2 backdrop (16-colour)
--    0 / 2 / 3     the tube's BG2: an AFFINE 1024x1024 map (one byte a cell)
--                  on an 8bpp sheet; colours 0-15 from palette 3, then 32
--                  colours of palette 3 picked by the time of day
--                  (sPaletteOffsets 0x20 / 0x60 / 0xA0 / 0xE0 bytes) loaded
--                  over colours 16-47
--    1             the same layer's map for the Pokemon-reveal phase
--    4 / 5         BG3 under it: an extended-affine 256-colour map whose
--                  colours come from BG EXTENDED palette slot 3 -- which the
--                  game CLEARS and then lights one entry at a time
--                  (PaletteShimmerEffect, main.c): the running lights in the
--                  tube. Written here as one white mask per colour index.
--    6             the palette PaletteShimmerEffect_New loads and then
--                  overwrites with zeroes before it is ever used -- not read
--    7 / 8 / 9 / 10   the Poke Ball OBJ: NCER, NANR, NCGR, NCLR (the flash
--                  as the ball opens or shuts, sequences 0-3)
--   11 / 12 / 13 / 14 the tube's drifting sparkles: NCER, NANR, NCGR, NCLR
--   15 / 16 / 17   the sky behind the ball's fly-by and arrival (256x512);
--                  palette 17 at colour 0 / 16 / 32 for day / evening / night
--   18 / 19 / 20   the wormhole both Pokemon pass through
--   24 / 25 / 26   the Wi-Fi sky -- TRADE_BACKGROUND_WIFI, which an in-game
--                  trade never asks for (NPCTrade_FillAnimationTemplate only
--                  picks day, evening or night), so it is not written
--   27             the Poke Ball, an NSBMD with its own textures
--
-- And the platform: TradeSequence_LoadPokemonPlatform copies a 10x10 cell
-- rectangle of pl_batt_bg member 262 (the sending Pokemon, and the received
-- one when its species may be mirrored) or 263 (a receiving species whose
-- personal-data flip bit is clear) onto the wormhole layers -- an
-- arrangement of the Pokemon's own 80x80 picture. HeartGold reads members
-- 266 / 267 of /a/0/0/7 at the same call site (ov71_02247230). Only what the
-- arrangement DOES is kept: whether it mirrors the picture.
--
-- Pictures go to assets/generated/gen4/trade/; the index (`gen4_trade_art`)
-- also carries the version's message bank (Platinum 350, HeartGold 179 --
-- ov71's NewMsgDataFromNarc(0, 0x1B, 0xB3)), music and fanfare names, the
-- cell animations and the packed model.

local A = {}

A.PLATINUM = {
  archive = "/graphic/demo_trade.narc",
  battleBg = "/battle/graphic/pl_batt_bg.narc", platforms = { 262, 263 },
  bank = 350,
  -- Sound_SetSceneAndPlayBGM(SOUND_SCENE_3, SEQ_KOUKAN, 1) and
  -- Sound_PlayFanfare(SEQ_FANFA5) in receive_phase.c
  bgm = "SEQ_KOUKAN", fanfare = "SEQ_FANFA5",
}
A.HGSS = {
  archive = "/a/0/8/9",
  battleBg = "/a/0/0/7", platforms = { 266, 267 },
  bank = 179,
  -- ov71: Sound_SetSceneAndPlayBGM(3, 0xFD << 2 = 1012 SEQ_GS_KOUKAN, 1) and
  -- PlayFanfare(0x4A4 = 1188 SEQ_ME_SHINKAOME)
  bgm = "SEQ_GS_KOUKAN", fanfare = "SEQ_ME_SHINKAOME",
}

-- the three skies an in-game trade can ask for (TRADE_BACKGROUND_DAY,
-- _EVENING, _NIGHT)
A.BACKGROUNDS = 3
-- tube_phase.c / pokemon_reveal_phase.c sPaletteOffsets, in bytes
A.TUBE_PALETTE_OFFSETS = { 0x20, 0x60, 0xA0, 0xE0 }

function A.config(version)
  local okV, V = pcall(require, "src.import.Gen4Versions")
  if okV and V.isHgss and V.isHgss(version) then return A.HGSS end
  return A.PLATINUM
end

-- one picture of a cell (every OAM entry), origin at the sprite's position
local function cellImages(G, Cells, Anim, member, prefix, x, out, saved)
  local bank = assert(Cells.parse(member(0), G))
  local anim = assert(Anim.parse(member(1), G))
  local sheet = assert(G.tiles(member(2)))
  local palette = assert(G.palette(member(3)))
  local cells = {}
  for i, cell in ipairs(bank.cells) do
    local pic = Cells.assemble(cell, sheet, palette, bank, G)
    if pic then
      local minX, minY = Cells.extent(cell)
      pic.originX, pic.originY = -minX, -minY
      local rec = x:saveImage(("trade/%s_%d"):format(prefix, i - 1), pic,
                              { originX = -minX, originY = -minY })
      cells[i - 1] = rec
      saved[#saved + 1] = rec
    end
  end
  local sequences = {}
  for s, seq in ipairs(anim.sequences) do
    local frames = {}
    for f, fr in ipairs(seq.frames) do
      frames[f] = { cell = fr.cell, duration = fr.duration, x = fr.x, y = fr.y,
                    rotation = fr.rotation, scaleX = fr.scaleX, scaleY = fr.scaleY }
    end
    sequences[s - 1] = { frames = frames, loopStart = seq.loopStart, playbackMode = seq.playbackMode }
  end
  out[prefix] = { cells = cells, sequences = sequences }
end

function A.build(x, config)
  config = config or A.config(x.version)
  local G = require("src.import.Gen4Graphics")
  local Narc = require("src.import.NarcArchive")
  local arc = assert(Narc.parse(assert(x.rom:read(config.archive))))
  local function member(i)
    local b = assert(arc:get(i), "demo_trade member " .. i)
    if G.isCompressed(b) then return assert(G.decompress(b)) end
    return b
  end
  local out = {
    source = "ROM:" .. config.archive .. " (pokeplatinum src/cutscenes/trade_sequence; pokeheartgold overlay 71)",
    bank = config.bank, bgm = config.bgm, fanfare = config.fanfare,
  }
  local function save(key, pic, extra)
    local rec = pic and x:saveImage("trade/" .. key, pic, extra)
    out[key] = rec or nil
    return rec
  end

  -- THE SEND / RECEIVE BACKDROP (BG2, palette slot 0)
  save("stage", G.compose(assert(G.tilemap(member(21))), assert(G.tiles(member(22))),
                          (assert(G.palette(member(23))))))

  -- THE TUBE AND THE REVEAL (BG2, affine). Graphics_LoadPalette(.., 3, .., 0,
  -- 0x20) puts the first 16 colours in place; Graphics_LoadPaletteWithSrcOffset
  -- (93, 3, .., sPaletteOffsets[bg], 0x20, 0x40) then copies 32 colours from
  -- that byte offset to colour 16. Every other colour stays black.
  local tubeSheet = assert(G.tiles(member(2)))
  local tubePalette = assert(G.palette(member(3)))
  local tubeMap, revealMap = assert(G.tilemap(member(0))), assert(G.tilemap(member(1)))
  for bg = 0, A.BACKGROUNDS - 1 do
    local pal = {}
    for i = 1, 256 do pal[i] = { 0, 0, 0 } end
    for i = 1, 16 do pal[i] = tubePalette[i] or { 0, 0, 0 } end
    local from = A.TUBE_PALETTE_OFFSETS[bg + 1] / 2
    for i = 0, 31 do pal[17 + i] = tubePalette[from + i + 1] or { 0, 0, 0 } end
    save(("tube_%d"):format(bg), G.compose(tubeMap, tubeSheet, pal))
    save(("reveal_%d"):format(bg), G.compose(revealMap, tubeSheet, pal))
  end

  -- THE RUNNING LIGHTS (BG3, extended palette slot 3, palette 0). One mask a
  -- colour index: white where the layer's pixel IS that index. The shimmer
  -- only ever lights entries 0-15 (a spark walks -1..15 or 15..-1).
  local lightSheet = assert(G.tiles(member(5)))
  local lightMap = assert(G.tilemap(member(4)))
  local grey = {}
  for i = 0, 255 do grey[i + 1] = { i, i, i } end
  -- the extended palette is 256 colours a palette; a cell's sub-palette
  -- picks one, and the game only ever writes palette 0 -- read every cell
  -- against it
  for _, cell in ipairs(lightMap.cells) do cell.palette = 0 end
  local indexed = G.compose(lightMap, lightSheet, grey)
  out.lights = {}
  if indexed then
    local w, h, px = indexed.width, indexed.height, indexed.rgba
    local used = {}
    for p = 0, w * h - 1 do
      local a = px:byte(p * 4 + 4)
      if a ~= 0 then used[px:byte(p * 4 + 1)] = true end
    end
    for index = 1, 15 do
      if used[index] then
        local parts = {}
        for p = 0, w * h - 1 do
          local on = px:byte(p * 4 + 4) ~= 0 and px:byte(p * 4 + 1) == index
          parts[p + 1] = on and "\255\255\255\255" or "\0\0\0\0"
        end
        out.lights[index] = x:saveImage(("trade/light_%d"):format(index),
                                        { width = w, height = h, rgba = table.concat(parts) })
      end
    end
    -- every lit-able pixel at once, opaque black: what the layer shows where
    -- BG2 is see-through and no spark is on it
    local parts = {}
    for p = 0, w * h - 1 do
      parts[p + 1] = px:byte(p * 4 + 4) ~= 0 and "\0\0\0\255" or "\0\0\0\0"
    end
    out.lightsBase = x:saveImage("trade/lights_base", { width = w, height = h, rgba = table.concat(parts) })
  end

  -- THE SKY (fly-by and arrival): palette 17, 16 colours from colour
  -- 0 / 16 / 32 into slot 0
  local skyPalette = assert(G.palette(member(17)))
  local skyMap, skySheet = assert(G.tilemap(member(15))), assert(G.tiles(member(16)))
  for bg = 0, A.BACKGROUNDS - 1 do
    local pal = {}
    for i = 1, 16 do pal[i] = skyPalette[bg * 16 + i] or { 0, 0, 0 } end
    for _, cell in ipairs(skyMap.cells) do cell.palette = 0 end
    save(("sky_%d"):format(bg), G.compose(skyMap, skySheet, pal))
  end

  -- THE WORMHOLE (BG3 of the wormhole phase)
  save("wormhole", G.compose(assert(G.tilemap(member(18))), assert(G.tiles(member(19))),
                             (assert(G.palette(member(20))))))

  -- THE OBJ CELL ANIMATIONS
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local saved = {}
  cellImages(G, Cells, Anim, function(i) return member(7 + i) end, "ball", x, out, saved)
  cellImages(G, Cells, Anim, function(i) return member(11 + i) end, "spark", x, out, saved)

  -- THE PLATFORMS: does each arrangement mirror the Pokemon's picture?
  out.platforms = {}
  local okB, battle = pcall(function()
    return assert(Narc.parse(assert(x.rom:read(config.battleBg))))
  end)
  if okB then
    for slot, m in ipairs(config.platforms) do
      local okM, map = pcall(function()
        local b = assert(battle:get(m))
        if G.isCompressed(b) then b = assert(G.decompress(b)) end
        return assert(G.tilemap(b))
      end)
      if okM then
        -- the rectangle is the top-left 10x10 of a 32-wide screen
        local first = map.cells[1]
        local flips = first and first.flipX or false
        out.platforms[slot - 1] = { member = m, mirror = flips }
      end
    end
  end

  -- THE POKE BALL (member 27): packed like every other Gen 4 model, its
  -- textures pictures of their own
  local Models = require("src.import.Gen4Models")
  local Pack = require("src.import.Gen4ModelPack")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local bytes = member(27)
  local parsed = assert(Nsbmd.parse(bytes))
  local model = assert(parsed.models[1])
  local packed = Pack.pack(model)
  local texAt = bytes:find("TEX0", 1, true)
  local tex = texAt and Models.parse(bytes, texAt - 1)
  local written = {}
  for _, shape in ipairs(packed.shapes) do
    if shape.texture and tex then
      local key = tostring(shape.texture) .. "/" .. tostring(shape.palette)
      if written[key] == nil then
        local ti, pi
        for k, t in ipairs(tex.textures) do if t.name == shape.texture then ti = k end end
        for k, p in ipairs(tex.palettes) do if p.name == shape.palette then pi = k end end
        local image = ti and Models.decode(tex, bytes, ti, pi or 1)
        local rec = image and x:saveImage(("trade/ball_tex_%s_%d"):format(shape.texture, pi or 1), image)
        written[key] = rec and (type(rec) == "table" and rec.path or rec) or false
      end
      shape.image = written[key] or nil
    end
  end
  -- the box GFXBoxTest_IsModelInView tests (the model header's own), in
  -- model units before the render object's scale
  -- (Gen4Nsbmd reads the header's six as min / max; they are the NNS box,
  -- x y z then WIDTH HEIGHT DEPTH -- the ball's are -2.4 and 4.8 -- and all
  -- six are scaled by posScale like the vertices)
  local s = model.posScale or 1
  local b = model.bounds or {}
  local x0, y0, z0 = (b.minX or -1), (b.minY or -1), (b.minZ or -1)
  packed.box = { x0 * s, y0 * s, z0 * s, (x0 + (b.maxX or 2)) * s,
                 (y0 + (b.maxY or 2)) * s, (z0 + (b.maxZ or 2)) * s }
  out.model = packed
  return out
end

return A
