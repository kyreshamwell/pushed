#!/usr/bin/env python3
"""Lays out the App Store screenshots: a dark gradient, a headline, and either
the real widgets or an app screen in a phone frame. 1320 x 2868, the 6.9"
size App Store Connect takes for every iPhone.

Inputs come from two places:
  widgets   Transparent widget cards drawn by the app's own code:
                TEST_RUNNER_PUSHED_RENDER_DIR=<dir> xcodebuild test \\
                    -only-testing:PushedTests/RenderPreviews/testRenderStoreWidgets ...
            writes them to <dir>/store.
  captures  Simulator screenshots of the demo build (-PushedDemo) on an
            iPhone 17 Pro Max with the status bar set to 9:41:
                main.png, rotation.png, editor.png

Usage:
    python3 Scripts/compose_screenshots.py WIDGETS CAPTURES OUT

Needs Pillow and the San Francisco fonts that ship with macOS.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868


def font(size, weight="Bold", rounded=False):
    path = "/System/Library/Fonts/SFNSRounded.ttf" if rounded else "/System/Library/Fonts/SFNS.ttf"
    f = ImageFont.truetype(path, size)
    f.set_variation_by_name(weight)
    return f


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def background(top, bottom, glows):
    """Vertical gradient plus soft colored glows: (hex, center x, center y, radius, alpha)."""
    line = Image.new("RGB", (1, 256))
    t, b = rgb(top), rgb(bottom)
    for y in range(256):
        k = y / 255
        line.putpixel((0, y), tuple(int(t[i] + (b[i] - t[i]) * k) for i in range(3)))
    img = line.resize((W, H), Image.BICUBIC).convert("RGBA")
    for color, cx, cy, r, a in glows:
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse((cx - r, cy - r, cx + r, cy + r), fill=rgb(color) + (a,))
        img = Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(r * 0.55)))
    return img


def headline(img, title, subtitle):
    """Centered title lines and a subtitle. Returns the y just below them."""
    d = ImageDraw.Draw(img)
    y = 190
    tf = font(118, "Heavy")
    for line in title.split("\n"):
        w = d.textlength(line, font=tf)
        assert w <= W - 80, f"title too wide: {line}"
        d.text(((W - w) / 2, y), line, font=tf, fill=(255, 255, 255))
        y += 136
    sf = font(52, "Medium")
    y += 26
    for line in subtitle.split("\n"):
        w = d.textlength(line, font=sf)
        assert w <= W - 80, f"subtitle too wide: {line}"
        d.text(((W - w) / 2, y), line, font=sf, fill=(255, 255, 255, 190))
        y += 66
    return y + 4


def shadowed(img, sprite, x, y, blur=40, opacity=150, offset=24):
    alpha = sprite.split()[-1]
    shadow = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda v: v * opacity // 255))
    pad = blur * 3
    canvas = Image.new("RGBA", (sprite.width + pad * 2, sprite.height + pad * 2), (0, 0, 0, 0))
    canvas.paste(shadow, (pad, pad))
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(canvas, (int(x - pad), int(y - pad + offset)))
    img.alpha_composite(sprite, (int(x), int(y)))


def phone(screen, width):
    """A screen in a simple iPhone frame: rounded screen, black bezel, thin rim."""
    sw = width - 52
    sh = round(screen.height * sw / screen.width)
    screen = screen.convert("RGBA").resize((sw, sh), Image.LANCZOS)
    radius = int(sw * 0.135)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius, fill=255)
    frame = Image.new("RGBA", (width, sh + 52), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        (0, 0, width - 1, sh + 51), radius + 26, fill=(12, 12, 14, 255), outline=(78, 78, 84, 255), width=5
    )
    frame.paste(screen, (26, 26), mask)
    return frame


def vibrant(im):
    """How the Lock Screen draws a widget: one white tint, with brightness
    turned into opacity. Black disappears, bright colors stay strong."""
    im = im.convert("RGBA")
    r, g, b, a = im.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    alpha = Image.eval(Image.composite(lum, Image.new("L", im.size, 0), a), lambda v: min(255, int(v * 1.15)))
    white = Image.new("RGBA", im.size, (255, 255, 255, 0))
    white.putalpha(alpha)
    return white


def main(widgets, captures, out):
    os.makedirs(out, exist_ok=True)

    def widget(name, width):
        im = Image.open(os.path.join(widgets, f"{name}.png")).convert("RGBA")
        return im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)

    def capture(name):
        return Image.open(os.path.join(captures, f"{name}.png"))

    def save(img, name):
        img.convert("RGB").save(os.path.join(out, f"{name}.png"), optimize=True)
        print("saved", name)

    def stack(img, top, items, gap):
        """Centers a column of (sprite, x offset) rows in the space below `top`."""
        total = sum(row[0].height for row in items) + gap * (len(items) - 1)
        y = top + (H - top - total) / 2
        for sprites in items:
            row_width = sum(s.width for s in sprites) + gap * (len(sprites) - 1)
            x = (W - row_width) / 2
            for s in sprites:
                shadowed(img, s, x, y)
                x += s.width + gap
            y += sprites[0].height + gap

    # 1. Hero: widgets in every layout, stacked like a home screen.
    img = background(0x07140C, 0x050807, [(0x1F9D4A, 250, 900, 520, 110), (0x3B82F6, 1150, 2300, 560, 70)])
    top = headline(img, "Your GitHub streak,\non your Home Screen", "Graph, big streak or this week, in every size.")
    stack(img, top, [
        [widget("classic-graph-medium", 1120)],
        [widget("aurora-week-medium", 1120)],
        [widget("ember-streak-small", 532), widget("terminal-week-small", 532)],
    ], 56)
    save(img, "01-home-screen-widgets")

    # 2. Rest days and the freeze.
    img = background(0x06131C, 0x04070A, [(0x38BDF8, 1100, 950, 540, 95), (0x22C55E, 200, 2350, 540, 70)])
    top = headline(img, "Take the weekend off", "Rest days and a monthly freeze\nkeep your streak alive.")
    stack(img, top, [[widget("classic-week-large", 1120)], [widget("ember-graph-medium", 1120)]], 60)
    save(img, "02-rest-days")

    # 3. Custom styles, one shape each.
    img = background(0x140B24, 0x07060D, [(0x7C3AED, 1100, 800, 560, 100), (0xEC4899, 200, 2400, 520, 70)])
    top = headline(img, "Shapes, colors,\nyour call", "Hearts, stars, hexagons and more.\nSave as many styles as you like.")
    shapes = ["heart", "hexagon", "star", "diamond", "dot", "square"]
    cards = [widget(f"custom-{s}-graph-small", 520) for s in shapes]
    stack(img, top, [cards[0:2], cards[2:4], cards[4:6]], 64)
    save(img, "03-your-styles")

    # 4. Daily Rotation.
    img = background(0x1A0A1F, 0x07050A, [(0xF472B6, 1100, 950, 520, 90), (0x2DD4BF, 150, 2350, 540, 80)])
    top = headline(img, "A new look every day", "Check the styles you love.\nThey take turns at midnight.")
    p = phone(capture("rotation"), 1000)
    shadowed(img, p, (W - p.width) / 2, top + 40, blur=50, opacity=170)
    save(img, "04-daily-rotation")

    # 5. The style editor.
    img = background(0x1B1036, 0x070A18, [(0xFF7A59, 1100, 1000, 520, 90), (0x6366F1, 150, 2300, 560, 90)])
    top = headline(img, "Design every detail", "Change anything and watch\nthe preview update live.")
    p = phone(capture("editor"), 1000)
    shadowed(img, p, (W - p.width) / 2, top + 40, blur=50, opacity=170)
    save(img, "05-design-your-own")

    # 6. The Lock Screen, built from the real widget drawings.
    img = background(0x0B1020, 0x05060A, [(0x6366F1, 1100, 900, 540, 90), (0x38BDF8, 200, 2400, 520, 70)])
    top = headline(img, "On your\nLock Screen too", "Your streak, before you even unlock.")
    screen = background(0x1E3A5F, 0x0B1426, [(0x7C3AED, 1000, 600, 700, 120), (0x0EA5E9, 300, 2200, 800, 110)])
    sd = ImageDraw.Draw(screen)
    inline = vibrant(widget("lock-inline", 640))
    screen.alpha_composite(inline, ((W - inline.width) // 2, 330))
    clock = font(420, "Semibold", rounded=True)
    cw = sd.textlength("9:41", font=clock)
    sd.text(((W - cw) / 2, 380), "9:41", font=clock, fill=(255, 255, 255, 235))
    circle = vibrant(widget("lock-circular", 300))
    rect = vibrant(widget("lock-rectangular", 680))
    gap = 60
    x = (W - circle.width - gap - rect.width) // 2
    y = 900
    disc = Image.new("RGBA", circle.size, (0, 0, 0, 0))
    ImageDraw.Draw(disc).ellipse((0, 0, circle.width - 1, circle.height - 1), fill=(255, 255, 255, 46))
    screen.alpha_composite(disc, (x, y))
    screen.alpha_composite(circle, (x, y))
    screen.alpha_composite(rect, (x + circle.width + gap, y + (circle.height - rect.height) // 2))
    sd.rounded_rectangle((W / 2 - 200, H - 90, W / 2 + 200, H - 74), 8, fill=(255, 255, 255, 200))
    # The Dynamic Island, where the real captures have it.
    sd.rounded_rectangle((W / 2 - 190, 44, W / 2 + 190, 158), 57, fill=(0, 0, 0, 255))
    p = phone(screen, 1000)
    shadowed(img, p, (W - p.width) / 2, top + 40, blur=50, opacity=170)
    save(img, "06-lock-screen")

    # 7. The app itself.
    img = background(0x061A12, 0x04080A, [(0x22C55E, 1100, 950, 520, 90), (0x14B8A6, 200, 2400, 540, 70)])
    top = headline(img, "Every day, at a glance", "Your streak, stats and days off\nin one place.")
    p = phone(capture("main"), 1000)
    shadowed(img, p, (W - p.width) / 2, top + 40, blur=50, opacity=170)
    save(img, "07-at-a-glance")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
