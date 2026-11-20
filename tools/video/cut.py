#!/usr/bin/env python3
"""Short gameplay videos (trailer cuts) from recorded Studio matches.

  python3 tools/studio/sim.py run record-forest record-ocean record-sky   # footage, one at a time
  python3 tools/video/cut.py sheets              # contact sheets of every take (pick moments)
  python3 tools/video/cut.py build               # every cut in tools/video/cuts.json
  python3 tools/video/cut.py build reel          # one cut
  python3 tools/video/cut.py build --clean reel  # reel-clean.mp4 keeps the
      big words (tag, title) and the end card, drops the small lines (sub);
      reel.srt has every line with its times, for CapCut: import the
      subtitles, restyle them, read them out with its TTS

Footage: reports/video/raw/<take>/ (NNN.mov pieces + take.json, written
by sim.py's "record" mode: the bot client's window only, never the desktop).
The screen must be awake and unlocked while recording.
Cuts: tools/video/cuts.json. A segment names a take and a time in it ("t",
seconds; `sheets` labels every 2 s), or is a card (store picture / colour
with text). Output: reports/video/<cut>.mp4 (git-ignored), silent H.264:
add music in the editor you post with.

Needs ffmpeg (on PATH, or `pip install imageio-ffmpeg`) and Pillow.
"""

import glob
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, "reports", "video", "raw")
OUT = os.path.join(ROOT, "reports", "video")
CUTS = os.path.join(os.path.dirname(__file__), "cuts.json")
FPS = 30
FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
FONT_BODY = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
# Korean cuts ("lang": "ko"): Apple SD Gothic Neo Bold (face 6 of the .ttc)
FONT_KO = ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 6)
SIZES = {"16x9": (1920, 1080), "9x16": (1080, 1920)}
# the 80s look (cuts with "look": "vhs"): titles, a script line, a TV's on-screen text
FONT_RETRO = ("/System/Library/Fonts/Supplemental/Futura.ttc", 4)       # Futura Condensed ExtraBold
FONT_RETRO_BODY = ("/System/Library/Fonts/Supplemental/Futura.ttc", 2)  # Futura Bold
FONT_SCRIPT = "/System/Library/Fonts/Supplemental/Brush Script.ttf"
FONT_VCR = "/System/Library/Fonts/Supplemental/Andale Mono.ttf"
SUNSET = [(255, 240, 110), (255, 170, 50), (255, 80, 120), (170, 60, 210)]
RETRO_BG = "#140C26"
# the same look in Korean ("look": "vhs", "lang": "ko"): a 90s Korean TV ad's
# yellow titles in a red and a white outline, a brush line (Nanum Brush Script,
# a downloadable macOS font; Apple SD Gothic Neo when it is not there)
FONT_KO_SCRIPT = next(iter(sorted(glob.glob(
    "/System/Library/AssetsV2/com_apple_MobileAsset_Font*/*/AssetData/NanumScript.ttc"))), None)
FONT_KO_SCRIPT = (FONT_KO_SCRIPT, 0) if FONT_KO_SCRIPT else FONT_KO
GOLD = [(255, 252, 170), (255, 220, 20), (255, 150, 0)]


def ffmpeg():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        return "ffmpeg"


def run(args):
    r = subprocess.run([ffmpeg(), "-hide_banner", "-loglevel", "error", "-y"] + args)
    if r.returncode != 0:
        sys.exit("ffmpeg failed: " + " ".join(args[:12]))


def duration(path):
    r = subprocess.run([ffmpeg(), "-hide_banner", "-i", path], capture_output=True, text=True)
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", r.stderr)
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3)) if m else 0.0


# ── Takes ──────────────────────────────────────────────────────────────────────

def take(name):
    """The take's pieces joined into one 30 fps file (cached) and a function
    from take time (s since the first piece began) to time in that file.
    Gaps between pieces (a fraction of a second) are skipped."""
    folder = os.path.join(RAW, name)
    info = json.load(open(os.path.join(folder, "take.json")))
    joined = os.path.join(folder, "joined.mp4")
    pieces = []
    at = 0.0
    for p in info["pieces"]:
        path = os.path.join(folder, p["file"])
        if not os.path.exists(path):
            continue
        d = duration(path)
        if d <= 0.2:
            continue
        pieces.append({"path": path, "start": p["start"], "dur": d, "at": at})
        at += d
    if not os.path.exists(joined) or os.path.getmtime(joined) < os.path.getmtime(os.path.join(folder, "take.json")):
        lst = os.path.join(folder, "pieces.txt")
        with open(lst, "w") as f:
            for p in pieces:
                f.write("file '%s'\n" % p["path"])
        run(["-f", "concat", "-safe", "0", "-i", lst, "-vf", "fps=%d,scale=-2:1080:flags=lanczos" % FPS,
             "-c:v", "libx264", "-preset", "veryfast", "-crf", "16", "-pix_fmt", "yuv420p", "-an", joined])

    def at_time(t):
        for p in pieces:
            if t < p["start"]:
                return p["at"]          # in a gap: the next piece's start
            if t < p["start"] + p["dur"]:
                return p["at"] + t - p["start"]
        return at

    return joined, info.get("phases", {}), at_time, at


def sheets(step=2.0, per_sheet=48):
    """Contact sheets of every take: a frame every `step` s, labelled with
    its time in the joined file (the pieces back to back, the short gaps
    between them dropped): what cuts.json's "t" means."""
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype(FONT_BODY, 22)
    for name in sorted(os.listdir(RAW)):
        if not os.path.exists(os.path.join(RAW, name, "take.json")):
            continue
        joined = take(name)[0]
        frames = os.path.join(tempfile.mkdtemp(), "f_%04d.jpg")
        # one pass over the joined file, then label by take time
        run(["-i", joined, "-vf", "fps=1/%g,scale=384:-2" % step, "-q:v", "4", frames])
        tiles, t = [], 0.0
        k = 1
        while os.path.exists(frames % k):
            im = Image.open(frames % k).convert("RGB")
            ImageDraw.Draw(im).text((8, 6), "t=%.0f" % t, font=font, fill=(255, 255, 0), stroke_width=3, stroke_fill=(0, 0, 0))
            tiles.append(im)
            t += step
            k += 1
        for n in range(0, len(tiles), per_sheet):
            group = tiles[n:n + per_sheet]
            w, h = group[0].size
            cols = 6
            sheet = Image.new("RGB", (w * cols, h * ((len(group) + cols - 1) // cols)), (0, 0, 0))
            for i, im in enumerate(group):
                sheet.paste(im, ((i % cols) * w, (i // cols) * h))
            path = os.path.join(OUT, "sheets", "%s_%d.jpg" % (name, n // per_sheet + 1))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            sheet.save(path, quality=80)
            print(os.path.relpath(path, ROOT))


# ── Overlays ───────────────────────────────────────────────────────────────────

def _truetype(path, size):
    from PIL import ImageFont
    if isinstance(path, tuple):
        return ImageFont.truetype(path[0], size, index=path[1])
    return ImageFont.truetype(path, size)


def _fit_font(draw, text, path, size, max_w):
    while size > 18:
        font = _truetype(path, size)
        w = max(draw.textlength(line, font=font) for line in text.split("\n"))
        if w <= max_w:
            return font
        size -= 4
    return _truetype(path, size)


def overlay_ko(size, seg, path):
    """Korean TTS reel (9x16, "lang": "ko"): a small spaced label ("MAP 01 ·
    FOREST") over a big title in the dark band above the footage, and the
    spoken line ("say") in big outlined letters under it, as short-form
    reels caption their voice-over. The clean build leaves "say" out: CapCut
    reads it from the .srt and draws its own captions."""
    from PIL import Image, ImageDraw
    W, H = size
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    y = int(H * seg.get("y", 0.1))
    if seg.get("head"):
        font = _truetype(FONT_KO, int(W * 0.03))
        text = " ".join(seg["head"])          # letter-spaced
        tw = d.textlength(text, font=font)
        d.text(((W - tw) / 2, y), text, font=font, fill=seg.get("headColor", "#C8A45A"))
        y += int(font.size * 1.9)
    if seg.get("title"):
        font = _fit_font(d, seg["title"], FONT_KO, int(W * 0.095), W * 0.9)
        for line in seg["title"].split("\n"):
            tw = d.textlength(line, font=font)
            d.text(((W - tw) / 2, y), line, font=font, fill=seg.get("color", "#FFFFFF"),
                   stroke_width=max(3, font.size // 14), stroke_fill=(0, 0, 0))
            y += int(font.size * 1.2)
    if seg.get("say"):
        font = _fit_font(d, seg["say"], FONT_KO, int(W * 0.075), W * 0.9)
        y = int(H * seg.get("sayY", 0.7))
        for line in seg["say"].split("\n"):
            tw = d.textlength(line, font=font)
            d.text(((W - tw) / 2, y), line, font=font, fill="#FFFFFF",
                   stroke_width=max(5, font.size // 9), stroke_fill=(0, 0, 0))
            y += int(font.size * 1.2)
    im.save(path)


def overlay(size, seg, path):
    """A transparent PNG: a step tag ("STEP 1 · FARM") over a big caption and
    a smaller line under it, centred. 16x9: in the lower middle (the game's
    own timer and buttons are at the top, its bars at the bottom); 9x16:
    above the footage. seg["y"] moves it (0..1, top of the stack)."""
    from PIL import Image, ImageDraw
    W, H = size
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    vertical = H > W
    y = int(H * seg.get("y", 0.13 if vertical else (0.30 if seg.get("card") else 0.56)))
    if seg.get("tag"):
        font = _fit_font(d, seg["tag"], FONT, int(W * (0.05 if vertical else 0.024)), W * 0.8)
        tw = d.textlength(seg["tag"], font=font)
        x0 = (W - tw) / 2 - font.size * 0.6
        d.rounded_rectangle((x0, y, x0 + tw + font.size * 1.2, y + font.size * 1.45), radius=font.size // 2,
                            fill=seg.get("color", "#FFB020"))
        d.text((x0 + font.size * 0.6, y + font.size * 0.12), seg["tag"], font=font, fill=(20, 20, 30))
        y += int(font.size * 1.8)
    if seg.get("title"):
        font = _fit_font(d, seg["title"], FONT, int(W * (0.1 if vertical else 0.055)), W * 0.92)
        for line in seg["title"].split("\n"):
            tw = d.textlength(line, font=font)
            d.text(((W - tw) / 2, y), line, font=font, fill=seg.get("color", "#FFFFFF") if not seg.get("tag") else "#FFFFFF",
                   stroke_width=max(4, font.size // 9), stroke_fill=(0, 0, 0))
            y += int(font.size * 1.15)
    if seg.get("sub"):
        font = _fit_font(d, seg["sub"], FONT_BODY, int(W * (0.05 if vertical else 0.028)), W * 0.9)
        y += int(font.size * 0.2)
        for line in seg["sub"].split("\n"):
            tw = d.textlength(line, font=font)
            pad = font.size // 3
            d.rounded_rectangle((W / 2 - tw / 2 - pad * 2, y, W / 2 + tw / 2 + pad * 2, y + font.size + pad * 2),
                                radius=pad * 2, fill=(0, 0, 0, 170))
            d.text(((W - tw) / 2, y + pad * 0.6), line, font=font, fill="#FFFFFF")
            y += int(font.size * 1.7)
    im.save(path)


def _gradient_text(im, x, y, text, font, colors, stroke, stroke_fill, shadow=None):
    """Text filled top to bottom with `colors` (a sunset), a thick outline
    and an offset shadow: an 80s title."""
    from PIL import Image, ImageDraw
    d = ImageDraw.Draw(im)
    if shadow:
        d.text((x + shadow[0], y + shadow[1]), text, font=font, fill=shadow[2], stroke_width=stroke, stroke_fill=shadow[2])
    d.text((x, y), text, font=font, fill=stroke_fill, stroke_width=stroke, stroke_fill=stroke_fill)
    box = [int(v) for v in d.textbbox((x, y), text, font=font)]
    w, h = box[2] - box[0] + 2, box[3] - box[1] + 2
    grad = Image.new("RGBA", (w, h))
    gd = ImageDraw.Draw(grad)
    n = len(colors) - 1
    for row in range(h):
        f = row / max(h - 1, 1) * n
        i = min(int(f), n - 1)
        t = f - i
        c = tuple(int(colors[i][j] + (colors[i + 1][j] - colors[i][j]) * t) for j in range(3))
        gd.line([(0, row), (w, row)], fill=c + (255,))
    # a thin bright band across the middle: chrome
    gd.line([(0, int(h * 0.52)), (w, int(h * 0.52))], fill=(255, 255, 255, 200), width=max(2, h // 30))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((x - box[0], y - box[1]), text, font=font, fill=255)
    im.paste(grad, (box[0], box[1]), mask)


def overlay_retro(size, seg, path, lang=None):
    """The 80s look's words: a script line ("Come on down to"), a big sunset
    title in Futura with a dark outline and a pink shadow, a white line under
    it, a yellow starburst badge, a TV's on-screen text (top left).
    In Korean (lang "ko"), a 90s Korean ad: a brush line, gold titles in a
    red and a white outline over a blue shadow, a red starburst."""
    from PIL import Image, ImageDraw
    import math as _m
    W, H = size
    ko = lang == "ko"
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    y = int(H * seg.get("y", 0.08))
    if seg.get("script"):
        font = _fit_font(d, seg["script"], FONT_KO_SCRIPT if ko else FONT_SCRIPT, int(W * (0.12 if ko else 0.1)), W * 0.86)
        for line in seg["script"].split("\n"):
            tw = d.textlength(line, font=font)
            if ko:
                d.text(((W - tw) / 2 + 5, y + 6), line, font=font, fill=(20, 50, 160), stroke_width=5, stroke_fill=(20, 50, 160))
                d.text(((W - tw) / 2, y), line, font=font, fill="#FFFFFF", stroke_width=5, stroke_fill=(220, 30, 50))
            else:
                d.text(((W - tw) / 2 + 4, y + 5), line, font=font, fill=(255, 60, 150), stroke_width=4, stroke_fill=(255, 60, 150))
                d.text(((W - tw) / 2, y), line, font=font, fill="#FFFFFF", stroke_width=3, stroke_fill=(60, 20, 90))
            y += int(font.size * 1.05)
    if seg.get("title"):
        font = _fit_font(d, seg["title"], FONT_KO if ko else FONT_RETRO, int(W * (0.14 if ko else 0.15)), W * 0.88)
        for line in seg["title"].split("\n"):
            tw = d.textlength(line, font=font)
            x = (W - tw) / 2
            if ko:
                st = max(6, font.size // 12)
                d.text((x + 9, y + 11), line, font=font, fill=(20, 50, 160), stroke_width=st * 3, stroke_fill=(20, 50, 160))
                d.text((x, y), line, font=font, fill="#FFFFFF", stroke_width=st * 3, stroke_fill="#FFFFFF")
                _gradient_text(im, x, y, line, font, GOLD, st, (210, 20, 40))
            else:
                _gradient_text(im, x, y, line, font, SUNSET, max(6, font.size // 11), (45, 15, 70),
                               shadow=(8, 10, (255, 60, 150)))
            y += int(font.size * (1.18 if ko else 1.0))
    if seg.get("sub"):
        font = _fit_font(d, seg["sub"], FONT_KO if ko else FONT_RETRO_BODY, int(W * 0.06), W * 0.9)
        y += int(font.size * 0.3)
        for line in seg["sub"].split("\n"):
            tw = d.textlength(line, font=font)
            d.text(((W - tw) / 2, y), line, font=font, fill="#FFFFFF", stroke_width=4, stroke_fill=(30, 60, 160))
            y += int(font.size * 1.25)
    if seg.get("badge"):
        # a yellow starburst with red words, tilted
        r = int(W * 0.13)
        cx, cy = int(W * seg.get("badgeX", 0.8)), int(H * seg.get("badgeY", 0.72))
        pts = []
        for k in range(32):
            a = k / 32 * 2 * _m.pi
            rr = r if k % 2 == 0 else r * 0.78
            pts.append((cx + _m.cos(a) * rr, cy + _m.sin(a) * rr))
        d.polygon(pts, fill=(225, 30, 40) if ko else (255, 225, 40), outline=(255, 255, 255) if ko else (200, 40, 40))
        font = _fit_font(d, seg["badge"], FONT_KO if ko else FONT_RETRO, int(r * (0.5 if ko else 0.55)), r * 1.45)
        lines = seg["badge"].split("\n")
        ty = cy - len(lines) * font.size * 0.55
        for line in lines:
            tw = d.textlength(line, font=font)
            d.text((cx - tw / 2, ty), line, font=font, fill=(255, 235, 40) if ko else (210, 30, 40))
            ty += font.size * 1.05
    if seg.get("osd"):
        font = _truetype(FONT_VCR, int(W * 0.055))
        text = seg["osd"]
        play = text.endswith("\u25b6")   # the VCR font has no ▶: drawn
        if play:
            text = text[:-1].rstrip()
        x0, y0 = int(W * 0.07), int(H * seg.get("osdY", 0.25))
        d.text((x0, y0), text, font=font, fill="#FFFFFF", stroke_width=2, stroke_fill=(0, 0, 0, 120))
        if play:
            tx = x0 + d.textlength(text + " ", font=font)
            sz = font.size * 0.8
            d.polygon([(tx, y0 + font.size * 0.15), (tx, y0 + font.size * 0.15 + sz), (tx + sz * 0.85, y0 + font.size * 0.15 + sz / 2)],
                      fill="#FFFFFF")
    im.save(path)


def sunset_card(size, path):
    """An 80s sky: a sunset gradient, a striped sun, a purple grid floor."""
    from PIL import Image, ImageDraw
    W, H = size
    im = Image.new("RGB", size)
    d = ImageDraw.Draw(im)
    top, mid, low = (30, 10, 60), (230, 70, 130), (255, 170, 60)
    horizon = int(H * 0.62)
    for row in range(horizon):
        f = row / horizon
        a, b, t = (top, mid, f / 0.6) if f < 0.6 else (mid, low, (f - 0.6) / 0.4)
        d.line([(0, row), (W, row)], fill=tuple(int(a[j] + (b[j] - a[j]) * t) for j in range(3)))
    # the sun, cut by stripes near the horizon
    r = int(W * 0.3)
    cx, cy = W // 2, horizon - int(r * 0.35)
    for row in range(cy - r, horizon):
        dy = row - cy
        if abs(dy) > r:
            continue
        half = int((r * r - dy * dy) ** 0.5)
        f = (row - (cy - r)) / (2 * r)
        col = (255, int(235 - 120 * f), int(90 - 40 * f))
        if row > cy and (row // 14) % 2 == 0 and row > cy + r * 0.1:
            continue
        d.line([(cx - half, row), (cx + half, row)], fill=col)
    d.rectangle((0, horizon, W, H), fill=(25, 8, 45))
    grid = (230, 60, 200)
    for k in range(-14, 15):
        d.line([(W / 2 + k * 40, horizon), (W / 2 + k * 400, H)], fill=grid, width=3)
    y, step = horizon, 8
    while y < H:
        d.line([(0, y), (W, y)], fill=grid, width=3)
        step *= 1.35
        y += int(step)
    im.save(path)


def burst_card(size, path):
    """A 90s Korean ad's card: sky-blue and white rays from a yellow sun."""
    from PIL import Image, ImageDraw
    import math as _m
    W, H = size
    im = Image.new("RGB", size, (40, 150, 235))
    d = ImageDraw.Draw(im)
    cx, cy, R = W / 2, H * 0.5, max(W, H) * 1.2
    n = 28
    for k in range(n):
        if k % 2:
            continue
        a0, a1 = k / n * 2 * _m.pi, (k + 1) / n * 2 * _m.pi
        d.polygon([(cx, cy), (cx + _m.cos(a0) * R, cy + _m.sin(a0) * R), (cx + _m.cos(a1) * R, cy + _m.sin(a1) * R)],
                  fill=(120, 205, 255))
    for r, col in ((W * 0.36, (255, 255, 255)), (W * 0.32, (255, 150, 0)), (W * 0.27, (255, 215, 40))):
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)
    im.save(path)


def card_image(size, seg, path):
    """A still: a store picture (cropped to fill) or a colour, darkened at
    the edges so the text reads."""
    from PIL import Image, ImageDraw, ImageFilter
    W, H = size
    if seg.get("bg") == "sunset":
        sunset_card(size, path)
        return
    if seg.get("bg") == "burst":
        burst_card(size, path)
        return
    if seg.get("image") and seg.get("fit") == "black":
        # the picture in the middle of a black frame, `zoom` × the width (sides
        # cut round cx), as the footage of a Korean reel sits
        src = Image.open(os.path.join(ROOT, seg["image"])).convert("RGB")
        w = int(W * seg.get("zoom", 1.0))
        src = src.resize((w, int(src.size[1] * w / src.size[0])), Image.LANCZOS)
        x = int((w - W) * seg.get("cx", 0.5))
        src = src.crop((x, 0, x + W, src.size[1]))
        im = Image.new("RGB", size, (0, 0, 0))
        im.paste(src, (0, (H - src.size[1]) // 2 + int(H * seg.get("shift", 0))))
        im.save(path)
        return
    if seg.get("image"):
        src = Image.open(os.path.join(ROOT, seg["image"])).convert("RGB")
        k = max(W / src.size[0], H / src.size[1])
        src = src.resize((int(src.size[0] * k) + 1, int(src.size[1] * k) + 1), Image.LANCZOS)
        # cx / cy: centre of the crop (0..1), the subject of a 16:9 still in a 9:16 cut
        x = int((src.size[0] - W) * seg.get("cx", 0.5))
        y = int((src.size[1] - H) * seg.get("cy", 0.5))
        im = src.crop((x, y, x + W, y + H))
    else:
        im = Image.new("RGB", size, seg.get("bg", "#1C1830"))
    shade = Image.new("L", size, 0)
    # darken only round the text, lightly (the store pictures are dark already)
    top = int(H * seg.get("y", 0.12 if H > W else 0.3))
    ImageDraw.Draw(shade).rectangle((0, max(0, top - H // 12), W, top + H // 4), fill=90)
    shade = shade.filter(ImageFilter.GaussianBlur(H // 8))
    im = Image.composite(Image.new("RGB", size, (0, 0, 0)), im, shade)
    im.save(path)


# ── Segments ───────────────────────────────────────────────────────────────────

def clean_text(seg):
    """What the clean cut still draws: the big words (tag, title) and a
    card's text (the game's name); the small lines go to the .srt only.
    Without the big words the reel read as plain footage (2026-11-12)."""
    if seg.get("card"):
        return seg
    return {k: v for k, v in seg.items() if k != "sub"}


def take_fix(fix):
    """Filters for a take's own flaws (cuts.json "takes"): mask = boxes
    [x, y, w, h] in the joined file's pixels blurred away (Studio's music
    tryout label), top = share of the height cut off (Studio's toolbar
    caught over the view)."""
    vf = []
    for x, y, w, h in fix.get("mask", []):
        vf.append("delogo=x=%d:y=%d:w=%d:h=%d" % (x, y, w, h))
    if fix.get("top"):
        vf.append("crop=iw:ih*%.4f:0:ih*%.4f" % (1 - fix["top"], fix["top"]))
    return "".join(f + "," for f in vf)


def segment(cut, seg, k, size, work, takes, clean=False, fixes=None, lang=None):
    W, H = size
    out = os.path.join(work, "seg_%02d.mp4" % k)
    ov = os.path.join(work, "ov_%02d.png" % k)
    if seg.get("_retro"):
        overlay_retro(size, clean_text(seg) if clean else seg, ov, lang)
    elif lang == "ko":
        overlay_ko(size, {k2: v for k2, v in seg.items() if k2 != "say"} if clean else seg, ov)
    else:
        overlay(size, clean_text(seg) if clean else seg, ov)
    dur = seg["dur"]
    fade = min(0.25, dur / 4)
    tail = "fade=t=in:st=0:d=%.2f,fade=t=out:st=%.2f:d=%.2f" % (fade, dur - fade, fade)
    if seg.get("hard"):
        tail = "null"   # a hard cut (trailers): no fade in or out
    if seg.get("card"):
        still = os.path.join(work, "card_%02d.png" % k)
        card_image(size, seg, still)
        # a slow push-in keeps a still alive
        zoom = "scale=%d:%d,zoompan=z='1+0.04*on/%d':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=%d:s=%dx%d:fps=%d" % (
            W * 2, H * 2, int(dur * FPS), int(dur * FPS), W, H, FPS)
        fc = "[0:v]%s[bg];[bg][1:v]overlay=0:0,%s,format=yuv420p[v]" % (zoom, tail)
        run(["-loop", "1", "-t", "%.2f" % dur, "-i", still, "-i", ov, "-filter_complex", fc, "-map", "[v]",
             "-r", str(FPS), "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-t", "%.2f" % dur, out])
        return out
    if seg["take"] not in takes:
        takes[seg["take"]] = take(seg["take"])
    joined, phases, at_time, _ = takes[seg["take"]]
    # "t": seconds into the take's joined file (what `cut.py sheets` labels)
    start = seg["t"]
    speed = seg.get("speed", 1.0)
    src_dur = dur * speed
    zoom = seg.get("zoom", 1.0)
    if seg.get("fit") == "tv":
        # a 4:3 picture across the frame's width, as an old TV ad (look vhs):
        # zoom > 1 cuts in further, cx picks the part of the wide view, shift
        # moves it down (share of the height)
        tw, th = W, int(W * 3 / 4) // 2 * 2
        y0 = int((H - th) / 2 + H * seg.get("shift", 0))
        cx = seg.get("cx", 0.5)
        vf = ("scale=-2:%d:flags=lanczos,crop=%d:%d:(iw-%d)*%.3f:(ih-%d)/2,pad=%d:%d:0:%d:color=%s"
              % (int(th * zoom) // 2 * 2, tw, th, tw, cx, th, W, H, y0, RETRO_BG))
    elif seg.get("fit") == "black":
        # the footage in the middle of a black frame (titles above, words below)
        fg_w = int(W * zoom) // 2 * 2
        shift = seg.get("shift", 0)
        # cx: which part of a view wider than the frame stays (0 left .. 1 right)
        cx = seg.get("cx", 0.5)
        vf = ("scale=%d:-2:flags=lanczos,crop=min(iw\\,%d):min(ih\\,%d):(iw-min(iw\\,%d))*%.3f:(ih-min(ih\\,%d))/2,"
              "pad=%d:%d:(ow-iw)/2:(oh-ih)/2+%d:black" % (fg_w, W, H, W, cx, H, W, H, int(H * shift)))
    elif seg.get("fit", "blur") == "blur":
        # the whole view (all of the game's UI), a blurred copy fills the rest
        fg_w = int(W * zoom) // 2 * 2
        shift = seg.get("shift", 0.08 if H > W else 0)
        vf = ("split[a][b];[a]scale=%d:%d:force_original_aspect_ratio=increase,crop=%d:%d,boxblur=20:2,eq=brightness=-0.2[bg];"
              "[b]scale=%d:-2:flags=lanczos,crop=min(iw\\,%d):min(ih\\,%d)[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2+%d"
              % (W, H, W, H, fg_w, W, H, int(H * shift)))
    else:
        # fill the frame: crop the middle (cx, cy = centre of the crop, 0..1)
        cx, cy = seg.get("cx", 0.5), seg.get("cy", 0.5)
        vf = ("scale=%d:%d:force_original_aspect_ratio=increase:flags=lanczos,scale=iw*%.3f:ih*%.3f,"
              "crop=%d:%d:(iw-%d)*%.3f:(ih-%d)*%.3f" % (W, H, zoom, zoom, W, H, W, cx, H, cy))
    fix = take_fix((fixes or {}).get(seg["take"], {}))
    fc = "[0:v]%ssetpts=PTS/%.3f,%s[base];[base][1:v]overlay=0:0,%s,format=yuv420p[v]" % (fix, speed, vf, tail)
    run(["-ss", "%.2f" % start, "-t", "%.2f" % src_dur, "-i", joined, "-i", ov, "-filter_complex", fc,
         "-map", "[v]", "-r", str(FPS), "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-t", "%.2f" % dur, out])
    return out


def _srt_time(t):
    ms = int(round(t * 1000))
    return "%02d:%02d:%02d,%03d" % (ms // 3600000, ms // 60000 % 60, ms // 1000 % 60, ms % 1000)


def srt(cut):
    """The cut's captions as SubRip text: one cue per segment that has any
    (tag, title, sub: one line each), timed by the segment durations."""
    out, t, n = [], 0.0, 0
    # a voice-over cut: only the spoken lines (CapCut reads every cue)
    keys = ("say",) if any(s.get("say") for s in cut["segments"]) else ("tag", "title", "sub")
    for seg in cut["segments"]:
        lines = [seg[k].replace("\n", " ") for k in keys if seg.get(k)]
        if lines:
            n += 1
            out.append("%d\n%s --> %s\n%s\n" % (n, _srt_time(t), _srt_time(t + seg["dur"]), "\n".join(lines)))
        t += seg["dur"]
    return "\n".join(out)


def vhs(src, out, size, work, stamp):
    """An old tape: a softer picture (down and up again), colour bleeding
    sideways, warm and saturated, grain, scanlines, a dark edge, and the
    camcorder's date in the corner."""
    from PIL import Image, ImageDraw
    W, H = size
    lines = os.path.join(work, "scanlines.png")
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for row in range(0, H, 4):
        d.line([(0, row), (W, row)], fill=(0, 0, 0, 46), width=1)
    if stamp:
        font = _truetype(FONT_VCR, int(W * 0.045))
        th = int(W * 3 / 4)
        y = (H + th) // 2 - int(font.size * 1.6)
        tw = d.textlength(stamp, font=font)
        d.text((W - tw - int(W * 0.06), y), stamp, font=font, fill=(255, 190, 60), stroke_width=2, stroke_fill=(60, 20, 0))
    im.save(lines)
    fc = ("[0:v]scale=%d:%d:flags=bilinear,scale=%d:%d:flags=bilinear,rgbashift=rh=5:bh=-5:rv=1,"
          "eq=saturation=1.28:contrast=1.06:brightness=0.015,colorbalance=rs=0.07:gs=0.02:bs=-0.07,"
          "noise=alls=11:allf=t,vignette=angle=PI/4.5[v0];[v0][1:v]overlay=0:0,format=yuv420p[v]"
          % (W // 2, H // 2, W, H))
    run(["-i", src, "-i", lines, "-filter_complex", fc, "-map", "[v]", "-r", str(FPS),
         "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-movflags", "+faststart", out])


def build(names, clean=False):
    data = json.load(open(CUTS))
    cuts, fixes = data["cuts"], data.get("takes", {})
    takes = {}
    for name, cut in cuts.items():
        if names and name not in names:
            continue
        size = SIZES[cut["format"]]
        work = tempfile.mkdtemp(prefix="cut-%s-" % name)
        retro = cut.get("look") == "vhs"
        segs = [segment(name, dict(seg, _retro=True) if retro else seg, k, size, work, takes, clean, fixes, cut.get("lang"))
                for k, seg in enumerate(cut["segments"])]
        lst = os.path.join(work, "list.txt")
        with open(lst, "w") as f:
            for s in segs:
                f.write("file '%s'\n" % s)
        out = os.path.join(OUT, name + ("-clean" if clean else "") + ".mp4")
        os.makedirs(OUT, exist_ok=True)
        if clean:
            with open(os.path.join(OUT, name + ".srt"), "w", encoding="utf-8") as f:
                f.write(srt(cut))
        if retro:
            joined = os.path.join(work, "joined.mp4")
            run(["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", joined])
            vhs(joined, out, size, work, cut.get("stamp", "JUN 21 1986"))
        else:
            run(["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", "-movflags", "+faststart", out])
        print("%s  %.1f s  %dx%d" % (os.path.relpath(out, ROOT), duration(out), size[0], size[1]))


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("sheets", "build"):
        print(__doc__)
        sys.exit(1)
    if sys.argv[1] == "sheets":
        sheets()
    else:
        args = sys.argv[2:]
        build([a for a in args if a != "--clean"], clean="--clean" in args)
