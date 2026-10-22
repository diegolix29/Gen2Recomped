#!/usr/bin/env python3
"""Convert Reloded / KIM HD Pokémon GIFs into Terrarium sprite sheets + Lua metadata.

Expected input names:
  <dex>-front-n.gif, <dex>-front-s.gif, <dex>-back-n.gif, <dex>-back-s.gif
Optional gender suffixes: ...-m.gif / ...-f.gif
Optional form suffix (Mega, Primal, ...): <dex>-front-n-mega.gif, <dex>-front-s-megax.gif
  (lowercase letters/digits only; this is the same key HDPokemonSheets.monForm() derives at runtime)

Default National Dex range is 1-721 (Gen 1-6, the full set this tool supports). Sheets are written under
assets/battle/hd-pokemon/; metadata is data/hd_pokemon.lua (dex-keyed).
"""
from __future__ import annotations

import argparse
import concurrent.futures
import io
import math
import os
import re
import shutil
import sys
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image
import threading

DEX_MAX_LIMIT = 721     # highest National Dex number the tool will accept (Gen 1-6)
DEX_MAX_DEFAULT = DEX_MAX_LIMIT
PROGRESS_LOCK = threading.Lock()
PROGRESS_PATH: Path | None = None
_LAST_PROGRESS = 0.0


def write_progress(state: str, current: int, total: int, message: str = "", force: bool = False) -> None:
    """Update the in-game bar. Never os.replace: LOVE may have the file open on
    Windows, and replace then raises WinError 5 and aborts the convert."""
    global _LAST_PROGRESS
    if PROGRESS_PATH is None:
        return
    now = time.monotonic()
    if not force and state == "converting" and (now - _LAST_PROGRESS) < 0.20:
        return
    _LAST_PROGRESS = now
    safe_message = message.encode('ascii', 'replace').decode('ascii')
    text = f"{state}\n{int(current)}\n{int(total)}\n{safe_message}\n"
    with PROGRESS_LOCK:
        last_error = None
        for _ in range(12):
            try:
                with open(PROGRESS_PATH, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(text)
                    fh.flush()
                    try:
                        os.fsync(fh.fileno())
                    except OSError:
                        pass
                return
            except OSError as err:
                last_error = err
                time.sleep(0.05)
        if last_error and force:
            raise last_error
NAME_RE = re.compile(
    r"^(?P<dex>\d+)-(?P<side>front|back)-(?P<color>[ns])(?:-(?P<tail>[a-z][a-z0-9]*))?\.gif$",
    re.IGNORECASE,
)


def parse_variant(tail: str | None) -> str:
    """'' -> default, f/m -> gender, anything else is a form key (mega, megax, primal...)."""
    t = (tail or "").lower()
    if not t:
        return "default"
    if t == "f":
        return "female"
    if t == "m":
        return "male"
    return t


def variant_suffix(variant: str) -> str:
    if variant == "default":
        return ""
    if variant == "male":
        return "-m"
    if variant == "female":
        return "-f"
    return "-" + variant


EXTRA_ASSET_SUBDIR = Path("assets") / "hd-pokemon"          # where HDPokemonSheets looks in the mod
EXTRA_META_REL = Path("data") / "hd_sheet_meta_extra.lua"   # merged by HDPokemonSheets.loadMeta()
FIT_HEIGHT = {"front": 186, "back": 246}                    # every existing HD sheet frame height


def effective_scale(data: bytes, side: str, scale: float, fit_height: bool) -> float:
    """--fit-height: scale each GIF so its frame height equals the existing sheets' (186 front / 246 back)."""
    if not fit_height:
        return scale
    with Image.open(io.BytesIO(data)) as im:
        return FIT_HEIGHT[side] / float(im.size[1])


@dataclass(frozen=True)
class SourceGif:
    source: Path
    member: str | None
    name: str

    def read_bytes(self) -> bytes:
        if self.member is None:
            return self.source.read_bytes()
        with zipfile.ZipFile(self.source) as zf:
            return zf.read(self.member)


def iter_source(path: Path) -> Iterable[SourceGif]:
    if path.is_dir():
        for p in sorted(path.rglob("*.gif")):
            yield SourceGif(p, None, p.name)
        return
    if path.is_file() and path.suffix.lower() == ".gif":
        yield SourceGif(path, None, path.name)
        return
    if not path.is_file() or not zipfile.is_zipfile(path):
        raise ValueError(f"Not a GIF folder or ZIP archive: {path}")
    with zipfile.ZipFile(path) as zf:
        for member in sorted(zf.namelist()):
            if member.lower().endswith(".gif"):
                yield SourceGif(path, member, Path(member).name)


def choose_grid(frame_count: int, width: int, height: int, max_texture: int) -> tuple[int, int]:
    max_cols = min(frame_count, max_texture // width)
    max_rows = max_texture // height
    if max_cols < 1 or max_rows < 1:
        raise ValueError(
            f"single frame {width}x{height} exceeds max texture size {max_texture}"
        )
    min_cols = max(1, math.ceil(frame_count / max_rows))
    if min_cols > max_cols:
        raise ValueError(
            f"{frame_count} frames of {width}x{height} cannot fit inside {max_texture}x{max_texture}"
        )
    best = None
    for cols in range(min_cols, max_cols + 1):
        rows = math.ceil(frame_count / cols)
        sw, sh = cols * width, rows * height
        if sw > max_texture or sh > max_texture:
            continue
        score = (max(sw, sh), abs(sw - sh), sw * sh, cols)
        if best is None or score < best[0]:
            best = (score, cols, rows)
    if best is None:
        raise ValueError("no valid sprite-sheet grid found")
    return best[1], best[2]


def display_scale(side: str) -> float:
    return 0.315 if side == "back" else 0.33


def gif_to_sheet(data: bytes, out_path: Path, max_texture: int, scale: float, compress_level: int) -> dict:
    im = Image.open(io.BytesIO(data))
    frames = int(getattr(im, "n_frames", 1) or 1)
    source_width, source_height = im.size
    width = max(1, int(round(source_width * scale)))
    height = max(1, int(round(source_height * scale)))
    cols, _rows = choose_grid(frames, width, height, max_texture)
    sheet = Image.new("RGBA", (cols * width, math.ceil(frames / cols) * height), (0, 0, 0, 0))
    durations: list[int] = []
    for i in range(frames):
        im.seek(i)
        frame = im.convert("RGBA")
        if frame.size != (width, height):
            frame = frame.resize((width, height), Image.Resampling.LANCZOS)
        x = (i % cols) * width
        y = (i // cols) * height
        sheet.alpha_composite(frame, (x, y))
        durations.append(max(1, int(im.info.get("duration") or 50)))
    sheet = sheet.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path, format="PNG", optimize=False, compress_level=compress_level)
    return {"width": width, "height": height, "columns": cols, "frames": frames, "durations": durations}


def gif_metadata(data: bytes, image_path: str, max_texture: int, scale: float) -> dict:
    im = Image.open(io.BytesIO(data))
    frame_count = int(getattr(im, "n_frames", 1) or 1)
    source_w, source_h = im.size
    w = max(1, int(round(source_w * scale)))
    h = max(1, int(round(source_h * scale)))
    cols, _ = choose_grid(frame_count, w, h, max_texture)
    durations = []
    for i in range(frame_count):
        im.seek(i)
        durations.append(max(1, int(im.info.get("duration") or 50)))
    return {
        "width": w, "height": h, "columns": cols, "frames": frame_count,
        "durations": durations, "image": image_path,
    }


def output_png_is_valid(path: Path) -> bool:
    if not path.is_file() or path.stat().st_size <= 0:
        return False
    try:
        with Image.open(path) as im:
            im.verify()
        return True
    except Exception:
        return False


def lua_record(image: str, meta: dict) -> str:
    durations = ",".join(str(v) for v in meta["durations"])
    return (
        "{ image = %r, width = %d, height = %d, columns = %d, frames = %d, durations = {%s}, displayScale = %.6f }"
        % (
            image,
            meta["width"],
            meta["height"],
            meta["columns"],
            meta["frames"],
            durations,
            float(meta.get("displayScale", 1.0)),
        )
    ).replace("'", '"')


def write_metadata(path: Path, records: dict[int, dict]) -> None:
    lines = [
        "-- Generated by tools/import_hd_pokemon.py. Do not hand-edit.",
        "-- National Dex HD front/back sheets (normal + shiny).",
        "return {",
    ]
    for dex in sorted(records):
        species = records[dex]
        lines.append(f"  [{dex}] = {{")
        lines.append(f"    dex = {dex},")
        for side in ("front", "back"):
            side_rec = species.get(side)
            if not side_rec:
                continue
            lines.append(f"    {side} = {{")
            for color_name in ("normal", "shiny"):
                color_rec = side_rec.get(color_name)
                if not color_rec:
                    continue
                lines.append(f"      {color_name} = {{")
                base_keys = [k for k in ("default", "male", "female") if k in color_rec]
                form_keys = sorted(k for k in color_rec if k not in ("default", "male", "female"))
                for gender in base_keys + form_keys:
                    rec = color_rec.get(gender)
                    if rec:
                        key = gender if gender in ("default", "male", "female") else '["%s"]' % gender
                        lines.append(f"        {key} = {lua_record(rec['image'], rec)},")
                lines.append("      },")
            lines.append("    },")
        lines.append("  },")
    lines.append("}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


EXTRA_ROW_RE = re.compile(
    r'^\s*\["(?P<stem>[0-9]{3}[a-z0-9\-]*)"\]\s*=\s*\{(?P<body>[^}]*)\},?\s*$'
)


def read_extra_meta(path: Path) -> dict:
    """Parse our own previous output so repeated --extra runs accumulate instead of overwriting."""
    out: dict = {"front": {"normal": {}, "shiny": {}}, "back": {"normal": {}, "shiny": {}}}
    if not path.is_file():
        return out
    facing = color = None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s{2}(front|back) = \{", line)
        if m:
            facing = m.group(1)
            continue
        m = re.match(r"^\s{4}(normal|shiny) = \{", line)
        if m:
            color = m.group(1)
            continue
        m = EXTRA_ROW_RE.match(line)
        if m and facing and color:
            out[facing][color][m.group("stem")] = m.group("body").strip()
    return out


def write_extra_meta(path: Path, records: dict[int, dict]) -> int:
    """data/hd_sheet_meta_extra.lua in the exact row format HDPokemonSheets.loadMeta() reads:
    ["NNN-stem"] = {width, height, columns, frames, scale, frame_ms}. Merges with an existing file."""
    table = read_extra_meta(path)
    for dex, species in records.items():
        for side, side_rec in species.items():
            for color, color_rec in side_rec.items():
                for variant, rec in color_rec.items():
                    stem = f"{dex:03d}{variant_suffix(variant)}"
                    ds = rec.get("durations") or [50]
                    frame_ms = max(1, int(round(sum(ds) / len(ds))))
                    table[side][color][stem] = "%d, %d, %d, %d, %.6f, %d" % (
                        rec["width"], rec["height"], rec["columns"], rec["frames"],
                        float(rec.get("displayScale", 1.0)), frame_ms)
    lines = [
        "-- Generated by tools/import_hd_pokemon.py --extra. Sheets live in assets/hd-pokemon/.",
        "-- Same format as data/hd_sheet_meta.lua: {width, height, columns, frames, scale, frame_ms}",
        "-- Gen 6 (650-721), species the HD pack is missing, Mega / Primal forms.",
        "return {",
    ]
    rows = 0
    for facing in ("front", "back"):
        lines.append(f"  {facing} = {{")
        for color in ("normal", "shiny"):
            lines.append(f"    {color} = {{")
            for stem in sorted(table[facing][color]):
                lines.append(f'      ["{stem}"] = {{{table[facing][color][stem]}}},')
                rows += 1
            lines.append("    },")
        lines.append("  },")
    lines.append("}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return rows


def write_file_list(path: Path, records: dict[int, dict], metadata_only: bool) -> None:
    names = ["data/hd_pokemon.lua"]
    if not metadata_only:
        for species in records.values():
            for side_rec in species.values():
                if not isinstance(side_rec, dict):
                    continue
                for color_rec in side_rec.values():
                    if not isinstance(color_rec, dict):
                        continue
                    for rec in color_rec.values():
                        image = rec.get("image") if isinstance(rec, dict) else None
                        if image:
                            names.append(str(image).replace("\\", "/"))
    unique = list(dict.fromkeys(names))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(unique) + "\n", encoding="utf-8")


def _convert_job(job, max_texture, scale, compress_level, fit_height=False):
    dex, side, color, gender, item, out, rel = job
    data = item.read_bytes()
    scale = effective_scale(data, side, scale, fit_height)
    meta = gif_to_sheet(data, out, max_texture, scale, compress_level)
    meta["image"] = rel.as_posix()
    meta["displayScale"] = display_scale(side)
    return dex, side, color, gender, item.name, meta


def main() -> int:
    ap = argparse.ArgumentParser(description=f"Convert HD Pokémon GIFs for Terrarium (dex 1-{DEX_MAX_LIMIT}).")
    ap.add_argument("sources", nargs="+", type=Path, help="GIF folders or ZIP archives")
    ap.add_argument("--target", type=Path, default=Path(__file__).resolve().parents[1],
                    help="Terrarium Advance Mod folder (ignored when --out is set)")
    ap.add_argument("--out", type=Path, default=None,
                    help="Write sheets and data/hd_pokemon.lua here instead of --target")
    ap.add_argument("--progress-file", type=Path, default=None,
                    help="Write CONVERTING/DONE/FAIL progress for the in-game import screen")
    ap.add_argument("--clean", action="store_true")
    ap.add_argument("--max-dex", type=int, default=DEX_MAX_DEFAULT)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--metadata-only", action="store_true")
    ap.add_argument("--max-texture", type=int, default=8192)
    ap.add_argument("--scale", type=float, default=0.60)
    ap.add_argument("--fit-height", action="store_true",
                    help="ignore --scale and size every GIF to the existing sheets' frame height "
                         "(front 186 px, back 246 px) so new art matches the installed pack")
    ap.add_argument("--extra", action="store_true",
                    help="ADD to an installed pack: write sheets to assets/hd-pokemon/ and the geometry to "
                         "data/hd_sheet_meta_extra.lua (merged with any earlier --extra run). Leaves "
                         "data/hd_pokemon.lua and files.txt untouched.")
    ap.add_argument("--workers", type=int, default=min(8, os.cpu_count() or 1))
    ap.add_argument("--compress-level", type=int, choices=range(0, 10), default=6, metavar="0-9")
    args = ap.parse_args()
    global PROGRESS_PATH
    if args.progress_file is not None:
        PROGRESS_PATH = args.progress_file.resolve()
        PROGRESS_PATH.parent.mkdir(parents=True, exist_ok=True)
        write_progress("converting", 0, 1, "STARTING")
    if not (0.10 <= args.scale <= 1.00) and not args.fit_height:
        ap.error("--scale must be between 0.10 and 1.00")
    if not (1 <= args.max_dex <= DEX_MAX_LIMIT):
        ap.error(f"--max-dex must be between 1 and {DEX_MAX_LIMIT}")

    try:
        if args.out is not None:
            dest = args.out.resolve()
            dest.mkdir(parents=True, exist_ok=True)
        else:
            dest = args.target.resolve()
            if not (dest / "manifest.json").is_file():
                ap.error(f"target does not look like a Terrarium mod folder: {dest}")

        asset_subdir = EXTRA_ASSET_SUBDIR if args.extra else Path("assets") / "battle" / "hd-pokemon"
        asset_root = dest / asset_subdir
        metadata_path = dest / "data" / "hd_pokemon.lua"
        if args.clean and args.extra:
            ap.error("--clean and --extra do not combine (--extra only ever adds)")
        if args.clean:
            shutil.rmtree(asset_root, ignore_errors=True)
            try:
                metadata_path.unlink()
            except FileNotFoundError:
                pass

        found = {}
        write_progress("converting", 0, 1, "SCANNING")
        for source_path in args.sources:
            for item in iter_source(source_path.resolve()):
                m = NAME_RE.match(item.name)
                if not m:
                    continue
                dex = int(m.group("dex"))
                if not (1 <= dex <= args.max_dex):
                    continue
                side = m.group("side").lower()
                color = "normal" if m.group("color").lower() == "n" else "shiny"
                gender = parse_variant(m.group("tail"))
                key = (dex, side, color, gender)
                if key in found:
                    raise RuntimeError(f"duplicate asset for {key}: {found[key].name} and {item.name}")
                found[key] = item

        if not found:
            raise RuntimeError("no matching HD Pokemon GIFs found")

        records: dict[int, dict] = {}
        total = len(found)
        write_progress("converting", 0, total, "CONVERTING")
        if args.metadata_only:
            for index, ((dex, side, color, gender), item) in enumerate(sorted(found.items()), 1):
                rel = asset_subdir / side / color / f"{dex:03d}{variant_suffix(gender)}.png"
                data = item.read_bytes()
                meta = gif_metadata(data, rel.as_posix(), args.max_texture,
                                    effective_scale(data, side, args.scale, args.fit_height))
                meta["displayScale"] = display_scale(side)
                species = records.setdefault(dex, {})
                species.setdefault(side, {}).setdefault(color, {})[gender] = meta
                write_progress("converting", index, total, item.name)
                if index % 100 == 0 or index == total:
                    safe_name = item.name.encode('ascii', 'replace').decode('ascii')
                    print(f"[{index:4d}/{total}] {safe_name}", flush=True)
        else:
            jobs = []
            reused = 0
            for (dex, side, color, gender), item in sorted(found.items()):
                rel = asset_subdir / side / color / f"{dex:03d}{variant_suffix(gender)}.png"
                out = dest / rel
                if not args.force and output_png_is_valid(out):
                    data = item.read_bytes()
                    meta = gif_metadata(data, rel.as_posix(), args.max_texture,
                                        effective_scale(data, side, args.scale, args.fit_height))
                    meta["displayScale"] = display_scale(side)
                    species = records.setdefault(dex, {})
                    species.setdefault(side, {}).setdefault(color, {})[gender] = meta
                    reused += 1
                    write_progress("converting", reused, total, item.name)
                else:
                    jobs.append((dex, side, color, gender, item, out, rel))
            if reused:
                print(f"Reusing {reused} sheets; converting {len(jobs)} GIFs.", flush=True)
            workers = max(1, int(args.workers))
            if jobs:
                with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
                    futures = [pool.submit(_convert_job, job, args.max_texture, args.scale, args.compress_level, args.fit_height) for job in jobs]
                    for index, fut in enumerate(concurrent.futures.as_completed(futures), 1):
                        dex, side, color, gender, name, meta = fut.result()
                        species = records.setdefault(dex, {})
                        species.setdefault(side, {}).setdefault(color, {})[gender] = meta
                        write_progress("converting", reused + index, total, name)
                        if index % 25 == 0 or index == len(jobs):
                            safe_name = name.encode('ascii', 'replace').decode('ascii')
                            print(f"[{index:4d}/{len(jobs)}] {safe_name}", flush=True)

        write_progress("converting", total, total, "WRITING")
        if args.extra:
            rows = write_extra_meta(dest / EXTRA_META_REL, records)
            print(f"Sheet meta: {(dest / EXTRA_META_REL).as_posix()} ({rows} rows)")
        else:
            write_metadata(metadata_path, records)
            write_file_list(dest / "files.txt", records, args.metadata_only)
        write_progress("done", len(records), total, "READY")
        print(f"\nGenerated metadata for {len(records)} species from {total} GIFs (max dex {args.max_dex}).")
        if not args.extra:
            print(f"Metadata: {metadata_path.as_posix()}")
        if not args.metadata_only:
            print(f"Sprites:  {asset_root.as_posix()}")
        return 0
    except Exception as err:
        write_progress("fail", 0, 1, str(err))
        raise


if __name__ == "__main__":
    raise SystemExit(main())