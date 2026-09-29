# Window glass metatiles — Pokémon Emerald and FireRed

Every metatile in both cartridges that shows **window glass**, by tileset.
Companion to `src/world/Gen3WindowMetatiles.lua`, which carries the same data
as a lookup table.

## Where this came from

**Neither pret disassembly labels window metatiles.** pokeemerald's
`include/constants/metatile_labels.h` has no `Window` macro at all;
pokefirered's only ones are Silph Co.'s scripted elevator window
(`METATILE_SilphCo_ElevatorWindow_Top0/Mid0/Bottom0` … `0x2E8`, `0x2F0`,
`0x2F8` and neighbours), which is an animation, not a building window. There is
no list in the ROM either — nothing in the metatile attributes, the behaviour
byte or the collision bits distinguishes glass from any other wall.

So this was read off the art. Every metatile of all 136 tilesets in the two
cartridges was composited exactly as the game draws it — both layers,
per-quadrant H/V flips, the pair's own palette banks (6 primary palettes in
Emerald, 7 in FireRed) — rendered at 4× onto labelled contact sheets, and
inspected. Secondary tilesets were paired with a primary they are actually
used with, so their palettes resolve the way the game resolves them.

## What counts

**Included** — a metatile you can see glass in. Windows are normally two or
four cells and panes straddle cell edges, so a cell holding part of a pane
counts even when most of it is wall. Interior windows count as well as
exterior ones.

**Excluded** — frame, sill, shutter and curtain cells with no glass showing;
water of every kind (sea, ponds, puddles, waterfalls, fountains); blue roofs,
floors and carpet; TV and PC screens, the Pokémon Center healing machine's
display, Game Corner machines; signs, banners and framed pictures; ice and
crystal; and glass-fronted furniture — a display case is glass, but it is not
a window.

**Doors are listed separately.** A shop's glass double door is glass and is
not a window, so it sits in its own column and in `M.doors`.

## Checks that were run

- Every id falls inside its own tileset's metatile range. **0 failures.**
- Window glass is drawn from a small set of 8×8 tiles, so any metatile *not*
  on the list that uses a tile appearing **only** in listed windows would be a
  miss. **0 found**, across all 136 tilesets.
- Every id was checked against the shipped blockdata of every map. 953 of the
  1,069 appear on at least one real map; the other 116 are marked ⚠ below and
  listed in `M.unused`. They are real window art in the tileset that no Hoenn
  or Kanto map happens to place — a map editor wants them, a renderer walking
  the shipped world will never meet one.

## Totals

| | Emerald | FireRed | Both |
|---|---:|---:|---:|
| Tilesets examined | 73 | 63 | 136 |
| Tilesets with glass | 33 | 43 | 76 |
| Window metatiles | 570 | 499 | 1069 |
| Glass doors | 66 | 33 | 99 |

Metatile ids are in the pair's numbering: below `metatilesInPrimary`
(512 Emerald, 640 FireRed) they belong to the primary tileset, at or above it
to the secondary. ⚠ marks an id no shipped map places.

## Emerald

### Tilesets with window glass

| Tileset | What it is | Window glass | Glass doors |
|---|---|---|---|
| `TILESET_03DF704` | EMERALD PRIMARY outdoor: grass/trees/cliffs/sea plus Center/Mart/Gym fronts | `0x00B`, `0x013`, `0x1C0`, `0x1C1`, `0x1C2`, `0x1C3`, `0x1C4` | `0x021`, `0x1CD` |
| `TILESET_03DF71C` | small Emerald town exterior | `0x20F`, `0x217`, `0x232`, `0x23A`, `0x262` ⚠, `0x263` ⚠, `0x26A` ⚠, `0x26B` ⚠, `0x27D`, `0x287`, `0x28F` | `0x238`, `0x248` |
| `TILESET_03DF734` | port/market town exterior (Slateport-like) | `0x23A`, `0x242`, `0x258`, `0x25C`, `0x25D`, `0x260`, `0x264`, `0x265` | `0x262` |
| `TILESET_03DF74C` | large coastal city exterior, window-grid buildings | `0x20B`, `0x20C`, `0x20D`, `0x20E`, `0x20F`, `0x211`, `0x212`, `0x213`, `0x214`, `0x215`, `0x216`, `0x217`, `0x218`, `0x21D`, `0x21E`, `0x21F`, `0x226`, `0x234`, `0x235`, `0x237`, `0x290` ⚠, `0x291` ⚠, `0x2A0` ⚠, `0x2A1` ⚠, `0x2A3` ⚠, `0x2A4` ⚠, `0x2AC` ⚠, `0x2B2` ⚠, `0x2B5` ⚠, `0x2B6` ⚠, `0x2CB` ⚠, `0x2CC` ⚠, `0x2CD` ⚠, `0x2D3` ⚠, `0x2D4` ⚠, `0x2D5` ⚠, `0x2E0` ⚠, `0x2E1` ⚠, `0x2E2` ⚠, `0x2E3` ⚠, `0x2E8` ⚠, `0x2E9` ⚠, `0x2EA` ⚠, `0x2EB` ⚠, `0x2F0` ⚠, `0x2F1` ⚠, `0x2F2` ⚠, `0x2F3` ⚠, `0x2F8` ⚠, `0x2F9` ⚠, `0x2FA` ⚠ | `0x2AA`, `0x2FB` |
| `TILESET_03DF764` | Battle Frontier outdoor resort | `0x205`, `0x206` ⚠, `0x207`, `0x20D`, `0x20E`, `0x20F`, `0x225`, `0x226` ⚠, `0x227`, `0x268`, `0x269`, `0x280` ⚠, `0x281` ⚠, `0x282` ⚠, `0x283` ⚠, `0x284` ⚠, `0x2BD`, `0x2BF`, `0x2D1`, `0x2D9` ⚠ | `0x38B`, `0x38C`, `0x393`, `0x394` |
| `TILESET_03DF77C` | large outdoor town/plaza exterior | `0x264` ⚠, `0x265`, `0x26B`, `0x26C`, `0x26D`, `0x26F`, `0x27E`, `0x27F`, `0x286`, `0x287`, `0x2A0`, `0x2A1`, `0x2A2`, `0x2A3`, `0x2A6`, `0x2A7`, `0x2A8`, `0x2A9`, `0x2AA`, `0x2D8`, `0x2D9`, `0x2DC`, `0x2E0`, `0x2E1`, `0x2E4`, `0x330`, `0x332`, `0x333`, `0x338`, `0x33A`, `0x33B`, `0x340`, `0x341`, `0x342`, `0x343`, `0x354`, `0x355`, `0x357`, `0x359`, `0x35B`, `0x360`, `0x361`, `0x362`, `0x363`, `0x364`, `0x365` ⚠, `0x367`, `0x38B`, `0x393`, `0x394`, `0x39B` ⚠, `0x3A0`, `0x3A1`, `0x3A2` ⚠, `0x3A3` ⚠, `0x3A8`, `0x3AA`, `0x3AB`, `0x3AC`, `0x3E7`, `0x3EF`, `0x3FB`, `0x3FC` | `0x289`, `0x2AB`, `0x2AC`, `0x2B8`, `0x315`, `0x31D`, `0x348`, `0x34A`, `0x35D`, `0x3CC`, `0x3CD`, `0x3D4`, `0x3D5` |
| `TILESET_03DF794` | lava/hideout cave with ship rooms; two panes above the counter | `0x239`, `0x23A` | — |
| `TILESET_03DF7AC` | seaside town exterior, green shophouses with cyan window bands | `0x29E`, `0x2A6`, `0x2A8`, `0x2FF`, `0x307` | `0x364`, `0x36C` |
| `TILESET_03DF7C4` | forest/route exterior plus domed building with curved cyan glass walls | `0x2B8`, `0x2B9`, `0x2BA`, `0x2BD`, `0x2BE`, `0x2C5`, `0x2C6`, `0x2C8`, `0x2C9`, `0x2CD`, `0x2CE`, `0x2F0`, `0x2F1`, `0x2F8`, `0x2F9`, `0x300`, `0x301` | `0x2C2` |
| `TILESET_03DF7DC` | coastal city exterior, banked facade windows | `0x20D`, `0x20E`, `0x20F`, `0x215`, `0x216`, `0x217`, `0x225`, `0x226`, `0x22D`, `0x22E`, `0x22F`, `0x235`, `0x236`, `0x237`, `0x23D`, `0x23E`, `0x23F`, `0x243`, `0x244`, `0x247`, `0x24A`, `0x24B`, `0x24C`, `0x24D`, `0x24E` ⚠, `0x252`, `0x253`, `0x254`, `0x255`, `0x256` ⚠, `0x25B`, `0x25C`, `0x25D`, `0x25E`, `0x25F`, `0x265`, `0x266`, `0x267`, `0x271`, `0x272`, `0x2D6`, `0x2D7`, `0x2E6` ⚠, `0x2ED`, `0x2FB`, `0x306`, `0x307`, `0x30B`, `0x30C`, `0x30D`, `0x310`, `0x311` ⚠, `0x324`, `0x326`, `0x32C` ⚠, `0x32D`, `0x32E` ⚠, `0x32F`, `0x333`, `0x335`, `0x336`, `0x337`, `0x344`, `0x345`, `0x34B`, `0x34C`, `0x34E`, `0x34F`, `0x357` ⚠ | `0x246`, `0x249`, `0x2FD` |
| `TILESET_03DF7F4` | seaside/undersea exterior, facility walls with small windows | `0x2DD`, `0x2EC`, `0x2ED`, `0x2EE`, `0x3B8`, `0x3B9`, `0x3BC`, `0x3BD`, `0x3C0`, `0x3C1`, `0x3C4`, `0x3C5` | — |
| `TILESET_03DF80C` | Emerald city building fronts, blue glass storefront and Contest-Hall facade | `0x201`, `0x202`, `0x213`, `0x214`, `0x215`, `0x216`, `0x217`, `0x21B`, `0x21C`, `0x21D`, `0x21E`, `0x21F`, `0x228` | `0x212` |
| `TILESET_03DF83C` | Sootopolis City exterior | `0x23F`, `0x250` ⚠ | `0x20C`, `0x214`, `0x216`, `0x21C`, `0x21E`, `0x224`, `0x22C`, `0x248` |
| `TILESET_03DF854` | Battle Frontier plaza, long blue glazed wall | `0x282`, `0x28A`, `0x294`, `0x29C`, `0x2A4`, `0x2A5`, `0x2AC`, `0x2C0`, `0x2C1`, `0x2C2`, `0x2C3`, `0x2C4`, `0x2C5`, `0x2C6`, `0x2C7`, `0x2C9`, `0x2CA`, `0x2CB`, `0x2CC`, `0x2CD`, `0x2CE`, `0x2CF`, `0x2D0`, `0x2D1`, `0x2D2`, `0x2D6`, `0x2D7`, `0x2D8`, `0x2D9`, `0x2DA`, `0x2DB`, `0x2DD`, `0x2DE`, `0x2DF`, `0x38A`, `0x38C`, `0x38E`, `0x38F`, `0x392`, `0x394`, `0x395`, `0x396`, `0x397`, `0x3A0`, `0x3A1`, `0x3A2`, `0x3A3`, `0x3A4`, `0x3A5` | — |
| `TILESET_03DF86C` | Battle Frontier outdoor, glass-curtain-wall towers | `0x289`, `0x292` ⚠, `0x293` ⚠, `0x294` ⚠, `0x2A1`, `0x2A2`, `0x2A3`, `0x2A4`, `0x2B7`, `0x2BF`, `0x2C5`, `0x2C7`, `0x2CF`, `0x2D3`, `0x2D4`, `0x2D6`, `0x2D8`, `0x2DB`, `0x2DC`, `0x2DE`, `0x2E0`, `0x2E8`, `0x2EB`, `0x2EC`, `0x2EE`, `0x2F0`, `0x2F3`, `0x2F8`, `0x2F9`, `0x2FA`, `0x2FB`, `0x2FD`, `0x2FE`, `0x300`, `0x301`, `0x302`, `0x303`, `0x305`, `0x306`, `0x313`, `0x315`, `0x316`, `0x31E`, `0x348`, `0x34A`, `0x34B`, `0x34E`, `0x34F`, `0x350`, `0x352`, `0x353`, `0x355`, `0x356`, `0x357`, `0x35B`, `0x35D`, `0x36A`, `0x370`, `0x371`, `0x372`, `0x378`, `0x379` ⚠, `0x380`, `0x381`, `0x388` ⚠, `0x389`, `0x38A`, `0x38C`, `0x38D`, `0x38E`, `0x38F`, `0x392`, `0x394`, `0x395`, `0x396`, `0x397`, `0x3AB`, `0x3AC`, `0x3D9` ⚠, `0x3DB` ⚠, `0x3E1` ⚠, `0x3E2` ⚠, `0x3E3` ⚠, `0x3EC` | `0x235`, `0x252`, `0x354`, `0x39B` |
| `TILESET_03DF89C` | Lilycove-style department store interior | `0x232`, `0x23A`, `0x240` ⚠, `0x241`, `0x242`, `0x2A2`, `0x2A3` | `0x219` |
| `TILESET_03DF8E4` | school/lab classroom interior | `0x211`, `0x212`, `0x218`, `0x219`, `0x21A`, `0x21B` ⚠ | — |
| `TILESET_03DF8FC` | indoor shopping arcade with a large multi-pane glazed frontage | `0x254` ⚠, `0x255` ⚠, `0x256` ⚠, `0x257` ⚠, `0x25C`, `0x25D`, `0x25E`, `0x25F`, `0x260`, `0x261`, `0x262` | — |
| `TILESET_03DF944` | passenger-ship interior (S.S. Tidal) | `0x210`, `0x211`, `0x212`, `0x213`, `0x216`, `0x217`, `0x218`, `0x219`, `0x21A`, `0x21B`, `0x21E`, `0x21F`, `0x221`, `0x226`, `0x229`, `0x22E` | — |
| `TILESET_03DF9A4` | interior, pale-blue walls, framed strip of sky behind counters | `0x210`, `0x211`, `0x213`, `0x217`, `0x21C`, `0x23D`, `0x23F` | `0x23E` |
| `TILESET_03DF9BC` | large ship set | `0x2F8`, `0x300`, `0x35A` ⚠, `0x35E` ⚠, `0x35F` ⚠, `0x389`, `0x3B6`, `0x3B7` | — |
| `TILESET_03DF9D4` | pale-green lab / research-centre interior | `0x229`, `0x22C`, `0x22D`, `0x231`, `0x234`, `0x235`, `0x26F`, `0x277` | — |
| `TILESET_03DFA34` | outdoor fairground/market on sand | `0x23D` ⚠ | `0x23F` |
| `TILESET_03DFAF4` | Hoenn house-interior secondary, small two-pane windows | `0x21E`, `0x24A`, `0x25D`, `0x25E` ⚠, `0x2B3` | — |
| `TILESET_03DFB6C` | indoor house/apartment set | `0x20F`, `0x238`, `0x28E`, `0x28F`, `0x2C6`, `0x2C7`, `0x306`, `0x307`, `0x30E`, `0x30F`, `0x339`, `0x33A`, `0x341`, `0x342`, `0x36E`, `0x36F`, `0x3E9` ⚠, `0x3EA` ⚠, `0x3F9` | — |
| `TILESET_03DFB84` | contest-hall / theatre interior with wall windows | `0x206`, `0x207`, `0x209`, `0x20A`, `0x20B`, `0x211`, `0x212`, `0x213`, `0x219`, `0x21A`, `0x21B`, `0x23C`, `0x23D`, `0x23E`, `0x23F` | — |
| `TILESET_03DFBFC` | wood-and-tatami house interior, two 2x2 windows | `0x238`, `0x239`, `0x23B` ⚠, `0x23C` ⚠, `0x240`, `0x241`, `0x243` ⚠, `0x244` ⚠ | — |
| `TILESET_03DFC44` | abandoned-ship interior, intact and shattered portholes | `0x209`, `0x211`, `0x2A8`, `0x2B0`, `0x2B8`, `0x2C0`, `0x2CC`, `0x2CD`, `0x2D4`, `0x2D5` | — |
| `TILESET_03DFC7C` | battle/contest arena interiors plus a glazed corridor | `0x271`, `0x27D`, `0x27E`, `0x27F`, `0x285`, `0x286`, `0x287`, `0x28D`, `0x28E`, `0x28F`, `0x29F` ⚠ | — |
| `TILESET_03DFCC4` | Battle Frontier outdoor plaza | `0x209`, `0x20A`, `0x256`, `0x257` | `0x25E` |
| `TILESET_03DFCDC` | Pokemon Center / Mart interior; front glazing is yellow-tinted with a shine streak | `0x23D`, `0x23E`, `0x23F`, `0x2D5`, `0x2D6`, `0x2D7`, `0x2DD`, `0x2DE`, `0x2DF` | `0x274`, `0x275` |
| `TILESET_03DFDB4` | white marble public-building interior, large sea-view windows | `0x218` ⚠, `0x219` ⚠, `0x253`, `0x254`, `0x255` | — |
| `TILESET_03DFDE4` | indoor hall/lobby, arched and rectangular teal-glass windows | `0x206`, `0x207`, `0x20E`, `0x20F`, `0x21C`, `0x21D`, `0x22D` | — |

### Tilesets with no window glass (40)

- `TILESET_03DF824` — Pacifidlog: reed huts on rafts, no glazing — glass doors: `0x21A`
- `TILESET_03DF884` — EMERALD PRIMARY tile-bank: 8 metatiles, a PC unit and a mat
- `TILESET_03DF8B4` — department-store / mall interior
- `TILESET_03DF8CC` — cave/desert secondary
- `TILESET_03DF92C` — purple-grey cave interior
- `TILESET_03DF95C` — space-centre / submarine interior
- `TILESET_03DF974` — small Japanese-style shop interior; 20E,20F are display cases
- `TILESET_03DF98C` — garden/lounge decor; 214-216 are paintings
- `TILESET_03DF9EC` — mossy green cave/canyon
- `TILESET_03DFA04` — Secret Base decoration set
- `TILESET_03DFA1C` — Secret Base decoration set
- `TILESET_03DFA4C` — Secret Base decoration set
- `TILESET_03DFA64` — Secret Base decoration set
- `TILESET_03DFA7C` — indoor decoration set (Secret Base style)
- `TILESET_03DFA94` — small dark ship/submarine bunk room
- `TILESET_03DFAC4` — contest-hall interior; palette has no cyan glass colour
- `TILESET_03DFADC` — museum/mansion interior, framed paintings — glass doors: `0x206`, `0x26B`
- `TILESET_03DFB0C` — lab/hospital/office interior, no exterior glazing
- `TILESET_03DFB24` — purple crystal cave interior
- `TILESET_03DFB3C` — house-interior furniture set
- `TILESET_03DFB54` — ice/crystal themed interior
- `TILESET_03DFB9C` — ornate cream/pink indoor hall, no glazing
- `TILESET_03DFBB4` — dark hideout/facility interior
- `TILESET_03DFBCC` — ornate indoor hall (Mauville Gym family)
- `TILESET_03DFBE4` — brick-walled indoor room
- `TILESET_03DFC14` — lab/greenhouse interior
- `TILESET_03DFC2C` — decoration/furniture set
- `TILESET_03DFC5C` — EMERALD PRIMARY: two metatiles, Secret Base base layer
- `TILESET_03DFC94` — very large mixed indoor tileset; blue square panels read as wall panelling
- `TILESET_03DFCAC` — ornate red-and-gold arena interior
- `TILESET_03DFCF4` — Contest Hall; blue items are monitor screens
- `TILESET_03DFD0C` — large indoor hall with a green pitch
- `TILESET_03DFD24` — volcanic hideout interior
- `TILESET_03DFD3C` — large cave set; blue items are gems/ice/water
- `TILESET_03DFD54` — interior, tan wood-slat walls with machinery; 218-221 is a screen
- `TILESET_03DFD6C` — indoor water-garden/atrium
- `TILESET_03DFD84` — multi-room facility interior
- `TILESET_03DFD9C` — desert/sand and rocky mountain terrain
- `TILESET_03DFDCC` — indoor battle/contest venue; only glass is the sliding entrance doors — glass doors: `0x252`, `0x254`, `0x255`, `0x257`, `0x25A`, `0x25C`, `0x25D`, `0x25F`, `0x262`, `0x263`, `0x264`, `0x26A`, `0x26B`, `0x26C`
- `TILESET_03DFDFC` — battle-arena interior

## FireRed

### Tilesets with window glass

| Tileset | What it is | Window glass | Glass doors |
|---|---|---|---|
| `TILESET_02D4A94` | FireRed primary outdoor: town/route plus house/Mart/Gym/Center facades | `0x006`, `0x007`, `0x018`, `0x019`, `0x020`, `0x021`, `0x042`, `0x043`, `0x04F` ⚠, `0x057`, `0x058`, `0x059`, `0x05B`, `0x062`, `0x150`, `0x151`, `0x154`, `0x155`, `0x156`, `0x180`, `0x181`, `0x182` ⚠, `0x18B` ⚠, `0x18C` ⚠, `0x197`, `0x19B` ⚠, `0x19C` ⚠, `0x1B5`, `0x1B6`, `0x1B7` | `0x03D`, `0x047`, `0x15B` |
| `TILESET_02D4AAC` | small-town building exteriors, porthole windows | `0x299`, `0x29A`, `0x29B`, `0x2A1`, `0x2A2`, `0x2B0`, `0x2B1`, `0x2B8`, `0x2B9`, `0x2C0`, `0x2C1`, `0x2C2`, `0x2C3`, `0x2C4`, `0x2C5`, `0x2C9`, `0x2CA` ⚠, `0x2CB`, `0x2CC`, `0x2D0`, `0x2D8` | `0x2A3`, `0x2B3`, `0x2B4` |
| `TILESET_02D4AC4` | town exterior: houses, Center/Mart with tall pale-blue windows | `0x29A`, `0x29B`, `0x2A5`, `0x2A6`, `0x2B5`, `0x2B7`, `0x2B8`, `0x2BB`, `0x2BD`, `0x2BF`, `0x2C3`, `0x2C8`, `0x2C9` ⚠, `0x2CA`, `0x2CB`, `0x2D0`, `0x2D1` ⚠, `0x2D2`, `0x2D4`, `0x2D6`, `0x2DC` ⚠, `0x2DE` ⚠ | `0x2C6` |
| `TILESET_02D4ADC` | city exterior, six-pane blue windows | `0x29C`, `0x2A9`, `0x2AD`, `0x2B8`, `0x2B9` | — |
| `TILESET_02D4AF4` | town exterior, cream houses with blue-pane windows | `0x28A`, `0x28B`, `0x28C`, `0x29A`, `0x29B`, `0x29C`, `0x2B6`, `0x2B7`, `0x2BD`, `0x2BE`, `0x2BF`, `0x2C0`, `0x2F4`, `0x2F5`, `0x2F6`, `0x2F7` | — |
| `TILESET_02D4B0C` | pale-green domed civic building exterior | `0x2D4`, `0x2D5`, `0x2DC`, `0x2DD`, `0x2E4`, `0x2E5`, `0x320`, `0x321`, `0x323`, `0x328`, `0x329`, `0x32A`, `0x32B`, `0x330`, `0x331`, `0x332`, `0x333` | `0x322`, `0x325` |
| `TILESET_02D4B24` | Vermilion-style port-town exterior | `0x29E`, `0x2A3`, `0x2A4`, `0x2A5`, `0x2A6`, `0x2AB`, `0x2AC`, `0x2AD`, `0x2AE`, `0x2E2`, `0x2E3`, `0x2F3` ⚠, `0x2F4`, `0x2F9`, `0x2FB`, `0x2FC`, `0x302`, `0x303`, `0x304` ⚠, `0x305` ⚠, `0x30B`, `0x30D`, `0x30E` ⚠, `0x30F` ⚠, `0x31B`, `0x31C` ⚠, `0x31D`, `0x31E`, `0x325` | — |
| `TILESET_02D4B3C` | Celadon-style city exterior | `0x284`, `0x295`, `0x296`, `0x297`, `0x29D`, `0x29E`, `0x29F`, `0x2A1`, `0x2A2`, `0x2A3`, `0x2A4`, `0x2A9`, `0x2AA`, `0x2AB`, `0x2AC`, `0x2B3`, `0x2B4`, `0x2B8`, `0x2BA`, `0x2BB`, `0x2BC`, `0x2C0`, `0x2C2`, `0x2E7`, `0x2E8`, `0x2E9`, `0x2EA`, `0x2EB`, `0x2EC`, `0x2F0`, `0x2F1`, `0x2F2`, `0x2F3`, `0x2F4`, `0x2F8`, `0x2F9`, `0x2FA`, `0x2FB`, `0x2FC`, `0x2FD`, `0x2FE`, `0x2FF`, `0x300`, `0x303`, `0x308`, `0x30B`, `0x310`, `0x311`, `0x312`, `0x313`, `0x314`, `0x315`, `0x316` | `0x294` |
| `TILESET_02D4B54` | city: brick apartment blocks with blue windows | `0x2B2`, `0x2B3`, `0x2B9`, `0x2BA`, `0x2BB`, `0x2D8` ⚠, `0x2D9` ⚠ | `0x2D2` |
| `TILESET_02D4B6C` | wooden-facade set, three-bay windows | `0x28C`, `0x28D`, `0x28E`, `0x294`, `0x295`, `0x296`, `0x29B`, `0x29C`, `0x29D`, `0x2A3`, `0x2A4`, `0x2A5` | — |
| `TILESET_02D4B84` | ruins/resort exterior plus plank lodge wall with blue-glass windows | `0x2F3`, `0x2F4`, `0x2F5`, `0x309`, `0x30B`, `0x30D` | — |
| `TILESET_02D4B9C` | Celadon-style city: dept store, Game Corner, cyan-glass tower | `0x287`, `0x28B`, `0x28C`, `0x28F`, `0x290`, `0x291`, `0x292`, `0x293`, `0x294`, `0x298`, `0x299`, `0x29A`, `0x29B`, `0x29C`, `0x2A0`, `0x2A1`, `0x2A2`, `0x2A3`, `0x2A4`, `0x2A5`, `0x2A6`, `0x2A7`, `0x2AB`, `0x2AC`, `0x2AD`, `0x2AF`, `0x2BB`, `0x2BD`, `0x2BE`, `0x2BF`, `0x2C1`, `0x2C2`, `0x2C3`, `0x2C5`, `0x2C6`, `0x2C7`, `0x2C9`, `0x2CA`, `0x2CB`, `0x2CD`, `0x2CE`, `0x2CF`, `0x2D1`, `0x2D2`, `0x2D5`, `0x2D6`, `0x2D7`, `0x2E6`, `0x2E7`, `0x2EE`, `0x2EF`, `0x305`, `0x336`, `0x337` | `0x284`, `0x2BC` |
| `TILESET_02D4BB4` | FireRed generic building-interior PRIMARY | `0x021`, `0x022`, `0x029`, `0x02A`, `0x036`, `0x037`, `0x098`, `0x0A0`, `0x0B4`, `0x0B5`, `0x114`, `0x115`, `0x118`, `0x120`, `0x160`, `0x161` | — |
| `TILESET_02D4BE4` | building interiors: Center, Mart, dept-store escalators, teal office wing | `0x29C`, `0x29D`, `0x2A4`, `0x2A5`, `0x2DE` | — |
| `TILESET_02D4C2C` | museum exhibit hall interior | `0x2BF`, `0x2C7` | — |
| `TILESET_02D4C5C` | bike-shop / workshop interior | `0x293`, `0x298` | — |
| `TILESET_02D4C8C` | indoor general-purpose set, small windows with flower boxes | `0x29E` ⚠, `0x29F`, `0x301`, `0x302`, `0x312` | — |
| `TILESET_02D4CA4` | pink-brick interior, one grey-framed blue window | `0x290`, `0x291`, `0x292`, `0x29A`, `0x29B`, `0x29C` | — |
| `TILESET_02D4CD4` | very large interior set plus pale building walls with teal windows | `0x2D0` ⚠, `0x2D1` ⚠, `0x2EA`, `0x2EB` ⚠, `0x2F2`, `0x322` ⚠, `0x323` ⚠, `0x32A`, `0x3CA`, `0x3CB`, `0x3D2` | — |
| `TILESET_02D4CEC` | ship/liner interior (S.S. Anne style) | `0x295`, `0x296`, `0x2C4`, `0x2C6`, `0x2C7`, `0x2DB`, `0x2DC`, `0x313`, `0x314` | `0x2A8`, `0x2A9`, `0x2B0`, `0x2B1`, `0x2B8`, `0x2B9`, `0x2C0`, `0x2C1`, `0x2D8`, `0x2D9` |
| `TILESET_02D4D04` | wooden cabin/house interior | `0x283`, `0x284`, `0x285` | — |
| `TILESET_02D4D34` | Pokemon Center interior, one framed blue panel = back-wall window | `0x2A2`, `0x2A3`, `0x2A4` | — |
| `TILESET_02D4D4C` | indoor greenhouse/gym rooms | `0x284`, `0x28C`, `0x2B0`, `0x2B1`, `0x2B2` | — |
| `TILESET_02D4D64` | purple-brick indoor room, one 3x2 blue window | `0x285`, `0x286`, `0x287`, `0x28D`, `0x28E`, `0x28F` | — |
| `TILESET_02D4D7C` | Pokemon Center interior, one blue window pane | `0x2AC`, `0x2AD`, `0x2AE` | — |
| `TILESET_02D4E6C` | Celadon Department Store interior | `0x2F4`, `0x2F5`, `0x2F6`, `0x2FC`, `0x2FD`, `0x2FE`, `0x300`, `0x301`, `0x302`, `0x31F`, `0x327` | — |
| `TILESET_02D4E84` | interior with teal glass curtain walls (dept store / hotel lobby) | `0x298`, `0x299`, `0x2A0`, `0x2A1`, `0x2A8`, `0x2A9`, `0x2B0`, `0x2B1`, `0x2C0`, `0x2C1`, `0x2FE`, `0x2FF`, `0x306`, `0x307` | — |
| `TILESET_02D4EB4` | laboratory/machine-room interior, windows with flower boxes | `0x28D`, `0x2B0`, `0x2B3` | — |
| `TILESET_02D4ECC` | ship interior (S.S. Anne style) | `0x345`, `0x38C`, `0x38D`, `0x390` | `0x2C4`, `0x374`, `0x391` |
| `TILESET_02D4F14` | house interior, curtained windows | `0x2A8`, `0x2A9`, `0x2B0`, `0x2B1`, `0x2C8`, `0x2C9`, `0x2CA`, `0x2CB` | — |
| `TILESET_02D4F2C` | mansion/house interior, one large arched 2x2 window | `0x378`, `0x379`, `0x380`, `0x381` | — |
| `TILESET_02D4F44` | hotel/restaurant interior | `0x2D0` | — |
| `TILESET_02D4F5C` | wooden schoolroom/lodge interior, four-pane window band | `0x28D`, `0x28E`, `0x28F` | — |
| `TILESET_02D4F74` | hotel/inn interior | `0x28A`, `0x28D`, `0x2C5`, `0x2C6`, `0x2DD` ⚠, `0x2DE` ⚠ | — |
| `TILESET_02D4F8C` | office/lab building interior | `0x2C2`, `0x2C3`, `0x2F8`, `0x2F9` | — |
| `TILESET_02D4FA4` | ransacked building interior, one two-pane curtained window | `0x289`, `0x28A` | — |
| `TILESET_02D504C` | Fuchsia-style town exterior, glass-fronted shops | `0x281`, `0x282`, `0x283`, `0x284`, `0x285`, `0x289`, `0x28A`, `0x28B`, `0x28C`, `0x28D`, `0x291`, `0x292`, `0x293`, `0x294`, `0x295`, `0x2AD`, `0x2AE`, `0x2B4`, `0x2B5`, `0x2B6`, `0x2E1`, `0x2E2`, `0x2E4`, `0x2E5` | `0x29B`, `0x2EB` |
| `TILESET_02D5064` | island-town exterior | `0x29B`, `0x29C`, `0x2BA`, `0x2BB`, `0x30E`, `0x30F` | `0x2B9` |
| `TILESET_02D507C` | city exterior, tall blue dept-store block with rows of windows | `0x29B`, `0x29C`, `0x2A1`, `0x2A2`, `0x2A3`, `0x2A4`, `0x2A5`, `0x2A9`, `0x2AA`, `0x2AB`, `0x2AC`, `0x2AD`, `0x2B1`, `0x2B2`, `0x2B3`, `0x2B4`, `0x2B5`, `0x318`, `0x319`, `0x31A`, `0x31B` | `0x369`, `0x36A` |
| `TILESET_02D5094` | Center / dept-store / Silph-style interior | `0x2E3`, `0x2EB`, `0x2EC` ⚠, `0x2ED` | — |
| `TILESET_02D50AC` | harbour / ferry terminal exterior | `0x292` | — |
| `TILESET_02D50C4` | striped-wallpaper interiors with arched glass windows plus teal-walled exterior | `0x341`, `0x342`, `0x343`, `0x344`, `0x349`, `0x34A`, `0x34D`, `0x398`, `0x399`, `0x39A`, `0x3A8`, `0x3A9`, `0x3AA`, `0x3AB`, `0x3AC` ⚠, `0x3B0`, `0x3B1`, `0x3B2`, `0x3B3`, `0x3B4` ⚠, `0x3B8`, `0x3B9`, `0x3BA`, `0x3BB`, `0x3C0`, `0x3C1`, `0x3C2`, `0x3C3`, `0x3C4`, `0x3C6`, `0x3F8`, `0x3FA` | `0x3F9` |
| `TILESET_02D50DC` | stadium/battle-arena interior | `0x2AB`, `0x2AC`, `0x2B3` | — |

### Tilesets with no window glass (20)

- `TILESET_02D4BCC` — shop / Center style interior
- `TILESET_02D4BFC` — rocky cave and desert exterior
- `TILESET_02D4C14` — two blank cream filler metatiles
- `TILESET_02D4C44` — large facility interior, helipad, consoles
- `TILESET_02D4C74` — small house interior extras
- `TILESET_02D4CBC` — Rocket-Hideout style facility interior
- `TILESET_02D4D1C` — blue-tiled swimming pool / bath hall
- `TILESET_02D4D94` — wood-panelled multi-storey interior, sea-view deck — glass doors: `0x281`
- `TILESET_02D4DC4` — park/garden exterior, no buildings
- `TILESET_02D4DF4` — grey rock cave interior
- `TILESET_02D4E0C` — rocky cave/mountain interior
- `TILESET_02D4E24` — ice-cave set
- `TILESET_02D4E54` — rocky mountainside/cave exterior
- `TILESET_02D4E9C` — pale stone hall/shrine interior, no glazing
- `TILESET_02D4EE4` — dark grey/olive facility interior
- `TILESET_02D4EFC` — villain-base / office interior
- `TILESET_02D4FEC` — cave/rock with sand floors and water pools
- `TILESET_02D5004` — outdoor sandy/desert area, no buildings
- `TILESET_02D501C` — snow and ice terrain
- `TILESET_02D5034` — indoor facility, yellow brick walls, colour-coded doors

## Judgement calls left open

Cells where glass could not be told from something else are **not** in the
list. They are recorded here so the calls can be revisited rather than
rediscovered — the recurring hard cases are bathroom mirrors, glass-fronted
cabinets, unlit dark panes, and pale wall panelling that shares the glass
palette.

### Emerald

- `TILESET_03DF704` — 039,059,1C5,1D3 1-2px blue sliver, likely top of glass door
- `TILESET_03DF71C` — 249 narrow teal strip; 250,251,258,259,285 blue slatted band (picket fence)
- `TILESET_03DF734` — 267 blue vertical bars; 299,29A,29B,2A8,2A9,2AA,2AB dark navy arched openings
- `TILESET_03DF74C` — 281,29C,2C2,2CA narrow pale-blue columns (fountain jets?); 2BA,2C4,2C5,2C6 arch panels; 2D0,2D1,2D8,2D9 white panels with pale-blue dots
- `TILESET_03DF764` — 362,363 dark-navy rectangles on the distant ferry
- `TILESET_03DF77C` — 2E9,2EC teal/white panels under the lit gate arch; 2AF,2B7 pale grey dither panel
- `TILESET_03DF7AC` — 2B0,2B3,2B4,300,301,302,308,309,30A pale circles on a boat hull (portholes or rivets)
- `TILESET_03DF7C4` — 2D1 a few glass-coloured pixels in a grass tile
- `TILESET_03DF7DC` — 200,201,204,205,206 frieze band; 2E8,2E9,2EA,2F8,2F9,2FA white-framed patterned panel
- `TILESET_03DF7F4` — 2E4,2E5,2E6 windshield of a machine; 393,394,39B,39C banding on a rocket body
- `TILESET_03DF854` — 2DC corner filler; 38D curtain only; 306 small blue square
- `TILESET_03DF86C` — 2B1,2B2,2BB white panel in wooden frame; 2E3,2E4,2E6,30B,30D,30E thin blue band along wall base
- `TILESET_03DF89C` — 213,21B,27F,320 small framed panes (window or display cabinet)
- `TILESET_03DF8B4` — 264 flat light-blue panel among counters
- `TILESET_03DF8E4` — 20B small dark-framed pale-cyan panel
- `TILESET_03DF944` — 214,215,21C,21D barred porthole or vent; 220,228 tall clear cylinder
- `TILESET_03DF974` — 216,217 green-framed pale-blue panel with a grid
- `TILESET_03DF9A4` — 208,209 flat pale-blue upper wall, may be upper pane
- `TILESET_03DF9BC` — 2DD framed panel (mirror?); 2E5,3EA,3EB glass above a counter
- `TILESET_03DFA34` — 2BD,2BE,2BF,2C5,2C6,2C7,2CD,2CE,2CF free-standing pale-blue framed panel
- `TILESET_03DFA64` — 237,23F gold-framed panel with light-blue and grey bars
- `TILESET_03DFA7C` — 2BD,2BE,2BF,2C5,2C6,2C7 framed pale-blue glass panel (sliding glass door?)
- `TILESET_03DFAF4` — 24C dresser with lavender panes (glass-fronted furniture)
- `TILESET_03DFB3C` — 210,211,26B,26C,273,274 slate-grey panel in pale wood frame
- `TILESET_03DFB6C` — 35B pale-blue panel over a washbasin (mirror?)
- `TILESET_03DFB84` — 20E,20F grey cabinet with blue sparkle panel
- `TILESET_03DFC7C` — 295,29D window head/trim band
- `TILESET_03DFC94` — 20A,20B,20C,20D cyan panels with an etched Poke Ball; 282,2DE,2E6 blue pane above a counter
- `TILESET_03DFCAC` — 220,221,228,229,22A,288,289,28A large pure-white panels in grey frames
- `TILESET_03DFD0C` — 250,256 white lattice panes in a brown frame
- `TILESET_03DFD6C` — 215,21D framed cyan panel in a counter-unit
- `TILESET_03DFD84` — 217,21F dark grey with white diagonal streak; 218,21A tall pale-blue panes in navy wall

### FireRed

- `TILESET_02D4AAC` — 2A8,2A9 dark grey recess above the multi-pane grid
- `TILESET_02D4ADC` — 2AA,2AB,2AC pale blue-grey panel above the store entrance; 2CE vending machine
- `TILESET_02D4AF4` — 2CC white-framed dark panel; 2FC,2FD,2FF,304 flat blue band at wall base
- `TILESET_02D4B0C` — 2CB,2CC,2CD dark navy recesses in the green facade
- `TILESET_02D4B24` — 2DA,2DB market-stall counter panes; 306,307 tiny pale sliver
- `TILESET_02D4B54` — 28E,28F,296,297,338,339 distant background buildings; 2A8,2A9,2AA mullioned facade grid
- `TILESET_02D4B6C` — 297 small grey-framed pane; 2AD blue panel with a catch
- `TILESET_02D4B84` — 313,315 pale panels flanking the door, likely gable/awning
- `TILESET_02D4B9C` — 2B3,2B4,2B5 grey-blue sparkle panel; 343 small green pane; 2F8-2FB blue grid basin
- `TILESET_02D4BB4` — 083,084 white-panelled grid; 0B8,0C0 framed blue/white panel; 183 uniform pale-blue filler
- `TILESET_02D4BCC` — 287,28F,2B0,2B1,2B2,2C0,2C1,2C2 display-cabinet glass fronts
- `TILESET_02D4C2C` — 2F9,2FA,2FB,2FC glass display case (furniture)
- `TILESET_02D4C74` — 281,28E two pale-blue panes over a counter (cupboard or window)
- `TILESET_02D4CD4` — 2F3,32B,3D3 small teal patch beside the window wall
- `TILESET_02D4CEC` — 281-284,289-28C wall-wide sea-and-island scene; 2BC,2BD,2BE display-case glass
- `TILESET_02D4D1C` — 2C8,2C9,2CA grey-framed blue rectangle on tiled wall
- `TILESET_02D4D94` — 282,2D4,2F2,33A,33B,39B round ring-framed wall fixture
- `TILESET_02D4ECC` — 343,344 white-rimmed oval, porthole or bathtub
- `TILESET_02D4F44` — 2C6,2C7 furniture glass; 288,29F hung pictures
- `TILESET_02D4F74` — 318,319,31A,320,321 likely mirrors; 2DC probably a bath/sink
- `TILESET_02D5034` — 2A0-2AB,2B0,2B1,2B2,2C8-2CB,2D0,2D1,2D8-2DB large flat pale-teal framed panels; 285,295,29D colour-coded plaques
- `TILESET_02D507C` — 2A0,2A6,2A8,2AE,2B0,2B6 tall pale-blue strips with foliage
- `TILESET_02D5094` — 31C,31E,31F pale blue with white sweeps, probably carpet
- `TILESET_02D50AC` — 2C0,2C1,2C2 unglazed window or ticket hatch; 2C3,2C5,2CB,2CD near-white framed panels
- `TILESET_02D50C4` — 2D4,2D5,2D9,2DA,2F4,2F5,2F9,2FA white-framed wall square, reads as a picture frame
- `TILESET_02D50DC` — 292-297,2A8,2AA periwinkle upper-wall band with white blocks

