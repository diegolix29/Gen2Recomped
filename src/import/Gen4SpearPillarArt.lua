-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SPEAR PILLAR CINEMATIC ART: /arc/demo_tengan_gra.narc, the
-- archive the overlay ScrCmd_2FB launches reads everything from (pokeplatinum
-- src/cutscenes/spear_pillar/*.c, formerly src/overlay100), plus the Poketch's
-- "unavailable" screen the first stage puts on the sub screen.
--
-- READ FROM CODE, member by member (the archive has no name table; every
-- index is the C's own literal):
--
--   dialga_palkia_arrival.c  46 the stage (CastModels.unk_04, no animation)
--                            24 shockwave + 22 BCA, 23 BMA
--                            79 falling summon ball + 77 BCA, 78 BMA,
--                               80 BTA, 81 BVA   (one copy each for Dialga
--                               and Palkia, all four tracks played)
--                            65 the round shadow under each figure
--                            66 Dialga + 67 BTP   68 Palkia + 69 BTP
--                            84 whirlpool + 82 BCA, 83 BMA (twice, cloned)
--                            61 Lucas + 62 BTP    63 Dawn + 64 BTP
--                            13 Cyrus + 14 BTP
--   lake_guardians_arrival.c 59 Uxie + 57 BCA, 58 BMA
--                            45 Mesprit + 43 BCA, 44 BMA
--                            17 Azelf + 15 BCA, 16 BMA
--                            60 the backlight
--                            70 sub BG tiles, 71 palette (2 x 16 colours,
--                               from the file's start), 72 sub BG1 screen,
--                               73 sub BG0 screen
--                            47 NANR, 48 NCER, 49 NCGR, 50 NCLR (3 palettes):
--                               the lake guardians' lights
--   giratina_intervention.c  26 + 25 BCA, 27 BTA   Giratina rising
--                            29 + 28 BCA, 30 BTA   ...settled
--                            32 + 31 BCA, 33 BTA   ...wings spread
--                            35 + 34 BCA, 36 BTA   ...lunge-ready
--                            38 + 37 BCA, 39 BTA   ...the attack
--                            41 + 40 BCA           the shadow pool
--                            42                    the red eyes
--                            53 + 51 BCA, 52 BMA   the droplet splash
--                            55 + 54 BCA, 56 BTA   the distortion ripple
--                            18 sub BG tiles, 19 palette (sub AND main BG,
--                               2 x 16), 20 sub BG1 screen
--   overlay 6 (ScrCmd_20D mode 0, the field's Red Chain effect before the
--   app starts: ov6_022401B8 / ov6_02240260)
--                            6 + 4 BCA, 5 BMA      the chain model
--                            74 tiles, 75 palette (one 16-colour row into
--                               main BG palette 6), 76 field BG2 screen
--   /graphic/poketch.narc   10 unavailable_bg_tiles.NCGR, 11 unavailable.NSCR,
--                           12 its NCLR (first 16 colours) -- poketch.order
--
-- Each model is packed the way Gen4HgssLegendArt packs its own (Gen4ModelPack
-- + its own textures); its animations stay SEPARATE TRACKS in load order,
-- because an Easy3DAnim carries its own frame and the C drives them one by
-- one (`anims[0]` is the main track, `anims[1]` the "secondary" one, and the
-- falling ball plays all four).

local A = { PATH = "/arc/demo_tengan_gra.narc", POKETCH = "/graphic/poketch.narc" }

A.PARTS = {
  stage       = { model = 46, anims = {} },
  shockwave   = { model = 24, anims = { 22, 23 } },
  ball        = { model = 79, anims = { 77, 78, 80, 81 } },
  shadow      = { model = 65, anims = {} },
  dialga      = { model = 66, anims = { 67 } },
  palkia      = { model = 68, anims = { 69 } },
  whirlpool   = { model = 84, anims = { 82, 83 } },
  lucas       = { model = 61, anims = { 62 } },
  dawn        = { model = 63, anims = { 64 } },
  cyrus       = { model = 13, anims = { 14 } },
  uxie        = { model = 59, anims = { 57, 58 } },
  mesprit     = { model = 45, anims = { 43, 44 } },
  azelf       = { model = 17, anims = { 15, 16 } },
  backlight   = { model = 60, anims = {} },
  giraRise    = { model = 26, anims = { 25, 27 } },
  giraFloat   = { model = 29, anims = { 28, 30 } },
  giraWings   = { model = 32, anims = { 31, 33 } },
  giraLunge   = { model = 35, anims = { 34, 36 } },
  giraAttack  = { model = 38, anims = { 37, 39 } },
  shadowPool  = { model = 41, anims = { 40 } },
  redEyes     = { model = 42, anims = {} },
  splash      = { model = 53, anims = { 51, 52 } },
  ripple      = { model = 55, anims = { 54, 56 } },
  chain       = { model = 6,  anims = { 4, 5 } },
}

A.LAKE = { tiles = 70, palette = 71, bg1 = 72, bg0 = 73 }
A.GIRA = { tiles = 18, palette = 19, bg1 = 20 }
A.LIGHTS = { anim = 47, cells = 48, tiles = 49, palette = 50, palettes = 3 }
A.CHAIN_BG = { tiles = 74, palette = 75, screen = 76 }
A.POKETCH_UNAVAILABLE = { tiles = 10, screen = 11, palette = 12 }
-- SpearPillarCutscene_UpdateBackgroundPulse: colours 0-3 and 4-9 of the
-- sub BG palette blended toward 0xCCCC
A.PULSE_COLOURS = 10

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Narc = require("src.import.NarcArchive")
  local Models = require("src.import.Gen4Models")
  local Anim = require("src.import.Gen4Anim")
  local Pack = require("src.import.Gen4ModelPack")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local arc = assert(Narc.parse(assert(x.rom:read(A.PATH), "no " .. A.PATH)))
  local function member(i, from)
    local b = assert((from or arc):get(i), "demo_tengan_gra member " .. tostring(i))
    if G.isCompressed(b) then return assert(G.decompress(b)) end
    return b
  end
  local out = { source = "ROM:" .. A.PATH .. " (pokeplatinum src/cutscenes/spear_pillar)",
                parts = {}, bg = {} }
  local written = {}

  local function textureImage(prefix, tex, bytes, name, paletteName)
    local key = prefix .. name .. "/" .. tostring(paletteName)
    if written[key] ~= nil then return written[key] end
    local ti, pi
    for k, t in ipairs(tex.textures) do if t.name == name then ti = k end end
    for k, p in ipairs(tex.palettes) do if p.name == paletteName then pi = k end end
    if not ti then written[key] = false return false end
    local image = Models.decode(tex, bytes, ti, pi or 1)
    local saved = image and x:saveImage(("spear_pillar/%s%s_%d"):format(prefix, name, pi or 1), image)
    written[key] = saved and (type(saved) == "table" and saved.path or saved) or false
    return written[key]
  end

  -- which node each shape hangs under (the last NODEDESC before it in the
  -- render walk), for a visibility track to switch off
  local function shapeNodes(ops)
    local map, node = {}, nil
    for _, op in ipairs(ops or {}) do
      if op.op == "node" then node = op.node
      elseif op.op == "shape" and node then map[op.shape] = node end
    end
    return map
  end

  for name, spec in pairs(A.PARTS) do
    local ok, err = pcall(function()
      local bytes = member(spec.model)
      local parsed = assert(Nsbmd.parse(bytes))
      local packed = Pack.pack(assert(parsed.models[1]))
      local texAt = bytes:find("TEX0", 1, true)
      local tex = texAt and Models.parse(bytes, texAt - 1)
      local prefix = ("m%d_"):format(spec.model)
      for _, shape in ipairs(packed.shapes) do
        if shape.texture and tex then
          shape.image = textureImage(prefix, tex, bytes, shape.texture, shape.palette) or nil
        end
      end
      packed.shapeNodes = shapeNodes(packed.ops)
      local part = { model = packed, tracks = {}, member = spec.model }
      for k, m in ipairs(spec.anims) do
        local data = member(m)
        local parsed2 = Anim.parse(data)
        local animation = parsed2 and parsed2.animations and parsed2.animations[1]
        local track = { member = m, kind = parsed2 and parsed2.kind, frames = 1 }
        if animation then
          track.frames = math.max(1, tonumber(animation.frames) or 1)
          local kind = parsed2.kind
          if kind == "BCA0" then
            local motion = { frames = track.frames, tracks = {} }
            for _, joint in ipairs(Anim.jointMatrices(data, animation) or {}) do
              motion.tracks[joint.index] = Anim.packTrack(joint.track)
            end
            track.motion = motion
          elseif kind == "BTA0" then
            track.record = { kind = "BTA0", frames = track.frames, srt = Anim.textureSrt(data, animation) }
          elseif kind == "BTP0" then
            local pattern = Anim.texturePattern(data, animation)
            track.record = { kind = "BTP0", frames = track.frames, pattern = pattern }
            packed.patternImages = packed.patternImages or {}
            for i, texName in ipairs((pattern and pattern.textures) or {}) do
              if packed.patternImages[texName] == nil and tex then
                local pal = (pattern.palettes or {})[i] or (pattern.palettes or {})[1]
                packed.patternImages[texName] = textureImage(prefix, tex, bytes, texName, pal)
              end
            end
          elseif kind == "BMA0" then
            track.record = { kind = "BMA0", frames = track.frames, colour = Anim.materialColour(data, animation) }
          elseif kind == "BVA0" then
            track.visibility = Anim.visibility(data, animation)
          end
        end
        part.tracks[k] = track
      end
      out.parts[name] = part
    end)
    if not ok then
      out.failed = out.failed or {}
      out.failed[name] = tostring(err)
    end
  end

  -- a 2 x 16-colour load from the file's start (PaletteData_LoadBuffer-
  -- FromFileStart, PALETTE_SIZE_BYTES * 2): the raw colours, file order
  local function rawPalette(bytes, count)
    local pal = assert(G.palette(bytes, true))
    local outPal = {}
    for i = 1, count do outPal[i] = pal[i] or { 0, 0, 0 } end
    return outPal
  end
  local function hex(c) return ("%02x%02x%02x"):format(c[1], c[2], c[3]) end
  local function save(key, pic)
    local rec = pic and x:saveImage("spear_pillar/" .. key, pic)
    return rec and (type(rec) == "table" and rec.path or rec) or nil
  end
  -- the same screen with every colour but the masked ones transparent and
  -- those white: drawn tinted, it is a PaletteData_Blend of just those
  local function mask(map, sheet, pal, first, count)
    local m = {}
    for i = 1, #pal do m[i] = { 255, 0, 255 } end
    for i = first + 1, first + count do m[i] = { 255, 255, 255 } end
    local pic = G.compose(map, sheet, m)
    if not pic then return nil end
    local parts = {}
    local rgba = pic.rgba
    for i = 1, #rgba, 4 do
      local r, g, b = rgba:byte(i, i + 2)
      if r == 255 and g == 0 and b == 255 then parts[#parts + 1] = "\0\0\0\0"
      else parts[#parts + 1] = rgba:sub(i, i + 3) end
    end
    pic.rgba = table.concat(parts)
    return pic
  end

  local okL, errL = pcall(function()
    local sheet = assert(G.tiles(member(A.LAKE.tiles)))
    local pal = rawPalette(member(A.LAKE.palette), 32)
    out.bg.lake = {
      bg1 = save("lake_bg1", G.compose(assert(G.tilemap(member(A.LAKE.bg1))), sheet, pal)),
      bg0 = save("lake_bg0", G.compose(assert(G.tilemap(member(A.LAKE.bg0))), sheet, pal)),
      backdrop = hex(pal[1]),
    }
  end)
  if not okL then out.lakeError = tostring(errL) end

  local okG, errG = pcall(function()
    local sheet = assert(G.tiles(member(A.GIRA.tiles)))
    local pal = rawPalette(member(A.GIRA.palette), 32)
    local map = assert(G.tilemap(member(A.GIRA.bg1)))
    out.bg.gira = {
      bg1 = save("gira_bg1", G.compose(map, sheet, pal)),
      pulse = save("gira_bg1_pulse", mask(map, sheet, pal, 0, A.PULSE_COLOURS)),
      backdrop = hex(pal[1]),
    }
  end)
  if not okG then out.giraError = tostring(errG) end

  local okP, errP = pcall(function()
    local p = assert(Narc.parse(assert(x.rom:read(A.POKETCH), "no " .. A.POKETCH)))
    local sheet = assert(G.tiles(member(A.POKETCH_UNAVAILABLE.tiles, p)))
    local pal = rawPalette(member(A.POKETCH_UNAVAILABLE.palette, p), 16)
    out.bg.unavailable = {
      bg0 = save("poketch_unavailable", G.compose(assert(G.tilemap(member(A.POKETCH_UNAVAILABLE.screen, p))), sheet, pal)),
      backdrop = hex(pal[1]),
    }
  end)
  if not okP then out.poketchError = tostring(errP) end

  -- the Red Chain's field overlay (overlay 6): Graphics_LoadPalette(75, main
  -- BG, 0x20 * 6, 0x20) puts the file's first sixteen colours in row 6
  local okC, errC = pcall(function()
    local sheet = assert(G.tiles(member(A.CHAIN_BG.tiles)))
    local raw = rawPalette(member(A.CHAIN_BG.palette), 16)
    local pal = {}
    for i = 1, 16 * 16 do pal[i] = { 0, 0, 0 } end
    for i = 1, 16 do pal[6 * 16 + i] = raw[i] end
    out.bg.chain = { bg2 = save("chain_bg2", G.compose(assert(G.tilemap(member(A.CHAIN_BG.screen))), sheet, pal)) }
  end)
  if not okC then out.chainError = tostring(errC) end

  -- the lights: one picture per cell per palette (ManagedSprite_Set-
  -- ExplicitPaletteOffset(sprite, i) for light i)
  local okS, errS = pcall(function()
    local Cells = require("src.import.Gen4Cells")
    local CellAnim = require("src.import.Gen4CellAnim")
    local bank = assert(Cells.parse(member(A.LIGHTS.cells), G))
    local anim = assert(CellAnim.parse(member(A.LIGHTS.anim), G))
    local sheet = assert(G.tiles(member(A.LIGHTS.tiles)))
    local pal = rawPalette(member(A.LIGHTS.palette), 16 * A.LIGHTS.palettes)
    local lights = { cells = {}, sequences = {} }
    for p = 0, A.LIGHTS.palettes - 1 do
      local slot = {}
      for i = 1, 16 * 16 do slot[i] = pal[p * 16 + ((i - 1) % 16) + 1] end
      local cells = {}
      for i, cell in ipairs(bank.cells) do
        local pic = Cells.assemble(cell, sheet, slot, bank, G)
        if pic then
          local minX, minY = Cells.extent(cell)
          local rec = x:saveImage(("spear_pillar/light_p%d_%d"):format(p, i - 1), pic,
                                  { originX = -minX, originY = -minY })
          cells[i - 1] = rec
        end
      end
      lights.cells[p] = cells
    end
    for s, seq in ipairs(anim.sequences) do
      local frames = {}
      for f, fr in ipairs(seq.frames) do
        frames[f] = { cell = fr.cell, duration = fr.duration }
      end
      lights.sequences[s - 1] = { frames = frames, loopStart = seq.loopStart, playbackMode = seq.playbackMode }
    end
    out.lights = lights
  end)
  if not okS then out.lightsError = tostring(errS) end

  return out
end

return A
