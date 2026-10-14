-- Bugsy's gym in Azalea Town: the Spinarak carts (HeartGold / SoulSilver).
--
-- Everything here is pokeheartgold's src/field/gymmick/azalea.c and
-- gymmick_init.c, transcribed:
--
--   * twelve stations (sSpinarakInitialPositions), four Spinarak standing at
--     four of them -- InitAzaleaGym puts them at 0, 1, 2 and 7 -- and two
--     switches, a bit each;
--   * a route per (station, switch state) (sSpinarakRoutes_From1..12): the
--     node list, and which station the cart ends at;
--   * the ride: the cart (build model 118, drawn 8 units east of its node)
--     runs node to node at 2 units a frame along the normalised segment, the
--     player 8, 8 off it and one tile further down when the ride goes down
--     the room (stations 3, 4, 5, 9, 10, 11 run their route BACKWARDS).
--
-- What this file leaves out: the switches' own lever animations (props 115,
-- 116, 117, 122), the camera's four-frame shake at the end, and the ride's
-- sound -- the cart and the player move exactly as the cartridge moves them.

local G = {}

local function n(x, z) return { x = x, z = z } end

local R_1to5  = { n(3,31), n(3,29), n(9,29), n(9,27), n(15,28), n(15,25), n(9,25), n(9,24) }
local R_2to6  = { n(9,31), n(9,29), n(3,29), n(3,27), n(9,26), n(9,25), n(15,25), n(15,24) }
local R_3to4  = { n(15,31), n(15,28), n(9,27), n(9,26), n(3,27), n(3,24) }
local R_7to10 = { n(3,16), n(3,12), n(9,13), n(9,10), n(3,10), n(3,9) }
local R_7to11 = { n(3,16), n(3,12), n(9,13), n(9,9) }
local R_8to10 = { n(9,16), n(9,14), n(15,14), n(15,11), n(9,12), n(9,10), n(3,10), n(3,9) }
local R_8to12 = { n(9,16), n(9,14), n(15,14), n(15,9) }
local R_8to11 = { n(9,16), n(9,14), n(15,14), n(15,11), n(9,12), n(9,9) }

G.STATIONS = { n(3,31), n(9,31), n(15,31), n(3,24), n(9,24), n(15,24),
               n(3,16), n(9,16), n(15,16), n(3,9), n(9,9), n(15,9) }

local function r(route, dest) return { route = route, destination = dest } end
local function same(route, dest) return { r(route, dest), r(route, dest), r(route, dest), r(route, dest) } end

-- ROUTES[station + 1][switches + 1] (both zero-based on the cartridge)
G.ROUTES = {
  same(R_1to5, 4), same(R_2to6, 5), same(R_3to4, 3), same(R_3to4, 2),
  same(R_1to5, 0), same(R_2to6, 1),
  { false, r(R_7to10, 9), false, r(R_7to11, 10) },
  { r(R_8to10, 9), r(R_8to12, 11), r(R_8to11, 10), r(R_8to12, 11) },
  { false, false, false, false },
  { r(R_8to10, 7), r(R_7to10, 6), false, false },
  { false, false, r(R_8to11, 7), r(R_7to11, 6) },
  { false, r(R_8to12, 7), false, r(R_8to12, 7) },
}

G.CART_MODEL = 118
G.SPEED = 2          -- units a frame, along the segment
G.BACKWARDS = { [3] = true, [4] = true, [5] = true, [9] = true, [10] = true, [11] = true }

-- InitAzaleaGym
function G.initialState() return { kind = "azalea", spiders = { 0, 1, 2, 7 }, switches = 0 } end

-- The four carts as runtime props, map world units (Gen4Ground)
function G.props(state, override)
  local out = {}
  for i, station in ipairs(state.spiders) do
    local s = G.STATIONS[station + 1]
    local x, z = s.x * 16 + 8, s.z * 16
    if override and override.index == i then x, z = override.x + 8, override.z end
    out[i] = { model = G.CART_MODEL, x = x, y = 0, z = z }
  end
  return out
end

-- FlipAzaleaGymSwitch
function G.flip(state, which)
  local bit = (which == 1) and 2 or 1
  if math.floor(state.switches / bit) % 2 == 1 then state.switches = state.switches - bit
  else state.switches = state.switches + bit end
end

-- ride(state, station) -> a ride, or nil when no cart stands there (the
-- cartridge asserts and does nothing) or the switches give it no route
function G.ride(state, station)
  local which
  for i, s in ipairs(state.spiders) do if s == station then which = i end end
  if not which then return nil end
  local route = G.ROUTES[station + 1] and G.ROUTES[station + 1][state.switches + 1]
  if not route then return nil end
  local backwards = G.BACKWARDS[station] or false
  local nodes = {}
  if backwards then
    for i = #route.route, 1, -1 do nodes[#nodes + 1] = route.route[i] end
  else
    for i = 1, #route.route do nodes[i] = route.route[i] end
  end
  return {
    spider = which, destination = route.destination, nodes = nodes, at = 1,
    x = nodes[1].x * 16, z = nodes[1].z * 16,
    -- the player rides a tile below the cart when the ride runs down the room
    playerZOffset = backwards and 1 or 0,
    stepDir = backwards and "down" or "up",
  }
end

-- step(ride) -> true when the ride has reached its last node. The segment's
-- vector is normalised and doubled once, when the segment starts; each frame
-- an axis that would pass its node stops (AzaleaGymmick_GetMovementDoneParams
-- answering 2), and once both axes are on or past it the cart snaps to the
-- node -- so on a slanted run the slower axis keeps its own speed after the
-- faster one has arrived, as on the cartridge.
local function doneState(sign, cur, delta, target)
  if cur + delta == target then return 1 end
  if sign then return (cur + delta > target) and 2 or 0 end
  return (cur + delta < target) and 2 or 0
end
function G.step(ride)
  local nextNode = ride.nodes[ride.at + 1]
  if not nextNode then return true end
  local tx, tz = nextNode.x * 16, nextNode.z * 16
  if not ride.vec then
    local prev = ride.nodes[ride.at]
    local dx, dz = nextNode.x - prev.x, nextNode.z - prev.z
    local len = math.sqrt(dx * dx + dz * dz)
    ride.vec = { dx / len * G.SPEED, dz / len * G.SPEED, dx >= 0, dz >= 0 }
  end
  local v = ride.vec
  local xd = doneState(v[3], ride.x, v[1], tx)
  local zd = doneState(v[4], ride.z, v[2], tz)
  if xd == 2 then v[1] = 0 end
  if zd == 2 then v[2] = 0 end
  if xd ~= 0 and zd ~= 0 then
    ride.x, ride.z = tx, tz
    ride.at = ride.at + 1
    ride.vec = nil
    return ride.at >= #ride.nodes
  end
  ride.x, ride.z = ride.x + v[1], ride.z + v[2]
  return false
end

return G
