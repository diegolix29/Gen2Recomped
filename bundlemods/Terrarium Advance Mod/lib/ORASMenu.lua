-- ORAS.. : every Omega Ruby / Alpha Sapphire row on one menu of its own.
--
-- They used to sit straight on the engine's OPTIONS list -- twelve rows
-- (models, effects, arenas, each with its build, pack and play settings) --
-- which buried everything after them. Now OPTIONS carries one "ORAS.." row
-- (main.lua) and lib/SettingsMenu.lua shows this list as its "oras" category
-- (also reachable from ADVANCED SHAPE..).
--
-- Nothing persists differently: every row keeps its own id, file and value;
-- only where it is drawn changed. ORAS stays independent of Colosseum: no
-- Colosseum row belongs here.

local V = ...

local M = {}

-- in menu order: each feature's build row, its pack row right below it, then
-- the rows that say how it plays
local SOURCES = {
  { "ORASModels", { "row", "packRow" } },
  { "ORASEffects", { "row", "packRow", "battleRow", "sizeRow", "soundRow", "cameraRow", "zoomRow" } },
  { "ORASArenas", { "row", "choiceRow", "packRow" } },
}

-- the rows, each module and each row reached through pcall: a fault in one
-- must not empty the menu
function M.rows()
  local out, seen = {}, {}
  for _, src in ipairs(SOURCES) do
    local okM, mod = pcall(V.require, src[1])
    if okM and type(mod) == "table" then
      for _, fn in ipairs(src[2]) do
        if type(mod[fn]) == "function" then
          local okR, row = pcall(mod[fn])
          if okR and type(row) == "table" and row.id and not seen[row.id] then
            seen[row.id] = true
            out[#out + 1] = row
          end
        end
      end
    end
  end
  return out
end

return M
