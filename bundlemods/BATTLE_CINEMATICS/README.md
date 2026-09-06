# Legendary Battle Cinematics Compatibility

**Current pre-release:** v0.7.2 TEST2 for Gen1Recomp 0.2.53 and Legendary Battle Art.

This is a compatibility fork of **Battle Cinematics v0.7.2** by EnterPlayerOne. It preserves the original camera choreography and credits while adapting the input hooks and Battle Art integration for the current Gen1Recomp build.

Cinematic battle-camera companion for Pokémon Gen1 Recomp with support for compatible Dramatic Shape battle-camera backends.

## TEST2: Gen1Recomp 0.2.53 compatibility

This test build preserves the complete v0.7.2 camera choreography and settings,
but ports its input hook to the current Mod API 2 sandbox. Older v0.7.2 builds
attempted to replace global `love.touchpressed` and `love.mousepressed`
callbacks. Gen1Recomp 0.1.87 and later reject those assignments and roll back
the whole mod during loading. TEST2 uses the supported `Game` input methods
instead, including Android touch input on 0.2.53.

The camera integration remains deliberately narrow: Battle Art owns the arena,
actors, HUD, effects, and base camera; Battle Cinematics wraps only
`BattleCam.rig`. This is compatible with the Battle Art Stadium-model provider.

## v0.7.2

This release promotes the successful v0.7.1 multi-backend/preset-configuration test branch into the next development baseline.

### Preset configuration

- Keeps the contextual **Configure Preset** submenu.
- **DW3 Classic** owns its persistent settings:
  - Framing: Standard / Near / Close
  - Orbit Speed: Slowest / Slow / Medium / Fast
  - Height: Low / Standard / High
  - Angle: Shallow / Standard / Strong
  - Reset to Default
- Preset settings continue to persist through Gen1Recomp's normal mod-option storage.

### Multi-backend compatibility

Battle Cinematics can attach to either compatible backend at runtime:

- `DRAMATIC_SHAPE` — upstream Dramatic Shape and same-ID Battle Art replacement builds
- `BATTLE_ART_VOXEL_FORK` — Battle Art voxel fork

The renderer backends remain optional manifest dependencies so either can provide the required camera interface. Battle Cinematics requires at least one compatible backend to be active.

Verified during v0.7.1 testing with:

- Dramatic Shape 1.6.1
- DramaticShape Battle Art 1.6.8 replacement
- BATTLE_ART_VOXEL_FORK 1.7.6

### Expanded Initial Delay

Initial Delay now offers:

- Immediate (0s)
- 2 seconds
- 4 seconds
- Short (6s)
- Standard (9s) — default
- Long (12s)
- Extra Long (15s)

`Immediate` removes the intentional idle wait only after the compatible battle rig is available; it does not bypass Battle Cinematics' normal camera/backend readiness checks.

### Dynamic Intro speed

**Intro Speed** remains directly beneath **Dynamic Intro** on the main Battle Cinematics options page and now offers:

- Slow
- Normal
- Fast — default

Fast preserves the established v0.7.1 intro timing exactly. Normal preserves the previous Normal timing. Slow adds a gentler 0.75× timing level.

### Camera safety

The v0.7.1 safety behavior is retained, including automatic safe alternatives for problematic camera layouts affecting Dynamic Intro, Hero Portrait, and DW3 Classic shoulder compositions.

### Updater metadata

Manifest version is **0.7.2-perf2-compat253** and update checks point to:

`ltzLegend/Legendary-Battle-Cinematics-Compat`

### Original project

Original Battle Cinematics project by EnterPlayerOne:

`EnterPlayerOne/Dynamic-Battle-Cinematics`
