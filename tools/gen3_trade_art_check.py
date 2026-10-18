"""Check the in-game trade art addresses against the decompilation's sources.

    python tools/gen3_trade_art_check.py emerald <rom.gba> <pokeemerald dir>
    python tools/gen3_trade_art_check.py firered <rom.gba> <pokefirered dir>

src/import/Gen3TradeArt.lua reads the trade sequence's art at addresses taken
from pret's .sym files for the ROM-matching builds, and verifies each blob's
SHAPE at import time (LZ77 size, BGR555, tilemap bounds).  This goes one step
further, offline: every blob at those addresses is compared BYTE FOR BYTE with
what the decomp builds it from -- the .bin tilemaps as they are, the .pal
palettes through gbagfx's 8-to-5-bit rule, the indexed .png sheets cut into
4bpp/8bpp tiles in gbagfx's row-major order -- so the address table is proved
against the source rather than against itself.

Prints one line per asset and exits non-zero if any differ.
"""
import os
import re
import sys

from PIL import Image

# file offset, size, lz -- mirrors Gen3TradeArt.ROMS (keep the two in step)
TABLES = {
    'emerald': {
        'textboxPal': (0xC004E0, 0x40, True), 'textboxMap': (0xC00524, 0x1000, True),
        'textboxTiles': (0xC00000, 0x2000, True),
        'gba2Pal': (0xDD7300, 0x60, False), 'gbaGfx': (0xDD7360, 0x1400, False),
        'platformMap': (0x331F60, 0x1000, False), 'affineGfx': (0x332F60, 0x2800, False),
        'affineMap': (0x3358A0, 0x100, False), 'gbaMap': (0x3359A0, 0x1000, False),
        'closeupMap': (0x3379A0, 0x800, True), 'signalSendPal': (0x337AA0, 0x200, False),
        'signalRecvPal': (0x337CA0, 0x200, False), 'signalNonePal': (0x337EA0, 0x20, False),
        'signalGfx': (0x337EC0, 0x1800, True), 'signalMap': (0x338550, 0x800, True),
        'pokeballPal': (0x32DFA0, 0x20, False), 'pokeballGfx': (0x32DFC0, 0x600, False),
        'gbaPal': (0x3308E0, 0x20, False), 'linkMonPal': (0x330940, 0x20, False),
        'glowGfx': (0x330960, 0x200, False), 'shadowGfx': (0x330B60, 0x200, False),
        'gbaScreenGfx': (0x330F60, 0x1000, False), 'shadowCycle': (0x338EA4, 0x18, False),
        'ballGfx': (0xC0173C, 384, True), 'ballPal': (0xC017F8, 0x20, True),
        'particleGfx': (0xC1A490, 0x100, True), 'particlePal': (0xC1A564, 0x20, True),
    },
    'firered': {
        'textboxPal': (0xD004D8, 0x40, True), 'textboxMap': (0xD0051C, 0x1000, True),
        'textboxTiles': (0xD00000, 0x2000, True),
        'gba2Pal': (0xEAEA20, 0x60, False), 'gbaGfx': (0xEAEA80, 0x1400, False),
        'platformMap': (0x26601C, 0x1000, False), 'affineGfx': (0x26701C, 0x2800, False),
        'affineMap': (0x26995C, 0x100, False), 'gbaMap': (0x269A5C, 0x1000, False),
        'closeupMap': (0x26BA5C, 0x800, True), 'signalSendPal': (0x26BB5C, 0x200, False),
        'signalRecvPal': (0x26BD5C, 0x200, False), 'signalNonePal': (0x26BF5C, 0x20, False),
        'signalGfx': (0x26BF7C, 0x1800, True), 'signalMap': (0x26C60C, 0x800, True),
        'pokeballPal': (0x26205C, 0x20, False), 'pokeballGfx': (0x26207C, 0x600, False),
        'gbaPal': (0x26499C, 0x20, False), 'linkMonPal': (0x2649FC, 0x20, False),
        'glowGfx': (0x264A1C, 0x200, False), 'shadowGfx': (0x264C1C, 0x200, False),
        'gbaScreenGfx': (0x26501C, 0x1000, False), 'shadowCycle': (0x26CF60, 0x18, False),
        'ballGfx': (0xD01724, 384, True), 'ballPal': (0xD017E0, 0x20, True),
        'particleGfx': (0xD1A608, 0x100, True), 'particlePal': (0xD1A6DC, 0x20, True),
    },
}

# which decomp file each blob is built from
SOURCES = {
    'emerald': {
        'textboxPal': ('pal', 'graphics/battle_interface/textbox_0.pal'),
        'textboxMap': ('bin', 'graphics/battle_interface/textbox_map.bin'),
        'textboxTiles': ('4bpp', 'graphics/battle_interface/textbox.png'),
        'gba2Pal': ('pal', 'graphics/trade/gba_pal2.pal'),
        'gbaGfx': ('4bpp', 'graphics/trade/gba.png'),
        'platformMap': ('bin', 'graphics/trade/platform.bin'),
        'affineGfx': ('8bpp', 'graphics/trade/gba_affine.png'),
        'affineMap': ('bin', 'graphics/trade/gba_affine_map_wireless.bin'),
        'gbaMap': ('bin', 'graphics/trade/gba_map_wireless.bin'),
        'closeupMap': ('bin', 'graphics/trade/crossing_highlight_wireless.bin'),
        'signalSendPal': ('pal', 'graphics/trade/wireless_signal_send.pal'),
        'signalRecvPal': ('pal', 'graphics/trade/wireless_signal_receive.pal'),
        'signalNonePal': ('pal', 'graphics/trade/wireless_signal_none.pal'),
        'signalGfx': ('4bpp', 'graphics/trade/wireless_signal.png'),
        'signalMap': ('bin', 'graphics/trade/wireless_signal.bin'),
        'pokeballPal': ('pngpal', 'graphics/trade/pokeball.png'),
        'pokeballGfx': ('4bpp', 'graphics/trade/pokeball.png'),
        'gbaPal': ('pal', 'graphics/trade/gba.pal'),
        'linkMonPal': ('pal', 'graphics/trade/link_mon.pal'),
        'glowGfx': ('4bpp', 'graphics/trade/link_mon_glow.png'),
        'shadowGfx': ('4bpp', 'graphics/trade/link_mon_shadow.png'),
        'gbaScreenGfx': ('4bpp', 'graphics/trade/gba_screen.png'),
        'shadowCycle': ('pal', 'graphics/trade/link_mon_shadow.pal'),
        'ballGfx': ('4bpp', 'graphics/balls/poke.png'),
        'ballPal': ('pngpal', 'graphics/balls/poke.png'),
        'particleGfx': ('4bpp', 'graphics/battle_anims/sprites/particles.png'),
        'particlePal': ('pngpal', 'graphics/battle_anims/sprites/circle_impact.png'),
    },
    'firered': {
        'textboxPal': ('pal', 'graphics/battle_interface/textbox1.pal'),
        'textboxMap': ('bin', 'graphics/battle_interface/textbox.bin'),
        'textboxTiles': ('4bpp', 'graphics/battle_interface/textbox.png'),
        'gba2Pal': ('pal', 'graphics/trade/gba_pal2.pal'),
        'gbaGfx': ('4bpp', 'graphics/trade/gba.png'),
        'platformMap': ('bin', 'graphics/trade/shadow_map.bin'),
        'affineGfx': ('8bpp', 'graphics/trade/gba_affine.png'),
        'affineMap': ('bin', 'graphics/trade/gba_affine_map_wireless.bin'),
        'gbaMap': ('bin', 'graphics/trade/gba_map_wireless.bin'),
        'closeupMap': ('bin', 'graphics/trade/wireless_signal_closeup.bin'),
        'signalSendPal': ('pal', 'graphics/trade/wireless_signal_send.pal'),
        'signalRecvPal': ('pal', 'graphics/trade/wireless_signal_receive.pal'),
        'signalNonePal': ('pal', 'graphics/trade/black.pal'),
        'signalGfx': ('4bpp', 'graphics/trade/wireless_signal.png'),
        'signalMap': ('bin', 'graphics/trade/wireless_signal.bin'),
        'pokeballPal': ('pngpal', 'graphics/trade/pokeball.png'),
        'pokeballGfx': ('4bpp', 'graphics/trade/pokeball.png'),
        'gbaPal': ('pal', 'graphics/trade/gba.pal'),
        'linkMonPal': ('pal', 'graphics/trade/link_mon.pal'),
        'glowGfx': ('4bpp', 'graphics/trade/link_mon_glow.png'),
        'shadowGfx': ('4bpp', 'graphics/trade/link_mon_shadow.png'),
        'gbaScreenGfx': ('4bpp', 'graphics/trade/gba_screen.png'),
        # trade_scene.c spells sLinkMonShadow_Pal out as RGB() literals
        'shadowCycle': ('words', [(18, 24, 31)] * 3 + [(31, 31, 31)] * 3
                        + [(18, 24, 31)] * 3 + [(31, 31, 31)] * 3),
        'ballGfx': ('4bpp', 'graphics/interface/ball/poke.png'),
        'ballPal': ('pngpal', 'graphics/interface/ball/poke.png'),
        'particleGfx': ('4bpp', 'graphics/battle_anims/sprites/particles.png'),
        'particlePal': ('pngpal', 'graphics/battle_anims/sprites/circle_impact.png'),
    },
}


def lz77(rom, off):
    if rom[off] != 0x10:
        raise ValueError('no LZ77 header at %07X' % off)
    size = rom[off + 1] | rom[off + 2] << 8 | rom[off + 3] << 16
    out = bytearray()
    i = off + 4
    while len(out) < size:
        flags = rom[i]
        i += 1
        for b in range(8):
            if len(out) >= size:
                break
            if flags & (0x80 >> b):
                x = rom[i] << 8 | rom[i + 1]
                i += 2
                n, d = (x >> 12) + 3, (x & 0xFFF) + 1
                for _ in range(n):
                    out.append(out[-d])
            else:
                out.append(rom[i])
                i += 1
    return bytes(out)


def words(colours):
    out = bytearray()
    for r, g, b in colours:
        w = (r >> 3) | (g >> 3) << 5 | (b >> 3) << 10
        out += bytes((w & 0xFF, w >> 8))
    return bytes(out)


def jasc(path):
    lines = open(path).read().split('\n')
    n = int(lines[2])
    return words([tuple(int(v) for v in lines[3 + i].split()[:3]) for i in range(n)])


def tiles(path, bpp):
    im = Image.open(path)
    w, h = im.size
    if im.mode == 'P':
        px = im.load()
        index = lambda x, y: px[x, y]
    else:
        # gbagfx reads a greyscale sheet as indices from the darkest
        g = im.convert('L').load()
        index = lambda x, y: (255 - g[x, y]) // 17
    out = bytearray()
    for ty in range(h // 8):
        for tx in range(w // 8):
            for y in range(8):
                row = [index(tx * 8 + x, ty * 8 + y) for x in range(8)]
                if bpp == 8:
                    out += bytes(row)
                else:
                    out += bytes((row[x] & 15) | (row[x + 1] & 15) << 4 for x in range(0, 8, 2))
    return bytes(out)


def pngpal(path):
    im = Image.open(path)
    pal = im.getpalette()[:48]
    return words([tuple(pal[i:i + 3]) for i in range(0, 48, 3)])


def main():
    game, rom_path, decomp = sys.argv[1], sys.argv[2], sys.argv[3]
    rom = open(rom_path, 'rb').read()
    bad = 0
    for name, (off, size, lz) in TABLES[game].items():
        blob = lz77(rom, off) if lz else rom[off:off + size]
        if len(blob) != size:
            print('FAIL %-14s %07X: %d bytes, expected %d' % (name, off, len(blob), size))
            bad += 1
            continue
        src = SOURCES[game].get(name)
        if not src:
            print('size %-14s %07X: %d bytes (no decomp source compared)' % (name, off, size))
            continue
        kind, path = src
        if kind == 'words':
            want = words([(r << 3, g << 3, b << 3) for r, g, b in path])
        else:
            full = os.path.join(decomp, path)
            if kind == 'bin':
                want = open(full, 'rb').read()
            elif kind == 'pal':
                want = jasc(full)
            elif kind == 'pngpal':
                want = pngpal(full)
            else:
                want = tiles(full, 8 if kind == '8bpp' else 4)
        # a blob may be a prefix of what the source holds (the text box
        # palette is two banks of the file's one) or the other way round
        n = min(len(want), len(blob))
        ok = want[:n] == blob[:n]
        if not ok:
            bad += 1
        print('%s %-14s %07X %5d bytes vs %s (%d compared)' % (
            'ok  ' if ok else 'FAIL', name, off, size,
            path if isinstance(path, str) else 'literal', n))
    print('%s: %d mismatch(es)' % (game, bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
