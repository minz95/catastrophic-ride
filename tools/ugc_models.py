"""Builds the achievement hats as Marketplace avatar items (docs/ugc.md).

Runs inside Blender (headless):

    lune run tools/ugc_dump.luau
    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/ugc_models.py [-- id id …]

Reads assets/ugc/designs.json (the game's own hat parts, Shared/HatDesigns),
the part-built ride-on of tools/ugc_rides.py and the hand-modelled items of
tools/ugc_custom.py, and writes, per item, into assets/ugc/<id>/:
  <id>.fbx      one mesh, one material, UVs on a colour palette (UGC rules:
                a single mesh and texture; Roblox's FBX importer ignores
                Blender's Base Color, so the colours live in the texture)
  texture.png   the palette (also embedded in the FBX)
  preview.png   a front three-quarter picture

Units are studs (import in Studio with Scale Unit = Stud). The origin is the
middle of the head's top for hats, the waist for ride-ons.
"""
import json
import math
import os

import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "ugc", "designs.json")
OUT = os.path.join(ROOT, "assets", "ugc")

CELL = 32          # px per palette cell
GRID = 8           # cells per side → 256 px texture
MAX_TRIS = 4000    # Roblox UGC accessory limit

# Roblox (X right of the wearer, Y up, -Z the face side) → Blender (Z up,
# the face towards -Y): a proper rotation, so no faces flip.
R2B = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))


def finish_colour(rgb, finish):
    r, g, b = rgb
    if finish == "glow":
        r, g, b = (min(255, int(c * 1.2 + 30)) for c in (r, g, b))
    return (r, g, b)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def part_verts(bm, part):
    """Adds one part to `bm` in Roblox space; returns its new faces."""
    before = set(bm.faces)
    shape = part["shape"]
    if shape == "ball":
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.5)
    elif shape == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.5, radius2=0.5, depth=1.0)
    else:
        bmesh.ops.create_cube(bm, size=1.0)
    faces = [f for f in bm.faces if f not in before]
    verts = {v for f in faces for v in f.verts}
    sx, sy, sz = part["size"]
    rx, ry, rz = (math.radians(a) for a in part["rot"])
    rot = (Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rz, 3, "Z"))
    pos = Vector(part["pos"])
    for v in verts:
        x, y, z = v.co
        if shape == "cyl":
            x, y, z = x, z, y            # Blender's cone stands on Z; the design's cylinder on Y
        local = Vector((x * sx, y * sy, z * sz))
        v.co = R2B @ (rot @ local + pos)
    return faces


def parts_objects(parts):
    """The game's part lists (HatDesigns fields, Roblox axes) as objects, one per part."""
    objs = []
    for part in parts:
        bm = bmesh.new()
        part_verts(bm, part)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new("part")
        bm.to_mesh(mesh)
        bm.free()
        o = bpy.data.objects.new("part", mesh)
        bpy.context.collection.objects.link(o)
        o["rgb"] = list(finish_colour(part["color"], part["finish"]))
        objs.append(o)
    return objs


def join_with_palette(name, objs):
    """Applies modifiers, points every face of an object at its colour's
    palette cell, joins all into one mesh. Returns (object, palette)."""
    palette = []
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")     # bakes bevel / solidify
    for o in objs:
        colour = tuple(int(c) for c in o["rgb"])
        if colour not in palette:
            palette.append(colour)
        k = palette.index(colour)
        cu = ((k % GRID) + 0.5) / GRID
        cv = 1 - ((k // GRID) + 0.5) / GRID
        me = o.data
        if not me.uv_layers:
            me.uv_layers.new(name="UVMap")
        for d in me.uv_layers.active.data:
            d.uv = (cu, cv)
        for poly in me.polygons:
            poly.use_smooth = False
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj, palette


def build_item(item, kind, builder=None):
    clear_scene()
    objs = parts_objects(item["parts"]) if builder is None else None
    if builder is not None:
        builder()
        objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    obj, palette = join_with_palette(item["id"], objs)
    mesh = obj.data

    # the palette texture
    size = CELL * GRID
    img = bpy.data.images.new(item["id"] + "_texture", size, size, alpha=False)
    px = [0.0] * (size * size * 4)
    for k, (r, g, b) in enumerate(palette):
        cx, cy = (k % GRID) * CELL, (GRID - 1 - (k // GRID)) * CELL
        for y in range(cy, cy + CELL):
            for x in range(cx, cx + CELL):
                i = (y * size + x) * 4
                px[i:i + 4] = [r / 255, g / 255, b / 255, 1.0]
    img.pixels = px
    folder = os.path.join(OUT, item["id"])
    os.makedirs(folder, exist_ok=True)
    img.filepath_raw = os.path.join(folder, "texture.png")
    img.file_format = "PNG"
    img.save()
    img.pack()

    mat = bpy.data.materials.new(item["id"])
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    node.interpolation = "Closest"
    mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    mesh.materials.clear()
    mesh.materials.append(mat)

    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    fbx = os.path.join(folder, item["id"] + ".fbx")
    bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, object_types={"MESH"},
                             bake_space_transform=True, path_mode="COPY", embed_textures=True,
                             global_scale=1.0, apply_unit_scale=True)
    preview(obj, os.path.join(folder, "preview.png"), kind)
    dims = obj.dimensions
    return {"id": item["id"], "name": item["name"], "kind": kind, "type": item.get("type"),
            "achievement": item.get("achievement"), "tris": tris, "colours": len(palette),
            "size_studs": [round(dims.x, 2), round(dims.z, 2), round(dims.y, 2)]}


def _plain(name, colour):
    m = bpy.data.materials.new(name)
    m.diffuse_color = colour
    return m


def preview(obj, path, kind):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.film_transparent = True
    stand_in = []
    skin = _plain("skin", (0.95, 0.8, 0.6, 1))
    shirt = _plain("shirt", (0.3, 0.5, 0.9, 1))
    if kind == "hat":
        # a plain head under it, for scale
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.6, location=(0, 0, -0.6))
        stand_in.append((bpy.context.active_object, skin))
        centre, eye_off = Vector((0, 0, 0.1)), Vector((2.6, -4.4, 2.2))
    else:
        # a blocky R15-sized avatar standing in the cockpit (waist at 0)
        for size, loc, mat in (((2, 1, 2), (0, 0, 1.0), shirt), ((1.2, 1.2, 1.2), (0, 0, 2.6), skin),
                               ((0.9, 0.9, 2.4), (-0.5, 0, -1.3), shirt), ((0.9, 0.9, 2.4), (0.5, 0, -1.3), shirt),
                               ((0.8, 0.8, 2.0), (-1.45, 0, 1.0), skin), ((0.8, 0.8, 2.0), (1.45, 0, 1.0), skin)):
            bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
            o = bpy.context.active_object
            o.scale = size
            stand_in.append((o, mat))
        centre, eye_off = Vector((0, 0, -0.4)), Vector((7.5, -9.5, 5.0))
    for o, m in stand_in:
        o.data.materials.append(m)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 60
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    eye = centre + eye_off
    cam.location = eye
    cam.rotation_euler = (centre - eye).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o, _ in stand_in:
        bpy.data.objects.remove(o)


def main():
    with open(SRC) as f:
        designs = json.load(f)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import ugc_custom
    import ugc_rides
    only = set(a for a in sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else None
    items = [(h, "hat", None) for h in designs["hats"]]
    items += [(r, "ride", None) for r in ugc_rides.RIDES]
    items += [(c, c["kind"], ugc_custom.BUILDERS[c["id"]]) for c in ugc_custom.ITEMS]
    report = []
    old = {}
    path = os.path.join(OUT, "report.json")
    if only and os.path.exists(path):
        with open(path) as f:
            old = {r["id"]: r for r in json.load(f)}
    for item, kind, builder in items:
        if only and item["id"] not in only:
            if item["id"] in old:
                report.append(old[item["id"]])
            continue
        r = build_item(item, kind, builder)
        if r["tris"] > MAX_TRIS:
            raise SystemExit("%s: %d triangles (limit %d)" % (r["id"], r["tris"], MAX_TRIS))
        report.append(r)
        print("UGC", json.dumps(r))
    with open(path, "w") as f:
        json.dump(report, f, indent=2)


main()
