-- Regression: FireRed must be reachable from the launcher as an official
-- Gen 3 cartridge, immediately before Emerald.
return function()
  local versions = require("src.core.GameVersion")
  local fireRedAt, emeraldAt
  for i, id in ipairs(versions.ORDER) do
    if id == "firered" then fireRedAt = i end
    if id == "emerald" then emeraldAt = i end
  end
  assert(fireRedAt, "FireRed is missing from the launcher game order")
  assert(emeraldAt and fireRedAt + 1 == emeraldAt,
    "FireRed must precede Emerald in the launcher game order")
  assert(versions.info("firered").importable,
    "FireRed must remain importable from the launcher")
  print("[driver] PASS FireRed launcher registration")
  love.event.quit(0)
end
