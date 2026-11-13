#!/usr/bin/env python3
"""Turn approved free Creator Store models into item model data (macOS).

    python3 tools/studio/store_models.py

Reads the approved list (roblox/ReplicatedStorage/Shared/StoreModels.lua:
item name → asset id, picked with tools/model_search.py and approved by a
person), loads each model in Studio (`RobloxStudio -task RunScript`, the
place is not saved), refuses any model with a script in it, and writes
roblox/ServerScriptService/Modules/StoreModelData.lua: per item its parts
(MeshPart mesh / texture ids or a plain Part's shape, size, colour,
material, position relative to the model centre). ItemModelPreloader
builds the items from that file like ItemMeshData. Checks on the way that
every mesh loads with AssetService:CreateMeshPartAsync.
"""

import glob
import json
import os
import re
import subprocess
import tempfile
import time
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIST = os.path.join(ROOT, "roblox", "ReplicatedStorage", "Shared", "StoreModels.lua")
OUT = os.path.join(ROOT, "roblox", "ServerScriptService", "Modules", "StoreModelData.lua")
STUDIO = os.environ.get("ROBLOX_STUDIO", "/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio")
LOG_DIR = os.path.expanduser("~/Library/Logs/Roblox")
PLACE_ID, UNIVERSE_ID = "74883519312765", "9983801557"

LUAU = r"""
print("STORE_RUN __TOKEN__")
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local AssetService = game:GetService("AssetService")
local LIST = HttpService:JSONDecode([==[__LIST__]==])
local out = {}
for name, id in pairs(LIST) do
  local root, how
  local ok, res = pcall(function() return InsertService:LoadAsset(id) end)
  if ok and res then root, how = res, "insert" else
    local ok2, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
    if ok2 and objs and objs[1] then
      root = Instance.new("Model"); for _, o in ipairs(objs) do o.Parent = root end; how = "objects"
    else
      out[name] = { err = tostring(res) .. " / " .. tostring(objs) }
    end
  end
  if root then
    local parts, scripts, other = {}, 0, {}
    for _, d in ipairs(root:GetDescendants()) do
      if d:IsA("LuaSourceContainer") then scripts += 1 end
      if d:IsA("BasePart") then
        local e = { n = d.Name, cls = d.ClassName, cf = { d.CFrame:GetComponents() },
          s = { d.Size.X, d.Size.Y, d.Size.Z }, col = { d.Color.R, d.Color.G, d.Color.B },
          mat = d.Material.Name, tr = d.Transparency }
        if d:IsA("MeshPart") then
          e.mesh = d.MeshId; e.tex = d.TextureID
          local sa = d:FindFirstChildWhichIsA("SurfaceAppearance")
          if sa then e.sa = sa.ColorMap end
          local okm, mp = pcall(function() return AssetService:CreateMeshPartAsync(d.MeshId) end)
          e.loads = okm and mp ~= nil
          if not okm then e.loadErr = tostring(mp) end
        elseif d:IsA("Part") then
          e.shape = d.Shape.Name
          local sm = d:FindFirstChildWhichIsA("SpecialMesh")
          if sm then e.special = { sm.MeshType.Name, sm.MeshId, sm.TextureId, sm.Scale.X, sm.Scale.Y, sm.Scale.Z } end
        end
        for _, c in ipairs(d:GetChildren()) do
          if c:IsA("Decal") or c:IsA("Texture") then e.decals = (e.decals or 0) + 1 end
        end
        table.insert(parts, e)
      end
    end
    out[name] = { how = how, scripts = scripts, parts = parts }
    root:Destroy()
  end
end
local s = HttpService:JSONEncode(out)
for i = 1, #s, 800 do print("SJ " .. s:sub(i, i + 799)) end
print("STORE_END __TOKEN__")
"""


def read_list():
    with open(LIST) as f:
        src = f.read()
    return {m[0]: int(m[1]) for m in re.findall(r'\["([^"]+)"\]\s*=\s*\{\s*id\s*=\s*(\d+)', src)}


def r(x, n=3):
    v = round(x, n)
    return 0 if v == 0 else v


def lua_part(p, centre):
    cf = p["cf"]
    pos = [cf[0] - centre[0], cf[1] - centre[1], cf[2] - centre[2]]
    rot = cf[3:12]
    f = ['n = %s' % json.dumps(p["n"])]
    if p.get("mesh"):
        f.append('mesh = "%s"' % p["mesh"])
        tex = p.get("tex") or p.get("sa") or ""
        if tex:
            f.append('tex = "%s"' % tex)
    else:
        f.append('shape = "%s"' % p.get("shape", "Block"))
    f.append("s = { %s }" % ", ".join(str(r(x)) for x in p["s"]))
    f.append("p = { %s }" % ", ".join(str(r(x)) for x in pos))
    if not all(abs(a - b) < 1e-4 for a, b in zip(rot, [1, 0, 0, 0, 1, 0, 0, 0, 1])):
        f.append("rot = { %s }" % ", ".join(str(r(x, 5)) for x in rot))
    f.append("col = { %s }" % ", ".join(str(round(c * 255)) for c in p["col"]))
    f.append('mat = "%s"' % p["mat"])
    if p.get("tr", 0) > 0:
        f.append("tr = %s" % r(p["tr"], 2))
    return "\t\t{ " + ", ".join(f) + " },"


def keep(p):
    if p.get("tr", 0) >= 0.99:
        return False                       # invisible hitboxes / roots
    if p.get("cls") == "MeshPart":
        return bool(p.get("mesh"))
    return p.get("cls") == "Part" and not p.get("special")


def write(data):
    lines = [
        "-- StoreModelData.lua (generated by tools/studio/store_models.py — do not edit)",
        "-- Free Creator Store models approved as items (Shared/StoreModels), as",
        "-- data: per item its parts (MeshPart mesh / texture ids, or a plain Part's",
        "-- shape), size, position `p` relative to the model's centre, optional",
        "-- rotation `rot`, colour `col` (0-255) and material. ItemModelPreloader",
        "-- builds the models from this.",
        "",
        "return {",
    ]
    for name in sorted(data):
        parts = [p for p in data[name].get("parts", []) if keep(p)]
        if not parts:
            continue
        lo = [min(p["cf"][i] - p["s"][i] / 2 for p in parts) for i in range(3)]
        hi = [max(p["cf"][i] + p["s"][i] / 2 for p in parts) for i in range(3)]
        centre = [(a + b) / 2 for a, b in zip(lo, hi)]
        lines.append('\t["%s"] = {' % name)
        for p in parts:
            lines.append(lua_part(p, centre))
        lines.append("\t},")
    lines.append("}")
    with open(OUT, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", nargs="+", metavar="NAME=ID",
                    help="only report on these candidates (unions, meshes that load); writes nothing")
    a = ap.parse_args()
    wanted = dict((x.split("=")[0], int(x.split("=")[1])) for x in a.check) if a.check else read_list()
    token = uuid.uuid4().hex
    work = tempfile.mkdtemp(prefix="store-models-")
    script = os.path.join(work, "store.luau")
    with open(script, "w") as f:
        f.write(LUAU.replace("__TOKEN__", token).replace("__LIST__", json.dumps(wanted)))
    t0 = time.time()
    proc = subprocess.Popen([STUDIO, "-task", "RunScript", "-placeId", PLACE_ID, "-universeId", UNIVERSE_ID,
                             "-runScriptFile", script, "-quitAfterExecution"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log = None
    while time.time() - t0 < 300:
        time.sleep(3)
        for path in sorted(glob.glob(os.path.join(LOG_DIR, "*_Studio_*_last.log")), key=os.path.getmtime)[-6:]:
            if os.path.getmtime(path) < t0 - 5:
                continue
            with open(path, errors="replace") as f:
                if ("STORE_END " + token) in f.read():
                    log = path
        if log:
            break
    time.sleep(2)
    if proc.poll() is None:
        proc.terminate()
    if not log:
        raise SystemExit("no output from Studio (logged in? place id right?)")
    with open(log, errors="replace") as f:
        txt = f.read()
    data = json.loads("".join(re.findall(r"\[FLog::CreatorOutput\] SJ (.*)", txt)))
    with open(os.path.join(work, "dump.json"), "w") as f:
        json.dump(data, f, indent=1)
    bad = []
    for name in sorted(wanted):
        d = data.get(name) or {"err": "missing"}
        if d.get("err") or d.get("scripts"):
            bad.append(name)
            print("%-18s REFUSED %s" % (name, d.get("err") or "%d scripts" % d["scripts"]))
            continue
        parts = d["parts"]
        kept = [p for p in parts if keep(p)]
        noload = [p["n"] for p in kept if p.get("mesh") and not p.get("loads")]
        unions = [p for p in parts if p["cls"] in ("UnionOperation", "NegateOperation") and p.get("tr", 0) < 0.99]
        if unions or noload:
            bad.append(name)       # unions cannot be rebuilt from data; a mesh that will not load shows nothing
        print("%-18s %3d parts, %3d kept, %2d unions, meshes not loading: %s" % (
            name, len(parts), len(kept), len(unions), ",".join(noload) or "-"))
    if a.check:
        return
    for name in bad:
        data.pop(name, None)
    write(data)
    print("dump: %s\n→ %s" % (os.path.join(work, "dump.json"), os.path.relpath(OUT, ROOT)))


if __name__ == "__main__":
    main()
