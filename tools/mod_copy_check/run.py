"""Isolated native mod-copy regression check and launcher screenshot (no ROMs)."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid
import zipfile

root = Path(__file__).resolve().parents[2]
fixtures = root / "tmp/mod_copy_check"
fixtures.mkdir(parents=True, exist_ok=True)
for name, version in [("original", "1.0.0"), ("updated", "2.0.0"), ("wrong", "2.0.0")]:
    with zipfile.ZipFile(fixtures / (name + ".zip"), "w") as archive:
        archive.writestr("manifest.json", json.dumps({
            "id": "another_mod" if name == "wrong" else "test_dramatic_shapes",
            "name": "Dramatic Shapes test fixture", "version": version,
            "entry": "main.lua", "api": 1, "category": "graphics",
        }))
        archive.writestr("main.lua", "return function(api) end")
        archive.writestr("marker.txt", name)
env = os.environ.copy()
env.update(ROOT=str(root), IDENTITY="Gen2ModCopyCheck-" + uuid.uuid4().hex,
           OUT=str(fixtures / "launcher.png"))
love = os.getenv("LOVE_EXE") or shutil.which("lovec") or shutil.which("love")
if not love and os.name == "nt":
    love = "C:/Program Files/LOVE/lovec.exe"
if not love:
    raise SystemExit("Set LOVE_EXE to the LOVE executable")
result = subprocess.run([love, "tools/mod_copy_check"], cwd=root, env=env,
                        capture_output=True, text=True, timeout=45)
print(result.stdout)
if result.returncode:
    print(result.stderr)
raise SystemExit(result.returncode)
