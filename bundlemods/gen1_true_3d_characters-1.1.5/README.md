# Gen1 TRUE 3D Characters v1.1.5
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
