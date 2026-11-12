#!/usr/bin/env python3
"""Search the Creator Store for free 3D models without Studio, keeping only
safe candidates, and draw a contact sheet to pick from.

    python3 tools/model_search.py "washing machine" "traffic cone" [--per 2] [--sheet out.png]

Kept: free, no scripts (instanceCounts.script == 0 and hasScripts false), at
least one MeshPart, at most --max-tris triangles, a verified creator or an
endorsed asset. Free models with scripts are skipped outright: they are the
usual way a backdoor gets into a place. Nothing is inserted anywhere; this
only lists candidates for a person to approve.
"""
import argparse, io, json, urllib.parse, urllib.request

UA = {"User-Agent": "Mozilla/5.0"}


def get(url, raw=False):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=20) as r:
        data = r.read()
    return data if raw else json.loads(data)


def details(ids):
    out = []
    for i in range(0, len(ids), 30):
        chunk = ",".join(str(x) for x in ids[i:i + 30])
        out += get("https://apis.roblox.com/toolbox-service/v1/items/details?assetIds=" + chunk).get("data", [])
    return out


def safe(d, max_tris):
    a, c = d["asset"], d["creator"]
    tech = a.get("modelTechnicalDetails") or {}
    counts = tech.get("instanceCounts") or {}
    tris = (tech.get("objectMeshSummary") or {}).get("triangles") or 0
    free = (d.get("fiatProduct") or {}).get("isFree")
    why = []
    if not free: why.append("not free")
    if a.get("hasScripts") or counts.get("script", 0) > 0: why.append("scripts")
    if counts.get("meshPart", 0) < 1: why.append("no mesh")
    if tris > max_tris: why.append(f"{tris} tris")
    if not (c.get("isVerifiedCreator") or a.get("isEndorsed")): why.append("unverified")
    if counts.get("tool", 0) or counts.get("audio", 0): why.append("tool/audio")
    return why, tris


def search(term, per, max_tris):
    q = urllib.parse.urlencode({"keyword": term, "limit": 30})
    ids = [x["id"] for x in get("https://apis.roblox.com/toolbox-service/v1/marketplace/10?" + q).get("data", [])]
    picks = []
    for d in details(ids):
        why, tris = safe(d, max_tris)
        if not why:
            a, c = d["asset"], d["creator"]
            v = d.get("voting") or {}
            picks.append({"term": term, "id": a["id"], "name": a["name"].strip(), "creator": c["name"],
                          "tris": tris, "parts": (a["modelTechnicalDetails"]["instanceCounts"].get("meshPart", 0)),
                          "up": v.get("upVotes", 0), "endorsed": a.get("isEndorsed", False)})
        if len(picks) >= per:
            break
    return picks


def thumbs(ids):
    q = urllib.parse.urlencode({"assetIds": ",".join(str(i) for i in ids), "size": "420x420", "format": "Png"})
    return {t["targetId"]: t.get("imageUrl") for t in get("https://thumbnails.roblox.com/v1/assets?" + q).get("data", [])}


def sheet(picks, path):
    from PIL import Image, ImageDraw, ImageFont
    urls = {}
    for i in range(0, len(picks), 50):
        urls.update(thumbs([p["id"] for p in picks[i:i + 50]]))
    cell, cols = 220, 5
    rows = (len(picks) + cols - 1) // cols
    img = Image.new("RGB", (cell * cols, (cell + 40) * rows), (245, 245, 245))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 15)
    except Exception:
        font = ImageFont.load_default()
    for n, p in enumerate(picks):
        x, y = (n % cols) * cell, (n // cols) * (cell + 40)
        url = urls.get(p["id"])
        if url:
            try:
                im = Image.open(io.BytesIO(get(url, raw=True))).convert("RGB").resize((cell - 10, cell - 10))
                img.paste(im, (x + 5, y + 5))
            except Exception:
                pass
        draw.text((x + 8, y + cell - 2), f"#{n + 1} {p['term']}"[:28], fill=(20, 20, 20), font=font)
        draw.text((x + 8, y + cell + 17), f"{p['tris']} tris, {p['parts']} mesh", fill=(90, 90, 90), font=font)
    img.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("terms", nargs="+")
    ap.add_argument("--per", type=int, default=2)
    ap.add_argument("--max-tris", type=int, default=15000)
    ap.add_argument("--sheet")
    ap.add_argument("--json")
    a = ap.parse_args()
    picks = []
    for t in a.terms:
        got = search(t, a.per, a.max_tris)
        if not got:
            print(f"== {t}: nothing safe")
        picks += got
    for n, p in enumerate(picks):
        print(f"#{n + 1:<3} {p['term']:<18} {p['id']:>16}  {p['creator']:<20} {p['tris']:>6} tris  {p['name']}")
    if a.json:
        with open(a.json, "w") as f:
            json.dump(picks, f, indent=1, ensure_ascii=False)
    if a.sheet:
        sheet(picks, a.sheet)


if __name__ == "__main__":
    main()
