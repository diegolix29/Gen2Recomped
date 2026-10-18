# Numbered mod imports

Ordinary ZIP imports, drops, and batch imports keep an existing mod and install subsequent copies with independent IDs: `<id>-1`, `<id>-2`, and so on. Both the folder and its installed `manifest.json` use the numbered ID so the launcher and runtime loader discover every copy. Occupied IDs and directories are skipped; deleted slots may be reused. No existing duplicate folders are automatically modified.

The launcher adds `(copy N)` to the copied mod's display name. New copies start disabled, with separate enable flags. Updating a numbered copy downloads its original mod's release, checks the original manifest ID, and retains the selected copy's ID. Updating, deleting, or rolling back one copy leaves its siblings alone. Explicit replacement imports, including the recovery inbox's existing replacement mode, continue to replace their target.

`install_source_id` in the installed manifest records the upstream ID for numbered-copy updates. The downloaded archive is unchanged; only the installed copy's manifest is rewritten. The existing source-checkout update protection and copy-failure rollback remain in force.

Validation: `python tools/mod_copy_check/run.py` builds tiny synthetic ZIPs, uses a fresh isolated LOVE identity, verifies repeated imports, launcher and loader discovery, independent updates and deletion, wrong-ID update rejection, explicit replacement, free-slot reuse and batch imports (24 checks). It also writes `tmp/mod_copy_check/launcher.png` for visual review. The existing launcher mod tests pass 68/68.
