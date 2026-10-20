"""Build a pinned Windows LÖVE 12 preview, without replacing stable runtimes.

python tools/build_love12_preview.py --artifact-zip <downloaded artifact.zip>
python tools/build_love12_preview.py --download

The upstream CI archive is verified BEFORE any inner runtime file is used.
No executable is downloaded by default. Requires only Python's standard library.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PIN = ROOT / "scripts/love12-runtime.json"


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def included(path: Path) -> bool:
    parts = path.parts
    if any(p in {"generated", ".git", "__pycache__", "node_modules"} for p in parts):
        return False
    if parts[0] == "mods":
        if any(p in {"tests", "tools", "oxr"} or p.startswith(".git") for p in parts[2:]):
            return False
        if path.suffix.lower() == ".zip" or path.name == "CHANGELOG.md" or path.name.endswith("_PLAN.md"):
            return False
    return True


def payload(destination: Path) -> None:
    inputs = [ROOT / p for p in ("main.lua", "conf.lua", "src", "data", "assets",
                                "tools/save-editor", "tools/map-editor")]
    inputs.extend(sorted((ROOT / "tools").glob("rom_manifest*.json")))
    for line in (ROOT / "scripts/bundled_mods.txt").read_text().splitlines():
        name = line.split("#", 1)[0].strip()
        if not name:
            continue
        if len(PurePosixPath(name).parts) != 1 or name in {".", ".."}:
            raise ValueError("Invalid bundled mod name")
        mod = ROOT / "mods" / name
        if not (mod / "manifest.json").is_file():
            raise ValueError(f"Missing bundled mod {name}")
        inputs.append(mod)
    if (ROOT / "cloud_clients.lua").is_file():
        inputs.append(ROOT / "cloud_clients.lua")
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as packed:
        for source in inputs:
            for file in sorted(source.rglob("*")) if source.is_dir() else [source]:
                rel = file.relative_to(ROOT)
                if file.is_file() and included(rel):
                    packed.write(file, rel.as_posix())
        # This is a separate test channel. Never apply a stable Lua payload
        # over the preview's compatibility fixes when its version is checked.
        packed.writestr("love12_preview.lua", "return true\n")
    with zipfile.ZipFile(destination) as packed:
        names = set(packed.namelist())
        assert "main.lua" in names and "src/render/ClipSpaceCompat.lua" in names
        assert "mods/DRAMATIC_SHAPE/lib/GpuQuadSink.lua" in names
        assert len([n for n in names if n.startswith("tools/rom_manifest")]) >= 15
        assert not any("generated" in PurePosixPath(n).parts for n in names)


def build(archive: Path, pin: dict) -> Path:
    if digest(archive) != pin["artifact_sha256"]:
        raise ValueError("Runtime artifact SHA256 differs from the pinned upstream digest")
    # Extract only the portable archive's flat runtime files. Never run the
    # installer also present in the upstream artifact, or reuse 11.5 DLLs.
    with zipfile.ZipFile(archive) as outer:
        members = [n for n in outer.namelist() if PurePosixPath(n).name == pin["portable_member"]]
        if len(members) != 1:
            raise ValueError("Expected exactly one pinned portable runtime zip")
        portable = outer.read(members[0])
    out = ROOT / "dist/love12-preview"
    if out.is_symlink() or not out.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Preview output must stay inside the workspace")
    out.mkdir(parents=True, exist_ok=True)
    runtime_hashes = {}
    with zipfile.ZipFile(io.BytesIO(portable)) as runtime:
        entries = {PurePosixPath(n).name: n for n in runtime.namelist() if not n.endswith("/")}
        if not {"love.exe", "love.dll", "lua51.dll", "SDL3.dll"}.issubset(entries):
            raise ValueError("Pinned runtime is incomplete")
        for name, entry in entries.items():
            if name.endswith(".dll") or name in {"love.exe", "lovec.exe", "license.txt"}:
                data = runtime.read(entry)
                target = out / name
                if target.is_symlink():
                    raise ValueError(f"Refusing symlink output {name}")
                target.write_bytes(data)
                runtime_hashes[name] = hashlib.sha256(data).hexdigest()
    game = out / "game.love"
    payload(game)
    exe = out / "Gen2Recomped-love12-preview.exe"
    with exe.open("wb") as fused, (out / "love.exe").open("rb") as runtime, game.open("rb") as gamefile:
        shutil.copyfileobj(runtime, fused)
        shutil.copyfileobj(gamefile, fused)
    translator = ROOT / "translation/rom-translate.exe"
    if translator.is_file():
        (out / "translation").mkdir(exist_ok=True)
        shutil.copy2(translator, out / "translation" / translator.name)
    (out / "Start-preview.cmd").write_text(
        '@echo off\nsetlocal\nset "POKEPORT_IDENTITY=Gen2Recomp-Love12Preview"\n'
        'set "POKEPORT_NOTIFY_ONLY_UPDATES=1"\n'
        '"%~dp0Gen2Recomped-love12-preview.exe" %*\n', encoding="utf-8")
    (out / "README.txt").write_text(
        "LÖVE 12 development preview; Windows x64 only.\n"
        "Run Start-preview.cmd for a separate save/settings profile. Import a ROM there to play.\n"
        "The stable installation and its saves are not replaced by this package.\n"
        "GPU MESH GENERATION in the mod settings uses compute when supported, otherwise CPU.\n"
        "Source/build details: docs/love12-migration.md\n", encoding="utf-8")
    (out / "build-info.json").write_text(json.dumps({
        "runtime": pin, "runtime_files": runtime_hashes, "game_sha256": digest(game),
        "executable_sha256": digest(exe), "channel": "love12-preview",
    }, indent=2) + "\n", encoding="utf-8")
    package = ROOT / "dist/Gen2Recomped-love12-preview-win64.zip"
    with zipfile.ZipFile(package, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as packed:
        for file in sorted(out.rglob("*")):
            if file.is_file():
                packed.write(file, "love12-preview/" + file.relative_to(out).as_posix())
    return exe


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--artifact-zip", type=Path)
    group.add_argument("--download", action="store_true")
    args = parser.parse_args()
    pin = json.loads(PIN.read_text(encoding="utf-8"))
    archive = args.artifact_zip
    if args.download:
        archive = ROOT / "tmp/love12-runtime-artifact.zip"
        archive.parent.mkdir(exist_ok=True)
        print("Downloading pinned upstream artifact (never latest); checking SHA256")
        urllib.request.urlretrieve(pin["download_url"], archive)
    print(build(archive, pin))


if __name__ == "__main__":
    main()
