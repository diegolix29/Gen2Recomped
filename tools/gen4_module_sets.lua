-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.

-- Does Data.requiredModules still answer the same way for Gen 1, Gen 2 and
-- Gen 3 caches?
--
-- src/core/Data.lua decides which modules a cache must provide, and it is the
-- file every generation boots through.  Adding a Gen 4 branch to it is the
-- kind of change that cannot be checked by reading: the risk is not that Gen 4
-- comes out wrong -- that is visible immediately -- but that Crystal, Gold,
-- Silver or Prism quietly start being asked for a different set.
--
-- So this pulls requiredModules and its module lists out of TWO copies of
-- Data.lua and runs both against synthetic caches, one per marker.  A cache is
-- just a directory with the marker module in it, because the marker is all
-- requiredModules looks at.
--
--   usage: texlua tools/gen4_module_sets.lua [<reference Data.lua>]
--
-- With no argument it checks the current file against itself, which proves
-- only that it runs; the point is to pass the PREVIOUS Data.lua and see that
-- every row but the Gen 4 one is identical.

local function extract(path)
  local handle = assert(io.open(path, "rb"), "cannot open " .. path)
  local source = handle:read("*a")
  handle:close()
  source = source:gsub("\r\n", "\n")

  local parts = {}
  for _, name in ipairs({ "SHARED_MODULES", "CLASSIC_MODULES",
                          "GEN3_MODULES", "GEN4_MODULES" }) do
    -- A list this copy does not have is not an error: the reference copy is
    -- older than the branch by design.
    local chunk = source:match("\nlocal " .. name .. " = %{.-\n%}")
    if chunk then parts[#parts + 1] = chunk end
  end
  parts[#parts + 1] = source:match("\nlocal function loadModule%(.-\nend")
  -- Anchored on "\nend" alone.  An earlier version also required a line
  -- beginning "return out", which the Gen 4 version does not have -- its
  -- return is indented, so the pattern silently matched nothing and the whole
  -- extraction came back nil.  Neither function nests an unindented `end`.
  parts[#parts + 1] = source:match("\nlocal function requiredModules%(.-\nend")
  parts[#parts + 1] = "return requiredModules"

  local loader = assert(load(table.concat(parts, "\n"), path))
  return loader()
end

local HERE = "src/core/Data.lua"
local current = extract(HERE)
local reference = arg and arg[1] and extract(arg[1]) or nil

local CASES = {
  { name = "gen1/gen2", marker = nil },
  { name = "gen3", marker = "save_layout" },
  { name = "gen4", marker = "gen4_map_headers" },
}

local root = os.getenv("TMPDIR") or "/tmp"
local base = root .. "/gen2recomped_module_sets"
os.execute("rm -rf " .. base)

local changed = 0
for _, case in ipairs(CASES) do
  local dir = base .. "/" .. case.name:gsub("[^%w]", "_")
  os.execute("mkdir -p " .. dir)
  if case.marker then
    local f = assert(io.open(dir .. "/" .. case.marker .. ".lua", "w"))
    f:write("return {}\n")
    f:close()
  end

  local now, nowGen3, nowGen4 = current(dir)
  local line = ("%-10s -> %2d modules (gen3=%s gen4=%s)")
    :format(case.name, #now, tostring(nowGen3), tostring(nowGen4))

  if reference then
    local was, wasGen3 = reference(dir)
    local same = table.concat(was, " ") == table.concat(now, " ")
                 and wasGen3 == nowGen3
    -- The Gen 4 row is SUPPOSED to differ; every other row differing is the
    -- failure this file exists to catch.
    local expected = (case.name == "gen4")
    if same == expected then
      changed = changed + 1
      print(line .. (same and "  UNCHANGED (expected a change)"
                          or "  CHANGED (expected none)"))
      print("    was: " .. table.concat(was, " "))
      print("    now: " .. table.concat(now, " "))
    else
      print(line .. (same and "  identical to the reference" or "  changed, as intended"))
    end
  else
    print(line .. "  " .. table.concat(now, " "))
  end
end

os.execute("rm -rf " .. base)
if reference then
  print(changed == 0 and "\nOK: only the Gen 4 answer changed"
                      or ("\nFAIL: %d row(s) answered unexpectedly"):format(changed))
end
os.exit(changed == 0 and 0 or 1)
