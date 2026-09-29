-- gen4_texture_files_check.lua -- which terrain textures are NAMED but not ON DISK.
--
-- `Assets.image` returns a placeholder for a missing path and says nothing, so a
-- texture that is correctly named, correctly in its set and simply never written
-- produces "some areas draw placeholder tile art" with no error anywhere.  This
-- resolves every path the terrain cache references and reports the misses.
--
--   run from the repo root:  texlua tools/gen4_texture_files_check.lua
--                       or:  lua    tools/gen4_texture_files_check.lua
--
-- Exit status is 1 when anything is missing, so it can gate a build.

local ROOTS = { "", "assets/", "../", "data/" }

local function exists(path)
  for _, root in ipairs(ROOTS) do
    local f = io.open(root .. path, "rb")
    if f then f:close() return true, root .. path end
  end
  return false
end

local ok, terrain = pcall(dofile, "data/generated/gen4_terrain.lua")
if not ok or type(terrain) ~= "table" then
  io.stderr:write("could not load data/generated/gen4_terrain.lua -- run me from the repo root\n")
  os.exit(2)
end

-- Which sets each map uses, so a miss can be reported as "N maps affected"
-- rather than as a set number nobody can place.
local mapsPerSet = {}
for _, def in pairs(terrain.maps or {}) do
  if def.texture then mapsPerSet[def.texture] = (mapsPerSet[def.texture] or 0) + 1 end
end

local sets, checked, missing = 0, 0, 0
local rows = {}
for id, set in pairs(terrain.sets or {}) do
  sets = sets + 1
  local gone, total = {}, 0
  for name, tex in pairs(set.textures or {}) do
    if tex.path then
      total = total + 1
      checked = checked + 1
      if not exists(tex.path) then
        missing = missing + 1
        gone[#gone + 1] = name
      end
    end
  end
  if #gone > 0 then
    table.sort(gone)
    rows[#rows + 1] = { id, #gone, total, mapsPerSet[id] or 0, gone }
  end
end

table.sort(rows, function(a, b) return a[4] > b[4] end)

print(("terrain texture sets: %d   texture files referenced: %d   MISSING: %d (%.1f%%)")
  :format(sets, checked, missing, checked > 0 and 100 * missing / checked or 0))

if missing == 0 then
  print("every referenced texture is on disk.")
  os.exit(0)
end

print("")
print(("%-6s %-14s %-8s %s"):format("set", "missing/total", "maps", "first few names"))
for _, r in ipairs(rows) do
  local shown = {}
  for i = 1, math.min(#r[5], 6) do shown[i] = r[5][i] end
  print(("%-6s %-14s %-8d %s%s"):format(
    tostring(r[1]), ("%d/%d"):format(r[2], r[3]), r[4],
    table.concat(shown, ", "), (#r[5] > 6) and (" ... +" .. (#r[5] - 6)) or ""))
end

print("")
print("A set with misses draws placeholder art on every map that uses it.")
os.exit(1)
