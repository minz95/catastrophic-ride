#!/usr/bin/env python3
"""Search the Creator Store for sounds without Studio.

    python3 tools/sound_search.py "ui pop" "soft click" [--creator ProSoundEffects] [--limit 8]
    python3 tools/sound_search.py --id 258057783 6026984224    # name + uploader of ids

Keeps only licensed catalogues (APMOfficial, ProSoundEffects, DistrokidOfficial)
unless --any. Still load-check new ids with `sim.py run sounds` before release.
"""
import argparse, json, urllib.parse, urllib.request

LICENSED = {"APMOfficial", "ProSoundEffects", "DistrokidOfficial"}

def get(url):
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read())

def details(aid):
    try:
        d = get(f"https://economy.roblox.com/v2/assets/{aid}/details")
    except Exception as e:  # noqa
        return {"id": aid, "error": str(e)}
    desc = (d.get("Description") or "").replace("\n", " ")
    return {"id": aid, "name": (d.get("Name") or "").strip(), "creator": d["Creator"]["Name"], "desc": desc[:90]}

def search(q, creator, limit, any_creator):
    params = {"keyword": q, "limit": 30}
    if creator:
        params["creatorName"] = creator
    url = "https://apis.roblox.com/toolbox-service/v1/marketplace/3?" + urllib.parse.urlencode(params)
    out = []
    for item in get(url).get("data", []):
        d = details(item["id"])
        if any_creator or d.get("creator") in LICENSED:
            out.append(d)
        if len(out) >= limit:
            break
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("terms", nargs="*")
    ap.add_argument("--id", nargs="*")
    ap.add_argument("--creator", default="ProSoundEffects")
    ap.add_argument("--limit", type=int, default=8)
    ap.add_argument("--any", action="store_true")
    a = ap.parse_args()
    for aid in a.id or []:
        print(json.dumps(details(aid), ensure_ascii=False))
    for t in a.terms:
        print(f"== {t}")
        for d in search(t, a.creator, a.limit, a.any):
            print(f"  {d['id']:>16}  {d.get('creator','?'):<18} {d.get('name','')}  | {d.get('desc','')}")

if __name__ == "__main__":
    main()
