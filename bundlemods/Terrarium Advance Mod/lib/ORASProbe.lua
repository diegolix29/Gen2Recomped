-- ORASProbe: a report of what a decrypted Omega Ruby / Alpha Sapphire dump
-- actually holds, written before any model is decoded.
--
-- The Pokemon battle models live in one GARC under a/, as several members
-- per species/form (model, textures, animation sets).  Which archive, how
-- many members a form takes and what magic each starts with are exactly the
-- facts the decoder is built on, so they are READ from the player's own dump
-- rather than assumed: this walks every GARC, records its entry count and the
-- first bytes of its first members, and for archives big enough to be the
-- Pokemon one (>= MODEL_MIN entries) opens the first members' mini-pack
-- containers and lists what is inside.
--
-- Output: mod.cache "oras/probe.txt", plus a one-line summary for the row.

local V = ...
local N3DSRom = V.require("N3DSRom")
local GARC = V.require("GARC")
local BCH = V.require("BCH")

local P = {}

local IMPORT_ID = "pokemon_oras"
local MODEL_MIN = 700        -- the Pokemon archive has well over 721 members
local SAMPLE = 3             -- members sampled per archive
local DEEP_SAMPLE = 18       -- members opened fully in a candidate archive
local DEEP_MAX = 4 * 1024 * 1024

-- product codes of the two retail games (any region)
local TITLES = { ["CTR-P-ECRA"] = "Omega Ruby", ["CTR-P-ECLA"] = "Alpha Sapphire" }

local function hex(s, n)
  local out = {}
  for i = 1, math.min(#s, n or 16) do out[#out + 1] = string.format("%02X", s:byte(i)) end
  return table.concat(out, " ")
end

local function ascii(s, n)
  return (s:sub(1, n or 4):gsub("[^%w]", "."))
end

local function u16(s, p) local a, b = s:byte(p, p + 1); return a + (b or 0) * 256 end
local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- Game Freak's mini-pack: two ASCII letters, a u16 count, then count + 1 u32
-- offsets (the last is the end).  Returns a list of {offset, size} or nil.
local function miniPack(data)
  if #data < 8 then return nil end
  local a, b = data:byte(1, 2)
  if not (a >= 65 and a <= 90 and b >= 65 and b <= 90) then return nil end
  local count = u16(data, 3)
  if count == 0 or count > 256 or #data < 4 + (count + 1) * 4 then return nil end
  local out, prev = {}, nil
  for i = 0, count do
    local off = u32(data, 5 + i * 4)
    if not off or off > #data or (prev and off < prev) then return nil end
    if prev then out[#out + 1] = { offset = prev, size = off - prev } end
    prev = off
  end
  return out, data:sub(1, 2)
end

local function describeMember(data)
  local parts, tag = miniPack(data)
  if not parts then return nil end
  local lines = {}
  for i, part in ipairs(parts) do
    local body = data:sub(part.offset + 1, part.offset + math.min(part.size, 16))
    lines[#lines + 1] = string.format("      [%d] %8d bytes  %s  %s", i - 1, part.size,
                                      hex(body, 8), ascii(body, 4))
  end
  return tag, lines
end

function P.run(mod)
  mod = mod or V.mod
  local lines = {}
  local function out(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end

  local rom, err = N3DSRom.open(mod, IMPORT_ID)
  if not rom then return nil, err end
  out("ORAS probe")
  out("product %s (%s), program %s, %d RomFS files",
      rom.productCode, TITLES[rom.productCode] or "unrecognised product code",
      rom.programId, #rom.files)

  local garcs, candidates = 0, {}
  for _, f in ipairs(rom.files) do
    if f.path:sub(1, 2) == "a/" and f.size >= 0x1C then
      local ok, g = pcall(GARC.open, rom, f)
      if ok and g then
        garcs = garcs + 1
        out("")
        out("%s  %d entries  v%04X  %d bytes", f.path, g.count, g.version, f.size)
        local deep = g.count >= MODEL_MIN
        if deep then candidates[#candidates + 1] = f.path .. " (" .. g.count .. ")" end
        for i = 0, math.min(g.count, deep and DEEP_SAMPLE or SAMPLE) - 1 do
          local subs = g.entries[i + 1]
          for s = 1, #subs do
            local okP, head, packed, total = pcall(g.peek, g, i, s, 16)
            if okP and head then
              out("  #%d.%d  %s%8d bytes  %s  %s", i, s, packed and "lz " or "   ",
                  total or 0, hex(head, 12), ascii(head, 4))
              if deep and (total or 0) <= DEEP_MAX then
                local okM, data = pcall(g.member, g, i, s)
                if okM and data then
                  local tag, parts = describeMember(data)
                  if tag then
                    out("    pack %q, %d parts", tag, #parts)
                    for _, l in ipairs(parts) do lines[#lines + 1] = l end
                  end
                end
              end
            end
          end
        end
      elseif not ok then
        out("%s  unreadable: %s", f.path, tostring(g))
      end
    end
  end
  out("")
  out("%d GARCs; model-sized: %s", garcs, #candidates > 0 and table.concat(candidates, ", ") or "none")

  local text = table.concat(lines, "\n") .. "\n"
  local saved = false
  if mod and mod.cache and type(mod.cache.write) == "function" then
    saved = pcall(mod.cache.write, mod.cache, "oras/probe.txt", text)
  end
  local summary = string.format("%s, %d GARCs, %d model-sized",
                                TITLES[rom.productCode] or rom.productCode, garcs, #candidates)
  return { summary = summary, text = text, saved = saved, candidates = candidates }
end

-- ------------------------------------------------------------ model probe
--
-- The first probe found the Pokemon archive: a/0/0/8, 8067 members.  Member 0
-- reads as a species index of 4-byte records (u16 first form, u8 form count,
-- u8 flags), and from member 2 on the members repeat in runs of eight per
-- form (model PC, PF, three PTs, PB motions, PK motions, ...).  This probe
-- checks that reading: it prints index records for species at every
-- generation boundary, then opens the eight members of a few forms and lists
-- what each BCH inside them declares -- counts per kind and its names, which
-- carry the species number (pmNNNN) if the mapping is right.

local MODEL_GARC = "a/0/0/8"
local FIRST_FORM_MEMBER = 2
local MEMBERS_PER_FORM = 8
local SPECIES_SAMPLE = { 0, 1, 2, 3, 6, 25, 151, 251, 386, 387, 493, 494, 649, 650, 721, 722 }
local NAMES_SHOWN = 12
local BCH_PARTS_SHOWN = 3

-- mini-pack index without bounds checks against the data, for a member that
-- was only partly inflated
local function packIndex(data)
  if #data < 8 then return nil end
  local a, b = data:byte(1, 2)
  if not (a >= 65 and a <= 90 and b >= 65 and b <= 90) then return nil end
  local count = u16(data, 3)
  if count == 0 or count > 256 or #data < 4 + (count + 1) * 4 then return nil end
  local parts = {}
  for i = 0, count - 1 do
    local off, nxt = u32(data, 5 + i * 4), u32(data, 9 + i * 4)
    parts[#parts + 1] = { offset = off, size = nxt - off }
  end
  return data:sub(1, 2), parts
end

function P.models(mod)
  mod = mod or V.mod
  local lines = {}
  local function out(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end

  local rom, err = N3DSRom.open(mod, IMPORT_ID)
  if not rom then return nil, err end
  local file = rom:file(MODEL_GARC)
  if not file then return nil, "no " .. MODEL_GARC .. " in this dump" end
  local g, gerr = GARC.open(rom, file)
  if not g then return nil, gerr end
  out("ORAS model probe: %s (%s), %s %d members", rom.productCode,
      TITLES[rom.productCode] or "?", MODEL_GARC, g.count)

  local index = g:member(0)
  local records = math.floor(#index / 4)
  out("index member: %d bytes (%d four-byte records)", #index, records)
  local function rec(sp)
    local p = sp * 4 + 1
    if p + 3 > #index then return nil end
    return u16(index, p), index:byte(p + 2), index:byte(p + 3)
  end
  for _, sp in ipairs(SPECIES_SAMPLE) do
    local start, forms, flags = rec(sp)
    if start then out("  species %3d: first form %4d, forms %2d, flags 0x%02X", sp, start, forms, flags) end
  end
  if #index > 722 * 4 then
    out("  after 722 records: %d bytes, starting %s", #index - 722 * 4, hex(index:sub(722 * 4 + 1), 24))
  end

  -- one BCH: counts that are not zero, then its first names
  local function describeBch(member, offset)
    local head = g:member(member, 1, offset + 0x44)
    local h, why = BCH.header(head:sub(offset + 1))
    if not h then out("        %s", why); return end
    local need = offset + h.strings + h.stringsLen
    local body = g:member(member, 1, need):sub(offset + 1)
    local counts, shown = BCH.counts(body, h), {}
    for _, kind in ipairs(BCH.KINDS) do
      if (counts[kind] or 0) > 0 then shown[#shown + 1] = kind .. "=" .. counts[kind] end
    end
    out("        BCH v%04X  %s", h.version, #shown > 0 and table.concat(shown, " ") or "(empty)")
    local names = BCH.strings(body, h)
    local list = {}
    for i = 1, math.min(#names, NAMES_SHOWN) do list[#list + 1] = names[i] end
    if #list > 0 then
      out("        names (%d): %s%s", #names, table.concat(list, ", "), #names > NAMES_SHOWN and ", ..." or "")
    end
  end

  local function describeForm(form, why)
    local base = FIRST_FORM_MEMBER + form * MEMBERS_PER_FORM
    out("")
    out("form %d (%s): members %d-%d", form, why, base, base + MEMBERS_PER_FORM - 1)
    for slot = 0, MEMBERS_PER_FORM - 1 do
      local m = base + slot
      if m >= g.count then break end
      local okH, head = pcall(g.member, g, m, 1, 512)
      if not okH or not head then
        out("  slot %d (#%d): unreadable", slot, m)
      elseif BCH.is(head) then
        out("  slot %d (#%d): bare BCH", slot, m)
        local ok, e = pcall(describeBch, m, 0)
        if not ok then out("        %s", tostring(e)) end
      else
        local tag, parts = packIndex(head)
        if tag then
          out("  slot %d (#%d): %q, %d parts", slot, m, tag, #parts)
          local bchShown = 0
          for i, part in ipairs(parts) do
            -- each look re-inflates from the start; stop once enough is shown
            if bchShown >= BCH_PARTS_SHOWN then break end
            if part.size > 0 then
              local okP, ph = pcall(g.member, g, m, 1, part.offset + 8)
              local body = okP and ph and ph:sub(part.offset + 1) or ""
              if body:sub(1, 4) == "BCH\0" then
                if bchShown < BCH_PARTS_SHOWN then
                  out("      [%d] %d bytes", i - 1, part.size)
                  local ok, e = pcall(describeBch, m, part.offset)
                  if not ok then out("        %s", tostring(e)) end
                  bchShown = bchShown + 1
                end
              elseif i == 1 then
                -- a non-BCH first part (PB/PK motion tables) -- show its head
                local okB, pb = pcall(g.member, g, m, 1, part.offset + 64)
                out("      [0] %d bytes, not BCH: %s", part.size,
                    okB and pb and hex(pb:sub(part.offset + 1), 32) or "?")
              end
            end
          end
        else
          out("  slot %d (#%d): %s", slot, m, hex(head, 16))
        end
      end
    end
  end

  describeForm(0, "first")
  describeForm(1, "second")
  for _, sp in ipairs({ 387, 494, 650 }) do
    local start = rec(sp)
    if start then describeForm(start, "species " .. sp .. "'s first form") end
  end

  local text = table.concat(lines, "\n") .. "\n"
  local saved = false
  if mod and mod.cache and type(mod.cache.write) == "function" then
    saved = pcall(mod.cache.write, mod.cache, "oras/model_probe.txt", text)
  end
  return { summary = string.format("%s, %d records", MODEL_GARC, records), text = text, saved = saved }
end

-- --------------------------------------------------------- anatomy probe
--
-- What the model probe settled: a/0/0/8 member 2 + 8k is the info PC of
-- form k+1 (member 2 itself is a shared shader BCH), and the seven after it
-- are model PC, face PF, normal-texture PT, shiny-texture PT, Id-texture PT,
-- battle-motion PB and Amie-motion PK.  Each member's names carry pmNNNN_FF,
-- so the installer maps forms by name, not by index arithmetic.
--
-- This probe dumps ONE form's model, material, texture and motion headers
-- word by word after BCH relocation (lib/BCH.lua), each word labelled with
-- what it points into or what it reads as -- the structure the decoder is
-- written against.  Ivysaur (members 10-17) is the specimen: block 0 has
-- the shared shader BCH where its info PC would be.

local SPECIMEN_BASE = 10
local FOLLOW_MAX = 14

function P.anatomy(mod)
  mod = mod or V.mod
  local lines = {}
  local function out(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
  local function dump(list, indent)
    for _, l in ipairs(list) do lines[#lines + 1] = (indent or "    ") .. l end
  end

  local rom, err = N3DSRom.open(mod, IMPORT_ID)
  if not rom then return nil, err end
  local g, gerr = GARC.open(rom, assert(rom:file(MODEL_GARC), "no " .. MODEL_GARC))
  if not g then return nil, gerr end
  out("ORAS anatomy probe: %s members %d-%d", MODEL_GARC, SPECIMEN_BASE, SPECIMEN_BASE + 7)

  local function packPart(member, n)
    local data = g:member(member)
    local tag, parts = packIndex(data)
    if not tag then return nil, "member " .. member .. " is not a mini-pack" end
    local p = parts[n]
    if not p then return nil, "no part " .. n end
    return data:sub(p.offset + 1, p.offset + p.size), tag, #parts
  end

  -- one relocated BCH: header, tally, content triples, then `visit(data, h)`
  local function anatomy(label, bch, visit)
    out("")
    out("== %s: %d bytes", label, #bch)
    local h, why = BCH.header(bch)
    if not h then out("  %s", why); return end
    out("  sections: content 0x%X+0x%X  strings 0x%X+0x%X  commands 0x%X+0x%X  data 0x%X+0x%X  ext 0x%X+0x%X  reloc 0x%X+0x%X",
        h.content, h.contentLen, h.strings, h.stringsLen, h.commands, h.commandsLen,
        h.data, h.dataLen, h.dataExt, h.dataExtLen, h.relocation, h.relocationLen)
    local data, tally = BCH.relocate(bch, h)
    local t = {}
    for flag, n in pairs(tally) do t[#t + 1] = string.format("0x%02X=%d", flag, n) end
    table.sort(t)
    out("  relocation flags: %s", table.concat(t, " "))
    out("  content header:")
    dump(BCH.annotate(data, h, h.content, #BCH.KINDS * 3))
    if visit then visit(data, h) end
  end

  -- annotate a block, then one level of the content/command pointers in it
  local function follow(data, h, at, n, depthWords)
    dump(BCH.annotate(data, h, at, n))
    local seen = 0
    for i = 0, n - 1 do
      local v = BCH.u32(data, at + i * 4 + 1)
      local sec = v and BCH.section(h, v)
      if (sec == "C" or sec == "G") and v ~= at and seen < FOLLOW_MAX then
        seen = seen + 1
        out("    -- +%03X -> %s+0x%X:", i * 4, sec, v - (sec == "C" and h.content or h.commands))
        dump(BCH.annotate(data, h, v, depthWords), "        ")
      end
    end
  end

  -- the first entry of one content kind (pointer table -> header)
  local function firstOf(data, h, kind)
    for i, k in ipairs(BCH.KINDS) do
      if k == kind then
        local base = h.content + (i - 1) * 12
        local tableAt, count = BCH.u32(data, base + 1), BCH.u32(data, base + 5)
        if count and count > 0 and BCH.section(h, tableAt) == "C" then
          return BCH.u32(data, tableAt + 1), count
        end
      end
    end
  end

  -- info PC: sixteen floats
  local okI, info = pcall(packPart, SPECIMEN_BASE, 1)
  if okI and info then
    local fl = {}
    for i = 0, math.floor(#info / 4) - 1 do fl[#fl + 1] = string.format("%.4g", BCH.f32(BCH.u32(info, i * 4 + 1))) end
    out("info PC part 0 as floats: %s", table.concat(fl, " "))
  end

  -- model
  local model, mtag = packPart(SPECIMEN_BASE + 1, 1)
  if model then
    anatomy("model (" .. tostring(mtag) .. " part 0)", model, function(data, h)
      local at, count = firstOf(data, h, "models")
      if at then
        out("  model 0 of %d at C+0x%X:", count, at - h.content)
        follow(data, h, at, 48, 16)
      end
      local mat, mcount = firstOf(data, h, "materials")
      if mat then
        out("  material 0 of %d at C+0x%X:", mcount, mat - h.content)
        follow(data, h, mat, 32, 12)
      end
      local lut = firstOf(data, h, "lookupTables")
      if lut then
        out("  lookup table 0 at C+0x%X:", lut - h.content)
        dump(BCH.annotate(data, h, lut, 12))
      end
      out("  first GPU command words:")
      dump(BCH.annotate(data, h, h.commands, 24))
    end)
  end

  -- textures (normal set)
  local tex = packPart(SPECIMEN_BASE + 3, 1)
  if tex then
    anatomy("textures (PT part 0)", tex, function(data, h)
      local at, count = firstOf(data, h, "textures")
      if at then
        out("  texture 0 of %d at C+0x%X:", count, at - h.content)
        follow(data, h, at, 24, 16)
      end
    end)
  end

  -- battle motions: PB part 0 is a pack of its own (u32 count, offsets)
  local pb = packPart(SPECIMEN_BASE + 6, 1)
  if pb then
    local count = BCH.u32(pb, 1)
    out("")
    out("== battle motion pack (PB part 0): %d bytes, %d entries", #pb, count)
    local shown = 0
    for i = 0, count - 1 do
      local off = BCH.u32(pb, 5 + i * 4)
      local nxt
      for j = i + 1, count do
        nxt = (j == count) and #pb or BCH.u32(pb, 5 + j * 4)
        if nxt and nxt > 0 then break end
      end
      if off and off > 0 and shown < 6 then
        shown = shown + 1
        local body = pb:sub(off + 1, (nxt or #pb))
        out("  [%d] @0x%X %d bytes: %s  %s", i, off, #body, hex(body, 16), ascii(body, 4))
        if BCH.is(body) then
          local h = BCH.header(body)
          if h then
            local c, list = BCH.counts(body, h), {}
            for _, kind in ipairs(BCH.KINDS) do
              if (c[kind] or 0) > 0 then list[#list + 1] = kind .. "=" .. c[kind] end
            end
            out("      BCH %s; names: %s", table.concat(list, " "), table.concat(BCH.strings(body, h), ", "))
            if shown == 1 then
              anatomy("motion " .. i, body, function(data, hh)
                local at = firstOf(data, hh, "skeletalAnimations")
                if at then
                  out("  skeletal animation 0 at C+0x%X:", at - hh.content)
                  follow(data, hh, at, 24, 16)
                end
              end)
            end
          end
        end
      end
    end
  end

  local text = table.concat(lines, "\n") .. "\n"
  local saved = false
  if mod and mod.cache and type(mod.cache.write) == "function" then
    saved = pcall(mod.cache.write, mod.cache, "oras/anatomy.txt", text)
  end
  return { summary = "anatomy of members " .. SPECIMEN_BASE .. "-" .. (SPECIMEN_BASE + 7),
           text = text, saved = saved }
end

-- ----------------------------------------------------------- test export
--
-- The first real decode: one form's model in bind pose, written as OBJ + MTL
-- with its diffuse textures as PNG, to mod.cache "oras/test/".  Opening the
-- OBJ in any viewer checks geometry, rigid skinning, UVs and texture decode
-- in one look, before any of it is baked for PokemonActors.

local H3D_ = nil
local function H3Dmod() H3D_ = H3D_ or V.require("H3D"); return H3D_ end

local function bchFromPack(g, member, n)
  local data = g:member(member)
  local tag, parts = packIndex(data)
  if not tag then return nil, "member " .. member .. " is not a mini-pack" end
  local p = parts[n]
  if not p then return nil, "member " .. member .. " has no part " .. n end
  local bch = data:sub(p.offset + 1, p.offset + p.size)
  local h, why = BCH.header(bch)
  if not h then return nil, why end
  return BCH.relocate(bch, h), h
end

function P.export(mod, base)
  mod = mod or V.mod
  base = base or SPECIMEN_BASE
  local H3D = H3Dmod()
  local PICA = V.require("PICA")
  local lines = {}
  local function out(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end

  local rom, err = N3DSRom.open(mod, IMPORT_ID)
  if not rom then return nil, err end
  local g, gerr = GARC.open(rom, assert(rom:file(MODEL_GARC), "no " .. MODEL_GARC))
  if not g then return nil, gerr end

  local md, mh = bchFromPack(g, base + 1, 1)
  if not md then return nil, mh end
  local model = H3D.models(md, mh)[1]
  if not model then return nil, "no model in member " .. (base + 1) end
  local td, th = bchFromPack(g, base + 3, 1)
  if not td then return nil, th end
  local textures = H3D.textures(td, th)

  local stem = model.name or ("member" .. (base + 1))
  out("ORAS export: %s (members %d-%d), %d meshes, %d materials, %d bones",
      stem, base, base + 7, #model.meshes, #model.materials, #model.bones)
  local tnames = {}
  for name, t in pairs(textures) do
    tnames[#tnames + 1] = string.format("%s %dx%d fmt %d mips %d", name, t.width, t.height, t.format, t.mipmaps or 0)
  end
  table.sort(tnames)
  out("textures: %s", table.concat(tnames, "; "))

  local obj = { "# " .. stem .. " -- bind pose, from the player's own ORAS dump", "mtllib " .. stem .. ".mtl" }
  local mtl = {}
  local used, vbase = {}, 0
  local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }

  for mi, mesh in ipairs(model.meshes) do
    local mat = model.materials[mesh.materialIndex + 1] or {}
    local tex = mat.textures and mat.textures[1]
    local attrs = {}
    for _, a in ipairs(mesh.layout.attrs) do
      attrs[#attrs + 1] = string.format("%s:%dx%d*%.4g", a.name, a.format, a.elements, a.scale)
    end
    local fixed = {}
    for name in pairs(mesh.layout.fixed) do fixed[#fixed + 1] = name end
    local skins, tris = {}, 0
    for _, sm in ipairs(mesh.submeshes) do
      skins[#skins + 1] = string.format("%d/%d/m%d", sm.skinning, #sm.palette, sm.mode)
      tris = tris + math.floor(#sm.indices / 3)
    end
    local uvT = mat.uvTransform
    out("mesh %d: material %d %s tex %s uv[%s], %d verts, %d tris, stride %d, attrs %s%s, submeshes %s",
        mi - 1, mesh.materialIndex, tostring(mat.name), tostring(tex),
        uvT and string.format("type %d s %.3g,%.3g r %.3g t %.3g,%.3g", uvT.kind, uvT.sx, uvT.sy, uvT.rot, uvT.tx, uvT.ty) or "-",
        mesh.vertexCount, tris,
        mesh.layout.stride, table.concat(attrs, " "),
        #fixed > 0 and (" fixed " .. table.concat(fixed, ",")) or "", table.concat(skins, " "))

    local bind = H3D.bindPose(model, mesh)
    obj[#obj + 1] = "g mesh" .. (mi - 1)
    obj[#obj + 1] = "usemtl " .. tostring(mat.name or ("mat" .. mesh.materialIndex))
    for _, v in ipairs(bind) do
      local p = v.position
      obj[#obj + 1] = string.format("v %.5f %.5f %.5f", p[1], p[2], p[3])
      for k = 1, 3 do
        if p[k] < lo[k] then lo[k] = p[k] end
        if p[k] > hi[k] then hi[k] = p[k] end
      end
      local uv = v.uv or { 0, 0 }
      obj[#obj + 1] = string.format("vt %.5f %.5f", uv[1], 1 - (uv[2] or 0))
      local n = v.normal or { 0, 1, 0 }
      obj[#obj + 1] = string.format("vn %.4f %.4f %.4f", n[1], n[2], n[3])
    end
    for _, sm in ipairs(mesh.submeshes) do
      local ix = sm.indices
      for t = 1, #ix - 2, 3 do
        local a, b, c = ix[t] + 1 + vbase, ix[t + 1] + 1 + vbase, ix[t + 2] + 1 + vbase
        obj[#obj + 1] = string.format("f %d/%d/%d %d/%d/%d %d/%d/%d", a, a, a, b, b, b, c, c, c)
      end
    end
    vbase = vbase + #bind

    if mat.name and not used[mat.name] then
      used[mat.name] = true
      mtl[#mtl + 1] = "newmtl " .. mat.name
      mtl[#mtl + 1] = "Kd 1 1 1"
      if tex and textures[tex] then mtl[#mtl + 1] = "map_Kd " .. tex .. ".png" end
    end
  end
  out("bind-pose bounds: (%.2f %.2f %.2f) - (%.2f %.2f %.2f)", lo[1], lo[2], lo[3], hi[1], hi[2], hi[3])

  local function write(path, bytes)
    local ok, wrote = pcall(mod.cache.write, mod.cache, path, bytes)
    return ok and wrote ~= false
  end
  local dir = "oras/test/"
  local okObj = write(dir .. stem .. ".obj", table.concat(obj, "\n") .. "\n")
  write(dir .. stem .. ".mtl", table.concat(mtl, "\n") .. "\n")

  local pngs = 0
  for _, mat in ipairs(model.materials) do
    local tex = mat.textures and mat.textures[1]
    local t = tex and textures[tex]
    if t and not used["png:" .. tex] then
      used["png:" .. tex] = true
      local ok, res = pcall(function()
        local img = PICA.decodeTexture(td, t.address, t.width, t.height, t.format)
        return img:encode("png"):getString()
      end)
      if ok and write(dir .. tex .. ".png", res) then
        pngs = pngs + 1
      else
        out("texture %s failed: %s", tex, tostring(res))
      end
    end
  end
  out("wrote %s%s.obj (%s) and %d PNG textures", dir, stem, okObj and "ok" or "FAILED", pngs)

  local text = table.concat(lines, "\n") .. "\n"
  write("oras/export.txt", text)
  return { summary = string.format("exported %s to mod cache %s", stem, dir), text = text, saved = true }
end

return P
