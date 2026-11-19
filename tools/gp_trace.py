#!/usr/bin/env python3
"""Where the cars went in a Studio gp-drive run: the player's samples
(bot_gp_sample, colour = real speed), the bots' (gp_bot_sample), resets
and rollovers over the circuit (reports/gp/layout.json from
tools/gp_layout.luau) → reports/gp/trace.png, and a text summary.
  python3 tools/gp_trace.py [reports/studio/gp-drive.json]"""
import json, sys
from PIL import Image, ImageDraw

rep = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "reports/studio/gp-drive.json"))["report"]
ev = rep["telemetry"]["events"]
lay = json.load(open("reports/gp/layout.json"))
g = lay["ground"]
S = 1.2
W, H = int((g[1] - g[0]) * S) + 40, int((g[3] - g[2]) * S) + 40
img = Image.new("RGB", (W, H), (110, 170, 90))
dr = ImageDraw.Draw(img)
P = lambda x, z: ((x - g[0]) * S + 20, (z - g[2]) * S + 20)
dr.line([P(*n) for n in lay["nodes"]], fill=(60, 60, 66), width=int(lay["width"] * S))
dr.line([P(*p) for p in lay["pit"]], fill=(90, 90, 120), width=int(14 * S))
def col(v, top=110):
    f = max(0, min(1, v / top))
    return (int(255 * (1 - f)), int(255 * f), 60)
for e in ev:
    k = e.get("kind")
    if k == "bot_gp_sample":
        d = e["data"]; x, y = P(d["x"], d["z"])
        dr.ellipse([x - 3, y - 3, x + 3, y + 3], fill=col(d["real"]))
    elif k == "gp_bot_sample":
        x, y = P(e["x"], e["z"])
        dr.rectangle([x - 1, y - 1, x + 1, y + 1], fill=(200, 200, 255))
for e in ev:
    k = e.get("kind")
    if k in ("gp_reset", "gp_bot_reset") and "x" in e:
        x, y = P(e["x"], e["z"]); dr.line([x - 6, y - 6, x + 6, y + 6], fill=(255, 0, 0), width=3); dr.line([x - 6, y + 6, x + 6, y - 6], fill=(255, 0, 0), width=3)
    elif k == "bot_gp_flip":
        d = e["data"]; x, y = P(d["x"], d["z"]); dr.ellipse([x - 7, y - 7, x + 7, y + 7], outline=(255, 255, 0), width=3)
img.save("reports/gp/trace.png")
for e in ev:
    k = e.get("kind", "")
    if k in ("gp_lap", "gp_reset", "gp_bot_reset", "bot_gp_flip", "gp_pit", "gp_done", "gp_end"):
        print(json.dumps(e)[:220])
s = [e["data"] for e in ev if e.get("kind") == "bot_gp_sample"]
if s:
    print("player samples", len(s), "max real", max(d["real"] for d in s), "max cmd", max(d["cmd"] for d in s))
    print("cmd-real gap avg", sum(d["cmd"] - d["real"] for d in s) / len(s))
print("reports/gp/trace.png")
