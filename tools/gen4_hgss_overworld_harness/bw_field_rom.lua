-- tools/gen4_hgss_overworld_harness/bw_field_rom.lua
--
-- BW_FIELD_ROM=<Black/White .nds>: what the gen5-field-effects import adds,
-- read from the ROM as the data loads, so an install imported before it
-- shows it (src/import/Gen5FieldEffects.lua):
--
--   gen4_emotes                 the "!" "?" note "..." bubbles (/a/0/7/5 50-53)
--   gen5_field_effects          phenomena, lure, ripple pictures + BTP tables
--   gen4_models.sets.fldeff     the sea_ride surf mount (its two PNGs are
--                               written under the install's
--                               assets/generated/gen4/models/bw_fldeff/, as an
--                               import would write them)
--   field.playerForms           bike / surf sheets (Gen5PlayerForms)

local Data = require("src.core.Data")
local load0 = Data.load
Data.load = function(self, ...)
  local r = { load0(self, ...) }
  local path = os.getenv("BW_FIELD_ROM")
  local rom = require("src.import.NdsRom").open(path)
  local install = (os.getenv("INSTALL") or ""):gsub("[/\\]+$", "")
  local function saveImage(rel, image, extra)
    local okI, data = pcall(love.image.newImageData, image.width, image.height, "rgba8", image.rgba)
    if not okI then return nil end
    local file = "assets/generated/gen4/" .. rel .. ".png"
    local full = install .. "/" .. file
    local dir = full:match("^(.*)/[^/]*$")
    os.execute(('mkdir "%s" 2>nul'):format(dir:gsub("/", "\\")))
    local f = io.open(full, "wb")
    if not f then return nil end
    f:write(data:encode("png"):getString())
    f:close()
    local entry = { path = file, width = image.width, height = image.height }
    for k, v in pairs(extra or {}) do entry[k] = v end
    return entry
  end
  local fx = rom and require("src.import.Gen5FieldEffects").build(rom, saveImage)
  if fx then
    if fx.emotes then self.gen4_emotes = fx.emotes end
    if fx.effects then self.gen5_field_effects = fx.effects end
    if fx.modelSet then
      self.gen4_models = self.gen4_models or { sets = {} }
      self.gen4_models.sets = self.gen4_models.sets or {}
      self.gen4_models.sets.fldeff = fx.modelSet
    end
    print(("BW_FIELD_ROM: emotes %s, %d picture(s), surf mount %s"):format(
      tostring(fx.emotes ~= nil), fx.effects and fx.effects.count or 0,
      tostring(fx.modelSet and fx.modelSet.byMember[49] ~= nil)))
  end
  return (table.unpack or unpack)(r)
end
