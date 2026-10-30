#!/usr/bin/env python3
"""Screen elements that overlap, from a Studio run with uiDump (BotDriver
reports kind "ui": every visible element at the top of a ScreenGui, its box
on screen and its UDim2 layout).

    python3 tools/studio/ui_overlap.py [reports/studio/ui-layout.json]
    python3 tools/studio/ui_overlap.py --phone [reports/studio/ui-layout.json]

For every phase it lists pairs of elements whose drawn boxes overlap at the
bot's window, then recomputes the layout for other window sizes (SIZES) and
lists what overlaps there. Roblox's own top bar, chat window and player list
are added as approximate zones. Elements that cover most of the screen
(backdrops, the crafting panel) are reported apart, not paired.
"""
import json
import subprocess
import sys

SIZES = [(1920, 1080), (1366, 768), (1280, 720), (1024, 640)]
FULL = 0.45          # an element covering this share of the window is a backdrop / panel
# Studio-only screens (live games never show them)
IGNORE = {"MusicTry"}
# placed at run time by Shared/SideButtons: mid-height, or up over the key list
SIDE = {"OpenShop", "OpenGuide"}
GAP = 8
MIN_OVERLAP = 6      # px each way: smaller touches are rounding

# Roblox's own UI (approximate, top-left of the whole window)
def core_zones(w, h, inset):
    return [
        {"screen": "Roblox", "name": "TopBarButtons", "box": [0, 0, 260, inset or 58]},
        {"screen": "Roblox", "name": "ChatWindow (approx.)", "box": [8, (inset or 58) + 4, 400, 230]},
        {"screen": "Roblox", "name": "PlayerList (approx.)", "box": [w - 190, (inset or 58) + 4, 180, 120]},
    ]


def overlap(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    ox = min(ax + aw, bx + bw) - max(ax, bx)
    oy = min(ay + ah, by + bh) - max(ay, by)
    return (ox, oy) if ox >= MIN_OVERLAP and oy >= MIN_OVERLAP else None


def scaled(e):
    """Drawn at another size than its UDim2 (a UIScale, e.g. the crafting
    screen shrinking in small windows): its layout in another window cannot
    be worked out from the dump, so it is checked at the run's window only."""
    if e["auto"]:
        return False
    s, r = e["size"], e["rect"]
    return s[0] == 0 and s[2] == 0 and (abs(s[1] - r[2]) > 2 or abs(s[3] - r[3]) > 2)


def relayout(e, w, h, inset, view):
    """The element's box in a w × h window (from its UDim2 layout)."""
    sw, sh = w, h if e["ignoreInset"] else h - inset
    oy = 0 if e["ignoreInset"] else inset
    ox0, oy0 = e["screenOrigin"]
    rx, ry, rw, rh = e["rect"]
    if e["auto"]:
        nw, nh = rw, rh
    else:
        s = e["size"]
        nw, nh = s[0] * sw + s[1], s[2] * sh + s[3]
    p, a = e["pos"], e["anchor"]
    nx = p[0] * sw + p[1] - a[0] * nw
    ny = p[2] * sh + p[3] - a[1] * nh + oy
    bx, by, bw, bh = e["box"]
    # the drawn box moves with the element and stretches with its size
    return [bx + (nx - rx), by + (ny - ry), bw + (nw - rw), bh + (nh - rh)]


def side_buttons(els, w, h):
    """Shared/SideButtons for a relaid window: mid-height, moved up over KeyStrip."""
    strip = next((e for e in els if e["name"] == "KeyStrip"), None)
    out = []
    for e in els:
        if e["name"] in SIDE and e["screen"] not in ("CraftingUI",):
            x, y, bw, bh = e["box"]
            cy = h / 2
            if strip and cy + bh / 2 > strip["box"][1] - GAP:
                cy = strip["box"][1] - GAP - bh / 2
            e = dict(e, box=[x, max(cy - bh / 2, GAP), bw, bh])
        out.append(e)
    return out


def pairs(elements, w, h):
    full = [e for e in elements if e["box"][2] * e["box"][3] > FULL * w * h]
    rest = [e for e in elements if e not in full]
    out = []
    for i, a in enumerate(rest):
        for b in rest[i + 1:]:
            if a["screen"] == "Roblox" and b["screen"] == "Roblox":
                continue
            o = overlap(a["box"], b["box"])
            if o:
                out.append((a, b, o))
    return out, full


def name(e):
    return "%s/%s" % (e["screen"], e["name"])


def game_overlaps(report):
    """[(phase, a, b, where)] for pairs of the game's own elements (not
    Roblox's approximate zones), for sim.py's uiOverlap check."""
    out = []
    for (ph, a, b), where in collect(report).items():
        if not a.startswith("Roblox/") and not b.startswith("Roblox/"):
            out.append((ph, a, b, sorted(set(where))))
    return out


def collect(r):
    ev = r["telemetry"]["events"]
    snaps = [(e.get("data") or {}) for e in ev if e.get("kind") == "bot_ui"]
    found = {}
    for s in snaps:
        view = s.get("view") or [1280, 720]
        inset = s.get("inset") or 0
        els = [e for e in s["elements"] if e["screen"] not in IGNORE]
        for size in [tuple(view)] + SIZES:
            sw, sh = size
            if size == tuple(view):
                cur = els
            else:
                cur = side_buttons([dict(e, box=relayout(e, sw, sh, inset, view)) for e in els if not scaled(e)], sw, sh)
            ps, _ = pairs(cur + core_zones(sw, sh, inset), sw, sh)
            for a, b, o in ps:
                found.setdefault((s["phase"], name(a), name(b)), []).append("%dx%d (%dx%d px)" % (sw, sh, o[0], o[1]))
    return found


# --phone: the same layout on phone / tablet screens with the touch buttons
# (tools/phone_layout.luau, the real Shared/TouchLayout) and Roblox's mobile
# controls (jump button, the side where the thumbstick starts). The key strip
# is not shown on touch-only devices (TutorialUI).
PHONE_HIDDEN = {"KeyStrip"}


def phone_cases():
    out = subprocess.run(["lune", "run", "tools/phone_layout.luau", "--json"],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out[out.index("["):])


def phone(r):
    cases = phone_cases()
    snaps = [(e.get("data") or {}) for e in r["telemetry"]["events"] if e.get("kind") == "bot_ui"]
    inset = snaps[0].get("inset") or 0
    found = {}
    screens = {}
    for c in cases:
        screens.setdefault((c["screen"], c["w"], c["h"]), []).append(c)
    for s in snaps:
        els = [e for e in s["elements"] if e["screen"] not in IGNORE and e["name"] not in PHONE_HIDDEN]
        for (sname, w, h), cs in screens.items():
            cur = side_buttons([dict(e, box=relayout(e, w, h, inset, None)) for e in els if not scaled(e)], w, h)
            z = cs[0]["zones"]
            roblox = [
                {"screen": "Roblox", "name": "TopBarButtons", "box": [0, 0, 260, inset or 58]},
                {"screen": "Roblox", "name": "JumpButton", "box": z["jump"]},
                {"screen": "Roblox", "name": "ThumbstickSide", "box": z["thumbstick"]},
            ]
            touch_sets = [c for c in cs if c["phase"] == s["phase"]] or [None]
            for c in touch_sets:
                touch = [{"screen": "Touch", "name": b["name"], "box": b["box"]} for b in (c["buttons"] if c else [])]
                ps, full = pairs(cur + touch + roblox, w, h)
                for a, b, o in ps:
                    if a["screen"] == "Touch" and b["screen"] in ("Touch", "Roblox"):
                        continue   # tests/specs/phone_layout checks these
                    if b["screen"] == "Touch" and a["screen"] == "Roblox":
                        continue
                    key = (s["phase"], name(a), name(b))
                    found.setdefault(key, set()).add("%s %dx%d" % (sname, w, h))
                for f in full:
                    found.setdefault((s["phase"], name(f), "(covers most of the screen)"), set()).add("%s %dx%d" % (sname, w, h))
    order = ["LOBBY", "FARMING", "CRAFTING", "RACING", "RESULTS"]
    for ph in order:
        rows = sorted((a, b, sorted(v)) for (p, a, b), v in found.items() if p == ph)
        if rows:
            print("\n%s" % ph)
            for a, b, where in rows:
                print("  %-36s x %-36s %s" % (a, b, ", ".join(where[:3]) + (" …" if len(where) > 3 else "")))
    if not found:
        print("no overlaps on phones")
    return 0


def main():
    args = [a for a in sys.argv[1:] if a != "--phone"]
    path = args[0] if args else "reports/studio/ui-layout.json"
    if "--phone" in sys.argv:
        return phone(json.load(open(path))["report"])
    r = json.load(open(path))["report"]
    snaps = [(e.get("data") or {}) for e in r["telemetry"]["events"] if e.get("kind") == "bot_ui"]
    if not snaps:
        print("no ui reports (run the ui-layout scenario)")
        return 1
    found = collect(r)
    print("window during the run: %s, top bar %s px" % (snaps[0].get("view"), snaps[0].get("inset")))
    order = ["LOBBY", "FARMING", "CRAFTING", "RACING", "RESULTS"]
    byphase = {}
    for (ph, a, b), where in found.items():
        byphase.setdefault(ph, []).append((a, b, sorted(set(where))))
    for ph in order + sorted(set(byphase) - set(order)):
        if ph in byphase:
            print("\n%s" % ph)
            for a, b, where in sorted(byphase[ph]):
                print("  %-40s x %-40s %s" % (a, b, ", ".join(where[:3]) + (" …" if len(where) > 3 else "")))
    if not found:
        print("no overlaps")
    return 0


if __name__ == "__main__":
    sys.exit(main())
