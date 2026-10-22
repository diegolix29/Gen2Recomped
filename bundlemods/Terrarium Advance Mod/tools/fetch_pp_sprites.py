#!/usr/bin/env python3
"""Download Project Pokemon 3D-model sprite GIFs and name them for tools/import_hd_pokemon.py.

Files written (front sprites; Project Pokemon's normal/shiny sprite GIFs are front-facing):
    <dex>-front-n.gif            <dex>-front-s.gif          default (male / genderless) art
    <dex>-front-n-f.gif          <dex>-front-s-f.gif        female art   (site name  <pokemon>-f.gif)
    <dex>-front-n-mega.gif ...   <dex>-front-s-megax.gif    forms        (site name  <pokemon>-mega-x.gif)

Typical run (from the mod folder):
    python tools/fetch_pp_sprites.py --out pp_gifs --mod .            # fill gaps + megas only
    python tools/import_hd_pokemon.py pp_gifs --target . --extra --fit-height

How it finds the real file names: it reads the seven sprite-index pages
(3d-models-generation-1..7 = r90..r96), collects every /images/normal-sprite/*.gif and
/images/shiny-sprite/*.gif it references, and maps each name to a National Dex number using the
built-in 1-721 name table. If the pages cannot be read it falls back to guessing the names
(<name>.gif, <name>-f.gif, <name>-mega.gif, <name>-mega-x/-y.gif, <name>-primal.gif).
Only the Python standard library is used. Already-downloaded files are skipped, so it can be re-run.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE_URL = "https://projectpokemon.org"
INDEX_PAGES = [  # generation -> index page (r90 .. r96)
    f"/home/docs/spriteindex_148/3d-models-generation-{g}-pok%C3%A9mon-r{89 + g}/" for g in range(1, 8)
]
UA = "Mozilla/5.0 (compatible; terrarium-hd-fetch/1.0; personal mod asset import)"

# National Dex 1-721, index 0 = dex 1.
NAMES = [
    "Bulbasaur", "Ivysaur", "Venusaur", "Charmander", "Charmeleon", "Charizard", "Squirtle",
    "Wartortle", "Blastoise", "Caterpie", "Metapod", "Butterfree", "Weedle", "Kakuna",
    "Beedrill", "Pidgey", "Pidgeotto", "Pidgeot", "Rattata", "Raticate", "Spearow", "Fearow",
    "Ekans", "Arbok", "Pikachu", "Raichu", "Sandshrew", "Sandslash", "Nidoran\u2640",
    "Nidorina", "Nidoqueen", "Nidoran\u2642", "Nidorino", "Nidoking", "Clefairy", "Clefable",
    "Vulpix", "Ninetales", "Jigglypuff", "Wigglytuff", "Zubat", "Golbat", "Oddish", "Gloom",
    "Vileplume", "Paras", "Parasect", "Venonat", "Venomoth", "Diglett", "Dugtrio", "Meowth",
    "Persian", "Psyduck", "Golduck", "Mankey", "Primeape", "Growlithe", "Arcanine", "Poliwag",
    "Poliwhirl", "Poliwrath", "Abra", "Kadabra", "Alakazam", "Machop", "Machoke", "Machamp",
    "Bellsprout", "Weepinbell", "Victreebel", "Tentacool", "Tentacruel", "Geodude", "Graveler",
    "Golem", "Ponyta", "Rapidash", "Slowpoke", "Slowbro", "Magnemite", "Magneton", "Farfetch'd",
    "Doduo", "Dodrio", "Seel", "Dewgong", "Grimer", "Muk", "Shellder", "Cloyster", "Gastly",
    "Haunter", "Gengar", "Onix", "Drowzee", "Hypno", "Krabby", "Kingler", "Voltorb",
    "Electrode", "Exeggcute", "Exeggutor", "Cubone", "Marowak", "Hitmonlee", "Hitmonchan",
    "Lickitung", "Koffing", "Weezing", "Rhyhorn", "Rhydon", "Chansey", "Tangela", "Kangaskhan",
    "Horsea", "Seadra", "Goldeen", "Seaking", "Staryu", "Starmie", "Mr. Mime", "Scyther",
    "Jynx", "Electabuzz", "Magmar", "Pinsir", "Tauros", "Magikarp", "Gyarados", "Lapras",
    "Ditto", "Eevee", "Vaporeon", "Jolteon", "Flareon", "Porygon", "Omanyte", "Omastar",
    "Kabuto", "Kabutops", "Aerodactyl", "Snorlax", "Articuno", "Zapdos", "Moltres", "Dratini",
    "Dragonair", "Dragonite", "Mewtwo", "Mew", "Chikorita", "Bayleef", "Meganium", "Cyndaquil",
    "Quilava", "Typhlosion", "Totodile", "Croconaw", "Feraligatr", "Sentret", "Furret",
    "Hoothoot", "Noctowl", "Ledyba", "Ledian", "Spinarak", "Ariados", "Crobat", "Chinchou",
    "Lanturn", "Pichu", "Cleffa", "Igglybuff", "Togepi", "Togetic", "Natu", "Xatu", "Mareep",
    "Flaaffy", "Ampharos", "Bellossom", "Marill", "Azumarill", "Sudowoodo", "Politoed",
    "Hoppip", "Skiploom", "Jumpluff", "Aipom", "Sunkern", "Sunflora", "Yanma", "Wooper",
    "Quagsire", "Espeon", "Umbreon", "Murkrow", "Slowking", "Misdreavus", "Unown", "Wobbuffet",
    "Girafarig", "Pineco", "Forretress", "Dunsparce", "Gligar", "Steelix", "Snubbull",
    "Granbull", "Qwilfish", "Scizor", "Shuckle", "Heracross", "Sneasel", "Teddiursa",
    "Ursaring", "Slugma", "Magcargo", "Swinub", "Piloswine", "Corsola", "Remoraid", "Octillery",
    "Delibird", "Mantine", "Skarmory", "Houndour", "Houndoom", "Kingdra", "Phanpy", "Donphan",
    "Porygon2", "Stantler", "Smeargle", "Tyrogue", "Hitmontop", "Smoochum", "Elekid", "Magby",
    "Miltank", "Blissey", "Raikou", "Entei", "Suicune", "Larvitar", "Pupitar", "Tyranitar",
    "Lugia", "Ho-Oh", "Celebi", "Treecko", "Grovyle", "Sceptile", "Torchic", "Combusken",
    "Blaziken", "Mudkip", "Marshtomp", "Swampert", "Poochyena", "Mightyena", "Zigzagoon",
    "Linoone", "Wurmple", "Silcoon", "Beautifly", "Cascoon", "Dustox", "Lotad", "Lombre",
    "Ludicolo", "Seedot", "Nuzleaf", "Shiftry", "Taillow", "Swellow", "Wingull", "Pelipper",
    "Ralts", "Kirlia", "Gardevoir", "Surskit", "Masquerain", "Shroomish", "Breloom", "Slakoth",
    "Vigoroth", "Slaking", "Nincada", "Ninjask", "Shedinja", "Whismur", "Loudred", "Exploud",
    "Makuhita", "Hariyama", "Azurill", "Nosepass", "Skitty", "Delcatty", "Sableye", "Mawile",
    "Aron", "Lairon", "Aggron", "Meditite", "Medicham", "Electrike", "Manectric", "Plusle",
    "Minun", "Volbeat", "Illumise", "Roselia", "Gulpin", "Swalot", "Carvanha", "Sharpedo",
    "Wailmer", "Wailord", "Numel", "Camerupt", "Torkoal", "Spoink", "Grumpig", "Spinda",
    "Trapinch", "Vibrava", "Flygon", "Cacnea", "Cacturne", "Swablu", "Altaria", "Zangoose",
    "Seviper", "Lunatone", "Solrock", "Barboach", "Whiscash", "Corphish", "Crawdaunt", "Baltoy",
    "Claydol", "Lileep", "Cradily", "Anorith", "Armaldo", "Feebas", "Milotic", "Castform",
    "Kecleon", "Shuppet", "Banette", "Duskull", "Dusclops", "Tropius", "Chimecho", "Absol",
    "Wynaut", "Snorunt", "Glalie", "Spheal", "Sealeo", "Walrein", "Clamperl", "Huntail",
    "Gorebyss", "Relicanth", "Luvdisc", "Bagon", "Shelgon", "Salamence", "Beldum", "Metang",
    "Metagross", "Regirock", "Regice", "Registeel", "Latias", "Latios", "Kyogre", "Groudon",
    "Rayquaza", "Jirachi", "Deoxys", "Turtwig", "Grotle", "Torterra", "Chimchar", "Monferno",
    "Infernape", "Piplup", "Prinplup", "Empoleon", "Starly", "Staravia", "Staraptor", "Bidoof",
    "Bibarel", "Kricketot", "Kricketune", "Shinx", "Luxio", "Luxray", "Budew", "Roserade",
    "Cranidos", "Rampardos", "Shieldon", "Bastiodon", "Burmy", "Wormadam", "Mothim", "Combee",
    "Vespiquen", "Pachirisu", "Buizel", "Floatzel", "Cherubi", "Cherrim", "Shellos",
    "Gastrodon", "Ambipom", "Drifloon", "Drifblim", "Buneary", "Lopunny", "Mismagius",
    "Honchkrow", "Glameow", "Purugly", "Chingling", "Stunky", "Skuntank", "Bronzor", "Bronzong",
    "Bonsly", "Mime Jr.", "Happiny", "Chatot", "Spiritomb", "Gible", "Gabite", "Garchomp",
    "Munchlax", "Riolu", "Lucario", "Hippopotas", "Hippowdon", "Skorupi", "Drapion", "Croagunk",
    "Toxicroak", "Carnivine", "Finneon", "Lumineon", "Mantyke", "Snover", "Abomasnow",
    "Weavile", "Magnezone", "Lickilicky", "Rhyperior", "Tangrowth", "Electivire", "Magmortar",
    "Togekiss", "Yanmega", "Leafeon", "Glaceon", "Gliscor", "Mamoswine", "Porygon-Z", "Gallade",
    "Probopass", "Dusknoir", "Froslass", "Rotom", "Uxie", "Mesprit", "Azelf", "Dialga",
    "Palkia", "Heatran", "Regigigas", "Giratina", "Cresselia", "Phione", "Manaphy", "Darkrai",
    "Shaymin", "Arceus", "Victini", "Snivy", "Servine", "Serperior", "Tepig", "Pignite",
    "Emboar", "Oshawott", "Dewott", "Samurott", "Patrat", "Watchog", "Lillipup", "Herdier",
    "Stoutland", "Purrloin", "Liepard", "Pansage", "Simisage", "Pansear", "Simisear", "Panpour",
    "Simipour", "Munna", "Musharna", "Pidove", "Tranquill", "Unfezant", "Blitzle", "Zebstrika",
    "Roggenrola", "Boldore", "Gigalith", "Woobat", "Swoobat", "Drilbur", "Excadrill", "Audino",
    "Timburr", "Gurdurr", "Conkeldurr", "Tympole", "Palpitoad", "Seismitoad", "Throh", "Sawk",
    "Sewaddle", "Swadloon", "Leavanny", "Venipede", "Whirlipede", "Scolipede", "Cottonee",
    "Whimsicott", "Petilil", "Lilligant", "Basculin", "Sandile", "Krokorok", "Krookodile",
    "Darumaka", "Darmanitan", "Maractus", "Dwebble", "Crustle", "Scraggy", "Scrafty",
    "Sigilyph", "Yamask", "Cofagrigus", "Tirtouga", "Carracosta", "Archen", "Archeops",
    "Trubbish", "Garbodor", "Zorua", "Zoroark", "Minccino", "Cinccino", "Gothita", "Gothorita",
    "Gothitelle", "Solosis", "Duosion", "Reuniclus", "Ducklett", "Swanna", "Vanillite",
    "Vanillish", "Vanilluxe", "Deerling", "Sawsbuck", "Emolga", "Karrablast", "Escavalier",
    "Foongus", "Amoonguss", "Frillish", "Jellicent", "Alomomola", "Joltik", "Galvantula",
    "Ferroseed", "Ferrothorn", "Klink", "Klang", "Klinklang", "Tynamo", "Eelektrik",
    "Eelektross", "Elgyem", "Beheeyem", "Litwick", "Lampent", "Chandelure", "Axew", "Fraxure",
    "Haxorus", "Cubchoo", "Beartic", "Cryogonal", "Shelmet", "Accelgor", "Stunfisk", "Mienfoo",
    "Mienshao", "Druddigon", "Golett", "Golurk", "Pawniard", "Bisharp", "Bouffalant", "Rufflet",
    "Braviary", "Vullaby", "Mandibuzz", "Heatmor", "Durant", "Deino", "Zweilous", "Hydreigon",
    "Larvesta", "Volcarona", "Cobalion", "Terrakion", "Virizion", "Tornadus", "Thundurus",
    "Reshiram", "Zekrom", "Landorus", "Kyurem", "Keldeo", "Meloetta", "Genesect", "Chespin",
    "Quilladin", "Chesnaught", "Fennekin", "Braixen", "Delphox", "Froakie", "Frogadier",
    "Greninja", "Bunnelby", "Diggersby", "Fletchling", "Fletchinder", "Talonflame",
    "Scatterbug", "Spewpa", "Vivillon", "Litleo", "Pyroar", "Flab\u00e9b\u00e9", "Floette",
    "Florges", "Skiddo", "Gogoat", "Pancham", "Pangoro", "Furfrou", "Espurr", "Meowstic",
    "Honedge", "Doublade", "Aegislash", "Spritzee", "Aromatisse", "Swirlix", "Slurpuff",
    "Inkay", "Malamar", "Binacle", "Barbaracle", "Skrelp", "Dragalge", "Clauncher", "Clawitzer",
    "Helioptile", "Heliolisk", "Tyrunt", "Tyrantrum", "Amaura", "Aurorus", "Sylveon",
    "Hawlucha", "Dedenne", "Carbink", "Goomy", "Sliggoo", "Goodra", "Klefki", "Phantump",
    "Trevenant", "Pumpkaboo", "Gourgeist", "Bergmite", "Avalugg", "Noibat", "Noivern",
    "Xerneas", "Yveltal", "Zygarde", "Diancie", "Hoopa", "Volcanion"
]
assert len(NAMES) == 721

# Mega Evolutions (Gen 6) and Primal Reversions. value = form keys; X/Y are separate sprites.
MEGA_FORMS = {
    3: ["mega"], 6: ["megax", "megay"], 9: ["mega"], 15: ["mega"], 18: ["mega"], 65: ["mega"],
    80: ["mega"], 94: ["mega"], 115: ["mega"], 127: ["mega"], 130: ["mega"], 142: ["mega"],
    150: ["megax", "megay"], 181: ["mega"], 208: ["mega"], 212: ["mega"], 214: ["mega"],
    229: ["mega"], 248: ["mega"], 254: ["mega"], 257: ["mega"], 260: ["mega"], 282: ["mega"],
    302: ["mega"], 303: ["mega"], 306: ["mega"], 308: ["mega"], 310: ["mega"], 319: ["mega"],
    323: ["mega"], 334: ["mega"], 354: ["mega"], 359: ["mega"], 362: ["mega"], 373: ["mega"],
    376: ["mega"], 380: ["mega"], 381: ["mega"], 384: ["mega"], 428: ["mega"], 445: ["mega"],
    448: ["mega"], 460: ["mega"], 475: ["mega"], 531: ["mega"], 719: ["mega"],
    382: ["primal"], 383: ["primal"],
}
# spellings a site might use for a form key when guessing file names
FORM_SPELLINGS = {
    "mega": ["mega"], "megax": ["mega-x", "megax", "mega_x"], "megay": ["mega-y", "megay", "mega_y"],
    "primal": ["primal"],
}


def ascii_fold(text: str) -> str:
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")


def base_slugs(dex: int) -> list[str]:
    """Plausible file-name stems for a species, most likely first."""
    name = NAMES[dex - 1]
    if dex == 29:
        return ["nidoran-f", "nidoranf", "nidoran"]
    if dex == 32:
        return ["nidoran-m", "nidoranm"]
    n = ascii_fold(name).lower().replace("'", "")
    out = [re.sub(r"[^a-z0-9]+", "-", n).strip("-")]          # mr-mime, ho-oh, porygon-z, farfetchd
    out.append(re.sub(r"[^a-z0-9]+", "", n))                    # mrmime, hooh, porygonz
    out.append(n.replace(" ", "-"))                             # mr.-mime, mime-jr.
    return list(dict.fromkeys(s for s in out if s))


def build_slug_map() -> dict[str, int]:
    m: dict[str, int] = {}
    for dex in range(1, 722):
        for s in base_slugs(dex):
            m.setdefault(s, dex)
    return m


def classify(slug: str, slug_map: dict[str, int]):
    """site file stem -> (dex, variant) where variant is '' | 'f' | 'm' | <form key>; None if unknown."""
    s = urllib.parse.unquote(slug).lower()
    if s in slug_map:
        return slug_map[s], ""
    parts = s.split("-")
    for i in range(len(parts) - 1, 0, -1):
        base, rest = "-".join(parts[:i]), "-".join(parts[i:])
        if base in slug_map:
            if rest in ("f", "m"):
                return slug_map[base], rest
            key = re.sub(r"[^a-z0-9]", "", rest)
            return (slug_map[base], key) if key else None
    return None


def http_get(url: str, timeout: float = 40.0, retries: int = 3):
    """bytes, or None for 404/403/410. Raises after retries on other errors."""
    last = None
    for attempt in range(retries):
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": BASE_URL + "/"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code in (404, 403, 410):
                return None
            last = e
        except Exception as e:  # noqa: BLE001 - network flake: retry
            last = e
        time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"{url}: {last}")


GIF_RE = re.compile(r"/images/(?:normal|shiny)-sprite/([A-Za-z0-9_.%\-]+?)\.gif", re.IGNORECASE)


def scrape_index(base_url: str) -> set[str]:
    found: set[str] = set()
    for page in INDEX_PAGES:
        try:
            html = http_get(base_url + page)
        except Exception as e:  # noqa: BLE001
            print(f"  index page failed: {page} ({e})")
            continue
        if html is None:
            print(f"  index page not reachable: {page}")
            continue
        names = {m.group(1).lower() for m in GIF_RE.finditer(html.decode("utf-8", "replace"))}
        print(f"  {page.split('/')[-2][:48]:<48} {len(names):4d} sprite names")
        found |= names
    return found


def meta_front_stems(mod_dir: Path) -> set[str]:
    """Stems that already have a FRONT sheet geometry row in the mod's data/hd_sheet_meta*.lua."""
    stems: set[str] = set()
    for f in sorted((mod_dir / "data").glob("hd_sheet_meta*.lua")):
        facing = None
        for line in f.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\s{2}(front|back) = \{", line)
            if m:
                facing = m.group(1)
                continue
            m = re.match(r'^\s*\["(\d{3}[a-z0-9\-]*)"\]\s*=', line)
            if m and facing == "front":
                stems.add(m.group(1))
    return stems


def covered(stems: set[str], dex: int, variant: str) -> bool:
    b = f"{dex:03d}"
    if variant == "":
        return bool({b, b + "-m", b + "-f"} & stems)
    return f"{b}-{variant}" in stems


def out_name(dex: int, color: str, variant: str) -> str:
    return f"{dex:03d}-front-{color}" + (f"-{variant}" if variant else "") + ".gif"


def keep_form(variant: str, mode: str) -> bool:
    if variant in ("", "f", "m"):
        return True
    if mode == "none":
        return False
    if mode == "all":
        return True
    return variant.startswith("mega") or variant == "primal"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, required=True, help="folder for the downloaded GIFs")
    ap.add_argument("--mod", type=Path, default=None,
                    help="mod folder; with it, species/forms the mod already has sheet geometry for are skipped "
                         "(gap-fill mode). Without it everything found is downloaded.")
    ap.add_argument("--all", action="store_true", help="with --mod: download everything anyway, not only gaps")
    ap.add_argument("--forms", choices=("mega", "all", "none"), default="mega",
                    help="which non-gender forms to keep: Mega+Primal (default), every form, or none")
    ap.add_argument("--max-dex", type=int, default=721)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--delay", type=float, default=0.15, help="seconds each worker waits between requests")
    ap.add_argument("--no-scrape", action="store_true", help="do not read the index pages; guess names only")
    ap.add_argument("--list-only", action="store_true", help="show what would be downloaded, download nothing")
    ap.add_argument("--base-url", default=BASE_URL, help=argparse.SUPPRESS)
    a = ap.parse_args()

    slug_map = build_slug_map()
    have = meta_front_stems(a.mod) if (a.mod and not a.all) else set()
    if a.mod and not a.all:
        print(f"Gap-fill mode: {len(have)} front stems already have geometry in {a.mod}/data")

    # wanted[(dex, variant)] = candidate site slugs, most likely first
    wanted: dict[tuple[int, str], list[str]] = {}
    scraped: set[str] = set()
    if not a.no_scrape:
        print("Reading sprite index pages...")
        scraped = scrape_index(a.base_url)
    scrape_ok = len(scraped) >= 100
    unmapped = []
    for slug in sorted(scraped):
        c = classify(slug, slug_map)
        if c is None:
            unmapped.append(slug)
            continue
        dex, variant = c
        if dex <= a.max_dex and keep_form(variant, a.forms):
            wanted.setdefault((dex, variant), [])
            if slug not in wanted[(dex, variant)]:
                wanted[(dex, variant)].append(slug)
    if not scrape_ok:
        print("Index pages gave no usable list; guessing file names (404s are expected).")
    # Guesses: every species' default art and every known Mega/Primal if the index did not name it; when the
    # index is unusable, also female art.
    for dex in range(1, a.max_dex + 1):
        guesses = base_slugs(dex)
        if (dex, "") not in wanted:
            wanted[(dex, "")] = list(guesses)
        if not scrape_ok:
            wanted.setdefault((dex, "f"), [g + "-f" for g in guesses[:2]])
        if a.forms != "none":  # the index may not list every Mega; probing a known one that is absent is one 404
            for form in MEGA_FORMS.get(dex, []):
                wanted.setdefault((dex, form), [f"{g}-{sp}" for g in guesses[:2] for sp in FORM_SPELLINGS[form]])

    todo = {k: v for k, v in sorted(wanted.items()) if a.all or not a.mod or not covered(have, *k)}
    print(f"{len(todo)} sprite entries to fetch ({len(wanted)} known, {len(wanted) - len(todo)} already in the mod)")
    if a.list_only:
        for (dex, variant), slugs in todo.items():
            print(f"  {dex:03d} {variant or 'default':<8} {NAMES[dex - 1]:<12} {slugs[0]}")
        return 0

    a.out.mkdir(parents=True, exist_ok=True)
    stats = {"ok": 0, "skipped": 0, "missing": 0, "error": 0}
    missing: list[str] = []

    def fetch_one(item):
        (dex, variant), slugs = item
        used = None
        results = {}
        for color, folder in (("n", "normal-sprite"), ("s", "shiny-sprite")):
            dest = a.out / out_name(dex, color, variant)
            if dest.is_file() and dest.stat().st_size > 6 and dest.read_bytes()[:4] == b"GIF8":
                results[color] = "skipped"
                used = used or dest.name
                continue
            order = ([used] if used else []) + [s for s in slugs if s != used]
            got = None
            for slug in order:
                time.sleep(a.delay)
                data = http_get(f"{a.base_url}/images/{folder}/{slug}.gif")
                if data and data[:4] == b"GIF8":
                    got = (slug, data)
                    break
            if got:
                tmp = dest.with_suffix(".part")
                tmp.write_bytes(got[1])
                tmp.replace(dest)
                used = got[0]
                results[color] = "ok"
            else:
                results[color] = "missing"
        return dex, variant, results

    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.workers)) as pool:
        futs = {pool.submit(fetch_one, it): it for it in todo.items()}
        for fut in concurrent.futures.as_completed(futs):
            (dex, variant), _ = futs[fut]
            try:
                _, _, res = fut.result()
            except Exception as e:  # noqa: BLE001
                stats["error"] += 1
                missing.append(f"{dex:03d} {variant or 'default'} {NAMES[dex - 1]}: ERROR {e}")
                continue
            for color, r in res.items():
                stats[r] += 1
                if r == "missing":
                    missing.append(f"{dex:03d} {variant or 'default'} {NAMES[dex - 1]} ({'normal' if color == 'n' else 'shiny'})")
            done += 1
            if done % 25 == 0 or done == len(todo):
                print(f"[{done:4d}/{len(todo)}] ok={stats['ok']} skipped={stats['skipped']} "
                      f"missing={stats['missing']} error={stats['error']}", flush=True)

    report = a.out / "fetch_report.txt"
    lines = [f"downloaded={stats['ok']} already_present={stats['skipped']} not_found={stats['missing']} errors={stats['error']}"]
    if unmapped:
        lines += ["", "Index names that matched no National Dex entry (ignored):"] + [f"  {u}" for u in unmapped]
    if missing:
        lines += ["", "Not downloaded:"] + [f"  {m}" for m in sorted(missing)]
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n" + lines[0])
    if missing:
        print(f"{len(missing)} entries not found - see {report}")
    print(f"Next: python tools/import_hd_pokemon.py {a.out} --target <mod folder> --extra --fit-height")
    return 0


if __name__ == "__main__":
    sys.exit(main())
