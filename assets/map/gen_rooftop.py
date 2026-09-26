"""The rooftop's architecture for Crazy 8 Ball's hub map, built headlessly in Blender from the plan.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \\
        --python assets/map/gen_rooftop.py [-- render]

It reads Layout.json (map_layout.py: every zone and position) and writes fbx/Rooftop.fbx
(import it with the 3D Importer, assets/map/Readme.md) and Map.blend. With `-- render` it also
renders the entrance, high three-quarter and lounge views to checkpoints/blender/ with the
textures from gen_textures.py, the 16 tables and a floor (neither is exported).

The meshes (Roblox studs, every origin at the world origin; map_common explains the axes):

    Parapet        the low stone wall round the terrace, the stair and the lower landing, with
                   its coping
    RailingFrame   the dark posts, handrail and shoe of the glass railing (a flat colour)
    RailingGlass   the glass panes (a flat colour, transparent)
    Steps          the entrance stair, the lounge's flight and the lounge riser
    Pergola        the cream columns (the pergola's and the two at the entrance), its fascia
                   and joist
    PergolaSlats   the wood slats of its roof
    Vines          vine drapes, climbers and bougainvillea (alpha cards, double-sided)
    TowerTop       the tower's top floors under the parapet: a cornice and four floors of windows
    TableGlow      the warm glow on the floor under each table (transparent)
    FloorShade     soft contact shade on the floor along walls and under columns (transparent)
    AnchorO/X/Z    tiny cubes MapBuilder.prepareImport uses to undo the importer's placement

The floor is not a mesh: it is the gray-box's floor Parts with a tiled MaterialVariant (Part
materials map in world space; STUDIO_NOTES). Collision is the gray-box's invisible Parts; no
mesh here collides. The script fails (exit 1) on any check: triangle budgets, anchors, the FBX
round trip.
"""

import json
import math
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import map_common as mc  # noqa: E402
import map_layout as ml  # noqa: E402

# Every drawing choice (studs). The layout's own numbers come from map_layout.P.
PARAMETERS = {
    'coping_height': 0.25,  # the cap on the parapet
    'coping_overhang': 0.25,  # past each face of the parapet
    'wall_chamfer': 0.06,  # the parapet's vertical corners
    'post_size': 0.2,  # railing post, square
    'post_spacing': 3.8,  # at most this far apart
    'rail_width': 0.4,  # handrail
    'rail_height': 0.25,
    'shoe_width': 0.16,  # the rail the glass stands in
    'shoe_height': 0.12,
    'glass_top_gap': 0.2,  # glass stops this far under the handrail's top
    'nosing': 0.07,  # the chamfer on each step's front edge
    'riser_offset': 0.04,  # the lounge riser stands this far proud of the platform part
    'column_chamfer': 0.22,  # the columns are plain square shafts, as in the art
    'riser_lip': 0.3,  # the lounge platform's coping overhangs its riser this much...
    'riser_lip_height': 0.25,  # ...and is this thick
    'fascia_height': 6.5,  # deep, so the pergola reads as a heavy roof (Stage 2 critic)
    'fascia_thickness': 1.2,
    'fascia_overrun': 2.0,  # the fascia runs this far past the end columns' centres
    'joist_width': 1.0,
    'joist_height': 1.4,
    'slat_width': 1.2,
    'slat_pitch': 2.0,
    'slat_thickness': 0.6,
    'slat_below_top': 0.2,  # the slats' top sits this far under the fascia's top
    'drape_tile_studs': 16.0,  # the drape image's width in studs: its two clumps sit at u 0.25 and 0.75
    'drape_card': 7.0,  # one clump card centred on each column head, this wide
    'drape_height': 9.5,  # from the fascia's top down (hangs about 3 under its foot)
    'card_offset': 0.06,  # vine cards stand this far off the surface they hang on
    'climb_card': 3.4,  # a square climber card on a column face
    'bloom_card': 4.0,
    'floor_height': 10.0,  # the tower's storeys (the facade strip is one)
    'tower_floors': 4,  # storeys drawn under the parapet
    'facade_offset': 0.12,  # the facade stands this far off the gray-box tower block
    'cornice_height': 2.5,
    'cornice_depth': 0.6,
    'shade_width': 2.2,  # the contact shade strip on the floor at a wall's foot
    'shade_lift': 0.015,  # overlays float this far over the floor
    'glow_lift': 0.02,
    'blob_extra': 3.0,  # the shade under a column, this much wider than it
}
TRIANGLE_CAP_TOTAL = 60000  # the brief's architecture group
TRIANGLE_CAP_MESH = 20000  # Roblox's per-mesh limit

LAYOUT = json.load(open(os.path.join(HERE, 'Layout.json')))
P = ml.P
Z = LAYOUT['zones']
H = LAYOUT['heights']


# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

def run_points(points, spacing):
    """Posts along a polyline: every vertex, and evenly between vertices at most `spacing`."""
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        length = math.dist(a, b)
        count = max(1, math.ceil(length / spacing - 1e-9))
        for k in range(1, count + 1):
            t = k / count
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def along_box(m, a, b, width, y0, y1, strip, extend=0.0, top_strip='top'):
    """An axis-aligned box of the given width centred on the horizontal segment a -> b (x, z),
    from y0 to y1, extended `extend` past each end."""
    (ax, az), (bx, bz) = a, b
    if abs(bx - ax) >= abs(bz - az):
        x0, x1 = min(ax, bx) - extend, max(ax, bx) + extend
        outline = mc.outward_rect(x0, az - width / 2, x1, az + width / 2)
    else:
        z0, z1 = min(az, bz) - extend, max(az, bz) + extend
        outline = mc.outward_rect(ax - width / 2, z0, ax + width / 2, z1)
    m.prism(outline, y0, y1, strip, top=True, top_strip=top_strip)


def floor_strip(m, a, b, inward, width, y, rect):
    """A flat strip on the floor along a -> b (x, z), `width` wide toward `inward` (a unit
    (dx, dz)), facing up; V runs from rect's v0 at the wall to v1 away from it."""
    u0, v0, u1, v1 = rect
    (ax, az), (bx, bz) = a, b
    cx, cz = ax + inward[0] * width, az + inward[1] * width
    dx_, dz_ = bx + inward[0] * width, bz + inward[1] * width
    pts = [(ax, y, az), (bx, y, bz), (dx_, y, dz_), (cx, y, cz)]
    uvs = [(u0 + 0.1 * (u1 - u0), v0), (u1 - 0.1 * (u1 - u0), v0), (u1 - 0.1 * (u1 - u0), v1), (u0 + 0.1 * (u1 - u0), v1)]
    # Face up: the corners must turn the right way round seen from above.
    n = Vector(pts[1]) - Vector(pts[0])
    w = Vector(pts[3]) - Vector(pts[0])
    if n.cross(w).y < 0:
        pts, uvs = pts[::-1], uvs[::-1]
    m.face(pts, uvs)


def up_quad(m, cx, cz, hx, hz, y, rect):
    """A horizontal quad facing up, centred (cx, cz), UV rect mapped X -> U, Z -> V."""
    u0, v0, u1, v1 = rect
    pts = [(cx - hx, y, cz + hz), (cx + hx, y, cz + hz), (cx + hx, y, cz - hz), (cx - hx, y, cz - hz)]
    uvs = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    m.face(pts, uvs)


# ---------------------------------------------------------------------------------------------
# The parts
# ---------------------------------------------------------------------------------------------

def geometry():
    A = PARAMETERS
    tx0, tz0, tx1, tz1 = Z['terrace']
    front, back = tz1, tz0
    pt, ph, top = P['parapet_thickness'], P['parapet_height'], P['railing_top']
    sx = P['steps_width'] / 2
    lower_y = H['lower_landing']
    platform_y = H['lounge']
    lower_end = Z['lower_landing'][3]
    lw, lf = P['lounge_half_width'], P['lounge_flight_half_width']
    cope = A['coping_height']

    parapet = mc.Mesh('Parapet')
    frame = mc.Mesh('RailingFrame')
    glass = mc.Mesh('RailingGlass')
    steps = mc.Mesh('Steps')
    pergola = mc.Mesh('Pergola')
    slats = mc.Mesh('PergolaSlats')
    vines = mc.Mesh('Vines')
    tower = mc.Mesh('TowerTop')
    glow = mc.Mesh('TableGlow')
    shade = mc.Mesh('FloorShade')

    # ---- Parapet: walls as boxes (x0, z0, x1, z1, floor level, base) ------------------------
    # (x0, z0, x1, z1, walking level beside it, base, the level its baked shade sits at)
    walls = [
        # Back, in three: the corners at the terrace level, the lounge's at the platform.
        (tx0 - pt, back - pt, -lw, back, 0.0, -1.0, 0.0),
        (-lw, back - pt, lw, back, platform_y, -1.0, platform_y),
        (lw, back - pt, tx1 + pt, back, 0.0, -1.0, 0.0),
        # Sides (between the front and back walls, which take the corners).
        (tx0 - pt, back, tx0, front, 0.0, -1.0, 0.0),
        (tx1, back, tx1 + pt, front, 0.0, -1.0, 0.0),
        # Front, stopping at the stair walls.
        (tx0 - pt, front, -(sx + pt), front + pt, 0.0, -1.0, 0.0),
        (sx + pt, front, tx1 + pt, front + pt, 0.0, -1.0, 0.0),
        # The stair's side walls, to the lower landing's outer edge, as tall as the roof's.
        (-(sx + pt), front, -sx, lower_end + pt, 0.0, lower_y - 1.0, lower_y),
        (sx, front, sx + pt, lower_end + pt, 0.0, lower_y - 1.0, lower_y),
        # The lower landing's front wall, between them.
        (-sx, lower_end, sx, lower_end + pt, lower_y, lower_y - 1.0, lower_y),
    ]
    for x0, z0, x1, z1, level, base, ao_level in walls:
        body_top = level + ph
        c = A['wall_chamfer']
        outline = mc.chamfer_rect((x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2, (z1 - z0) / 2, c)
        # Below the shade's level the wall is the strip's foot colour; above it the gradient.
        parapet.prism(outline, base, ao_level, 'wall', top=False, v_range=(0.0, 0.0))
        parapet.prism(outline, ao_level, body_top, 'wall', top=False)
        o = A['coping_overhang']
        cap = mc.chamfer_rect((x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2 + o, (z1 - z0) / 2 + o, c)
        parapet.prism(cap, body_top, body_top + cope, 'top', top=True, bottom=True, top_strip='top')

    # ---- Railing: posts, handrail, shoe, glass along polylines on the parapets' centre lines --
    half = pt / 2
    runs = [
        # Terrace level, city side: down the stair wall, along the front, the city side and
        # the back to the lounge.
        ([(-(sx + half), lower_end + half), (-(sx + half), front + half), (tx0 - half, front + half),
          (tx0 - half, back - half), (-lw, back - half)], 0.0),
        ([(-lw, back - half), (lw, back - half)], platform_y),
        ([(lw, back - half), (tx1 + half, back - half), (tx1 + half, front + half), (sx + half, front + half),
          (sx + half, lower_end + half)], 0.0),
        ([(-sx, lower_end + half), (sx, lower_end + half)], lower_y),
    ]
    for points, level in runs:
        base = level + ph + cope
        y_top = level + top
        for x, z in run_points(points, A['post_spacing']):
            s = A['post_size'] / 2
            frame.prism(mc.outward_rect(x - s, z - s, x + s, z + s), base, y_top - A['rail_height'], 'dark', top=False)
        for a, b in zip(points, points[1:]):
            along_box(frame, a, b, A['rail_width'], y_top - A['rail_height'], y_top, 'dark',
                      extend=A['rail_width'] / 2, top_strip='dark')
            along_box(frame, a, b, A['shoe_width'], base, base + A['shoe_height'], 'dark', top_strip='dark')
            # The glass: one double-sided pane per run segment.
            g0, g1 = base + A['shoe_height'], y_top - A['glass_top_gap']
            glass.face([(a[0], g0, a[1]), (b[0], g0, b[1]), (b[0], g1, b[1]), (a[0], g1, a[1])],
                       [(0, 0), (1, 0), (1, 1), (0, 1)], double=True)

    # ---- Steps: the entrance stair (down toward +Z) ------------------------------------------
    n, rise, run = P['step_count'], P['step_rise'], P['step_run']
    c = A['nosing']
    for k in range(n):
        z0, z1 = front + run * k, front + run * (k + 1)
        y_above, y_here = -rise * k, -rise * (k + 1)
        # Nosing chamfer (facing up and toward +Z), then the riser (facing +Z), then the tread.
        steps.face([(sx, y_above, z0 - c), (-sx, y_above, z0 - c), (-sx, y_above - c, z0), (sx, y_above - c, z0)],
                   [(mc.trim_u('top', 0), mc.trim_v('riser', 1.0)), (mc.trim_u('top', 2 * sx), mc.trim_v('riser', 1.0)),
                    (mc.trim_u('top', 2 * sx), mc.trim_v('riser', 0.93)), (mc.trim_u('top', 0), mc.trim_v('riser', 0.93))])
        # The riser, facing +Z (down the stair).
        steps.wall((-sx, z0), (sx, z0), y_here, y_above - c, 'riser', v_range=(0.0, 0.9))
        steps.flat([(-sx, z0), (-sx, z1 - c), (sx, z1 - c), (sx, z0)], y_here, 'top', up=True)
    # (The last tread meets the lower landing's floor part at the stair's foot.)

    # ---- The lounge flight (up toward -Z) and the riser ---------------------------------------
    m, lrise, lrun = P['lounge_step_count'], P['lounge_step_rise'], P['lounge_step_run']
    lounge_front = Z['lounge_steps'][3]
    platform_front = Z['lounge_steps'][1]
    for k in range(m):
        z_face = lounge_front - lrun * k  # this step's riser, facing +Z
        z_back = z_face - lrun
        y0, y1 = lrise * k, lrise * (k + 1)
        steps.wall((-lf, z_face), (lf, z_face), y0, y1 - c, 'riser', v_range=(0.0, 0.9))
        steps.face([(-lf, y1 - c, z_face), (lf, y1 - c, z_face), (lf, y1, z_face - c), (-lf, y1, z_face - c)],
                   [(0, mc.trim_v('riser', 0.93)), (mc.trim_u('top', 2 * lf), mc.trim_v('riser', 0.93)),
                    (mc.trim_u('top', 2 * lf), mc.trim_v('riser', 1.0)), (0, mc.trim_v('riser', 1.0))])
        steps.flat([(-lf, z_back), (-lf, z_face - c), (lf, z_face - c), (lf, z_back)], y1, 'top', up=True)
        # The cheeks at each end of this step (the flight stands out from the platform).
        for side in (-1, 1):
            x = side * lf
            a, b = ((x, z_back), (x, z_face)) if side < 0 else ((x, z_face), (x, z_back))
            steps.wall(a, b, 0.0, y1, 'riser', v_range=(0.0, y1 / (m * lrise)))
    # The riser: the platform's front either side of the flight, and its two ends.
    ro = A['riser_offset']
    zf = platform_front + ro
    lip, lh = A['riser_lip'], A['riser_lip_height']
    y_lip = platform_y - lh
    for x0, x1 in ((-lw - ro, -lf), (lf, lw + ro)):
        steps.wall((x0, zf), (x1, zf), 0.0, y_lip, 'riser', v_range=(0.0, 0.8))
        # The coping: a slab overhanging the riser, its top flush with the platform.
        xa = x0 - (lip if x0 < -lf else 0.0)
        xb = x1 + (lip if x1 > lf else 0.0)
        coping = mc.outward_rect(xa, platform_front, xb, zf + lip)
        steps.prism(coping, y_lip, platform_y + 0.001, 'top', top=True)
        steps.flat(coping, y_lip, 'riser', up=False, frac=0.1)
    for side in (-1, 1):
        x = side * (lw + ro)
        a, b = ((x, back), (x, zf)) if side < 0 else ((x, zf), (x, back))
        steps.wall(a, b, 0.0, y_lip, 'riser', v_range=(0.0, 0.8))
        xo = x + side * lip
        coping = mc.outward_rect(min(side * lw, xo), back, max(side * lw, xo), zf + lip)
        steps.prism(coping, y_lip, platform_y + 0.001, 'top', top=True)
        steps.flat(coping, y_lip, 'riser', up=False, frac=0.1)

    # ---- Pergola: columns, fascia, joist, slats -----------------------------------------------
    px0, pz0, px1, pz1 = Z['pergola']
    pcol = P['pergola_column']
    pw = P['pergola_half_width']
    beam_y = platform_y + P['pergola_height']
    columns = [p for p in LAYOUT['props'] if p['kind'] == 'column']
    for col in columns:
        s = col['size'][0] / 2
        y0 = col['Y']
        y1 = y0 + col['size'][1]
        entrance = col.get('part_of') == 'entrance'
        # A plain shaft; the entrance's two free-standing columns get a flat cap.
        pergola.prism(mc.chamfer_rect(col['X'], col['Z'], s, s, A['column_chamfer']), y0, y1, 'column', top=entrance)
    zf_row, zb_row = pz1 - pcol / 2, pz0 + pcol / 2
    ft, fh = A['fascia_thickness'], A['fascia_height']
    over = pw + A['fascia_overrun']
    fascia_boxes = [
        (-over, zf_row - ft / 2, over, zf_row + ft / 2),
        (-over, zb_row - ft / 2, over, zb_row + ft / 2),
        (-pw - ft / 2, zb_row + ft / 2, -pw + ft / 2, zf_row - ft / 2),
        (pw - ft / 2, zb_row + ft / 2, pw + ft / 2, zf_row - ft / 2),
    ]
    zmid, xmid = (zf_row + zb_row) / 2, 0.0
    for x0, z0, x1, z1 in fascia_boxes:
        outline = mc.outward_rect(x0, z0, x1, z1)
        # Outer faces in the lit cream, inner faces (toward the pergola's middle) in its shade.
        n = len(outline)
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        u = 0.0
        for i in range(n):
            a, b = outline[i], outline[(i + 1) % n]
            nx, nz = -(b[1] - a[1]), b[0] - a[0]
            mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            inward = (nx * (xmid - mx) + nz * (zmid - mz)) > 0 and abs(cz - zmid) + abs(cx - xmid) > 0
            u = pergola.wall(a, b, beam_y, beam_y + fh, 'soffit' if inward else 'fascia', u)
        pergola.flat(outline, beam_y + fh, 'top', up=True)
        pergola.flat(outline, beam_y, 'soffit', up=False)
    jw, jh = A['joist_width'], A['joist_height']
    top_y = beam_y + fh - A['slat_below_top']
    slat_bottom = top_y - A['slat_thickness']
    zm = (zf_row + zb_row) / 2
    joist = mc.outward_rect(-pw + ft / 2, zm - jw / 2, pw - ft / 2, zm + jw / 2)
    pergola.prism(joist, slat_bottom - jh, slat_bottom, 'soffit', top=False)
    pergola.flat(joist, slat_bottom - jh, 'soffit', up=False)
    x = -pw + A['slat_pitch'] / 2
    while x < pw - A['slat_pitch'] / 2 + 1e-6:
        w = A['slat_width'] / 2
        z0, z1 = zb_row + ft / 2, zf_row - ft / 2
        slats.wall((x - w, z0), (x - w, z1), slat_bottom, top_y, 'wood')  # facing -X
        slats.wall((x + w, z1), (x + w, z0), slat_bottom, top_y, 'wood')  # facing +X
        outline = mc.outward_rect(x - w, z0, x + w, z1)
        slats.flat(outline, top_y, 'wood', up=True, frac=0.8, along='z')
        slats.flat(outline, slat_bottom, 'wood', up=False, frac=0.2, along='z')
        x += A['slat_pitch']

    # ---- Vines: a drape along the front fascia, climbers on some front columns, bougainvillea -
    off = A['card_offset']
    drape_u = A['drape_tile_studs']
    u0, v0, u1, v1 = mc.FOLIAGE['drape']
    dz = zf_row + ft / 2 + off
    dy1, dy0 = beam_y + fh, beam_y + fh - A['drape_height']
    front_cols = sorted([c for c in columns if c.get('part_of') == 'pergola' and c['Z'] > (pz0 + pz1) / 2],
                        key=lambda c: c['X'])
    # One clump centred on each column head, the bays between bare (Stage 2 critic): the drape
    # image holds two clumps, at u 0.25 and 0.75; alternate them.
    half_u = A['drape_card'] / drape_u / 2
    hw = A['drape_card'] / 2
    for i, col in enumerate(front_cols):
        uc = 0.25 if i % 2 == 0 else 0.75
        x = col['X']
        vines.face([(x - hw, dy0, dz), (x + hw, dy0, dz), (x + hw, dy1, dz), (x - hw, dy1, dz)],
                   [(uc - half_u, v0), (uc + half_u, v0), (uc + half_u, v1), (uc - half_u, v1)], double=True)
    # And on the side fascias, at their front corners.
    for side in (-1, 1):
        xx = side * (pw + ft / 2 + off)
        zc = zf_row - ft / 2 - hw - 0.5
        a, b = ((xx, zc + hw), (xx, zc - hw)) if side < 0 else ((xx, zc - hw), (xx, zc + hw))
        vines.face([(a[0], dy0 + 1.0, a[1]), (b[0], dy0 + 1.0, b[1]), (b[0], dy1, b[1]), (a[0], dy1, a[1])],
                   [(0.75 - half_u, v0), (0.75 + half_u, v0), (0.75 + half_u, v1), (0.75 - half_u, v1)], double=True)
    cu0, cv0, cu1, cv1 = mc.FOLIAGE['climb']
    card = A['climb_card']
    for i, col in enumerate(front_cols):
        stacks = 4 if i in (0, len(front_cols) - 1) else (2 if i in (2, 3) else 0)
        s = col['size'][0] / 2
        y_top = col['Y'] + col['size'][1]
        for k in range(stacks):
            y1 = y_top - k * card * 0.92
            y0 = y1 - card
            mirror = k % 2 == 1
            ua, ub = (cu1, cu0) if mirror else (cu0, cu1)
            zc = col['Z'] + s + off
            vines.face([(col['X'] - card / 2, y0, zc), (col['X'] + card / 2, y0, zc), (col['X'] + card / 2, y1, zc),
                        (col['X'] - card / 2, y1, zc)], [(ua, cv0), (ub, cv0), (ub, cv1), (ua, cv1)], double=True)
            # And round the outer side of the end columns.
            if i in (0, len(front_cols) - 1):
                side = -1 if i == 0 else 1
                xc = col['X'] + side * (s + off)
                vines.face([(xc, y0, col['Z'] - card / 2), (xc, y0, col['Z'] + card / 2), (xc, y1, col['Z'] + card / 2),
                            (xc, y1, col['Z'] - card / 2)], [(ua, cv0), (ub, cv0), (ub, cv1), (ua, cv1)], double=True)
    bu0, bv0, bu1, bv1 = mc.FOLIAGE['bloom']
    bc = A['bloom_card']
    right = front_cols[-1]
    for bx, by in ((right['X'] - 1.2, beam_y - 1.0), (right['X'] + 1.2, beam_y - 3.6), (right['X'] - 0.6, beam_y - 6.4),
                   (right['X'] + 0.8, beam_y - 9.0), (front_cols[1]['X'] + 1.5, beam_y + 0.8),
                   (front_cols[3]['X'] - 1.5, beam_y + 1.0)):
        zc = zf_row + ft / 2 + off * 2
        vines.face([(bx - bc / 2, by - bc / 2, zc), (bx + bc / 2, by - bc / 2, zc), (bx + bc / 2, by + bc / 2, zc),
                    (bx - bc / 2, by + bc / 2, zc)], [(bu0, bv0), (bu1, bv0), (bu1, bv1), (bu0, bv1)], double=True)

    # ---- Tower top: a cornice and storeys of windows on the outer walls -----------------------
    fo = A['facade_offset']
    X0, X1, Zb, Zf = tx0 - pt - fo, tx1 + pt + fo, back - pt - fo, front + pt + fo
    floors = A['tower_floors']
    fh_ = A['floor_height']
    y_top = -1.0
    y_bottom = y_top - floors * fh_

    def facade(a, b, y_hi, y_lo):
        """Storey bands on a wall a -> b (outward-facing), between y_lo and y_hi (clipped to
        whole storeys counted from y_top)."""
        u = 0.0
        length = math.dist(a, b)
        for k in range(floors):
            band_hi, band_lo = y_top - k * fh_, y_top - (k + 1) * fh_
            hi, lo = min(band_hi, y_hi), max(band_lo, y_lo)
            if hi - lo < 1e-6:
                continue
            tower.wall(a, b, lo, hi, 'facade', u0=0.0,
                       v_range=((lo - band_lo) / fh_, (hi - band_lo) / fh_))
        return length

    bay_x = sx + pt + fo
    bay_z = lower_end + pt + fo
    # Outline of the tower's walls (outward order), the stair bay cut into the front.
    facade((X0, Zb), (X0, Zf), y_top, y_bottom)  # city side, facing -X
    facade((X0, Zf), (-bay_x, Zf), y_top, y_bottom)  # front left, facing +Z
    facade((-bay_x, Zf), (-bay_x, bay_z), lower_y - 1.0, y_bottom)  # bay, facing -X
    facade((-bay_x, bay_z), (bay_x, bay_z), lower_y - 1.0, y_bottom)  # bay front, facing +Z
    facade((bay_x, bay_z), (bay_x, Zf), lower_y - 1.0, y_bottom)  # bay, facing +X
    facade((bay_x, Zf), (X1, Zf), y_top, y_bottom)  # front right
    facade((X1, Zf), (X1, Zb), y_top, y_bottom)  # ocean side, facing +X
    facade((X1, Zb), (X0, Zb), y_top, y_bottom)  # back, facing -Z
    # The cornice round the main walls, just under the parapet.
    cd, ch = A['cornice_depth'], A['cornice_height']
    for x0, z0, x1, z1 in ((X0 - cd, Zb - cd, X1 + cd, Zb), (X0 - cd, Zf, -bay_x, Zf + cd), (bay_x, Zf, X1 + cd, Zf + cd),
                           (X0 - cd, Zb, X0, Zf), (X1, Zb, X1 + cd, Zf)):
        outline = mc.outward_rect(x0, z0, x1, z1)
        tower.prism(outline, y_top - ch, y_top, 'wall', top=True, v_range=(0.25, 1.0))
        tower.flat(outline, y_top - ch, 'wall', up=False, frac=0.3)

    # ---- Overlays: the glow under each table, contact shade on the floor ----------------------
    for p in LAYOUT['props']:
        if p['kind'] == 'table_glow':
            up_quad(glow, p['X'], p['Z'], p['size'][0] / 2, p['size'][2] / 2, A['glow_lift'], mc.OVERLAY['glow'])
    sw, lift = A['shade_width'], A['shade_lift']
    edge = mc.OVERLAY['edge']
    floor_edges = [
        ((tx0, back), (tx0, front), (1, 0), 0.0),  # city side
        ((tx1, front), (tx1, back), (-1, 0), 0.0),  # ocean side
        ((tx0, back), (-lw, back), (0, 1), 0.0),  # back corners
        ((lw, back), (tx1, back), (0, 1), 0.0),
        ((-lw, back), (lw, back), (0, 1), platform_y),  # the lounge's back wall
        ((tx0, front), (-sx, front), (0, -1), 0.0),  # front
        ((sx, front), (tx1, front), (0, -1), 0.0),
        ((-lw, platform_front), (-lf, platform_front), (0, 1), 0.0),  # the foot of the riser
        ((lf, platform_front), (lw, platform_front), (0, 1), 0.0),
        ((-lw, back), (-lw, platform_front), (-1, 0), 0.0),  # the riser's ends
        ((lw, back), (lw, platform_front), (1, 0), 0.0),
        ((-lf, lounge_front), (lf, lounge_front), (0, 1), 0.0),  # the flight's foot
    ]
    for a, b, inward, level in floor_edges:
        floor_strip(shade, a, b, inward, sw, level + lift, edge)
    blob = mc.OVERLAY['blob']
    for col in columns:
        hh = col['size'][0] / 2 + A['blob_extra']
        up_quad(shade, col['X'], col['Z'], hh, hh, col['Y'] + lift + 0.002, blob)

    return [parapet, frame, glass, steps, pergola, slats, vines, tower, glow, shade]


# ---------------------------------------------------------------------------------------------
# Blender materials (for renders; the importer's materials are ignored)
# ---------------------------------------------------------------------------------------------

def image_material(name, image_file, alpha=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    tex = nodes.new('ShaderNodeTexImage')
    path = os.path.join(HERE, 'textures', image_file)
    tex.image = bpy.data.images.load(path, check_existing=True)
    links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.8
    if alpha:
        links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
        if hasattr(mat, 'surface_render_method'):
            mat.surface_render_method = 'BLENDED'
    return mat


def flat_material(name, hex_colour, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    col = mc.rgb(hex_colour)
    bsdf.inputs['Base Color'].default_value = tuple(mc.srgb_to_linear(c) for c in col) + (1.0,)
    bsdf.inputs['Roughness'].default_value = 0.35
    if alpha < 1.0:
        bsdf.inputs['Alpha'].default_value = alpha
        if hasattr(mat, 'surface_render_method'):
            mat.surface_render_method = 'BLENDED'
    return mat


# ---------------------------------------------------------------------------------------------
# Render (reference angles), for the Blender checkpoint only
# ---------------------------------------------------------------------------------------------

def render(collection):
    scene = bpy.context.scene
    try:
        scene.render.engine = 'BLENDER_EEVEE'
    except TypeError:
        scene.render.engine = 'CYCLES'
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    if hasattr(scene, 'eevee'):
        scene.eevee.taa_render_samples = 32
    # The floor (the MaterialVariant's image, 9 studs a repeat) and the tables, render only.
    floor_mat = image_material('FloorPreview', 'floor_color.png')
    extra = bpy.data.collections.new('RenderOnly')
    scene.collection.children.link(extra)
    for zone in ('terrace', 'lounge', 'lower_landing'):
        x0, z0, x1, z1 = Z[zone]
        y = H['lounge'] if zone == 'lounge' else (H['lower_landing'] if zone == 'lower_landing' else 0.0)
        m = mc.Mesh('Floor_' + zone)
        pts = [(x0, y, z1), (x1, y, z1), (x1, y, z0), (x0, y, z0)]
        m.face(pts, [(x0 / 9, -z1 / 9), (x1 / 9, -z1 / 9), (x1 / 9, -z0 / 9), (x0 / 9, -z0 / 9)])
        mc.to_object(m, extra, floor_mat)
    table_fbx = os.path.join(HERE, '..', 'table', 'PoolTable.fbx')
    if os.path.exists(table_fbx):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=table_fbx)
        parts = [o for o in bpy.data.objects if o not in before]
        for o in parts:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            extra.objects.link(o)
        cloth = flat_material('ClothPreview', '#28AF2D')
        wood = flat_material('WoodPreview', '#7A3A22')
        for o in parts:
            o.data.materials.clear()
            o.data.materials.append(cloth if 'Cloth' in o.name else wood)
        for t in LAYOUT['tables']:
            for o in parts:
                dup = o.copy()
                extra.objects.link(dup)
                dup.location = mc.rb((t['X'], 0.0, t['Z']))
        for o in parts:
            o.hide_render = True
    # Sun: the Spec's Day sun (latitude 45, clock 10), a sky-coloured world.
    sun_dir = Vector(mc.rb((0.465, 0.806, 0.367))).normalized()
    light = bpy.data.lights.new('Sun', 'SUN')
    light.energy = 4.0
    light.angle = math.radians(1.5)
    sun = bpy.data.objects.new('Sun', light)
    extra.objects.link(sun)
    sun.rotation_euler = sun_dir.to_track_quat('Z', 'Y').to_euler()
    world = scene.world or bpy.data.worlds.new('World')
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    sky = mc.rgb(mc.hexc('sky_horizon_day'))
    bg.inputs['Color'].default_value = tuple(mc.srgb_to_linear(c) for c in sky) + (1.0,)
    bg.inputs['Strength'].default_value = 0.8
    out_dir = os.path.join(HERE, 'checkpoints', 'blender')
    os.makedirs(out_dir, exist_ok=True)
    cams = LAYOUT['cameras']
    for view in ('entrance', 'high-day', 'lounge-back', 'day-view'):
        c = cams[view]
        cam_data = bpy.data.cameras.new('Cam_' + view)
        cam_data.sensor_fit = 'VERTICAL'
        cam_data.angle_y = math.radians(c['fov'])
        cam_data.clip_end = 5000
        cam = bpy.data.objects.new('Cam_' + view, cam_data)
        extra.objects.link(cam)
        pos, look = Vector(mc.rb(c['pos'])), Vector(mc.rb(c['look']))
        cam.location = pos
        cam.rotation_euler = (look - pos).to_track_quat('-Z', 'Y').to_euler()
        scene.camera = cam
        scene.render.filepath = os.path.join(out_dir, 'stage2-%s.png' % view)
        bpy.ops.render.render(write_still=True)
        print('rendered', scene.render.filepath)


# ---------------------------------------------------------------------------------------------

def main():
    render_views = '--' in sys.argv and 'render' in sys.argv[sys.argv.index('--') + 1:]
    scene = mc.clear_scene()
    collection = bpy.data.collections.new('Rooftop')
    scene.collection.children.link(collection)
    arch = image_material('Arch', 'arch_color.png')
    foliage = image_material('Foliage', 'foliage.png', alpha=True)
    overlays = image_material('Overlays', 'overlays.png', alpha=True)
    materials = {
        'Parapet': arch, 'Steps': arch, 'Pergola': arch, 'PergolaSlats': arch, 'TowerTop': arch,
        'RailingFrame': flat_material('Frame', '#1B1B22'),
        'RailingGlass': flat_material('Glass', mc.ALBEDO['glass'], alpha=0.3),
        'Vines': foliage, 'TableGlow': overlays, 'FloorShade': overlays,
    }
    meshes = geometry() + mc.anchor_meshes()
    objects = []
    report = []
    total = 0
    for m in meshes:
        obj = mc.to_object(m, collection, materials.get(m.name, arch))
        tris = obj['triangle_count']
        total += tris
        report.append('%-13s %6d triangles' % (m.name, tris))
        assert tris <= TRIANGLE_CAP_MESH, (m.name, tris, 'over the per-mesh cap')
        objects.append(obj)
    assert total <= TRIANGLE_CAP_TOTAL, ('architecture over its cap', total)
    # The anchors are where MapBuilder expects them.
    for name, want in (('AnchorO', (0, 0, 0)), ('AnchorX', (10, 0, 0)), ('AnchorZ', (0, 0, 10))):
        obj = bpy.data.objects[name]
        centre = sum((v.co for v in obj.data.vertices), Vector()) / len(obj.data.vertices)
        got = (centre.x, centre.z, -centre.y)
        assert max(abs(a - b) for a, b in zip(got, want)) < 1e-6, (name, got)
    fbx = os.path.join(HERE, 'fbx', 'Rooftop.fbx')
    mc.export_fbx(fbx, objects)
    worst = mc.roundtrip_check(fbx, objects)
    report.append('total         %6d triangles (cap %d); FBX round trip within %.2g studs' % (total, TRIANGLE_CAP_TOTAL, worst))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'Map.blend'), check_existing=False, compress=True)
    backup = os.path.join(HERE, 'Map.blend1')
    if os.path.exists(backup):
        os.remove(backup)
    with open(os.path.join(HERE, 'checkpoints', 'rooftop_triangles.txt'), 'w') as handle:
        handle.write('\n'.join(report) + '\n')
    print('\n'.join(report))
    if render_views:
        render(collection)


main()
