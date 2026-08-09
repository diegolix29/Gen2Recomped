"""Build the normal-vs-shiny sprite sheet for all 151.

    luajit mods/DramaticShapeVoxelMod/tools/dump_shiny_palettes.lua > pals.json
    python mods/DramaticShapeVoxelMod/tools/shiny_sprite_sheet.py pals.json OUT.png

Run from the PROJECT ROOT.

WHY THIS IS A PALETTE JOB. The game's battle pics carry no colour: they are
four-shade DMG grey (255/170/85/0 plus transparency). Under ADVANCED the
colour comes entirely from a per-species palette laid over that art. So a
"shiny sprite" is the same pixels under a shifted palette -- which is what
this composites, using the real palettes out of data/palettes_gbc.lua and the
real shift out of the mod's own colour tables.

Each Pokemon appears as a PAIR, normal beside shiny, because a lone shiny
sprite says nothing about what changed.
"""
import json
import os
import sys
from PIL import Image, ImageDraw

ROOT = os.getcwd()
FRONT = os.path.join(ROOT, "assets", "generated", "battle", "front")

pals = json.load(open(sys.argv[1], encoding="utf-8"))
OUT = sys.argv[2] if len(sys.argv) > 2 else "shiny_sprites.png"

# the four DMG shades the art is drawn in, lightest first, matching the
# palette's own colour order
SHADES = [255, 170, 85, 0]

SCALE = 2
SW = 40 * SCALE            # sprite box
PAD = 3
LABEL = 11
CELL_W = SW * 2 + PAD      # a normal/shiny pair
CELL_H = SW + LABEL
COLS = 8                   # pairs per row
MARGIN = 10
GAP_X, GAP_Y = 14, 8


def slug_for(species):
    """assets/generated/battle/front filenames, which are not the species key."""
    s = species.lower()
    cands = [s, s.replace("_", ""), s.replace("_", "."),
             s.replace("_f", "f").replace("_m", "m")]
    for c in cands:
        p = os.path.join(FRONT, c + ".png")
        if os.path.exists(p):
            return p
    return None


def colorize(img, pal):
    """Map the four DMG shades onto a palette. Alpha is carried through."""
    src = img.convert("RGBA")
    out = Image.new("RGBA", src.size, (0, 0, 0, 0))
    sp, op = src.load(), out.load()
    for y in range(src.size[1]):
        for x in range(src.size[0]):
            r, g, b, a = sp[x, y]
            if a < 8:
                continue
            # the art is grey, so any channel identifies the shade; nearest
            # rather than exact, because a scaled or re-encoded asset can be
            # a unit off
            best, bi = None, 0
            for i, sh in enumerate(SHADES):
                d = abs(r - sh)
                if best is None or d < best:
                    best, bi = d, i
            c = pal[bi]
            op[x, y] = (c[0], c[1], c[2], a)
    return out


rows = (len(pals) + COLS - 1) // COLS
W = MARGIN * 2 + COLS * CELL_W + (COLS - 1) * GAP_X
H = MARGIN * 2 + 34 + rows * (CELL_H + GAP_Y)

sheet = Image.new("RGB", (W, H), (24, 24, 28))
d = ImageDraw.Draw(sheet)
d.text((MARGIN, 8),
       "Gen 1 battle sprites -- NORMAL (left) vs SHINY (right) of each pair."
       "  ADVANCED palettes, shifted by the Stadium shiny values.",
       fill=(235, 235, 235))
d.text((MARGIN, 21),
       "The art is 4-shade DMG grey; all colour is the palette, so a shiny"
       " sprite is the same pixels under a shifted palette.",
       fill=(150, 150, 158))

missing = []
for i, e in enumerate(pals):
    path = slug_for(e["species"])
    cx = MARGIN + (i % COLS) * (CELL_W + GAP_X)
    cy = MARGIN + 34 + (i // COLS) * (CELL_H + GAP_Y)
    if not path:
        missing.append(e["species"])
        continue
    src = Image.open(path)
    n = colorize(src, e["normal"]).resize((SW, SW), Image.NEAREST)
    s = colorize(src, e["shiny"]).resize((SW, SW), Image.NEAREST)
    # a faint plate behind each half so a dark shiny is not lost on the
    # background -- the same plate under both, so it cannot flatter one
    d.rectangle([cx, cy, cx + SW - 1, cy + SW - 1], fill=(44, 44, 50))
    d.rectangle([cx + SW + PAD, cy, cx + SW * 2 + PAD - 1, cy + SW - 1],
                fill=(44, 44, 50))
    sheet.paste(n, (cx, cy), n)
    sheet.paste(s, (cx + SW + PAD, cy), s)
    tag = "%03d %s" % (e["dex"], e["name"][:11])
    same = e["normal"] == e["shiny"]
    d.text((cx + 1, cy + SW + 1), tag,
           fill=(120, 120, 128) if same else (225, 225, 232))

d.text((MARGIN, H - 12),
       "grey label = palette identical between the two (that species' shiny"
       " does not move this palette)",
       fill=(120, 120, 128))

sheet.save(OUT)
print("wrote", OUT, sheet.size)
if missing:
    print("no sprite for:", ", ".join(missing))
same_n = sum(1 for e in pals if e["normal"] == e["shiny"])
print("pairs: %d, palettes that shift: %d, identical: %d"
      % (len(pals), len(pals) - same_n, same_n))
