"""Hand-modelled avatar items (Blender only; tools/ugc_models.py runs them).

Each builder makes Blender objects in Blender's axes (Z up, the wearer's
front towards -Y), in studs, and tags each with its colour (`rgb`) through
`add`. ugc_models.py joins them into one mesh with a palette texture.

Origins: the waist (WaistCenterAttachment, ~2.6 studs over the ground) for
ride-ons and the belt, the middle of the head's top for the helmet.
"""
import math

import bmesh
import bpy
from mathutils import Vector

GROUND = -2.6

WHITE = (248, 248, 250)
SEAT = (232, 234, 240)
CHROME = (200, 205, 215)
DARK = (35, 35, 40)
RED = (220, 40, 45)
GOLD = (255, 196, 40)
METAL = (185, 190, 200)
PAPER = (252, 252, 248)
CARDBOARD = (165, 125, 85)


def add(obj, rgb, bevel=0.0, segments=2):
    obj["rgb"] = list(rgb)
    if bevel > 0:
        m = obj.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = segments
        m.limit_method = "ANGLE"
    return obj


def _active():
    return bpy.context.active_object


def cube(size, loc, rgb, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[math.radians(a) for a in rot])
    o = _active()
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return add(o, rgb, bevel)


def cyl(r, depth, loc, rgb, rot=(0, 0, 0), verts=16, r2=None, scale=(1, 1, 1)):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc,
                                            rotation=[math.radians(a) for a in rot])
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc,
                                        rotation=[math.radians(a) for a in rot])
    o = _active()
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return add(o, rgb)


def sphere(r, loc, rgb, scale=(1, 1, 1), seg=16, rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=loc)
    o = _active()
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return add(o, rgb)


def torus(R, r, loc, rgb, scale=(1, 1, 1), rot=(0, 0, 0), major=24, minor=8):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=major, minor_segments=minor,
                                     location=loc, rotation=[math.radians(a) for a in rot])
    o = _active()
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return add(o, rgb)


def bar(p1, p2, r, rgb, verts=6):
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d.length, location=(p1 + p2) / 2)
    o = _active()
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    return add(o, rgb)


def cut(obj, keep):
    """Deletes the faces whose centre (world) fails `keep(Vector)`."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    mw = obj.matrix_world
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not keep(mw @ f.calc_center_median())], context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def solidify(obj, t):
    m = obj.modifiers.new("solid", "SOLIDIFY")
    m.thickness = t
    m.offset = -1
    return obj


def wheel(x, y, r, width, tyre=DARK, hub=CHROME, z=None):
    z = GROUND + r if z is None else z
    cyl(r, width, (x, y, z), tyre, rot=(0, 90, 0), verts=18)
    cyl(r * 0.55, width + 0.04, (x, y, z), hub, rot=(0, 90, 0), verts=12)


def steering(at, rgb=DARK, column_from=None):
    """A little steering wheel facing the rider, tilted towards them."""
    torus(0.3, 0.05, at, rgb, rot=(-60, 0, 0), major=16, minor=6)
    if column_from:
        bar(column_from, at, 0.05, rgb)


# ── Toilet ride-on ───────────────────────────────────────────────────────────
def toilet():
    # the bowl: an open oval basin round the rider
    bowl = sphere(1.0, (0, -0.15, -1.15), WHITE, scale=(1.25, 1.55, 0.85), seg=20, rings=12)
    cut(bowl, lambda c: c.z < -0.84)
    solidify(bowl, 0.1)
    torus(1.0, 0.13, (0, -0.15, -0.84), WHITE, scale=(1.22, 1.5, 1), major=22, minor=6)
    # the seat on the rim, the lid standing up behind it
    torus(1.0, 0.13, (0, -0.15, -0.68), SEAT, scale=(1.27, 1.56, 0.45), major=22, minor=6)
    cyl(1.0, 0.1, (0, 1.32, 0.15), SEAT, rot=(-78, 0, 0), verts=20, scale=(1.2, 1.4, 1))
    # the tank, its lid and the flush lever
    cube((2.3, 0.85, 1.45), (0, 1.95, -0.4), WHITE, bevel=0.14)
    cube((2.45, 1.0, 0.16), (0, 1.95, 0.4), WHITE, bevel=0.05)
    cube((0.45, 0.08, 0.1), (-0.72, 1.48, 0.05), CHROME)
    sphere(0.09, (-0.95, 1.5, 0.05), CHROME, seg=8, rings=6)
    # the foot and the base the wheels hang on
    cyl(0.8, 0.8, (0, -0.1, -2.0), WHITE, verts=18, r2=0.66, scale=(1, 1.3, 1))
    cyl(1.0, 0.14, (0, 0.2, -2.38), WHITE, verts=20, scale=(1.05, 1.9, 1))
    for y in (-1.25, 1.6):
        bar((-1.25, y, GROUND + 0.4), (1.25, y, GROUND + 0.4), 0.06, CHROME)
        wheel(1.35, y, 0.4, 0.3)
        wheel(-1.35, y, 0.4, 0.3)
    # toilet-paper headlights on the front of the bowl
    for x in (-0.65, 0.65):
        cyl(0.27, 0.42, (x, -1.82, -1.35), PAPER, rot=(0, 90, 0), verts=14)
        cyl(0.1, 0.44, (x, -1.82, -1.35), CARDBOARD, rot=(0, 90, 0), verts=8)
        bar((x, -1.55, -1.25), (x, -1.75, -1.35), 0.05, CHROME)
    steering((0, -1.3, -0.45), CHROME, column_from=(0, -1.62, -0.85))


# ── Shopping cart ride-on ────────────────────────────────────────────────────
def cart():
    W_TOP, W_BOT = 1.3, 1.08
    FRONT_TOP, FRONT_BOT, BACK = -2.05, -1.6, 1.5
    Z_TOP, Z_BOT = -0.3, -1.6

    def lerp(a, b, t):
        return a + (b - a) * t

    def side_point(sx, t, h):
        """On a side wall: t 0 front → 1 back, h 0 bottom → 1 top."""
        y_bot = lerp(FRONT_BOT, BACK, t)
        y_top = lerp(FRONT_TOP, BACK, t)
        return (sx * lerp(W_BOT, W_TOP, h), lerp(y_bot, y_top, h), lerp(Z_BOT, Z_TOP, h))

    # the rims
    for z, w, yf, r in ((Z_TOP, W_TOP, FRONT_TOP, 0.06), (Z_BOT, W_BOT, FRONT_BOT, 0.045)):
        corners = [(-w, yf, z), (w, yf, z), (w, BACK, z), (-w, BACK, z)]
        for i in range(4):
            bar(corners[i], corners[(i + 1) % 4], r, METAL)
    # the side walls: uprights and three rails
    for sx in (-1, 1):
        for i in range(1, 9):
            t = i / 9
            bar(side_point(sx, t, 0), side_point(sx, t, 1), 0.03, METAL)
        for h in (0.33, 0.66):
            bar(side_point(sx, 0, h), side_point(sx, 1, h), 0.03, METAL)
    # the front wall (leaning out) and the back gate
    for i in range(1, 8):
        u = -1 + 2 * i / 8
        bar((u * W_BOT, FRONT_BOT, Z_BOT), (u * W_TOP, FRONT_TOP, Z_TOP), 0.03, METAL)
        bar((u * W_BOT, BACK, Z_BOT), (u * W_TOP, BACK, Z_TOP), 0.03, METAL)
    for h in (0.33, 0.66):
        bar(side_point(-1, 0, h), side_point(1, 0, h), 0.03, METAL)
        bar(side_point(-1, 1, h), side_point(1, 1, h), 0.03, METAL)
    # the floor wires
    for i in range(1, 5):
        u = -1 + 2 * i / 5
        bar((u * W_BOT, FRONT_BOT, Z_BOT), (u * W_BOT, BACK, Z_BOT), 0.03, METAL)
    # the handle: tubes up and back from the gate, the red grip across
    for sx in (-1, 1):
        bar((sx * W_TOP, BACK, Z_TOP), (sx * 1.25, BACK + 0.55, Z_TOP + 0.45), 0.06, METAL)
    cyl(0.1, 2.7, (0, BACK + 0.55, Z_TOP + 0.45), RED, rot=(0, 90, 0), verts=12)
    # the red child-seat flap folded against the gate, red corner caps, a red plate in front
    cube((2.1, 0.07, 0.75), (0, BACK - 0.08, -0.85), RED, rot=(8, 0, 0))
    for sx in (-1, 1):
        cube((0.22, 0.22, 0.2), (sx * W_TOP, FRONT_TOP, Z_TOP), RED, bevel=0.05)
    cube((1.0, 0.06, 0.32), (0, FRONT_TOP + 0.04 * 0, -0.75), RED)
    # the chassis: legs down to two rails, the bottom tray, castors
    for sx in (-1, 1):
        bar((sx * W_BOT, FRONT_BOT, Z_BOT), (sx * 0.8, FRONT_BOT + 0.1, -2.1), 0.05, METAL)
        bar((sx * W_BOT, BACK, Z_BOT), (sx * 0.8, BACK + 0.1, -2.1), 0.05, METAL)
        bar((sx * 0.8, FRONT_BOT + 0.1, -2.1), (sx * 0.8, BACK + 0.1, -2.1), 0.06, METAL)
    for i in range(3):
        u = -0.5 + i * 0.5
        bar((u, FRONT_BOT + 0.1, -2.1), (u, BACK + 0.1, -2.1), 0.03, METAL)
    for sx in (-1, 1):
        for y in (FRONT_BOT + 0.15, BACK + 0.05):
            cube((0.08, 0.18, 0.25), (sx * 0.8, y, -2.2), DARK)
            wheel(sx * 0.8, y, 0.24, 0.16, z=GROUND + 0.24)


# ── Golden racer ride-on (Speed Legend) ──────────────────────────────────────
def racer():
    cube((1.7, 4.2, 0.7), (0, -0.1, -1.75), GOLD, bevel=0.25)
    cyl(0.62, 1.5, (0, -2.85, -1.85), GOLD, rot=(90, 0, 0), verts=16, r2=0.16)
    for sx in (-1, 1):
        cube((0.6, 2.0, 0.65), (sx * 1.1, 0.4, -1.8), GOLD, bevel=0.2)
    # the cockpit rim round the rider and a headrest behind
    torus(1.0, 0.1, (0, 0.0, -1.38), DARK, scale=(0.95, 1.25, 1), major=20, minor=6)
    cube((1.2, 0.35, 0.8), (0, 1.55, -1.1), GOLD, bevel=0.12)
    # wings
    cube((3.1, 0.55, 0.1), (0, -3.25, -2.2), RED, bevel=0.03)
    for sx in (-1, 1):
        cube((0.08, 0.6, 0.4), (sx * 1.55, -3.25, -2.05), RED)
    cube((2.6, 0.6, 0.12), (0, 2.35, -0.55), RED, bevel=0.03)
    for sx in (-1, 1):
        cube((0.1, 0.5, 0.9), (sx * 0.6, 2.25, -1.05), DARK)
        cube((0.08, 0.7, 0.6), (sx * 1.3, 2.35, -0.65), RED)
    # number roundel on the nose: a white disc with a black 1
    cyl(0.32, 0.04, (0, -2.0, -1.38), WHITE, verts=16)
    cube((0.08, 0.32, 0.03), (0, -2.0, -1.35), DARK)
    for x, y, r, w in ((1.55, -1.95, 0.45, 0.5), (-1.55, -1.95, 0.45, 0.5), (1.6, 1.55, 0.56, 0.6), (-1.6, 1.55, 0.56, 0.6)):
        wheel(x, y, r, w, hub=GOLD)
    for sx in (-1, 1):
        bar((sx * 0.8, -1.95, GROUND + 0.45), (sx * 1.35, -1.95, GROUND + 0.45), 0.06, DARK)
        bar((sx * 0.8, 1.55, GROUND + 0.56), (sx * 1.35, 1.55, GROUND + 0.56), 0.07, DARK)
    steering((0, -0.95, -0.95), DARK, column_from=(0, -1.6, -1.35))


# ── Champion belt (Brawler) ──────────────────────────────────────────────────
def belt():
    torus(1.0, 0.12, (0, 0, 0), DARK, scale=(1.08, 0.66, 1.9), major=28, minor=6)
    # the big gold plate in front with a red jewel, two side plates
    cyl(0.55, 0.08, (0, -0.72, 0.02), GOLD, rot=(90, 0, 0), verts=24, scale=(1.35, 1, 1))
    torus(0.55, 0.05, (0, -0.77, 0.02), GOLD, rot=(90, 0, 0), scale=(1.35, 1, 1), major=24, minor=6)
    cyl(0.32, 0.06, (0, -0.79, 0.02), (255, 230, 120), rot=(90, 0, 0), verts=20)
    sphere(0.14, (0, -0.83, 0.02), (220, 30, 50), seg=10, rings=6)
    for sx in (-1, 1):
        cyl(0.26, 0.06, (sx * 0.8, -0.5, 0.0), GOLD, rot=(90, 0, sx * 35), verts=16)
        sphere(0.06, (sx * 0.83, -0.55, 0.0), (40, 120, 230), seg=8, rings=5)


# ── Junk racer's pot helmet (Road Warrior) ─────────────────────────────────
POT = (175, 182, 192)
LEATHER = (120, 75, 40)


def helmet_pot():
    # a cooking pot upside down on the head: the wall, the rounded bottom
    # (now the top), the rim, two black handles and the lid knob
    cyl(0.74, 0.62, (0, 0, -0.18), POT, verts=24)
    top = sphere(0.74, (0, 0, 0.1), POT, scale=(1, 1, 0.3), seg=24, rings=10)
    cut(top, lambda c: c.z > 0.1)
    torus(0.76, 0.05, (0, 0, -0.5), POT, major=24, minor=6)
    for sx in (-1, 1):
        cube((0.36, 0.14, 0.12), (sx * 0.9, 0, -0.08), DARK, bevel=0.04)
    cyl(0.12, 0.12, (0, 0, 0.36), DARK, verts=12)
    # aviator goggles pushed up on the front of the pot, strap round it
    torus(0.77, 0.045, (0, 0, -0.36), LEATHER, major=28, minor=5)
    for sx in (-1, 1):
        cyl(0.2, 0.12, (sx * 0.24, -0.78, -0.3), (210, 170, 60), rot=(90, 0, 0), verts=16)
        cyl(0.15, 0.13, (sx * 0.24, -0.79, -0.3), (120, 200, 230), rot=(90, 0, 0), verts=16)
    cube((0.12, 0.06, 0.08), (0, -0.8, -0.3), (210, 170, 60))


BUILDERS = {"ride_toilet": toilet, "ride_cart": cart, "ride_racer": racer, "belt_champion": belt,
            "helmet_pot": helmet_pot}

# kind: "hat" (previewed on a head) or "ride" (on a standing avatar);
# type: the Accessory Fitting Tool's accessory type.
ITEMS = [
    {"id": "ride_cart", "name": "Shopping Cart Ride-On", "achievement": "races10", "kind": "ride", "type": "Waist"},
    {"id": "helmet_pot", "name": "Junk Racer Helmet", "achievement": "races50", "kind": "hat", "type": "Hat"},
    {"id": "ride_racer", "name": "Golden Racer Ride-On", "achievement": "wins10", "kind": "ride", "type": "Waist"},
    {"id": "ride_toilet", "name": "Toilet Ride-On", "achievement": "flush", "kind": "ride", "type": "Waist"},
    {"id": "belt_champion", "name": "Champion Belt", "achievement": "brawler", "kind": "ride", "type": "Waist"},
]
