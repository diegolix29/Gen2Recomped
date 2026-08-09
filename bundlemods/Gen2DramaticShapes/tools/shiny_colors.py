"""Emit the mod's data/shiny_colors.lua from the validated Stadium tables.

PROVENANCE. data/shiny_colors.lua is 62KB of generated data and this is
where it came from, so it is checked in even though its INPUTS are not:
they live under .claude/shiny_stadium/ (the research tree: the transcribed
Stadium colour table, the extracted texture pairs, the inventory that marks
which textures are effects), and that path is gitignored along with
everything else derived from the ROM.

So this will not run from a fresh clone, and it is not meant to -- the Lua
it writes is the shipped artefact. It is here to record HOW the numbers were
arrived at, and to be re-runnable by anyone who still has the research tree.

The values themselves are the Stadium games' own: a hue rotation in degrees
plus saturation and lightness on a quantized -8..+8 scale at 12.5% a step.
The column order in the source table is H, L, S -- hue, LIGHTNESS,
saturation -- which was checked against the canonical pokeemerald palettes
across all 146 sliding species before being trusted.


Two kinds of entry, because Stadium itself has two kinds of shiny:

  slide {h, l, s}   the 146 species Stadium recolours by sliding the whole
                    model in HSL.  h is degrees; l and s are Stadium's
                    -8..+8 steps at 12.5% each.  Three numbers reproduce the
                    whole model, so this is data-cheap and exact.

  lut {from = to}   the 5 species Stadium ships a genuine alternate texture
                    for (Clefairy, Clefable, Jigglypuff, Wigglytuff,
                    Gyarados).  No slide can express those -- Jigglypuff's
                    body must stay pink while its irises rotate to green --
                    so they carry an explicit colour mapping, sampled from
                    the verified texture pairs.  Exact by construction, and
                    only the colours that actually change are listed.
"""
import json
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
# the research tree (gitignored -- see the provenance note above)
SS = os.path.join(MOD, ".claude", "shiny_stadium")
OUT = os.path.join(MOD, "data", "shiny_colors.lua")

vals = json.load(open(os.path.join(SS, "stadium_shiny_values.json"), encoding="utf-8"))
V = vals["species"]

inv = json.load(open(os.path.join(SS, "texture_inventory.json"), encoding="utf-8"))
models = inv["models"] if isinstance(inv, dict) and "models" in inv else inv
if isinstance(models, dict):
    models = list(models.values())
kind = {}
for m in models:
    dex = str(m.get("dex") or m.get("species") or "").zfill(3)
    for t in m.get("textures", []):
        kind[(dex, int(t.get("index", -1)))] = t.get("kind", "body")

TEX = os.path.join(SS, "textures")
slugs = {d.split("_")[0]: d for d in os.listdir(os.path.join(TEX, "normal"))}


def lut_for(dex):
    """Distinct colour mapping over this species' BODY textures only.

    fx textures are excluded exactly as the build excluded them: a shiny
    Gyarados has shiny scales and an ordinary Hyper Beam.
    """
    d = slugs[dex]
    pairs = {}
    for fn in sorted(os.listdir(os.path.join(TEX, "normal", d))):
        idx = int(fn.replace("tex_", "").replace(".png", ""))
        if kind.get((dex, idx), "body") != "body":
            continue
        a = Image.open(os.path.join(TEX, "normal", d, fn)).convert("RGBA")
        b = Image.open(os.path.join(TEX, "shiny", d, fn)).convert("RGBA")
        if a.size != b.size:
            continue
        pa, pb = a.load(), b.load()
        for y in range(a.size[1]):
            for x in range(a.size[0]):
                ca, cb = pa[x, y], pb[x, y]
                if ca[3] < 8:
                    continue
                pairs.setdefault(ca[:3], cb[:3])
    return {k: v for k, v in pairs.items() if k != v}


def dominant(dex):
    """The most-covering opaque colour across this species' BODY textures.

    Deliberately not the mean: a mean over a Pokemon with a light belly and a
    dark back lands on a mid-grey that belongs to neither, and the tint drawn
    from it would be no tint. The modal colour is a real colour off the model.
    """
    d = slugs[dex]
    counts = {}
    for fn in sorted(os.listdir(os.path.join(TEX, "normal", d))):
        idx = int(fn.replace("tex_", "").replace(".png", ""))
        if kind.get((dex, idx), "body") != "body":
            continue
        im = Image.open(os.path.join(TEX, "normal", d, fn)).convert("RGBA")
        px = im.load()
        for y in range(im.size[1]):
            for x in range(im.size[0]):
                c = px[x, y]
                if c[3] < 8:
                    continue
                # skip the near-black and near-white structural colours:
                # outlines and eye whites are on every model and say nothing
                # about which Pokemon this is
                if max(c[:3]) < 30 or min(c[:3]) > 225:
                    continue
                counts[c[:3]] = counts.get(c[:3], 0) + 1
    if not counts:
        return None
    return max(counts.items(), key=lambda kv: kv[1])[0]


lines = []
w = lines.append

w("-- Shiny colours for the 151 Stadium models, as the Stadium games define")
w("-- them. GENERATED -- do not hand-edit. The colour model is documented in")
w("-- the header of lib/ShinyPalette.lua.")
w("--")
w("-- Stadium does not ship a second set of textures for a shiny Pokemon. It")
w("-- slides the colours it already has in HSL: a hue rotation in degrees,")
w("-- plus saturation and lightness on a quantized -8..+8 scale where one")
w("-- step is 12.5% (so +-8 is +-100%, exactly GIMP's Hue-Saturation range --")
w("-- s = -8 is full greyscale, l = +8 is white).")
w("--")
w("-- FIVE SPECIES ARE DIFFERENT. Clefairy, Clefable, Jigglypuff, Wigglytuff")
w("-- and Gyarados get a genuine alternate texture in Stadium, because no")
w("-- single slide can produce their shiny: Jigglypuff's body must stay pink")
w("-- while its irises rotate to green, and one rotation moves both or")
w("-- neither. Those five carry `lut` -- an explicit before/after colour")
w("-- mapping sampled from the verified texture pairs, listing only the")
w("-- colours that actually change. A colour absent from the table is left")
w("-- exactly as it was.")
w("--")
w("-- hueRange is the min/max hue a NON-shiny nicknamed mon can slide to in")
w("-- Stadium (derived from the trainer ID and the nickname). Carried for")
w("-- reference; nothing reads it today.")
w("")
w("return {")

n_slide = n_lut = n_entries = 0
for dex in sorted(V):
    e = V[dex]
    hr = e["hue_range"]
    w("  [%d] = {" % int(dex))
    w('    name = "%s",' % e["name"])
    w("    hueRange = { min = %d, max = %d }," % (hr["min"], hr["max"]))
    dom = dominant(dex)
    if dom:
        w("    -- the colour this species is mostly MADE of, and what its"
          " shiny")
        w("    -- shift does to it. A flat sprite cannot be recoloured, only")
        w("    -- multiplied, and the multiply has to be measured against the")
        w("    -- body colour: averaged over a balanced set of references a")
        w("    -- hue rotation cancels itself out to no tint at all.")
        w("    dom = 0x%02X%02X%02X," % dom)
    if e["special_texture"]:
        n_lut += 1
        lut = lut_for(dex)
        n_entries += len(lut)
        w("    -- Stadium ships a real alternate texture for this one; %d"
          % len(lut))
        w("    -- colours move, every other colour stays exactly as it was.")
        w("    lut = {")
        row = []
        for src in sorted(lut):
            dst = lut[src]
            row.append("[0x%02X%02X%02X]=0x%02X%02X%02X,"
                       % (src[0], src[1], src[2], dst[0], dst[1], dst[2]))
            if len(row) == 4:
                w("      " + " ".join(row))
                row = []
        if row:
            w("      " + " ".join(row))
        w("    },")
    else:
        n_slide += 1
        h = e["hsl"]
        w("    slide = { h = %d, l = %d, s = %d }," % (h["h"], h["l"], h["s"]))
    w("  },")

w("}")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("wrote", OUT)
print("slide species:", n_slide, " lut species:", n_lut,
      " lut entries:", n_entries)
print("bytes:", os.path.getsize(OUT))
