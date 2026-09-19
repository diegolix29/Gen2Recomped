-- FireRed's warp_event rows are destinations as well as entrances.  The
-- field controller only starts an arrival warp for IsWarpMetatileBehavior;
-- ordinary floor rows and directional arrows/mats/stairs stay inert here.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local GameVersion = require("src.core.GameVersion")
local Map = require("src.world.Map")
local Warp = require("src.world.Warp")
local S = require("tests.harness").suite("parity FireRed warp allowlist")
local check = S.check

local oldVersion = GameVersion.get()
GameVersion.set("firered")

local behaviour = 0x00
local fake = setmetatable({
  tileset = { warpsAreEvents = true, behaviourBytes = true },
  doorTiles = {}, warpTiles = {},
  widthCells = 8, heightCells = 8,
}, { __index = Map })
function fake:cellBehaviour() return behaviour end
function fake:warpAtCell() return { def = { destMap = "TEST" } } end

local allowed = {
  [0x60] = true, [0x61] = true, [0x66] = true, [0x67] = true,
  [0x68] = true, [0x69] = true, [0x6A] = true, [0x6B] = true,
  [0x71] = true,
}
for b = 0, 0xFF do
  behaviour = b
  local active = fake:isWarpTileCell(3, 3)
  check(active == (allowed[b] == true),
        ("behaviour $%02X arrival=%s"):format(b, tostring(active)))
end

behaviour = 0x00
check(Warp.onArrive(fake, 3, 3) == nil,
      "plain-floor warp_event is not an arrival warp")
check(not Warp.extraCheck(fake, nil, 0, 7, "down"),
      "plain-floor warp_event does not gain the Gen 1 map-edge fallback")

behaviour = 0x65
check(Warp.onArrive(fake, 3, 3) == nil,
      "south exit mat is not an arrival warp")
check(Warp.extraCheck(fake, nil, 3, 3, "down"),
      "south exit mat fires when walked south")
check(not Warp.extraCheck(fake, nil, 3, 3, "right"),
      "south exit mat stays inert when walked sideways")

behaviour = 0xEC
check(Warp.extraCheck(fake, nil, 3, 3, "right"),
      "right stair warp fires from the matching walk")
check(not Warp.extraCheck(fake, nil, 3, 3, "up"),
      "right stair warp stays inert from a vertical walk")

GameVersion.set("emerald")
behaviour = 0x00
check(fake:isWarpTileCell(3, 3),
      "Emerald keeps the existing warp-event arrival semantics")

GameVersion.set(oldVersion)
S.finish()
