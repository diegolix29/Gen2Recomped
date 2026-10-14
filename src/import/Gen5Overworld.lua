-- BLACK AND WHITE'S OVERWORLD CHARACTERS.
--
-- A map's NPC names a sprite id (Gen5Events); the sprite table /a/0/4/8 --
-- one file, a u32 count (799) then 28 bytes per id -- turns the id into a
-- MODEL: its ninth u16 runs 0..763 over exactly 764 distinct values, the
-- member count of /a/0/4/9, an archive of 764 NSBMD files. Gen 5 draws its
-- characters as textured billboards and keeps the frames in each model's own
-- TEX0 -- where Gen 4's mmodel.narc is bare BTX0 texture files.
--
-- So each model's TEX0 is wrapped in the standard 20-byte BTX0 container (the
-- section is the same bytes either way) and handed to Gen4Models.sheet, which
-- already turns a texture file of equal-sized frames into a sheet.

local Nsbmd = require("src.import.Gen4Nsbmd")

local O = {}

O.TABLE = "/a/0/4/8"
O.MODELS = "/a/0/4/9"
O.RECORD_BYTES = 28

local function u16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end
local function u32le(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end

-- table(bytes) -> { [spriteId] = modelMember }
function O.table(bytes)
  local out = {}
  if type(bytes) ~= "string" or #bytes < 4 then return out end
  local n = u16(bytes, 0)
  for i = 0, n - 1 do
    local o = 4 + i * O.RECORD_BYTES
    if o + O.RECORD_BYTES > #bytes then break end
    out[u16(bytes, o)] = u16(bytes, o + 16)
  end
  return out
end

-- btx(nsbmdBytes) -> a BTX0 file holding the model's TEX0, or nil
function O.btx(bytes)
  local sections = bytes and Nsbmd.sections(bytes)
  local at = sections and sections.TEX0
  if not at then return nil end
  local size = bytes:byte(at + 5) + bytes:byte(at + 6) * 256 + bytes:byte(at + 7) * 65536 + bytes:byte(at + 8) * 16777216
  local tex = bytes:sub(at + 1, at + size)
  local total = 20 + #tex
  return "BTX0" .. string.char(0xFF, 0xFE, 0x01, 0x00) .. u32le(total)
         .. string.char(0x10, 0x00, 0x01, 0x00) .. u32le(20) .. tex
end

return O
