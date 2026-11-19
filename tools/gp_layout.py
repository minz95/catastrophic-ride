#!/usr/bin/env python3
"""Top view of the Junk GP circuit from reports/gp/layout.json
(lune run tools/gp_layout.luau) → reports/gp/layout.png."""
import json
from PIL import Image, ImageDraw

d = json.load(open("reports/gp/layout.json"))
g = d["ground"]
S = 1.0
W, H = int((g[1] - g[0]) * S) + 40, int((g[3] - g[2]) * S) + 40
img = Image.new("RGB", (W, H), (110, 170, 90))
dr = ImageDraw.Draw(img)
def P(x, z):
    return ((x - g[0]) * S + 20, (z - g[2]) * S + 20)
# town side
dr.rectangle([P(-310, g[2]), P(g[1], g[3])], fill=(200, 200, 200))
nodes = d["nodes"]
pts = [P(n[0], n[1]) for n in nodes]
dr.line(pts, fill=(60, 60, 66), width=int(d["width"] * S))
dr.line(pts, fill=(255, 255, 255), width=1)
dr.line([P(*p) for p in d["pit"]], fill=(90, 90, 120), width=int(14 * S))
for b in d["boxes"]:
    x, y = P(*b)
    dr.rectangle([x - 3, y - 3, x + 3, y + 3], fill=(240, 200, 40))
x0, y0 = P(-380, d["line"]); x1, y1 = P(-340, d["line"])
dr.line([x0, y0, x1, y1], fill=(255, 0, 0), width=3)
n = len(nodes)
for s in d["sectors"]:
    p = P(*nodes[int(s * (n - 1))])
    dr.ellipse([p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5], fill=(160, 60, 220))
p = P(*nodes[3])
dr.ellipse([p[0] - 6, p[1] - 6, p[0] + 6, p[1] + 6], fill=(0, 120, 255))  # direction marker after the line
img.save("reports/gp/layout.png")
print("reports/gp/layout.png", img.size)
