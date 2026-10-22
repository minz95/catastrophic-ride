#!/usr/bin/env python3
"""Top-down PNG of a biome from tools/topview.luau JSON: lane, walls, driver
paths (expert green, average yellow, novice pink) and respawns (red X).

    python3 tools/topview.py reports/sky/topview.json [out.png] [--box x0,z0,x1,z1] [--scale 1]
"""
import argparse
import json
import math

from PIL import Image, ImageDraw

ap = argparse.ArgumentParser()
ap.add_argument("json")
ap.add_argument("out", nargs="?")
ap.add_argument("--box")
ap.add_argument("--scale", type=float, default=0.5)
a = ap.parse_args()
d = json.load(open(a.json))
nodes = d["nodes"]
if a.box:
    x0, z0, x1, z1 = map(float, a.box.split(","))
else:
    xs = [n[0] for n in nodes]; zs = [n[1] for n in nodes]
    x0, x1, z0, z1 = min(xs) - 80, max(xs) + 80, min(zs) - 80, max(zs) + 80
sc = a.scale
W, H = int((x1 - x0) * sc), int((z1 - z0) * sc)
img = Image.new("RGB", (W, H), (140, 165, 220))
dr = ImageDraw.Draw(img)


def P(x, z):  # +Z up, +X right
    return ((x - x0) * sc, (z1 - z) * sc)


lw = max(1, int(d["width"] * sc))
dr.line([P(n[0], n[1]) for n in nodes], fill=(180, 160, 215), width=lw, joint="curve")
for n in nodes:
    cx, cy = P(n[0], n[1]); r = lw / 2
    dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(180, 160, 215))
for i, n in enumerate(nodes):
    dr.text(P(n[0] + 6, n[1] + 6), f"N{i+1}", fill=(40, 40, 60))
for w in d["walls"]:
    c = []
    for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        c.append(P(w["cx"] + su * w["hu"] * w["ux"] + sv * w["hv"] * w["vx"], w["cz"] + su * w["hu"] * w["uz"] + sv * w["hv"] * w["vz"]))
    dr.polygon(c, fill=(70, 40, 160))
col = {"expert": (0, 220, 180), "average": (240, 210, 40), "novice": (240, 80, 160)}
for r in d["runs"]:
    pts = [P(p[0], p[1]) for p in r["pts"]]
    if len(pts) > 1:
        dr.line(pts, fill=col[r["profile"]], width=1)
for r in d["runs"]:
    for e in r["respawns"]:
        cx, cy = P(e["x"], e["z"])
        dr.line([cx - 6, cy - 6, cx + 6, cy + 6], fill=(230, 0, 0), width=3)
        dr.line([cx - 6, cy + 6, cx + 6, cy - 6], fill=(230, 0, 0), width=3)
out = a.out or a.json.replace(".json", ".png")
img.save(out)
print(out, W, H)
