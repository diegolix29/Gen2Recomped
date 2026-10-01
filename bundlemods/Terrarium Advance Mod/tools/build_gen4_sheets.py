#!/usr/bin/env python3
"""Build Terrarium HD sheets (and geometry rows) from animated GIFs.

KIM ships art for dex 1-386 only. This produces the same sheet format for
whatever you supply for 387-493 (or replacements for 1-386):

    <out>/<front|back>/<normal|shiny>/<stem>.png    palette-PNG atlas, 0.60x
    data/hd_sheet_meta_gen4.lua                     geometry rows (merged)

Input naming (same convention as Kanto in Motion's importer, plus forms):

    400-front-n.gif        Bibarel, front, normal        (n = normal, s = shiny)
    400-back-s.gif         Bibarel, back, shiny
    403-front-n-m.gif      Luxio, front, normal, male    (-m / -f gender variant)
    487-origin-front-n.gif Giratina-Origin, front, normal (form name, a-z0-9)

Everything above dex 493 is skipped: Platinum has nothing there.

Then copy <out>/* into the mod at  assets/hd-pokemon/  (or into mod.cache under
hd_sheets/). A species with no file is left on its native art; a form with no
file is also left native (never shown as the wrong form).

    build_gen4_sheets.py GIFS_OR_ZIP [...] --out ./hd-pokemon
    build_gen4_sheets.py GIFS --scales scales.json   # {"400": 0.31, "487-origin": 0.4}

displayScale (HD px -> Game Boy px) decides on-screen size. KIM derived it from a
per-species reference table that only exists for 1-386, so 387-493 default to the
median of KIM's own Gen 2 rows (front 0.33 / back 0.315). Tune per species in
scales.json; the key is "<dex>", "<stem>", or "<stem>-<front|back>".
"""
import argparse
import io
import json
import math
import re
import zipfile
from pathlib import Path

from PIL import Image

MAX_DEX = 493
DEFAULT_SCALE = {"front": 0.33, "back": 0.315}
TICK_MS = 50
MAX_FRAMES = 120

NAME_RE = re.compile(
    r"^(?P<dex>\d+)(?:-(?P<form>[a-z][a-z0-9]*))?-(?P<side>front|back)-(?P<color>[ns])"
    r"(?:-(?P<gender>[fm]))?\.gif$",
    re.IGNORECASE,
)
ROW_RE = re.compile(r'^\s+\["(?P<stem>[0-9a-z-]+)"\] = \{(?P<v>[0-9.,-]+)\},\s*$')


def iter_source(path: Path):
    if path.is_dir():
        for p in sorted(path.rglob("*.gif")):
            yield p.name, p.read_bytes
        return
    if not (path.is_file() and zipfile.is_zipfile(path)):
        raise SystemExit(f"Not a GIF folder or ZIP: {path}")
    zf = zipfile.ZipFile(path)
    for member in sorted(zf.namelist()):
        if member.lower().endswith(".gif"):
            yield Path(member).name, (lambda m=member: zf.read(m))


def choose_grid(n, w, h, max_texture):
    max_cols = min(n, max_texture // w)
    max_rows = max_texture // h
    if max_cols < 1 or max_rows < 1:
        raise ValueError(f"frame {w}x{h} exceeds max texture {max_texture}")
    min_cols = max(1, math.ceil(n / max_rows))
    if min_cols > max_cols:
        raise ValueError(f"{n} frames of {w}x{h} do not fit {max_texture}x{max_texture}")
    best = None
    for cols in range(min_cols, max_cols + 1):
        rows = math.ceil(n / cols)
        sw, sh = cols * w, rows * h
        score = (max(sw, sh), abs(sw - sh), sw * sh, cols)
        if best is None or score < best[0]:
            best = (score, cols, rows)
    return best[1], best[2]


def read_frames(data: bytes):
    """Return (frames as RGBA images, ms per frame). Uneven GIF timing is
    resampled onto a fixed tick so the runtime can use one duration."""
    im = Image.open(io.BytesIO(data))
    raw, durations = [], []
    for i in range(int(getattr(im, "n_frames", 1) or 1)):
        im.seek(i)
        raw.append(im.convert("RGBA").copy())
        durations.append(max(10, int(im.info.get("duration") or TICK_MS)))
    if len(set(durations)) == 1:
        return raw[:MAX_FRAMES], durations[0]
    total = sum(durations)
    ticks = max(1, min(MAX_FRAMES, round(total / TICK_MS)))
    out, edges, acc = [], [], 0
    for d in durations:
        acc += d
        edges.append(acc)
    for t in range(ticks):
        at = (t + 0.5) * total / ticks
        out.append(raw[next(i for i, e in enumerate(edges) if at <= e)])
    return out, TICK_MS


def build_sheet(data: bytes, out_path: Path, scale: float, max_texture: int, write: bool):
    frames, ms = read_frames(data)
    sw, sh = frames[0].size
    w, h = max(1, round(sw * scale)), max(1, round(sh * scale))
    cols, rows = choose_grid(len(frames), w, h, max_texture)
    if write:
        sheet = Image.new("RGBA", (cols * w, rows * h), (0, 0, 0, 0))
        for i, frame in enumerate(frames):
            if frame.size != (w, h):
                frame = frame.resize((w, h), Image.Resampling.LANCZOS)
            sheet.alpha_composite(frame, ((i % cols) * w, (i // cols) * h))
        sheet = sheet.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(out_path, format="PNG", optimize=False, compress_level=6)
    return w, h, cols, len(frames), ms


def read_existing_meta(path: Path):
    table = {s: {c: {} for c in ("normal", "shiny")} for s in ("front", "back")}
    if not path.is_file():
        return table
    side = color = None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s{2}(front|back)\s*=\s*\{\s*$", line)
        if m:
            side = m[1]
            continue
        m = re.match(r"^\s{4}(normal|shiny)\s*=\s*\{\s*$", line)
        if m:
            color = m[1]
            continue
        m = ROW_RE.match(line)
        if m and side and color:
            table[side][color][m["stem"]] = m["v"]
    return table


def write_meta(path: Path, table):
    lines = [
        "-- Sheet geometry for National Dex 387-493 (and any extra/replacement sheet).",
        "-- Same format as hd_sheet_meta.lua: {frameW, frameH, columns, frames, displayScale [, ms]}",
        "-- Generated by tools/build_gen4_sheets.py. Entries here override the KIM table.",
        "-- A sheet with no row here is drawn as one static frame at a default scale.",
        "return {",
    ]
    for side in ("front", "back"):
        lines.append(f"  {side} = {{")
        for color in ("normal", "shiny"):
            lines.append(f"    {color} = {{")
            for stem in sorted(table[side][color]):
                lines.append(f'      ["{stem}"] = {{{table[side][color][stem]}}},')
            lines.append("    },")
        lines.append("  },")
    lines.append("}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sources", nargs="+", type=Path, help="GIF folders or ZIP archives")
    ap.add_argument("--out", type=Path, default=Path("hd-pokemon"), help="sheet output root")
    ap.add_argument("--meta", type=Path,
                    default=Path(__file__).resolve().parents[1] / "data" / "hd_sheet_meta_gen4.lua")
    ap.add_argument("--min-dex", type=int, default=387)
    ap.add_argument("--max-dex", type=int, default=MAX_DEX)
    ap.add_argument("--scale", type=float, default=0.60, help="frame size multiplier (KIM: 0.60)")
    ap.add_argument("--max-texture", type=int, default=8192)
    ap.add_argument("--scales", type=Path, help="JSON of per-species displayScale overrides")
    ap.add_argument("--metadata-only", action="store_true")
    args = ap.parse_args()

    max_dex = min(args.max_dex, MAX_DEX)
    overrides = json.loads(args.scales.read_text(encoding="utf-8")) if args.scales else {}
    table = read_existing_meta(args.meta)
    done = skipped = 0
    for source in args.sources:
        for name, read in iter_source(source):
            m = NAME_RE.match(name)
            if not m:
                continue
            dex = int(m["dex"])
            if not (args.min_dex <= dex <= max_dex):
                skipped += 1
                continue
            form, gender = (m["form"] or "").lower(), (m["gender"] or "").lower()
            if form and gender:
                print(f"skip {name}: form + gender together is not supported")
                skipped += 1
                continue
            side = m["side"].lower()
            color = "normal" if m["color"].lower() == "n" else "shiny"
            stem = f"{dex:03d}" + (f"-{form}" if form else "") + (f"-{gender}" if gender else "")
            scale = float(overrides.get(f"{stem}-{side}", overrides.get(stem, overrides.get(str(dex), DEFAULT_SCALE[side]))))
            try:
                w, h, cols, frames, ms = build_sheet(
                    read(), args.out / side / color / f"{stem}.png", args.scale, args.max_texture,
                    not args.metadata_only)
            except Exception as exc:  # one bad GIF must not stop the batch
                print(f"skip {name}: {exc}")
                skipped += 1
                continue
            row = f"{w},{h},{cols},{frames},{scale:.6f}" + (f",{ms}" if ms != TICK_MS else "")
            table[side][color][stem] = row
            done += 1
            print(f"{name} -> {side}/{color}/{stem}.png  {w}x{h} {cols}c {frames}f {ms}ms scale {scale}")
    write_meta(args.meta, table)
    print(f"{done} sheets, {skipped} skipped -> {args.meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
