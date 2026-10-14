# Generates src/import/Gen3PyramidTables.lua from a pokeemerald checkout: the
# Battle Pyramid's tables (src/battle_pyramid.c, its two wild-mon headers, and
# gBattlePyramidWildMonHeaders in src/data/wild_encounters.json), with every
# ITEM_ / SPECIES_ / MOVE_ / FACILITY_CLASS_ name resolved to its number.
#
# Numbers, not names: the port's keys are not the constants' spellings
# (ITEM_BRIGHT_POWDER is BRIGHTPOWDER in the cache), so the runtime maps them
# through constants.itemOrder / speciesOrder / moveOrder, which are indexed by
# exactly these numbers.
#
#   python tools/gen3_pyramid_tables_gen.py <pokeemerald> [out.lua]

import json
import re
import sys
from pathlib import Path


def defines(path, prefix):
    out = {}
    for name, val in re.findall(r"#define\s+(" + prefix + r"[A-Z0-9_]+)\s+(0x[0-9A-Fa-f]+|\d+)\b", path.read_text()):
        out[name] = int(val, 0)
    return out


def enum_values(path, prefix):
    """The members of the file's `enum { ... }` blocks with this prefix, numbered
    as C numbers them (from 0, or from an explicit `= n`)."""
    out = {}
    text = re.sub(r"//[^\n]*|/\*.*?\*/", "", path.read_text(), flags=re.S)
    for blk in re.findall(r"enum\s*\w*\s*\{(.*?)\}", text, flags=re.S):
        n = 0
        for entry in blk.split(","):
            entry = entry.strip()
            if not entry:
                continue
            m = re.match(r"(\w+)\s*(?:=\s*(.+))?$", entry)
            if not m:
                continue
            if m.group(2):
                v = m.group(2).strip()
                n = int(v, 0) if re.match(r"^(0x[0-9A-Fa-f]+|\d+)$", v) else out.get(v, n)
            if m.group(1).startswith(prefix):
                out[m.group(1)] = n
            n += 1
    return out


def body(src, name):
    m = re.search(re.escape(name) + r"\s*(\[[^=]*)?=\s*\{", src)
    if not m:
        raise SystemExit("not found: " + name)
    i, depth = m.end() - 1, 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[i + 1:j]
    raise SystemExit("unbalanced: " + name)


def rows(text):
    return [re.findall(r"[A-Za-z_0-9]+", r) for r in re.findall(r"\{([^{}]*)\}", text)]


def lua(v, indent=""):
    if isinstance(v, list):
        if not v:
            return "{}"
        if all(not isinstance(x, (list, dict)) for x in v):
            return "{ " + ", ".join(lua(x) for x in v) + " }"
        inner = indent + "  "
        return "{\n" + ",\n".join(inner + lua(x, inner) for x in v) + ",\n" + indent + "}"
    if isinstance(v, dict):
        inner = indent + "  "
        return "{ " + ", ".join("%s = %s" % (k, lua(x, inner)) for k, x in v.items()) + " }"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v
    return str(v)


def main():
    root = Path(sys.argv[1])
    out = Path(sys.argv[2] if len(sys.argv) > 2 else "src/import/Gen3PyramidTables.lua")
    src = (root / "src/battle_pyramid.c").read_text()
    items = enum_values(root / "include/constants/items.h", "ITEM_")
    species = defines(root / "include/constants/species.h", "SPECIES_")
    moves = defines(root / "include/constants/moves.h", "MOVE_")
    classes = defines(root / "include/constants/trainers.h", "FACILITY_CLASS_")

    # sPyramidFloorTemplates
    temps = []
    for blk in re.findall(r"\{([^{}]*\{[^{}]*\}[^{}]*)\}", body(src, "sPyramidFloorTemplates")):
        f = dict(re.findall(r"\.(\w+)\s*=\s*([A-Z_0-9]+)", blk))
        lo = [int(x) for x in re.search(r"layoutOffsets\s*=\s*\{([^}]*)\}", blk).group(1).split(",")]
        pos = {"OBJ_POSITIONS_UNIFORM": 0, "OBJ_POSITIONS_IN_AND_NEAR_ENTRANCE": 1, "OBJ_POSITIONS_IN_AND_NEAR_EXIT": 2,
               "OBJ_POSITIONS_NEAR_ENTRANCE": 3, "OBJ_POSITIONS_NEAR_EXIT": 4}
        temps.append({"numItems": int(f["numItems"]), "numTrainers": int(f["numTrainers"]),
                      "itemPositions": pos[f["itemPositions"]], "trainerPositions": pos[f["trainerPositions"]],
                      "runMultiplier": int(f["runMultiplier"]), "layoutOffsets": lo})
    assert len(temps) == 16, len(temps)

    def nums(name):
        return [[int(x, 0) for x in r] for r in rows(body(src, name))]

    def flat(name):
        return [int(x, 0) for x in re.findall(r"\b(0x[0-9A-Fa-f]+|\d+)\b", body(src, name))]

    options = nums("sPyramidFloorTemplateOptions")
    pickup_slots = nums("sPickupItemSlots")
    bordered = [[(x & 0xFF) for x in r] for r in [[int(x) for x in re.findall(r"-?\d+", r)] for r in re.findall(r"\{([^{}]*)\}", body(src, "sBorderedSquareIds"))]]

    def item_rows(name):
        return [[items[x] for x in r] for r in rows(body(src, name))]

    groups = [[classes[r[0]], int(r[1])] for r in rows(body(src, "sTrainerTextGroups"))]
    hint_types = {"HINT_EXIT_DIRECTION": 0, "HINT_REMAINING_ITEMS": 1, "HINT_REMAINING_TRAINERS": 2,
                  "HINT_EXIT_SHORT_REMAINING_TRAINERS": 3, "HINT_EXIT_SHORT_REMAINING_ITEMS": 4,
                  "HINT_EXIT_MEDIUM_REMAINING_TRAINERS": 5, "HINT_EXIT_MEDIUM_REMAINING_ITEMS": 6,
                  "HINT_EXIT_FAR_REMAINING_TRAINERS": 7, "HINT_EXIT_FAR_REMAINING_ITEMS": 8}
    hints = [hint_types[x] for x in re.findall(r"HINT_[A-Z_]+", body(src, "sHintTextTypes"))]

    def wild(fname, prefix):
        text = (root / "src/data/battle_frontier" / fname).read_text()
        rounds = []
        for n in range(1, 21):
            b = body(text, "%s_Round%d" % (prefix, n))
            mons = []
            for blk in re.findall(r"\{([^{}]*\{[^{}]*\}[^{}]*)\}", b):
                sp = re.search(r"\.species\s*=\s*(SPECIES_\w+)", blk).group(1)
                lvl = int(re.search(r"\.lvl\s*=\s*(\d+)", blk).group(1))
                ab = re.search(r"\.abilityNum\s*=\s*(\w+)", blk).group(1)
                ab = 2 if ab == "ABILITY_RANDOM" else int(ab)
                mv = [moves[m] for m in re.findall(r"MOVE_\w+", re.search(r"\.moves\s*=\s*\{([^}]*)\}", blk).group(1))]
                mons.append({"species": species[sp], "lvl": lvl, "ability": ab, "moves": mv})
            rounds.append(mons)
        return rounds

    w50 = wild("battle_pyramid_level_50_wild_mons.h", "sLevel50WildMons")
    wopen = wild("battle_pyramid_open_level_wild_mons.h", "sOpenLevelWildMons")

    enc = json.loads((root / "src/data/wild_encounters.json").read_text())
    headers = None
    for g in enc["wild_encounter_groups"]:
        if g["label"] == "gBattlePyramidWildMonHeaders":
            headers = [{"rate": e["land_mons"]["encounter_rate"],
                        "slots": [species[m["species"]] for m in e["land_mons"]["mons"]]} for e in g["encounters"]]
    assert headers and len(headers) == 7

    T = [
        "-- GENERATED by tools/gen3_pyramid_tables_gen.py from pokeemerald's",
        "-- src/battle_pyramid.c, src/data/battle_frontier/battle_pyramid_*_wild_mons.h and",
        "-- gBattlePyramidWildMonHeaders -- do not edit by hand.",
        "--",
        "-- Items, species and moves are the cartridge's NUMBERS (constants.itemOrder /",
        "-- speciesOrder / moveOrder turn them into the cache's keys); facility classes",
        "-- are FACILITY_CLASS_* numbers. Lists are 1-based Lua lists of the C arrays in",
        "-- order (so C index i is Lua [i + 1]); OBJ_POSITIONS_* and HINT_* by their",
        "-- enum values.",
        "",
        "local T = {}",
        "",
        "T.FLOOR_TEMPLATES = " + lua(temps),
        "T.TEMPLATE_OPTIONS = " + lua(options),
        "T.FLOOR_TEMPLATE_OFFSETS = " + lua(flat("sFloorTemplateOffsets")),
        "T.PICKUP_50 = " + lua(item_rows("sPickupItemsLvl50")),
        "T.PICKUP_OPEN = " + lua(item_rows("sPickupItemsLvlOpen")),
        "T.PICKUP_SLOTS = " + lua(pickup_slots),
        "T.PICKUP_OFFSETS = " + lua(flat("sPickupItemOffsets")),
        "T.PICKUP_PERCENTAGES = " + lua(flat("sPickupPercentages")),
        "T.BORDERED = " + lua(bordered),
        "T.TEXT_GROUPS = " + lua(groups),
        "T.HINT_TYPES = " + lua(hints),
        "T.SHORT_REWARDS = " + lua([items[x] for x in re.findall(r"ITEM_\w+", body(src, "sShortStreakRewardItems"))]),
        "T.LONG_REWARDS = " + lua([items[x] for x in re.findall(r"ITEM_\w+", body(src, "sLongStreakRewardItems"))]),
        "T.WILD_50 = " + lua(w50),
        "T.WILD_OPEN = " + lua(wopen),
        "T.WILD_HEADERS = " + lua(headers),
        "",
        "return T",
        "",
    ]
    out.write_text("\n".join(T), encoding="utf-8", newline="\n")
    print("wrote %s: %d templates, %d+%d wild rounds" % (out, len(temps), len(w50), len(wopen)))


main()
