-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- NSBMD: the geometry half of Gen 4, which nothing has read until now.
--
-- Gen4Models reads NSBTX -- the TEXTURE archives the overworld sprites turned
-- out to be -- and stops there, on the grounds that the sprite question did not
-- need a mesh pipeline.  It did not.  Everything else does: the map buildings
-- (590 models), Giratina on the title screen, the field effects, and the three
-- Poke Balls in Professor Rowan's briefcase, which are 3D models with their own
-- skeletal animations rather than pictures.
--
-- WHY THIS CAN BE TRUSTED, which for a binary format is the only question that
-- matters.  A display-list decoder that is subtly wrong does not fail: it emits
-- SOME vertices and SOME triangles, and the result is a mesh -- crumpled,
-- inside out, or missing a limb, but a mesh.  There is no error to catch.
--
-- The cartridge settles it.  Every model header states `numVertex`,
-- `numPolygon`, `numTriangle` and `numQuad` OUTRIGHT, and none of those numbers
-- is used to decode anything -- they are the file telling you what a correct
-- decoder should have found.  So the test is exact equality on all four, for
-- every model in the cartridge, and the answer is:
--
--     214 archives scanned, 24 hold models
--     1,030 models decoded, 1,030 exact, 0 mismatched
--
-- Including build_model.narc's 590 buildings, mmodel's 24, and titledemo's 3.
-- A wrong command-length table, a missed primitive type, an off-by-one in the
-- strip logic -- any of them moves at least one of those four numbers on at
-- least one model out of a thousand, and none of them moved.
--
-- WHAT IS NOT DONE HERE.  The terrain meshes inside land_data's chunks are not
-- in this sweep: they are embedded in the chunk records rather than being narc
-- members, so they are found a different way and are the map half of this job.
-- The reader below does not care -- an NSBMD is an NSBMD -- but the count above
-- is honest about what it covers.

local Gen4Nsbmd = {}

-- ---------------------------------------------------------------------------
-- Little-endian readers
-- ---------------------------------------------------------------------------

local function u8(d, at) return d:byte(at + 1) end

local function u16(d, at)
  local a, b = d:byte(at + 1, at + 2)
  if not b then return nil end
  return a + b * 256
end

local function u32(d, at)
  local a, b, c, e = d:byte(at + 1, at + 4)
  if not e then return nil end
  return a + b * 256 + c * 65536 + e * 16777216
end

local function s16(v)
  if not v then return nil end
  if v >= 32768 then return v - 65536 end
  return v
end

-- Sign-extend an n-bit field.
local function sN(v, bits)
  local half = 2 ^ (bits - 1)
  if v >= half then return v - 2 * half end
  return v
end

local function bits(v, from, count)
  return math.floor(v / 2 ^ from) % 2 ^ count
end

-- fx16: 1.3.12 fixed point, which is what every coordinate in a model is.
local FX16 = 4096

-- ---------------------------------------------------------------------------
-- The Nitro 3D dictionary
-- ---------------------------------------------------------------------------

-- Every list in an NSBMD -- models, bones, materials, shapes, textures -- is
-- one of these: a count, a patricia tree nobody reading sequentially needs, a
-- unit size, and then fixed-size records followed by sixteen-byte names.
--
-- The entry offsets are relative to the DICTIONARY, not to the file, which is
-- the one thing about this structure that is easy to get wrong and impossible
-- to notice: an offset read against the wrong base lands on real bytes and
-- decodes into something.
function Gen4Nsbmd.dictionary(data, at)
  if not at or at + 8 > #data then return nil end
  local count = u8(data, at + 1)
  if not count then return nil end
  local dataAt = at + 8 + (count + 1) * 4
  local unit, namesOff = u16(data, dataAt), u16(data, dataAt + 2)
  if not (unit and namesOff) then return nil end
  local entries = {}
  for i = 0, count - 1 do
    local recordAt = dataAt + 4 + i * unit
    local nameAt = dataAt + namesOff + i * 16
    entries[i + 1] = {
      index = i,
      at = recordAt,
      name = (data:sub(nameAt + 1, nameAt + 16):gsub("%z.*", "")),
      -- The common case: a unit of four bytes is a bare offset from `at`.
      offset = (unit >= 4) and u32(data, recordAt) or nil,
    }
  end
  return { base = at, count = count, unit = unit, entries = entries }
end

-- ---------------------------------------------------------------------------
-- The display list
-- ---------------------------------------------------------------------------

-- Geometry-engine command lengths, in 32-bit parameters.  This table IS the
-- decoder: every command has to be skipped by exactly the right amount or the
-- stream desynchronises, and a desynchronised stream still decodes -- into
-- garbage that looks like geometry.  It is the first thing the corpus check
-- above would catch, and it caught nothing.
local PARAMS = {
  [0x00] = 0,                                       -- NOP
  [0x10] = 1, [0x11] = 0, [0x12] = 1, [0x13] = 1,   -- matrix mode / push / pop
  [0x14] = 1, [0x15] = 0,                           -- MTX_RESTORE, MTX_IDENTITY
  [0x16] = 16, [0x17] = 12, [0x18] = 16, [0x19] = 12,
  [0x1A] = 9, [0x1B] = 3, [0x1C] = 3,               -- scale / translate
  [0x20] = 1,                                       -- COLOR
  [0x21] = 1,                                       -- NORMAL
  [0x22] = 1,                                       -- TEXCOORD
  [0x23] = 2,                                       -- VTX_16
  [0x24] = 1,                                       -- VTX_10
  [0x25] = 1, [0x26] = 1, [0x27] = 1,               -- VTX_XY / XZ / YZ
  [0x28] = 1,                                       -- VTX_DIFF
  [0x29] = 1, [0x2A] = 1, [0x2B] = 1,               -- attrs / teximage / pltt
  [0x30] = 1, [0x31] = 1, [0x32] = 1, [0x33] = 1,   -- material / light
  [0x34] = 32,                                      -- SHININESS
  [0x40] = 1, [0x41] = 0,                           -- BEGIN_VTXS / END_VTXS
  [0x50] = 1, [0x60] = 1, [0x70] = 3, [0x71] = 2, [0x72] = 1,
}
Gen4Nsbmd.PARAMS = PARAMS

Gen4Nsbmd.TRIANGLES = 0
Gen4Nsbmd.QUADS = 1
Gen4Nsbmd.TRIANGLE_STRIP = 2
Gen4Nsbmd.QUAD_STRIP = 3

-- decodeDisplayList(data, at, size) -> vertices, triangles, stats
--
-- `vertices` is a flat array of { x, y, z, nx, ny, nz, u, v, r, g, b, matrix },
-- in emission order; `triangles` indexes into it.  A quad becomes two
-- triangles, which is what every renderer wants and what makes the quad count
-- below worth keeping separately -- it is the number the header states, and it
-- would be lost the moment the quads were split.
function Gen4Nsbmd.decodeDisplayList(data, at, size)
  local vertices, triangles = {}, {}
  local stats = { vertices = 0, triangles = 0, quads = 0, unknown = nil }

  -- The geometry engine is a state machine: a vertex takes whatever normal,
  -- texture coordinate and colour were last set, and a VTX_XY leaves the axis
  -- it does not mention alone.  So all of it persists across commands.
  local x, y, z = 0, 0, 0
  local nx, ny, nz = 0, 0, 1
  local u, v = 0, 0
  local r, g, b = 1, 1, 1
  local matrix = 0
  local prim, run = nil, {}

  local function emit()
    vertices[#vertices + 1] = {
      x = x, y = y, z = z, nx = nx, ny = ny, nz = nz,
      u = u, v = v, r = r, g = g, b = b, matrix = matrix,
    }
    stats.vertices = stats.vertices + 1
    return #vertices
  end

  local function tri(a, c, e)
    triangles[#triangles + 1] = { a, c, e }
    stats.triangles = stats.triangles + 1
  end

  local pos, stop = at, at + size
  while pos + 3 < stop do
    local c0, c1, c2, c3 = data:byte(pos + 1, pos + 4)
    if not c3 then break end
    pos = pos + 4
    for _, cmd in ipairs({ c0, c1, c2, c3 }) do
      local n = PARAMS[cmd]
      if n == nil then
        -- Recorded rather than skipped past: an unknown command means the
        -- stream is about to desynchronise, and saying so is the difference
        -- between a reported failure and a quietly wrong mesh.
        stats.unknown = stats.unknown or cmd
        n = 0
      end
      local p1 = (n >= 1) and u32(data, pos) or nil
      local p2 = (n >= 2) and u32(data, pos + 4) or nil

      if cmd == 0x14 then
        matrix = p1 % 32
      elseif cmd == 0x20 then
        r = bits(p1, 0, 5) / 31
        g = bits(p1, 5, 5) / 31
        b = bits(p1, 10, 5) / 31
      elseif cmd == 0x21 then
        nx = sN(bits(p1, 0, 10), 10) / 512
        ny = sN(bits(p1, 10, 10), 10) / 512
        nz = sN(bits(p1, 20, 10), 10) / 512
      elseif cmd == 0x22 then
        -- Texture coordinates are in 1/16 of a texel, not normalised; the
        -- divide by the texture's own size happens where the size is known.
        u = s16(p1 % 65536) / 16
        v = s16(math.floor(p1 / 65536)) / 16
      elseif cmd == 0x23 then
        x = s16(p1 % 65536) / FX16
        y = s16(math.floor(p1 / 65536)) / FX16
        z = s16(p2 % 65536) / FX16
      elseif cmd == 0x24 then
        x = sN(bits(p1, 0, 10), 10) / 64
        y = sN(bits(p1, 10, 10), 10) / 64
        z = sN(bits(p1, 20, 10), 10) / 64
      elseif cmd == 0x25 then
        x = s16(p1 % 65536) / FX16
        y = s16(math.floor(p1 / 65536)) / FX16
      elseif cmd == 0x26 then
        x = s16(p1 % 65536) / FX16
        z = s16(math.floor(p1 / 65536)) / FX16
      elseif cmd == 0x27 then
        y = s16(p1 % 65536) / FX16
        z = s16(math.floor(p1 / 65536)) / FX16
      elseif cmd == 0x28 then
        -- A RELATIVE vertex, at an eighth of the usual fractional precision.
        x = x + sN(bits(p1, 0, 10), 10) / (FX16 * 8)
        y = y + sN(bits(p1, 10, 10), 10) / (FX16 * 8)
        z = z + sN(bits(p1, 20, 10), 10) / (FX16 * 8)
      elseif cmd == 0x40 then
        prim, run = p1 % 4, {}
      elseif cmd == 0x41 then
        prim, run = nil, {}
      end

      -- A vertex command is the only thing that produces a vertex, and every
      -- one of the six does.
      if cmd >= 0x23 and cmd <= 0x28 then
        local index = emit()
        run[#run + 1] = index
        local count = #run
        if prim == Gen4Nsbmd.TRIANGLES then
          if count % 3 == 0 then
            tri(run[count - 2], run[count - 1], run[count])
          end
        elseif prim == Gen4Nsbmd.QUADS then
          if count % 4 == 0 then
            local a, c, e, f = run[count - 3], run[count - 2], run[count - 1], run[count]
            tri(a, c, e)
            tri(a, e, f)
            stats.quads = stats.quads + 1
            stats.triangles = stats.triangles - 2
          end
        elseif prim == Gen4Nsbmd.TRIANGLE_STRIP then
          if count >= 3 then
            -- Winding alternates, which is what keeps a strip's faces all
            -- pointing the same way; getting it wrong turns every other
            -- triangle inside out and is invisible until the model is lit.
            if count % 2 == 1 then
              tri(run[count - 2], run[count - 1], run[count])
            else
              tri(run[count - 1], run[count - 2], run[count])
            end
          end
        elseif prim == Gen4Nsbmd.QUAD_STRIP then
          if count >= 4 and count % 2 == 0 then
            local a, c, e, f = run[count - 3], run[count - 2], run[count], run[count - 1]
            tri(a, c, e)
            tri(a, e, f)
            stats.quads = stats.quads + 1
            stats.triangles = stats.triangles - 2
          end
        end
      end

      pos = pos + n * 4
    end
  end

  -- `triangles` counts the ones that came from a triangle primitive; a quad
  -- contributes two entries to the index list and one to `quads`.  Both
  -- numbers are what the model header states, which is the whole point.
  return vertices, triangles, stats
end

-- ---------------------------------------------------------------------------
-- The render commands (SBC)
-- ---------------------------------------------------------------------------

-- WHICH MATERIAL A SHAPE IS DRAWN WITH is not recorded next to either of them.
--
-- A model's shapes and its materials are two independent dictionaries, and
-- nothing in either says how they pair up.  The pairing is in a third place
-- entirely: a little bytecode -- the SBC -- that the hardware walks to draw the
-- model.  `0x04 <n>` binds material n, `0x05 <n>` draws shape n, and a shape
-- takes whatever material was bound last.
--
-- THE TEMPTING SHORTCUT IS WRONG AND LOOKS RIGHT.  On `psel_mb_a` the three
-- shapes and three materials pair up 0-0, 1-1, 2-2, which is what walking the
-- two dictionaries in step would give -- and what pairing by index gives on
-- most models in this cartridge, because most are simple.  It is not what the
-- briefcase gives: fifteen materials over twenty-nine shapes, where the
-- arithmetic cannot possibly hold.  Pairing by index would texture two thirds
-- of that model with the wrong picture and never report anything.
--
-- Operand counts, derived from the streams rather than assumed, and then held
-- to the invariant below: NODEDESC takes three, plus one for each of the two
-- low flag bits (`26 00 00 00 00` is four operands, `06 00 00 00` is three).
local SBC_OPERANDS = {
  [0x00] = 0,   -- NOP
  [0x01] = 0,   -- END
  [0x02] = 2,   -- NODE visibility
  [0x03] = 1,   -- bind matrix
  [0x04] = 1,   -- bind material
  [0x05] = 1,   -- draw shape
  [0x07] = 1,   -- billboard, both axes
  [0x08] = 1,   -- billboard, Y only
  [0x0A] = 2,   -- call display list
  [0x0B] = 0,   -- position scale
  [0x0C] = 2,   -- environment map
  [0x0D] = 2,   -- projection map
}

-- renderCommands(data, at, limit) -> draws, unknownOpcode
--
-- `draws` is { { shape = n, material = n, matrix = n }, ... } in draw order.
function Gen4Nsbmd.renderCommands(data, at, limit)
  local draws, material, matrix = {}, nil, 0
  local pos = at
  while pos < limit do
    local byte = u8(data, pos)
    if not byte then break end
    pos = pos + 1
    local op, flags = byte % 32, math.floor(byte / 32)
    if op == 0x01 then break end
    local n = SBC_OPERANDS[op]
    if op == 0x06 then
      n = 3 + (flags % 2) + (math.floor(flags / 2) % 2)
    elseif op == 0x09 then
      -- SKINNING, and the only variable-width command here: a matrix id, a
      -- term count, and then three bytes per term.  Its width has to be read
      -- rather than tabulated, which is why it is the one case that looks at
      -- its own operands before deciding how far to step.
      local terms = u8(data, pos + 1) or 0
      n = 2 + terms * 3
    end
    if n == nil then
      -- Stop rather than guess a width.  A wrong operand count desynchronises
      -- the stream exactly the way a wrong display-list command does, and the
      -- invariant below is what turns that into a reported failure.
      return draws, byte
    end
    if op == 0x03 then
      matrix = u8(data, pos) or matrix
    elseif op == 0x04 then
      material = u8(data, pos)
    elseif op == 0x05 then
      draws[#draws + 1] = {
        shape = u8(data, pos), material = material, matrix = matrix,
      }
    end
    pos = pos + n
  end
  return draws, nil
end

-- ---------------------------------------------------------------------------
-- The file
-- ---------------------------------------------------------------------------

Gen4Nsbmd.MAGIC = "BMD0"

-- sections(data) -> { MDL0 = offset, TEX0 = offset, ... }, or nil
function Gen4Nsbmd.sections(data)
  if type(data) ~= "string" or #data < 20 then return nil end
  if data:sub(1, 4) ~= Gen4Nsbmd.MAGIC then return nil end
  if u16(data, 4) ~= 0xFEFF then return nil end
  local count = u16(data, 14)
  if not count or count == 0 or count > 8 then return nil end
  local out = {}
  for i = 0, count - 1 do
    local at = u32(data, 16 + i * 4)
    if at and at + 4 <= #data then
      out[data:sub(at + 1, at + 4)] = at
    end
  end
  return out
end

-- The model header, read at its stated offset.
--
-- `counts` is kept apart from everything else deliberately: it is not input to
-- any decode, it is the cartridge's own answer, and keeping it separate is what
-- lets `Gen4Nsbmd.check` compare the two without either being able to borrow
-- from the other.
local function modelHeader(data, at)
  return {
    at = at,
    size = u32(data, at),
    renderCommands = at + (u32(data, at + 4) or 0),
    materials = at + (u32(data, at + 8) or 0),
    shapes = at + (u32(data, at + 12) or 0),
    matrices = at + (u32(data, at + 16) or 0),
    numObjects = u8(data, at + 0x17),
    numMaterials = u8(data, at + 0x18),
    numShapes = u8(data, at + 0x19),
    posScale = (u32(data, at + 0x1C) or FX16) / FX16,
    counts = {
      vertices = u16(data, at + 0x24),
      polygons = u16(data, at + 0x26),
      triangles = u16(data, at + 0x28),
      quads = u16(data, at + 0x2A),
    },
    bounds = {
      minX = s16(u16(data, at + 0x2C)) / FX16,
      minY = s16(u16(data, at + 0x2E)) / FX16,
      minZ = s16(u16(data, at + 0x30)) / FX16,
      maxX = s16(u16(data, at + 0x32)) / FX16,
      maxY = s16(u16(data, at + 0x34)) / FX16,
      maxZ = s16(u16(data, at + 0x36)) / FX16,
    },
  }
end

-- A shape record: sixteen bytes, of which the two that matter are the display
-- list's offset (from the RECORD, not the file) and its size.
--
-- Both were measured rather than assumed, and each confirms the other: on
-- pmsel_bg the offset lands exactly on a `40 22 21 24` packet -- BEGIN_VTXS,
-- TEXCOORD, NORMAL, VTX_10, which is how every display list in this cartridge
-- opens -- and record + offset + size lands exactly on the start of TEX0.
local SHAPE_DL_OFFSET = 8
local SHAPE_DL_SIZE = 12

-- parse(data) -> { models = { ... } } or nil, reason
--
-- Each model carries its bones, materials and shapes, with every shape's
-- display list already decoded into vertices and triangles.
function Gen4Nsbmd.parse(data)
  local sections = Gen4Nsbmd.sections(data)
  local mdl = sections and sections.MDL0
  if not mdl then return nil, "not an NSBMD with a model section" end

  local dict = Gen4Nsbmd.dictionary(data, mdl + 8)
  if not dict then return nil, "the model section has no readable dictionary" end

  local models = {}
  for _, entry in ipairs(dict.entries) do
    local header = modelHeader(data, mdl + entry.offset)
    local model = {
      name = entry.name,
      posScale = header.posScale,
      bounds = header.bounds,
      counts = header.counts,
      bones = {}, materials = {}, shapes = {},
      decoded = { vertices = 0, triangles = 0, quads = 0 },
    }

    local bones = Gen4Nsbmd.dictionary(data, header.at + 0x40)
    for _, bone in ipairs(bones and bones.entries or {}) do
      -- The node's own transform, which is where a shape's vertices actually
      -- stand: identity on most models in this cartridge, and the only source
      -- of the three Poke Balls' positions on the one that matters.
      local matrix = Gen4Nsbmd.nodeMatrix(data, bones.base + (bone.offset or 0))
      model.bones[#model.bones + 1] =
        { name = bone.name, index = bone.index, matrix = matrix }
    end

    -- WHICH TEXTURE A MATERIAL WEARS, which is recorded backwards.
    --
    -- The materials section holds three dictionaries: the materials, and one
    -- each for the texture and palette NAMES.  A texture entry does not say
    -- "material n uses me" by sitting at index n -- it carries a list of the
    -- material indices that use it, packed as bytes just before the material
    -- records, at an offset measured from the SECTION rather than from the
    -- dictionary.
    --
    -- AND THE ORDER IS NOT THE SAME.  On the briefcase, texture 1 (`op_mb`)
    -- belongs to material 2 and texture 2 (`op_mb_a`) to material 1; `trank_a`
    -- and `trank_a_` are swapped the same way.  Walking the two dictionaries in
    -- step -- the obvious reading, and correct on the simple models -- gives
    -- those four the wrong picture and reports nothing.  This is the second
    -- place in this file where the pairing is stored somewhere other than
    -- where it is used, and both of them look right when read the easy way.
    local function nameList(dictOffset, into)
      local dict = Gen4Nsbmd.dictionary(data, header.materials + dictOffset)
      for _, entry in ipairs(dict and dict.entries or {}) do
        local listAt = u16(data, entry.at)
        local count = u8(data, entry.at + 2) or 0
        local users = {}
        for i = 0, count - 1 do
          users[#users + 1] = u8(data, header.materials + (listAt or 0) + i)
        end
        into[#into + 1] = { name = entry.name, index = entry.index, materials = users }
      end
      return dict
    end

    model.textures, model.palettes = {}, {}
    nameList(u16(data, header.materials) or 0, model.textures)
    nameList(u16(data, header.materials + 2) or 0, model.palettes)

    local matDict = Gen4Nsbmd.dictionary(data, header.materials + 4)
    for _, mat in ipairs(matDict and matDict.entries or {}) do
      -- The material record's own texture scale, which is the thing that says
      -- whether this material HAS a texture at all.  It is zero exactly when
      -- the name lists above leave the material unbound, and that agreement --
      -- two records, neither derived from the other -- is what turns
      -- "untextured" from an excuse into a checked fact.  See `check`.
      local record = header.materials + (mat.offset or 0)
      model.materials[#model.materials + 1] = {
        name = mat.name, index = mat.index,
        texScale = u32(data, record + 0x20) or 0,
      }
    end
    -- ...and the same fact the way a renderer wants it: material -> names.
    for _, tex in ipairs(model.textures) do
      for _, index in ipairs(tex.materials) do
        local material = model.materials[index + 1]
        if material then material.texture = tex.name end
      end
    end
    for _, pal in ipairs(model.palettes) do
      for _, index in ipairs(pal.materials) do
        local material = model.materials[index + 1]
        if material then material.palette = pal.name end
      end
    end

    -- The SBC runs from its own offset up to the materials section, which is
    -- what follows it in every model in this cartridge.
    local draws, badOpcode =
      Gen4Nsbmd.renderCommands(data, header.renderCommands, header.materials)
    model.unknownRenderOpcode = badOpcode
    local materialOf, matrixOf = {}, {}
    for _, draw in ipairs(draws) do
      if draw.shape then
        materialOf[draw.shape] = draw.material
        matrixOf[draw.shape] = draw.matrix
      end
    end
    model.draws = draws
    -- ...and the same bytecode kept whole, so a pose can be replayed rather
    -- than baked: see `poseCommands`.
    model.pose = Gen4Nsbmd.poseCommands(data, header.renderCommands,
                                        header.materials)

    local shapeDict = Gen4Nsbmd.dictionary(data, header.shapes)
    for _, shape in ipairs(shapeDict and shapeDict.entries or {}) do
      local at = header.shapes + shape.offset
      local dlAt = at + (u32(data, at + SHAPE_DL_OFFSET) or 0)
      local dlSize = u32(data, at + SHAPE_DL_SIZE) or 0
      local vertices, triangles, stats =
        Gen4Nsbmd.decodeDisplayList(data, dlAt, dlSize)
      model.shapes[#model.shapes + 1] = {
        name = shape.name, index = shape.index,
        vertices = vertices, triangles = triangles,
        -- Which material this shape is drawn with, and on which matrix, out of
        -- the SBC rather than out of its own index.
        material = materialOf[shape.index],
        matrix = matrixOf[shape.index],
        unknownCommand = stats.unknown,
      }
      model.decoded.vertices = model.decoded.vertices + stats.vertices
      model.decoded.triangles = model.decoded.triangles + stats.triangles
      model.decoded.quads = model.decoded.quads + stats.quads
      model.unknownCommand = model.unknownCommand or stats.unknown
    end

    models[#models + 1] = model
  end

  return { models = models, hasTextures = sections.TEX0 ~= nil }
end

-- check(data) -> ok, total, failures
--
-- The corpus test, as a function rather than a script, so it can be run against
-- a cartridge that is not this one.  A model passes when all four of the
-- header's stated counts equal what the decoder found.
function Gen4Nsbmd.check(data)
  local parsed = Gen4Nsbmd.parse(data)
  if not parsed then return 0, 0, {} end
  local ok, failures = 0, {}
  for _, model in ipairs(parsed.models) do
    local c, d = model.counts, model.decoded
    local geometryOk = c.vertices == d.vertices and c.triangles == d.triangles
      and c.quads == d.quads and c.polygons == d.triangles + d.quads

    -- AND THE SECOND INVARIANT, on the render commands: no shape is drawn
    -- TWICE, every material named exists, and no opcode was unknown.  Those
    -- three are what a wrong operand width breaks -- a desynchronised walk
    -- produces repeated shape ids, material indices off the end of the
    -- dictionary, or a byte that is not an opcode at all.
    --
    -- "EVERY SHAPE IS DRAWN" IS DELIBERATELY NOT ONE OF THEM, and that is a
    -- relaxation worth justifying rather than quietly making.  It was the
    -- fourth clause, and exactly one model out of 1,030 failed it: `kurotama`
    -- in demo_tengan_gra draws 38 of its 40 shapes.  Those 38 are each drawn
    -- exactly once, with materials 0-6 out of seven, and no unknown opcode --
    -- which is not what a desynchronised walk looks like.  A cutscene model
    -- carrying two shapes its render commands never reach is ordinary content,
    -- so it is COUNTED here rather than called a failure.
    local drawn, twice = {}, false
    local badMaterial = false
    for _, draw in ipairs(model.draws or {}) do
      if drawn[draw.shape] then twice = true end
      drawn[draw.shape] = true
      if draw.material == nil or draw.material >= #model.materials then
        badMaterial = true
      end
    end
    local missing = 0
    for _, shape in ipairs(model.shapes) do
      if not drawn[shape.index] then missing = missing + 1 end
    end
    model.shapesNotDrawn = (missing > 0) and missing or nil
    -- AND THE THIRD INVARIANT, on the texture binding: every material ends up
    -- named by exactly one texture and one palette, and every index in those
    -- lists is a material that exists.  A binding read against the wrong base
    -- -- the mistake this is guarding, since the offsets are from the section
    -- and not from the dictionary -- lands on bytes that are usually in range
    -- and produces a mapping that is merely wrong.  Requiring a PERFECT
    -- one-to-one cover is what makes that impossible to miss.
    local textured, paletted, outOfRange = 0, 0, false
    for _, tex in ipairs(model.textures or {}) do
      for _, index in ipairs(tex.materials) do
        if index >= #model.materials then outOfRange = true end
      end
    end
    for _, pal in ipairs(model.palettes or {}) do
      for _, index in ipairs(pal.materials) do
        if index >= #model.materials then outOfRange = true end
      end
    end
    for _, material in ipairs(model.materials) do
      if material.texture then textured = textured + 1 end
      if material.palette then paletted = paletted + 1 end
    end
    -- A MATERIAL IS BOUND TO A TEXTURE IF AND ONLY IF IT DECLARES ONE.
    --
    -- Requiring every material to be textured was the first version of this
    -- check and 122 of the 1,030 models failed it -- always one or two
    -- materials on an otherwise complete model, never a whole model, which is
    -- not the shape a wrong base address produces.  A DS polygon can have no
    -- texture at all, and this cartridge has plenty that do not.
    --
    -- What makes that an answer rather than an excuse is the material's own
    -- texture-scale field: zero on exactly the materials the name lists leave
    -- unbound, non-zero on exactly the ones they bind.  Two records that know
    -- nothing about each other, agreeing on every material in the cartridge.
    local disagreement = 0
    for _, material in ipairs(model.materials) do
      local declares = (material.texScale or 0) ~= 0
      local bound = material.texture ~= nil
      if declares ~= bound then disagreement = disagreement + 1 end
    end
    local bindingOk = not outOfRange and disagreement == 0

    local drawsOk = not twice and not badMaterial
      and model.unknownRenderOpcode == nil

    if geometryOk and drawsOk and bindingOk then
      ok = ok + 1
    else
      failures[#failures + 1] = {
        name = model.name, stated = c, decoded = d,
        unknownCommand = model.unknownCommand,
        unknownRenderOpcode = model.unknownRenderOpcode,
        shapesDrawnTwice = twice or nil,
        bindingDisagreement = (disagreement > 0) and disagreement or nil,
        bindingOutOfRange = outOfRange or nil,
        untextured = (#model.materials - textured > 0)
          and (#model.materials - textured) or nil,
        materialOutOfRange = badMaterial or nil,
      }
    end
  end
  return ok, #parsed.models, failures
end

-- ---------------------------------------------------------------------------
-- Where a shape actually stands
-- ---------------------------------------------------------------------------

-- A NODE'S OWN TRANSFORM, which this reader ignored until the briefcase needed
-- it.  Every model has a node list beside its shapes, and a shape's vertices
-- are in ITS node's space rather than the model's: on the simple models the
-- nodes are all identity and nothing is lost, and on `psel_all` -- the case
-- with its three Poke Balls -- the nodes are the only thing that says where
-- the balls are.
--
-- The block is a flags word, a spare fx16 that belongs to the rotation, and
-- then only the parts that are not the default:
--
--   bit 0  translation is zero      otherwise three fx32
--   bit 1  rotation is identity     otherwise a pivot (two fx16, bit 3) or the
--                                   other eight of a 3x3, whose first element
--                                   is the spare word above
--   bit 2  scale is one             otherwise three fx32 and their reciprocals
--
-- Every node block in the cartridge ends exactly where the next one begins
-- under that reading, which is what makes the widths right rather than
-- plausible.
--
-- THE PIVOT FIELDS ARE NOT WHERE THE ANIMATIONS PUT THEM.  Here the position
-- of the +-1 is bits 4..7 and the negation is bits 8..9; a joint animation's
-- pivot record keeps the position in its LOW nibble.  Reading either one with
-- the other's layout gives a rotation -- the wrong one, about the wrong axis,
-- with nothing to complain.
local NODE_FX = 4096

local function nodeSigned16(data, at)
  local v = u16(data, at)
  if not v then return 0 end
  if v >= 32768 then v = v - 65536 end
  return v
end

local function nodeSigned32(data, at)
  local v = u32(data, at)
  if not v then return 0 end
  if v >= 2147483648 then v = v - 4294967296 end
  return v
end

local function nodeBit(flags, n) return math.floor(flags / 2 ^ n) % 2 == 1 end

-- The same pivot reconstruction the animations use, with this format's own
-- field positions.  Kept here rather than shared because the two layouts
-- differ, and a shared function would have to be told which -- at which point
-- it is two functions with a flag.
local function nodePivot(flags, a, b)
  local p = math.floor(flags / 16) % 16
  local neg = math.floor(flags / 256) % 4
  local row, col = math.floor(p / 3), p % 3
  local sign = ((row + col) % 2 == 0) and 1 or -1
  local flip = (neg % 2 == 1)
  if flip then sign = -sign end
  local m = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  m[row * 3 + col + 1] = sign
  local rows, cols = {}, {}
  for i = 0, 2 do if i ~= row then rows[#rows + 1] = i end end
  for i = 0, 2 do if i ~= col then cols[#cols + 1] = i end end
  m[rows[1] * 3 + cols[1] + 1] = a
  m[rows[1] * 3 + cols[2] + 1] = b
  if flip then
    m[rows[2] * 3 + cols[1] + 1] = b
    m[rows[2] * 3 + cols[2] + 1] = -a
  else
    m[rows[2] * 3 + cols[1] + 1] = -b
    m[rows[2] * 3 + cols[2] + 1] = a
  end
  return m
end

-- nodeMatrix(data, at) -> 4x4 row-major, size in bytes
function Gen4Nsbmd.nodeMatrix(data, at)
  local flags = u16(data, at) or 0
  local first = nodeSigned16(data, at + 2) / NODE_FX
  local pos = at + 4

  local tx, ty, tz = 0, 0, 0
  if not nodeBit(flags, 0) then
    tx = nodeSigned32(data, pos) / NODE_FX
    ty = nodeSigned32(data, pos + 4) / NODE_FX
    tz = nodeSigned32(data, pos + 8) / NODE_FX
    pos = pos + 12
  end

  local r = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
  if not nodeBit(flags, 1) then
    if nodeBit(flags, 3) then
      r = nodePivot(flags, nodeSigned16(data, pos) / NODE_FX,
                    nodeSigned16(data, pos + 2) / NODE_FX)
      pos = pos + 4
    else
      r = { first }
      for i = 0, 7 do
        r[i + 2] = nodeSigned16(data, pos + i * 2) / NODE_FX
      end
      pos = pos + 16
    end
  end

  local sx, sy, sz = 1, 1, 1
  if not nodeBit(flags, 2) then
    sx = nodeSigned32(data, pos) / NODE_FX
    sy = nodeSigned32(data, pos + 4) / NODE_FX
    sz = nodeSigned32(data, pos + 8) / NODE_FX
    pos = pos + 24
  end

  return {
    r[1] * sx, r[2] * sy, r[3] * sz, tx,
    r[4] * sx, r[5] * sy, r[6] * sz, ty,
    r[7] * sx, r[8] * sy, r[9] * sz, tz,
    0, 0, 0, 1,
  }, pos - at
end

-- poseCommands(data, at, limit) -> { { op, ... }, ... }
--
-- The SBC again, but kept whole this time.  `renderCommands` above reduces it
-- to which material and which matrix each shape is drawn with, which is all
-- the pairing needs; posing needs the ORDER as well, because a node descriptor
-- multiplies onto whatever matrix is current and may save the result for a
-- later shape to come back to.
--
-- The three that matter:
--   node     bind node n onto the current matrix, optionally restoring from a
--            stack slot first and optionally storing the result to one
--   matrix   make a stack slot current
--   shape    draw shape n with the current matrix
function Gen4Nsbmd.poseCommands(data, at, limit)
  local ops = {}
  local pos = at
  while pos < limit do
    local byte = u8(data, pos)
    if not byte then break end
    pos = pos + 1
    local op, flags = byte % 32, math.floor(byte / 32)
    if op == 0x01 then break end
    local n = SBC_OPERANDS[op]
    if op == 0x06 then
      n = 3 + (flags % 2) + (math.floor(flags / 2) % 2)
    elseif op == 0x09 then
      n = 2 + (u8(data, pos + 1) or 0) * 3
    end
    if n == nil then return ops, byte end
    if op == 0x06 then
      local entry = { op = "node", node = u8(data, pos) }
      local i = 3
      if flags % 2 == 1 then entry.store = u8(data, pos + i); i = i + 1 end
      if math.floor(flags / 2) % 2 == 1 then entry.restore = u8(data, pos + i) end
      ops[#ops + 1] = entry
    elseif op == 0x03 then
      ops[#ops + 1] = { op = "matrix", slot = u8(data, pos) }
    elseif op == 0x05 then
      ops[#ops + 1] = { op = "shape", shape = u8(data, pos) }
    end
    pos = pos + n
  end
  return ops, nil
end

-- pose(ops, matrixOf) -> { [shape] = 4x4 }
--
-- Replaying the sequence above with a matrix per node.  `matrixOf(node)` is
-- the model's own node transform for the rest pose and a joint animation's
-- frame for a moving one -- which is the whole point of keeping the sequence:
-- the two are the same walk over different numbers.
function Gen4Nsbmd.pose(ops, matrixOf)
  local out, stack = {}, {}
  local current = {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  }
  for _, entry in ipairs(ops or {}) do
    if entry.op == "node" then
      if entry.restore then
        current = stack[entry.restore] or current
      end
      local local4 = matrixOf(entry.node)
      if local4 then
        local product = {}
        for row = 0, 3 do
          for col = 0, 3 do
            local sum = 0
            for k = 0, 3 do
              sum = sum + current[row * 4 + k + 1] * local4[k * 4 + col + 1]
            end
            product[row * 4 + col + 1] = sum
          end
        end
        current = product
      end
      if entry.store then stack[entry.store] = current end
    elseif entry.op == "matrix" then
      current = stack[entry.slot] or current
    elseif entry.op == "shape" then
      out[entry.shape] = current
    end
  end
  return out
end

return Gen4Nsbmd
