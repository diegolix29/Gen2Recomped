# Terrain and character height on `mod.world`

New in the engine. Everything is in **walk cells** (16px), the same space
`mod.world:current()` already reported x/y in.

## The one thing to get right first

The Gen 3 elevation nibble is a **level ID, not a height**. Using it as a
height is what puts a character underground:

| nibble | meaning |
|---|---|
| `0` | "any level" — ordinary ground, and it never changes what a mover is standing at |
| `1` | water |
| `3` | Hoenn's dry land |
| `4`, `6`, `8`, `10`, `12` | raised levels (bridge decks) |
| `13`, `14` | levels that pass over a deck |
| `15` | "under a bridge" — also not a level, also sticky |

Read `0` as height 0 and every ordinary cell drops three units below the
land beside it. Use **`layer`** instead: 0, 1, 2 — bottom-first, derived from
the cartridge's own OAM priority table (`UpdateObjectEventZCoordAndPriority`,
`08096D14`), not invented. Both wildcards land on the bottom layer.

## Terrain

```lua
local info = mod.world:elevationInfo()        -- optional mapId
-- { mapId, supported, width, height, layers, wildcard=0, underBridge=15,
--   ground=3, water=1 }
if not info.supported then ... end            -- every Gen 1 / Gen 2 map

local nibble, layer = mod.world:elevationAt(x, y)     -- nil, "off the map"
local cell = mod.world:terrainAt(x, y)
-- { elevation, raw, layer, wildcard, underBridge, water, walkable, behaviour }
```

Bulk — **use this for meshing**, one crossing instead of 6,400:

```lua
local g = mod.world:elevationGrid({ x = 0, y = 0, width = 32, height = 32 })
-- { mapId, x, y, width, height, cells = {...}, layers = {...} }
-- row-major from (x, y), 1-based: index = row * g.width + col + 1
```

The rectangle is **clipped, never refused**, so a chunk hanging off the map
edge is not a special case. Defaults cover the whole map.

## The character

```lua
local here = mod.world:current()
-- mapId, x, y, facing, px, py, elevation, layer
```

`elevation` is the level the player is **standing at**, which is not always
the level of the cell under them — `0` and `15` do not replace what is held,
so someone crossing under a bridge keeps the ground's level the whole way.
**Use this, not `elevationAt(x, y)`, to place the character.** `px`/`py` are
the pixel position the engine's own camera follows, for smooth movement
between cells.

NPCs:

```lua
local x, y, elevation = mod.world:npc(mapId, "MAN"):position()
local e = handle:elevation()
```

`position()`'s third return is new; the first two are unchanged.

## Seams

```lua
for _, m in ipairs(mod.world:loadedMaps()) do
  -- { mapId, x, y, width, height, active }  -- x/y are cell offsets from the
  -- active map's origin
end
```

Every id listed here answers `elevationAt` / `elevationGrid` / `terrainAt`
via their `mapId` argument. A map that is merely in the dataset does not —
loading one costs a tileset and an atlas, and a draw call is not the place
to pay it.

## Declaring generations

`manifest.json` may carry `"generations": [1, 2, 3]`. A mod that declares
nothing runs everywhere, as before. A mod that declares a list is not loaded
outside it — but that is now a **default, not a wall**: the player can tick
the generation's chip in the launcher, confirm, and the mod loads with a
warning in the log saying it is running outside its own claim. The chip
draws gold instead of green when it is doing that.

---

# Read this part first: the host generation

Your log, on Emerald:

```
[runtime] environment api=unknown
Colosseum UI runtime compatibility: gen1
ColosseumDex mark routing blocked: host generation unavailable
Gen 2 Colosseum battle transition class unavailable; screen.pushed bridge remains active
pokemon.PIKACHU.types[1]: unresolved reference to type_chart "ELECTR"
```

Every one of those is the mod deciding it is on generation 1 and then acting
on it — the Gen 1 type chart, the **Gen 2** battle bridge (which is what leaves
a white screen after the battle menu), the dex router refusing once a frame.
`UIMain installed successfully for generation 3` in the same log shows the gen 3
path exists and simply wasn't taken.

There was nothing on the mod table to ask. There is now:

```lua
mod.generation    -- 1, 2 or 3
mod.gameVersion   -- "red" | "crystal" | "emerald" | "prism" | "polishedcrystal" | ...
mod.host          -- { generation, version, name, label, engine, modApi, developer }
```

Read once when the api is built — after the version is chosen, before your
entry chunk runs — and handed over as values. The boot log now states it too:

```
[info] mods: host is generation 3 (emerald) -- mod.generation, mod.gameVersion and mod.host carry it
```

# Height on the `gen3WorldFor` descriptor

Your log says `gen3 voxel: using the engine's gen3WorldFor seam`, so this is
the surface you are already wired into. It carried the terrain's elevation and
nothing about the people standing on it — which is the whole bug: `gen3 shapes:
... 6708 tile(s) raised` and nothing to raise the player by.

```lua
world.layerAt(cx, cy)      -- 0/1/2 height ordering, not the level id
world.layerOf(elevation)   -- the same mapping directly
world.elevationLayers      -- how many levels the ranking has
world.mapId, world.widthCells, world.heightCells

world.playerAt()           -- { mapId, x, y, px, py, facing, elevation, layer }
world.actors()             -- the player and every live NPC, same shape
```

`playerAt().elevation` is the level the player is **standing at**, kept sticky
the cartridge's way — read `elevationAt(x, y)` under them instead and someone
walking *under* a bridge pops onto the deck above.

One correction that may matter to you directly: the comment on
`world.elevationAt` shipped with **0 and 15 described the wrong way round** (it
said 15 was "any level" and 0 was the transition cell). It is the other way
about — `0` is "any level", `15` is "under a bridge". If the voxel floor was
built against that comment, that alone would sink it.
