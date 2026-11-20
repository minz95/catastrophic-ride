#!/usr/bin/env python3
"""The Alpine Luge from above (the trough coloured by height, high banked
walls red, trestles brown, the chairlift, the stations) and its height
profile → reports/luge/layout.png.
    lune run tools/luge_layout.luau && python3 tools/luge_layout.py"""
import json
from PIL import Image, ImageDraw

lay = json.load(open("reports/luge/layout.json"))
R = lay["region"]; S = 3
W, H = int((R[1] - R[0]) * S) + 40, int((R[3] - R[2]) * S) + 40
prof_h = 220
img = Image.new("RGB", (W + 520, max(H, prof_h + 40)), (245, 245, 240))
d = ImageDraw.Draw(img)
P = lambda x, z: ((x - R[0]) * S + 20, (z - R[2]) * S + 20)
top = lay["hill"]["top"]
d.rectangle([P(R[0], R[2]), P(R[1], R[3])], fill=(150, 200, 120))
zt, zb = lay["hill"]["zTop"], lay["hill"]["zBottom"]
for z in range(int(R[2]), int(R[3]), 4):   # the slope, darker up the hill
    f = max(0, min(1, (zb - z) / (zb - zt)))
    d.rectangle([P(R[0], z), P(R[1], z + 4)], fill=(int(150 - 60 * f), int(200 - 50 * f), int(120 - 50 * f)))
for r, col in ((lay["bottom"], (170, 120, 80)), (lay["top"], (170, 120, 80))):
    d.rectangle([P(r[0], r[2]), P(r[1], r[3])], fill=col)
N = lay["nodes"]; g = lay["ground"]; K = lay["curves"]
w = lay["width"] * S
for i in range(1, len(N)):
    a, b = N[i - 1], N[i]
    t = b[2] - g[i]
    col = (120, 80, 40) if t > 2.5 else (205, 210, 218)
    d.line([P(a[0], a[1]), P(b[0], b[1])], fill=col, width=int(w))
for i in range(1, len(N)):
    a, b = N[i - 1], N[i]
    if abs(K[i]) > 1 / 20:
        d.line([P(a[0], a[1]), P(b[0], b[1])], fill=(220, 50, 50), width=3)
    else:
        d.line([P(a[0], a[1]), P(b[0], b[1])], fill=(70, 130, 220), width=1)
L = lay["lift"]
d.line([P(L[0], L[1]), P(L[2], L[3])], fill=(40, 40, 44), width=3)
d.text(P(L[0] + 3, L[1] - 10), "lift", fill=(0, 0, 0))
d.text(P(N[0][0] - 10, N[0][1] - 14), "START", fill=(150, 0, 0))
d.text(P(N[-1][0] - 30, N[-1][1] + 6), "FINISH", fill=(150, 0, 0))
d.ellipse([P(lay["desk"][0] - 2, lay["desk"][1] - 2), P(lay["desk"][0] + 2, lay["desk"][1] + 2)], fill=(200, 40, 40))
# the profile: floor and ground along the trough
ox, oy, pw = W + 20, 20, 480
s = [0]
for i in range(1, len(N)):
    s.append(s[-1] + ((N[i][0] - N[i - 1][0]) ** 2 + (N[i][1] - N[i - 1][1]) ** 2) ** 0.5)
X = lambda v: ox + v / s[-1] * pw
Y = lambda y: oy + prof_h - y / (top + 10) * prof_h
d.rectangle([ox, oy, ox + pw, oy + prof_h], outline=(150, 150, 150))
d.line([(X(s[i]), Y(g[i])) for i in range(len(N))], fill=(80, 150, 70), width=2)
d.line([(X(s[i]), Y(N[i][2])) for i in range(len(N))], fill=(40, 60, 160), width=2)
d.text((ox, oy + prof_h + 6), "height along the trough: blue floor, green ground (%.0f studs, finish at %.0f)" % (s[-1], lay["finishS"]), fill=(0, 0, 0))
img.save("reports/luge/layout.png")
print("reports/luge/layout.png")
