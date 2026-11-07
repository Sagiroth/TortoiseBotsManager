#!/usr/bin/env python3
"""Draw the addon's interface glyphs into Media/*.tga.

    python3 tools/make_media.py

White shapes on a transparent background, 32x32 (power of two, as the 1.12
client needs). The addon tints them with SetVertexColor, so one file serves
every colour. Drawn at 8x and scaled down for clean edges. Re-run after
changing a shape; the .tga files are committed and shipped.
"""
import os

from PIL import Image, ImageDraw

SIZE = 32
SS = 8  # supersampling
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media")


def canvas():
    im = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    return im, ImageDraw.Draw(im)


def save(mask, name):
    mask = mask.resize((SIZE, SIZE), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    out.putalpha(mask)
    os.makedirs(ROOT, exist_ok=True)
    out.save(os.path.join(ROOT, name + ".tga"), compression=None, orientation=1)


def p(v):
    return v * SS


def line(d, a, b, w):
    d.line([p(a[0]), p(a[1]), p(b[0]), p(b[1])], fill=255, width=int(w * SS))
    r = w * SS / 2
    for x, y in (a, b):
        d.ellipse([p(x) - r, p(y) - r, p(x) + r, p(y) + r], fill=255)


def close():
    im, d = canvas()
    line(d, (10, 10), (22, 22), 3.2)
    line(d, (22, 10), (10, 22), 3.2)
    save(im, "close")


def check():
    im, d = canvas()
    line(d, (8, 16.5), (13.5, 22), 3.6)
    line(d, (13.5, 22), (24, 10), 3.6)
    save(im, "check")


def search():
    im, d = canvas()
    w = 3.0 * SS
    d.ellipse([p(7), p(7), p(20), p(20)], outline=255, width=int(w))
    line(d, (18.5, 18.5), (25, 25), 3.4)
    save(im, "search")


def gradient():
    # Vertical fade: opaque at the top, clear at the bottom.
    mask = Image.new("L", (SIZE, SIZE), 0)
    for y in range(SIZE):
        a = int(255 * (1 - y / (SIZE - 1)))
        for x in range(SIZE):
            mask.putpixel((x, y), a)
    out = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    out.putalpha(mask)
    os.makedirs(ROOT, exist_ok=True)
    out.save(os.path.join(ROOT, "gradient.tga"), compression=None, orientation=1)


if __name__ == "__main__":
    close()
    check()
    search()
    gradient()
    print("Media written to", os.path.normpath(ROOT))
