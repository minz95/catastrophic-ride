#!/usr/bin/env python3
"""Draws a scene dumped by tools/scene_dump.luau as a PNG (simple z-buffer
rasterizer: Lambert shading, Neon glows, transparency, distance fog).

    python3 tools/scene_render.py scene.json [out.png] [--width 960]
           [--eye x,y,z --target x,y,z]

It is a preview of shapes, colours and brightness, not of Roblox lighting:
no shadows, no textures, no bloom beyond a simple Neon boost.
"""
import argparse
import json
import math
import os

import numpy as np
from PIL import Image

LIGHT = np.array([0.35, 0.85, 0.4])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def box_tris():
    v = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    tris = []
    for a, b, c, d in faces:
        tris += [(a, b, c), (a, c, d)]
    return v, tris


def wedge_tris():
    # WedgePart: bottom full, top edge along +Z back; slope faces -Z/up
    v = np.array([[-.5, -.5, -.5], [.5, -.5, -.5], [-.5, -.5, .5], [.5, -.5, .5], [-.5, .5, .5], [.5, .5, .5]])
    tris = [(0, 2, 3), (0, 3, 1), (2, 4, 5), (2, 5, 3), (0, 1, 5), (0, 5, 4), (0, 4, 2), (1, 3, 5)]
    return v, tris


def cyl_tris(n=14):
    # Roblox cylinder: axis along X
    v = [[-.5, 0, 0], [.5, 0, 0]]
    for i in range(n):
        a = 2 * math.pi * i / n
        v.append([-.5, .5 * math.cos(a), .5 * math.sin(a)])
        v.append([.5, .5 * math.cos(a), .5 * math.sin(a)])
    tris = []
    for i in range(n):
        j = (i + 1) % n
        a0, a1, b0, b1 = 2 + 2 * i, 3 + 2 * i, 2 + 2 * j, 3 + 2 * j
        tris += [(a0, b0, b1), (a0, b1, a1), (0, b0, a0), (1, a1, b1)]
    return np.array(v), tris


def ball_tris(n=8):
    v, tris = [], []
    for i in range(n + 1):
        th = math.pi * i / n
        for j in range(2 * n):
            ph = math.pi * j / n
            v.append([.5 * math.sin(th) * math.cos(ph), .5 * math.cos(th), .5 * math.sin(th) * math.sin(ph)])
    for i in range(n):
        for j in range(2 * n):
            a = i * 2 * n + j
            b = i * 2 * n + (j + 1) % (2 * n)
            c, d = a + 2 * n, b + 2 * n
            tris += [(a, c, d), (a, d, b)]
    return np.array(v), tris


SHAPES = {"block": box_tris(), "wedge": wedge_tris(), "cylinder": cyl_tris(), "ball": ball_tris()}


def look_at(eye, target):
    f = target - eye
    f = f / np.linalg.norm(f)
    r = np.cross(f, [0, 1, 0])
    r = r / np.linalg.norm(r)
    u = np.cross(r, f)
    return r, u, f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scene")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--width", type=int, default=960)
    ap.add_argument("--fov", type=float, default=70)
    ap.add_argument("--eye")
    ap.add_argument("--target")
    ap.add_argument("--fog", type=float, default=1500)
    ap.add_argument("--fogcolor", default="185,205,235")
    ap.add_argument("--sky", default="110,160,230:200,220,245", help="top:horizon RGB")
    a = ap.parse_args()
    sc = json.load(open(a.scene))
    cam = sc["camera"]
    eye = np.array([float(x) for x in a.eye.split(",")]) if a.eye else np.array(cam["eye"], float)
    target = np.array([float(x) for x in a.target.split(",")]) if a.target else np.array(cam["target"], float)
    W = a.width
    H = W * 9 // 16
    r, u, f = look_at(eye, target)
    focal = (W / 2) / math.tan(math.radians(a.fov) / 2)
    fogc = np.array([float(x) for x in a.fogcolor.split(",")]) / 255
    top, hor = [np.array([float(x) for x in s.split(",")]) / 255 for s in a.sky.split(":")]

    img = np.zeros((H, W, 3))
    # sky gradient by view elevation
    ys = (np.arange(H) - H / 2) / focal
    for yi in range(H):
        d = f - ys[yi] * u
        el = max(0.0, d[1] / np.linalg.norm(d))
        img[yi, :] = hor + (top - hor) * min(1, el * 2.5)
    zbuf = np.full((H, W), np.inf)
    trans = []

    def project(P):
        rel = P - eye
        x, y, z = rel @ r, rel @ u, rel @ f
        return x, y, z

    opaque_tris = []
    for p in sc["parts"]:
        verts, tris = SHAPES.get(p["s"], SHAPES["block"])
        cf = p["cf"]
        pos = np.array(cf[0:3])
        R = np.array(cf[3:12]).reshape(3, 3)
        size = np.array(p["size"])
        world = (verts * size) @ R.T + pos
        col = np.array(p["col"]) / 255
        mat = p.get("mat", "")
        t = p.get("t", 0)
        if mat == "Glass":
            t = max(t, 0.35)
        if mat == "ForceField":
            t = max(t, 0.7)
        for tri in tris:
            P = world[list(tri)]
            n = np.cross(P[1] - P[0], P[2] - P[0])
            nn = np.linalg.norm(n)
            if nn < 1e-9:
                continue
            n = n / nn
            if mat == "Neon":
                c = np.minimum(1, col * 1.35 + 0.15)
            else:
                c = col * (0.55 + 0.45 * abs(n @ LIGHT))
            item = (P, c, t)
            (trans if t > 0.02 else opaque_tris).append(item)

    def raster(P, c, t, blend):
        x, y, z = project(P.T.T) if False else (None, None, None)
        rel = P - eye
        cx, cy, cz = rel @ r, rel @ u, rel @ f
        if (cz < 0.5).any():
            if (cz < 0.5).all():
                return
            # crude near-plane handling: skip triangles crossing the eye plane
            return
        sx = W / 2 + focal * cx / cz
        sy = H / 2 - focal * cy / cz
        x0, x1 = int(max(0, math.floor(sx.min()))), int(min(W - 1, math.ceil(sx.max())))
        y0, y1 = int(max(0, math.floor(sy.min()))), int(min(H - 1, math.ceil(sy.max())))
        if x0 > x1 or y0 > y1:
            return
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, bx, qx), (ay, by, qy) = sx, sy
        den = (by - qy) * (ax - qx) + (qx - bx) * (ay - qy)
        if abs(den) < 1e-9:
            return
        w0 = ((by - qy) * (gx - qx) + (qx - bx) * (gy - qy)) / den
        w1 = ((qy - ay) * (gx - qx) + (ax - qx) * (gy - qy)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            return
        iz = w0 / cz[0] + w1 / cz[1] + w2 / cz[2]
        depth = 1 / np.where(inside, iz, 1e-9)
        zb = zbuf[y0:y1 + 1, x0:x1 + 1]
        m = inside & (depth < zb)
        if not m.any():
            return
        fogk = np.clip(depth / a.fog, 0, 1)[..., None] ** 1.2
        shade = c * (1 - fogk) + fogc * fogk
        region = img[y0:y1 + 1, x0:x1 + 1]
        if blend:
            region[m] = region[m] * t + shade[m] * (1 - t)
        else:
            region[m] = shade[m]
            zb[m] = depth[m]

    for P, c, t in opaque_tris:
        raster(P, c, t, False)
    trans.sort(key=lambda it: -np.linalg.norm(it[0].mean(axis=0) - eye))
    for P, c, t in trans:
        raster(P, c, t, True)

    out = a.out or os.path.splitext(a.scene)[0] + ".png"
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(out)
    print(out)


if __name__ == "__main__":
    main()
