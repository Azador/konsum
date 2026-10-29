#!/usr/bin/env python3
"""Erzeugt die App-Icons aller Plattformen aus icon/Icon.png.

Die Vorlage ist ein grünes abgerundetes Quadrat auf Weiß mit einem Zettel
darauf. Daraus entstehen:
- abgerundet mit transparenten Ecken (Web, Linux, ältere Android-Versionen),
- randlos (iOS rundet selbst ab),
- verkleinert auf grünem Grund für runde Masken (Android adaptiv,
  Web „maskable“), damit der Zettel nicht abgeschnitten wird.

Aufruf (aus app/): python3 tool/make_icons.py   (braucht Pillow)
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

app = Path(__file__).resolve().parent.parent
src = Image.open(app / "icon/Icon.png").convert("RGB")

# Grünes Quadrat: alles, was nicht zum weißen Rand gehört.
gray = src.convert("L").point(lambda v: 255 if v > 235 else 0)
outside = gray.copy()
for corner in [(0, 0), (src.width - 1, 0), (0, src.height - 1),
               (src.width - 1, src.height - 1)]:
    ImageDraw.floodfill(outside, corner, 128)
outside = outside.point(lambda v: 255 if v == 128 else 0)
square = ImageChops.invert(outside)
box = square.getbbox()
square = square.crop(box)
src = src.crop(box)
size = src.width

# Grünverlauf der Vorlage (oben links heller), zum Auffüllen der Ecken und
# als Hintergrund.
TOP_LEFT, BOTTOM_RIGHT = (96, 133, 112), (82, 123, 100)


def gradient(n):
    g = Image.new("RGB", (n, n))
    px = g.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            px[x, y] = tuple(round(a + (b - a) * t)
                             for a, b in zip(TOP_LEFT, BOTTOM_RIGHT))
    return g


# Randlos: Ecken mit Grün füllen (Maske etwas verkleinert und weich, damit
# kein heller Saum bleibt).
inner = square.filter(ImageFilter.MinFilter(9)).filter(
    ImageFilter.GaussianBlur(3))
full = Image.composite(src, gradient(size), inner)

# Abgerundet mit transparenten Ecken.
rounded = src.convert("RGBA")
rounded.putalpha(square.filter(ImageFilter.GaussianBlur(1)))


def inset(n, scale, background):
    """Randloses Bild auf scale·n verkleinert, Rand weich ausgeblendet, auf
    background (None: transparent) der Größe n."""
    inner_n = round(n * scale)
    img = full.resize((inner_n, inner_n), Image.LANCZOS).convert("RGBA")
    fade = max(2, inner_n // 12)
    mask = Image.new("L", (inner_n, inner_n), 0)
    ImageDraw.Draw(mask).rectangle(
        [fade, fade, inner_n - 1 - fade, inner_n - 1 - fade], fill=255)
    img.putalpha(mask.filter(ImageFilter.GaussianBlur(fade / 2)))
    canvas = (gradient(n).convert("RGBA") if background
              else Image.new("RGBA", (n, n), (0, 0, 0, 0)))
    canvas.alpha_composite(img, ((n - inner_n) // 2, (n - inner_n) // 2))
    return canvas


def save(img, path, n, rgb=False):
    path = app / path
    path.parent.mkdir(parents=True, exist_ok=True)
    out = img if img.width == n else img.resize((n, n), Image.LANCZOS)
    (out.convert("RGB") if rgb else out).save(path, optimize=True)


# Android: adaptiv (108 dp, sichtbar ein Kreis von etwa 72 dp) und klassisch.
# Der Zettel reicht bis 47 % der Kantenlänge vom Mittelpunkt; 0,64 hält ihn
# im Kreis.
res = "android/app/src/main/res"
fg = inset(432 * 2, 0.64, background=False)
bg = gradient(432)
for dpi, f in [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3),
               ("xxxhdpi", 4)]:
    save(rounded, f"{res}/mipmap-{dpi}/ic_launcher.png", round(48 * f))
    save(fg, f"{res}/mipmap-{dpi}/ic_launcher_foreground.png", round(108 * f))
    save(bg, f"{res}/mipmap-{dpi}/ic_launcher_background.png", round(108 * f))
adaptive = app / res / "mipmap-anydpi-v26/ic_launcher.xml"
adaptive.parent.mkdir(exist_ok=True)
adaptive.write_text("""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
""")

# iOS: randlos, ohne Transparenz.
ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for f in (app / ios).glob("Icon-App-*.png"):
    pts, scale = f.stem.removeprefix("Icon-App-").split("@")
    n = round(float(pts.split("x")[0]) * int(scale.rstrip("x")))
    save(full, f"{ios}/{f.name}", n, rgb=True)

# Web: maskable mit Sicherheitszone (Kreis mit 80 % Durchmesser).
save(rounded, "web/favicon.png", 64)
save(rounded, "web/icons/Icon-192.png", 192)
save(rounded, "web/icons/Icon-512.png", 512)
save(full, "web/icons/apple-touch-icon.png", 180, rgb=True)
maskable = inset(1024, 0.86, background=True)
save(maskable, "web/icons/Icon-maskable-192.png", 192)
save(maskable, "web/icons/Icon-maskable-512.png", 512)

# Linux: Fenstersymbol.
save(rounded, "linux/runner/resources/app_icon.png", 256)
