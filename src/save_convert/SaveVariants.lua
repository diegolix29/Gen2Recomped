-- SaveVariants -- the save files that are "the right save, the wrong size".
--
-- The import used to measure every file against one number per generation
-- (32768 for a Game Boy battery, 131072 for GBA flash, 512 KiB for a DS) and
-- refuse anything else with "A <game> save file must be N bytes; this one is
-- M".  Reported as "importing a save from an old version fails with size
-- doesn't match".  The files that hit it are real saves in a wrapper:
--
--   PORT SAVES.  This port's own slot files (saves/<version>/slotN.lua, a
--   .bak of one, save_online.lua, the pre-slot save.lua) from an older build.
--   They are text, not a battery image, so no size could ever match.  They are
--   decoded with SaveSerializer and brought forward with SaveData.runMigrations
--   -- the same pass every load runs -- then written as a fresh slot.
--
--   GAME BOY (Gen 1 / Gen 2, 32 KiB SRAM)
--     * + 44 or 48 bytes: the MBC3 real-time-clock footer VBA, VBA-M, BGB,
--       mGBA, Gambatte and My OldBoy append (Gold / Silver / Crystal; some of
--       them write it for Red too).  The clock is not modelled; it is dropped.
--     * 64 KiB: padded, or the 32 KiB image written twice.
--   GAME BOY ADVANCE (Gen 3, 128 KiB flash)
--     * + 16 bytes (mGBA's RTC block) or any other short footer.
--     * 64 KiB: an emulator left on 512 Kbit flash.  The image is padded back
--       to 128 KiB with erased flash (0xFF); slot A is whole in the first
--       64 KiB, and Gen3Save's own sector checks decide whether it is usable.
--     * padded past 128 KiB with erased (0xFF) or zero bytes.
--   NINTENDO DS (Gen 4 / Gen 5): NdsSave.unwrap already handles DeSmuME's
--   .dsv footer, no$gba's header and 1 MiB images; this only routes to it.
--
-- Anything else is still refused, with the size it expected.  Pure Lua, no
-- love.* at require time.

local SaveVariants = {}

-- the longest trailer treated as a footer rather than as data
SaveVariants.MAX_FOOTER = 64

local KNOWN_FOOTERS = {
  gb = { [44] = "RTC footer (VBA / BGB, 32-bit time)", [48] = "RTC footer (VBA-M / mGBA / BGB)" },
  gba = { [16] = "RTC footer (mGBA)" },
}

local function uniform(s, from)
  -- every byte from `from` on is the same erased value (0x00 or 0xFF)
  local b = s:byte(from)
  if b ~= 0 and b ~= 255 then return false end
  local run = string.char(b)
  local i = from
  local step = 4096
  while i <= #s do
    local j = math.min(#s, i + step - 1)
    if s:sub(i, j) ~= run:rep(j - i + 1) then return false end
    i = j + 1
  end
  return true
end

-- Is this one of this port's own text saves?  ("return {" after optional
-- whitespace / a UTF-8 BOM -- what SaveSerializer.encode writes.)
function SaveVariants.isPortSave(bytes)
  if type(bytes) ~= "string" or #bytes < 8 then return false end
  local head = bytes:sub(1, 64):gsub("^\239\187\191", "")
  return head:match("^%s*return%s*{") ~= nil
end

-- normalize(bytes, want, family) -> raw image, how | nil, why
-- `want` is the codec's size; `family` is "gb", "gba" or "nds".
function SaveVariants.normalize(bytes, want, family)
  if type(bytes) ~= "string" then return nil, "expected save bytes" end
  local n = #bytes
  if n == want then return bytes, "raw" end
  if family == "nds" then
    local raw, how = require("src.save_convert.NdsSave").unwrap(bytes)
    if raw then return raw, how end
    return nil, how
  end
  if n > want then
    local extra = n - want
    local known = KNOWN_FOOTERS[family] and KNOWN_FOOTERS[family][extra]
    if known then return bytes:sub(1, want), known end
    if extra <= SaveVariants.MAX_FOOTER then return bytes:sub(1, want), "footer" end
    if n == want * 2 and bytes:sub(1, want) == bytes:sub(want + 1) then
      return bytes:sub(1, want), "mirrored"
    end
    if uniform(bytes, want + 1) then return bytes:sub(1, want), "padded" end
    return nil, ("the %d bytes after the save are not padding or an emulator footer"):format(extra)
  end
  -- short: only the GBA half-size flash image is a known shape
  if family == "gba" and n == want / 2 then
    return bytes .. string.rep("\255", want - n), "64 KiB flash"
  end
  return nil, nil
end

-- the codec family for a generation number
function SaveVariants.family(generation)
  if generation == 3 then return "gba" end
  if generation == 4 or generation == 5 then return "nds" end
  return "gb"
end

-- importPortSave(bytes, version) -> save table | nil, why
-- Decodes one of this port's own .lua saves and runs the migrations every
-- load runs.  A save that names a different game is refused: the slot
-- layout, the species and the maps all belong to the game that wrote it.
function SaveVariants.importPortSave(bytes, version)
  local SaveSerializer = require("src.core.SaveSerializer")
  local text = bytes:gsub("^\239\187\191", "")
  local save, err = SaveSerializer.decode(text)
  if not save then return nil, "this looks like a Gen2Recomped save but could not be read (" .. tostring(err) .. ")" end
  local from = save.version or (type(save.meta) == "table" and save.meta.version) or nil
  if from ~= nil and version ~= nil and from ~= version then
    local ok, GameVersion = pcall(require, "src.core.GameVersion")
    local name = function(v)
      local info = ok and GameVersion.VERSIONS and GameVersion.VERSIONS[v]
      return (info and info.displayName) or tostring(v)
    end
    return nil, ("this is a %s save; import it on the %s page"):format(name(from), name(from))
  end
  if type(save.player) ~= "table" then
    return nil, "this file is a Gen2Recomped table but not a save (no player)"
  end
  -- options live in their own file now; an old save.lua carried them inline,
  -- and an import must not overwrite the player's current options with them
  save.options = nil
  local SaveData = require("src.core.SaveData")
  local okm, merr = pcall(SaveData.runMigrations, save)
  if not okm then return nil, "this save could not be brought up to date: " .. tostring(merr) end
  save.version = version or from
  return save
end

return SaveVariants
