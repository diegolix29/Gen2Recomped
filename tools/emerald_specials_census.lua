-- Run:  python tools/run_lua_check.py tools/emerald_specials_census.lua [rows]
--
-- WHICH OF EMERALD'S SPECIALS THE SCRIPTS CALL THAT NOTHING HANDLES, ranked by
-- call sites -- the Gen 3 counterpart of tools/gen4_declined_census_check.lua.
-- Reads every `special` / `specialvar` in the Emerald cache's map_scripts and
-- asks Gen3Commands.SPECIALS; names come from src/script/Gen3Specials.lua.
package.path = './?.lua;./?/init.lua;' .. package.path; love = require('tests.love_stub'); require('src.core.GameVersion').set('emerald')
local ok, C = pcall(require, 'src.script.Gen3Commands')
if not ok then print('load failed: ' .. tostring(C)) return end
local S = require('src.script.Gen3Specials')
local f = io.open('G:/Gen2Recomped/emerald/data/generated/map_scripts.lua', 'rb'); local chunk = loadstring(f:read('*a')); f:close()
setfenv(chunk, {}); local scripts = chunk().scripts
local count, scriptsOf = {}, {}
for label, list in pairs(scripts) do
  if type(list) == 'table' then
    for _, ins in ipairs(list) do
      if type(ins) == 'table' then
        local id
        if ins[1] == 'special' then id = ins[2] elseif ins[1] == 'specialvar' then id = ins[3] end
        if type(id) == 'number' then count[id] = (count[id] or 0) + 1; scriptsOf[id] = scriptsOf[id] or label end
      end
    end
  end
end
local rows, handled, total = {}, 0, 0
for id, n in pairs(count) do
  total = total + 1
  if C.SPECIALS[id] then handled = handled + 1 else rows[#rows + 1] = { id = id, n = n } end
end
table.sort(rows, function(a, b) return a.n > b.n end)
print(('specials called: %d, handled %d, missing %d'):format(total, handled, #rows))
local sites = 0 for _, r in ipairs(rows) do sites = sites + r.n end
print('missing call sites: ' .. sites)
for i = 1, math.min(#rows, tonumber(arg[1]) or 60) do
  print(('%5d  %-48s %s'):format(rows[i].n, S.label(rows[i].id), scriptsOf[rows[i].id]))
end
