#!/usr/bin/env python3
"""Store-page art: the game logo and captions over the promo shots.

  python3 tools/studio/sim.py run promo   # raw shots → assets/store/*.png
  python3 tools/store_art.py              # → assets/store/final/

Writes icon.png (512 x 512) and thumb_1..5.png (1920 x 1080) ready to upload
on the Creator Dashboard. Fonts come from the Roblox Studio install (Luckiest
Guy for the logo, Montserrat Black for captions, the game's own font), so
Studio must be installed. Needs Pillow.
"""

import math
import os
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE = os.path.join(ROOT, "assets", "store")
OUT = os.path.join(STORE, "final")
FONTS = "/Applications/RobloxStudio.app/Contents/Resources/content/fonts"
LOGO_FONT = os.path.join(FONTS, "LuckiestGuy-Regular.ttf")
CAPTION_FONT = os.path.join(FONTS, "Montserrat-Black.ttf")

INK = (35, 20, 70)            # outline and shadow
TOP, BOTTOM = (255, 236, 90), (255, 150, 30)   # logo fill gradient
RED = (230, 57, 70)

# shot, caption (None = the title card), caption position
THUMBS = [
    ("1_grid", None, None),
    ("2_ramp_jump", "JUMP RAMPS!", "left"),
    ("3_gap_jump", "SPRING OVER THE GAP!", "left"),
    ("4_ocean", "SAIL A SOFA!", "left"),
    ("5_sky", "FLY THE SKY!", "bottom"),
]


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        sys.exit("font missing: %s (install Roblox Studio)" % path)


def gradient(w, h, top, bottom):
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        g.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return g.resize((w, h))


def word_art(lines, sizes, stroke_k=0.11, depth_k=0.07, gap_k=0.0, fill=(TOP, BOTTOM)):
    """Centred lines of chunky text: gradient fill, dark outline, a solid
    drop 'extrusion' under it. Returns an RGBA image cropped to the text."""
    pad = int(max(sizes) * 0.4)
    fonts = [font(LOGO_FONT, s) for s in sizes]
    boxes = [f.getbbox(t) for f, t in zip(fonts, lines)]
    widths = [b[2] - b[0] for b in boxes]
    heights = [b[3] - b[1] for b in boxes]
    W = max(widths) + pad * 2
    H = sum(heights) + int(sum(sizes[1:]) * gap_k) + pad * 2
    mask_fill = Image.new("L", (W, H), 0)
    mask_out = Image.new("L", (W, H), 0)
    df, do = ImageDraw.Draw(mask_fill), ImageDraw.Draw(mask_out)
    y = pad
    for i, (t, f, b) in enumerate(zip(lines, fonts, boxes)):
        x = (W - widths[i]) // 2 - b[0]
        sw = max(2, int(sizes[i] * stroke_k))
        do.text((x, y - b[1]), t, font=f, fill=255, stroke_width=sw, stroke_fill=255)
        df.text((x, y - b[1]), t, font=f, fill=255)
        y += heights[i] + int(sizes[min(i + 1, len(sizes) - 1)] * gap_k)
    depth = max(3, int(max(sizes) * depth_k))
    img = Image.new("RGBA", (W, H + depth), (0, 0, 0, 0))
    ink = Image.new("RGBA", (W, H), INK + (255,))
    for d in range(depth, 0, -1):                    # extrusion
        img.paste(ink, (0, d), mask_out)
    img.paste(ink, (0, 0), mask_out)                 # outline
    img.paste(gradient(W, H, *fill).convert("RGBA"), (0, 0), mask_fill)
    # a thin white shine along the top of the letters
    shine = mask_fill.filter(ImageFilter.MinFilter(5))
    shine = Image.composite(Image.new("L", (W, H), 0), shine,
                            shine.transform((W, H), Image.AFFINE, (1, 0, 0, 0, 1, -max(2, sizes[0] // 30))))
    img.paste(Image.new("RGBA", (W, H), (255, 255, 255, 150)), (0, 0), shine)
    return img.crop(img.getbbox())


def logo(scale=1.0):
    return word_art(["CATASTROPHIC", "RIDE!"], [int(130 * scale), int(230 * scale)]).rotate(
        4, resample=Image.BICUBIC, expand=True)


def shadowed(img, blur=14, alpha=150, offset=(0, 10)):
    """img with a soft shadow under it (for pasting onto busy shots)."""
    sh = Image.new("RGBA", (img.width + blur * 4, img.height + blur * 4), (0, 0, 0, 0))
    a = img.split()[3].point(lambda v: v * alpha // 255)
    sh.paste((0, 0, 0, 255), (blur * 2 + offset[0], blur * 2 + offset[1]), a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    sh.alpha_composite(img, (blur * 2, blur * 2))
    return sh


def sticker(text, size=78, bg=RED, angle=-4):
    """A rotated label: white Montserrat Black on a coloured rounded card
    with a dark border."""
    f = font(CAPTION_FONT, size)
    b = f.getbbox(text)
    w, h = b[2] - b[0], b[3] - b[1]
    px, py = int(size * 0.55), int(size * 0.38)
    W, H = w + px * 2, h + py * 2
    border = max(4, size // 12)
    card = Image.new("RGBA", (W + border * 2, H + border * 2 + border * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    r = H // 3
    d.rounded_rectangle((0, border * 2, W + border * 2, H + border * 4), r + border, fill=INK + (255,))
    d.rounded_rectangle((0, 0, W + border * 2, H + border * 2), r + border, fill=INK + (255,))
    d.rounded_rectangle((border, border, W + border, H + border), r, fill=bg + (255,))
    d.text((border + px - b[0], border + py - b[1]), text, font=f, fill=(255, 255, 255),
           stroke_width=max(2, size // 22), stroke_fill=INK)
    return card.rotate(angle, resample=Image.BICUBIC, expand=True)


def pop(im, sat=1.18, con=1.06):
    return ImageEnhance.Contrast(ImageEnhance.Color(im).enhance(sat)).enhance(con)


def vignette(im, strength=0.35):
    w, h = im.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse((-w * 0.15, -h * 0.25, w * 1.15, h * 1.25), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(w // 8))
    dark = Image.new("RGB", (w, h), (10, 5, 30))
    return Image.composite(im, Image.blend(im, dark, strength), m)


def title_card(shot):
    im = vignette(pop(shot.convert("RGB")))
    # darken the top so the logo reads over sky and heads
    top = gradient(im.width, im.height, (20, 10, 50), (20, 10, 50)).convert("RGBA")
    a = Image.new("L", im.size, 0)
    for y in range(int(im.height * 0.55)):
        ImageDraw.Draw(a).line((0, y, im.width, y), fill=int(150 * (1 - y / (im.height * 0.55)) ** 1.5))
    im = Image.composite(top.convert("RGB"), im, a).convert("RGBA")
    lg = shadowed(logo(1.45))
    im.alpha_composite(lg, ((im.width - lg.width) // 2, 10))
    st = shadowed(sticker("GRAB JUNK • BUILD A RIDE • RACE!", 60, angle=2), blur=10)
    im.alpha_composite(st, ((im.width - st.width) // 2, im.height - st.height - 30))
    return im.convert("RGB")


def captioned(shot, caption, where="left"):
    im = pop(shot.convert("RGB")).convert("RGBA")
    st = shadowed(sticker(caption, 84), blur=10)
    im.alpha_composite(st, (40, 40) if where == "left" else (40, im.height - st.height - 40))
    lg = shadowed(logo(0.55), blur=8)
    y = im.height - lg.height - 10 if where == "left" else 10
    im.alpha_composite(lg, (im.width - lg.width - 20, y))
    return im.convert("RGB")


def icon(shot):
    s = 512
    im = pop(shot.convert("RGB").resize((s, s), Image.LANCZOS), sat=1.25)
    # light burst behind the rider
    burst = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(burst)
    cx, cy = s / 2, s * 0.42
    for i in range(16):
        a0, a1 = i * math.tau / 16, (i + 0.45) * math.tau / 16
        d.polygon([(cx, cy), (cx + math.cos(a0) * s, cy + math.sin(a0) * s),
                   (cx + math.cos(a1) * s, cy + math.sin(a1) * s)], fill=70)
    burst = burst.filter(ImageFilter.GaussianBlur(3))
    # only on the sky: blue pixels (the rider and the ride stay as they are)
    r, g, b = im.split()
    sky = Image.frombytes("L", (s, s), bytes(
        255 if (pb > pr + 40 and pb > 150) else 0
        for pr, pb in zip(r.tobytes(), b.tobytes()))).filter(ImageFilter.GaussianBlur(2))
    burst = Image.composite(burst, Image.new("L", (s, s), 0), sky)
    im = Image.composite(Image.new("RGB", (s, s), (255, 255, 255)), im, burst).convert("RGBA")
    word = shadowed(word_art(["RIDE!"], [112]).rotate(6, resample=Image.BICUBIC, expand=True), blur=8)
    im.alpha_composite(word, ((s - word.width) // 2, s - word.height + 8))
    return im.convert("RGB")


def main():
    os.makedirs(OUT, exist_ok=True)
    for i, (name, caption, where) in enumerate(THUMBS, 1):
        shot = Image.open(os.path.join(STORE, name + ".png")).resize((1920, 1080), Image.LANCZOS)
        out = title_card(shot) if caption is None else captioned(shot, caption, where)
        path = os.path.join(OUT, "thumb_%d.png" % i)
        out.save(path, optimize=True)
        print(os.path.relpath(path, ROOT))
    path = os.path.join(OUT, "icon.png")
    icon(Image.open(os.path.join(STORE, "icon.png"))).save(path, optimize=True)
    print(os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
