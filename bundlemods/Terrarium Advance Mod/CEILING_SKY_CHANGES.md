# Ceiling and Sky Handling Unification

## Problem
The ceiling and sky handling was inconsistent across generations:
- **Forest detection**: Only VIRIDIAN_FOREST was in the canopy list, but many forest maps exist across all generations
- **No rooftop detection**: No systematic way to detect when a map is a rooftop (should have no ceiling, just sky)
- **Cave detection**: Generation-specific - Gen1/Gen2 used tileset IDs, Gen3 used `rock_plateau` profile flag
- **Inconsistent ceiling behavior**: Some generations got forest ceilings, others didn't

## Solution
Implemented a unified system in `lib/DayNight.lua` with three main detection functions:

### 1. Enhanced Forest Detection (`DayNight.isCanopy`)
- **Tileset-based detection**: Checks against `FOREST_TILESETS` for consistent forest identification
- **Map name pattern matching**: Detects forests by name patterns (FOREST, WOODS, GROVE)
- **Backward compatible**: Still honors explicit map IDs in `CANOPY` table

### 2. New Rooftop Detection (`DayNight.isRooftop`)
- **Pattern-based detection**: Identifies rooftops by map name patterns (ROOF, ROOFTOP, DECK, TERRACE)
- **Applied consistently**: Used in ceiling logic to prevent ceilings on rooftops
- **Sky display**: Ensures rooftops show sky instead of ceiling

### 3. Unified Cave Detection (`DayNight.isCave`)
- **Tileset-based detection**: Checks against `CAVE_TILESETS` across all generations
- **Map name pattern matching**: Detects caves by name patterns (CAVE, MT_, TUNNEL, etc.)
- **Gen3 integration**: Respects existing `rock_plateau` profile flag for Gen3
- **Consistent behavior**: Applied in ceiling logic for uniform cave headroom across generations

## Files Modified

### `lib/DayNight.lua`
- Added `FOREST_TILESETS` table with forest tileset IDs
- Added `ROOFTOP_PATTERNS` table with rooftop name patterns
- Added `CAVE_TILESETS` table with cave tileset IDs
- Added `CAVE_PATTERNS` table with cave name patterns
- Enhanced `isCanopy()` function with tileset and pattern detection
- Added `isRooftop()` function for rooftop detection
- Added `isCave()` function for unified cave detection

### `lib/Ceiling.lua`
- Updated `isInterior()` to check for rooftops (no ceiling on rooftops)
- Updated cave detection to use `DayNight.isCave()` for consistency
- Maintains backward compatibility with fallback logic

### `lib/Backdrop.lua`
- Updated `isOutdoor()` to check for rooftops (show sky on rooftops)

### `lib/SkyLayer.lua`
- Updated `isOutdoor()` to check for rooftops (show sky on rooftops)

### `lib/HorizonArt.lua`
- Updated `isOutdoor()` to check for rooftops (show sky on rooftops)

## Expected Behavior

### Forests (All Generations)
- **Before**: Only VIRIDIAN_FOREST had canopy, inconsistent ceiling behavior
- **After**: All forest maps get canopy detection with forest ceiling/sky behavior

### Rooftops (All Generations)
- **Before**: No rooftop detection, inconsistent ceiling behavior
- **After**: Rooftops properly detected, no ceiling, sky displayed

### Caves (All Generations)
- **Before**: Gen1/Gen2 used tileset IDs, Gen3 used `rock_plateau`, inconsistent headroom
- **After**: Unified cave detection, consistent cave ceiling behavior across all generations

## Testing Recommendations

1. **Test Forest Maps**: Visit forest maps in all generations (Gen1 Viridian Forest, Gen2 Ilex Forest, Gen3 Petalburg Woods)
2. **Test Rooftop Maps**: Visit any maps with rooftop names to ensure sky is displayed
3. **Test Cave Maps**: Visit caves in all generations to ensure consistent cave ceiling behavior
4. **Test Regular Interiors**: Ensure normal indoor maps still get proper ceilings
5. **Test Outdoor Maps**: Ensure regular outdoor maps still display sky correctly

## Configuration

The detection patterns can be extended by adding entries to the respective tables in `lib/DayNight.lua`:

```lua
-- Add more forest tilesets
DayNight.FOREST_TILESETS["TilesetNewForest"] = true

-- Add more rooftop patterns
table.insert(DayNight.ROOFTOP_PATTERNS, "BALCONY")

-- Add more cave tilesets
DayNight.CAVE_TILESETS["TilesetNewCave"] = true

-- Add more cave patterns
table.insert(DayNight.CAVE_PATTERNS, "DUNGEON")
```

## Backward Compatibility

All changes maintain backward compatibility:
- Explicit map IDs in `CANOPY` table still honored
- Fallback logic if `DayNight` functions are unavailable
- Existing Gen3 `rock_plateau` detection still respected
- Original tileset detection still used as fallback