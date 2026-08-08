# Pokemon Stadium Overworld Models v0.1.50

A Gen1Recomp companion mod for Dramatic Shape that replaces identified overworld Pokemon with Pokemon Stadium 3D models and extends the 3D presentation into battles.

No Pokemon Stadium ROM, extracted model files, or Nintendo assets are distributed with this repository. Stadium data is imported locally from the user's own compatible ROM through Dramatic Shape / the mod's ROM picker.

## v0.1.52

- Fixed the primary follower getting stuck visually as Pikachu after party reordering.
- The primary behind-the-player follower now resolves directly from live party slot #1 before any Followers EX cached species metadata.
- Additional Followers EX followers still keep their own assigned party species.
- Keeps the Charizard and Mankey locomotion changes from v0.1.50/v0.1.51.


## Features

- Pokemon Stadium 3D models for identified overworld Pokemon
- Lead-party and Followers EX compatibility, including configurable follower count
- Ground locomotion / waddles for non-Flying species
- Curated overworld scaling for tiny and very large Pokemon
- Stadium battle model integration and procedural 2D/3D battle effects
- 3D wind funnels and branching electrical effects
- Android Stadium ROM file picker
- Dramatic Sky Ride compatibility
- Water reflection and 3D shadow integration where supported by Dramatic Shape

## Requirements

- Gen1Recomp compatible with the manifest range
- Dramatic Shape (`DRAMATIC_SHAPE`)
- A user-supplied compatible Pokemon Stadium ROM for local model import

Optional integrations include Followers EX and Dramatic Sky Ride.

## Install

Download the release asset named `STADIUM_OVERWORLD_MODELS-X.Y.Z.zip`, then import it from Gen1Recomp's **MODS > Import mod .zip** screen.

Do not extract or bundle a Stadium ROM with this mod.

## Automatic updates

This mod declares:

```json
"github": "randyadr/3D-Pokemon-Sprites"
```

Gen1Recomp can use GitHub Releases from this repository for **Update / Versions**. Release assets are generated automatically with the mod files at the ZIP root.

## v0.1.50

- Smooths Charizard's stand-to-walk transition instead of snapping directly into the gait loop.
- Charizard now plays the authored `idle_alt` lead-in frames once as in-between poses before entering `loopStart`.
- Uses a smoothstep time curve across the transition so the pose velocity eases in and meets the looping walk cleanly.
- Slows Charizard's procedural bob/pitch blend-in and blend-out for a heavier, less abrupt body transition.
- Adds `charizardWalkUseIntro` and `charizardWalkTransitionSeconds` tuning options; the default transition is 0.34 seconds.

## v0.1.49

- Fixes overworld Stadium locomotion that could make some Pokemon look like their in-place animation was running in fast-forward.
- The skeletal walk loop now advances from actual distance travelled at a bounded, near-authored rate instead of squeezing a full standby loop into every short footfall cycle.
- Starts locomotion at each clip's `loopStart`, avoiding repeated standby-intro twitches when a follower starts and stops.
- Enables grounded overworld locomotion for Charizard with slower, heavier gait tuning while leaving the rest of the Flying-type exclusion list unchanged.
- Adds `walkClipWorldSpeed` and `walkClipMaxRate` tuning knobs for future movement-mod compatibility.

## v0.1.48

- Fixes the Electric battle-effect glitch that could draw a huge diagonal yellow line across Dramatic Shape's 3D arena.
- When Phase 5 world-space effects are active, Electric moves now use only the 3D lightning pass plus Gen1Recomp's normal move animation instead of stacking the old flat Phase 2 bolt on top.
- ThunderShock, Thunderbolt, Thunder Wave, Thunder, and generic Electric attacks keep their 3D electrical effects.
- No changes to Stadium Pokemon model rendering, overworld followers, scaling, or Sky Ride compatibility.

## v0.1.47

- Adds GitHub repository metadata required by Gen1Recomp's updater.
- Adds the standard automatic GitHub Release workflow.
- Keeps the v0.1.46 gameplay/rendering behavior unchanged.


### 0.1.51
- Mankey now uses a dedicated Stadium locomotion animation instead of the near-static generic standby, slowed and tuned into a brisk walking gait.
