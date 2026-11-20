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
            iPhone 17 Pro Max in dark mode with the status bar set to 9:41:
                1.3: home.png (Home), styles.png (Styles, with the rotation
                     strip showing), customize.png (the Customize sheet)
                1.2: main.png, rotation.png, editor.png

Usage:
    python3 Scripts/compose_screenshots.py WIDGETS CAPTURES OUT [1.3|1.2]

The set defaults to 1.3. Needs Pillow and the San Francisco fonts that ship
with macOS.
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


def stack(img, top, items, gap):
    """Centers rows of sprites in the space below `top`, each row centered too."""
    total = sum(row[0].height for row in items) + gap * (len(items) - 1)
    y = top + (H - top - total) / 2
    for sprites in items:
        row_width = sum(s.width for s in sprites) + gap * (len(sprites) - 1)
        x = (W - row_width) / 2
        for s in sprites:
            shadowed(img, s, x, y)
            x += s.width + gap
        y += sprites[0].height + gap
    return y - gap


class Sources:
    """Loads widget cards and captures, and saves finished images."""

    def __init__(self, widgets, captures, out):
        self.widgets, self.captures, self.out = widgets, captures, out
        os.makedirs(out, exist_ok=True)

    def widget(self, name, width):
        im = Image.open(os.path.join(self.widgets, f"{name}.png")).convert("RGBA")
        return im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)

    def capture(self, name):
        return Image.open(os.path.join(self.captures, f"{name}.png"))

    def save(self, img, name):
        img.convert("RGB").save(os.path.join(self.out, f"{name}.png"), optimize=True)
        print("saved", name)


# 1.3: darker, with one soft glow in the colors of the look on show, a
# lighter headline weight and a slimmer phone.

INK = (255, 255, 255)
SOFT = (168, 168, 176)


def headline_13(img, title, subtitle, y=210):
    """Centered title and subtitle. Returns the y just below them."""
    d = ImageDraw.Draw(img)
    tf = font(122, "Bold")
    for line in title.split("\n"):
        w = d.textlength(line, font=tf)
        assert w <= W - 120, f"title too wide: {line}"
        d.text(((W - w) / 2, y), line, font=tf, fill=INK)
        y += 140
    sf = font(50, "Regular")
    y += 34
    for line in subtitle.split("\n"):
        w = d.textlength(line, font=sf)
        assert w <= W - 120, f"subtitle too wide: {line}"
        d.text(((W - w) / 2, y), line, font=sf, fill=SOFT)
        y += 66
    return y


def phone_13(screen, width):
    """A screen in a slim iPhone frame: a thin bezel inside a brushed rim."""
    rim, bezel = 7, 18
    inset = rim + bezel
    sw = width - inset * 2
    sh = round(screen.height * sw / screen.width)
    screen = screen.convert("RGBA").resize((sw, sh), Image.LANCZOS)
    radius = int(sw * 0.128)
    fh = sh + inset * 2
    outer = radius + inset
    # The rim: light at the top, darker toward the bottom, like metal.
    line = Image.new("RGB", (1, 256))
    for y in range(256):
        k = y / 255
        line.putpixel((0, y), tuple(int(a + (b - a) * k) for a, b in zip((112, 112, 120), (44, 44, 50))))
    metal = line.resize((width, fh), Image.BICUBIC).convert("RGBA")
    shape = Image.new("L", (width, fh), 0)
    ImageDraw.Draw(shape).rounded_rectangle((0, 0, width - 1, fh - 1), outer, fill=255)
    frame = Image.new("RGBA", (width, fh), (0, 0, 0, 0))
    frame.paste(metal, (0, 0), shape)
    ImageDraw.Draw(frame).rounded_rectangle(
        (rim, rim, width - 1 - rim, fh - 1 - rim), outer - rim, fill=(6, 6, 8, 255)
    )
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius, fill=255)
    frame.paste(screen, (inset, inset), mask)
    return frame


def marks_legend(img, y):
    """The Marks symbols with what each one means, as in the Marks board."""
    items = [("dot", "Pushed"), ("x", "Missed"), ("F", "Freeze"), ("R", "Rest day"), ("today", "Today")]
    d = ImageDraw.Draw(img)
    col, tile = 236, 100
    x0 = (W - col * len(items)) / 2
    label = font(40, "Medium")
    letter = font(54, "Bold")
    for i, (kind, text) in enumerate(items):
        cx = x0 + col * i + col / 2
        box = (cx - tile / 2, y, cx + tile / 2, y + tile)
        d.rounded_rectangle(box, 20, fill=(30, 30, 33))
        mx, my = cx, y + tile / 2
        if kind in ("dot", "today"):
            d.ellipse((mx - 21, my - 21, mx + 21, my + 21), fill=(242, 242, 242))
        if kind == "today":
            d.rounded_rectangle((box[0] - 9, box[1] - 9, box[2] + 9, box[3] + 9), 27, outline=(242, 242, 242), width=6)
        if kind == "x":
            for a, b in (((-17, -17), (17, 17)), ((-17, 17), (17, -17))):
                d.line((mx + a[0], my + a[1], mx + b[0], my + b[1]), fill=(142, 142, 147), width=7)
        if kind in ("F", "R"):
            color = (174, 174, 178) if kind == "F" else (142, 142, 147)
            w = d.textlength(kind, font=letter)
            d.text((mx - w / 2, my - 33), kind, font=letter, fill=color)
        w = d.textlength(text, font=label)
        d.text((cx - w / 2, y + tile + 34), text, font=label, fill=(206, 206, 212))
    return y + tile + 34 + 48


def layout_13(src):
    dark = (0x0D0D12, 0x040405)

    def phone_page(name, glows, title, subtitle, capture):
        img = background(*dark, glows)
        top = headline_13(img, title, subtitle)
        p = phone_13(src.capture(capture), 1010)
        shadowed(img, p, (W - p.width) / 2, top + 64, blur=60, opacity=190, offset=30)
        src.save(img, name)

    # 1. Hero: the widgets, big and filling their frames.
    img = background(*dark, [(0x2DD4BF, 1120, 980, 560, 72), (0x8B5CF6, 240, 1500, 560, 64), (0xF97316, 1100, 2500, 520, 52)])
    top = headline_13(img, "Your GitHub streak,\non your Home Screen", "Bold widgets that fill the frame,\nin every size.")
    stack(img, top + 20, [
        [src.widget("aurora-graph-large", 1120)],
        [src.widget("ember-streak-small", 532), src.widget("marks-week-small", 532)],
    ], 56)
    src.save(img, "01-home-screen-widgets")

    # 2. Six looks, Marks included, in small and medium.
    img = background(*dark, [(0x22C55E, 200, 1000, 560, 60), (0x8B5CF6, 1150, 1900, 560, 60), (0xF59E0B, 250, 2600, 480, 44)])
    top = headline_13(img, "Six looks,\nevery size", "Classic, Aurora, Ember, Terminal,\nPaper and Marks.")
    stack(img, top + 10, [
        [src.widget("classic-graph-medium", 1000)],
        [src.widget("aurora-week-small", 474), src.widget("ember-graph-small", 474)],
        [src.widget("terminal-streak-small", 474), src.widget("paper-week-small", 474)],
        [src.widget("marks-graph-medium", 1000)],
    ], 40)
    src.save(img, "02-six-looks")

    # 3. The streak sheet: the run on a calendar, rest days and the freeze.
    phone_page("03-every-day-of-your-streak", [(0x22C55E, 1120, 1100, 560, 66), (0x38BDF8, 180, 2300, 600, 60)],
               "See every day\nof your streak", "Your run on a calendar, with rest days,\nfreezes and today marked.", "streak")

    # 4. The year sheet: totals and every month.
    phone_page("04-your-year", [(0x14B8A6, 1150, 1100, 560, 64), (0x22C55E, 160, 2350, 600, 60)],
               "Your year,\nmonth by month", "Look back at any year\nsince you joined GitHub.", "year")

    # 5. The Look picker, with four looks in the rotation.
    phone_page("05-new-look-every-day", [(0x2DD4BF, 1150, 1100, 560, 70), (0x8B5CF6, 150, 2300, 600, 70)],
               "A new look\nevery day", "Pick the looks you love.\nThey take turns at midnight.", "styles")

    # 6. The Customize sheet.
    phone_page("06-make-it-yours", [(0xFF7A59, 1120, 1150, 540, 70), (0xEC4899, 180, 2300, 600, 76)],
               "Make it yours", "Pick a shape and a color,\nthen save it as your own look.", "customize")

    # 7. Marks up close, with what the symbols mean.
    img = background(*dark, [(0x94A3B8, 1080, 1150, 600, 46), (0x3B82F6, 220, 2350, 560, 54)])
    top = headline_13(img, "Every day,\nmarked", "A symbol for every day, so you see\nwhat happened, not just how much.")
    large = src.widget("marks-graph-large", 1120)
    legend_h = 100 + 34 + 48
    gap = 110
    y = top + (H - top - large.height - gap - legend_h) / 2
    shadowed(img, large, (W - large.width) / 2, y)
    marks_legend(img, y + large.height + gap)
    src.save(img, "07-every-day-marked")

    # 8. Rest days and the freeze.
    img = background(*dark, [(0x38BDF8, 1120, 1000, 560, 66), (0x22C55E, 200, 2350, 560, 56)])
    top = headline_13(img, "Rest without\nlosing your streak", "Rest days and a monthly freeze\nkeep your streak alive.")
    stack(img, top + 20, [[src.widget("classic-week-large", 1120)], [src.widget("ember-graph-medium", 1120)]], 60)
    src.save(img, "08-rest-days")

    # 9. Home.
    phone_page("09-at-a-glance", [(0x22C55E, 1120, 1100, 540, 62), (0x14B8A6, 180, 2350, 600, 62)],
               "Everything\nat a glance", "Today, your streak and your year,\none tap away.", "home")


def layout_12(src):
    widget, capture, save = src.widget, src.capture, src.save

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


def main(widgets, captures, out, version="1.3"):
    layouts = {"1.3": layout_13, "1.2": layout_12}
    if version not in layouts:
        sys.exit(f"unknown set {version}, pick one of {', '.join(layouts)}")
    layouts[version](Sources(widgets, captures, out))


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    main(*sys.argv[1:])
