-- N3DSRom: random-access reader for a DECRYPTED 3DS game dump, as far as its
-- RomFS file tree.  Used by the ORAS model import (lib/ORASModels.lua).
--
-- The dump is a launcher import (manifest.json `required_imports`, id
-- "pokemon_oras"), read through mod.imports in bounded slices -- an Omega
-- Ruby / Alpha Sapphire cartridge image is about 2 GB, so nothing here ever
-- asks for the whole file.
--
-- Layout walked (3dbrew's names):
--
--   NCSD   cartridge image (.3ds / .cci): partition table at 0x120, partition
--          0 is the game's NCCH.  A bare NCCH (.cxi) is accepted too.
--   NCCH   magic at 0x100, flags at 0x188 (flags[7] bit 2 = NoCrypto),
--          product code at 0x150, RomFS offset/size at 0x1B0 in 0x200 units.
--   RomFS  an IVFC hash tree; only level 3 (the file system) is read.  It
--          starts at align(0x60 + master hash size, level 3 block size).
--   L3     directory / file metadata tables; names are UTF-16LE.
--
-- ENCRYPTED DUMPS ARE REFUSED, with a reason that says what to do: decrypting
-- needs the console's keys, which this mod does not and will not carry.

local V = ...

local R = {}

local MEDIA = 0x200
local SLICE = 8 * 1024 * 1024          -- ModImports.MAX_READ_BYTES
local NONE = 0xFFFFFFFF

local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end
local function u64(s, p)
  local lo, hi = u32(s, p), u32(s, p + 4)
  if not hi then return nil end
  return lo + hi * 4294967296
end

local function utf16(s, p, bytes)
  local out = {}
  for i = p, p + bytes - 2, 2 do
    local c = s:byte(i) + s:byte(i + 1) * 256
    out[#out + 1] = (c < 128) and string.char(c) or "?"
  end
  return table.concat(out)
end

local function alignUp(n, a) return math.ceil(n / a) * a end

-- A reader over one launcher import: read(offset, length) -> bytes.
local function importReader(mod, id)
  local imports = mod and mod.imports
  if not imports then return nil, "this build has no mod.imports" end
  local info, err = imports:info(id)
  if not info then return nil, err or "the 3DS dump is not imported" end
  if info.ready == false then return nil, info.reason or "the 3DS dump is not imported" end
  local size = tonumber(info.size or info.bytes)
  if not size or size <= 0 then return nil, "the 3DS dump's size is unknown" end

  local function read(offset, length)
    assert(offset >= 0 and length >= 0, "invalid 3DS read range")
    if length == 0 then return "" end
    assert(offset + length <= size, "3DS read past the end of the dump")
    local parts, at, left = {}, offset, length
    while left > 0 do
      local n = math.min(left, SLICE)
      local bytes, why = imports:read(id, at, n)
      assert(type(bytes) == "string" and #bytes == n,
             why or "short read from the 3DS dump")
      parts[#parts + 1] = bytes
      at, left = at + n, left - n
    end
    return table.concat(parts)
  end
  return { read = read, size = size, info = info }
end

-- Locate the NCCH that holds the game: partition 0 of an NCSD, or the file
-- itself when it is a bare NCCH.
local function findNcch(src)
  local head = src.read(0, 0x200)
  if head:sub(0x101, 0x104) == "NCCH" then return 0 end
  if head:sub(0x101, 0x104) ~= "NCSD" then
    return nil, "not a 3DS cartridge image (.3ds/.cci) or NCCH (.cxi)"
  end
  local off = u32(head, 0x121) * MEDIA
  if off == 0 then return nil, "the cartridge image has no game partition" end
  return off
end

function R.open(mod, id)
  local src, err = importReader(mod, id)
  if not src then return nil, err end

  local ncchOff, why = findNcch(src)
  if not ncchOff then return nil, why end
  local ncch = src.read(ncchOff, 0x200)
  if ncch:sub(0x101, 0x104) ~= "NCCH" then return nil, "game partition is not an NCCH" end

  local flags7 = ncch:byte(0x18F + 1)
  if math.floor(flags7 / 4) % 2 == 0 then
    return nil, "this dump is ENCRYPTED; decrypt it with GodMode9 or dump it decrypted from Azahar/Citra"
  end

  local self = {
    src = src,
    ncchOffset = ncchOff,
    productCode = (ncch:sub(0x151, 0x160):gsub("%z.*$", "")),
    -- u64 at 0x118 (u32 takes 1-based positions)
    programId = string.format("%08X%08X", u32(ncch, 0x11D), u32(ncch, 0x119)),
    files = {}, byPath = {},
  }

  local romfsOff = ncchOff + u32(ncch, 0x1B1) * MEDIA
  local romfsSize = u32(ncch, 0x1B5) * MEDIA
  if romfsSize == 0 then return nil, "the game partition has no RomFS" end
  local ivfc = src.read(romfsOff, 0x60)
  if ivfc:sub(1, 4) ~= "IVFC" then return nil, "RomFS has no IVFC header (still encrypted?)" end
  local masterHash = u32(ivfc, 0x09)
  local l3Block = 2 ^ u32(ivfc, 0x4D)
  local l3 = romfsOff + alignUp(0x60 + masterHash, l3Block)

  local h = src.read(l3, 0x28)
  local dirMetaOff, dirMetaLen = u32(h, 0x0D), u32(h, 0x11)
  local fileMetaOff, fileMetaLen = u32(h, 0x1D), u32(h, 0x21)
  local dataOff = l3 + u32(h, 0x25)
  local dirs = src.read(l3 + dirMetaOff, dirMetaLen)
  local fileMeta = src.read(l3 + fileMetaOff, fileMetaLen)

  local function walkFiles(first, prefix)
    local at = first
    while at ~= NONE do
      local p = at + 1
      local nameLen = u32(fileMeta, p + 0x1C)
      local name = utf16(fileMeta, p + 0x20, nameLen)
      local path = prefix == "" and name or (prefix .. "/" .. name)
      local f = { path = path, offset = dataOff + u64(fileMeta, p + 0x08),
                  size = u64(fileMeta, p + 0x10) }
      self.files[#self.files + 1] = f
      self.byPath[path:lower()] = f
      at = u32(fileMeta, p + 0x04)
    end
  end

  local function walkDir(at, prefix)
    local p = at + 1
    local nameLen = u32(dirs, p + 0x14)
    local name = nameLen > 0 and utf16(dirs, p + 0x18, nameLen) or ""
    local path = (prefix == "" and name) or (prefix .. "/" .. name)
    if at == 0 then path = "" end
    walkFiles(u32(dirs, p + 0x0C), path)
    local child = u32(dirs, p + 0x08)
    while child ~= NONE do
      walkDir(child, path)
      child = u32(dirs, child + 1 + 0x04)
    end
  end
  walkDir(0, "")
  table.sort(self.files, function(a, b) return a.path < b.path end)

  function self:file(path)
    return self.byPath[tostring(path):lower()]
  end

  function self:readFile(file, off, len)
    if type(file) == "string" then file = assert(self:file(file), "no RomFS file " .. file) end
    off = off or 0
    len = len or (file.size - off)
    assert(off >= 0 and len >= 0 and off + len <= file.size, "read past the end of " .. file.path)
    return self.src.read(file.offset + off, len)
  end

  return self
end

return R
