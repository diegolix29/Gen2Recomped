#!/usr/bin/env python3
"""Regenerate every platform's app icon from icons/icon.png.

icons/icon.png (square, transparent corners) is the one source of truth.
Replace it, run `python3 tools/make_icons.py`, and commit what changes:

  icons/icon.ico                        Windows .exe (patched in by scripts/build.sh)
  icons/icon.icns                       macOS app bundle
  icons/icon-opaque.png                 iOS app icon source (iOS wants no alpha)
  assets/logo/icon-window.png           the window/taskbar icon conf.lua sets
  mobile/android/.../drawable-*/love.png  Android launcher icon
  ports/switch/assets/icon.jpg          Switch .nro and OTA launcher icon
  ports/uwp/Assets/*.png                Xbox UWP tiles and splash

The MSIX tiles and the Linux AppImage icons are made from icon.png at build
time, so they need nothing here.  icons/ sits outside assets/ on purpose:
every game.love packer zips all of assets/, and only the window icon belongs
in the game itself.  Needs only Pillow.
"""

import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "icons", "icon.png")
# the dark violet behind the logo wherever a platform forbids transparency
BACKGROUND = (13, 10, 31)

ANDROID = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# UWP asset: (width, height), sized as the files the project already ships
UWP = {
    "Square44x44Logo.png": (44, 44),
    "StoreLogo.png": (50, 50),
    "SmallTile.png": (71, 71),
    "Square150x150Logo.png": (150, 150),
    "LargeTile.png": (310, 310),
    "WideTile.png": (310, 150),
    "SplashScreen.png": (620, 300),
}


def path(*parts):
    return os.path.join(ROOT, *parts)


def square(image, size):
    return image.resize((size, size), Image.LANCZOS)


def opaque(image):
    flat = Image.new("RGBA", image.size, BACKGROUND + (255,))
    flat.alpha_composite(image)
    return flat.convert("RGB")


def fit(image, width, height):
    """The icon centred on a transparent canvas, as large as fits."""
    side = min(width, height)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    canvas.alpha_composite(square(image, side), ((width - side) // 2, (height - side) // 2))
    return canvas


def main():
    if not os.path.isfile(SOURCE):
        sys.exit(f"missing {SOURCE}")
    with Image.open(SOURCE) as loaded:
        icon = loaded.convert("RGBA")
    if icon.width != icon.height:
        sys.exit(f"{SOURCE} must be square, got {icon.width}x{icon.height}")
    if icon.width < 1024:
        print(f"warning: {SOURCE} is {icon.width}px; 1024px or larger looks best", file=sys.stderr)
    icon = square(icon, 1024)

    written = []

    def save(image, *parts, **options):
        target = path(*parts)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        image.save(target, **options)
        written.append(os.path.relpath(target, ROOT))

    save(icon, "icons", "icon.ico", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    save(icon, "icons", "icon.icns")
    save(opaque(icon), "icons", "icon-opaque.png", optimize=True)
    save(square(icon, 256), "assets", "logo", "icon-window.png", optimize=True)
    for density, size in ANDROID.items():
        save(square(icon, size), "mobile", "android", "app", "src", "main", "res",
             f"drawable-{density}", "love.png", optimize=True)
    save(opaque(square(icon, 256)), "ports", "switch", "assets", "icon.jpg", quality=95)
    for name, (width, height) in UWP.items():
        save(fit(icon, width, height), "ports", "uwp", "Assets", name, optimize=True)

    print("\n".join(written))


if __name__ == "__main__":
    main()
