-- Headless check for the Switch "no ground" fix (docs/switch.md):
-- the prefix shim must redirect love.filesystem.newFile, and Gen4RangeFile
-- must fall back to a whole read when no File handle opens.
--   python tools/run_lua_check.py tools/switch_terrain_paths_check.lua
local files = { ['heartgold/assets/generated/gen4/terrain/chunks.bin'] = 'abcdefghij' }
local function handle(bytes)
  local pos = 0
  return { seek = function(_, p) pos = p return true end,
           read = function(_, n) local s = bytes:sub(pos + 1, pos + n) pos = pos + #s return s, #s end }
end
love = { filesystem = {
  read = function(p) return files[p] end,
  getInfo = function(p) return files[p] and { type = 'file' } or nil end,
  newFile = function(p) if files[p] then return handle(files[p]) end return nil, 'Does not exist.' end,
} }
package.loaded['src.core.Logger'] = { info = function() end, warn = function() end, error = function() end }
local C = require('src.import.CacheFs')
local R = require('src.render.Gen4RangeFile')
local path = 'assets/generated/gen4/terrain/chunks.bin'

-- before the shim: the un-prefixed path is not there (the Switch symptom)
assert(R.open(path) == nil, 'un-prefixed terrain must not resolve without the shim')

assert(C.installPrefixShim('heartgold/'))
local f = assert(love.filesystem.newFile(path, 'r'), 'shim must redirect newFile')
assert(f:seek(3) and f:read(4) == 'defg')

-- a port whose newFile refuses: whole-read fallback through the shimmed read
love.filesystem.newFile = function() return nil, 'refused' end
local g = assert(R.open(path), 'Gen4RangeFile must fall back to love.filesystem.read')
assert(g:seek(5) and g:read(3) == 'fgh')
assert(g:seek(8) and g:read(10) == 'ij')
print('4 Switch terrain path checks passed')
