"""Does each mod load exactly once?  Scenario runner for tools/mod_double_load_check.

Every scenario is built from scratch under SCRATCH (default
G:/Gen2Recomped/scratch_claude/mod_double/scn): a save directory (APPDATA is
redirected there, so the real one is never touched) and a stand-in game folder
(MODS_ROOT).  The game itself is driven through the real main.lua: launcher ->
Play -> EXIT GAME -> launcher -> Play.  No network: the LOVE side refuses child
processes, sockets and worker threads that fetch.

    python tools/mod_double_load_check/run.py [scenario ...]
        [--version crystal] [--cache G:/Gen2Recomped/crystal]
        [--terrarium-old <zip>] [--terrarium-new <zip>] [--ds <folder>]

--cache is an IMPORTED game folder (it holds rom-cache.complete); it is copied
into each scenario's save directory.  The Terrarium/DS options add scenarios
that run the real third-party mod (untrusted: only ever inside this check).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IDENTITY = "dblcheck"

PROBE_MAIN = r'''
local mod = ...
local R = rawget(_G, "__DBL") or {}
R.inits = R.inits or {}
local lib = mod:read("lib/version.txt") or "?"
local old = mod:read("lib/only_old.txt") and "only_old" or "-"
R.inits[#R.inits + 1] = table.concat({ mod.id, tostring(mod.version), tostring(mod.path), lib, old }, "@")
local boot = #R.inits
local V = require("src.core.Version")
local orig = V.title
V.title = function(...) R.unguarded = (R.unguarded or 0) + 1; return orig(...) end
if not V.__dblFlagWrapped then
  V.__dblFlagWrapped = true
  local o2 = V.title
  V.title = function(...) R.flagged = R.flagged or {}; R.flagged[#R.flagged + 1] = boot; return o2(...) end
end
mod.events:on("mods.loaded", function() R.loadedEvents = (R.loadedEvents or 0) + 1 end)
'''


def manifest(mod_id, version, **extra):
    data = {"id": mod_id, "name": "Probe " + mod_id, "version": version, "api": 2,
            "entry": "main.lua", "permissions": ["engine_internals"]}
    data.update(extra)
    return json.dumps(data)


def write_mod(folder, mod_id, version, only_old=False, **extra):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "manifest.json").write_text(manifest(mod_id, version, **extra))
    (folder / "main.lua").write_text(PROBE_MAIN + "\n-- " + version + "\n")
    (folder / "lib").mkdir(exist_ok=True)
    (folder / "lib" / "version.txt").write_text(version)
    if only_old:
        (folder / "lib" / "only_old.txt").write_text("from " + version)


def write_zip(path, mod_id, version, nested=None, **extra):
    path.parent.mkdir(parents=True, exist_ok=True)
    pre = (nested + "/") if nested else ""
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(pre + "manifest.json", manifest(mod_id, version, **extra))
        z.writestr(pre + "main.lua", PROBE_MAIN + "\n-- " + version + "\n")
        z.writestr(pre + "lib/version.txt", version)


class Scenario:
    def __init__(self, base, name):
        self.dir = base / name
        if self.dir.exists():
            shutil.rmtree(self.dir)
        self.save = self.dir / "appdata" / "LOVE" / IDENTITY
        self.game = self.dir / "game"
        (self.game / "mods").mkdir(parents=True)
        (self.save / "mods").mkdir(parents=True)
        self.env = {}


def results(text):
    out = {}
    for line in text.splitlines():
        if line.startswith("RESULT "):
            parts = line.split(" ", 2)
            key = parts[1]
            val = parts[2] if len(parts) > 2 else ""
            if key in out:
                out[key] = out[key] + " || " + val
            else:
                out[key] = val
    return out


def run(sc, args, rounds=2, extra_env=None):
    cache = Path(args.cache)
    shutil.copytree(cache, sc.save / args.version)
    env = os.environ.copy()
    env.update(ROOT=str(ROOT), MODS_ROOT=str(sc.game), APPDATA=str(sc.dir / "appdata"),
               IDENTITY=IDENTITY, VERSION=args.version, ROUNDS=str(rounds))
    env.update(sc.env)
    env.update(extra_env or {})
    love = os.getenv("LOVE_EXE") or shutil.which("lovec") or "C:/Program Files/LOVE/lovec.exe"
    proc = subprocess.run([love, "tools/mod_double_load_check"], cwd=ROOT, env=env,
                          capture_output=True, text=True, timeout=900, errors="replace")
    (sc.dir / "run.log").write_text(proc.stdout + "\n--- stderr ---\n" + proc.stderr,
                                    errors="replace")
    return results(proc.stdout), proc.stdout


def count_runs(value):
    total = 0
    for part in (value or "").split(","):
        if "=" in part:
            total += int(part.split("=")[1])
    return total


SCENARIOS = []


def scenario(fn):
    SCENARIOS.append(fn)
    return fn


@scenario
def zip_alone(base, args):
    sc = Scenario(base, "zip_alone")
    write_zip(sc.game / "mods" / "probe-1.1.0.zip", "probe", "1.1.0")
    r, _ = run(sc, args, rounds=1)
    return [
        ("zip is not loaded", r.get("round1.game.inits") == "0"),
        ("launcher says the zip is not installed", "not loaded" in r.get("launcher.copies", "")),
    ], r


@scenario
def zip_plus_folder(base, args):
    sc = Scenario(base, "zip_plus_folder")
    write_zip(sc.game / "mods" / "probe-1.1.0.zip", "probe", "1.1.0")
    write_mod(sc.game / "mods" / "probe-1.0.0", "probe", "1.0.0")
    r, _ = run(sc, args, rounds=1)
    return [
        ("one init", r.get("round1.game.inits") == "1"),
        ("the folder copy runs", "probe@1.0.0@mods/probe-1.0.0" in r.get("round1.game.init_list", "")),
        ("launcher says the zip is newer and not loaded", "NEWER" in r.get("launcher.copies", "")),
    ], r


@scenario
def flat_vs_nested_zip(base, args):
    sc = Scenario(base, "flat_vs_nested_zip")
    write_zip(sc.game / "mods" / "flat.zip", "flatmod", "1.0.0")
    write_zip(sc.game / "mods" / "nested.zip", "nestmod", "1.0.0", nested="nestmod-1.0.0")
    r, _ = run(sc, args, rounds=1)
    rep = r.get("launcher.copies", "")
    return [
        ("flat zip manifest read", "flatmod" in rep),
        ("nested zip manifest read", "nestmod" in rep),
        ("neither runs", r.get("round1.game.inits") == "0"),
    ], r


@scenario
def folder_name_differs(base, args):
    sc = Scenario(base, "folder_name_differs")
    write_mod(sc.game / "mods" / "Probe.Mod.1.0.0", "probe", "1.0.0")
    r, _ = run(sc, args, rounds=1)
    return [("one init", r.get("round1.game.inits") == "1"),
            ("no errors", r.get("round1.game.errors") == "0")], r


@scenario
def two_folders_one_id(base, args):
    sc = Scenario(base, "two_folders_one_id")
    write_mod(sc.game / "mods" / "a_probe_old", "probe", "1.0.0")
    write_mod(sc.game / "mods" / "b_probe_new", "probe", "1.1.0")
    r, _ = run(sc, args, rounds=1)
    return [
        ("one init", r.get("round1.game.inits") == "1"),
        ("newest wins", "probe@1.1.0@mods/b_probe_new" in r.get("round1.game.init_list", "")),
        ("older is reported, not an error", "a_probe_old" in r.get("round1.game.ignored", "")
         and r.get("round1.game.errors") == "0"),
    ], r


@scenario
def both_homes_same_folder(base, args):
    sc = Scenario(base, "both_homes_same_folder")
    write_mod(sc.save / "mods" / "probe", "probe", "1.0.0", only_old=True)
    write_mod(sc.game / "mods" / "probe", "probe", "1.1.0")
    r, _ = run(sc, args, rounds=1)
    lst = r.get("round1.game.init_list", "")
    return [
        ("one init", r.get("round1.game.inits") == "1"),
        ("the newer (game folder) copy runs", "probe@1.1.0@" in lst),
        ("its files are its own (no file from the older copy)", "@1.1.0@-" in lst),
        ("the save-dir copy is reported", "1.0.0" in r.get("round1.game.ignored", "")),
    ], r


@scenario
def both_homes_same_folder_save_newer(base, args):
    sc = Scenario(base, "both_homes_same_folder_save_newer")
    write_mod(sc.save / "mods" / "probe", "probe", "1.1.0")
    write_mod(sc.game / "mods" / "probe", "probe", "1.0.0", only_old=True)
    r, _ = run(sc, args, rounds=1)
    lst = r.get("round1.game.init_list", "")
    return [
        ("one init", r.get("round1.game.inits") == "1"),
        ("the newer (save dir) copy runs", "probe@1.1.0@" in lst),
        ("no file leaks in from the older game-folder copy", "@1.1.0@-" in lst),
    ], r


@scenario
def both_homes_other_names(base, args):
    sc = Scenario(base, "both_homes_other_names")
    write_mod(sc.save / "mods" / "probe_installed", "probe", "1.0.0")
    write_mod(sc.game / "mods" / "probe_unzipped", "probe", "1.1.0")
    r, _ = run(sc, args, rounds=1)
    return [("one init", r.get("round1.game.inits") == "1"),
            ("newest wins", "probe@1.1.0" in r.get("round1.game.init_list", ""))], r


@scenario
def custom_data_folder(base, args):
    # a chosen game-data folder: only it (and the game's source) counts, and
    # a stale save-directory copy of the same folder must not hide its copy
    sc = Scenario(base, "custom_data_folder")
    data = sc.dir / "gamedata"
    write_mod(sc.save / "mods" / "probe", "probe", "1.0.0", only_old=True)
    write_mod(sc.save / "mods" / "stranded", "stranded", "1.0.0")
    write_mod(data / "mods" / "probe", "probe", "1.1.0")
    shutil.copytree(Path(args.cache), data / args.version)
    (sc.save / "options.lua").write_text('return { dataDir = %s }' % json.dumps(str(data).replace("\\", "/")))
    sc.env["MODS_ROOT"] = ""
    r, _ = run(sc, args, rounds=1)
    lst = r.get("round1.game.init_list", "")
    return [
        ("one init", r.get("round1.game.inits") == "1"),
        ("the chosen folder's copy runs, alone", "probe@1.1.0@" in lst and "@1.1.0@-" in lst),
        ("a mod only in the save directory stays out", "stranded" not in lst),
    ], r


@scenario
def update_over_older(base, args):
    sc = Scenario(base, "update_over_older")
    write_mod(sc.save / "mods" / "probe", "probe", "1.0.0", only_old=True)
    z = sc.dir / "dl" / "probe-1.1.0.zip"
    write_zip(z, "probe", "1.1.0")
    sc.env["INSTALL"] = str(z)
    r, _ = run(sc, args, rounds=1)
    return [
        ("install is an update, not a copy", "-> true probe 1.1.0" in r.get("install", "")),
        ("one init, new version", r.get("round1.game.inits") == "1"
         and "probe@1.1.0@mods/probe@1.1.0@-" in r.get("round1.game.init_list", "")),
    ], r


@scenario
def same_version_copy_enabled(base, args):
    sc = Scenario(base, "same_version_copy_enabled")
    write_mod(sc.save / "mods" / "probe", "probe", "1.0.0")
    z = sc.dir / "dl" / "probe-1.0.0.zip"
    write_zip(z, "probe", "1.0.0")
    sc.env["INSTALL"] = str(z)
    sc.env["ENABLE"] = "probe-1"
    r, _ = run(sc, args, rounds=1)
    return [
        ("a same-version import is still a separate copy", "-> true probe-1" in r.get("install", "")),
        ("with both on, one runs", r.get("round1.game.inits") == "1"),
        ("the other is superseded", "superseded" in r.get("round1.game.states", "")),
    ], r


@scenario
def renamed_fork_alias(base, args):
    sc = Scenario(base, "renamed_fork_alias")
    write_mod(sc.game / "mods" / "DRAMATIC_SHAPE", "Gen2Recomped-DramaticShapes", "0.7.71")
    z = sc.dir / "dl" / "Fork.Advance.Mod.1.8.7.zip"
    write_zip(z, "DRAMATIC_SHAPE", "1.8.7")
    sc.env["INSTALL"] = str(z)
    r, _ = run(sc, args, rounds=1)
    return [
        ("the fork installs", "-> true DRAMATIC_SHAPE 1.8.7" in r.get("install", "")),
        ("only one of the two voxel mods runs", r.get("round1.game.inits") == "1"),
        ("the newer one", "DRAMATIC_SHAPE@1.8.7" in r.get("round1.game.init_list", "")),
        ("launcher row says which one", "Not loaded" in r.get("launcher.rows", "")),
    ], r


def relaunch_checks(r):
    return [
        ("backdrop/launcher runs no mod code", r.get("round1.launcher.inits") == "0"),
        ("one load per Play", r.get("round2.game.inits") == "2" and count_runs(r.get("round2.game.entry_runs")) == 2),
        ("launcher after EXIT GAME has no mod wraps left", r.get("round2.launcher.unguarded_wraps") == "0"),
        ("second Play: one wrap, not two", r.get("round2.game.unguarded_wraps") == "1"),
        ("second Play: the flag-guarded wrap is the live load's", r.get("round2.game.flagged_wrap_boots") == "2"),
    ]


@scenario
def relaunch_desktop(base, args):
    sc = Scenario(base, "relaunch_desktop")
    write_mod(sc.game / "mods" / "probe", "probe", "1.0.0")
    r, _ = run(sc, args, rounds=2)
    return relaunch_checks(r), r


@scenario
def relaunch_android(base, args):
    sc = Scenario(base, "relaunch_android")
    write_mod(sc.game / "mods" / "probe", "probe", "1.0.0")
    r, _ = run(sc, args, rounds=2, extra_env={"FAKE_OS": "Android"})
    return relaunch_checks(r), r


def terrarium_scenarios(args):
    out = []
    if args.game_mods:
        def installed_mods(base, args):
            # COPIES of a real mods/ folder (and, optionally, of a save
            # directory's mods/), never the folders themselves
            sc = Scenario(base, "installed_mods")
            skip = shutil.ignore_patterns(".git", "*.zip", "tests", "tools")
            for src in Path(args.game_mods).iterdir():
                if (src / "manifest.json").exists():
                    shutil.copytree(src, sc.game / "mods" / src.name, ignore=skip)
            if args.save_mods:
                for src in Path(args.save_mods).iterdir():
                    if src.is_dir():
                        shutil.copytree(src, sc.save / "mods" / src.name, ignore=skip)
            r, _ = run(sc, args, rounds=2)
            runs = r.get("round2.game.entry_runs", "")
            return [
                ("no load errors", r.get("round1.game.errors") == "0" and r.get("round2.game.errors") == "0"),
                ("every mod ran once per Play", all(part.endswith("=2") for part in runs.split(",") if part)),
                ("the same mods loaded both times",
                 r.get("round1.game.loaded") == r.get("round2.game.loaded")),
            ], r
        out.append(installed_mods)
    if args.terrarium_new:
        def terrarium_install(base, args):
            sc = Scenario(base, "terrarium_install")
            if args.ds:
                shutil.copytree(args.ds, sc.game / "mods" / "DRAMATIC_SHAPE",
                                ignore=shutil.ignore_patterns(".git", "*.zip"))
            installs = [args.terrarium_old, args.terrarium_new] if args.terrarium_old else [args.terrarium_new]
            sc.env["INSTALL"] = ";".join(str(p) for p in installs)
            r, _ = run(sc, args, rounds=2)
            runs = r.get("round2.game.entry_runs", "")
            return [
                ("terrarium installs (update over the old one when given)",
                 r.get("install", "").count("-> true DRAMATIC_SHAPE") == len(installs)),
                ("one copy of the voxel mod runs per Play",
                 "DRAMATIC_SHAPE=2" in runs and "Gen2Recomped-DramaticShapes" not in runs),
                ("no registry collision", "already registered" not in r.get("round1.game.error", "")),
            ], r
        out.append(terrarium_install)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("only", nargs="*")
    ap.add_argument("--version", default="crystal")
    ap.add_argument("--cache", default="G:/Gen2Recomped/crystal")
    ap.add_argument("--scratch", default="G:/Gen2Recomped/scratch_claude/mod_double/scn")
    ap.add_argument("--terrarium-old")
    ap.add_argument("--terrarium-new")
    ap.add_argument("--ds")
    ap.add_argument("--game-mods", help="a mods/ folder to copy in as the game folder's")
    ap.add_argument("--save-mods", help="a save directory's mods/ to copy in as well")
    args = ap.parse_args()
    base = Path(args.scratch)
    base.mkdir(parents=True, exist_ok=True)
    total = failed = 0
    for fn in SCENARIOS + terrarium_scenarios(args):
        if args.only and fn.__name__ not in args.only:
            continue
        try:
            checks, r = fn(base, args)
        except Exception as exc:  # noqa: BLE001 -- report and go on
            checks, r = [("ran", False)], {"exception": repr(exc)}
        for label, ok in checks:
            total += 1
            failed += 0 if ok else 1
            print(("ok   " if ok else "FAIL ") + fn.__name__ + ": " + label)
        if not all(ok for _, ok in checks):
            for k in sorted(r):
                print("       " + k + " = " + str(r[k])[:300])
    print("mod double-load check: %d/%d passed" % (total - failed, total))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
