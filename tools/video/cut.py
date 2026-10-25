#!/usr/bin/env python3
"""Short gameplay videos (trailer cuts) from recorded Studio matches.

  python3 tools/studio/sim.py run record-forest record-ocean record-sky   # footage, one at a time
  python3 tools/video/cut.py sheets              # contact sheets of every take (pick moments)
  python3 tools/video/cut.py build               # every cut in tools/video/cuts.json
  python3 tools/video/cut.py build reel          # one cut

Footage: reports/video/raw/<take>/ (NNN.mov pieces + take.json, written
by sim.py's "record" mode: the bot client's window only, never the desktop).
The screen must be awake and unlocked while recording.
Cuts: tools/video/cuts.json. A segment names a take and a time in it ("t",
seconds; `sheets` labels every 2 s), or is a card (store picture / colour
with text). Output: reports/video/<cut>.mp4 (git-ignored), silent H.264:
add music in the editor you post with.

Needs ffmpeg (on PATH, or `pip install imageio-ffmpeg`) and Pillow.
"""

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
SIZES = {"16x9": (1920, 1080), "9x16": (1080, 1920)}


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

def _fit_font(draw, text, path, size, max_w):
    from PIL import ImageFont
    while size > 18:
        font = ImageFont.truetype(path, size)
        w = max(draw.textlength(line, font=font) for line in text.split("\n"))
        if w <= max_w:
            return font
        size -= 4
    return ImageFont.truetype(path, size)


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


def card_image(size, seg, path):
    """A still: a store picture (cropped to fill) or a colour, darkened at
    the edges so the text reads."""
    from PIL import Image, ImageDraw, ImageFilter
    W, H = size
    if seg.get("image"):
        src = Image.open(os.path.join(ROOT, seg["image"])).convert("RGB")
        k = max(W / src.size[0], H / src.size[1])
        src = src.resize((int(src.size[0] * k) + 1, int(src.size[1] * k) + 1), Image.LANCZOS)
        x, y = (src.size[0] - W) // 2, (src.size[1] - H) // 2
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

def segment(cut, seg, k, size, work, takes):
    W, H = size
    out = os.path.join(work, "seg_%02d.mp4" % k)
    ov = os.path.join(work, "ov_%02d.png" % k)
    overlay(size, seg, ov)
    dur = seg["dur"]
    fade = min(0.25, dur / 4)
    tail = "fade=t=in:st=0:d=%.2f,fade=t=out:st=%.2f:d=%.2f" % (fade, dur - fade, fade)
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
    if seg.get("fit", "blur") == "blur":
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
    fc = "[0:v]setpts=PTS/%.3f,%s[base];[base][1:v]overlay=0:0,%s,format=yuv420p[v]" % (speed, vf, tail)
    run(["-ss", "%.2f" % start, "-t", "%.2f" % src_dur, "-i", joined, "-i", ov, "-filter_complex", fc,
         "-map", "[v]", "-r", str(FPS), "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-t", "%.2f" % dur, out])
    return out


def build(names):
    cuts = json.load(open(CUTS))["cuts"]
    takes = {}
    for name, cut in cuts.items():
        if names and name not in names:
            continue
        size = SIZES[cut["format"]]
        work = tempfile.mkdtemp(prefix="cut-%s-" % name)
        segs = [segment(name, seg, k, size, work, takes) for k, seg in enumerate(cut["segments"])]
        lst = os.path.join(work, "list.txt")
        with open(lst, "w") as f:
            for s in segs:
                f.write("file '%s'\n" % s)
        out = os.path.join(OUT, name + ".mp4")
        os.makedirs(OUT, exist_ok=True)
        run(["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", "-movflags", "+faststart", out])
        print("%s  %.1f s  %dx%d" % (os.path.relpath(out, ROOT), duration(out), size[0], size[1]))


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("sheets", "build"):
        print(__doc__)
        sys.exit(1)
    if sys.argv[1] == "sheets":
        sheets()
    else:
        build(sys.argv[2:])
