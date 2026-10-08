"""The icons of the three abilities added in the rework (ABILITIES_REWORK_PLAN): Catch-a-Ball,
Look Over There! and Verity. Same rig as icons.py (its camera, lights, rarity rim light, ink
outline, framing and 512 x 512 transparent render): this file only adds builders to it.

    Blender -b --python tools/blender/abilities/icons_v2.py -- [Id ...]   (no ids: all three)

Renders go to assets/abilities/icons/<Id>.png.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else os.path.join(
    os.environ.get("EIGHTBALL_ROOT", ""), "tools", "blender", "abilities")
sys.path.insert(0, HERE)
import catchball  # noqa: E402
import icons  # noqa: E402
from icons import (CAM_AZIMUTH, CAM_DIR, extrude_outline, face_camera, glow, mat, prim,  # noqa: E402
                   slab, surface_y, transform, tube_path)


def sparkle(name, at, size, material):
    """A flat four-point star facing the camera (long thin points), not counted in the frame."""
    pts = []
    for i in range(16):
        a = 2 * math.pi * i / 16
        if i % 4 == 0:
            r = size
        elif i % 2 == 0:
            r = size * 0.16
        else:
            r = size * 0.22
        pts.append((math.cos(a) * r, math.sin(a) * r))
    obj = extrude_outline(name, pts, 0.03, material)
    face_camera(obj)
    obj.location = at
    obj["outline_scale"] = 0.5
    return obj


def catch_a_ball():
    """The catch ball, closed, turned a little toward the camera and tilted, a sparkle at its
    top right (the model of catchball.py, so the icon matches the game)."""
    parts, hinge = catchball.build_model()
    bpy.data.objects.remove(hinge, do_unlink=True)
    m = bpy.data.materials["CatchMat"]
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Coat Weight"].default_value = 0.8
    bsdf.inputs["Coat Roughness"].default_value = 0.06
    bsdf.inputs["Roughness"].default_value = 0.25
    for o in parts:
        if o.name == "CatchInner":
            o["no_outline"] = True
            o["no_frame"] = True
        if o.name == "CatchButton":
            o["outline_scale"] = 0.45
    # Bake each part's origin offset away: the rig moves objects, and these sit at the hinge.
    transform(parts, Matrix.Rotation(math.radians(-14), 4, CAM_DIR)
              @ Matrix.Rotation(math.radians(CAM_AZIMUTH - 8), 4, "Z")
              @ Matrix.Rotation(math.radians(-12), 4, "X"))
    star_m = mat("CatchSparkle", "FFFFFF", emit=4.0, emit_color="FFF6C8")
    objs = list(parts)
    objs.append(sparkle("Sparkle", Vector((0.78, -0.4, 0.78)), 0.42, star_m))
    objs.append(sparkle("Sparkle2", Vector((1.02, -0.3, 0.32)), 0.18, star_m))
    for s in objs[-2:]:
        s["no_frame"] = True
    objs.append(glow("CatchGlow", (0, 0.3, 0), 1.3, "FF6A6A", strength=0.8, power=1.6))
    return objs


def look_over_there():
    """A white cartoon glove pointing hard up and to the right, a big glossy yellow "!" on a
    red comic burst where it points, motion ticks round the fingertip."""
    glove = mat("Glove", "FFFFFF", rough=0.35, coat=0.4)
    sleeve = mat("Sleeve", "7A4DFF", rough=0.35, coat=0.5)
    yellow = mat("Bang", "FFD21E", rough=0.2, coat=0.9, emit=0.25)
    burst_m = mat("Burst", "FF3B30", rough=0.35, coat=0.4, emit=0.6, emit_color="FF2A1A")
    tick_m = mat("Tick", "1B2033", rough=0.4)
    objs = []
    # The hand, built pointing +X in the XZ plane (front -Y), then turned up.
    hand = []
    palm = prim("uv_sphere", "Palm", glove, segments=40, ring_count=20, radius=1.0,
                scale=(0.3, 0.2, 0.27))
    hand.append(palm)
    hand.append(tube_path("Index", [(0.12, -0.02, 0.12), (0.45, -0.02, 0.14), (0.76, -0.02, 0.15)],
                          0.085, glove, sides=16))
    for k, z in enumerate((0.02, -0.1, -0.21)):
        r = 0.075 - 0.006 * k
        hand.append(tube_path("Curl", [(0.12, -0.04, z), (0.3, -0.07, z - 0.01),
                                       (0.33, -0.17, z - 0.05), (0.22, -0.22, z - 0.06)],
                              r, glove, sides=14))
    hand.append(tube_path("Thumb", [(-0.05, -0.16, 0.0), (0.1, -0.26, 0.02), (0.24, -0.27, 0.06)],
                          0.08, glove, sides=14))
    cuff = prim("cylinder", "Cuff", glove, location=(-0.32, 0, -0.02), rotation=(0, math.pi / 2, 0),
                radius=0.25, depth=0.14, vertices=40)
    bev = cuff.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.04
    bev.segments = 3
    hand.append(cuff)
    hand.append(prim("cylinder", "Sleeve", sleeve, location=(-0.6, 0, -0.02),
                     rotation=(0, math.pi / 2, 0), radius=0.2, depth=0.44, vertices=40))
    transform(hand, Matrix.Translation((-0.4, 0, -0.45)) @ Matrix.Rotation(math.radians(-32), 4, "Y")
              @ Matrix.Scale(1.25, 4))
    objs += hand
    # The burst: a jagged comic star, flat, standing in XZ facing -Y, behind the "!".
    pts = []
    n = 22
    for i in range(n):
        a = 2 * math.pi * i / n + 0.1
        r = (0.62 if i % 2 == 0 else 0.42) * (1 + 0.08 * math.sin(i * 2.7))
        pts.append((math.cos(a) * r, math.sin(a) * r))
    burst = slab("Burst", pts, 0.08, burst_m, bevel=0.015, at=(0.5, 0.18, 0.45))
    objs.append(burst)
    # The "!": a bar narrowing to the bottom and a round dot, chunky.
    bar = [(-0.13, 0.5), (0.13, 0.5), (0.07, -0.08), (-0.07, -0.08)]
    objs.append(slab("Bar", bar, 0.14, yellow, bevel=0.04, at=(0.5, 0.0, 0.42)))
    objs.append(prim("uv_sphere", "Dot", yellow, location=(0.5, 0.0, 0.14), radius=1.0,
                     segments=32, ring_count=16, scale=(0.1, 0.09, 0.1)))
    # Motion ticks by the fingertip (it just snapped to point).
    tip = Vector((0.0, -0.05, 0.05))
    for deg in (200, 235, 270):
        a = math.radians(deg)
        d = Vector((math.cos(a), 0, math.sin(a)))
        t = tube_path("Tick", [tip + d * 0.12, tip + d * 0.26], 0.025, tick_m)
        t["no_outline"] = True
        objs.append(t)
    transform(objs, Matrix.Rotation(math.radians(CAM_AZIMUTH), 4, "Z"))
    objs.append(glow("BangGlow", (0.3, 0.3, 0.3), 1.2, "FFC83A", strength=0.9, power=1.5))
    return objs


def verity():
    """The yellow smiley ball (two tall black oval eyes, a wide black smile) with a creepy
    long-fingered yellow hand curling over its top right from behind: thin bony fingers with
    knobbly knuckles and dark pointed nails."""
    ball_m = mat("VerityBall", "FFD21E", rough=0.25, coat=0.8)
    hand_m = mat("VerityHand", "E0A815", rough=0.45, coat=0.3)
    ink = mat("VerityInk", "0E0E12", rough=0.25, coat=0.6)
    nail_m = mat("VerityNail", "2A1E14", rough=0.3, coat=0.7)
    R = 0.62
    objs = []
    ball = prim("uv_sphere", "Ball", ball_m, segments=64, ring_count=32, radius=R)
    objs.append(ball)
    for side in (-1, 1):
        ex, ez = 0.15 * side, 0.14
        ey = surface_y(ex, ez, R, R, R)
        eye = prim("uv_sphere", "Eye", ink, location=(ex, ey + 0.015, ez), radius=1.0,
                   segments=24, ring_count=12, scale=(0.058, 0.03, 0.11))
        eye["no_outline"] = True
        objs.append(eye)
    smile = []
    for i in range(25):
        x = -0.36 + 0.72 * i / 24
        z = -0.06 - 0.2 * max(1 - (x / 0.36) ** 2, 0.0) ** 0.8
        smile.append((x, surface_y(x, z, R, R, R) + 0.012, z))
    s = tube_path("Smile", smile, 0.022, ink, sides=10)
    s["no_outline"] = True
    objs.append(s)
    for side in (-1, 1):  # the little curled ends of the smile
        x0, z0 = 0.36 * side, -0.06
        p0 = (x0, surface_y(x0, z0, R, R, R) + 0.012, z0)
        x1, z1 = 0.4 * side, -0.0
        p1 = (x1, surface_y(x1, z1, R, R, R) + 0.012, z1)
        e = tube_path("SmileEnd", [p0, p1], 0.02, ink, sides=8)
        e["no_outline"] = True
        objs.append(e)
    # The hand: four long bony fingers reaching from behind (+Y) over the top of the ball and
    # down its front above the eyes, dark claws at the tips; the palm hidden behind.
    Y = Vector((0, 1, 0))
    fingers = ((48, 0.95), (74, 1.08), (104, 1.1), (130, 0.95))  # (phi, length)
    for k, (phi, length) in enumerate(fingers):
        u = Vector((math.cos(math.radians(phi)), 0, math.sin(math.radians(phi))))
        pts, radii = [], []
        steps = 32
        a0, a1 = 75.0, 75.0 - 125.0 * length
        for i in range(steps + 1):
            t = i / steps
            a = math.radians(a0 + (a1 - a0) * t)
            knuckle = math.exp(-((t - 0.5) / 0.06) ** 2) + math.exp(-((t - 0.76) / 0.05) ** 2)
            rr = R + 0.03 + 0.012 * knuckle - 0.012 * max(t - 0.85, 0) / 0.15  # the tip digs in
            pts.append(tuple(u * (math.cos(a) * rr) + Y * (math.sin(a) * rr)))
            radii.append((1.0 - 0.35 * t) + 0.3 * knuckle)
        f = tube_path("Finger", pts, 0.027, hand_m, sides=12, radii=radii)
        f["outline_scale"] = 0.5
        objs.append(f)
        p_end, p_prev = Vector(pts[-1]), Vector(pts[-3])
        d = (p_end - p_prev).normalized()
        nail = prim("cone", "Nail", nail_m, radius1=0.019, radius2=0.0, depth=0.11, vertices=12)
        icons.point_along(nail, d)
        nail.location = p_end + d * 0.05
        nail["outline_scale"] = 0.35
        objs.append(nail)
    palm = prim("uv_sphere", "Palm", hand_m, location=(0.0, 0.42, 0.42), radius=1.0,
                segments=32, ring_count=16, scale=(0.3, 0.16, 0.22))
    objs.append(palm)
    transform(objs, Matrix.Rotation(math.radians(CAM_AZIMUTH * 0.8), 4, "Z")
              @ Matrix.Rotation(math.radians(-6), 4, "X"))
    objs.append(glow("VerityGlow", (0, 0.3, 0), 1.3, "FFE45C", strength=0.7, power=1.6))
    return objs


NEW = {
    "CatchABall": (catch_a_ball, "Rare"),
    "LookOverThere": (look_over_there, "Epic"),
    "Verity": (verity, "Legendary"),
}
for _id, (_fn, _rarity) in NEW.items():
    icons.BUILDERS[_id] = _fn
    icons.RARITY_OF[_id] = _rarity


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for ult_id in argv or list(NEW):
        print("icon:", icons.build(ult_id))


if __name__ == "__main__":
    main()
