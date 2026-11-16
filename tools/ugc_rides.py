"""Ride-on toy cars as waist accessories (docs/ugc.md): the avatar stands in
the cockpit and walks it around like a kid's ride-on car. Plain data, read
by tools/ugc_models.py (Blender) and the preview.

Parts use HatDesigns' fields (shape block / ball / cyl with the cylinder's
axis on Y, size, pos, rot in degrees, color, finish), in studs, Roblox axes
(X the wearer's right, Y up, -Z the front). Origin: the waist (an R15
avatar's WaistCenterAttachment, ~2.6 studs over the ground).
"""

import math

GROUND = -2.6          # the floor under an R15 avatar, from the waist
WHEEL_R = 0.55


def block(size, pos, color, rot=(0, 0, 0), finish="plastic"):
    return {"shape": "block", "size": list(size), "pos": list(pos), "rot": list(rot), "color": list(color),
            "finish": finish}


def ball(d, pos, color, finish="plastic", size=None):
    return {"shape": "ball", "size": list(size or (d, d, d)), "pos": list(pos), "rot": [0, 0, 0],
            "color": list(color), "finish": finish}


def cyl(d, h, pos, color, rot=(0, 0, 0), finish="plastic"):
    return {"shape": "cyl", "size": [d, h, d], "pos": list(pos), "rot": list(rot), "color": list(color),
            "finish": finish}


def wheels(x, zs, tyre=(30, 30, 35), hub=(240, 240, 240)):
    """Four chunky toy wheels, axles along X."""
    out = []
    y = GROUND + WHEEL_R
    for z in zs:
        for sx in (-1, 1):
            out.append(cyl(WHEEL_R * 2, 0.42, (sx * x, y, z), tyre, rot=(0, 0, 90)))
            out.append(cyl(WHEEL_R * 1.0, 0.46, (sx * x, y, z), hub, rot=(0, 0, 90)))
    return out


def tub(colour, half_w=1.3, front=-1.0, back=1.0, y0=-2.0, y1=-0.75, wall=0.32):
    """The body round the cockpit: two sides, a dashboard and a back wall,
    open in the middle where the avatar stands."""
    h = y1 - y0
    yc = (y0 + y1) / 2
    length = back - front + 2 * wall
    return [
        block((wall, h, length), (-half_w, yc, (front + back) / 2), colour),
        block((wall, h, length), (half_w, yc, (front + back) / 2), colour),
        block((2 * half_w, h, wall), (0, yc, front - wall / 2), colour),
        block((2 * half_w, h, wall), (0, yc, back + wall / 2), colour),
    ]


def steering(z, colour=(40, 40, 45)):
    return [
        cyl(0.12, 0.7, (0, -0.65, z + 0.12), colour, rot=(-35, 0, 0)),
        cyl(0.62, 0.1, (0, -0.35, z + 0.28), colour, rot=(-35, 0, 0)),
    ]


RED = (220, 40, 45)
YELLOW = (255, 205, 40)
WHITE = (245, 245, 245)
METAL = (175, 180, 190)

CART = (
    tub(RED)
    + [
        # hood and nose
        block((2.6, 0.8, 1.3), (0, -1.55, -1.95), RED),
        block((2.2, 0.32, 1.0), (0, -1.0, -1.85), RED),
        block((2.9, 0.35, 0.3), (0, -1.95, -2.7), YELLOW),
        ball(0.36, (-0.8, -1.35, -2.62), YELLOW, finish="glow"),
        ball(0.36, (0.8, -1.35, -2.62), YELLOW, finish="glow"),
        # the basket behind: wire bars
        block((2.4, 0.08, 1.6), (0, -1.0, 2.15), METAL, finish="metal"),
    ]
    + [block((0.07, 0.9, 1.6), (x, -0.55, 2.15), METAL, finish="metal") for x in (-1.2, -0.6, 0.0, 0.6, 1.2)]
    + [block((2.47, 0.9, 0.07), (0, -0.55, z), METAL, finish="metal") for z in (1.35, 2.15, 2.95)]
    + [block((2.47, 0.07, 1.67), (0, -0.1, 2.15), METAL, finish="metal"),
       block((2.6, 0.16, 0.16), (0, 0.15, 3.1), RED),
       block((0.14, 0.4, 0.14), (-1.2, -0.05, 3.05), METAL, finish="metal"),
       block((0.14, 0.4, 0.14), (1.2, -0.05, 3.05), METAL, finish="metal")]
    + steering(-1.0)
    + wheels(1.45, (-1.9, 2.2))
)

DUCK_YELLOW = (255, 214, 30)
BEAK = (255, 130, 20)
DUCK = (
    tub(DUCK_YELLOW, half_w=1.3, front=-0.9, back=0.9, y1=-0.8)
    + [
        ball(2.7, (0, -1.4, 0.0), DUCK_YELLOW, size=(2.9, 1.4, 4.4)),   # the round belly under the cockpit walls
        ball(1.5, (0, -0.25, -2.0), DUCK_YELLOW),                        # head on a neck at the front
        cyl(0.9, 0.9, (0, -0.95, -1.8), DUCK_YELLOW),
        block((0.9, 0.24, 0.7), (0, -0.4, -2.95), BEAK),
        ball(0.26, (-0.42, 0.0, -2.62), (20, 20, 25)),
        ball(0.26, (0.42, 0.0, -2.62), (20, 20, 25)),
        ball(0.09, (-0.38, 0.06, -2.73), WHITE),
        ball(0.09, (0.46, 0.06, -2.73), WHITE),
        block((1.0, 0.8, 0.3), (0, -0.8, 2.35), DUCK_YELLOW, rot=(-35, 0, 0)),   # tail up
        block((0.3, 0.6, 1.4), (-1.5, -1.2, 0.2), (250, 190, 20), rot=(0, 0, 15)),   # wings
        block((0.3, 0.6, 1.4), (1.5, -1.2, 0.2), (250, 190, 20), rot=(0, 0, -15)),
    ]
    + steering(-0.9, colour=BEAK)
    + wheels(1.35, (-1.5, 1.6), tyre=(40, 110, 220), hub=WHITE)
)

PORCELAIN = (248, 248, 250)
SEAT = (235, 235, 240)
CHROME = (200, 205, 215)
def ring(n, radius, y, tangential, height, radial, colour, zc=0.0):
    """`n` blocks round a circle (no gaps: tangential ≥ the arc between them)."""
    out = []
    for i in range(n):
        a = i * 2 * math.pi / n
        out.append(block((tangential, height, radial), (radius * math.sin(a), y, radius * math.cos(a) + zc),
                         colour, rot=(0, math.degrees(a), 0)))
    return out


# the bowl: a ring round the avatar, the seat on its rim
TOILET = (
    ring(18, 1.15, -1.25, 0.46, 0.95, 0.36, PORCELAIN, zc=-0.1)
    + ring(18, 1.2, -0.72, 0.48, 0.14, 0.42, SEAT, zc=-0.1)
    + [
        cyl(1.6, 0.6, (0, -1.95, -0.1), PORCELAIN),                       # the foot
        block((2.5, 1.5, 0.75), (0, -0.55, 1.75), PORCELAIN),              # the tank
        block((2.65, 0.16, 0.9), (0, 0.27, 1.75), PORCELAIN),              # tank lid
        block((0.5, 0.1, 0.12), (-0.95, -0.1, 1.33), CHROME, finish="metal"),   # flush handle
        block((2.3, 1.7, 0.12), (0, 0.4, 1.32), SEAT, rot=(-12, 0, 0)),    # the lid, up
        # toilet-paper headlights on the front bumper
        block((2.6, 0.3, 0.3), (0, -1.95, -1.55), CHROME, finish="metal"),
        cyl(0.55, 0.5, (-0.85, -1.55, -1.6), WHITE, rot=(0, 0, 90)),
        cyl(0.55, 0.5, (0.85, -1.55, -1.6), WHITE, rot=(0, 0, 90)),
        cyl(0.2, 0.52, (-0.85, -1.55, -1.6), (150, 120, 90), rot=(0, 0, 90)),
        cyl(0.2, 0.52, (0.85, -1.55, -1.6), (150, 120, 90), rot=(0, 0, 90)),
    ]
    + steering(-1.25, colour=CHROME)
    + wheels(1.45, (-1.25, 1.55), tyre=(30, 30, 35), hub=CHROME)
)

# The cart and the toilet are hand-modelled now (tools/ugc_custom.py).
RIDES = [
    {"id": "ride_duck", "name": "Rubber Duck Ride-On", "achievement": "funniest", "type": "Waist", "parts": DUCK},
]
