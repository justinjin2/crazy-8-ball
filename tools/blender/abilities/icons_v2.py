"""The icons of the abilities added in the rework (ABILITIES_REWORK_PLAN): Catch-a-Ball, Look
Over There!, Verity, and Fire Shot (the designer's third round, 2026-10-08: Super Bounce
reworked). Same rig as icons.py (its camera, lights, rarity rim light, ink outline, framing and
512 x 512 transparent render): this file only adds builders to it.

    Blender -b --python tools/blender/abilities/icons_v2.py -- [Id ...]   (no ids: all four)

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
    # The ink outline from a plain sphere just inside the shell, not from the shell's parts:
    # their rims would draw lines across the ball at the seam (the designer, 2026-10-09: no
    # lines that read as a capture ball).
    for o in parts:
        if o.name in ("CatchTop", "CatchBand", "CatchBottom"):
            o["no_outline"] = True
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.99, segments=64, ring_count=32, location=(0, 0, 0))
    core = bpy.context.active_object
    core.name = "CatchOutline"
    core.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    parts.append(core)
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


def catmull(points, closed=True, sharp=(), steps=8):
    """A smooth closed outline through 2-D control points (Catmull-Rom); the points whose
    indices are in `sharp` stay corners (a flame's tips)."""
    n = len(points)
    out = []
    for i in range(n):
        p0, p1 = points[(i - 1) % n], points[i]
        p2, p3 = points[(i + 1) % n], points[(i + 2) % n]
        if i in sharp:
            p0 = p1
        if (i + 1) % n in sharp:
            p3 = p2
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t
                                    + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3)
                             for j in range(2)))
    return out


def tongue(cx, cy, h, w, lean, toward=(0.0, 1.0)):
    """One small flame tongue: a round base of half-width `w` at (cx, cy), its tip `h` along
    `toward` (a direction; up by default), leaning `lean` of its height to its left."""
    ux, uy = toward
    n = math.hypot(ux, uy)
    ux, uy = ux / n, uy / n
    sx, sy = uy, -ux  # its right

    def at(across, along):
        return (cx + sx * across + ux * along, cy + sy * across + uy * along)
    pts = [at(-w, 0), at(-w * 0.92, h * 0.3), at(-w * 0.4 - lean * h * 0.5, h * 0.66),
           at(-lean * h, h), at(w * 0.38 - lean * h * 0.42, h * 0.55), at(w * 0.95, h * 0.2),
           at(w, 0), at(w * 0.7, -w * 0.72), at(0, -w), at(-w * 0.7, -w * 0.72)]
    return catmull(pts, sharp=(3,))


# The fireball's flame round a ball of radius 1 at the origin flying along +X (up +Y): drawn
# by hand as control points, counter-clockwise from under the ball (hidden behind it), five
# S-curved tongues streaming back and curling up; FIRE_TIPS are the tongues' sharp tips.
FIRE = [(0.62, -0.72), (0.18, -1.12), (-0.5, -1.22), (-1.2, -1.16), (-1.95, -1.3),
        (-2.75, -1.12), (-2.05, -0.76), (-2.65, -0.56), (-3.55, -0.12), (-2.55, 0.05),
        (-3.05, 0.48), (-3.75, 1.2), (-2.6, 0.78), (-2.25, 1.22), (-2.55, 2.05), (-1.5, 1.32),
        (-0.92, 1.38), (-0.62, 1.98), (-0.22, 1.16), (0.46, 0.86)]
FIRE_TIPS = (5, 8, 11, 14, 17)
# The layers, outside in: colour, emission, scale toward the ball's back, a nudge up and back.
FIRE_LAYERS = [
    ("FF3D1A", 0.8, 1.0, (0.0, 0.0)),
    ("FF7A1A", 0.95, 0.78, (-0.06, 0.06)),
    ("FFB52A", 1.05, 0.57, (-0.1, 0.12)),
    ("FFEB8A", 1.25, 0.38, (-0.12, 0.16)),
]
FIRE_HEART = (-0.35, 0.08)  # where the layers shrink toward: the hottest place, at the ball's back


def fire_shot():
    """The cue ball on fire, flying: a glossy white ball shooting down and to the right, a
    comet of layered cartoon flame (red-orange, orange, amber, a pale yellow core) streaming
    back from it and rising, embers flying off the tongues."""
    objs = []
    fly = Matrix.Rotation(math.radians(-32), 2)  # the flight, down and to the right

    def flat(name, pts2d, depth, thick, m, bevel):
        obj = extrude_outline(name, [tuple(fly @ Vector(p)) for p in pts2d], thick, m, bevel=bevel)
        face_camera(obj)
        obj.location = CAM_DIR * depth
        return obj

    outline_pts = catmull(FIRE, sharp=FIRE_TIPS)
    hx, hy = FIRE_HEART
    for k, (color, emit, scale, (nx, ny)) in enumerate(FIRE_LAYERS):
        m = mat("Fire%d" % k, color, rough=0.35, coat=0.3, emit=emit, emit_color=color)
        pts = [(hx + (x - hx) * scale + nx, hy + (y - hy) * scale + ny) for x, y in outline_pts]
        obj = flat("Fire%d" % k, pts, -0.8 + 0.12 * k, 0.05, m, 0.02)
        if k > 0:
            obj["ink"] = "B8260A"
            obj["outline_scale"] = 0.3
        objs.append(obj)
    # The ball: glossy white, warmed orange on the side the fire is.
    ball_m = bpy.data.materials.new("FireBall")
    ball_m.use_nodes = True
    nodes, links = ball_m.node_tree.nodes, ball_m.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.12
    bsdf.inputs["Coat Weight"].default_value = 1.0
    bsdf.inputs["Coat Roughness"].default_value = 0.04
    bsdf.inputs["Emission Color"].default_value = icons.hexcolor("FFFFFF")
    bsdf.inputs["Emission Strength"].default_value = 0.42
    coord = nodes.new("ShaderNodeTexCoord")
    dot = nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    ahead = fly @ Vector((1.0, 0.0))
    dot.inputs[1].default_value = (icons.SCREEN_RIGHT * ahead.x + icons.SCREEN_UP * ahead.y)
    mr = nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -1.0
    mr.inputs["From Max"].default_value = 1.0
    ramp = nodes.new("ShaderNodeValToRGB")
    icons.ramp_fill(ramp, [(0.0, "FFA54D"), (0.4, "FFE2BF"), (0.62, "FFFFFF"), (1.0, "FFFFFF")])
    links.new(coord.outputs["Object"], dot.inputs[0])
    links.new(dot.outputs["Value"], mr.inputs["Value"])
    links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    objs.append(prim("uv_sphere", "Ball", ball_m, segments=64, ring_count=32, radius=1.0))
    # Embers flying off the tongues.
    ember_m = mat("Ember", "FFD84A", rough=0.3, emit=1.6, emit_color="FFC02A")
    for j, (x, y, size) in enumerate(((-3.55, 0.95, 0.15), (-2.9, 2.05, 0.11), (-3.75, -0.6, 0.1),
                                      (-1.6, 2.05, 0.09))):
        pts = [(0, size), (size * 0.55, 0), (0, -size), (-size * 0.55, 0)]
        obj = flat("Ember%d" % j, [(px + x, py + y) for px, py in pts], 0.3, 0.03, ember_m, 0.01)
        obj["outline_scale"] = 0.5
        obj["no_frame"] = True
        objs.append(obj)
    # The fire's light on the ball's back, and its glow.
    light = bpy.data.lights.new("FireLight", "POINT")
    light.energy = 220
    light.color = (1.0, 0.5, 0.15)
    lo = bpy.data.objects.new("FireLight", light)
    bpy.context.scene.collection.objects.link(lo)
    back = fly @ Vector((-1.6, 0.2))
    lo.location = icons.screen(back.x, back.y, 0.4)
    glow_at = fly @ Vector((-1.3, 0.1))
    objs.append(glow("FireGlow", tuple(icons.screen(glow_at.x, glow_at.y, -1.4)), 2.6, "FF6A12",
                     strength=1.2, power=1.4))
    return objs


NEW = {
    "CatchABall": (catch_a_ball, "Rare"),
    "LookOverThere": (look_over_there, "Epic"),
    "Verity": (verity, "Legendary"),
    "FireShot": (fire_shot, "Common"),
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
