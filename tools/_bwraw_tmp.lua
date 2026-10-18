love = love or require("tests.love_stub")
local rom = assert(require("src.import.NdsRom").open("Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds"))
local Narc = require("src.import.NarcArchive")
local arc = assert(Narc.parse(assert(rom:read("/a/0/5/7"))))
local count, firsts = {}, {}
for line in io.lines("G:/Gen2Recomped/scratch_claude/bwsites.txt") do
  local mem, at, name = line:match("(%d+) (%d+) (%S+)")
  local d = arc:get(tonumber(mem))
  local p = tonumber(at) + 1  -- opcode end
  local args = {}
  for k = 0, 3 do local lo, hi = d:byte(p + 1 + k * 2, p + 2 + k * 2); args[#args + 1] = lo and ("%X"):format(lo + hi * 256) or "-" end
  local key = name .. " " .. args[1]
  count[key] = (count[key] or 0) + 1
  if not firsts[key] then firsts[key] = table.concat(args, ",") .. " @" .. mem end
end
local keys = {} for k in pairs(count) do keys[#keys + 1] = k end
table.sort(keys, function(a, b) return count[a] > count[b] end)
for i = 1, math.min(40, #keys) do print(count[keys[i]], keys[i], firsts[keys[i]]) end
