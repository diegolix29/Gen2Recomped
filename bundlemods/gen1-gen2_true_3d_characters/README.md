# Gen1 TRUE 3D Characters v1.1.6 TEST8

## Correct model-forward direction

- Rotates the imported character rigs 180 degrees into Battle Art's yaw space
- Trainers approaching from the north now face south toward the player
- NPCs remain correctly oriented after stopping to begin their dialogue
- Retains TEST7's nested-facing recovery and forward-only calmer gait
- Retains TEST6's unified skin and the complete eye-atlas correction

Disable TEST7 or any earlier version and fully restart before testing.

## Natural movement and trainer-facing correction

- Reads Battle Art 1.10.3's actual NPC direction from `ctx.pose.facing`
- Uses real motion direction as a fallback when a scripted facing is stale
- Stops trainers from facing away while approaching the player for battle
- Advances walking animation by absolute distance, so left/up movement no
  longer plays the 24-frame gait backwards
- Slows the full gait cycle from 32 to 40 world pixels for calmer movement
- Retains TEST6's decisive unified-skin correction and the complete eye fix

Disable TEST6 or any earlier version and fully restart before testing.

## Decisive unified-skin correction

- Replaces incremental skin adjustments with one unified warm palette per NPC
- Face, ears, arms, hands, legs, and feet now use the same base color
- Equalizes baked brightness on skin instead of merely limiting highlights
- Applies identically to neutral models and all 24 walking poses
- Preserves eyes, facial lines, clothing, hair, geometry, scale, and animation
- Nurse Joy and Professor Oak remain unchanged because they already match

Disable TEST5 or any earlier version and fully restart the game before testing.

## Complete generic-NPC skin match

- Corrects the remaining pale/white face, arm, hand, leg, and foot highlights
  across all 19 generic NPC archetypes
- Matches the full skin RGB brightness as well as hue; TEST4 changed hue only
- Constrains washed-out baked skin highlights while retaining gentle 3D shading
- Applies to every neutral mesh and all 24 walking poses per archetype
- Includes the complete TEST1 eye correction and TEST4 palette correction
- Nurse Joy and Professor Oak were checked separately and already match, so
  their custom textures and animation remain unchanged

Disable TEST4 or any earlier version and fully restart the game before testing.

## Roster-wide complexion correction

- Extends the successful adult-woman correction to all 19 generic archetypes
- Uses each model's own warmer ear palette instead of one universal skin color
- Safety caps preserve naturally darker characters and prevent oversaturation
- Changes only washed-out peach pixels in the face and skin atlas regions
- Hair, clothing, eyes, makeup, outlines, geometry, animation, scale, Nurse
  Joy, Professor Oak, player, and Pokemon remain unchanged
- Includes the complete TEST1 eye correction

## Strong complexion match

- TEST2's subtle warming remained too pale under Battle Art's daylight tint
- TEST3 directly matches the `adult_woman` face and exposed body base to her
  existing ear palette
- Other NPCs and all non-skin artwork remain unchanged
- Includes the complete TEST1 eye correction

## Adult-woman complexion correction

- Warms the overly pale face, arms, hands, legs, and feet of the
  `adult_woman` archetype toward her existing ear tone
- Preserves her eyes, lashes, blush, hair, clothing, and darker ear shading
- Includes the complete TEST1 eye-atlas UV correction below

Disable TEST1 or v1.1.5 and fully restart the game before testing TEST2.

## Eye-atlas UV correction

Six imported archetypes use native 512x512 eye sheets while the previous mesh
builder treated every eye sheet as 1024x1024. That doubled their sampled UV
area and could paint multiple blinking-expression rows across the face.

- Corrected `adult_woman`, `cook`, `elderly_woman`, `fat`, `staff_man`, and
  `staff_woman`
- Repaired each neutral mesh and all 24 walking poses
- Left the thirteen already-correct 1024x1024 archetypes unchanged
- Nurse Joy, Professor Oak, player rendering, model scale, and Battle Art's
  provider bridge are unchanged

Disable v1.1.5 and fully restart the game before testing this build.

## v1.1.5 GitHub repository fix

- GitHub repository is corrected in `manifest.json`: `randyadr/Gen-1-3D-NPC-s`
- GitHub Actions publishes Gen1Recomp-compatible release ZIPs automatically
- Release assets use the required name `gen1_true_3d_characters-X.Y.Z.zip`
- Future versions can be detected by Gen1Recomp's Update / Versions system
- Character/model behavior is otherwise unchanged from v1.1.3


## Natural hand rig

This update keeps the corrected forward-bending forearms from v1.1.2 and improves the generic NPC hands. The supplied models already contain individual finger bones, so the hand pose now uses them instead of leaving every hand completely flat.

- all 19 generic NPC archetypes rebuilt
- 24 walking poses per archetype retained
- wrists remain aligned with the corrected forearms
- four fingers use a gentle three-joint curl
- thumbs use a smaller relaxed tuck
- fingers stay relaxed during walking instead of opening/closing dramatically
- shoulder/elbow/leg/foot motion otherwise unchanged
- Nurse Joy custom animation unchanged
- Professor Oak dedicated rig unchanged
- Player unchanged

Disable older standalone character mods and older combined versions while testing this build.
