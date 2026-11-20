#!/usr/bin/env python3
"""Lays out the App Store creative assets: the product page header and the
search results image. Both use the same widget cards as the screenshots.

Sizes come from Apple's creative assets specifications:
  header   3840 x 1646 (21:9), art safe area 1646 x 661 at (1097, 493)
  search   3840 x 2560 (3:2),  art safe area 2168 x 1030 at (836, 765)
No alpha, so both are saved as plain RGB PNGs.

The key art sits inside the safe area, sharp and lit. Other looks fill the
rest of the canvas, dimmed, so they add depth on wide screens and can be
cropped away on narrow ones without losing anything.

Usage:
    python3 Scripts/compose_creative.py WIDGETS OUT [--guides]

WIDGETS is the `store` folder from testRenderStoreWidgets (see
compose_screenshots.py). --guides also writes copies with the safe area
outlined, for checking.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

HEADER = (3840, 1646, (1097, 493, 1646, 661))
SEARCH = (3840, 2560, (836, 765, 2168, 1030))


def rgb(value):
    return ((value >> 16) & 255, (value >> 8) & 255, value & 255)


def background(w, h, top, bottom, glows):
    """Vertical gradient plus soft colored glows: (hex, cx, cy, radius, alpha)."""
    line = Image.new("RGB", (1, 256))
    t, b = rgb(top), rgb(bottom)
    for y in range(256):
        k = y / 255
        line.putpixel((0, y), tuple(int(t[i] + (b[i] - t[i]) * k) for i in range(3)))
    img = line.resize((w, h), Image.BICUBIC).convert("RGBA")
    for color, cx, cy, r, a in glows:
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse((cx - r, cy - r, cx + r, cy + r), fill=rgb(color) + (a,))
        img = Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(r * 0.55)))
    return img


def card(widgets, name, width, dim=0.0, soften=0):
    im = Image.open(os.path.join(widgets, f"{name}.png")).convert("RGBA")
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    if soften:
        # Pad first so the blur doesn't clip at the card's edges.
        padded = Image.new("RGBA", (im.width + soften * 6, im.height + soften * 6), (0, 0, 0, 0))
        padded.paste(im, (soften * 3, soften * 3))
        im = padded.filter(ImageFilter.GaussianBlur(soften))
    if dim:
        r, g, b, a = im.split()
        rgb_part = Image.merge("RGB", (r, g, b)).point(lambda v: int(v * (1 - dim)))
        im = Image.merge("RGBA", (*rgb_part.split(), a))
    return im


def place(img, sprite, x, y, blur=36, opacity=170, offset=22):
    """Pastes a card with a soft drop shadow. Off-canvas parts are cropped."""
    pad = blur * 3
    shadow = Image.new("RGBA", (sprite.width + pad * 2, sprite.height + pad * 2), (0, 0, 0, 0))
    mask = sprite.split()[-1].point(lambda v: v * opacity // 255)
    shadow.paste((0, 0, 0, 255), (pad, pad), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    layer.paste(shadow, (int(x - pad), int(y - pad + offset)))
    layer.paste(sprite, (int(x), int(y)), sprite)
    return Image.alpha_composite(img, layer)


def halo(img, box, color, alpha=90):
    """A wide glow behind the key art, in the hero look's colors."""
    x0, y0, x1, y1 = box
    spread = (x1 - x0) * 0.18
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        (x0 - spread, y0 - spread, x1 + spread, y1 + spread), spread, fill=rgb(color) + (alpha,)
    )
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(spread * 0.9)))


def save(img, out, name, safe=None, guides=False):
    img.convert("RGB").save(os.path.join(out, f"{name}.png"), optimize=True)
    print("saved", name, img.size)
    if guides and safe:
        g = img.convert("RGB")
        x, y, w, h = safe
        ImageDraw.Draw(g).rectangle((x, y, x + w, y + h), outline=(255, 59, 48), width=8)
        g.save(os.path.join(out, f"{name}-guides.png"))


def header(widgets, out, guides):
    w, h, safe = HEADER
    img = background(w, h, 0x0B0D14, 0x040405, [
        (0x2DD4BF, 1700, 700, 700, 46), (0x8B5CF6, 2250, 950, 700, 50),
        (0xF97316, 450, 900, 600, 34), (0x22C55E, 3400, 800, 600, 34),
    ])
    sx, sy, sw, sh = safe
    cy = sy + sh / 2

    # A carousel of looks, bleeding off both edges. The ones further out
    # are dimmer, so the eye lands on the center.
    gap = 72
    hero = card(widgets, "aurora-graph-medium", 1290)
    hx = (w - hero.width) / 2
    hy = cy - hero.height / 2
    small = 620
    sy0 = cy - small / 2
    left = [("ember-streak-small", 0.28), ("marks-week-small", 0.55)]
    right = [("classic-graph-small", 0.28), ("paper-week-small", 0.55)]
    x = hx - gap - small
    for name, dim in left:
        img = place(img, card(widgets, name, small, dim), x, sy0)
        x -= small + gap
    x = hx + hero.width + gap
    for name, dim in right:
        img = place(img, card(widgets, name, small, dim), x, sy0)
        x += small + gap

    img = halo(img, (hx, hy, hx + hero.width, hy + hero.height), 0x5EEAD4, 70)
    img = place(img, hero, hx, hy, blur=44, opacity=200, offset=28)
    save(img, out, "header", safe, guides)


def search(widgets, out, guides):
    w, h, safe = SEARCH
    img = background(w, h, 0x0B0D14, 0x040405, [
        (0x2DD4BF, 1500, 1150, 760, 44), (0xF97316, 2700, 1400, 700, 40),
        (0x8B5CF6, 700, 400, 700, 30), (0x22C55E, 3300, 2300, 700, 30),
    ])
    sx, sy, sw, sh = safe

    # The key art: the graph and the big streak, side by side.
    gap = 76
    hero = card(widgets, "aurora-graph-medium", 1340)
    side = card(widgets, "ember-streak-small", hero.height)
    row = hero.width + gap + side.width
    x0 = sx + (sw - row) / 2
    y0 = sy + (sh - hero.height) / 2

    # A dim wall of the other looks around it, cropped by the edges.
    wall_gap = 64
    tile = 560
    medium = round(tile * 2 + wall_gap)
    rows = [
        (y0 - wall_gap - tile, [("terminal-graph-small", tile), ("classic-graph-medium", medium),
                                ("aurora-streak-small", tile), ("marks-graph-medium", medium), ("ember-week-small", tile)]),
        (y0 + hero.height + wall_gap + 12, [("marks-week-small", tile), ("ember-graph-medium", medium),
                                            ("classic-week-small", tile), ("terminal-streak-small", tile),
                                            ("terminal-graph-medium", medium)]),
    ]
    for y, cards in rows:
        total = sum(width for _, width in cards) + wall_gap * (len(cards) - 1)
        x = (w - total) / 2
        for name, width in cards:
            img = place(img, card(widgets, name, width, 0.66, soften=5), x, y, opacity=110)
            x += width + wall_gap
    # Two more on each side of the key art, on its own row.
    for name, x in (("classic-graph-small", x0 - wall_gap - tile), ("marks-streak-small", x0 + row + wall_gap)):
        img = place(img, card(widgets, name, tile, 0.66, soften=5), x, y0 + (hero.height - tile) / 2, opacity=110)

    img = halo(img, (x0, y0, x0 + row, y0 + hero.height), 0x5EEAD4, 60)
    img = place(img, hero, x0, y0, blur=44, opacity=200, offset=28)
    img = place(img, side, x0 + hero.width + gap, y0, blur=44, opacity=200, offset=28)
    save(img, out, "search-results", safe, guides)


def main(widgets, out, guides=False):
    os.makedirs(out, exist_ok=True)
    header(widgets, out, guides)
    search(widgets, out, guides)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--guides"]
    if len(args) != 2:
        sys.exit(__doc__)
    main(*args, guides="--guides" in sys.argv)
