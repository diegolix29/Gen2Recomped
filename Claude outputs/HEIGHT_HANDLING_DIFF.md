# Why characters stand on the ground in one build and inside it in the other

Two copies of this mod are installed and they are not the same code:

| | appdata `mods/DRAMATIC_SHAPE` | `G:\Gen2Recomped\mods\DRAMATIC_SHAPE-2` (the one being loaded) |
|---|---|---|
| `lib/VoxelScene.lua` | 140 KB | 89 KB |
| `lib/ChunkMesher.lua` | 138 KB | 59 KB |
| `lib/Gen3.lua` | 357 KB | 332 KB |
| `lib/Structures.lua` | 1.36 MB | 1.28 MB |

The height work lives in the bigger one. The loaded build is an earlier cut.

## The one function that differs

`VoxelScene.groundAt` — the function every character's feet go through.

**Loaded build (`DRAMATIC_SHAPE-2`, line 203):**

```lua
local function groundAt(map, cellX, cellY)
  ...
  local s = TileShape.at(map, shapes, tile, tx, ty)
  if not s then return 0 end
  if s.art == "stair" then return 0 end
  if map.doorTiles and map.doorTiles[tile] then return 0 end
  if s.h and s.h < 0 then return s.h end
  return s.h > 0 and s.h or 0
end
```

That is the **tileset art's** class height and nothing else. It never reads the
elevation grid. On Hoenn, ordinary ground art is height 0 — so on a map whose
terrain the mesher has raised (your log: `terraces from roles — 34 terrace(s)
… cells z0=2340 z16=1732 z32=607 z48=12; 6708 tile(s) raised`), the ground
rises to 16, 32 or 48 and the character is still answered **0**. That is the
report, exactly: the terrain goes up, the player doesn't, and on the raised
parts of the map they're inside it.

It also takes no `elev` and no pixel position, which rules out the two cases
that need them before they're even considered.

**appdata build (line 191):**

```lua
local function groundAt(map, cellX, cellY, elev, px, py)
```

and it asks, in this order:

1. **off the map** → 0 (the seam-step case)
2. **doorway** (`s.art == "upright"` but walkable) → `Structures.standHeight`,
   not 0 — a doorway cut into a facade founded four courses up
3. **stairs / flights** → `Structures.flightEnds` gives the two landings, and
   `px`/`py` give the position along the run, so a flight *climbs continuously*
   instead of popping a course at the top. The loaded build returns `0` here,
   which the newer one names as "the whole of the stairs-don't-lead-up report"
4. **bridge decks** — keyed on elevation **15**, not on the voxel class,
   because Victory Road's crossings are ordinary floor metatiles whose only
   statement of "deck" is the elevation. It then *walks along the span* to find
   a cell at the walker's own level and asks that cell instead. This is what
   keeps the walker under Fortree's rope walkway on the street instead of
   teleporting them onto the planks
5. **terrace** → `Structures.terraceAt`
6. **stamp** → `Structures.stampGround` (props whose art was lathed into a hull)
7. measured height, then the class default

## The Gen 3 height ladder

`lib/Gen3.lua`, `buildElevationRanks` (line 436) — this is the part worth
copying verbatim:

```lua
-- collect the levels actually present, ignoring 0 (any), 15 (deck), 1 (surf)
table.sort(list)
local datum = rank[ELEV_DEFAULT] or 1      -- elevation 3 is ordinary ground
for e, i in pairs(rank) do height[e] = (i - datum) * COURSE end   -- COURSE = 16
```

Rank the levels **this map uses** and space them one metatile apart, with
elevation 3 at zero. Route 119 uses three levels; Victory Road uses six. A
fixed table can't separate six, and reading the nibble as a height sinks every
elevation-0 cell three courses below the land beside it.

`ctx.groundHeight` (line 1091) then resolves the two non-levels: a **0** cell
takes a ramp height (or the lowest real level touching it), and a **15** cell
is lifted by the bridge behaviour — `MetatileBehavior_GetBridgeType` maps
LOW/MED/HIGH to 0/1/2, floored at the datum rather than at the neighbour so a
bridge over the sea doesn't hang fourteen pixels above the water.

## Where the feet actually get set

`posesOf` (line 1435). Player, NPCs and neighbour-map ghosts all go through the
same call, and all three pass the entity's elevation and pixel position:

```lua
gh = plantedOn(state.map, e,
               groundAt(state.map, e.cellX, e.cellY, e.elevation, vx, e.py)),
```

The loaded build's equivalent is `entityGround(map, e, px, py)`, which uses
`px`/`py` **only** for water swell and ice, and otherwise ends at
`groundAt(map, e.cellX, e.cellY)` — elevation dropped on the floor.

`plantedOn` is the object case: for a berry plot the feet go on the **top of
the hull** the mesher stamped there, not on the floor the hull stands on,
reproducing `ChunkMesher`'s own placement line for line.

## Engine side

`mod.world` and the `gen3WorldFor` descriptor now carry the ladder, so it
doesn't have to be re-derived:

```lua
world.elevationHeights   -- { [elevation] = world pixels }, map-relative
world.elevationLevels    -- how many levels this map uses
world.course             -- 16
world.heightAt(cx, cy)   -- nil + "transition cell" / "bridge cell" on 0 and 15

mod.world:elevationRanks()      -- same, with mapId/ground/wildcard/underBridge
mod.world:heightAt(x, y)
```

`heightAt` **declines** on 0 and 15 rather than guessing. Those are the two the
appdata build spends most of its code resolving, and a guess at either is what
puts somebody underground.
