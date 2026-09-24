"""Snooker-style bridge (rake) for Crazy 8 Ball: a stepped "moose head" on a long maple shaft.

Run it headless from the repository root:

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
        --python assets/bridge/Bridge.py

or open Bridge.blend, pick Bridge.py in the Text Editor and press Run Script. Everything it
writes lands next to this file: Bridge.blend, BridgeModel.fbx, Parameters.json and
renders/preview.png.

Frame. One Blender unit is one Roblox stud (0.16 studs per inch). The pivot, the cue axis
resting in the High notch, is the Blender origin. The shaft runs along Blender +Y, Blender Z is
up, and Blender -X is the shooter's right. After Studio imports the FBX (its half turn) and
BridgeBuilder straightens the model, Blender (x, y, z) is Roblox local (-x, z, y): +X the
shooter's right, +Y up, +Z from the head down the shaft.

Headless-safe: meshes are built with bmesh and data calls only. The only operators are the FBX
export/import, the render and the save, none of which needs a window (bpy.context.screen is
None under -b, so it is never touched).
"""

import json
import math
import os
from math import cos, pi, radians, sin, sqrt

import bmesh
import bpy
from mathutils import Vector

# Every number the model uses. Lengths are studs unless a comment says otherwise. "x" and "y"
# in these comments are Roblox local (x = shooter's right, y = up, origin = the pivot).
PARAMETERS = {
    # ---- Frame ----------------------------------------------------------------------------
    'studs_per_inch': 0.16,  # project scale; the plate is 0.96 studs = 6 inches wide
    'pivot_height': 0.36,  # cloth to pivot (the cue axis in the High notch); the plate's base sits on the cloth
    # ---- Head plate (mesh "Head", SmoothPlastic, near-black) -----------------------------
    'head_half_width': 0.48,  # the plate spans x -0.48..0.48 (0.96 wide)
    'head_thickness': 0.07,  # plate thickness along the shaft, centred on z = 0 (z -0.035..0.035)
    'head_bevel': 0.008,  # chamfer on the front and back outline edges (bmesh bevel offset)
    'foot_corner_radius': 0.03,  # rounded outer corners of the two feet
    'foot_corner_steps': 2,  # segments per foot corner
    'arch_width': 0.36,  # arch cut into the base, centred on x = 0 (x -0.18..0.18)
    'arch_height': 0.10,  # arch rises from the base (y -0.36) to y -0.26
    'arch_steps': 8,  # segments along the arch (9 points; the top point is exact)
    'shoulder_corner_radius': 0.02,  # rounded top-right corner of the shoulder beside the Low notch
    'shoulder_corner_steps': 2,  # segments on that corner
    # ---- Notches (part of Head) ----------------------------------------------------------
    # (name, right, rest_height): right = x of the notch centre (the shooter's right is +),
    # rest_height = y of the cue axis resting in the notch, measured from the pivot (so 0.36 /
    # 0.26 / 0.16 above the cloth). Blender x = -right. Listed Low, Mid, High like Config.Bridge.Notches.
    'notches': [['Low', 0.365, -0.20], ['Mid', 0.19, -0.10], ['High', 0.0, 0.0]],
    'notch_radius': 0.055,  # U-shaped notch: half width and radius of its round bottom
    'notch_depth': 0.11,  # notch bottom to its own shoulder (the top of its outer, right-hand wall)
    'notch_rest_above_bottom': 0.045,  # cue radius: the rest point sits this far above the notch bottom
    'notch_flare': 0.02,  # rounded flare that widens each notch mouth
    'notch_flare_steps': 2,  # segments per flare
    'notch_arc_steps': 6,  # segments on each notch's round bottom (7 points; the bottom point is exact)
    # Each lobe between two notches stands as tall as the higher notch's shoulder, so every notch
    # has a 0.11 outer wall and a taller inner wall: the stepped moose head.
    'lobe_crown': 0.03,  # the left lobe's crown rises this far above the High shoulder (top y = 0.095)
    'left_lobe_side_top': 0.0,  # y where the straight left edge ends and the rounded lobe top begins
    'left_lobe_steps_to_crown': 3,  # segments from the High notch's flare up to the crown
    'left_lobe_steps_from_crown': 5,  # segments from the crown down to the left edge
    # ---- Collar and joint ring (mesh "Ferrule", Metal, brass) ----------------------------
    'shaft_axis_y': -0.16,  # the collar, shaft and cap share this axis (y from the pivot, x = 0)
    'collar_diameter': 0.14,  # brass collar that holds the plate
    'collar_z0': 0.035,  # collar starts on the plate's back face ...
    'collar_z1': 0.255,  # ... and ends here, around the shaft end
    'collar_chamfer': 0.015,  # 45-degree chamfer on both collar ends
    'ring_extra_diameter': 0.012,  # joint ring diameter = shaft diameter at the ring + this
    'ring_length': 0.05,  # joint ring length along the shaft
    'ring_position': 0.55,  # ring centre as a fraction of the shaft length from the head end
    'ring_chamfer': 0.004,  # small chamfer on both ring ends
    # ---- Shaft (mesh "Shaft", Wood, maple) ------------------------------------------------
    'shaft_z0': 0.10,  # shaft starts inside the collar (0.155 of overlap, so no gap shows)
    'shaft_length': 6.0,  # shaft runs z 0.10..6.10
    'shaft_head_diameter': 0.09,  # thin end, at the collar
    'shaft_butt_diameter': 0.13,  # thick end, inside the cap
    'shaft_rings': 4,  # rings along the taper; the extra two keep the long triangles from getting needle-thin
    # ---- Butt cap (mesh "Cap", Rubber) -----------------------------------------------------
    'cap_diameter': 0.14,  # rubber cap on the butt
    'cap_z0': 6.08,  # overlaps the shaft end by 0.02
    'cap_z1': 6.20,  # tip of the dome; the whole bridge runs z -0.035..6.20
    'cap_dome_height': 0.05,  # the last 0.05 is a quarter-ellipse dome
    'cap_dome_rings': 3,  # rings on the dome before its pole
    # ---- Mesh, validation and export --------------------------------------------------------
    'radial_segments': 16,  # sides on every round piece
    'sharp_angle_degrees': 40.0,  # edges whose faces meet at this angle or more are marked sharp (same rule as the table)
    'merge_distance': 1e-6,  # remove_doubles distance
    'min_face_area': 1e-8,  # square studs; anything smaller counts as a zero-area face
    'triangle_budget': 1500,  # the script fails if the four meshes add up to more
    'reimport_tolerance': 1e-5,  # FBX round trip: bounding boxes must match this closely
    'roblox_materials': {'Head': 'SmoothPlastic', 'Shaft': 'Wood', 'Ferrule': 'Metal', 'Cap': 'Rubber'},
    # sRGB 0..255, the same colours as Config.Bridge.Meshes; only used for the preview materials
    'colors': {'Head': [28, 28, 32], 'Shaft': [200, 158, 104], 'Ferrule': [190, 156, 84], 'Cap': [22, 22, 24]},
    # ---- Preview render ---------------------------------------------------------------------
    'render_preview': True,  # False skips renders/preview.png (quicker rebuild)
    'reimport_check': True,  # False skips the FBX round-trip check
    'preview_resolution': [960, 540],  # pixels; kept small so the PNG stays light in git
    'preview_samples': 32,  # Cycles samples (denoised)
}

MESH_NAMES = ('Head', 'Shaft', 'Ferrule', 'Cap')
FBX_NAME = 'BridgeModel.fbx'
BLEND_NAME = 'Bridge.blend'
TEXT_NAME = 'Bridge.py'


def output_dir():
    if bpy.data.filepath:
        return os.path.dirname(os.path.abspath(bpy.data.filepath))
    return os.path.dirname(os.path.abspath(__file__))


OUTPUT_DIR = output_dir()


# ---------------------------------------------------------------------------------------------
# 1-2. Setup and a clean scene (data calls only)
# ---------------------------------------------------------------------------------------------

def ensure_fbx_addon():
    if 'fbx' not in dir(bpy.ops.export_scene) or 'fbx' not in dir(bpy.ops.import_scene):
        import addon_utils
        addon_utils.enable('io_scene_fbx', default_set=True)
    assert 'fbx' in dir(bpy.ops.export_scene), 'the FBX exporter (io_scene_fbx) is not available'


def clear_scene(p):
    scene = bpy.context.scene
    for other in list(bpy.data.scenes):
        if other != scene:
            bpy.data.scenes.remove(other)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for pool in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights,
                 bpy.data.collections, bpy.data.worlds):
        for block in list(pool):
            pool.remove(block)
    scene.name = 'Bridge'
    scene.unit_settings.system = 'NONE'
    scene.unit_settings.scale_length = 1.0
    scene['PARAMETERS'] = json.dumps(p, sort_keys=True)
    scene['unit_convention'] = ('1 Blender unit = 1 Roblox stud; 0.16 stud/in; Blender Z up; the shaft runs '
                                'along Blender +Y; origin = pivot (cue axis in the High notch); Blender -X is '
                                "the shooter's right; Blender (x, y, z) = Roblox local (-x, z, y) once "
                                'BridgeBuilder straightens the import; FBX -Z forward, Y up')
    scene['generated_by'] = 'assets/bridge/Bridge.py'
    return scene


# ---------------------------------------------------------------------------------------------
# 3. Geometry (bmesh only)
# ---------------------------------------------------------------------------------------------

def arc(cx, cy, rx, ry, a0, a1, steps):
    """Points on an ellipse from angle a0 to a1 (degrees), both ends included."""
    out = []
    for k in range(steps + 1):
        a = radians(a0 + (a1 - a0) * k / steps)
        out.append((cx + rx * cos(a), cy + ry * sin(a)))
    return out


def notch_heights(p):
    """Rest, bottom, arc centre and shoulder y of each notch, keyed by name."""
    out = {}
    for name, right, rest in p['notches']:
        bottom = rest - p['notch_rest_above_bottom']
        out[name] = {'x': right, 'rest': rest, 'bottom': bottom,
                     'centre': bottom + p['notch_radius'], 'shoulder': bottom + p['notch_depth']}
    return out


def head_outline(p):
    """The plate outline as (x, y) Roblox-local points, counter-clockwise as the shooter sees it:
    left foot, arch, right foot, right edge, then the top from right to left (shoulder, Low
    notch, lobe, Mid notch, lobe, High notch, crowned left lobe) and down the left edge."""
    hw, base = p['head_half_width'], -p['pivot_height']
    r, fl = p['notch_radius'], p['notch_flare']
    rf, rs = p['foot_corner_radius'], p['shoulder_corner_radius']
    heights = notch_heights(p)
    order = sorted(p['notches'], key=lambda n: -n[1])  # right to left: Low, Mid, High
    pts = []
    pts += arc(-hw + rf, base + rf, rf, rf, 180, 270, p['foot_corner_steps'])
    pts += arc(0.0, base, p['arch_width'] / 2, p['arch_height'], 180, 0, p['arch_steps'])
    pts += arc(hw - rf, base + rf, rf, rf, 270, 360, p['foot_corner_steps'])
    low = heights[order[0][0]]
    pts += arc(hw - rs, low['shoulder'] - rs, rs, rs, 0, 90, p['shoulder_corner_steps'])
    for index, (name, right, _) in enumerate(order):
        h = heights[name]
        # The inner (left) wall rises to the next, higher notch's shoulder; the High notch's to its own.
        left_top = heights[order[index + 1][0]]['shoulder'] if index + 1 < len(order) else h['shoulder']
        assert h['shoulder'] - fl > h['centre'] + 1e-9, name + ': the notch wall has no straight part'
        pts += arc(right + r + fl, h['shoulder'] - fl, fl, fl, 90, 180, p['notch_flare_steps'])
        pts += arc(right, h['centre'], r, r, 0, -180, p['notch_arc_steps'])
        pts += arc(right - r - fl, left_top - fl, fl, fl, 0, 90, p['notch_flare_steps'])
    # Crowned left lobe: a quarter-ellipse meeting the left edge with a vertical tangent at
    # left_lobe_side_top, peaking exactly at the High shoulder + lobe_crown, and passing through
    # the High notch's flare top.
    high = heights[order[-1][0]]
    sx, sy = pts[-1]
    cy = p['left_lobe_side_top']
    ry = high['shoulder'] + p['lobe_crown'] - cy
    c = sqrt(1.0 - ((sy - cy) / ry) ** 2)
    rx = (sx + hw) / (1.0 + c)
    cx = -hw + rx
    start = math.degrees(math.atan2((sy - cy) / ry, c))
    pts += arc(cx, cy, rx, ry, start, 90, p['left_lobe_steps_to_crown'])[1:]
    pts += arc(cx, cy, rx, ry, 90, 180, p['left_lobe_steps_from_crown'])[1:]
    # Top of the left edge must be exact so the bounding box is exact.
    pts[-1] = (-hw, cy)
    # Sanity: strictly ordered lobes, no repeated points, the crown is the highest point.
    for a, b in zip(pts, pts[1:] + pts[:1]):
        assert math.dist(a, b) > 1e-4, ('repeated outline point', a, b)
    return pts


def lathe(bm, uv, profile, segments, axis_z):
    """Revolve (radius, y) profile points around the line x = 0, z = axis_z (parallel to Blender Y).
    A radius of 0 is a pole on the axis; a ring at either end gets a flat fan cap. The seam is
    at the bottom. Sides: u = segment / segments, v = y in studs. Flat caps: planar (x, z)."""
    angles = [-pi / 2 + 2 * pi * i / segments for i in range(segments)]
    rings = []
    for radius, y in profile:
        if radius == 0:
            rings.append([bm.verts.new((0.0, y, axis_z))])
        else:
            rings.append([bm.verts.new((radius * cos(a), y, axis_z + radius * sin(a))) for a in angles])

    def face(verts, uvs):
        f = bm.faces.new(verts)
        for loop, coord in zip(f.loops, uvs):
            loop[uv].uv = coord
        return f

    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        ya, yb = profile[k][1], profile[k + 1][1]
        for i in range(segments):
            j = (i + 1) % segments
            u0, u1 = i / segments, (i + 1) / segments
            if len(a) == 1:
                face((a[0], b[j], b[i]), (((u0 + u1) / 2, ya), (u1, yb), (u0, yb)))
            elif len(b) == 1:
                face((a[i], a[j], b[0]), ((u0, ya), (u1, ya), ((u0 + u1) / 2, yb)))
            else:
                face((a[i], a[j], b[j], b[i]), ((u0, ya), (u1, ya), (u1, yb), (u0, yb)))
    for k in (0, len(rings) - 1):
        ring = rings[k]
        if len(ring) == 1:
            continue
        y = profile[k][1]
        centre = bm.verts.new((0.0, y, axis_z))
        for i in range(segments):
            j = (i + 1) % segments
            tri = (centre, ring[j], ring[i])
            face(tri, [(v.co.x, v.co.z) for v in tri])


def build_head(p):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    half = p['head_thickness'] / 2
    outline = [(-x, y) for x, y in head_outline(p)]  # Roblox x -> Blender x = -x; Roblox y -> Blender z
    front = [bm.verts.new((bx, -half, bz)) for bx, bz in outline]
    back = [bm.verts.new((bx, half, bz)) for bx, bz in outline]
    n = len(outline)
    bm.faces.new(front)
    bm.faces.new(back)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    loops = [bm.edges.get((front[i], front[(i + 1) % n])) for i in range(n)]
    loops += [bm.edges.get((back[i], back[(i + 1) % n])) for i in range(n)]
    bmesh.ops.bevel(bm, geom=loops, offset=p['head_bevel'], offset_type='OFFSET', segments=1,
                    profile=0.5, affect='EDGES', clamp_overlap=True)

    # UVs: caps get planar Blender XZ; the side wall and bevel strips get (perimeter, thickness).
    perimeter = [0.0]
    for i in range(n):
        perimeter.append(perimeter[-1] + math.dist(outline[i], outline[(i + 1) % n]))
    total = perimeter[-1]

    def arc_length(x, z):
        best, best_s = None, 0.0
        for i in range(n):
            ax, az = outline[i]
            bx, bz = outline[(i + 1) % n]
            dx, dz = bx - ax, bz - az
            t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)))
            d = (x - ax - t * dx) ** 2 + (z - az - t * dz) ** 2
            if best is None or d < best:
                best, best_s = d, perimeter[i] + t * (perimeter[i + 1] - perimeter[i])
        return best_s

    bm.normal_update()
    for f in bm.faces:
        if abs(f.normal.y) > 0.99:
            for loop in f.loops:
                loop[uv].uv = (loop.vert.co.x, loop.vert.co.z)
        else:
            s = [arc_length(loop.vert.co.x, loop.vert.co.z) for loop in f.loops]
            if max(s) - min(s) > total / 2:
                s = [v + total if v < total / 2 else v for v in s]
            for loop, value in zip(f.loops, s):
                loop[uv].uv = (value, loop.vert.co.y)
    return bm


def build_shaft(p):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    rings = p['shaft_rings']
    r0, r1 = p['shaft_head_diameter'] / 2, p['shaft_butt_diameter'] / 2
    profile = []
    for k in range(rings):
        t = k / (rings - 1)
        profile.append((r0 + (r1 - r0) * t, p['shaft_z0'] + p['shaft_length'] * t))
    lathe(bm, uv, profile, p['radial_segments'], p['shaft_axis_y'])
    return bm


def shaft_radius_at(p, z):
    t = (z - p['shaft_z0']) / p['shaft_length']
    return (p['shaft_head_diameter'] + (p['shaft_butt_diameter'] - p['shaft_head_diameter']) * t) / 2


def build_ferrule(p):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    rc, ch, z0, z1 = p['collar_diameter'] / 2, p['collar_chamfer'], p['collar_z0'], p['collar_z1']
    lathe(bm, uv, [(rc - ch, z0), (rc, z0 + ch), (rc, z1 - ch), (rc - ch, z1)],
          p['radial_segments'], p['shaft_axis_y'])
    zc = p['shaft_z0'] + p['ring_position'] * p['shaft_length']
    rr = shaft_radius_at(p, zc) + p['ring_extra_diameter'] / 2
    half, rch = p['ring_length'] / 2, p['ring_chamfer']
    assert rr - rch > shaft_radius_at(p, zc + half), 'the ring chamfer would cut into the shaft'
    lathe(bm, uv, [(rr - rch, zc - half), (rr, zc - half + rch), (rr, zc + half - rch), (rr - rch, zc + half)],
          p['radial_segments'], p['shaft_axis_y'])
    return bm


def build_cap(p):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    rc, z0, z1, dome = p['cap_diameter'] / 2, p['cap_z0'], p['cap_z1'], p['cap_dome_height']
    assert rc > shaft_radius_at(p, z0), 'the cap must be wider than the shaft end'
    profile = [(rc, z0)]
    rings = p['cap_dome_rings']
    for k in range(rings):  # quarter ellipse from the side (0 degrees) toward the pole
        a = (pi / 2) * k / rings
        profile.append((rc * cos(a), (z1 - dome) + dome * sin(a)))
    profile.append((0, z1))
    lathe(bm, uv, profile, p['radial_segments'], p['shaft_axis_y'])
    return bm


# ---------------------------------------------------------------------------------------------
# 5. Finish: merge, normals, triangulate, smoothing, one object per mesh at the origin
# ---------------------------------------------------------------------------------------------

def finish(bm, name, p, collection):
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=p['merge_distance'])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method='BEAUTY', ngon_method='BEAUTY')
    bm.normal_update()
    sharp = radians(p['sharp_angle_degrees'])
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = len(e.link_faces) == 2 and e.calc_face_angle(pi) < sharp
    mesh = bpy.data.meshes.new(name + 'Mesh')
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    obj['triangle_count'] = len(mesh.polygons)
    obj['roblox_material'] = p['roblox_materials'][name]
    obj['roblox_color'] = ', '.join(str(c) for c in p['colors'][name])  # a string: the FBX exporter only takes float vectors
    return obj


# ---------------------------------------------------------------------------------------------
# 6. Validation
# ---------------------------------------------------------------------------------------------

def bounds(obj):
    xs = [v.co for v in obj.data.vertices]
    lo = Vector((min(c.x for c in xs), min(c.y for c in xs), min(c.z for c in xs)))
    hi = Vector((max(c.x for c in xs), max(c.y for c in xs), max(c.z for c in xs)))
    return lo, hi


def validate(obj, p):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bad_edges = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    tiny = sum(1 for f in bm.faces if f.calc_area() < p['min_face_area'])
    non_tri = sum(1 for f in bm.faces if len(f.verts) != 3)
    loose = sum(1 for v in bm.verts if not v.link_faces)
    volume = 0.0
    for f in bm.faces:
        a, b, c = (loop.vert.co for loop in f.loops)
        volume += a.dot(b.cross(c)) / 6.0
    bm.free()
    report = {'triangles': len(obj.data.polygons), 'non_manifold_edges': bad_edges,
              'zero_area_faces': tiny, 'non_triangles': non_tri, 'loose_vertices': loose,
              'signed_volume': volume}
    assert bad_edges == 0, (obj.name, 'edges without exactly two faces', bad_edges)
    assert tiny == 0, (obj.name, 'zero-area faces', tiny)
    assert non_tri == 0 and loose == 0, (obj.name, report)
    assert volume > 0, (obj.name, 'normals point inward (signed volume)', volume)
    assert tuple(obj.location) == (0, 0, 0) and tuple(obj.scale) == (1, 1, 1), obj.name
    assert tuple(obj.rotation_euler) == (0, 0, 0), obj.name
    assert len(obj.data.uv_layers) == 1, obj.name
    return report


def check_dimensions(objects, p):
    """The meshes must land exactly where Config.Bridge and BridgeBuilder expect them."""
    tol = 1e-6  # float32 vertex storage
    hw, half = p['head_half_width'], p['head_thickness'] / 2
    heights = notch_heights(p)
    top = heights['High']['shoulder'] + p['lobe_crown']

    def near(a, b):
        return all(abs(x - y) < tol for x, y in zip(a, b))

    lo, hi = bounds(objects['Head'])
    assert near(lo, (-hw, -half, -p['pivot_height'])) and near(hi, (hw, half, top)), ('Head bounds', lo, hi)
    # The notch bottoms (the cue rest minus the cue radius) are real vertices on the side wall.
    wall = [v.co for v in objects['Head'].data.vertices if abs(abs(v.co.y) - (half - p['head_bevel'])) < tol]
    for name, h in heights.items():
        assert any(near((c.x, c.z), (-h['x'], h['bottom'])) for c in wall), ('missing notch bottom', name)
    ax = p['shaft_axis_y']
    r = p['shaft_butt_diameter'] / 2
    lo, hi = bounds(objects['Shaft'])
    assert near(lo, (-r, p['shaft_z0'], ax - r)) and near(hi, (r, p['shaft_z0'] + p['shaft_length'], ax + r)), \
        ('Shaft bounds', lo, hi)
    rc = p['collar_diameter'] / 2
    lo, hi = bounds(objects['Ferrule'])
    assert near(lo, (-rc, p['collar_z0'], ax - rc)), ('Ferrule bounds', lo, hi)
    rc = p['cap_diameter'] / 2
    lo, hi = bounds(objects['Cap'])
    assert near(lo, (-rc, p['cap_z0'], ax - rc)) and near(hi, (rc, p['cap_z1'], ax + rc)), ('Cap bounds', lo, hi)


# ---------------------------------------------------------------------------------------------
# 7. Preview materials (the game dresses the parts itself; these only colour the render)
# ---------------------------------------------------------------------------------------------

def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def preview_material(name, rgb, roughness, metallic):
    mat = bpy.data.materials.new('Bridge_' + name)
    colour = tuple(srgb_to_linear(c) for c in rgb) + (1.0,)
    mat.diffuse_color = colour
    if mat.node_tree is None:  # Blender 5 gives new materials a node tree; older versions need use_nodes
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    shader = nodes.new('ShaderNodeBsdfPrincipled')
    out = nodes.new('ShaderNodeOutputMaterial')
    shader.location, out.location = (0, 0), (300, 0)
    links.new(shader.outputs['BSDF'], out.inputs['Surface'])
    shader.inputs['Base Color'].default_value = colour
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Metallic'].default_value = metallic
    return mat


def assign_materials(objects, p):
    looks = {'Head': (0.35, 0.0), 'Shaft': (0.45, 0.0), 'Ferrule': (0.3, 1.0), 'Cap': (0.8, 0.0)}
    for name, obj in objects.items():
        mat = preview_material(name, p['colors'][name], *looks[name])
        obj.data.materials.clear()
        obj.data.materials.append(mat)


# ---------------------------------------------------------------------------------------------
# 8. Preview render (Cycles; never touches bpy.context.screen)
# ---------------------------------------------------------------------------------------------

def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


def render_preview(scene, p, path):
    rig = bpy.data.collections.new('Preview')
    scene.collection.children.link(rig)
    rig['preview_only'] = 'Camera, lights and floor for renders/preview.png; never exported.'
    cam_data = bpy.data.cameras.new('PreviewCamera')
    cam_data.lens = 40
    cam_data.clip_start = 0.01
    cam = bpy.data.objects.new('PreviewCamera', cam_data)
    rig.objects.link(cam)
    cam.location = (1.75, -1.95, 1.15)
    aim(cam, (-0.35, 1.3, -0.42))
    scene.camera = cam
    for name, loc, power, size in (('Key', (1.2, -1.6, 2.4), 90.0, 1.6), ('Fill', (-2.2, 0.6, 1.6), 45.0, 2.0),
                                   ('Rim', (-0.8, 5.0, 1.4), 70.0, 2.5)):
        light_data = bpy.data.lights.new(name, 'AREA')
        light_data.energy = power
        light_data.shape = 'DISK'
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        rig.objects.link(light)
        light.location = loc
        aim(light, (0, 1.0, -0.2))
    floor_bm = bmesh.new()
    s = 20.0
    z = -p['pivot_height']
    floor_bm.faces.new([floor_bm.verts.new(c) for c in ((-s, -s, z), (s, -s, z), (s, s, z), (-s, s, z))])
    floor_mesh = bpy.data.meshes.new('PreviewFloorMesh')
    floor_bm.to_mesh(floor_mesh)
    floor_bm.free()
    floor = bpy.data.objects.new('PreviewFloor', floor_mesh)
    rig.objects.link(floor)
    cloth = preview_material('PreviewCloth', (7, 140, 207), 0.9, 0.0)  # tournament-blue cloth, like the table
    floor_mesh.materials.append(cloth)
    world = bpy.data.worlds.new('PreviewWorld')
    if world.node_tree is None:
        world.use_nodes = True
    background = world.node_tree.nodes.get('Background')
    if background is not None:
        background.inputs['Color'].default_value = (0.62, 0.66, 0.74, 1.0)
        background.inputs['Strength'].default_value = 0.35
    scene.world = world
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = p['preview_samples']
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = p['preview_resolution']
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.image_settings.color_depth = '8'
    scene.render.image_settings.compression = 100
    scene.view_settings.view_transform = 'Standard'
    looks = [x.identifier for x in scene.view_settings.bl_rna.properties['look'].enum_items]
    scene.view_settings.look = 'Medium High Contrast' if 'Medium High Contrast' in looks else 'None'
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------------------------------------
# 9-10. FBX export (the table's exact settings) and the round-trip check
# ---------------------------------------------------------------------------------------------

def export_fbx(path, objects):
    view_layer = bpy.context.view_layer
    for obj in bpy.context.scene.objects:
        obj.select_set(obj in objects)
    view_layer.objects.active = objects[0]
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={'MESH', 'EMPTY'},
                             axis_forward='-Z', axis_up='Y', global_scale=1.0, apply_unit_scale=False,
                             apply_scale_options='FBX_SCALE_UNITS', use_space_transform=True,
                             bake_space_transform=True, use_mesh_modifiers=True, use_triangles=True,
                             mesh_smooth_type='OFF', add_leaf_bones=False, bake_anim=False,
                             path_mode='RELATIVE', embed_textures=False, use_custom_props=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(False)


def world_bounds(obj, matrix):
    pts = [matrix @ v.co for v in obj.data.vertices]
    return ([min(c[i] for c in pts) for i in range(3)], [max(c[i] for c in pts) for i in range(3)])


def reimport_check(path, objects, p):
    expected = {o.name: world_bounds(o, o.matrix_world) for o in objects}
    before = {pool: set(getattr(bpy.data, pool)) for pool in ('objects', 'meshes', 'materials', 'images')}
    scratch = bpy.data.scenes.new('BridgeReimportCheck')
    with bpy.context.temp_override(scene=scratch, view_layer=scratch.view_layers[0]):
        bpy.ops.import_scene.fbx(filepath=path)
    scratch.view_layers[0].update()
    imported = [o for o in scratch.objects if o.type == 'MESH']
    worst, found = 0.0, {}
    for obj in imported:
        base = obj.name.split('.')[0]
        found[base] = obj.name
        lo, hi = world_bounds(obj, obj.matrix_world)
        elo, ehi = expected[base]
        worst = max(worst, max(abs(a - b) for a, b in zip(lo + hi, elo + ehi)))
    assert sorted(found) == sorted(expected), ('reimported meshes', sorted(found))
    for pool, old in before.items():
        for block in list(getattr(bpy.data, pool)):
            if block not in old:
                getattr(bpy.data, pool).remove(block)
    bpy.data.scenes.remove(scratch)
    assert worst <= p['reimport_tolerance'], ('FBX round trip moved a bounding box by', worst)
    return worst


# ---------------------------------------------------------------------------------------------
# 11. Parameters.json (Roblox-local values the game reads through Config.Bridge)
# ---------------------------------------------------------------------------------------------

def clean(value):
    """Round away float noise and never write -0.0."""
    if isinstance(value, float):
        return round(value, 9) + 0.0
    if isinstance(value, (list, tuple)):
        return [clean(v) for v in value]
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    return value


def to_roblox(v):
    """Blender (x, y, z) -> Roblox local (-x, z, y)."""
    return [-v[0], v[2], v[1]]


def write_parameters(path, p, objects, reports, reimport_error):
    heights = notch_heights(p)
    head_lo, head_hi = bounds(objects['Head'])
    mesh_bounds = {}
    for name, obj in objects.items():
        lo, hi = bounds(obj)
        a, b = to_roblox(lo), to_roblox(hi)
        # Measured from float32 vertices, so rounded to 6 decimals (well inside the 1e-6 checks).
        rmin = [round(min(x, y), 6) for x, y in zip(a, b)]
        rmax = [round(max(x, y), 6) for x, y in zip(a, b)]
        mesh_bounds[name] = {'Min': rmin, 'Max': rmax,
                             'Centre': [(x + y) / 2 for x, y in zip(rmin, rmax)],
                             'Size': [y - x for x, y in zip(rmin, rmax)]}
    head_centre = [0.0, (-p['pivot_height'] + heights['High']['shoulder'] + p['lobe_crown']) / 2, 0.0]
    measured = mesh_bounds['Head']['Centre']
    assert all(abs(a - b) < 1e-6 for a, b in zip(head_centre, measured)), ('HeadCentre', head_centre, measured)
    counts = {name: obj['triangle_count'] for name, obj in objects.items()}
    counts['Total'] = sum(counts.values())
    data = {
        'asset': 'BridgeModel',
        'generator': 'assets/bridge/Bridge.py',
        'blender_version': bpy.app.version_string,
        'units': 'studs (0.16 studs per inch)',
        'frame': ("Roblox local after BridgeBuilder.normalize: origin = the pivot (the cue axis resting in the "
                  "High notch); +X = the shooter's right, +Y = up, +Z = from the head down the shaft. "
                  'Blender (x, y, z) = Roblox local (-x, z, y).'),
        # Keys and shapes match Config.Bridge; tests/bridge_test.luau compares them.
        'roblox_local': {
            'PivotHeightStuds': p['pivot_height'],
            'Notches': [{'Name': name, 'X': right, 'Y': rest} for name, right, rest in p['notches']],
            'HeadCentre': head_centre,
            'HeadWidthStuds': 2 * p['head_half_width'],
            'ShaftAxisYStuds': p['shaft_axis_y'],
            'ShaftLengthStuds': p['shaft_length'],
            'Meshes': {name: {'Material': p['roblox_materials'][name], 'Color': list(p['colors'][name])}
                       for name in MESH_NAMES},
        },
        'derived': {
            'NotchHeightsAboveCloth': {n: p['pivot_height'] + h['rest'] for n, h in heights.items()},
            'NotchBottomsY': {n: h['bottom'] for n, h in heights.items()},
            'NotchShouldersY': {n: h['shoulder'] for n, h in heights.items()},
            'NotchRadiusStuds': p['notch_radius'],
            'NotchDepthStuds': p['notch_depth'],
            'HeadTopY': heights['High']['shoulder'] + p['lobe_crown'],
            'HeadSize': mesh_bounds['Head']['Size'],
            'OverallLengthStuds': p['cap_z1'] + p['head_thickness'] / 2,
            'MeshBounds': mesh_bounds,
        },
        'triangle_counts': counts,
        'triangle_budget': p['triangle_budget'],
        'validation': {
            'meshes': reports,
            'fbx_reimport_max_bounds_error': reimport_error,
        },
        'parameters': p,
    }
    with open(path, 'w') as handle:
        handle.write(json.dumps(clean(data), indent=2) + '\n')
    return data


# ---------------------------------------------------------------------------------------------
# 12. Embed this script and save the .blend
# ---------------------------------------------------------------------------------------------

def embed_script():
    source = os.path.abspath(__file__) if '__file__' in globals() else ''
    text = bpy.data.texts.get(TEXT_NAME)
    if os.path.isfile(source):
        if text is None:
            text = bpy.data.texts.new(TEXT_NAME)
        text.clear()
        with open(source) as handle:
            text.write(handle.read())
    return text


def save_blend(path):
    bpy.ops.wm.save_as_mainfile(filepath=path, check_existing=False, compress=True)
    backup = path + '1'
    if bpy.app.background and os.path.exists(backup):
        os.remove(backup)  # a headless rebuild regenerates everything; no .blend1 residue


def main():
    p = PARAMETERS
    ensure_fbx_addon()
    scene = clear_scene(p)
    model = bpy.data.collections.new('BridgeModel')
    scene.collection.children.link(model)
    builders = {'Head': build_head, 'Shaft': build_shaft, 'Ferrule': build_ferrule, 'Cap': build_cap}
    objects = {name: finish(builders[name](p), name, p, model) for name in MESH_NAMES}
    reports = {name: validate(obj, p) for name, obj in objects.items()}
    check_dimensions(objects, p)
    total = sum(r['triangles'] for r in reports.values())
    assert total <= p['triangle_budget'], ('over the triangle budget', total)
    assign_materials(objects, p)
    if p['render_preview']:
        render_preview(scene, p, os.path.join(OUTPUT_DIR, 'renders', 'preview.png'))
    fbx_path = os.path.join(OUTPUT_DIR, FBX_NAME)
    export_fbx(fbx_path, list(objects.values()))
    reimport_error = reimport_check(fbx_path, list(objects.values()), p) if p['reimport_check'] else None
    write_parameters(os.path.join(OUTPUT_DIR, 'Parameters.json'), p, objects, reports, reimport_error)
    embed_script()
    save_blend(os.path.join(OUTPUT_DIR, BLEND_NAME))
    for name in MESH_NAMES:
        r = reports[name]
        print('BRIDGE %-8s %5d triangles  volume %.6f  non-manifold %d  zero-area %d'
              % (name, r['triangles'], r['signed_volume'], r['non_manifold_edges'], r['zero_area_faces']))
    print('BRIDGE total %d triangles (budget %d); FBX round trip max bounds error %s'
          % (total, p['triangle_budget'], reimport_error))
    print('BRIDGE OK ->', OUTPUT_DIR)


if __name__ == '__main__':
    main()
