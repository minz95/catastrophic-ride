#!/usr/bin/env python3
"""Every symbol a player can see must be in Roblox's fonts: Gotham is
Montserrat, and what it lacks comes from the Twemoji emoji font. Characters
in neither drew an empty box ("✕" close buttons, a "⟲" reset icon; Studio
Device Simulator 2026-10-30). Studio itself also falls back to Noto CJK, so
a symbol can look right in Studio and still be a box on a phone.

    python3 tools/glyph_check.py          # lists missing symbols
    python3 tools/glyph_check.py --write  # rewrites tests/glyphs.txt (the
                                          # spec's list of checked symbols)
Needs Roblox Studio installed (reads its font files).
"""
import glob, re, struct, sys

FONTS = "/Applications/RobloxStudio.app/Contents/Resources/content/fonts/"
DIRS = ["roblox/StarterGui", "roblox/StarterPlayer", "roblox/ReplicatedStorage",
        "roblox/ServerScriptService/Modules/AbilityConfig.lua", "roblox/ServerScriptService/Modules/ItemConfig.lua"]


def cmap(path):
    d = open(path, "rb").read()
    num = struct.unpack(">H", d[4:6])[0]
    tables = {}
    for i in range(num):
        tag, _, off, _ = struct.unpack(">4sIII", d[12 + 16 * i:28 + 16 * i])
        tables[tag] = off
    o = tables[b"cmap"]
    codes = set()
    for i in range(struct.unpack(">H", d[o + 2:o + 4])[0]):
        _, _, so = struct.unpack(">HHI", d[o + 4 + 8 * i:o + 12 + 8 * i])
        s = o + so
        fmt = struct.unpack(">H", d[s:s + 2])[0]
        if fmt == 4:
            segx2 = struct.unpack(">H", d[s + 6:s + 8])[0]
            seg = segx2 // 2
            ends = struct.unpack(">%dH" % seg, d[s + 14:s + 14 + segx2])
            starts = struct.unpack(">%dH" % seg, d[s + 16 + segx2:s + 16 + 2 * segx2])
            for a, b in zip(starts, ends):
                if a != 0xFFFF:
                    codes.update(range(a, b + 1))
        elif fmt == 12:
            for g in range(struct.unpack(">I", d[s + 12:s + 16])[0]):
                a, b, _ = struct.unpack(">III", d[s + 16 + 12 * g:s + 28 + 12 * g])
                codes.update(range(a, b + 1))
    return codes


def visible_chars():
    """Non-ASCII characters inside string literals (not comments) of client
    code and the item / ability data clients show."""
    files = []
    for d in DIRS:
        files += [d] if d.endswith(".lua") else glob.glob(d + "/**/*.lua", recursive=True)
    out = {}
    for f in files:
        for line in open(f, encoding="utf-8"):
            code = line.split("--", 1)[0] if not line.lstrip().startswith("--") else ""
            for s in re.findall(r'"([^"]*)"', code):
                for ch in s:
                    if ord(ch) > 0x7F and ch not in "️‍":
                        out.setdefault(ch, f)
    return out


def main():
    ok = cmap(FONTS + "Montserrat-Black.ttf") | cmap(FONTS + "TwemojiMozilla.ttf")
    chars = visible_chars()
    missing = {c: f for c, f in chars.items() if ord(c) not in ok}
    for c, f in sorted(missing.items()):
        print("MISSING %s U+%04X  (%s)" % (c, ord(c), f))
    if "--write" in sys.argv:
        good = "".join(sorted(c for c in chars if ord(c) in ok))
        open("tests/glyphs.txt", "w", encoding="utf-8").write(good + "\n")
        print("tests/glyphs.txt: %d symbols" % len(good))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
