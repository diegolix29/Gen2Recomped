-- HEARTGOLD / SOULSILVER'S CONNECT TO POKeWALKER (main menu, bank 442 line 9).
--
-- On the cartridge it opens the infrared link to the Pokewalker: send a
-- Pokemon off on a course, bring it home with what it found. This port's
-- Pokewalker is the launcher's Monster Walker (src/ui/PokewalkerScreen.lua),
-- so the row hands back to the launcher and asks it to open there, at this
-- game's save picker (main.lua honours HostShell.requestLauncher).

local Strings = require("src.core.Strings")

local M = {}
M.BANK, M.LINE = 442, 9

function M.menuItems(game)
  local GameVersion = require("src.core.GameVersion")
  local okF, Bands = pcall(require, "src.import.Gen4ScriptBands")
  if not (okF and Bands.family == "hgss") then return {} end
  local version = GameVersion.get()
  local okS, slots = pcall(require("src.core.SaveData").listSlots, version)
  local any = false
  for _, s in ipairs(okS and slots or {}) do if s.exists then any = true end end
  if not any then return {} end
  local t = game.data and game.data.text
  local label = t and t[("TEXT_B%04d_%05d"):format(M.BANK, M.LINE)] or Strings("CONNECT TO POKéWALKER")
  return { { key = "pokewalker", label = label, lines = 1, onSelect = function()
    local HostShell = require("src.core.HostShell")
    HostShell.requestLauncher({ section = "walker", version = version })
    if game.returnToLauncher then game:returnToLauncher() else HostShell.toLauncher() end
  end } }
end

return M
