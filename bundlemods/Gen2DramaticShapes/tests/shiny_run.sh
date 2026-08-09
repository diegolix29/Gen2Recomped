#!/usr/bin/env bash
# Shiny encounters, one per outdoor place, one window at a time.
#
#   bash mods/DramaticShapeVoxelMod/tests/shiny_run.sh
#
# Run from the PROJECT ROOT.
#
# Each Pokemon gets its OWN game window, launched only after the previous one
# has been closed -- the loop blocks on the process, so closing the window is
# what advances it. Nothing is on a timer, so a take can be as long as it
# needs to be, and a bad one can just be closed and re-run.
#
# The battles run at true 1x: tests/shiny_one.lua paces itself against the
# wall clock, because a POKEPORT_DRIVER run is otherwise unpaced and goes as
# fast as the machine can manage.
set -u

LOVE=${LOVE:-/c/Program Files/LOVE/lovec.exe}
DRIVER=mods/DramaticShapeVoxelMod/tests/shiny_one.lua

# species | level | map | cell x | cell y | rung
#
# Lapras out on the open sea: ROUTE_20 is the 50-wide water run between
# Fuchsia and Cinnabar, and the middle of it is nothing but water in every
# direction. A species or map this dataset does not have is skipped with a
# line rather than failing the run.
#
# The rung column picks STADIUM A (the fight staged on the map itself) or
# STADIUM B (the two carried discs). Over open water there is no clear GROUND
# to stage on, which is exactly the case B exists for -- see shiny_one.lua.
RUNS=(
  "LAPRAS|40|ROUTE_20|25|4|stadium"
)

OPTS="$APPDATA/LOVE/pokemon-love2d/options.lua"
if [ -f "$OPTS" ]; then
  cp "$OPTS" "$OPTS.shiny_run_backup"
  echo "backed up options.lua"
fi

i=0
for row in "${RUNS[@]}"; do
  i=$((i + 1))
  IFS='|' read -r SPECIES LEVEL MAP CX CY RUNG <<< "$row"
  echo ""
  echo "=== $i/${#RUNS[@]}  $SPECIES  at  $MAP  ==="
  echo "    close the window when you are done recording it"
  DS_SPECIES="$SPECIES" DS_LEVEL="$LEVEL" DS_MAP="$MAP" \
  DS_CX="$CX" DS_CY="$CY" DS_RUNG="${RUNG:-stadium}" \
  POKEPORT_DRIVER="$DRIVER" "$LOVE" .
done

# The game persists the whole options table mid-run (OverworldBattle.forceOG),
# so a run leaves the display settings it used on disk. Put them back.
if [ -f "$OPTS.shiny_run_backup" ]; then
  cp "$OPTS.shiny_run_backup" "$OPTS"
  echo ""
  echo "options.lua restored"
fi

echo "done -- ${#RUNS[@]} encounters"
