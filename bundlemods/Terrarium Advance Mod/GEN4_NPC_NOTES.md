# Gen 4 NPCs as smooth 3D bodies

Platinum's people are billboards: a flat card showing one of four REAL pictures
(south, north, west, east; nothing is mirrored) plus two step frames per side,
placed in a real 3D world. In a free camera every NPC is a paper cut-out.
`Gen4NpcModels` builds a closed, rounded 3D body out of each walker sheet's own
art and draws it instead of the card.

## Files

- `lib/SpriteSolid.lua`: the geometry. Pure Lua, no LOVE. Four alpha masks in,
  a Voxel3D-ready mesh out (`{x,y,z,u,v,shade,0}` + an index map).
- `lib/Gen4NpcModels.lua`: the engine side: eligibility, per-sheet caching,
  time-sliced builds, turning, drawing, the `G4 NPC 3D` setting.
- `lib/Gen4WorldHost.lua` (4 small edits), `lib/Gen4Bridge.lua` (1 name in
  `invalidateAll`), `main.lua` (require, install, one settings row). See
  `npc3d.diff`. Engine files are not touched.
- `tools/test_spritesolid.lua`, `tools/test_gen4_npcmodels.lua`: run with
  `texlua` from the mod root. `tools/preview_spritesolid.lua` + `.py` render a
  body from 8 angles without LOVE.

## How the shape is made

1. Per pixel row, the front/back masks give the occupied x runs and the
   east/west masks the z runs. Each (x run, z run) pair is one ELLIPSE
   cross-section. A leg 4 px wide from the front and 7 px deep from the side is
   a 4 x 7 ellipse, not a box.
2. Runs pair BY ORDER when both views see the same count (two legs seen as two
   legs in profile), and as a product otherwise. This is what stops a stride
   pose growing four legs.
3. Ellipses become a soft density, stacked into a 3D field, blurred
   (`blur`, 2 passes of [1 2 1]/4 per axis). That rounds the pixel staircase.
4. Naive surface nets extracts the iso-surface (`iso` 0.45); normals are the
   field's gradient, so shading is smooth.
5. Virtual rows under the soles keep the blur from lifting the feet, then
   vertices are clamped to y = 0: the body stands flat on the ground.

Texture: every triangle wears whichever of the four pictures it faces most
(front/back favoured 1.2x). The UV is the planar projection of the vertex into
that picture; vertices are duplicated per picture, so seams are colour changes,
never cracks. The sheet is uploaded once more with colour grown 4 px past each
silhouette (inside its own cell) so the rounder mesh never lands on a
transparent texel, which the shader would discard.

Poses: one body per (sheet, pose): stand, step, step, each from that pose's
four pictures. Which pose shows follows `NPC:pose()` exactly like the sprite
does (`SpriteRenderer.facingFrames`). Bodies turn by the NPC's WORLD facing
(eased at 14 rad/s), not the camera-relative one the flat card uses.

## How it hooks in

- `Gen4WorldHost.wantFieldActor` asks `Npc.wants(e, state)` last.
- `drawFieldActors` calls `Npc.drawPose(pose, ground)` after the existing model
  paths. True means a body was drawn, and the host's existing position skip then
  suppresses the flat sprite. False (not built yet, or any failure) leaves the
  sprite drawing, so nobody vanishes while a body builds.
- `overlay3D` calls `Npc.pump()` once a frame. All building happens there,
  through `Gen4Budget`, in 4 ms slices (a coroutine), never inside the draw.

Who gets one: any entity whose sheet has the importer's `facings` for all four
sides (people AND the Pokemon walkers). Not the player (PlayerModel owns that;
`Npc.includePlayer = true` opts in), not followers/roamers, not fixed-frame
NPCs, not props.

## A bug this exposed, fixed in Gen4WorldHost

`Gen4Ground:freeEntity` skips by POSITION. The "!" / "?" bubble over a trainer
is drawn through the same call at the same position (the only caller that
passes `depthLift`), so the moment a trainer became a 3D body the bubble would
have been skipped with their flat sprite. The skip now requires
`depthLift == nil`. (This also fixes it for any existing 3D actor.)

## Knobs (top of `Gen4NpcModels.lua`, and `Npc.solid` for the mesher)

`PAD`, `MAX_BODIES` (120), `TURN_RATE`, `FILTER` ("nearest" / "linear"),
`includePlayer`, `solid = { ss, blur, iso, minDepth, frontBias, light, ... }`.
`ss = 2` gives 4x the triangles and no visible gain at 32 px cells.
Setting: `G4 NPC 3D` ON/OFF (default ON). Switching it off restores the flat
cards the same frame. Cost: ~2.7-3.2k triangles and ~100 KB per body; 3 bodies
per sheet; capped at 120 cached bodies.

## Tested vs not tested

Tested (`texlua`, no LOVE, no ROM; 96 assertions, and the existing 246 still
pass): mask reading, padding (no bleed between cells), closed surface above the
ground, soles exactly on y = 0, UV equals the stated projection for every
vertex, no vertex on a transparent texel, each side's picture used on its own
flank, no ghost legs in a stride, sliced build == direct build, eligibility,
sheet then body queueing, sprite fallback while building, pose selection, turn
easing, failure handling, eviction, invalidate, and the whole chain through the
REAL `Gen4WorldHost` (body drawn, sprite skipped, "!" bubble still drawn,
setting off restores the sprite). The tests were mutation-checked: breaking the
projection, the sole flattening, the surface, and the emote guard each fails.

NOT verified (I had no LOVE runtime, no ROM, and no real Platinum sheets):
- Everything has only been run on a SYNTHETIC four-sided sheet. How well real
  Platinum art (hats, coats, 1-px details) survives the blur is unseen. If
  thin parts vanish, lower `solid.blur` to 1 or `iso` to 0.40.
- Real timings. Plain Lua builds a body in ~100 ms; LuaJIT is much faster and
  it is sliced to 4 ms anyway, but a phone is unmeasured. Watch the
  `Gen4Budget: burst ... npc` log line.
- Whether `ImageData:getString()` / `Assets.imageData` behave as assumed on your
  LOVE build (a slow `getPixel` fallback exists for non-rgba8 data).
- The sign-of-shade "up" flag on a smooth mesh (it interpolates, so snow tint
  fades over the shoulders instead of stepping). Should look right; unseen.
- Seams: the colour change where front/side pictures meet is a hard edge.

Known limits / not done:
- Only in FREE cameras (third / first person, numeric CAM TILT). The default
  CARTRIDGE rung has no matrix to put a mesh through, same as every other
  Terrarium Gen 4 effect (see GEN4_PORT_NOTES.md "Not done yet" 1).
- Lighting is baked in the BODY's frame (a key light from above/front), not the
  sun's, because Voxel3D has no normal attribute and a turning body would need
  a re-bake. The scene shader's own sun/sky/lamps/fog still apply on top.
- No contact shadow (the engine draws none in free cameras either).
- Battles: `Gen4Battle3D` already removes NPCs from the draw lists.
- This deliberately reverses a Gen 1-3 decision recorded in
  `SpriteBillboards.lua` ("nothing about a sprite is voxelized"). That reasoning
  was about GB art with one front-facing picture; Platinum ships four real
  sides, so a body is reconstructed from art that exists rather than invented.
