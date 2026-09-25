"""Skyline Club: the hub map builder (brief: docs/prompts/HUB_BLENDER_PROMPT.md).

One idempotent script, run in stages. Every stage rebuilds only what it owns, so running a stage
twice gives the same scene.

Through the Blender MCP (execute_blender_code):

    p = '/path/to/repo/assets/hub/HubBuilder.py'
    exec(compile(open(p).read(), p, 'exec'), {'__file__': p, '__name__': '__main__',
                                               'HUB_ARGS': ['blockout', 'audit', 'save']})

Headless (from the repo root, B=/Applications/Blender.app/Contents/MacOS/Blender):

    $B -b --factory-startup --python-exit-code 1 --python assets/hub/HubBuilder.py -- blockout audit
    $B -b assets/hub/Hub.blend --factory-startup --python-exit-code 1 \
        --python assets/hub/HubBuilder.py -- render1

Stages written so far:
    blockout  stage 1: shell, windows, zones, balcony, stair, walkways, 16 table instances
    audit     stage 1: clearance, join pads, heights and walk distances -> layout_audit.md
    render1   stage 1: labelled plan, spawn view, 1v1 eye level, north windows, overview
    save      save assets/hub/Hub.blend (texture paths made relative)

Frame: 1 Blender unit = 1 stud, Z up, X east, Y north, main floor Z = 0. Table instances use the
table package's frame: origin at the table centre on the floor, length along local X, head at -X.
"""

import heapq
import json
import math
import os
import sys

import bpy

try:
    HERE = os.path.dirname(os.path.abspath(__file__))
except NameError:  # exec'd without __file__
    HERE = os.path.join(os.getcwd(), 'assets', 'hub')
REPO = os.path.dirname(os.path.dirname(HERE))
HUB_BLEND = os.path.join(HERE, 'Hub.blend')
TABLE_BLEND = os.path.join(REPO, 'assets', 'table', 'TableModel.blend')
TABLE_TEX = os.path.join(REPO, 'assets', 'table', 'textures')
RENDER_DIR = os.path.join(HERE, 'renders')
AUDIT_MD = os.path.join(HERE, 'layout_audit.md')

# =================================================================================================
# PARAMETERS: every tunable number. Positions are studs in the hub frame above.
# =================================================================================================
PARAMETERS = {
    # Interior faces of the outer walls. The brief allows "about 170 x 150".
    'room': {'x0': -85.5, 'x1': 86.0, 'y0': -75.0, 'y1': 76.5,
             'ceiling': 26.0,  # main hall ceiling height (brief: 26, tune)
             'wall': 1.0,  # outer wall thickness
             'slab': 1.0},  # floor and roof slab thickness
    # The finished table (assets/table): 9 ft Pro-Am at 0.16 stud per inch, cloth at 2.9.
    'table': {'length': 18.24, 'width': 10.24, 'cloth_z': 2.9, 'top_z': 3.3},
    'ZONE_TABLES': {'1v1': 10, '2v2': 4, '3v3': 2},
    # Table grids. axis: which way the long side runs. west_rail/south_rail: outer edge of the
    # first column/row. Gaps are rail to rail. heads: the head end of each table (its join pad
    # sits 14 studs from the centre that way), per row (south first) or per column (west first).
    'zones': {
        '1v1': {'axis': 'NS', 'cols': 5, 'rows': 2, 'west_rail': -72.3, 'south_rail': 10.36,
                'col_gap': 10.0, 'row_gap': 16.0, 'heads': {'row': ['S', 'S']},
                'clearance': 10.0, 'first': 1},
        '2v2': {'axis': 'EW', 'cols': 2, 'rows': 2, 'west_rail': -72.3, 'south_rail': -53.0,
                'col_gap': 10.0, 'row_gap': 10.0, 'heads': {'col': ['W', 'E']},
                'clearance': 10.0, 'first': 11},
        # west_rail None: derived from the 1v1/3v3 partition (1v1 clearance + partition + 12)
        '3v3': {'axis': 'NS', 'cols': 2, 'rows': 1, 'west_rail': None, 'south_rail': 20.88,
                'col_gap': 12.0, 'row_gap': 0.0, 'heads': {'row': ['S']},
                'clearance': 12.0, 'first': 15},
    },
    'pad': {'size': 6.0, 'offset': 14.0},  # join pad: square, centre this far from table centre
    'seat_depth': 3.0,  # blockout seat bands (armchair depth)
    'seat_margin': 0.2,  # seats sit this far outside a table's clearance
    'partition': {'t': 0.4, 'h': 9.0, 'opening_pad': 4.0},  # glass partitions
    'window': {'sill': 0.6, 'head': 23.0, 'mullion_every': 8.5, 'mullion_w': 0.5, 'glass_t': 0.2},
    'balcony': {'z': 11.2, 'depth': 12.0, 'slab': 1.0, 'rail_h': 3.5, 'rail_t': 0.5,
                'prow_depth': 8.0,  # spawn landing that juts out over the plaza
                'prow_east_margin': 2.82,  # prow beyond the stair seats
                'column': 1.0, 'lounge_columns_x': [40.4, 63.0]},
    'stair': {'steps': 14, 'rise': 0.8, 'run': 1.6, 'width': 16.0},
    'stair_seats': {'tiers': 7, 'rise': 1.6, 'run': 3.2, 'width': 10.0},
    'bar': {'counter': [20.0, 23.0, -35.0, -15.0], 'counter_h': 3.6,
            'back': [27.0, 28.0, -38.0, -13.0], 'back_h': 13.0,
            'screens_y': [-31.0, -24.0, -17.0], 'screen_w': 6.0, 'screen_z': [7.5, 11.0],
            'stand_x': 18.2},  # where a player stands at the bar (walk target)
    'cue_room': {'x1': 40.6, 'door': [35.0, 39.0]},  # runs from the stair core to x1, under the balcony
    'kiosks': {'Kiosk_Shop': [22.5, -48.0], 'Kiosk_Trade': [31.5, -48.0], 'size': [3.0, 2.0, 5.0]},
    'podium': {'x': [2.5, 6.0, 9.5], 'h': [1.4, 2.0, 1.0], 'y': -14.5, 'size': 3.0},  # top-3 statues
    'bench': [15.5, 26.0],  # walkway-edge bench by the bar (x range)
    'featured_screen': {'w': 18.7, 'z': [15.0, 25.5]},  # on the south wall above the balcony, over the stair
    'piano_stage': {'centre': [75.0, -26.0], 'diameter': 14.0, 'height': 0.8, 'step': 1.0},
    'terrace': {'depth': 28.0, 'y': [-66.0, -20.0], 'door_y': [-52.0, -38.0], 'rail_h': 3.5,
                'col_h': 12.0},
    'pro_door': {'w': 8.0, 'h': 16.0, 'frame': 0.6, 'panel': 12.0},
    'avatar': {'height': 5.0, 'radius': 2.0, 'eye': 4.5, 'walk_speed': 16.0},
    'walk_limit': 128.0,  # 8 s at 16 studs/s from the foot of the spawn stair
    'grid': 0.5,  # walk-audit grid
    'min_clear_over_tables': 20.0,
    'min_clear_walk_under': 10.0,
    'palette': {
        'cloud_white': '#EEF1F6', 'soft_sky': '#B9C7DC', 'warm_marble': '#F4F0E8',
        'carpet_gray': '#5E636B', 'carpet_streak': '#B9BDC4', 'sunny_yellow': '#FFD23F',
        'midnight_navy': '#19213A', 'cobalt': '#2563FF', 'sunflower': '#FFC531',
        'tangerine': '#FF7A1A', 'coral': '#FF4F5E', 'glossy_white': '#FFFFFF',
        'emerald': '#1F8F55', '1v1': '#FFB000', '2v2': '#00C2A8', '3v3': '#8A4DFF',
        'gold': '#F0B429', 'warm_led': '#FFF3D6', 'cloth_green': '#28AF2D',
        'terrace_tile': '#E9C9A3', 'slab': '#3A3F48', 'glass': '#BFE3F5', 'ink': '#101418',
    },
    'table_look': {'tint': [40, 175, 45], 'wood': 'Cherry'},  # the package's green look
    'render': {'size': [1600, 900], 'plan_size': [2400, 1880], 'samples': 32, 'fov_v': 70.0},
}

P = PARAMETERS
ROOT = 'HUB'
SUBS = ['HUB_Shell', 'HUB_Ceiling', 'HUB_Balcony', 'HUB_Circulation', 'HUB_Zones', 'HUB_Fixtures',
        'HUB_Terrace', 'HUB_Collision', 'HUB_Tables', 'HUB_Markers', 'HUB_Plan', 'HUB_Cameras',
        'HUB_Lights']
HEAD_YAW = {'W': 0.0, 'E': 180.0, 'N': -90.0, 'S': 90.0}  # table local -X (head) -> world direction
HEAD_DIR = {'W': (-1.0, 0.0), 'E': (1.0, 0.0), 'N': (0.0, 1.0), 'S': (0.0, -1.0)}


# =================================================================================================
# Layout: every position the builder and the audit use, derived from PARAMETERS
# =================================================================================================
def layout():
    r, t = P['room'], P['table']
    L = {'room': r}
    tables = []
    zone_boxes = {}
    part_t = P['partition']['t']
    # 1v1 first: the 3v3 grid hangs off its east clearance
    order = ['1v1', '2v2', '3v3']
    east_rail = {}
    for zone in order:
        z = dict(P['zones'][zone])
        if zone == '3v3' and z['west_rail'] is None:
            L['x_part_13'] = east_rail['1v1'] + P['zones']['1v1']['clearance']  # partition west face
            z['west_rail'] = L['x_part_13'] + part_t + z['clearance']
        assert z['cols'] * z['rows'] == P['ZONE_TABLES'][zone], zone
        fx, fy = (t['width'], t['length']) if z['axis'] == 'NS' else (t['length'], t['width'])
        n = z['first']
        for row in range(z['rows']):
            for col in range(z['cols']):
                x0 = z['west_rail'] + col * (fx + z['col_gap'])
                y0 = z['south_rail'] + row * (fy + z['row_gap'])
                cx, cy = x0 + fx / 2, y0 + fy / 2
                head = z['heads']['row'][row] if 'row' in z['heads'] else z['heads']['col'][col]
                assert (head in 'NS') == (z['axis'] == 'NS'), (zone, head)
                dx, dy = HEAD_DIR[head]
                px, py = cx + dx * P['pad']['offset'], cy + dy * P['pad']['offset']
                h = P['pad']['size'] / 2
                tables.append({'n': n, 'zone': zone, 'x': cx, 'y': cy, 'head': head,
                               'yaw': HEAD_YAW[head], 'rect': (x0, y0, x0 + fx, y0 + fy),
                               'pad': (px, py), 'pad_rect': (px - h, py - h, px + h, py + h),
                               'clearance': z['clearance'], 'col': col, 'row': row})
                n += 1
        zt = [tb for tb in tables if tb['zone'] == zone]
        zone_boxes[zone] = (min(tb['rect'][0] for tb in zt), min(tb['rect'][1] for tb in zt),
                            max(tb['rect'][2] for tb in zt), max(tb['rect'][3] for tb in zt))
        east_rail[zone] = zone_boxes[zone][2]
    L['tables'], L['zone_boxes'] = tables, zone_boxes
    z1, z2, z3 = zone_boxes['1v1'], zone_boxes['2v2'], zone_boxes['3v3']
    c2 = P['zones']['2v2']['clearance']
    # Main walkway: from the 2v2 north partition to the 1v1 join pads
    L['y_part_2n'] = z2[3] + c2  # 2v2 north partition, south face
    L['walk_s'] = L['y_part_2n'] + part_t
    L['walk_n'] = z1[1] - P['pad']['offset'] + t['length'] / 2 - P['pad']['size'] / 2  # 1v1 pad south edge
    L['y_part_3s'] = L['walk_n']  # 3v3 south partition sits on the same line
    # 2v2 east edge: clearance, seat band, glass
    L['x_2v2_seat'] = z2[2] + c2 + P['seat_margin']
    L['x_part_2e'] = z2[2] + c2 + P['seat_margin'] + P['seat_depth']  # partition west face
    # Stair, stair seats and prow sit against the 2v2 east glass
    s, ss, b = P['stair'], P['stair_seats'], P['balcony']
    L['balcony_front'] = r['y0'] + b['depth']
    L['prow_front'] = L['balcony_front'] + b['prow_depth']
    L['stair_x'] = (L['x_part_2e'] + part_t, L['x_part_2e'] + part_t + s['width'])
    L['seats_x'] = (L['stair_x'][1], L['stair_x'][1] + ss['width'])
    L['prow_x'] = (L['stair_x'][0], L['seats_x'][1] + b['prow_east_margin'])
    L['stair_top_y'] = L['prow_front']
    L['stair_foot_y'] = L['prow_front'] + s['steps'] * s['run']
    assert abs(ss['tiers'] * ss['run'] - s['steps'] * s['run']) < 1e-6
    assert abs(s['steps'] * s['rise'] - b['z']) < 1e-6 and abs(ss['tiers'] * ss['rise'] - b['z']) < 1e-6
    L['stair_foot'] = ((L['stair_x'][0] + L['stair_x'][1]) / 2, L['stair_foot_y'])
    L['spawn'] = ((L['prow_x'][0] + L['prow_x'][1]) / 2, L['balcony_front'] + b['prow_depth'] / 2, b['z'])
    L['cue_x'] = (L['prow_x'][1], P['cue_room']['x1'])
    # 2v2 north partition: one glass run over each column (rails +1), openings between
    segs = []
    for col in range(P['zones']['2v2']['cols']):
        tc = [tb for tb in tables if tb['zone'] == '2v2' and tb['col'] == col]
        segs.append((min(tb['rect'][0] for tb in tc) - 1.0, max(tb['rect'][2] for tb in tc) + 1.0))
    # the last run carries on to the east glass: the east pads are reached from the plaza, and the
    # gallery seats along it face the middle 1v1 tables
    segs[-1] = (segs[-1][0], L['x_part_2e'] + part_t)
    L['part_2n_segs'] = segs
    # 2v2 east partition: opening facing the plaza, north of the stair foot
    L['part_2e_segs'] = [(r['y0'] + b['depth'], L['stair_foot_y'] + 1.0), (-22.0, L['y_part_2n'])]
    # 3v3 south partition: openings in front of each join pad
    op = P['partition']['opening_pad']
    x_start = L['x_part_13'] + part_t
    t3 = sorted([tb for tb in tables if tb['zone'] == '3v3'], key=lambda tb: tb['x'])
    segs, cur = [], x_start
    for tb in t3:
        segs.append((cur, tb['pad'][0] - op))
        cur = tb['pad'][0] + op
    segs.append((cur, r['x1']))
    L['part_3s_segs'] = segs
    return L


# =================================================================================================
# Blender helpers
# =================================================================================================
def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h):
    h = P['palette'].get(h, h).lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def lin(h):
    return tuple(srgb_to_linear(c) for c in hex_rgb(h))


def socket(sockets, identifier, fallback_name):
    for s in sockets:
        if s.identifier == identifier:
            return s
    return sockets[fallback_name]


def material(name, colour, rough=0.6, metal=0.0, alpha=1.0, emit=0.0):
    """Blockout material: flat colour. diffuse_color drives the Workbench plan."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
    out = next((n for n in nodes if n.type == 'OUTPUT_MATERIAL'), None)
    if bsdf is None or out is None:
        nodes.clear()
        bsdf = nodes.new('ShaderNodeBsdfPrincipled')
        out = nodes.new('ShaderNodeOutputMaterial')
        links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    c = lin(colour)
    bsdf.inputs['Base Color'].default_value = (*c, 1.0)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Alpha'].default_value = alpha
    bsdf.inputs['Emission Color'].default_value = (*c, 1.0)
    bsdf.inputs['Emission Strength'].default_value = emit
    mat.diffuse_color = (*c, alpha)
    if alpha < 1.0:
        try:
            mat.surface_render_method = 'BLENDED'
        except (AttributeError, TypeError):
            pass
    return mat


def collection(name, parent=None):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
    parent = parent or bpy.context.scene.collection
    if coll.name not in parent.children:
        parent.children.link(coll)
    return coll


def clear_collection(coll):
    for child in list(coll.children):
        clear_collection(child)
        bpy.data.collections.remove(child)
    for obj in list(coll.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def mesh_object(name, verts, faces, mat, coll):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    if mat is not None:
        me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    coll.objects.link(obj)
    return obj


def box(name, x0, y0, z0, x1, y1, z1, mat, coll, floor=False, block=None, kind=None, **props):
    """Axis-aligned box. floor=True marks it as something standing on the main floor (clearance
    audit); block (default = floor) marks it as blocking the walk audit."""
    x0, x1 = min(x0, x1), max(x0, x1)
    y0, y1 = min(y0, y1), max(y0, y1)
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    obj = mesh_object(name, v, f, mat, coll)
    tag(obj, floor, block, kind, **props)
    return obj


def quad(name, x0, y0, x1, y1, z, mat, coll):
    v = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
    return mesh_object(name, v, [(0, 1, 2, 3)], mat, coll)


def cylinder(name, cx, cy, radius, z0, z1, mat, coll, segments=32, floor=False, kind=None):
    v, f = [], []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        v.append((cx + radius * math.cos(a), cy + radius * math.sin(a), z0))
        v.append((cx + radius * math.cos(a), cy + radius * math.sin(a), z1))
    for i in range(segments):
        j = (i + 1) % segments
        f.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
    f.append(tuple(2 * i for i in reversed(range(segments))))
    f.append(tuple(2 * i + 1 for i in range(segments)))
    obj = mesh_object(name, v, f, mat, coll)
    tag(obj, floor, None, kind)
    return obj


def tag(obj, floor, block, kind, **props):
    if floor:
        obj['hub_floor'] = 1
    if block if block is not None else floor:
        obj['hub_block'] = 1
    if kind:
        obj['hub_kind'] = kind
    for k, v in props.items():
        obj[k] = v


def empty(name, loc, coll, rot_z=0.0, size=1.0, display='PLAIN_AXES', **props):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = display
    obj.empty_display_size = size
    obj.location = loc
    obj.rotation_euler = (0.0, 0.0, math.radians(rot_z))
    coll.objects.link(obj)
    for k, v in props.items():
        obj[k] = v
    return obj


def poly_curve(name, points, mat, coll, width=0.12, closed=False, z=0.05):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = width
    sp = cu.splines.new('POLY')
    sp.points.add(len(points) - 1)
    for p, (x, y) in zip(sp.points, points):
        p.co = (x, y, z, 1.0)
    sp.use_cyclic_u = closed
    obj = bpy.data.objects.new(name, cu)
    obj.data.materials.append(mat)
    coll.objects.link(obj)
    return obj


def text(name, body, x, y, size, mat, coll, z=30.0, align='CENTER'):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = body
    cu.size = size
    cu.align_x = align
    cu.align_y = 'CENTER'
    obj = bpy.data.objects.new(name, cu)
    obj.location = (x, y, z)
    obj.data.materials.append(mat)
    coll.objects.link(obj)
    return obj


def hub_scene():
    scene = bpy.context.scene
    if scene.name != 'Hub':
        if 'Hub' in bpy.data.scenes:
            scene = bpy.data.scenes['Hub']
            if bpy.context.window is not None:
                bpy.context.window.scene = scene
        else:
            scene.name = 'Hub'
    # the factory startup objects are not ours
    for name in ('Cube', 'Light', 'Camera'):
        obj = bpy.data.objects.get(name)
        if obj is not None and not obj.get('hub_owned'):
            bpy.data.objects.remove(obj, do_unlink=True)
    scene.unit_settings.system = 'NONE'
    scene.unit_settings.scale_length = 1.0
    return scene


def walk_objects(coll):
    for obj in coll.objects:
        yield obj
    for child in coll.children:
        yield from walk_objects(child)


def world_aabb(obj):
    from mathutils import Vector
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    return (min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts),
            max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))


# =================================================================================================
# The table: appended once from assets/table/TableModel.blend, dressed in the green look
# =================================================================================================
def table_image(name):
    img = bpy.data.images.get(name + '.png')
    if img is None:
        img = bpy.data.images.load(os.path.join(TABLE_TEX, name + '.png'), check_existing=True)
    return img


TABLE_MAPS = {  # mesh -> colour sheet, normal, roughness, metalness, default roughness (TableRender.py)
    'Cloth': ('Cloth_Color', 'Cloth_Normal', 'Cloth_Roughness', None, 0.9),
    'Rails': ('Rails_Color_{wood}', 'Rails_Normal', 'Rails_Roughness', None, 0.4),
    'Body': ('Body_Color_{wood}', 'Body_Normal', 'Body_Roughness', None, 0.4),
    'Pockets': ('Parts_Color', 'Parts_Normal', 'Parts_Roughness', 'Parts_Metalness', 0.6),
    'Caps': ('Parts_Color', 'Parts_Normal', 'Parts_Roughness', 'Parts_Metalness', 0.2),
    'Hardware': ('Parts_Color', 'Parts_Normal', 'Parts_Roughness', 'Parts_Metalness', 0.2),
    'LogoPlate': ('LogoPlate_Color', None, None, None, 0.7),
}
TABLE_FLAT = {'Cloth': '#28AF2D', 'Rails': '#6B3A26', 'Body': '#5A301F', 'Pockets': '#1A1614',
              'Caps': '#C8CACE', 'Hardware': '#C8CACE', 'LogoPlate': '#BEBEBA'}  # Workbench plan colours


def green_look_material(mesh):
    col_name, nrm_name, rgh_name, met_name, rough_default = TABLE_MAPS[mesh]
    col_name = col_name.format(wood=P['table_look']['wood'])
    name = 'HubLook_green_' + mesh
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    out = nodes.new('ShaderNodeOutputMaterial')
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'UVMap'

    def tex(img_name, data):
        node = nodes.new('ShaderNodeTexImage')
        node.image = table_image(img_name)
        node.image.colorspace_settings.name = 'Non-Color' if data else 'sRGB'
        node.extension = 'REPEAT'
        links.new(uv.outputs['UV'], node.inputs['Vector'])
        return node
    colour = tex(col_name, False).outputs['Color']
    if mesh == 'Cloth':  # SurfaceAppearance.Color multiplies the ColorMap
        mix = nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        mix.inputs['Factor'].default_value = 1.0
        links.new(colour, socket(mix.inputs, 'A_Color', 'A'))
        tint = [srgb_to_linear(v / 255.0) for v in P['table_look']['tint']]
        socket(mix.inputs, 'B_Color', 'B').default_value = (*tint, 1.0)
        colour = socket(mix.outputs, 'Result_Color', 'Result')
    links.new(colour, bsdf.inputs['Base Color'])
    if nrm_name:
        nm = nodes.new('ShaderNodeNormalMap')
        nm.uv_map = 'UVMap'
        links.new(tex(nrm_name, True).outputs['Color'], nm.inputs['Color'])
        links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    if rgh_name:
        links.new(tex(rgh_name, True).outputs['Color'], bsdf.inputs['Roughness'])
    else:
        bsdf.inputs['Roughness'].default_value = rough_default
    if met_name:
        links.new(tex(met_name, True).outputs['Color'], bsdf.inputs['Metallic'])
    mat.diffuse_color = (*lin(TABLE_FLAT[mesh]), 1.0)
    return mat


def pool_table_collection():
    """The appended table (never edited or exported by the hub; only re-dressed for renders)."""
    lib = collection('HUB_Lib')
    for child in lib.children:
        if child.get('hub_table'):
            return child
    with bpy.data.libraries.load(TABLE_BLEND, link=False) as (src, dst):
        assert 'PoolTable' in src.collections, src.collections
        dst.collections = ['PoolTable']
    coll = dst.collections[0]
    coll['hub_table'] = 1
    lib.children.link(coll)
    for obj in list(coll.objects):
        if obj.name.startswith('Marks'):  # Config.TableModel.Marks = false: clean cloth
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        base = obj.name.split('.')[0]
        obj.data.materials.clear()
        obj.data.materials.append(green_look_material(base))
    # keep the library out of the view layer; the 16 instances still render
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.collection == lib:
            lc.exclude = True
    return coll


# =================================================================================================
# Stage 1: blockout
# =================================================================================================
def stage_blockout():
    scene = hub_scene()
    L = layout()
    r, b, pal = P['room'], P['balcony'], P['palette']
    x0, x1, y0, y1, H = r['x0'], r['x1'], r['y0'], r['y1'], r['ceiling']
    w = r['wall']
    root = collection(ROOT)
    colls = {}
    for name in SUBS:
        colls[name] = collection(name, root)
        clear_collection(colls[name])
    bpy.data.orphans_purge(do_recursive=True)
    table_coll = pool_table_collection()

    M = {
        'wall': material('BO_Wall', 'cloud_white', 0.7),
        'accent': material('BO_AccentWall', 'soft_sky', 0.7),
        'yellow': material('BO_Yellow', 'sunny_yellow', 0.6),
        'navy': material('BO_Navy', 'midnight_navy', 0.3),
        'marble': material('BO_Marble', 'warm_marble', 0.15),
        'carpet': material('BO_Carpet', 'carpet_gray', 0.9),
        'slab': material('BO_Slab', 'slab', 0.9),
        'glass': material('BO_Glass', 'glass', 0.05, alpha=0.18),
        'frame': material('BO_Frame', 'midnight_navy', 0.35),
        'gold': material('BO_Gold', 'gold', 0.25, metal=1.0),
        'white': material('BO_GlossyWhite', 'glossy_white', 0.2),
        'screen': material('BO_Screen', '#0B0E16', 0.08),
        'tile': material('BO_TerraceTile', 'terrace_tile', 0.7),
        'cobalt': material('BO_Cobalt', 'cobalt', 0.8),
        'tangerine': material('BO_Tangerine', 'tangerine', 0.7),
        'coral': material('BO_Coral', 'coral', 0.7),
        'sunflower': material('BO_Sunflower', 'sunflower', 0.7),
        'col': material('BO_Collision', '#FF00FF', 1.0, alpha=0.25),
        'prodoor': material('BO_ProDoorGlow', 'gold', 0.3, emit=3.0),
    }
    for zone in ('1v1', '2v2', '3v3'):
        M[zone] = material('BO_Zone_' + zone, zone, 0.75)
        M['pad_' + zone] = material('BO_Pad_' + zone, zone, 0.5, alpha=0.75)

    C = colls
    sh = C['HUB_Shell']
    # ---- floor slab, ceiling, outer walls ------------------------------------------------------
    box('BO_FloorSlab', x0 - w, y0 - w, -r['slab'], x1 + w, y1 + w, 0.0, M['slab'], sh)
    box('BO_Roof', x0 - w, y0 - w, H, x1 + w, y1 + w, H + r['slab'], M['wall'], C['HUB_Ceiling'])
    box('BO_Wall_S', x0 - w, y0 - w, 0.0, x1 + w, y0, H, M['wall'], sh, floor=True, kind='wall')
    box('BO_WallBand_S', x0, y0, 20.0, x1, y0 + 0.05, 24.0, M['yellow'], sh)  # the high yellow band
    win = P['window']

    def window_run(name, horizontal, fixed, a0, a1, inward):
        """A full-height window wall between a0 and a1 along X (horizontal) or Y, interior face at
        `fixed`, the wall thickness going outward (inward = -1 or +1 is the room side)."""
        o0, o1 = (fixed, fixed - inward * w)

        def bx(n, s0, s1, z0, z1, mat, t0=None, t1=None):
            t0 = o0 if t0 is None else t0
            t1 = o1 if t1 is None else t1
            if horizontal:
                return box(n, s0, t0, z0, s1, t1, z1, mat, sh, floor=True, kind='wall')
            return box(n, t0, s0, z0, t1, s1, z1, mat, sh, floor=True, kind='wall')
        bx(name + '_Curb', a0, a1, 0.0, win['sill'], M['frame'])
        bx(name + '_Head', a0, a1, win['head'], H, M['wall'])
        gm = fixed - inward * w / 2
        bx(name + '_Glass', a0, a1, win['sill'], win['head'], M['glass'],
           gm - win['glass_t'] / 2, gm + win['glass_t'] / 2)
        n = max(1, int(round((a1 - a0) / win['mullion_every'])))
        for i in range(n + 1):
            s = a0 + (a1 - a0) * i / n
            s0 = max(a0, s - win['mullion_w'] / 2)
            s1 = min(a1, s + win['mullion_w'] / 2)
            bx('%s_Mullion_%02d' % (name, i), s0, s1, win['sill'], win['head'], M['frame'])

    window_run('BO_Window_N', True, y1, x0 - w, x1 + w, -1)
    ty, dy = P['terrace']['y'], P['terrace']['door_y']
    window_run('BO_Window_E1', False, x1, y0 - w, dy[0], -1)
    window_run('BO_Window_E2', False, x1, dy[1], y1 + w, -1)
    # terrace doors: an opening with a frame (the doors slide open; glass leaves come in stage 2)
    box('BO_TerraceDoor_Head', x1, dy[0], 12.0, x1 + w, dy[1], H, M['wall'], sh)
    for i, yy in enumerate(dy):
        box('BO_TerraceDoor_Jamb_%d' % i, x1, yy - 0.4, 0.0, x1 + w, yy + 0.4, 12.0, M['frame'], sh)
    pd = P['pro_door']
    walk_c = (L['walk_s'] + L['walk_n']) / 2
    window_run('BO_Window_W1', False, x0, y0 - w, walk_c - pd['panel'] / 2, 1)
    window_run('BO_Window_W2', False, x0, walk_c + pd['panel'] / 2, y1 + w, 1)
    # the pro lobby door: solid panel, locked door, glowing frame, blank sign above
    fx = C['HUB_Fixtures']
    box('BO_ProDoor_Wall', x0 - w, walk_c - pd['panel'] / 2, 0.0, x0, walk_c + pd['panel'] / 2, H,
        M['accent'], sh, floor=True, kind='wall')
    box('BO_ProDoor_Leaf', x0 - 0.2, walk_c - pd['w'] / 2, 0.0, x0 + 0.1, walk_c + pd['w'] / 2, pd['h'],
        M['navy'], fx)
    fr = pd['frame']
    for side, (ya, yb) in (('S', (walk_c - pd['w'] / 2 - fr, walk_c - pd['w'] / 2)),
                           ('N', (walk_c + pd['w'] / 2, walk_c + pd['w'] / 2 + fr))):
        box('Emissive_ProDoor_' + side, x0, ya, 0.0, x0 + 0.3, yb, pd['h'] + fr, M['prodoor'], fx)
    box('Emissive_ProDoor_Head', x0, walk_c - pd['w'] / 2 - fr, pd['h'], x0 + 0.3,
        walk_c + pd['w'] / 2 + fr, pd['h'] + fr, M['prodoor'], fx)
    box('Sign_Logo_ProDoor', x0, walk_c - pd['w'] / 2, pd['h'] + 1.5, x0 + 0.2, walk_c + pd['w'] / 2,
        pd['h'] + 4.5, M['white'], fx)

    # ---- floors: marble where people walk, carpet where people play ---------------------------
    zn = C['HUB_Zones']
    z1b, z2b, z3b = L['zone_boxes']['1v1'], L['zone_boxes']['2v2'], L['zone_boxes']['3v3']
    xp13 = L['x_part_13']
    pt = P['partition']['t']
    quad('BO_Marble_Walkway', x0, L['y_part_2n'], x1, L['walk_n'], 0.01, M['marble'], zn)
    quad('BO_Marble_PlazaLounge', L['stair_x'][0], y0, x1, L['y_part_2n'], 0.01, M['marble'], zn)
    quad('BO_Carpet_1v1', x0, L['walk_n'], xp13 + pt, y1, 0.01, M['carpet'], zn)
    quad('BO_Carpet_2v2', x0, y0, L['stair_x'][0], L['y_part_2n'], 0.01, M['carpet'], zn)
    quad('BO_Carpet_3v3', xp13 + pt, L['walk_n'], x1, y1, 0.01, M['carpet'], zn)
    # zone inlay stripes (the carpet stripe in each zone colour, along the zone front)
    quad('BO_Stripe_1v1', x0, L['walk_n'] + 0.2, xp13, L['walk_n'] + 1.0, 0.02, M['1v1'], zn)
    quad('BO_Stripe_2v2', x0, L['y_part_2n'] - 1.0, L['x_part_2e'], L['y_part_2n'] - 0.2, 0.02, M['2v2'], zn)
    quad('BO_Stripe_3v3', xp13 + pt, L['walk_n'] + pt + 0.2, x1, L['walk_n'] + pt + 1.0, 0.02, M['3v3'], zn)

    # ---- glass partitions (black frames come in stage 2) ---------------------------------------
    ph = P['partition']['h']
    for i, (a, bb) in enumerate(L['part_2n_segs']):
        box('BO_Glass_2v2N_%d' % i, a, L['y_part_2n'], 0.0, bb, L['y_part_2n'] + pt, ph, M['glass'], zn,
            floor=True, kind='partition')
    for i, (a, bb) in enumerate(L['part_2e_segs']):
        box('BO_Glass_2v2E_%d' % i, L['x_part_2e'], a, 0.0, L['x_part_2e'] + pt, bb, ph, M['glass'], zn,
            floor=True, kind='partition')
    box('BO_Glass_1v1_3v3', xp13, L['walk_n'], 0.0, xp13 + pt, y1, ph, M['glass'], zn,
        floor=True, kind='partition')
    for i, (a, bb) in enumerate(L['part_3s_segs']):
        box('BO_Glass_3v3S_%d' % i, a, L['y_part_3s'], 0.0, bb, L['y_part_3s'] + pt, ph, M['glass'], zn,
            floor=True, kind='partition')

    # ---- seat bands (blockout proxies for armchairs, sofas and benches) ------------------------
    sd, sm = P['seat_depth'], P['seat_margin']
    c1 = P['zones']['1v1']['clearance']
    c2 = P['zones']['2v2']['clearance']
    c3 = P['zones']['3v3']['clearance']

    def seats(name, xa, ya, xb, yb, mat, zone, height=3.0):
        return box('BO_Seats_' + name, xa, ya, 0.0, xb, yb, height, mat, zn, floor=True,
                   kind='seat', zone=zone)
    seats('1v1_WestWindow', x0, z1b[1], x0 + sd, z1b[3], M['1v1'], '1v1')
    seats('1v1_NorthWindow', x0 + sd, y1 - sd, z1b[2], y1, M['1v1'], '1v1')
    for i, (a, bb) in enumerate(L['part_2n_segs']):
        seats('1v1_Gallery_%d' % i, a, L['walk_s'], bb, L['walk_s'] + sd, M['1v1'], '1v1')
    bx0, bx1 = P['bench']
    seats('1v1_BarBench', bx0, L['walk_s'], bx1, L['walk_s'] + 2.5, M['1v1'], '1v1')
    seats('2v2_WestWindow', x0, z2b[1], x0 + sd, z2b[3], M['2v2'], '2v2')
    col_x = (z2b[0] + z2b[2]) / 2  # the balcony column sits in the 2v2 column gap
    gap_mid = None
    t2 = [tb for tb in L['tables'] if tb['zone'] == '2v2' and tb['row'] == 0]
    if len(t2) == 2:
        gap_mid = (t2[0]['rect'][2] + t2[1]['rect'][0]) / 2
        col_x = gap_mid
    ub0, ub1 = z2b[1] - c2 - sm - sd, z2b[1] - c2 - sm
    seats('2v2_UnderBalcony_W', x0 + sd, ub0, col_x - 1.0, ub1, M['2v2'], '2v2')
    seats('2v2_UnderBalcony_E', col_x + 1.0, ub0, L['x_2v2_seat'], ub1, M['2v2'], '2v2')
    seats('2v2_EastGlass', L['x_2v2_seat'], z2b[1], L['x_part_2e'], L['part_2e_segs'][0][1], M['2v2'], '2v2')
    seats('3v3_North', z3b[0] - 4.0, z3b[3] + c3 + sm, z3b[2] + 4.0, z3b[3] + c3 + sm + sd, M['3v3'], '3v3')
    for i, (a, bb) in enumerate(L['part_3s_segs']):
        seats('3v3_South_%d' % i, a + 0.2, L['y_part_3s'] + pt, bb - 0.2, L['y_part_3s'] + pt + sd,
              M['3v3'], '3v3')
    seats('3v3_WindowSofas', xp13 + 3.0, y1 - sd, x1 - 2.0, y1, M['cobalt'], 'lounge')
    bk = P['bar']['back']
    seats('Lounge_BarSofas', bk[1], bk[2] + 2.0, bk[1] + sd, bk[3] - 2.0, M['cobalt'], 'lounge')
    seats('Lounge_Booths', L['cue_x'][1] + 1.5, y0, x1 - 2.0, y0 + 3.5, M['coral'], 'lounge')

    # ---- balcony, prow, railing, columns ---------------------------------------------------------
    bc = C['HUB_Balcony']
    bz, bs = b['z'], b['slab']
    bf, pf = L['balcony_front'], L['prow_front']
    px0, px1 = L['prow_x']
    box('BO_Balcony', x0, y0, bz - bs, x1, bf, bz, M['marble'], bc)
    box('BO_Prow', px0, bf, bz - bs, px1, pf, bz, M['marble'], bc)
    box('BO_BalconyFascia', x0, bf - 0.05, bz - bs, x1, bf, bz, M['white'], bc)
    rt, rh = b['rail_t'], b['rail_h']
    box('BO_Rail_W', x0, bf - rt, bz, px0, bf, bz + rh, M['white'], bc)
    box('BO_Rail_E', px1, bf - rt, bz, x1, bf, bz + rh, M['white'], bc)
    box('BO_Rail_ProwW', px0, bf, bz, px0 + rt, pf, bz + rh, M['white'], bc)
    box('BO_Rail_ProwE', px1 - rt, bf, bz, px1, pf, bz + rh, M['white'], bc)
    box('BO_Rail_ProwN', L['seats_x'][1], pf - rt, bz, px1, pf, bz + rh, M['white'], bc)
    box('BO_Rail_Cap', x0, bf - rt, bz + rh, px0, bf, bz + rh + 0.3, M['gold'], bc)
    box('BO_Rail_CapE', px1, bf - rt, bz + rh, x1, bf, bz + rh + 0.3, M['gold'], bc)
    cz = b['column']
    col_list = [col_x] + list(b['lounge_columns_x'])
    for i, cx in enumerate(col_list):
        box('BO_BalconyColumn_%d' % i, cx - cz / 2, bf - 0.2 - cz, 0.0, cx + cz / 2, bf - 0.2, bz - bs,
            M['gold'], sh, floor=True, kind='column')

    # ---- the spawn stair, stair seats, the core under the prow ---------------------------------
    cc = C['HUB_Circulation']
    st, ss = P['stair'], P['stair_seats']
    sx0, sx1 = L['stair_x']
    foot = L['stair_foot_y']
    for k in range(1, st['steps'] + 1):
        box('BO_Stair_%02d' % k, sx0, foot - k * st['run'], 0.0, sx1, foot - (k - 1) * st['run'],
            k * st['rise'], M['marble'], cc, floor=True, kind='stair')
    tx0, tx1 = L['seats_x']
    for k in range(1, ss['tiers'] + 1):
        box('BO_StairSeat_%d' % k, tx0, foot - k * ss['run'], 0.0, tx1, foot - (k - 1) * ss['run'],
            k * ss['rise'], M['sunflower'] if k % 2 else M['tangerine'], cc, floor=True, kind='stair')
    box('BO_Core', sx0, y0, 0.0, px1, pf, bz - bs, M['wall'], cc, floor=True, kind='core')
    box('BO_CurvedYellowWall', tx1, pf - 0.3, 0.0, px1, pf, bz - bs, M['yellow'], cc)  # curves in stage 2

    # ---- fixtures: bar, screens, kiosks, podium, cue room, piano stage ---------------------------
    bar = P['bar']
    c = bar['counter']
    box('BO_BarCounter', c[0], c[2], 0.0, c[1], c[3], bar['counter_h'], M['white'], fx, floor=True,
        kind='bar')
    box('BO_BarBack', bk[0], bk[2], 0.0, bk[1], bk[3], bar['back_h'], M['navy'], fx, floor=True,
        kind='bar')
    for i, sy in enumerate(bar['screens_y']):
        box('BO_Screen_Leader_%d' % (i + 1), bk[0] - 0.2, sy - bar['screen_w'] / 2, bar['screen_z'][0],
            bk[0], sy + bar['screen_w'] / 2, bar['screen_z'][1], M['screen'], fx)
    fs = P['featured_screen']
    fcx = L['stair_foot'][0]
    box('BO_Screen_Featured', fcx - fs['w'] / 2, y0, fs['z'][0], fcx + fs['w'] / 2, y0 + 0.3, fs['z'][1],
        M['screen'], fx)
    box('BO_Screen_Featured_Frame', fcx - fs['w'] / 2 - 0.5, y0, fs['z'][0] - 0.5, fcx + fs['w'] / 2 + 0.5,
        y0 + 0.2, fs['z'][1] + 0.3, M['white'], fx)
    box('BO_Seats_Balcony_UnderScreen', fcx - fs['w'] / 2, y0, bz, fcx + fs['w'] / 2, y0 + 3.0, bz + 3.0,
        M['cobalt'], fx)
    kw, kd, kh = P['kiosks']['size']
    for name in ('Kiosk_Shop', 'Kiosk_Trade'):
        kx, ky = P['kiosks'][name]
        box('BO_' + name, kx - kw / 2, ky - kd / 2, 0.0, kx + kw / 2, ky + kd / 2, kh,
            M['tangerine'] if name == 'Kiosk_Shop' else M['coral'], fx, floor=True, kind='kiosk')
    pod = P['podium']
    for i, (px, ph_) in enumerate(zip(pod['x'], pod['h'])):
        hs = pod['size'] / 2
        box('BO_Statue_%d' % [2, 1, 3][i], px - hs, pod['y'] - hs, 0.0, px + hs, pod['y'] + hs, ph_,
            M['gold'], fx, floor=True, kind='plinth')
    cx0, cx1 = L['cue_x']
    box('BO_CueRoom_E', cx1 - 0.4, y0, 0.0, cx1, bf, bz - bs, M['accent'], fx, floor=True, kind='wall')
    d0, d1 = P['cue_room']['door']
    box('BO_CueRoom_Curb', cx0, bf - 0.4, 0.0, d0, bf, 1.0, M['frame'], fx, floor=True, kind='wall')
    box('BO_CueRoom_Window', cx0, bf - 0.3, 1.0, d0, bf - 0.1, 9.0, M['glass'], fx, floor=True, kind='wall')
    box('BO_CueRoom_Head', cx0, bf - 0.4, 9.0, cx1, bf, bz - bs, M['wall'], fx)
    box('BO_CueRoom_DoorGlass', d0, bf - 0.3, 0.0, d1, bf - 0.1, 9.0, M['glass'], fx)
    box('BO_CueRoom_Post', d1, bf - 0.4, 0.0, cx1, bf, 9.0, M['frame'], fx, floor=True, kind='wall')
    box('BO_CueRoom_BackWall', cx0, y0, 0.0, cx1, y0 + 0.2, bz - bs, M['yellow'], fx)
    ps = P['piano_stage']
    cylinder('BO_PianoStage_Step', ps['centre'][0], ps['centre'][1], ps['diameter'] / 2 + ps['step'],
             0.0, ps['height'] / 2, M['marble'], fx, floor=True, kind='stage')
    cylinder('BO_PianoStage', ps['centre'][0], ps['centre'][1], ps['diameter'] / 2, 0.0, ps['height'],
             M['marble'], fx)
    cylinder('BO_PianoStage_Edge', ps['centre'][0], ps['centre'][1], ps['diameter'] / 2 + 0.05,
             ps['height'] - 0.2, ps['height'] + 0.02, M['gold'], fx)

    # ---- ceiling: dark slat panels over the play zones (texture in stage 2) --------------------
    cl = C['HUB_Ceiling']
    for zone, (a0, a1, b0, b1) in (
            ('1v1', (x0 + 4, xp13 - 4, L['walk_n'] + 4, y1 - 4)),
            ('2v2', (x0 + 4, L['x_part_2e'] - 4, bf + 4, L['y_part_2n'] - 4)),
            ('3v3', (xp13 + 4, x1 - 4, L['walk_n'] + 4, y1 - 4))):
        box('BO_SlatPanel_' + zone, a0, b0, H - 0.25, a1, b1, H, M['navy'], cl)

    # ---- terrace ---------------------------------------------------------------------------------
    te = P['terrace']
    tr = C['HUB_Terrace']
    tx_0, tx_1 = x1 + w, x1 + w + te['depth']
    box('BO_Terrace_Floor', tx_0, ty[0], -r['slab'], tx_1, ty[1], 0.0, M['tile'], tr)
    rh_ = te['rail_h']
    box('BO_Terrace_Rail_E', tx_1 - 0.5, ty[0], 0.0, tx_1, ty[1], rh_, M['white'], tr)
    box('BO_Terrace_Rail_S', tx_0, ty[0], 0.0, tx_1, ty[0] + 0.5, rh_, M['white'], tr)
    box('BO_Terrace_Rail_N', tx_0, ty[1] - 0.5, 0.0, tx_1, ty[1], rh_, M['white'], tr)
    colc = C['HUB_Collision']
    for name, a in (('E', (tx_1, ty[0] - 0.5, tx_1 + 0.5, ty[1] + 0.5)),
                    ('S', (tx_0, ty[0] - 0.5, tx_1 + 0.5, ty[0])),
                    ('N', (tx_0, ty[1], tx_1 + 0.5, ty[1] + 0.5))):
        o = box('COL_TerraceWall_' + name, a[0], a[1], 0.0, a[2], a[3], te['col_h'], M['col'], colc)
        o.hide_render = True
        o.display_type = 'WIRE'

    # ---- 16 table instances, pads, markers -------------------------------------------------------
    tcoll, mk = C['HUB_Tables'], C['HUB_Markers']
    for tb in L['tables']:
        inst = bpy.data.objects.new('Table_%d' % tb['n'], None)
        inst.instance_type = 'COLLECTION'
        inst.instance_collection = table_coll
        inst.location = (tb['x'], tb['y'], 0.0)
        inst.rotation_euler = (0.0, 0.0, math.radians(tb['yaw']))
        inst['zone'] = tb['zone']
        inst['yaw_deg'] = tb['yaw']
        inst['head'] = tb['head']
        tcoll.objects.link(inst)
        pr = tb['pad_rect']
        quad('BO_Pad_%d' % tb['n'], pr[0], pr[1], pr[2], pr[3], 0.03, M['pad_' + tb['zone']], mk)
        empty('Pad_%d' % tb['n'], (tb['pad'][0], tb['pad'][1], 0.0), mk, tb['yaw'], 3.0, 'CUBE',
              table=tb['n'], zone=tb['zone'])
    sp = L['spawn']
    empty('Spawn', sp, mk, 0.0, 3.0, 'SINGLE_ARROW')
    empty('StairFoot', (L['stair_foot'][0], L['stair_foot'][1], 0.0), mk, 0.0, 2.0, 'CIRCLE')
    empty('Door_ProLobby', (x0 + 0.3, walk_c, 0.0), mk, 0.0, 3.0, 'SINGLE_ARROW', facing='+X')
    empty('Screen_Featured', (fcx, y0 + 0.3, sum(fs['z']) / 2), mk, 0.0, 3.0, 'SINGLE_ARROW', facing='+Y')
    for i, sy in enumerate(bar['screens_y']):
        empty('Screen_Leader_%d' % (i + 1), (bk[0] - 0.2, sy, sum(bar['screen_z']) / 2), mk, 0.0, 2.0,
              'SINGLE_ARROW', facing='-X')
    for name in ('Kiosk_Shop', 'Kiosk_Trade'):
        empty(name, (*P['kiosks'][name], 0.0), mk, 0.0, 2.0, 'CUBE')
    for i, px in enumerate(pod['x']):
        empty('Statue_%d' % [2, 1, 3][i], (px, pod['y'], pod['h'][i]), mk, 90.0, 2.0, 'SINGLE_ARROW')
    empty('Piano', (ps['centre'][0], ps['centre'][1], ps['height']), mk, 0.0, 3.0, 'CUBE')

    # ---- lights for the blockout renders only (the Roblox lights are data, stage 4) ------------
    lt = C['HUB_Lights']
    for i in range(3):
        for j in range(3):
            ld = bpy.data.lights.new('BO_Light_%d%d' % (i, j), 'AREA')
            ld.shape = 'RECTANGLE'
            ld.size, ld.size_y = (x1 - x0) / 3.0, (y1 - y0) / 3.0
            ld.energy = 5500.0
            ld.color = (1.0, 0.98, 0.95)
            ob = bpy.data.objects.new('BO_Light_%d%d' % (i, j), ld)
            ob.location = (x0 + (i + 0.5) * (x1 - x0) / 3, y0 + (j + 0.5) * (y1 - y0) / 3, H - 0.5)
            lt.objects.link(ob)
    sun_d = bpy.data.lights.new('BO_DuskSun', 'SUN')
    sun_d.energy = 1.2
    sun_d.color = (1.0, 0.72, 0.45)
    sun = bpy.data.objects.new('BO_DuskSun', sun_d)
    sun.rotation_euler = (math.radians(80), 0.0, math.radians(-100))
    lt.objects.link(sun)
    setup_world(scene)
    for obj in walk_objects(root):
        obj['hub_owned'] = 1
    print('HUB blockout: %d objects, %d tables' % (len(list(walk_objects(root))), len(L['tables'])))
    return L


def setup_world(scene):
    world = bpy.data.worlds.get('HubDuskPlaceholder') or bpy.data.worlds.new('HubDuskPlaceholder')
    scene.world = world
    if world.node_tree is None:
        world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    nodes.clear()
    out = nodes.new('ShaderNodeOutputWorld')
    bg = nodes.new('ShaderNodeBackground')
    bg.inputs['Strength'].default_value = 1.0
    tc = nodes.new('ShaderNodeTexCoord')
    sep = nodes.new('ShaderNodeSeparateXYZ')
    fac = nodes.new('ShaderNodeMath')  # view direction z (-1..1) -> 0..1, horizon at 0.5
    fac.operation = 'MULTIPLY_ADD'
    fac.inputs[1].default_value = 0.5
    fac.inputs[2].default_value = 0.5
    ramp = nodes.new('ShaderNodeValToRGB')
    links.new(tc.outputs['Generated'], sep.inputs[0])
    links.new(sep.outputs['Z'], fac.inputs[0])
    links.new(fac.outputs['Value'], ramp.inputs['Fac'])
    els = ramp.color_ramp.elements  # placeholder dusk sky until the stage 4 skyboxes
    els[0].position, els[0].color = 0.40, (*lin('#2A2F45'), 1.0)
    els[1].position, els[1].color = 0.80, (*lin('#2E3F78'), 1.0)
    for pos, col in ((0.50, '#F2A65A'), (0.56, '#F7C98B')):
        e = els.new(pos)
        e.color = (*lin(col), 1.0)
    links.new(ramp.outputs['Color'], bg.inputs['Color'])
    links.new(bg.outputs['Background'], out.inputs['Surface'])
    world.color = lin('#F4F6FA')  # Workbench background


# =================================================================================================
# Stage 1: audit
# =================================================================================================
def rect_gap(a, b):
    dx = max(0.0, a[0] - b[2], b[0] - a[2])
    dy = max(0.0, a[1] - b[3], b[1] - a[3])
    return math.hypot(dx, dy)


def rect_overlap(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def floor_obstacles():
    root = bpy.data.collections.get(ROOT)
    obs = []
    for obj in walk_objects(root):
        if obj.get('hub_floor'):
            bb = world_aabb(obj)
            if bb[2] > 0.5:  # starts above the floor: not standing on it
                continue
            obs.append({'name': obj.name, 'rect': (bb[0], bb[1], bb[3], bb[4]),
                        'kind': obj.get('hub_kind', ''), 'block': bool(obj.get('hub_block')),
                        'zone': obj.get('zone', '')})
    return obs


class WalkGrid:
    def __init__(self, L, obstacles):
        r = P['room']
        self.res = P['grid']
        self.rad = P['avatar']['radius']
        self.x0, self.y0 = r['x0'], r['y0']
        self.nx = int(round((r['x1'] - r['x0']) / self.res))
        self.ny = int(round((r['y1'] - r['y0']) / self.res))
        self.blocked = bytearray(self.nx * self.ny)
        rad = self.rad
        # the outer walls (door openings are targets on the wall line, snapped inward)
        self.mark((r['x0'] - 5, r['y0'] - 5, r['x0'], r['y1'] + 5), rad)
        self.mark((r['x1'], r['y0'] - 5, r['x1'] + 5, r['y1'] + 5), rad)
        self.mark((r['x0'] - 5, r['y0'] - 5, r['x1'] + 5, r['y0']), rad)
        self.mark((r['x0'] - 5, r['y1'], r['x1'] + 5, r['y1'] + 5), rad)
        for o in obstacles:
            if o['block'] and o['kind'] != 'wall':
                self.mark(o['rect'], rad)
            elif o['block']:
                self.mark(o['rect'], rad)
        for tb in L['tables']:
            self.mark(tb['rect'], rad)

    def mark(self, rect, rad):
        i0 = max(0, int(math.floor((rect[0] - rad - self.x0) / self.res)))
        i1 = min(self.nx - 1, int(math.ceil((rect[2] + rad - self.x0) / self.res)))
        j0 = max(0, int(math.floor((rect[1] - rad - self.y0) / self.res)))
        j1 = min(self.ny - 1, int(math.ceil((rect[3] + rad - self.y0) / self.res)))
        for j in range(j0, j1 + 1):
            cy = self.y0 + (j + 0.5) * self.res
            if not (rect[1] - rad <= cy <= rect[3] + rad):
                continue
            row = j * self.nx
            for i in range(i0, i1 + 1):
                cx = self.x0 + (i + 0.5) * self.res
                if rect[0] - rad <= cx <= rect[2] + rad:
                    self.blocked[row + i] = 1

    def cell(self, x, y):
        i = int((x - self.x0) / self.res)
        j = int((y - self.y0) / self.res)
        return max(0, min(self.nx - 1, i)), max(0, min(self.ny - 1, j))

    def centre(self, i, j):
        return self.x0 + (i + 0.5) * self.res, self.y0 + (j + 0.5) * self.res

    def snap(self, x, y):
        """Nearest free cell to (x, y): (index, snap distance)."""
        i, j = self.cell(x, y)
        best = None
        for rr in range(0, 40):
            for dj in range(-rr, rr + 1):
                for di in range(-rr, rr + 1):
                    if max(abs(di), abs(dj)) != rr:
                        continue
                    ii, jj = i + di, j + dj
                    if 0 <= ii < self.nx and 0 <= jj < self.ny and not self.blocked[jj * self.nx + ii]:
                        cx, cy = self.centre(ii, jj)
                        d = math.hypot(cx - x, cy - y)
                        if best is None or d < best[1]:
                            best = (jj * self.nx + ii, d)
            if best is not None:
                return best
        return None

    def dijkstra(self, start_idx):
        nx, ny, blocked = self.nx, self.ny, self.blocked
        INF = float('inf')
        dist = [INF] * (nx * ny)
        parent = [-1] * (nx * ny)
        dist[start_idx] = 0.0
        heap = [(0.0, start_idx)]
        s2 = math.sqrt(2.0) * self.res
        res = self.res
        steps = [(1, 0, res), (-1, 0, res), (0, 1, res), (0, -1, res),
                 (1, 1, s2), (1, -1, s2), (-1, 1, s2), (-1, -1, s2)]
        while heap:
            d, idx = heapq.heappop(heap)
            if d > dist[idx]:
                continue
            j, i = divmod(idx, nx)
            for di, dj, c in steps:
                ii, jj = i + di, j + dj
                if ii < 0 or jj < 0 or ii >= nx or jj >= ny:
                    continue
                n = jj * nx + ii
                if blocked[n]:
                    continue
                if di and dj and (blocked[j * nx + ii] or blocked[jj * nx + i]):
                    continue  # no corner cutting
                nd = d + c
                if nd < dist[n]:
                    dist[n] = nd
                    parent[n] = idx
                    heapq.heappush(heap, (nd, n))
        return dist, parent

    def los(self, a, b):
        (ax, ay), (bx, by) = self.centre(*a), self.centre(*b)
        n = int(math.hypot(bx - ax, by - ay) / (self.res * 0.25)) + 1
        for k in range(n + 1):
            t = k / n
            i, j = self.cell(ax + (bx - ax) * t, ay + (by - ay) * t)
            if self.blocked[j * self.nx + i]:
                return False
        return True

    def smooth_path(self, parent, idx):
        """Grid path from the start to idx, string-pulled to an any-angle path."""
        cells = []
        while idx != -1:
            j, i = divmod(idx, self.nx)
            cells.append((i, j))
            idx = parent[idx]
        cells.reverse()
        out = [cells[0]]
        k = 0
        while k < len(cells) - 1:
            nxt = k + 1
            lo, hi = k + 1, len(cells) - 1
            while lo <= hi:  # furthest visible cell (binary search is fine on these paths)
                mid = (lo + hi) // 2
                if self.los(cells[k], cells[mid]):
                    nxt, lo = mid, mid + 1
                else:
                    hi = mid - 1
            out.append(cells[nxt])
            k = nxt
        pts = [self.centre(i, j) for i, j in out]
        length = sum(math.hypot(pts[q + 1][0] - pts[q][0], pts[q + 1][1] - pts[q][1])
                     for q in range(len(pts) - 1))
        return pts, length


def stage_audit():
    scene = bpy.context.scene
    L = layout()
    obs = floor_obstacles()
    tables = L['tables']
    res = {'tables': [], 'walk': [], 'heights': {}, 'room': {}, 'pass': True}
    fails = []
    # ---- 1. clearance: every table to everything standing on the floor, and to other tables ---
    for tb in tables:
        best = (1e9, '')
        for o in obs:
            d = rect_gap(tb['rect'], o['rect'])
            if d < best[0]:
                best = (d, o['name'])
        for other in tables:
            if other is tb:
                continue
            d = rect_gap(tb['rect'], other['rect'])
            if d < best[0]:
                best = (d, 'Table_%d' % other['n'])
        seat_d = min((rect_gap(tb['rect'], o['rect']), o['name']) for o in obs if o['kind'] == 'seat')
        # pad: clear of every obstacle, every table and every other pad
        pad_best = (1e9, '')
        for o in obs:
            d = rect_gap(tb['pad_rect'], o['rect'])
            if d < pad_best[0]:
                pad_best = (d, o['name'])
        own = rect_gap(tb['pad_rect'], tb['rect'])
        if own <= 0.0:
            pad_best = (0.0, 'own table')
        for other in tables:
            if other is tb:
                continue
            d = rect_gap(tb['pad_rect'], other['rect'])
            if d < pad_best[0]:
                pad_best = (d, 'Table_%d' % other['n'])
            if True:
                d = rect_gap(tb['pad_rect'], other['pad_rect'])
                if d < pad_best[0]:
                    pad_best = (d, 'Pad_%d' % other['n'])
        row = {'n': tb['n'], 'zone': tb['zone'], 'x': round(tb['x'], 2), 'y': round(tb['y'], 2),
               'yaw': tb['yaw'], 'head': tb['head'], 'pad': [round(tb['pad'][0], 2), round(tb['pad'][1], 2)],
               'clearance_needed': tb['clearance'], 'nearest': round(best[0], 2), 'nearest_what': best[1],
               'clear_ok': best[0] >= tb['clearance'] - 1e-6,
               'seat_distance': round(seat_d[0], 2), 'seat_what': seat_d[1],
               'seat_ok': 7.0 <= seat_d[0] <= 20.0,
               'pad_gap': round(pad_best[0], 2), 'pad_gap_what': pad_best[1], 'pad_ok': pad_best[0] > 0.0}
        res['tables'].append(row)
        for key in ('clear_ok', 'seat_ok', 'pad_ok'):
            if not row[key]:
                fails.append('Table_%d %s' % (tb['n'], key))
    # ---- 2. heights: ray casts through the real geometry ----------------------------------------
    # every hub layer must be in the depsgraph, whatever the viewport currently hides
    hidden = []

    def unhide(lc):
        if lc.collection.name.startswith('HUB') and lc.collection.name != 'HUB_Plan':
            if lc.hide_viewport or lc.collection.hide_viewport:
                hidden.append((lc, lc.hide_viewport, lc.collection.hide_viewport))
                lc.hide_viewport = False
                lc.collection.hide_viewport = False
        for child in lc.children:
            unhide(child)
    unhide(bpy.context.view_layer.layer_collection)
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    from mathutils import Vector

    def up_hit(x, y, z):
        hit, loc, _n, _i, obj, _m = scene.ray_cast(depsgraph, Vector((x, y, z)), Vector((0, 0, 1)))
        return (loc.z, obj.name) if hit else (None, None)
    over = []
    for tb in tables:
        x0, y0, x1, y1 = tb['rect']
        for (x, y) in ((tb['x'], tb['y']), (x0 + 0.3, y0 + 0.3), (x1 - 0.3, y0 + 0.3),
                       (x0 + 0.3, y1 - 0.3), (x1 - 0.3, y1 - 0.3)):
            z, name = up_hit(x, y, 5.0)
            over.append((z if z is not None else -1.0, name, tb['n']))  # no ceiling hit is a failure
    worst = min(over)
    res['heights']['clear_over_tables_min'] = round(worst[0], 3)
    res['heights']['clear_over_tables_what'] = '%s over Table_%d' % (worst[1], worst[2])
    if worst[0] < P['min_clear_over_tables']:
        fails.append('clear height over tables')
    under = []
    bf = L['balcony_front']
    for x in (-80.0, -60.0, -30.0, 50.0, 75.0):
        z, name = up_hit(x, (P['room']['y0'] + bf) / 2 + 2.0, 0.1)
        under.append((z if z is not None else -1.0, name, x))
    px0, px1 = L['prow_x']
    worst_u = min(under)
    res['heights']['under_balcony_min'] = round(worst_u[0], 3)
    res['heights']['under_balcony_what'] = '%s at x %.1f' % (worst_u[1], worst_u[2])
    if worst_u[0] < P['min_clear_walk_under']:
        fails.append('clear height under balcony')
    for lc, a, b_ in hidden:
        lc.hide_viewport, lc.collection.hide_viewport = a, b_
    res['heights']['ceiling'] = P['room']['ceiling']
    res['heights']['balcony_z'] = P['balcony']['z']
    res['heights']['stair'] = '%d steps, %.1f rise, %.1f run' % (P['stair']['steps'], P['stair']['rise'],
                                                               P['stair']['run'])
    # balcony and prow never overhang a table
    bal = [(P['room']['x0'], P['room']['y0'], P['room']['x1'], bf), (px0, bf, px1, L['prow_front'])]
    ov = min(rect_gap(tb['rect'], bb) for tb in tables for bb in bal)
    res['heights']['balcony_to_nearest_table'] = round(ov, 3)
    if ov <= 0.0:
        fails.append('balcony overhangs a table')
    # ---- 3. walk distances from the foot of the spawn stair ------------------------------------
    grid = WalkGrid(L, obs)
    sx, sy = L['stair_foot']
    start = grid.snap(sx, sy + 1.0)
    dist, parent = grid.dijkstra(start[0])
    r = P['room']
    walk_c = (L['walk_s'] + L['walk_n']) / 2
    targets = [('Table_%d (pad)' % tb['n'], tb['pad'], True) for tb in tables]
    bar = P['bar']
    targets += [
        ('Bar (stool line)', (bar['stand_x'], (bar['counter'][2] + bar['counter'][3]) / 2), True),
        ('Terrace door', (r['x1'], sum(P['terrace']['door_y']) / 2), True),
        ('Pro lobby door', (r['x0'], walk_c), False),
        ('Kiosk_Shop', (P['kiosks']['Kiosk_Shop'][0], P['kiosks']['Kiosk_Shop'][1] + 2.5), False),
        ('Kiosk_Trade', (P['kiosks']['Kiosk_Trade'][0], P['kiosks']['Kiosk_Trade'][1] + 2.5), False),
        ('Piano stage', (P['piano_stage']['centre'][0], P['piano_stage']['centre'][1] + 9.0), False),
        ('Cue room door', (sum(P['cue_room']['door']) / 2, L['balcony_front'] + 1.0), False),
    ]
    far = (0.0, None)
    for name, (tx, ty_), required in targets:
        sn = grid.snap(tx, ty_)
        if sn is None or dist[sn[0]] == float('inf'):
            res['walk'].append({'target': name, 'grid': None, 'path': None, 'snap': None,
                                'required': required, 'ok': False})
            fails.append('unreachable: ' + name)
            continue
        pts, length = grid.smooth_path(parent, sn[0])
        length += sn[1]
        ok = length <= P['walk_limit']
        res['walk'].append({'target': name, 'grid': round(dist[sn[0]], 1), 'path': round(length, 1),
                            'seconds': round(length / P['avatar']['walk_speed'], 2),
                            'snap': round(sn[1], 2), 'required': required, 'ok': ok,
                            'xy': [round(tx, 2), round(ty_, 2)]})
        if required and not ok:
            fails.append('walk > %.0f: %s' % (P['walk_limit'], name))
        if required and length > far[0]:
            far = (length, name, pts)
    res['farthest'] = {'target': far[1], 'path': round(far[0], 1), 'points': [[round(a, 2), round(b_, 2)]
                                                                             for a, b_ in far[2]]}
    res['room'] = {'interior_x': round(r['x1'] - r['x0'], 2), 'interior_y': round(r['y1'] - r['y0'], 2),
                   'brief': 'at most about 170 x 150'}
    res['fails'] = fails
    res['pass'] = not fails
    res['start'] = [round(sx, 2), round(sy, 2)]
    scene['hub_audit'] = json.dumps(res)
    write_audit_md(res, L)
    print('HUB audit: %s, %d fails %s' % ('PASS' if res['pass'] else 'FAIL', len(fails), fails))
    return res


def write_audit_md(res, L):
    t = P['table']
    lines = ['# Skyline Club: stage 1 layout audit', '',
             'Generated by `assets/hub/HubBuilder.py -- audit` from the blockout geometry in '
             '`assets/hub/Hub.blend`. Units are studs. X runs east, Y north, the main floor is Z = 0.',
             '', '**Result: %s**' % ('PASS' if res['pass'] else 'FAIL: ' + '; '.join(res['fails'])), '',
             '## Rules checked', '',
             '- Every table keeps 10 studs (3v3: 12) to anything standing on the floor and to other tables.',
             '- Every 6 x 6 join pad (14 studs from the table centre towards the head rail) is clear of '
             'furniture, walls, other tables and other pads.',
             '- Every table has seating 7 to 20 studs away.',
             '- At least %.0f studs clear over every table, at least %.0f under anything walked beneath.'
             % (P['min_clear_over_tables'], P['min_clear_walk_under']),
             '- Every table (its join pad), the bar and the terrace door are within %.0f studs '
             '(8 s at 16 studs/s) of the foot of the spawn stair.' % P['walk_limit'],
             '', '## Room', '',
             '| Item | Value |', '|---|---|',
             '| Interior | %.1f x %.1f (brief: %s) |' % (res['room']['interior_x'], res['room']['interior_y'],
                                                        res['room']['brief']),
             '| Main hall ceiling | %.1f |' % res['heights']['ceiling'],
             '| Lowest thing over any table | %.2f (%s) |' % (res['heights']['clear_over_tables_min'],
                                                           res['heights']['clear_over_tables_what']),
             '| Clear height under the balcony | %.2f (%s) |' % (res['heights']['under_balcony_min'],
                                                               res['heights']['under_balcony_what']),
             '| Balcony floor | Z %.1f, %s |' % (res['heights']['balcony_z'], res['heights']['stair']),
             '| Balcony/prow to nearest table (plan) | %.2f |' % res['heights']['balcony_to_nearest_table'],
             '| Table footprint | %.2f x %.2f |' % (t['length'], t['width']),
             '', '## Tables', '',
             '| Table | Zone | Centre | Yaw | Head | Pad centre | Nearest thing (need) | Pad gap | '
             'Nearest seats | OK |',
             '|---|---|---|---|---|---|---|---|---|---|']
    for row in res['tables']:
        ok = row['clear_ok'] and row['pad_ok'] and row['seat_ok']
        lines.append('| %d | %s | %.2f, %.2f | %.0f | %s | %.2f, %.2f | %.2f %s (%.0f) | %.2f %s | %.2f %s | %s |'
                     % (row['n'], row['zone'], row['x'], row['y'], row['yaw'], row['head'], row['pad'][0],
                        row['pad'][1], row['nearest'], row['nearest_what'], row['clearance_needed'],
                        row['pad_gap'], row['pad_gap_what'], row['seat_distance'], row['seat_what'],
                        'yes' if ok else '**NO**'))
    lines += ['', '## Walk distances from the foot of the spawn stair', '',
              'Start: (%.2f, %.2f), one stud north of the bottom step. Method: Dijkstra on a %.1f-stud '
              'grid with every obstacle and table grown by the avatar radius (%.1f, arms out), then the '
              'path pulled tight (any-angle). "Grid" is the raw 8-way grid length, which overstates '
              'diagonals; "Path" is the pulled path and is what is checked.'
              % (res['start'][0], res['start'][1], P['grid'], P['avatar']['radius']), '',
              '| Target | Path | Seconds | Grid | Required | OK |', '|---|---|---|---|---|---|']
    for w in res['walk']:
        lines.append('| %s | %s | %s | %s | %s | %s |' % (
            w['target'], w['path'], w.get('seconds', '-'), w['grid'], 'yes' if w['required'] else 'info',
            'yes' if w['ok'] else '**NO**'))
    lines += ['', 'Longest required walk: **%s, %.1f studs** (%.1f s).' % (
        res['farthest']['target'], res['farthest']['path'], res['farthest']['path'] / P['avatar']['walk_speed']),
        '']
    with open(AUDIT_MD, 'w') as f:
        f.write('\n'.join(lines))


# =================================================================================================
# Stage 1: renders
# =================================================================================================
def set_engine(scene, want):
    try:
        scene.render.engine = want
    except TypeError as e:
        raise RuntimeError('render engine %s not available: %s' % (want, e))


def camera(name, loc, target, coll, ortho=None, fov_v=None, lens=None):
    from mathutils import Vector
    cd = bpy.data.cameras.new(name)
    if ortho:
        cd.type = 'ORTHO'
        cd.ortho_scale = ortho
    elif fov_v:
        cd.sensor_fit = 'VERTICAL'
        cd.angle_y = math.radians(fov_v)
    elif lens:
        cd.lens = lens
    cd.clip_start, cd.clip_end = 0.5, 2000.0
    obj = bpy.data.objects.new(name, cd)
    obj.location = loc
    d = Vector(target) - Vector(loc)
    obj.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    coll.objects.link(obj)
    return obj


def set_hidden(names, hidden):
    root = bpy.data.collections.get(ROOT)
    for child in root.children:
        if child.name in names:
            child.hide_render = hidden


def build_plan_overlay(L, audit):
    pl = bpy.data.collections['HUB_Plan']
    clear_collection(pl)
    ink = material('BO_Ink', 'ink', 1.0)
    white = material('BO_InkWhite', '#FFFFFF', 1.0)
    red = material('BO_PathRed', '#E0162B', 1.0)
    faint = material('BO_InkFaint', '#46506A', 1.0)
    zmat = {z: material('BO_ZoneLine_' + z, z, 1.0) for z in ('1v1', '2v2', '3v3')}
    r = P['room']
    walk = {w['target']: w for w in audit['walk']} if audit else {}
    for tb in L['tables']:
        c = tb['clearance']
        x0, y0, x1, y1 = tb['rect']
        poly_curve('PL_Clear_%d' % tb['n'], [(x0 - c, y0 - c), (x1 + c, y0 - c), (x1 + c, y1 + c),
                                             (x0 - c, y1 + c)], zmat[tb['zone']], pl, 0.12, True, 28.0)
        text('PL_T%d' % tb['n'], 'T%d' % tb['n'], tb['x'], tb['y'], 3.2, white, pl, 29.0)
        wd = walk.get('Table_%d (pad)' % tb['n'])
        body = '%d' % round(wd['path']) if wd and wd['path'] is not None else '?'
        text('PL_PadD_%d' % tb['n'], body, tb['pad'][0], tb['pad'][1], 2.2, ink, pl, 29.0)
    bf, pf = L['balcony_front'], L['prow_front']
    px0, px1 = L['prow_x']
    poly_curve('PL_BalconyEdge', [(r['x0'], bf), (px0, bf), (px0, pf), (px1, pf), (px1, bf), (r['x1'], bf)],
               faint, pl, 0.35, False, 28.0)
    labels = [
        ('1v1 ZONE  (10 tables)', -27.0, 66.5, 4.2, ink),
        ('2v2 ZONE  (4 tables)', -49.0, -37.8, 3.2, ink),
        ('3v3 ZONE  (2 tables)', 57.5, 63.0, 4.2, ink),
        ('MAIN WALKWAY  (marble)', -45.0, -6.0, 3.0, ink),
        ('PLAZA / CROSSROADS', 8.0, -22.0, 2.4, ink),
        ('SPAWN STAIR', L['stair_foot'][0], -44.0, 2.2, ink),
        ('STAIR SEATS', (L['seats_x'][0] + L['seats_x'][1]) / 2, -40.0, 1.6, ink),
        ('BAR', 21.5, -25.0, 2.2, ink),
        ('3 LEADERBOARDS', 25.0, -39.8, 1.5, ink),
        ('LOUNGE', 50.0, -30.0, 4.0, ink),
        ('PIANO STAGE', 75.0, -26.0, 2.0, ink),
        ('TERRACE', r['x1'] + 15.0, -43.0, 4.0, ink),
        ('CUE ROOM (glass)', (L['cue_x'][0] + L['cue_x'][1]) / 2, -69.0, 2.0, ink),
        ('SHOP  TRADE', 27.0, -51.5, 1.6, ink),
        ('TOP-3 STATUES', 6.0, -18.2, 1.5, ink),
        ('PRO LOBBY DOOR', r['x0'] + 12.0, (L['walk_s'] + L['walk_n']) / 2 + 3.0, 2.0, ink),
        ('BALCONY ABOVE (Z 11.2)', -50.0, -71.0, 2.4, faint),
        ('SPAWN', L['spawn'][0], L['spawn'][1], 2.2, red),
        ('FEATURED SCREEN (south wall, above balcony)', L['stair_foot'][0], -77.5, 1.8, ink),
        ('North windows: skyline', -27.0, r['y1'] + 3.5, 2.6, faint),
        ('West windows', r['x0'] - 3.5, 40.0, 2.4, faint),
        ('East windows', r['x1'] + 3.5, 40.0, 2.4, faint),
    ]
    for i, (body, x, y, size, mat) in enumerate(labels):
        o = text('PL_Label_%02d' % i, body, x, y, size, mat, pl, 29.5)
        if body in ('West windows', 'East windows'):
            o.rotation_euler = (0, 0, math.radians(90))
    text('PL_Title', 'SKYLINE CLUB  -  stage 1 blockout plan (studs)', r['x0'], r['y1'] + 9.0, 4.0, ink, pl,
         29.5, 'LEFT')
    legend = ['Squares on the floor = join pads; the number is the walk from the stair foot.',
              'Thin coloured outlines = table clearance (10 studs, 12 for 3v3).',
              'Coloured bars = seating proxies. Red line = the longest walk. Grey line = balcony edge.']
    for i, body in enumerate(legend):
        text('PL_Legend_%d' % i, body, r['x0'], r['y0'] - 8.0 - i * 3.2, 2.2, ink, pl, 29.5, 'LEFT')
    # scale bar and north arrow
    sx, sy = r['x1'] - 45.0, r['y0'] - 9.0
    box('PL_Scale', sx, sy, 28.0, sx + 20.0, sy + 0.8, 28.2, ink, pl)
    text('PL_ScaleT', '20 studs', sx + 10.0, sy - 2.2, 2.0, ink, pl, 29.5)
    ax, ay = r['x1'] + 22.0, r['y1'] - 4.0
    mesh_object('PL_North', [(ax - 2.5, ay - 3.0, 28.0), (ax + 2.5, ay - 3.0, 28.0), (ax, ay + 4.0, 28.0)],
                [(0, 1, 2)], ink, pl)
    text('PL_NorthT', 'N', ax, ay + 7.0, 3.5, ink, pl, 29.5)
    if audit and audit.get('farthest', {}).get('points'):
        pts = [tuple(p) for p in audit['farthest']['points']]
        poly_curve('PL_LongestWalk', pts, red, pl, 0.35, False, 28.5)
    return pl


def render_to(scene, cam, path, size):
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    scene.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
    print('HUB render', path)


def stage_render1(which=None):
    scene = bpy.context.scene
    L = layout()
    audit = json.loads(scene['hub_audit']) if 'hub_audit' in scene else None
    os.makedirs(RENDER_DIR, exist_ok=True)
    cams = bpy.data.collections['HUB_Cameras']
    clear_collection(cams)
    build_plan_overlay(L, audit)
    try:
        scene.view_settings.view_transform = 'Standard'
    except TypeError:
        pass
    rp = P['render']
    r = P['room']
    out = {}
    # ---- plan: Workbench, flat colours, top-down ------------------------------------------------
    if which in (None, 'plan'):
        set_engine(scene, 'BLENDER_WORKBENCH')
        sh = scene.display.shading
        sh.light = 'FLAT'
        sh.color_type = 'MATERIAL'
        sh.show_object_outline = True
        sh.show_shadows = False
        sh.show_cavity = False
        cx = (r['x0'] + r['x1'] + P['terrace']['depth'] + 10) / 2
        cy = (r['y0'] + r['y1']) / 2 - 2.0
        cam = camera('CAM_Plan', (cx, cy, 200.0), (cx, cy, 0.0), cams, ortho=r['x1'] - r['x0'] + 60.0)
        set_hidden({'HUB_Ceiling', 'HUB_Balcony', 'HUB_Lights', 'HUB_Collision'}, True)
        set_hidden({'HUB_Plan'}, False)
        out['plan'] = os.path.join(RENDER_DIR, 'checkpoint_stage1_plan.png')
        render_to(scene, cam, out['plan'], rp['plan_size'])
    # ---- perspective views: EEVEE -----------------------------------------------------------------
    set_engine(scene, 'BLENDER_EEVEE')
    try:
        scene.eevee.taa_render_samples = rp['samples']
    except AttributeError:
        pass
    for attr, val in (('use_raytracing', True), ('use_shadows', True)):
        try:
            setattr(scene.eevee, attr, val)
        except AttributeError:
            pass
    set_hidden({'HUB_Plan', 'HUB_Collision'}, True)
    set_hidden({'HUB_Ceiling', 'HUB_Balcony', 'HUB_Lights'}, False)
    sp = L['spawn']
    eye = P['avatar']['eye']
    views = {
        # Roblox's default camera sits behind and above the avatar; this is that view from spawn
        'spawn': ((sp[0], sp[1] - 6.0, sp[2] + eye + 2.5), (sp[0] - 6.0, 30.0, 2.0)),
        'eye_1v1': ((8.0, 36.0, eye + 0.8), (-60.0, 33.0, 2.5)),
        'north_windows': ((-36.8, 50.0, eye + 1.5), (-52.0, 160.0, 13.0)),  # in the gap between tables 7 and 8
    }
    for name, (loc, tgt) in views.items():
        if which not in (None, name):
            continue
        cam = camera('CAM_' + name, loc, tgt, cams, fov_v=rp['fov_v'])
        out[name] = os.path.join(RENDER_DIR, 'checkpoint_stage1_%s.png' % name)
        render_to(scene, cam, out[name], rp['size'])
    if which in (None, 'overview'):
        set_hidden({'HUB_Ceiling'}, True)
        cam = camera('CAM_overview', (135.0, -150.0, 150.0), (5.0, -5.0, 0.0), cams, lens=30.0)
        out['overview'] = os.path.join(RENDER_DIR, 'checkpoint_stage1_overview.png')
        render_to(scene, cam, out['overview'], rp['size'])
        set_hidden({'HUB_Ceiling'}, False)
    set_hidden({'HUB_Plan'}, True)
    return out


# =================================================================================================
# Save
# =================================================================================================
def stage_save():
    bpy.ops.wm.save_as_mainfile(filepath=HUB_BLEND, compress=True)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(compress=True)
    print('HUB saved', HUB_BLEND)


STAGES = {'blockout': stage_blockout, 'audit': stage_audit, 'render1': stage_render1, 'save': stage_save}


def main(args):
    if not args:
        args = ['blockout', 'audit']
    for a in args:
        if ':' in a:  # render1:plan renders one view
            name, arg = a.split(':', 1)
            STAGES[name](arg)
        else:
            STAGES[a]()


if __name__ == '__main__':
    _args = globals().get('HUB_ARGS')
    if _args is None:
        _args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    main(_args)
