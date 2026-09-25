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
    'bar': {'counter': [21.5, 24.5, -35.0, -15.0], 'counter_h': 3.6,
            'back': [28.5, 29.5, -38.0, -13.0], 'back_h': 13.0,
            'screens_y': [-31.0, -24.0, -17.0], 'screen_w': 6.0, 'screen_z': [7.5, 11.0],
            'stand_x': 19.7},  # where a player stands at the bar (walk target)
    'cue_room': {'x1': 40.6, 'door': [35.0, 39.0]},  # runs from the stair core to x1, under the balcony
    'kiosks': {'Kiosk_Shop': [22.5, -48.0], 'Kiosk_Trade': [31.5, -48.0], 'size': [3.0, 2.0, 5.0]},
    'podium': {'x': [2.5, 6.0, 9.5], 'h': [1.4, 2.0, 1.0], 'y': -14.5, 'size': 3.0},  # top-3 statues
    'bench': [15.5, 27.5],  # walkway-edge bench by the bar (x range)
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
    # ---- stage 2: architecture ------------------------------------------------------------------
    'arch': {
        'window_head': 21.0,  # glass runs from the sill to here; the head above carries the band
        'band': [21.3, 24.3],  # the warm yellow band high on every wall
        'corner_radius': 10.0,  # NW and NE corners are curved walls; the band sweeps round them
        'corner_segments': 12,
        'bulkhead_w': 4.0, 'bulkhead_bottom': 24.5,  # white bulkheads flanking the slat fields
        'downlight_every': 6.0, 'downlight_r': 0.4,
        'led_w': 0.3,  # every LED line (nothing thinner than 0.25)
        'tray_top': 28.0,  # recessed tray ceiling over the main walkway
        'beam_every': 24.0, 'beam_w': 0.8, 'beam_depth': 1.2,
        'slat_inset': {'1v1': [6.0, 4.0, 5.0, 5.0], '2v2': [6.0, 4.0, 4.0, 4.0], '3v3': [4.0, 6.0, 5.0, 5.0]},
        'partition_post_every': 6.0, 'frame': 0.3,
        # free-standing columns: [x_min, y_min, size]; balcony columns come from the layout
        'columns': [[-12.22, -14.2, 1.6], [28.2, -13.0, 1.6], [29.3, 2.88, 1.6]],
        'column_chamfer': 0.25,
        'rail_cap': 0.3,
        'stage_segments': 32,
        'glass_t': 0.25,
        'fin': {'x': [41.0, 41.8], 'depth': 6.0, 'h': 12.0, 'r': 3.0},  # curved yellow fin by the cue room
    },
    # ---- stage 3: furniture, props, anchors ----------------------------------------------------------
    'pendant': {'bottom': 9.5},  # pendant bottom edge above the floor (tune; clear of the pool camera)
    'furnish': {
        'pair': 7.6, 'pair_gap': 1.4,  # armchair, side table, armchair; gap to the next pair
        'align': {'1v1_Gallery_1': 'max'},  # push this band's chairs towards the middle tables
        'stools': 8,
        'display_case': [21.5, -39.2, 24.9, -37.0],
        'lounge_cluster': [60.0, -32.0],
        'capsules': [46.0, -44.0],  # first capsule screen centre x, the row's y
        'lattice_x': [36.0, 42.0], 'lattice_y': -15.5,
        'ribbon': [38.0, 66.0, -30.0, 3.0, 15.5],  # x from, x to, y centre, wave amplitude, height
        'booths': [42.5, 84.5, 4],  # x from, x to, count (under the balcony)
        'jukebox': [83.0, -58.0],
        # zone: sign centre (x, y), facing, sign bottom height; the zone screen hangs below it
        'zone_signs': [['1v1', [-26.7, 1.0], '-Y', 16.5], ['2v2', [-12.9, -44.0], '+X', 14.5],
                       ['3v3', [57.5, 2.0], '-Y', 16.5]],
        'logo_balcony': [24.0],
        'window_sofas': [[38.0, 67.2], [47.0, 67.2], [56.0, 67.2], [65.0, 67.2]],
        'balcony_rail': [[-82.5, -66.5, -16.0, -63.5], [20.0, -66.5, 82.0, -63.5]],
        'plants': [[-83.0, -9.0], [-83.0, 3.0], [84.0, -14.5], [31.5, -60.5], [66.0, -60.0], [84.0, -35.0],
                   [32.0, 73.5], [73.0, 72.0], [13.5, -14.8]],
        'balcony_plants': [[-84.0, -73.5], [84.5, -73.5], [-15.8, -73.5], [8.3, -73.5]],
        'umbrellas': [[97.0, -56.0], [106.0, -43.0], [97.0, -30.0]],
        'terrace_plants': [[113.0, -64.0], [113.0, -22.0], [89.0, -64.0], [89.0, -22.0]],
        'decor': [[13.5, -18.5, 0.0], [-80.0, -8.0, 0.0], [-80.0, 1.0, 0.0], [82.0, -8.0, 0.0],
                  [70.0, -58.0, 0.0], [44.0, -52.0, 0.0], [-40.0, -72.0, 11.2], [50.0, -72.0, 11.2],
                  [100.0, -64.0, 0.0], [100.0, -22.0, 0.0], [32.0, 70.0, 0.0], [74.5, 60.0, 0.0],
                  [26.0, -58.0, 0.0]],
        'secrets': [[15.2, -59.0, 0.0], [85.2, -60.5, 0.0], [114.0, -21.0, 0.0], [-84.5, -74.5, 11.2],
                    [39.5, -74.0, 0.0]],
    },
    # ---- stage 4: skyline and lights -----------------------------------------------------------------
    'sky': {
        'eye': [0.0, 0.0, 8.0],  # skybox render point: the room centre
        'face_px': 1024,
        'city': {'seed': 11, 'count': 3200, 'r': [700.0, 6000.0], 'ground': -420.0},
        'mountains': [[9000.0, 700.0, 1500.0], [13000.0, 1100.0, 2400.0], [19000.0, 1500.0, 3400.0]],
        # time presets: sky top, sky horizon, sun direction (towards the sun), sun colour, sun strength,
        # haze, city facade, city glass, lit window fraction, mountain near and far colours
        'presets': {
            'Dusk': {'top': '#27336B', 'mid': '#8C5C8E', 'horizon': '#FFB067', 'sun': [-0.97, 0.12, 0.05],
                     'sun_colour': '#FFB36B', 'sun_strength': 2.2, 'haze': '#E9A48A', 'facade': '#6A6F8C',
                     'glass': '#3A4467', 'lit': 0.22, 'mtn': ['#6E5E8C', '#A889A6'], 'world': 0.75, 'ambient': '#C9D1E4'},
            'Day': {'top': '#2F7BE0', 'mid': '#6FA7EA', 'horizon': '#CFE4F6', 'sun': [-0.35, -0.45, 0.82],
                    'sun_colour': '#FFF6E5', 'sun_strength': 4.0, 'haze': '#D6E6F3', 'facade': '#B8C2D2',
                    'glass': '#7C9CC4', 'lit': 0.0, 'mtn': ['#6F8DB6', '#A6BEDA'], 'world': 1.2, 'ambient': '#E3EAF5'},
            'Night': {'top': '#050817', 'mid': '#0E1433', 'horizon': '#26305E', 'sun': [0.3, 0.5, 0.6],
                      'sun_colour': '#A9B8FF', 'sun_strength': 0.15, 'haze': '#1E2750', 'facade': '#1C2136',
                      'glass': '#101528', 'lit': 0.42, 'mtn': ['#10152E', '#1B2244'], 'world': 0.6, 'ambient': '#56608A'},
        },
        'towers': {'seed': 5, 'count': 30, 'r': [210.0, 400.0], 'bottom': -300.0},
        'cards': [[0.0, 640.0, 1500.0, 0.0], [610.0, 60.0, 1400.0, 1.0], [-610.0, 60.0, 1400.0, 2.0],
                  [470.0, 470.0, 800.0, 3.0], [-470.0, 470.0, 800.0, 4.0]],  # x, y, width, strip
        'card_z': [-160.0, 170.0],
        'deck': {'z': -40.0, 'r': 1000.0, 'segments': 24},
        'facade_studs': [48.0, 64.0],  # studs per facade texture repeat: across, up
    },
    # ---- lights (Roblox values; the preview factors turn them into Blender watts) ----------------------
    'lights': {
        'pendant': {'brightness': 2.2, 'range': 14.0, 'angle': 100.0},
        'ambient': [
            {'name': 'Light_WalkwayTray_W', 'type': 'SurfaceLight', 'position': [-45.0, -4.82, 27.9],
             'direction': [0, 0, -1], 'face_size': [80.0, 12.0], 'colour': '#FFF3D6', 'kelvin': 4000,
             'brightness': 1.2, 'range': 30.0, 'angle': 120.0, 'shadows': False},
            {'name': 'Light_WalkwayTray_E', 'type': 'SurfaceLight', 'position': [45.0, -4.82, 27.9],
             'direction': [0, 0, -1], 'face_size': [80.0, 12.0], 'colour': '#FFF3D6', 'kelvin': 4000,
             'brightness': 1.2, 'range': 30.0, 'angle': 120.0, 'shadows': False},
            {'name': 'Light_Plaza', 'type': 'PointLight', 'position': [2.0, -22.0, 15.0], 'colour': '#FFF6EA',
             'kelvin': 4500, 'brightness': 0.8, 'range': 30.0, 'shadows': True},
            {'name': 'Light_Bar', 'type': 'SurfaceLight', 'position': [23.0, -25.0, 12.0], 'direction': [0, 0, -1],
             'face_size': [3.0, 20.0], 'colour': '#FFE2B0', 'kelvin': 3300, 'brightness': 1.5, 'range': 14.0,
             'angle': 90.0, 'shadows': False},
            {'name': 'Light_Lounge_1', 'type': 'PointLight', 'position': [48.0, -30.0, 17.0], 'colour': '#FFF6EA',
             'kelvin': 4500, 'brightness': 1.0, 'range': 30.0, 'shadows': False},
            {'name': 'Light_Lounge_2', 'type': 'PointLight', 'position': [66.0, -50.0, 17.0], 'colour': '#FFF6EA',
             'kelvin': 4500, 'brightness': 1.0, 'range': 30.0, 'shadows': False},
            {'name': 'Light_Piano', 'type': 'SpotLight', 'position': [75.0, -26.0, 25.5], 'direction': [0, 0, -1],
             'colour': '#FFE2B0', 'kelvin': 3200, 'brightness': 3.0, 'range': 32.0, 'angle': 50.0, 'shadows': True},
            {'name': 'Light_CueRoom', 'type': 'SurfaceLight', 'position': [28.6, -69.0, 10.1], 'direction': [0, 0, -1],
             'face_size': [20.0, 8.0], 'colour': '#FFF3D6', 'kelvin': 4000, 'brightness': 1.5, 'range': 12.0,
             'angle': 110.0, 'shadows': False},
            {'name': 'Light_Balcony', 'type': 'PointLight', 'position': [0.0, -69.0, 20.0], 'colour': '#FFF6EA',
             'kelvin': 4500, 'brightness': 0.9, 'range': 40.0, 'shadows': False},
            {'name': 'Light_UnderBalcony_2v2', 'type': 'SurfaceLight', 'position': [-48.0, -69.0, 10.1],
             'direction': [0, 0, -1], 'face_size': [60.0, 8.0], 'colour': '#FFF3D6', 'kelvin': 4000,
             'brightness': 1.0, 'range': 12.0, 'angle': 110.0, 'shadows': False},
            {'name': 'Light_Booths', 'type': 'SurfaceLight', 'position': [63.5, -71.0, 10.1], 'direction': [0, 0, -1],
             'face_size': [40.0, 6.0], 'colour': '#FFE2B0', 'kelvin': 3300, 'brightness': 1.2, 'range': 12.0,
             'angle': 110.0, 'shadows': False},
            {'name': 'Light_Terrace', 'type': 'PointLight', 'position': [101.0, -43.0, 9.0], 'colour': '#FFD49A',
             'kelvin': 2700, 'brightness': 1.0, 'range': 30.0, 'shadows': False},
            {'name': 'Light_ProDoor', 'type': 'PointLight', 'position': [-83.5, -4.82, 8.0], 'colour': '#F0B429',
             'kelvin': 2500, 'brightness': 1.5, 'range': 16.0, 'shadows': False},
            {'name': 'Light_3v3Window', 'type': 'PointLight', 'position': [52.0, 66.0, 17.0], 'colour': '#FFF6EA',
             'kelvin': 4500, 'brightness': 0.9, 'range': 30.0, 'shadows': False},
        ],
        'preview': {'surface': 7.0, 'point': 3.0, 'spot': 4.0, 'exposure': 0.3, 'neon': 8.0},
    },
    # ---- textures ----------------------------------------------------------------------------------
    'textures': {
        'seed': 8,
        'upload': 1024,  # Roblox renders uploads at 1024 at most
        'marble': {'master': 4096, 'tiles': 4, 'tile_studs': 6.0, 'grout_px': 5, 'version': 4},
        'carpet': {'master': 4096, 'blocks': 4, 'block_studs': 6.4, 'version': 3},
        'slats': {'master': 1024, 'studs': 8.0, 'pitch_px': 128, 'slat_px': 84, 'version': 2},
        'palette': {'size': 512, 'cells': 16, 'version': 2},
        'fluted': {'size': 512, 'studs': 2.0, 'ribs': 8, 'alpha': 0.42, 'version': 2},
        'facade': {'size': 1024, 'cells': 16, 'version': 2},
        'cards': {'master': 2048, 'height': 512, 'version': 3},
    },
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
    bpy.context.view_layer.update()  # new objects have no world matrix or bounds until this
    obs = []
    for obj in walk_objects(root):
        if obj.get('hub_rects'):  # merged meshes carry their exact floor footprints
            for x0, y0, x1, y1, kind, block, zone in json.loads(obj['hub_rects']):
                obs.append({'name': obj.name + ':' + kind, 'rect': (x0, y0, x1, y1), 'kind': kind,
                            'block': block, 'zone': zone})
            continue
        if obj.get('hub_floor'):
            bb = world_aabb(obj)
            base_z = obj.matrix_world.translation.z if obj.get('hub_prop') else bb[2]
            if base_z > 0.5:  # starts above the floor: not standing on it
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
# Shared infrastructure for stages 2 to 6
# =================================================================================================
import random  # noqa: E402  (seeded generators only)
import struct  # noqa: E402
import zlib  # noqa: E402
import hashlib  # noqa: E402

import numpy as np  # noqa: E402

TEX_DIR = os.path.join(HERE, 'textures')  # upload maps (committed)
MASTER_DIR = os.path.join(TEX_DIR, 'masters')  # 4096 masters (git-ignored, rebuilt from seeds)
SKY_DIR = os.path.join(HERE, 'sky')
TEX_JSON = os.path.join(HERE, 'Textures.json')
PACKAGES = ['Hub_Architecture', 'Hub_Furniture', 'Hub_PropLibrary', 'Hub_Emissive', 'Hub_Glass',
            'Hub_Skyline', 'Hub_Screens', 'Hub_Collision']
PKG_COLL = {p: 'HUB_' + p[4:] for p in PACKAGES}
EXTRA_COLLS = ['HUB_Props', 'HUB_Preview']


def pkg_collection(name):
    return collection(name, collection(ROOT))


def clear_stage(stage):
    """Remove every object an earlier run of this stage made (tagged hub_stage)."""
    root = bpy.data.collections.get(ROOT)
    if root is None:
        return
    for obj in list(walk_objects(root)):
        if obj.get('hub_stage') == stage:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.orphans_purge(do_recursive=True)


def remove_blockout(keep=()):
    root = bpy.data.collections.get(ROOT)
    for obj in list(walk_objects(root)):
        n = obj.name
        if (n.startswith('BO_') or n.startswith('Emissive_ProDoor') or n == 'Sign_Logo_ProDoor'
                or n.startswith('COL_TerraceWall')) and not any(n.startswith(k) for k in keep):
            if obj.get('hub_stage') is None:
                bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.orphans_purge(do_recursive=True)


# ---- PNG in and out (numpy + zlib: deterministic, no image datablocks) ----------------------------
def write_png(path, arr):
    """arr: uint8, row 0 = top of the image, shape HxW or HxWxC (C = 1, 2, 3, 4)."""
    a = np.ascontiguousarray(arr, dtype=np.uint8)
    if a.ndim == 2:
        a = a[:, :, None]
    h, w, c = a.shape
    ctype = {1: 0, 2: 4, 3: 2, 4: 6}[c]
    raw = np.concatenate([np.zeros((h, 1), np.uint8), a.reshape(h, w * c)], axis=1).tobytes()

    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, ctype, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


def read_png(path):
    """Reads the PNGs this script writes (8-bit, no interlace)."""
    data = open(path, 'rb').read()
    pos, idat, w = 8, b'', None
    while pos < len(data):
        n = struct.unpack('>I', data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        if tag == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
        elif tag == b'IDAT':
            idat += body
        pos += 12 + n
    c = {0: 1, 4: 2, 2: 3, 6: 4}[ctype]
    raw = np.frombuffer(zlib.decompress(idat), np.uint8).reshape(h, w * c + 1)
    out = np.zeros((h, w * c), np.int32)
    prev = np.zeros(w * c, np.int32)
    for y in range(h):  # undo PNG filters (ours are all type 0; others kept for safety)
        ft, line = raw[y, 0], raw[y, 1:].astype(np.int32)
        if ft == 0:
            cur = line
        elif ft == 2:
            cur = (line + prev) & 255
        else:
            cur = line.copy()
            for x in range(w * c):
                a_ = cur[x - c] if x >= c else 0
                b_ = prev[x]
                cc = prev[x - c] if x >= c else 0
                if ft == 1:
                    cur[x] = (line[x] + a_) & 255
                elif ft == 3:
                    cur[x] = (line[x] + ((a_ + b_) >> 1)) & 255
                else:
                    pa, pb, pc = abs(b_ - cc), abs(a_ - cc), abs(a_ + b_ - 2 * cc)
                    pr = a_ if pa <= pb and pa <= pc else (b_ if pb <= pc else cc)
                    cur[x] = (line[x] + pr) & 255
        out[y] = cur
        prev = cur
    return out.reshape(h, w, c).astype(np.uint8)


def to_u8(a):
    return np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)


def downscale(a, size):
    """Box-filter a float HxW(xC) array so its width is `size` (height scales the same)."""
    f = a.shape[1] // size
    if f <= 1:
        return a
    h, w = a.shape[0] // f, a.shape[1] // f
    if a.ndim == 2:
        return a.reshape(h, f, w, f).mean(axis=(1, 3))
    return a.reshape(h, f, w, f, a.shape[2]).mean(axis=(1, 3))


# ---- noise ------------------------------------------------------------------------------------------
def value_noise(shape, cells, rng):
    """Tileable smooth value noise in 0..1. shape (h, w), cells (cy, cx) lattice size."""
    h, w = shape
    cy, cx = max(1, int(cells[0])), max(1, int(cells[1]))
    lat = rng.random((cy, cx)).astype(np.float32)
    ys = np.arange(h, dtype=np.float32) * cy / h
    xs = np.arange(w, dtype=np.float32) * cx / w
    y0 = np.floor(ys).astype(np.int64)
    x0 = np.floor(xs).astype(np.int64)
    fy, fx = ys - y0, xs - x0
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    y1, x1 = (y0 + 1) % cy, (x0 + 1) % cx
    y0, x0 = y0 % cy, x0 % cx
    top = lat[y0][:, x0] * (1 - fx) + lat[y0][:, x1] * fx
    bot = lat[y1][:, x0] * (1 - fx) + lat[y1][:, x1] * fx
    return top * (1 - fy[:, None]) + bot * fy[:, None]


def fbm(shape, base, octaves, rng, gain=0.5, aspect=(1.0, 1.0)):
    total = np.zeros(shape, np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        c = base * (2 ** o)
        total += amp * value_noise(shape, (c * aspect[0], c * aspect[1]), rng)
        norm += amp
        amp *= gain
    return total / norm


def box_blur(a, r, axis):
    if r < 1:
        return a
    c = np.cumsum(np.concatenate([np.take(a, range(-r - 1, 0), axis=axis), a,
                                  np.take(a, range(0, r), axis=axis)], axis=axis), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, range(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, range(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def blur(a, r, passes=3):
    """Wrapping gaussian-like blur (three box passes each way)."""
    out = a.astype(np.float32)
    for _ in range(passes):
        out = box_blur(box_blur(out, r, 0), r, 1)
    return out


def normal_map(height, strength):
    """OpenGL tangent-space normal (+Y towards the image top) from a height field (row 0 = top)."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dup = (np.roll(height, 1, axis=0) - np.roll(height, -1, axis=0)) * 0.5
    nx, ny, nz = -dx * strength, -dup * strength, np.ones_like(height)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5


def renorm(nmap):
    v = nmap * 2.0 - 1.0
    v /= np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-6)
    return v * 0.5 + 0.5


# ---- texture sets -----------------------------------------------------------------------------------
def tex_marble():
    tp = P['textures']['marble']
    n, tiles = tp['master'], tp['tiles']
    rng = np.random.default_rng(P['textures']['seed'] * 1000 + 1)
    t = n // tiles
    col = np.zeros((n, n, 3), np.float32)
    rough = np.zeros((n, n), np.float32)
    height = np.zeros((n, n), np.float32)
    base = np.array(hex_rgb('warm_marble'), np.float32)
    vein_c = np.array([0.62, 0.62, 0.63], np.float32)
    yy, xx = np.mgrid[0:t, 0:t].astype(np.float32) / t
    d_edge = np.minimum(np.minimum(np.mgrid[0:t, 0:t][0], t - 1 - np.mgrid[0:t, 0:t][0]),
                        np.minimum(np.mgrid[0:t, 0:t][1], t - 1 - np.mgrid[0:t, 0:t][1])).astype(np.float32)
    grout = np.clip(1.0 - (d_edge - tp['grout_px'] / 2.0) / 1.5, 0.0, 1.0)
    for ty in range(tiles):
        for tx in range(tiles):
            r = np.random.default_rng(int(rng.integers(1 << 31)))
            cloud = fbm((t, t), 2, 5, r)
            th = r.uniform(0, math.pi)
            s = xx * math.cos(th) + yy * math.sin(th)
            # long flowing veins: a gently warped stripe field (small warp = no closed blobs)
            warp = (fbm((t, t), 1, 6, r, gain=0.55) - 0.5) * r.uniform(0.5, 0.9)
            f = r.uniform(0.7, 1.3)
            v1 = np.abs(np.sin(math.pi * (s * f + warp)))
            vein = np.clip(1.0 - v1 / 0.03, 0, 1) ** 1.3 * r.uniform(0.3, 0.55)
            th2 = th + r.uniform(0.3, 0.8)
            s2 = xx * math.cos(th2) + yy * math.sin(th2)
            warp2 = (fbm((t, t), 2, 5, r) - 0.5) * 0.7
            v2 = np.abs(np.sin(math.pi * (s2 * f * 2.1 + warp2 + 0.37)))
            vein2 = np.clip(1.0 - v2 / 0.018, 0, 1) * r.uniform(0.1, 0.22)
            haze = np.clip(1.0 - v1 / 0.25, 0, 1) ** 2 * 0.07  # soft cloud along the main vein
            vt = np.clip(vein + vein2 + haze, 0, 0.6)
            light = 1.0 + (cloud - 0.5) * 0.05 + r.uniform(-0.012, 0.012)
            c = base[None, None, :] * light[..., None]
            c = c * (1 - vt[..., None]) + vein_c[None, None, :] * vt[..., None]
            c = c * (1 - grout[..., None]) + np.array([0.84, 0.82, 0.78])[None, None, :] * grout[..., None]
            sl = (slice(ty * t, ty * t + t), slice(tx * t, tx * t + t))
            col[sl] = c
            rough[sl] = np.clip(0.13 + vt * 0.08 + (cloud - 0.5) * 0.03, 0.12, 0.2) * (1 - grout) + 0.5 * grout
            height[sl] = -grout * 2.0 + (fbm((t, t), 64, 2, r) - 0.5) * 0.05 - vt * 0.05
    return {'Color': col, 'Roughness': rough, 'Normal': normal_map(height, 1.0)}


def tex_carpet():
    tp = P['textures']['carpet']
    n, blocks = tp['master'], tp['blocks']
    rng = np.random.default_rng(P['textures']['seed'] * 1000 + 2)
    bp = n // blocks
    pw = bp // 4  # plank width: 1.6 of 6.4 studs
    col = np.zeros((n, n, 3), np.float32)
    rough = np.zeros((n, n), np.float32)
    height = np.zeros((n, n), np.float32)
    base = np.array(hex_rgb('carpet_gray'), np.float32)
    streak_c = np.array(hex_rgb('carpet_streak'), np.float32)
    ac = np.arange(pw, dtype=np.float32)[:, None]  # across
    al = np.arange(bp, dtype=np.float32)[None, :]  # along
    loops = (0.5 + 0.5 * np.sin(2 * math.pi * al / 14.0)) * (0.5 + 0.5 * np.sin(2 * math.pi * ac / 12.0))
    seam = np.clip(1.0 - np.minimum(np.minimum(ac, pw - 1 - ac), np.minimum(al, bp - 1 - al)) / 3.0, 0, 1)
    for by in range(blocks):
        for bx in range(blocks):
            vertical = (bx + by) % 2 == 0
            for k in range(4):
                r = np.random.default_rng(int(rng.integers(1 << 31)))
                shade = r.uniform(-0.07, 0.07)
                grain = (fbm((pw, bp), 8, 4, r, aspect=(8.0, 1.0)) - 0.5)
                streak = np.zeros((pw, bp), np.float32)
                for _ in range(int(r.integers(3, 8))):
                    pos = r.uniform(4, pw - 4)
                    wid = r.uniform(1.5, 4.0)
                    prof = np.clip(1.0 - np.abs(ac - pos) / wid, 0, 1)
                    dash = value_noise((1, bp), (1, int(r.integers(6, 14))), r)
                    dash = np.clip((dash - r.uniform(0.45, 0.65)) * 6.0, 0, 1)
                    streak = np.maximum(streak, prof * dash * r.uniform(0.35, 0.95))
                fib = value_noise((pw, bp), (pw / 3, bp / 5), r)
                c = base[None, None, :] * (1.0 + shade + grain[..., None] * 0.18 + (fib[..., None] - 0.5) * 0.08)
                c = c * (1 - streak[..., None]) + streak_c[None, None, :] * streak[..., None]
                c = c * (1 - seam[..., None] * 0.25)
                h = loops * 0.6 + fib * 0.5 + grain * 0.6 - seam * 1.2 + streak * 0.2
                rgh = np.clip(0.9 + (fib - 0.5) * 0.08 - streak * 0.04, 0.85, 0.95)
                if vertical:  # plank runs down the image: along = rows
                    sl = (slice(by * bp, by * bp + bp), slice(bx * bp + k * pw, bx * bp + k * pw + pw))
                    col[sl], height[sl], rough[sl] = c.transpose(1, 0, 2), h.T, rgh.T
                else:
                    sl = (slice(by * bp + k * pw, by * bp + k * pw + pw), slice(bx * bp, bx * bp + bp))
                    col[sl], height[sl], rough[sl] = c, h, rgh
    return {'Color': col, 'Roughness': rough, 'Normal': normal_map(height, 0.9)}


def tex_slats():
    tp = P['textures']['slats']
    n, pitch, slat = tp['master'], tp['pitch_px'], tp['slat_px']
    rng = np.random.default_rng(P['textures']['seed'] * 1000 + 3)
    row = np.arange(n) % pitch
    inside = row < slat
    across = np.where(inside, (row + 0.5) / slat, 0.0)
    shade = np.where(inside, 0.82 + 0.35 * np.sin(math.pi * across) ** 2, 0.0).astype(np.float32)
    navy = np.array(hex_rgb('midnight_navy'), np.float32)
    gap = np.array([0.02, 0.025, 0.04], np.float32)
    noise = fbm((n, n), 4, 3, rng, aspect=(1.0, 0.25)) - 0.5
    s = shade[:, None] * (1.0 + noise * 0.06)
    col = np.where(inside[:, None, None], navy[None, None, :] * s[..., None], gap[None, None, :])
    rough = np.where(inside[:, None], 0.45 + noise * 0.05, 0.95).astype(np.float32)
    return {'Color': col.astype(np.float32), 'Roughness': rough}


SWATCHES = [  # palette atlas cells, row by row from the top: name, colour, roughness, metalness
    ('wall', 'cloud_white', 0.7, 0), ('accent', 'soft_sky', 0.7, 0), ('yellow', 'sunny_yellow', 0.55, 0),
    ('navy', 'midnight_navy', 0.35, 0), ('navy_gloss', 'midnight_navy', 0.1, 0), ('black_gloss', '#0B0E16', 0.08, 0),
    ('white_gloss', 'glossy_white', 0.2, 0), ('gold', 'gold', 0.25, 1), ('marble_flat', 'warm_marble', 0.16, 0),
    ('z1v1', '1v1', 0.8, 0), ('z2v2', '2v2', 0.8, 0), ('z3v3', '3v3', 0.8, 0), ('cobalt', 'cobalt', 0.8, 0),
    ('sunflower', 'sunflower', 0.8, 0), ('tangerine', 'tangerine', 0.8, 0), ('coral', 'coral', 0.75, 0),
    ('emerald', 'emerald', 0.7, 0), ('emerald_light', '#2BA866', 0.7, 0), ('side_table', '#1E2233', 0.3, 0),
    ('rubber', '#2A2D35', 0.85, 0), ('key_white', '#F7F5EF', 0.3, 0), ('fabric_white', '#F0F0F0', 0.85, 0),
    ('screen_black', '#07090D', 0.06, 0), ('planter_white', '#F4F4F2', 0.5, 0), ('chrome', '#D6D1CB', 0.12, 1),
    ('cue_wood', '#C98A4B', 0.45, 0), ('cue_dark', '#3B2416', 0.4, 0), ('white_matte', '#FAFAFA', 0.6, 0),
]
SW = {name: i for i, (name, _c, _r, _m) in enumerate(SWATCHES)}


def swatch_uv(name):
    cells = P['textures']['palette']['cells']
    i = SW[name]
    col, row = i % cells, i // cells
    return ((col + 0.5) / cells, 1.0 - (row + 0.5) / cells)


def tex_palette():
    tp = P['textures']['palette']
    n, cells = tp['size'], tp['cells']
    cp = n // cells
    col = np.ones((n, n, 3), np.float32) * 0.5
    rough = np.ones((n, n), np.float32) * 0.5
    metal = np.zeros((n, n), np.float32)
    for i, (_name, c, rgh, met) in enumerate(SWATCHES):
        cx, cy = i % cells, i // cells
        sl = (slice(cy * cp, cy * cp + cp), slice(cx * cp, cx * cp + cp))
        col[sl] = np.array(hex_rgb(c), np.float32)
        rough[sl] = rgh
        metal[sl] = met
    return {'Color': col, 'Roughness': rough, 'Metalness': metal}


def tex_fluted():
    tp = P['textures']['fluted']
    n, ribs = tp['size'], tp['ribs']
    x = (np.arange(n, dtype=np.float32) + 0.5) / n * ribs
    fr = x - np.floor(x)
    h = np.sqrt(np.clip(1.0 - (2 * fr - 1) ** 2, 0, 1))  # half-cylinder ribs, vertical
    height = np.tile(h[None, :], (n, 1)) * 6.0
    col = np.zeros((n, n, 4), np.float32)
    col[..., :3] = np.array([0.87, 0.93, 0.95], np.float32)
    col[..., 3] = tp['alpha'] + (1 - h[None, :]) * 0.12  # a touch denser in the grooves
    return {'Color': col, 'Normal': normal_map(height, 1.0)}


TEXTURE_BUILDERS = {'Marble': ('marble', tex_marble), 'Carpet': ('carpet', tex_carpet),
                    'Slats': ('slats', tex_slats), 'Palette': ('palette', tex_palette),
                    'FlutedGlass': ('fluted', tex_fluted)}


def textures_manifest():
    if os.path.exists(TEX_JSON):
        with open(TEX_JSON) as f:
            return json.load(f)
    return {}


def save_manifest(man):
    with open(TEX_JSON, 'w') as f:
        json.dump(man, f, indent=1, sort_keys=True)


def sha(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()


def ensure_textures(names, builders=None):
    """Build each named texture set unless Textures.json already records this recipe version."""
    builders = builders or TEXTURE_BUILDERS
    man = textures_manifest()
    for name in names:
        key, fn = builders[name]
        tp = P['textures'][key] if key in P['textures'] else {}
        recipe = json.dumps(tp, sort_keys=True)
        rec = man.get(name)
        files_ok = rec and all(os.path.exists(os.path.join(TEX_DIR, f)) for f in rec['files'])
        if rec and rec.get('recipe') == recipe and files_ok:
            continue
        print('HUB texture', name, '...')
        maps = fn()
        up = P['textures']['upload']
        files, masters = {}, {}
        for m, arr in maps.items():
            size = arr.shape[1]
            if size > up:
                mpath = os.path.join(MASTER_DIR, '%s_%s.png' % (name, m))
                write_png(mpath, to_u8(arr))
                masters[m] = size
                arr = downscale(arr, up)
                if m == 'Normal':
                    arr = renorm(arr)
            path = os.path.join(TEX_DIR, '%s_%s.png' % (name, m))
            write_png(path, to_u8(arr))
            files['%s_%s.png' % (name, m)] = sha(path)
        man[name] = {'recipe': recipe, 'files': files, 'masters': masters, 'size': int(min(up, max(
            a.shape[1] for a in maps.values())))}
        save_manifest(man)
    return man


# ---- materials --------------------------------------------------------------------------------------
SURFACES = {  # surface -> texture set maps (Roblox SurfaceAppearance) and preview settings
    'Marble': {'maps': ['Color', 'Roughness', 'Normal']},
    'Carpet': {'maps': ['Color', 'Roughness', 'Normal']},
    'Slats': {'maps': ['Color', 'Roughness']},
    'Palette': {'maps': ['Color', 'Roughness', 'Metalness']},
    'FlutedGlass': {'maps': ['Color', 'Normal'], 'alpha': True},
}


def load_image(filename, data):
    path = os.path.join(TEX_DIR, filename)
    img = None
    for im in bpy.data.images:
        if im.filepath and os.path.normpath(bpy.path.abspath(im.filepath)) == os.path.normpath(path):
            img = im
            break
    if img is None:
        img = bpy.data.images.load(path)
    else:
        img.reload()
    img.colorspace_settings.name = 'Non-Color' if data else 'sRGB'
    return img


def surface_material(surface, tint=None, name=None):
    """A textured preview material that shades like the Roblox SurfaceAppearance."""
    spec = SURFACES[surface]
    name = name or ('Hub_' + surface)
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
    avg = None
    for m in spec['maps']:
        node = nodes.new('ShaderNodeTexImage')
        node.image = load_image('%s_%s.png' % (surface.split('.')[0], m), m != 'Color')
        node.interpolation = 'Linear' if surface != 'Palette' else 'Closest'
        links.new(uv.outputs['UV'], node.inputs['Vector'])
        if m == 'Color':
            colour = node.outputs['Color']
            if tint is not None:
                mix = nodes.new('ShaderNodeMix')
                mix.data_type = 'RGBA'
                mix.blend_type = 'MULTIPLY'
                mix.inputs['Factor'].default_value = 1.0
                links.new(colour, socket(mix.inputs, 'A_Color', 'A'))
                socket(mix.inputs, 'B_Color', 'B').default_value = (*lin(tint), 1.0)
                colour = socket(mix.outputs, 'Result_Color', 'Result')
            links.new(colour, bsdf.inputs['Base Color'])
            if spec.get('alpha'):
                links.new(node.outputs['Alpha'], bsdf.inputs['Alpha'])
            try:
                px = np.array(node.image.pixels[:], np.float32).reshape(-1, 4)[::97]
                avg = px[:, :3].mean(axis=0)
            except Exception:
                avg = np.array([0.5, 0.5, 0.5])
        elif m == 'Roughness':
            links.new(node.outputs['Color'], bsdf.inputs['Roughness'])
        elif m == 'Metalness':
            links.new(node.outputs['Color'], bsdf.inputs['Metallic'])
        elif m == 'Normal':
            nm = nodes.new('ShaderNodeNormalMap')
            nm.uv_map = 'UVMap'
            links.new(node.outputs['Color'], nm.inputs['Color'])
            links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    if spec.get('alpha'):
        try:
            mat.surface_render_method = 'BLENDED'
        except (AttributeError, TypeError):
            pass
    if 'Roughness' not in spec['maps']:  # glass is glossy; signs are matte (no glare on the text)
        bsdf.inputs['Roughness'].default_value = 0.05 if spec.get('alpha') else 0.6
    if avg is not None:
        mat.diffuse_color = (float(avg[0]), float(avg[1]), float(avg[2]), 1.0)
    mat['hub_surface'] = surface
    return mat


def neon_material(name, colour, strength=4.0):
    mat = material('Hub_Neon_' + name, colour, 0.5, emit=strength)
    mat['hub_surface'] = 'Neon'
    return mat


def glass_material():
    mat = material('Hub_Glass', '#CFE8F2', 0.04, alpha=0.2)
    mat['hub_surface'] = 'Glass'
    return mat


def screen_material():
    mat = material('Hub_ScreenOff', '#07090D', 0.06)
    mat['hub_surface'] = 'Screen'
    return mat


# ---- geometry batches -------------------------------------------------------------------------------
class Batch:
    """Accumulates polygons for one mesh (one material). UVs: 'palette' swatches, 'world' planar
    tiling (studs per texture repeat), or explicit per-polygon UVs."""

    def __init__(self, name, surface, coll, stage, uv='palette', studs=1.0, offset=(0.0, 0.0),
                 material=None, limit=9000, props=None):
        self.name, self.surface, self.coll, self.stage = name, surface, coll, stage
        self.uvmode, self.studs, self.offset = uv, studs, offset
        self.material, self.limit = material, limit
        self.v, self.f, self.uv, self.sm = [], [], [], []
        self.rects = []
        self.props = props or {}

    # -- primitives
    def poly(self, pts, sw=None, uvs=None, smooth=False):
        if len(pts) < 3:
            return
        base = len(self.v)
        self.v.extend([tuple(p) for p in pts])
        self.f.append(tuple(range(base, base + len(pts))))
        if uvs is None:
            if self.uvmode == 'palette':
                u = swatch_uv(sw or 'wall')
                uvs = [u] * len(pts)
            elif self.uvmode == 'world':
                uvs = self.world_uv(pts)
            else:
                uvs = [(0.0, 0.0)] * len(pts)
        self.uv.append(list(uvs))
        self.sm.append(smooth)

    def world_uv(self, pts):
        nx, ny, nz = poly_normal(pts)
        s, (ou, ov) = self.studs, self.offset
        ax = max((abs(nx), 0), (abs(ny), 1), (abs(nz), 2))[1]
        out = []
        for x, y, z in pts:
            if ax == 2:
                out.append((x / s + ou, y / s + ov))
            elif ax == 0:
                out.append(((y if nx > 0 else -y) / s + ou, z / s + ov))
            else:
                out.append(((-x if ny > 0 else x) / s + ou, z / s + ov))
        return out

    def quad_z(self, x0, y0, x1, y1, z, sw=None, down=False):
        pts = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
        self.poly(pts[::-1] if down else pts, sw)

    def rect(self, x0, y0, x1, y1, kind, block=True, zone=''):
        self.rects.append([min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1), kind, bool(block), zone])

    def box(self, x0, y0, z0, x1, y1, z1, sw='wall', faces=None, chamfer=0.0, sw_edge=None, kind=None,
            block=True, zone=''):
        x0, x1 = min(x0, x1), max(x0, x1)
        y0, y1 = min(y0, y1), max(y0, y1)
        if kind:
            self.rect(x0, y0, x1, y1, kind, block, zone)
        if chamfer > 0:
            return self.chamfer_box(x0, y0, z0, x1, y1, z1, chamfer, sw, sw_edge or sw)
        F = {'-z': [(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)],
             '+z': [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
             '-y': [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
             '+y': [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)],
             '-x': [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)],
             '+x': [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)]}
        for key, pts in F.items():
            if faces is None or key in faces:
                self.poly(pts, sw)

    def chamfer_box(self, x0, y0, z0, x1, y1, z1, c, sw, sw_edge):
        c = min(c, (x1 - x0) / 2.01, (y1 - y0) / 2.01, (z1 - z0) / 2.01)
        cen = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        pts = {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    X, Y, Z = (x1 if sx > 0 else x0), (y1 if sy > 0 else y0), (z1 if sz > 0 else z0)
                    pts[(sx, sy, sz)] = {'x': (X, Y - sy * c, Z - sz * c), 'y': (X - sx * c, Y, Z - sz * c),
                                         'z': (X - sx * c, Y - sy * c, Z)}

        def add(poly_pts, s):
            nrm = poly_normal(poly_pts)
            ctr = [sum(p[i] for p in poly_pts) / len(poly_pts) for i in range(3)]
            if sum(nrm[i] * (ctr[i] - cen[i]) for i in range(3)) < 0:
                poly_pts = poly_pts[::-1]
            self.poly(poly_pts, s)
        # the six faces
        for axis, idx in (('x', 0), ('y', 1), ('z', 2)):
            for sgn in (-1, 1):
                corners = [k for k in pts if k[idx] == sgn]
                ring = sorted(corners, key=lambda k: math.atan2(*[k[i] for i in range(3) if i != idx][::-1]))
                add([pts[k][axis] for k in ring], sw)
        # twelve edges
        for idx in range(3):
            others = [i for i in range(3) if i != idx]
            for s1 in (-1, 1):
                for s2 in (-1, 1):
                    ka, kb = [0, 0, 0], [0, 0, 0]
                    ka[idx], kb[idx] = -1, 1
                    ka[others[0]] = kb[others[0]] = s1
                    ka[others[1]] = kb[others[1]] = s2
                    ka, kb = tuple(ka), tuple(kb)
                    a1, a2 = 'xyz'[others[0]], 'xyz'[others[1]]
                    add([pts[ka][a1], pts[kb][a1], pts[kb][a2], pts[ka][a2]], sw_edge)
        # eight corners
        for k, p in pts.items():
            add([p['x'], p['y'], p['z']], sw_edge)

    def prism(self, outline, z0, z1, sw='wall', sw_top=None, top=True, bottom=False, smooth_sides=False):
        """Vertical extrusion of a closed CCW outline [(x, y), ...]."""
        n = len(outline)
        for i in range(n):
            (ax, ay), (bx, by) = outline[i], outline[(i + 1) % n]
            self.poly([(ax, ay, z0), (bx, by, z0), (bx, by, z1), (ax, ay, z1)], sw, smooth=smooth_sides)
        if top:
            self.poly([(x, y, z1) for x, y in outline], sw_top or sw)
        if bottom:
            self.poly([(x, y, z0) for x, y in reversed(outline)], sw)

    def cylinder(self, cx, cy, r, z0, z1, segs=16, sw='wall', sw_top=None, top=True, bottom=False):
        ring = [(cx + r * math.cos(2 * math.pi * i / segs), cy + r * math.sin(2 * math.pi * i / segs))
                for i in range(segs)]
        self.prism(ring, z0, z1, sw, sw_top, top, bottom, smooth_sides=True)

    def disk(self, cx, cy, r, z, segs=16, sw='wall', down=False):
        ring = [(cx + r * math.cos(2 * math.pi * i / segs), cy + r * math.sin(2 * math.pi * i / segs), z)
                for i in range(segs)]
        self.poly(ring[::-1] if down else ring, sw)

    def annulus(self, cx, cy, r0, r1, z, segs=32, sw='wall'):
        for i in range(segs):
            a, b = 2 * math.pi * i / segs, 2 * math.pi * (i + 1) / segs
            self.poly([(cx + r0 * math.cos(a), cy + r0 * math.sin(a), z), (cx + r1 * math.cos(a), cy + r1 * math.sin(a), z),
                       (cx + r1 * math.cos(b), cy + r1 * math.sin(b), z), (cx + r0 * math.cos(b), cy + r0 * math.sin(b), z)], sw)

    def tris(self):
        return sum(len(f) - 2 for f in self.f)

    # -- output
    def emit(self):
        if not self.f:
            return []
        groups = [list(range(len(self.f)))]
        if self.tris() > self.limit:  # split along the longer horizontal axis until each fits
            groups = split_faces(self, groups[0])
        objs = []
        coll = pkg_collection(self.coll)
        mat = self.material or surface_material(self.surface)
        for gi, g in enumerate(groups):
            name = self.name if len(groups) == 1 else '%s_%02d' % (self.name, gi + 1)
            used = sorted({vi for fi in g for vi in self.f[fi]})
            remap = {vi: k for k, vi in enumerate(used)}
            verts = [self.v[vi] for vi in used]
            faces = [tuple(remap[vi] for vi in self.f[fi]) for fi in g]
            me = bpy.data.meshes.new(name)
            me.from_pydata(verts, [], faces)
            uvl = me.uv_layers.new(name='UVMap')
            flat = [c for fi in g for uv in self.uv[fi] for c in uv]
            uvl.data.foreach_set('uv', flat)
            sm = [self.sm[fi] for fi in g]
            me.polygons.foreach_set('use_smooth', sm)
            me.validate(clean_customdata=False)
            me.update()
            me.materials.append(mat)
            obj = bpy.data.objects.new(name, me)
            coll.objects.link(obj)
            obj['hub_stage'] = self.stage
            obj['hub_owned'] = 1
            obj['hub_surface'] = self.surface
            obj['hub_package'] = [k for k, v in PKG_COLL.items() if v == self.coll][0] if self.coll in PKG_COLL.values() else ''
            for k, v in self.props.items():
                obj[k] = v
            if self.rects:
                mine = self.rects if len(groups) == 1 else [r_ for r_ in self.rects if rect_in_group(r_, verts)]
                if mine:
                    obj['hub_rects'] = json.dumps(mine)
                    obj['hub_floor'] = 1
            objs.append(obj)
        return objs


def rect_in_group(r_, verts):
    cx, cy = (r_[0] + r_[2]) / 2, (r_[1] + r_[3]) / 2
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    return min(xs) - 1e-3 <= cx <= max(xs) + 1e-3 and min(ys) - 1e-3 <= cy <= max(ys) + 1e-3


def split_faces(batch, faces):
    tri = lambda fi: len(batch.f[fi]) - 2  # noqa: E731
    if sum(tri(fi) for fi in faces) <= batch.limit:
        return [faces]
    cents = {fi: tuple(sum(batch.v[vi][k] for vi in batch.f[fi]) / len(batch.f[fi]) for k in range(2))
             for fi in faces}
    xs = [c[0] for c in cents.values()]
    ys = [c[1] for c in cents.values()]
    axis = 0 if (max(xs) - min(xs)) >= (max(ys) - min(ys)) else 1
    order = sorted(faces, key=lambda fi: cents[fi][axis])
    half, acc, cut = sum(tri(fi) for fi in faces) / 2, 0, 0
    for i, fi in enumerate(order):
        acc += tri(fi)
        if acc >= half:
            cut = i + 1
            break
    return split_faces(batch, order[:cut]) + split_faces(batch, order[cut:])


def poly_normal(pts):
    nx = ny = nz = 0.0
    n = len(pts)
    for i in range(n):
        x0_, y0_, z0_ = pts[i]
        x1_, y1_, z1_ = pts[(i + 1) % n]
        nx += (y0_ - y1_) * (z0_ + z1_)
        ny += (z0_ - z1_) * (x0_ + x1_)
        nz += (x0_ - x1_) * (y0_ + y1_)
    ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return (nx / ln, ny / ln, nz / ln)


class Batches:
    def __init__(self, stage):
        self.stage, self.items = stage, {}

    def get(self, name, surface='Palette', coll='HUB_Architecture', **kw):
        if name not in self.items:
            self.items[name] = Batch(name, surface, coll, self.stage, **kw)
        return self.items[name]

    def emit(self):
        out = []
        for b in self.items.values():
            out += b.emit()
        return out


def col_box(name, x0, y0, z0, x1, y1, z1, stage, shape='Box', kind=None):
    """A hidden collision box (or wedge) as its own mesh: exported to Hub_Collision and listed in
    Markers.json so Roblox can build plain Parts from the data instead."""
    b = Batch(name, 'Collision', 'HUB_Collision', stage, material=material('Hub_Collision', '#FF00FF', 1.0, alpha=0.2))
    if shape == 'Box':
        b.box(x0, y0, z0, x1, y1, z1, 'wall')
    objs = b.emit()
    for o in objs:
        o['hub_col_shape'] = shape
        o['hub_col'] = json.dumps([x0, y0, z0, x1, y1, z1])
        o.hide_render = True
        o.display_type = 'WIRE'
    return objs


def col_ramp(name, x0, x1, y_low, y_high, z_low, z_high, stage):
    """A wedge ramp proxy for a stair: rises from (y_low, z_low) to (y_high, z_high)."""
    b = Batch(name, 'Collision', 'HUB_Collision', stage, material=material('Hub_Collision', '#FF00FF', 1.0, alpha=0.2))
    v = [(x0, y_low, z_low), (x1, y_low, z_low), (x1, y_high, z_low), (x0, y_high, z_low),
         (x0, y_high, z_high), (x1, y_high, z_high)]
    for f in ([0, 3, 2, 1], [0, 1, 5, 4], [3, 4, 5, 2], [0, 4, 3], [1, 2, 5]):
        pts = [v[i] for i in f]
        b.poly(pts, 'wall')
    objs = b.emit()
    for o in objs:
        o['hub_col_shape'] = 'Wedge'
        o['hub_col'] = json.dumps([x0, min(y_low, y_high), z_low, x1, max(y_low, y_high), z_high])
        o['hub_col_rise_towards'] = '+Y' if y_high > y_low else '-Y'
        o.hide_render = True
        o.display_type = 'WIRE'
    return objs


# =================================================================================================
# Stage 2: architecture and materials
# =================================================================================================
def stage_architecture():
    scene = hub_scene()
    L = layout()
    ensure_textures(['Marble', 'Carpet', 'Slats', 'Palette', 'FlutedGlass'])
    for name in PKG_COLL.values():
        pkg_collection(name)
    for name in EXTRA_COLLS:
        pkg_collection(name)
    remove_blockout(keep=('BO_Seats_', 'BO_Light', 'BO_DuskSun'))
    clear_stage(2)
    r, b, a = P['room'], P['balcony'], P['arch']
    x0, x1, y0, y1, H = r['x0'], r['x1'], r['y0'], r['y1'], r['ceiling']
    w, t = r['wall'], P['partition']['t']
    bf, pf = L['balcony_front'], L['prow_front']
    px0, px1 = L['prow_x']
    sx0, sx1 = L['stair_x']
    tx0, tx1 = L['seats_x']
    foot = L['stair_foot_y']
    walk_s, walk_n = L['walk_s'], L['walk_n']
    walk_c = (walk_s + walk_n) / 2
    xp13 = L['x_part_13']
    bz, bs = b['z'], b['slab']
    head = a['window_head']
    band0, band1 = a['band']
    led = a['led_w']
    R = a['corner_radius']
    te = P['terrace']
    ty0, ty1 = te['y']
    dy0, dy1 = te['door_y']
    tex0, tex1 = x1 + w, x1 + w + te['depth']
    B = Batches(2)
    marble = B.get('Arch_Floor_Marble', 'Marble', uv='world', studs=P['textures']['marble']['tiles'] *
                   P['textures']['marble']['tile_studs'])
    carpet = B.get('Arch_Floor_Carpet', 'Carpet', uv='world', studs=P['textures']['carpet']['blocks'] *
                   P['textures']['carpet']['block_studs'])
    inlay = B.get('Arch_Floor_Inlays')
    walls = B.get('Arch_Walls')
    frames = B.get('Arch_Frames')
    ceil = B.get('Arch_Ceiling')
    slats = B.get('Arch_Ceiling_Slats', 'Slats', uv='world', studs=P['textures']['slats']['studs'])
    balc = B.get('Arch_Balcony')
    stair = B.get('Arch_Stair')
    rooms = B.get('Arch_Rooms')
    terr = B.get('Arch_Terrace')
    glass_m = glass_material()
    gwin = B.get('Glass_Windows', 'Glass', 'HUB_Glass', material=glass_m)
    gpart = B.get('Glass_Partitions', 'Glass', 'HUB_Glass', material=glass_m)
    gcue = B.get('Glass_CueRoom', 'Glass', 'HUB_Glass', material=glass_m)
    warm = P['palette']['warm_led']
    E = {k: B.get('Emissive_' + k, 'Neon', 'HUB_Emissive', material=neon_material(k, c), props={'hub_neon': c})
         for k, c in (('LED_Ceiling', warm), ('Downlights', warm), ('LED_Tray', warm), ('LED_Balcony', warm),
                      ('Zone_1v1', P['palette']['1v1']), ('Zone_2v2', P['palette']['2v2']),
                      ('Zone_3v3', P['palette']['3v3']), ('ProDoor', P['palette']['gold']))}

    # ---- floors: marble where people walk, carpet where people play ---------------------------
    marble.quad_z(x0, L['y_part_2n'], x1, walk_n, 0.0)
    marble.quad_z(sx0, foot, x1, L['y_part_2n'], 0.0)
    marble.quad_z(tx1, pf, x1, foot, 0.0)
    marble.quad_z(tx1, bf, px1, pf, 0.0)
    marble.quad_z(px1, y0, x1, pf, 0.0)
    marble.quad_z(tex0, ty0, tex1, ty1, 0.0)  # terrace
    marble.quad_z(x0, y0, x1, bf, bz)  # balcony
    marble.quad_z(px0, bf, px1, pf, bz)  # prow
    carpet.offset = (0.0, 0.0)
    carpet.quad_z(x0, walk_n, xp13, y1, 0.0)
    carpet.quad_z(x0, y0, L['x_part_2e'], L['y_part_2n'], 0.0)
    carpet.quad_z(xp13 + t, walk_n, x1, y1, 0.0)
    # zone inlay stripes, cut into the carpet (0.004 proud: no z-fighting in Roblox)
    zi = 0.004
    inlay.quad_z(x0, walk_n + 0.4, xp13, walk_n + 1.2, zi, 'z1v1')
    inlay.quad_z(xp13 - 1.2, walk_n + 1.2, xp13 - 0.4, y1 - 3.5, zi, 'z1v1')
    inlay.quad_z(x0 + 3.2, L['y_part_2n'] - 1.2, L['x_2v2_seat'] - 1.0, L['y_part_2n'] - 0.4, zi, 'z2v2')
    inlay.quad_z(L['x_2v2_seat'] - 1.0, bf - 3.5, L['x_2v2_seat'] - 0.2, L['y_part_2n'] - 0.4, zi, 'z2v2')
    y3s = L['y_part_3s'] + t + P['seat_depth'] + 0.3
    inlay.quad_z(xp13 + t, y3s, x1, y3s + 0.8, zi, 'z3v3')
    inlay.quad_z(xp13 + t + 0.4, y3s + 0.8, xp13 + t + 1.2, y1 - 3.5, zi, 'z3v3')

    # ---- outer walls, windows, curved corners -----------------------------------------------------
    def window_run(horizontal, fixed, a0, a1, inward, door=None):
        """Full-height glass from the sill to the head; mullions; head with the yellow band."""
        o_in, o_out = fixed, fixed - inward * w

        def bx(batch, s0, s1, z0, z1, sw, t0=None, t1=None, kind=None):
            t0 = o_in if t0 is None else t0
            t1 = o_out if t1 is None else t1
            if horizontal:
                batch.box(s0, t0, z0, s1, t1, z1, sw, kind=kind)
            else:
                batch.box(t0, s0, z0, t1, s1, z1, sw, kind=kind)
        bx(frames, a0, a1, 0.0, win['sill'], 'navy', kind='wall')
        bx(walls, a0, a1, head, H, 'wall')
        bi = fixed + inward * 0.02  # the band sits a hair proud of the head
        bx(walls, a0, a1, band0, band1, 'yellow', bi, fixed)
        gm = fixed - inward * w / 2
        gt = a['glass_t'] / 2
        bx(gwin, a0, a1, win['sill'], head, 'wall', gm - gt, gm + gt)
        n = max(1, int(round((a1 - a0) / win['mullion_every'])))
        mw = win['mullion_w'] / 2
        for i in range(n + 1):
            s = a0 + (a1 - a0) * i / n
            bx(frames, max(a0, s - mw), min(a1, s + mw), win['sill'], head, 'navy',
               fixed + inward * 0.15, o_out)
    win = P['window']
    window_run(True, y1, x0 + R, x1 - R, -1)
    window_run(False, x0, y0, walk_c - P['pro_door']['panel'] / 2, 1)
    window_run(False, x0, walk_c + P['pro_door']['panel'] / 2, y1 - R, 1)
    window_run(False, x1, y0, dy0, -1)
    window_run(False, x1, dy1, y1 - R, -1)
    # terrace doorway: open (the doors slide into the wall), glass transom above
    walls.box(x1, dy0, 12.0, x1 + w, dy1, 12.6, 'navy')
    gwin.box(x1 + w / 2 - a['glass_t'] / 2, dy0, 12.6, x1 + w / 2 + a['glass_t'] / 2, dy1, head, 'wall')
    walls.box(x1, dy0, head, x1 + w, dy1, H, 'wall')
    walls.box(x1 - 0.02, dy0, band0, x1, dy1, band1, 'yellow')
    for yy in (dy0, dy1):
        frames.box(x1 - 0.2, yy - 0.4, 0.0, x1 + w + 0.2, yy + 0.4, 12.6, 'navy', kind='wall')
    # curved corners (NW and NE): the band sweeps round them
    segs = a['corner_segments']
    for cx, cy, a_start in ((x0 + R, y1 - R, math.pi / 2), (x1 - R, y1 - R, 0.0)):
        pts = [(cx + R * math.cos(a_start + (math.pi / 2) * i / segs), cy + R * math.sin(a_start + (math.pi / 2) * i / segs))
               for i in range(segs + 1)]
        for i in range(segs):
            (ax_, ay_), (bx_, by_) = pts[i], pts[i + 1]
            for z0_, z1_, sw in ((0.0, band0, 'wall'), (band0, band1, 'yellow'), (band1, H, 'wall')):
                walls.poly([(bx_, by_, z0_), (ax_, ay_, z0_), (ax_, ay_, z1_), (bx_, by_, z1_)], sw)
            walls.rect(min(ax_, bx_), min(ay_, by_), max(ax_, bx_), max(ay_, by_), 'wall')
        # skirting in navy like the window curbs
        for i in range(segs):
            (ax_, ay_), (bx_, by_) = pts[i], pts[i + 1]
            walls.poly([(bx_, by_, 0.0), (ax_, ay_, 0.0), (ax_, ay_, 0.6), (bx_, by_, 0.6)], 'navy')
    # south wall: white, the band, soft-sky accent under the balcony
    walls.poly([(x1, y0, 0.0), (x0, y0, 0.0), (x0, y0, band0), (x1, y0, band0)][::-1], 'wall')
    walls.poly([(x0, y0 + 0.02, band0), (x1, y0 + 0.02, band0), (x1, y0 + 0.02, band1), (x0, y0 + 0.02, band1)], 'yellow')
    walls.poly([(x0, y0, band1), (x1, y0, band1), (x1, y0, H), (x0, y0, H)], 'wall')
    walls.rect(x0, y0 - w, x1, y0, 'wall')
    for xa, xb in ((x0, sx0), (L['cue_x'][1] + 1.2, x1)):
        walls.poly([(xa, y0 + 0.03, 0.6), (xb, y0 + 0.03, 0.6), (xb, y0 + 0.03, bz - bs), (xa, y0 + 0.03, bz - bs)], 'accent')
        walls.poly([(xa, y0 + 0.03, 0.0), (xb, y0 + 0.03, 0.0), (xb, y0 + 0.03, 0.6), (xa, y0 + 0.03, 0.6)], 'navy')
    # the pro lobby door: soft-sky wall panel, locked door, glowing frame, blank sign
    pd = P['pro_door']
    pa, pb_ = walk_c - pd['panel'] / 2, walk_c + pd['panel'] / 2
    walls.box(x0 - w, pa, 0.0, x0, pb_, H, 'accent', kind='wall')
    walls.box(x0 - 0.01, pa, band0, x0 + 0.02, pb_, band1, 'yellow')
    da, db = walk_c - pd['w'] / 2, walk_c + pd['w'] / 2
    rooms.box(x0 - 0.3, da, 0.0, x0 + 0.1, db, pd['h'], 'navy_gloss', chamfer=0.1)
    rooms.box(x0 + 0.1, walk_c - 0.9, 6.5, x0 + 0.45, walk_c - 0.55, 9.5, 'gold', chamfer=0.08)
    rooms.box(x0 + 0.1, walk_c + 0.55, 6.5, x0 + 0.45, walk_c + 0.9, 9.5, 'gold', chamfer=0.08)
    fr = pd['frame']
    E['ProDoor'].box(x0, da - fr, 0.0, x0 + 0.35, da, pd['h'] + fr, 'wall')
    E['ProDoor'].box(x0, db, 0.0, x0 + 0.35, db + fr, pd['h'] + fr, 'wall')
    E['ProDoor'].box(x0, da - fr, pd['h'], x0 + 0.35, db + fr, pd['h'] + fr, 'wall')
    rooms.box(x0, da - 0.3, pd['h'] + 1.3, x0 + 0.25, db + 0.3, pd['h'] + 4.9, 'white_gloss', chamfer=0.08)

    # ---- ceiling: white ceiling, raised tray over the walkway, slat fields, bulkheads, beams ------
    ceil.quad_z(x0, y0, x1, walk_s, H, 'wall', down=True)
    ceil.quad_z(x0, walk_n, x1, y1, H, 'wall', down=True)
    tt = a['tray_top']
    ceil.quad_z(x0, walk_s, x1, walk_n, tt, 'navy', down=True)
    ceil.poly([(x0, walk_s, H), (x1, walk_s, H), (x1, walk_s, tt), (x0, walk_s, tt)], 'wall')
    ceil.poly([(x1, walk_n, H), (x0, walk_n, H), (x0, walk_n, tt), (x1, walk_n, tt)], 'wall')
    E['LED_Tray'].box(x0, walk_s, H - 0.25, x1, walk_s + led + 0.05, H, 'wall', faces={'-z', '+y'})
    E['LED_Tray'].box(x0, walk_n - led - 0.05, H - 0.25, x1, walk_n, H, 'wall', faces={'-z', '-y'})
    E['LED_Tray'].box(x0, walk_s + 1.0, tt - 0.05, x1, walk_s + 1.0 + led, tt, 'wall', faces={'-z'})
    E['LED_Tray'].box(x0, walk_n - 1.0 - led, tt - 0.05, x1, walk_n - 1.0, tt, 'wall', faces={'-z'})
    fields = {
        '1v1': (x0, xp13, walk_n, y1),
        '2v2': (x0, L['x_part_2e'], bf, L['y_part_2n']),
        '3v3': (xp13 + t, x1, walk_n, y1),
    }
    bw, bb = a['bulkhead_w'], a['bulkhead_bottom']
    for zone, (fx0, fx1, fy0, fy1) in fields.items():
        iw, ie, is_, in_ = a['slat_inset'][zone]
        sx_0, sx_1, sy_0, sy_1 = fx0 + iw, fx1 - ie, fy0 + is_ + bw, fy1 - in_ - bw
        slats.quad_z(sx_0, sy_0, sx_1, sy_1, H - 0.03, down=True)
        # bulkheads on the long sides (north and south of the field), ref_01
        for yb0, yb1, inner in ((sy_0 - bw, sy_0, sy_0), (sy_1, sy_1 + bw, sy_1)):
            ceil.box(sx_0, yb0, bb, sx_1, yb1, H - 0.01, 'wall', faces={'-z', '+y', '-y', '-x', '+x'})
            edge = inner + (0.35 if inner == sy_0 else -0.35 - led) - (0.0 if inner == sy_0 else 0.0)
            ly0 = inner - 0.35 - led if inner == sy_0 else inner + 0.35
            E['LED_Ceiling'].box(sx_0 + 0.5, ly0, bb - 0.03, sx_1 - 0.5, ly0 + led, bb, 'wall', faces={'-z'})
            zy = inner + (0.02 if inner == sy_0 else -0.02)
            face_y = inner
            if inner == sy_0:
                E['Zone_' + zone].poly([(sx_0 + 0.5, zy, bb + 0.4), (sx_1 - 0.5, zy, bb + 0.4),
                                        (sx_1 - 0.5, zy, bb + 0.4 + led), (sx_0 + 0.5, zy, bb + 0.4 + led)])
            else:
                E['Zone_' + zone].poly([(sx_1 - 0.5, zy, bb + 0.4), (sx_0 + 0.5, zy, bb + 0.4),
                                        (sx_0 + 0.5, zy, bb + 0.4 + led), (sx_1 - 0.5, zy, bb + 0.4 + led)])
            del edge, face_y
            n_ = int((sx_1 - sx_0) // a['downlight_every'])
            ymid = (yb0 + yb1) / 2 + (0.6 if inner == sy_0 else -0.6)
            for i in range(n_):
                xx = sx_0 + (i + 0.5) * (sx_1 - sx_0) / n_
                E['Downlights'].disk(xx, ymid, a['downlight_r'], bb - 0.02, 8, down=True)
        # a handful of real beams across the slats
        nb = max(1, int((sx_1 - sx_0) // a['beam_every']))
        for i in range(1, nb + 1):
            xx = sx_0 + i * (sx_1 - sx_0) / (nb + 1)
            ceil.box(xx - a['beam_w'] / 2, sy_0, H - a['beam_depth'], xx + a['beam_w'] / 2, sy_1, H - 0.02,
                     'navy', faces={'-z', '+x', '-x'})
    # downlights on the plain ceiling over the plaza, lounge and balcony
    for xx in np.arange(sx0 + 5.0, x1 - 2.0, 10.0):
        for yy in np.arange(y0 + 5.0, walk_s - 2.0, 10.0):
            E['Downlights'].disk(float(xx), float(yy), a['downlight_r'], H - 0.02, 8, down=True)
    for xx in np.arange(x0 + 5.0, sx0 - 2.0, 10.0):
        E['Downlights'].disk(float(xx), y0 + 6.0, a['downlight_r'], H - 0.02, 8, down=True)

    # ---- glass partitions with black frames ------------------------------------------------------
    ph, fw = P['partition']['h'], a['frame']

    def partition(horizontal, fixed, s0, s1, name):
        gt = a['glass_t'] / 2
        mid = fixed + t / 2

        def bx(batch, a0, a1, z0, z1, sw, th0, th1, kind=None, chamfer=0.0):
            if horizontal:
                batch.box(a0, th0, z0, a1, th1, z1, sw, kind=kind, chamfer=chamfer)
            else:
                batch.box(th0, a0, z0, th1, a1, z1, sw, kind=kind, chamfer=chamfer)
        bx(frames, s0, s1, 0.0, fw, 'navy', fixed, fixed + t, kind='partition')
        bx(frames, s0, s1, ph - fw, ph, 'navy', fixed, fixed + t, chamfer=0.06)
        n = max(1, int(math.ceil((s1 - s0) / a['partition_post_every'])))
        for i in range(n + 1):
            s = s0 + (s1 - s0) * i / n
            bx(frames, max(s0, s - fw / 2), min(s1, s + fw / 2), fw, ph - fw, 'navy', fixed, fixed + t)
        bx(gpart, s0, s1, fw, ph - fw, 'wall', mid - gt, mid + gt)
    for s0, s1 in L['part_2n_segs']:
        partition(True, L['y_part_2n'], s0, s1, '2v2N')
    for s0, s1 in L['part_2e_segs']:
        partition(False, L['x_part_2e'], s0, s1, '2v2E')
    partition(False, xp13, walk_n, y1, '1v1_3v3')
    for s0, s1 in L['part_3s_segs']:
        partition(True, L['y_part_3s'], s0, s1, '3v3S')

    # ---- columns: glossy black glass cladding, gold edges and caps --------------------------------
    cols = [(cx - b['column'] / 2, bf - 0.2 - b['column'], b['column'], bz - bs) for cx in balcony_columns(L)]
    cols += [(c[0], c[1], c[2], H) for c in a['columns']]
    for cx0, cy0, size, top in cols:
        ch = a['column_chamfer'] * size / 1.6
        rooms.box(cx0, cy0, 0.3, cx0 + size, cy0 + size, top - 0.3, 'navy_gloss', chamfer=ch, sw_edge='gold',
                  kind='column')
        rooms.box(cx0 - 0.1, cy0 - 0.1, 0.0, cx0 + size + 0.1, cy0 + size + 0.1, 0.3, 'gold')
        rooms.box(cx0 - 0.1, cy0 - 0.1, top - 0.3, cx0 + size + 0.1, cy0 + size + 0.1, top, 'gold')

    # ---- balcony: slab, fascia with LED, solid-faced railing with gold cap --------------------------
    balc.quad_z(x0, y0, x1, bf, bz - bs, 'wall', down=True)
    balc.quad_z(px0, bf, px1, pf, bz - bs, 'wall', down=True)
    balc.poly([(x0, bf, bz - bs), (px0, bf, bz - bs), (px0, bf, bz), (x0, bf, bz)], 'white_gloss')
    balc.poly([(px1, bf, bz - bs), (x1, bf, bz - bs), (x1, bf, bz), (px1, bf, bz)], 'white_gloss')
    balc.poly([(px0, pf, bz - bs), (px1, pf, bz - bs), (px1, pf, bz), (px0, pf, bz)], 'white_gloss')
    balc.poly([(px1, bf, bz - bs), (px1, pf, bz - bs), (px1, pf, bz), (px1, bf, bz)][::-1], 'white_gloss')
    balc.poly([(px0, pf, bz - bs), (px0, bf, bz - bs), (px0, bf, bz), (px0, pf, bz)][::-1], 'white_gloss')
    el = E['LED_Balcony']
    el.box(x0, bf, bz - bs, px0, bf + 0.05, bz - bs + led, 'wall', faces={'+y', '-z'})
    el.box(px1, bf, bz - bs, x1, bf + 0.05, bz - bs + led, 'wall', faces={'+y', '-z'})
    el.box(px0, pf, bz - bs, px1, pf + 0.05, bz - bs + led, 'wall', faces={'+y', '-z'})
    rt, rh, cap = b['rail_t'], b['rail_h'], a['rail_cap']
    rails = [(x0, bf - rt, px0, bf), (px1, bf - rt, x1, bf), (px0, bf, px0 + rt, pf),
             (px1 - rt, bf, px1, pf), (tx1, pf - rt, px1 - rt, pf)]
    for ra in rails:
        balc.box(ra[0], ra[1], bz, ra[2], ra[3], bz + rh - cap, 'white_gloss', chamfer=0.08)
        balc.box(ra[0] - 0.1, ra[1] - 0.1, bz + rh - cap, ra[2] + 0.1, ra[3] + 0.1, bz + rh, 'gold', chamfer=0.1)
    # under-balcony downlights
    for xx in np.arange(x0 + 4.0, x1 - 2.0, 8.0):
        if sx0 - 1 < xx < px1 + 1:
            continue
        E['Downlights'].disk(float(xx), (y0 + bf) / 2, a['downlight_r'], bz - bs - 0.02, 8, down=True)

    # ---- the spawn stair, balustrade, stair seats with cushions -------------------------------------
    st, ss = P['stair'], P['stair_seats']
    for k in range(1, st['steps'] + 1):
        ya, yb = foot - k * st['run'], foot - (k - 1) * st['run']
        zt = k * st['rise']
        marble.quad_z(sx0, ya, sx1, yb, zt)
        stair.poly([(sx0, yb, zt - st['rise']), (sx1, yb, zt - st['rise']), (sx1, yb, zt - 0.25), (sx0, yb, zt - 0.25)],
                   'white_gloss')
        stair.poly([(sx0, yb, zt - 0.25), (sx1, yb, zt - 0.25), (sx1, yb, zt), (sx0, yb, zt)], 'gold')
    stair.rect(sx0, pf, sx1, foot, 'stair')
    # the balustrade on the west side: solid panel following the stair, gold cap
    bt = 0.5
    zf, ztp = 3.4, bz + b['rail_h'] - cap
    for xf, sgn in ((sx0, -1), (sx0 + bt, 1)):
        pts = [(xf, foot, 0.0), (xf, pf, 0.0), (xf, pf, ztp), (xf, foot, zf)]
        stair.poly(pts if sgn > 0 else pts[::-1], 'white_gloss')
    stair.poly([(sx0, foot, zf), (sx0 + bt, foot, zf), (sx0 + bt, pf, ztp), (sx0, pf, ztp)], 'white_gloss')
    stair.poly([(sx0, foot, 0.0), (sx0 + bt, foot, 0.0), (sx0 + bt, foot, zf), (sx0, foot, zf)][::-1], 'white_gloss')
    stair.poly([(sx0 - 0.1, foot, zf), (sx0 + bt + 0.1, foot, zf), (sx0 + bt + 0.1, pf, ztp + cap - 0.0),
                (sx0 - 0.1, pf, ztp + cap)][::-1], 'gold')
    stair.poly([(sx0 - 0.1, foot, zf + cap), (sx0 + bt + 0.1, foot, zf + cap), (sx0 + bt + 0.1, pf, ztp + cap),
                (sx0 - 0.1, pf, ztp + cap)], 'gold')
    for k in range(1, ss['tiers'] + 1):
        ya, yb = foot - k * ss['run'], foot - (k - 1) * ss['run']
        zt = k * ss['rise']
        stair.box(tx0, ya, 0.0, tx1, yb, zt, 'wall', faces={'+z', '+y', '+x'})
        stair.poly([(tx0, yb, zt - 0.2), (tx1, yb, zt - 0.2), (tx1, yb, zt), (tx0, yb, zt)], 'gold')
        cz = 'sunflower' if k % 2 else 'tangerine'
        stair.box(tx0 + 0.3, yb - 2.1, zt, tx1 - 0.3, yb - 0.2, zt + 0.45, cz, chamfer=0.18)
    stair.rect(tx0, pf, tx1, foot, 'stair')
    # the core under the prow, the secret nook behind the stair seats, the cue room
    rooms.rect(sx0, y0, tx1, pf, 'core')
    rooms.rect(tx1, y0, px1, bf, 'core')
    rooms.poly([(tx1, bf, 0.0), (px1, bf, 0.0), (px1, bf, bz - bs), (tx1, bf, bz - bs)], 'accent')  # nook back
    rooms.poly([(tx1, pf, 0.0), (tx1, bf, 0.0), (tx1, bf, bz - bs), (tx1, pf, bz - bs)][::-1], 'wall')
    cx0_, cx1_ = L['cue_x']
    d0, d1 = P['cue_room']['door']
    rooms.poly([(cx0_, y0, 0.0), (cx0_, bf, 0.0), (cx0_, bf, bz - bs), (cx0_, y0, bz - bs)][::-1], 'wall')
    rooms.poly([(cx0_, y0 + 0.02, 0.0), (cx1_, y0 + 0.02, 0.0), (cx1_, y0 + 0.02, bz - bs), (cx0_, y0 + 0.02, bz - bs)],
               'yellow')
    rooms.box(cx1_ - 0.4, y0, 0.0, cx1_, bf, bz - bs, 'accent', kind='wall')
    rooms.box(cx0_, bf - 0.4, 0.0, d0, bf, 1.0, 'navy', kind='wall')
    rooms.box(cx0_, bf - 0.4, 9.0, cx1_, bf, bz - bs, 'wall')
    for xx in (cx0_, (cx0_ + d0) / 2, d0 - 0.3):
        rooms.box(xx, bf - 0.45, 1.0, xx + 0.3, bf + 0.05, 9.0, 'navy')
    rooms.box(cx0_, bf - 0.45, 8.7, d0, bf + 0.05, 9.0, 'navy')
    rooms.box(d1, bf - 0.4, 0.0, cx1_, bf, 9.0, 'navy', kind='wall')
    rooms.box(d0 - 0.3, bf - 0.45, 0.0, d1, bf + 0.05, 0.25, 'gold')
    gcue.box(cx0_, bf - 0.2 - a['glass_t'] / 2, 1.0, d0, bf - 0.2 + a['glass_t'] / 2, 8.7, 'wall')
    for xx in np.arange(cx0_ + 4.0, cx1_ - 2.0, 7.0):
        E['Downlights'].disk(float(xx), (y0 + bf) / 2, a['downlight_r'], bz - bs - 0.02, 8, down=True)
    # the curved yellow fin beside the cue room window (ref_02)
    fin = a['fin']
    fy0, fy1, fh, frr = bf, bf + fin['depth'], fin['h'], fin['r']
    prof = [(fy0, 0.0), (fy1, 0.0), (fy1, fh - frr)]
    for i in range(1, 9):
        ang = (math.pi / 2) * i / 8
        prof.append((fy1 - frr + frr * math.cos(ang), fh - frr + frr * math.sin(ang)))
    prof.append((fy0, fh))
    for xf, sgn in ((fin['x'][0], -1), (fin['x'][1], 1)):
        pts = [(xf, yy, zz) for yy, zz in prof]
        rooms.poly(pts if sgn > 0 else pts[::-1], 'yellow')
    for i in range(len(prof) - 1):
        (ya_, za_), (yb_, zb_) = prof[i], prof[i + 1]
        if i == 0:
            continue
        rooms.poly([(fin['x'][0], ya_, za_), (fin['x'][1], ya_, za_), (fin['x'][1], yb_, zb_), (fin['x'][0], yb_, zb_)][::-1],
                   'yellow', smooth=True)
    rooms.rect(fin['x'][0], fy0, fin['x'][1], fy1, 'wall')

    # ---- piano stage: marble top, gold edge, one step --------------------------------------------
    ps = P['piano_stage']
    pcx, pcy = ps['centre']
    rad = ps['diameter'] / 2
    sg = a['stage_segments']
    marble.disk(pcx, pcy, rad, ps['height'], sg)
    marble.annulus(pcx, pcy, rad, rad + ps['step'], ps['height'] / 2, sg)
    rooms.cylinder(pcx, pcy, rad + 0.06, ps['height'] - 0.25, ps['height'] + 0.01, sg, 'gold', top=False)
    rooms.cylinder(pcx, pcy, rad, ps['height'] / 2, ps['height'] - 0.25, sg, 'white_gloss', top=False)
    rooms.cylinder(pcx, pcy, rad + ps['step'], 0.0, ps['height'] / 2, sg, 'white_gloss', top=False)
    rooms.rect(pcx - rad - ps['step'], pcy - rad - ps['step'], pcx + rad + ps['step'], pcy + rad + ps['step'],
               'stage')

    # ---- terrace: railing (solid face, gold cap) ------------------------------------------------------
    trh = te['rail_h']
    for ra in ((tex1 - 0.5, ty0, tex1, ty1), (tex0, ty1 - 0.5, tex1, ty1), (tex0, ty0, tex1, ty0 + 0.5)):
        terr.box(ra[0], ra[1], 0.0, ra[2], ra[3], trh - cap, 'white_gloss', chamfer=0.08)
        terr.box(ra[0] - 0.1, ra[1] - 0.1, trh - cap, ra[2] + 0.1, ra[3] + 0.1, trh, 'gold', chamfer=0.1)
    terr.box(tex0, ty0, -1.0, tex1, ty1, -0.01, 'wall', faces={'+x', '-y', '+y'})

    objs = B.emit()
    logo = screen_quad('Sign_Logo_ProDoor', (x0 + 0.27, walk_c, pd['h'] + 3.1), pd['w'], 3.0, '+X',
                       surface_material('Sign_Logo'), stage=2)
    objs.append(logo)
    stage2_collision(L)
    for o in objs:
        o['hub_owned'] = 1
    print('HUB architecture: %d meshes, %d triangles' % (len(objs), sum(tri_count(o) for o in objs)))
    return objs


def balcony_columns(L):
    t2 = sorted([tb for tb in L['tables'] if tb['zone'] == '2v2' and tb['row'] == 0], key=lambda tb: tb['x'])
    gap = (t2[0]['rect'][2] + t2[1]['rect'][0]) / 2
    return [gap] + list(P['balcony']['lounge_columns_x'])


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def stage2_collision(L):
    r, b = P['room'], P['balcony']
    x0, x1, y0, y1, H = r['x0'], r['x1'], r['y0'], r['y1'], r['ceiling']
    w = r['wall']
    te = P['terrace']
    ty0, ty1 = te['y']
    dy0, dy1 = te['door_y']
    tex0, tex1 = x1 + w, x1 + w + te['depth']
    bf, pf = L['balcony_front'], L['prow_front']
    px0, px1 = L['prow_x']
    sx0, sx1 = L['stair_x']
    tx0, tx1 = L['seats_x']
    foot = L['stair_foot_y']
    bz, bs = b['z'], b['slab']
    t = P['partition']['t']
    s = 2
    col_box('COL_Floor', x0 - w, y0 - w, -1.0, x1 + w, y1 + w, 0.0, s)
    col_box('COL_TerraceFloor', tex0, ty0, -1.0, tex1, ty1, 0.0, s)
    col_box('COL_Wall_S', x0 - w, y0 - w, 0.0, x1 + w, y0, H, s)
    col_box('COL_Wall_N', x0 - w, y1, 0.0, x1 + w, y1 + w, H, s)
    col_box('COL_Wall_W', x0 - w, y0, 0.0, x0, y1, H, s)
    col_box('COL_Wall_E1', x1, y0, 0.0, x1 + w, dy0, H, s)
    col_box('COL_Wall_E2', x1, dy1, 0.0, x1 + w, y1, H, s)
    col_box('COL_Wall_EDoorHead', x1, dy0, 12.0, x1 + w, dy1, H, s)
    R = P['arch']['corner_radius']
    for name, cx in (('NW', x0), ('NE', x1 - R)):
        col_box('COL_Corner_' + name, cx, y1 - R * 0.3, 0.0, cx + R, y1, H, s)
    col_box('COL_Ceiling', x0 - w, y0 - w, H, x1 + w, y1 + w, H + 1.0, s)
    col_box('COL_Balcony', x0, y0, bz - bs, x1, bf, bz, s)
    col_box('COL_Prow', px0, bf, bz - bs, px1, pf, bz, s)
    col_box('COL_Rail_W', x0, bf - 0.5, bz, px0, bf, bz + b['rail_h'], s)
    col_box('COL_Rail_E', px1, bf - 0.5, bz, x1, bf, bz + b['rail_h'], s)
    col_box('COL_Rail_ProwE', px1 - 0.5, bf, bz, px1, pf, bz + b['rail_h'], s)
    col_box('COL_Rail_ProwN', tx1, pf - 0.5, bz, px1, pf, bz + b['rail_h'], s)
    col_box('COL_Rail_Stair', sx0, pf, 0.0, sx0 + 0.5, foot, bz + b['rail_h'], s)
    col_ramp('COL_StairRamp', sx0 + 0.5, sx1, foot, pf, 0.0, bz, s)
    for k in range(1, P['stair_seats']['tiers'] + 1):
        run, rise = P['stair_seats']['run'], P['stair_seats']['rise']
        col_box('COL_StairSeat_%d' % k, tx0, foot - k * run, 0.0, tx1, foot - (k - 1) * run, k * rise, s)
    col_box('COL_Core', sx0, y0, 0.0, tx1, pf, bz - bs, s)
    col_box('COL_CoreEast', tx1, y0, 0.0, px1, bf, bz - bs, s)
    cx0_, cx1_ = L['cue_x']
    d0, d1 = P['cue_room']['door']
    col_box('COL_CueRoom_E', cx1_ - 0.4, y0, 0.0, cx1_, bf, bz - bs, s)
    col_box('COL_CueRoom_Front', cx0_, bf - 0.4, 0.0, d0, bf, bz - bs, s)
    col_box('COL_CueRoom_Post', d1, bf - 0.4, 0.0, cx1_, bf, bz - bs, s)
    fin = P['arch']['fin']
    col_box('COL_Fin', fin['x'][0], bf, 0.0, fin['x'][1], bf + fin['depth'], fin['h'], s)
    ph = P['partition']['h']
    for i, (a0, a1) in enumerate(L['part_2n_segs']):
        col_box('COL_Glass_2v2N_%d' % i, a0, L['y_part_2n'], 0.0, a1, L['y_part_2n'] + t, ph, s)
    for i, (a0, a1) in enumerate(L['part_2e_segs']):
        col_box('COL_Glass_2v2E_%d' % i, L['x_part_2e'], a0, 0.0, L['x_part_2e'] + t, a1, ph, s)
    col_box('COL_Glass_1v1_3v3', L['x_part_13'], L['walk_n'], 0.0, L['x_part_13'] + t, y1, ph, s)
    for i, (a0, a1) in enumerate(L['part_3s_segs']):
        col_box('COL_Glass_3v3S_%d' % i, a0, L['y_part_3s'], 0.0, a1, L['y_part_3s'] + t, ph, s)
    cols = [(cx - b['column'] / 2, bf - 0.2 - b['column'], b['column'], bz - bs) for cx in balcony_columns(L)]
    cols += [(c[0], c[1], c[2], H) for c in P['arch']['columns']]
    for i, (cx0, cy0, size, top) in enumerate(cols):
        col_box('COL_Column_%d' % i, cx0, cy0, 0.0, cx0 + size, cy0 + size, top, s)
    ps = P['piano_stage']
    rr = ps['diameter'] / 2
    pcx, pcy = ps['centre']
    col_box('COL_PianoStep', pcx - rr - ps['step'] * 0.7, pcy - rr - ps['step'] * 0.7, 0.0,
            pcx + rr + ps['step'] * 0.7, pcy + rr + ps['step'] * 0.7, ps['height'] / 2, s, shape='Box')
    col_box('COL_PianoStage', pcx - rr * 0.88, pcy - rr * 0.88, 0.0, pcx + rr * 0.88, pcy + rr * 0.88, ps['height'], s)
    col_box('COL_TerraceRail_E', tex1 - 0.5, ty0, 0.0, tex1, ty1, te['rail_h'], s)
    col_box('COL_TerraceRail_N', tex0, ty1 - 0.5, 0.0, tex1, ty1, te['rail_h'], s)
    col_box('COL_TerraceRail_S', tex0, ty0, 0.0, tex1, ty0 + 0.5, te['rail_h'], s)
    # the invisible walls that stop anyone jumping off the terrace
    col_box('COL_TerraceWall_E', tex1, ty0 - 0.5, 0.0, tex1 + 0.5, ty1 + 0.5, te['col_h'], s)
    col_box('COL_TerraceWall_S', tex0, ty0 - 0.5, 0.0, tex1 + 0.5, ty0, te['col_h'], s)
    col_box('COL_TerraceWall_N', tex0, ty1, 0.0, tex1 + 0.5, ty1 + 0.5, te['col_h'], s)


# =================================================================================================
# Stage 3: furniture, props, anchors, pendants, emissives, signs, cue room, piano
# =================================================================================================
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402


def bm_box(sx, sy, sz, bevel=0.0, segs=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=min(bevel, min(sx, sy, sz) * 0.49),
                        segments=segs, profile=0.5, affect='EDGES')
    return bm


def bm_cyl(r, h, segs=16, r2=None, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=h)
    if bevel > 0:
        caps = [e for e in bm.edges if all(abs(abs(v.co.z) - h / 2) < 1e-4 for v in e.verts) and
                abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-4]
        bmesh.ops.bevel(bm, geom=caps, offset=min(bevel, h * 0.45, r * 0.45), segments=2, profile=0.5,
                        affect='EDGES')
    return bm


def bm_sphere(r, subdiv=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    return bm


def put(batch, bm, sw, loc=(0, 0, 0), rot=(0.0, 0.0, 0.0), smooth=True, scale=None):
    """Adds a bmesh part to a batch: rotate (degrees, XYZ), then move."""
    m = Matrix.Translation(Vector(loc)) @ (Matrix.Rotation(math.radians(rot[2]), 4, 'Z') @
                                           Matrix.Rotation(math.radians(rot[1]), 4, 'Y') @
                                           Matrix.Rotation(math.radians(rot[0]), 4, 'X'))
    if scale:
        m = m @ Matrix.Diagonal((*scale, 1.0))
    for f in bm.faces:
        batch.poly([tuple(m @ v.co) for v in f.verts], sw, smooth=smooth)
    bm.free()


def tube(batch, a, b, thick, sw):
    """A square bar from point a to point b (nothing thinner than 0.25)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    ln = d.length
    bm = bm_box(thick, thick, ln, bevel=thick * 0.2, segs=1)
    rot = d.to_track_quat('Z', 'Y').to_euler()
    m = Matrix.Translation((a + b) / 2) @ rot.to_matrix().to_4x4()
    for f in bm.faces:
        batch.poly([tuple(m @ v.co) for v in f.verts], sw, smooth=False)
    bm.free()


def outline_ring(batch, outline, width, z0, z1, sw, sw_bottom=None, glow=None, glow_w=0.3):
    """A flat frame following a closed outline (offset half the width each side); the bottom
    face can go to a separate glow batch (the pendants' glowing undersides)."""
    n = len(outline)
    outer, inner = offset_outline(outline, width / 2), offset_outline(outline, -width / 2)
    for i in range(n):
        j = (i + 1) % n
        batch.poly([(*outer[i], z0), (*outer[j], z0), (*outer[j], z1), (*outer[i], z1)], sw)
        batch.poly([(*inner[j], z0), (*inner[i], z0), (*inner[i], z1), (*inner[j], z1)], sw)
        batch.poly([(*outer[i], z1), (*outer[j], z1), (*inner[j], z1), (*inner[i], z1)], sw)
        batch.poly([(*inner[i], z0), (*inner[j], z0), (*outer[j], z0), (*outer[i], z0)], sw_bottom or sw)
    if glow is not None:
        go, gi = offset_outline(outline, glow_w / 2), offset_outline(outline, -glow_w / 2)
        for i in range(n):
            j = (i + 1) % n
            glow.poly([(*gi[i], z0 - 0.03), (*gi[j], z0 - 0.03), (*go[j], z0 - 0.03), (*go[i], z0 - 0.03)], 'wall')


def offset_outline(outline, d):
    n = len(outline)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(outline[i - 1]), Vector(outline[i]), Vector(outline[(i + 1) % n])
        e0, e1 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n0, n1 = Vector((e0.y, -e0.x)), Vector((e1.y, -e1.x))  # right-hand normals (outward for CCW)
        nm = (n0 + n1).normalized()
        k = d / max(nm.dot(n1), 0.2)
        q = p1 + nm * k
        out.append((q.x, q.y))
    return out


# ---- prop masters -----------------------------------------------------------------------------------
PROP_SPECS = {}  # name -> {'parts': [mesh names], 'tint': bool, 'seats': [(x, y, z)], 'kind': str}


def prop(name, tint=False, seats=(), kind='prop', block=True):
    def deco(fn):
        PROP_SPECS[name] = {'fn': fn, 'tint': tint, 'seats': list(seats), 'kind': kind, 'block': block}
        return fn
    return deco


@prop('Armchair', tint=True, seats=[(0.0, 0.1, 1.95)], kind='seat')
def prop_armchair(fab, frame, glow):
    """Slim velvet armchair on thin gold legs (ref_01). Faces +Y. The fabric mesh is tinted."""
    put(fab, bm_box(2.7, 2.5, 0.65, 0.28, 3), 'fabric_white', (0, 0.05, 1.62))
    put(fab, bm_box(2.7, 0.62, 2.3, 0.3, 3), 'fabric_white', (0, -1.05, 2.95), rot=(-9, 0, 0))
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.cylinder(sx * 1.15, sy * 1.0, 0.14, 0.0, 1.3, 8, 'gold', top=False)
        tube(frame, (sx * 1.42, 1.1, 1.3), (sx * 1.42, 1.1, 2.55), 0.26, 'gold')
        tube(frame, (sx * 1.42, 1.1, 2.55), (sx * 1.42, -1.25, 2.7), 0.26, 'gold')
        tube(frame, (sx * 1.42, -1.25, 1.3), (sx * 1.42, -1.25, 2.7), 0.26, 'gold')
    tube(frame, (-1.15, 1.0, 1.3), (1.15, 1.0, 1.3), 0.26, 'gold')
    tube(frame, (-1.15, -1.0, 1.3), (1.15, -1.0, 1.3), 0.26, 'gold')


@prop('SideTable', kind='table_small')
def prop_side_table(main, _b, _g):
    put(main, bm_cyl(0.8, 0.3, 20, bevel=0.1), 'side_table', (0, 0, 2.05))
    main.cylinder(0, 0, 0.15, 0.2, 1.9, 8, 'gold', top=False)
    put(main, bm_cyl(0.6, 0.25, 16, bevel=0.08), 'gold', (0, 0, 0.125))


@prop('Sofa', seats=[(-2.2, 0.2, 2.2), (0.0, 0.2, 2.2), (2.2, 0.2, 2.2)], kind='seat')
def prop_sofa(main, _b, _g):
    """Plump cobalt velvet sofa (ref_03), 7 wide, faces +Y, with sunflower and tangerine cushions."""
    put(main, bm_box(6.8, 3.2, 1.1, 0.3, 2), 'cobalt', (0, 0, 1.05))
    for i in (-1, 0, 1):
        put(main, bm_box(2.15, 2.5, 0.62, 0.28, 3), 'cobalt', (i * 2.18, 0.25, 1.9))
    put(main, bm_box(6.6, 0.95, 1.9, 0.4, 3), 'cobalt', (0, -1.15, 2.75), rot=(-6, 0, 0))
    for sx in (-1, 1):
        put(main, bm_box(0.85, 3.2, 1.55, 0.38, 3), 'cobalt', (sx * 3.35, 0, 1.95))
    put(main, bm_box(1.4, 0.5, 1.4, 0.35, 3), 'sunflower', (-2.3, -0.45, 2.85), rot=(-15, 0, 12))
    put(main, bm_box(1.4, 0.5, 1.4, 0.35, 3), 'tangerine', (2.3, -0.45, 2.85), rot=(-15, 0, -12))
    for sx in (-1, 1):
        for sy in (-1, 1):
            put(main, bm_box(0.3, 0.3, 0.5, 0.06, 1), 'gold', (sx * 3.2, sy * 1.3, 0.25), smooth=False)


@prop('BarStool', seats=[(0.0, 0.0, 2.75)], kind='seat')
def prop_bar_stool(main, _b, _g):
    """Coral seat on gold legs with a footrest ring (ref_03). Faces +Y."""
    put(main, bm_cyl(0.95, 0.5, 20, bevel=0.2), 'coral', (0, 0, 2.55))
    for i in range(9):
        a = math.radians(-150 + i * 37.5)
        a2 = math.radians(-150 + (i + 1) * 37.5)
        if i < 8:
            tube(main, (0.85 * math.sin(a), -0.85 * math.cos(a), 3.3), (0.85 * math.sin(a2), -0.85 * math.cos(a2), 3.3),
                 0.35, 'coral')
    for a in (-150, -75, 0, 75, 150):
        pass
    tube(main, (-0.8, -0.35, 2.75), (-0.8, -0.35, 3.3), 0.26, 'gold')
    tube(main, (0.8, -0.35, 2.75), (0.8, -0.35, 3.3), 0.26, 'gold')
    for k in range(4):
        a = math.radians(45 + 90 * k)
        tube(main, (0.55 * math.cos(a), 0.55 * math.sin(a), 2.35), (0.9 * math.cos(a), 0.9 * math.sin(a), 0.0),
             0.26, 'gold')
    ring = [(0.78 * math.cos(math.radians(30 * i)), 0.78 * math.sin(math.radians(30 * i))) for i in range(12)]
    for i in range(12):
        tube(main, (*ring[i], 1.1), (*ring[(i + 1) % 12], 1.1), 0.26, 'gold')


@prop('Pouf', tint=True, seats=[(0.0, 0.0, 1.4)], kind='seat')
def prop_pouf(fab, _b, _g):
    put(fab, bm_cyl(1.05, 1.35, 20, bevel=0.35), 'fabric_white', (0, 0, 0.675))


@prop('Plant', kind='plant')
def prop_plant(main, _b, _g):
    """White planter with a gold rim and a bushy emerald plant. Keep away from the tables."""
    put(main, bm_cyl(1.0, 1.9, 16, r2=0.8, bevel=0.1), 'planter_white', (0, 0, 0.95))
    main.cylinder(0, 0, 1.05, 1.8, 2.0, 16, 'gold', top=False)
    rng = random.Random(7)
    for i in range(6):
        a = i * 1.05
        rr = 0.35 + 0.25 * (i % 2)
        put(main, bm_sphere(0.95 - 0.08 * i, 1), 'emerald' if i % 2 else 'emerald_light',
            (rr * math.cos(a), rr * math.sin(a), 2.6 + i * 0.45 + rng.uniform(-0.1, 0.1)), smooth=True)


@prop('CueRack', kind='wall_prop', block=False)
def prop_cue_rack(main, _b, _g):
    """Wall rack with six cues (the showcase slots). Back against -Y, faces +Y."""
    put(main, bm_box(3.6, 0.3, 6.4, 0.08, 1), 'white_gloss', (0, 0.15, 3.9), smooth=False)
    for zz in (1.4, 6.2):
        put(main, bm_box(3.4, 0.6, 0.3, 0.08, 1), 'gold', (0, 0.45, zz), smooth=False)
    for i in range(6):
        x = -1.5 + i * 0.6
        main.cylinder(x, 0.55, 0.13, 1.0, 3.6, 6, 'cue_dark', top=False)
        main.cylinder(x, 0.55, 0.13, 3.6, 6.7, 6, 'cue_wood', top=False)
        main.cylinder(x, 0.55, 0.13, 6.7, 6.9, 6, 'key_white')


@prop('Plinth', kind='plinth')
def prop_plinth(main, _b, _g):
    """Statue plinth: marble drum with gold rings. Height 1 (scale Z for the podium)."""
    put(main, bm_cyl(1.5, 1.0, 24, bevel=0.06), 'marble_flat', (0, 0, 0.5))
    main.cylinder(0, 0, 1.55, 0.0, 0.18, 24, 'gold', top=False)
    main.cylinder(0, 0, 1.55, 0.86, 1.0, 24, 'gold', top=False)


@prop('Umbrella', kind='umbrella', block=False)
def prop_umbrella(main, _b, _g):
    """Terrace umbrella: striped canopy (sunflower and white), gold pole, heavy base."""
    main.cylinder(0, 0, 0.14, 0.2, 7.9, 8, 'gold', top=False)
    put(main, bm_cyl(1.0, 0.4, 16, bevel=0.1), 'navy', (0, 0, 0.2))
    n = 12
    for i in range(n):
        a, b_ = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        sw = 'sunflower' if i % 2 == 0 else 'white_matte'
        p0, p1 = (5.0 * math.cos(a), 5.0 * math.sin(a), 6.3), (5.0 * math.cos(b_), 5.0 * math.sin(b_), 6.3)
        main.poly([p0, p1, (0, 0, 7.9)], sw)
        main.poly([(0, 0, 7.6), p1, p0], sw)
        main.poly([p0, (p0[0], p0[1], 5.9), (p1[0], p1[1], 5.9), p1][::-1], sw)
    main.cylinder(0, 0, 0.3, 7.8, 8.2, 8, 'gold')


def pendant_parts(shape):
    """Outline and size of each zone's pendant; long axis along local X (the table length)."""
    if shape == 'Hex':  # long hexagon frame (ref_01)
        return [[(8.2, 0.0), (5.6, 3.3), (-5.6, 3.3), (-8.2, 0.0), (-5.6, -3.3), (5.6, -3.3)]]
    if shape == 'Square':  # nested double squares (ref_04)
        return [[(7.4, -4.3), (7.4, 4.3), (-7.4, 4.3), (-7.4, -4.3)][::-1],
                [(5.0, -2.5), (5.0, 2.5), (-5.0, 2.5), (-5.0, -2.5)][::-1]]
    return None


def make_pendant(shape):
    def fn(main, _b, glow):
        bw, bh = 0.55, 0.6
        if shape in ('Hex', 'Square'):
            rings = pendant_parts(shape)
            for k, ring in enumerate(rings):
                zb = k * 0.9  # the inner square hangs a little higher (ref_04)
                outline_ring(main, ring, bw, zb, zb + bh, 'black_gloss', glow=glow, glow_w=0.32)
            rod_pts = [(-4.5, 0.0), (4.5, 0.0)] if shape == 'Hex' else [(-5.0, 0.0), (5.0, 0.0)]
            if shape == 'Square':  # cross bars tie the inner frame to the outer
                for sx in (-1, 1):
                    tube(main, (sx * 5.0, 0.0, 0.9 + bh), (sx * 7.4, 0.0, bh), 0.3, 'black_gloss')
        else:  # Y: three arms (ref_05, ref_07)
            for k in range(3):
                a = math.radians(90 + 120 * k)
                ca, sa = math.cos(a), math.sin(a)
                L_ = 7.5
                pts = [(-0.3 * sa + 0.9 * ca, 0.3 * ca + 0.9 * sa), (L_ * ca - 0.3 * sa, L_ * sa + 0.3 * ca),
                       (L_ * ca + 0.3 * sa, L_ * sa - 0.3 * ca), (0.3 * sa + 0.9 * ca, -0.3 * ca + 0.9 * sa)]
                main.prism(pts, 0.0, bh, 'black_gloss', bottom=True)
                g0 = [(0.9 * ca - 0.16 * sa + 0.2 * ca, 0.9 * sa + 0.16 * ca + 0.2 * sa)]
                glow.poly([(1.2 * ca + 0.16 * sa, 1.2 * sa - 0.16 * ca, -0.03),
                           ((L_ - 0.3) * ca + 0.16 * sa, (L_ - 0.3) * sa - 0.16 * ca, -0.03),
                           ((L_ - 0.3) * ca - 0.16 * sa, (L_ - 0.3) * sa + 0.16 * ca, -0.03),
                           (1.2 * ca - 0.16 * sa, 1.2 * sa + 0.16 * ca, -0.03)], 'wall')
                del g0
            hub = [(0.95 * math.cos(math.radians(30 + 60 * i)), 0.95 * math.sin(math.radians(30 + 60 * i)))
                   for i in range(6)]
            outline_ring(main, hub, 0.45, 0.0, bh, 'black_gloss')
            rod_pts = [(0.0, 5.0), (4.33, -2.5), (-4.33, -2.5)]
        top = P['room']['ceiling'] - P['pendant']['bottom']
        for x, y in rod_pts:
            main.box(x - 0.125, y - 0.125, bh, x + 0.125, y + 0.125, top, 'black_gloss')
    return fn


for _shape in ('Hex', 'Square', 'Y'):
    PROP_SPECS['Pendant_' + _shape] = {'fn': make_pendant(_shape), 'tint': False, 'seats': [], 'kind': 'pendant',
                                       'block': False, 'glow': True}


def build_prop_library():
    """Every repeated prop once, at the origin, in HUB_PropLibrary (kept out of the view layer).
    Returns name -> {'objects': [...], ...}."""
    lib = pkg_collection('HUB_PropLibrary')
    for obj in list(lib.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    pal = surface_material('Palette')
    tint = palette_tint_material()
    warm = P['palette']['warm_led']
    out = {}
    for name, spec in PROP_SPECS.items():
        if name.startswith('Tower_'):
            continue
        main = Batch('Prop_' + name + ('_Fabric' if spec['tint'] else ''), 'Palette', 'HUB_PropLibrary', 3,
                     material=tint if spec['tint'] else pal)
        frame = Batch('Prop_' + name + '_Frame', 'Palette', 'HUB_PropLibrary', 3, material=pal)
        glow = Batch('Emissive_Pendant_' + name.split('_')[-1] if name.startswith('Pendant') else 'Emissive_' + name,
                     'Neon', 'HUB_PropLibrary', 3, material=neon_material('Pendant', warm), props={'hub_neon': warm})
        spec['fn'](main, frame, glow)
        objs = main.emit() + frame.emit() + glow.emit()
        for o in objs:
            o['hub_prop'] = name
            o['hub_tint'] = 1 if (spec['tint'] and o.name.endswith('_Fabric')) else 0
            if o.data.polygons:
                o.data.set_sharp_from_angle(angle=math.radians(35))
        out[name] = {'objects': objs, **{k: v for k, v in spec.items() if k != 'fn'}}
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.collection.name == ROOT:
            for c in lc.children:
                if c.collection == lib:
                    c.exclude = True
    return out


def palette_tint_material():
    """Palette colour x the placement's tint (Roblox: SurfaceAppearance.Color)."""
    name = 'Hub_Palette_Tinted'
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = surface_material('Palette', name=name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    col_link = next(lk for lk in links if lk.to_socket == bsdf.inputs['Base Color'])
    src = col_link.from_socket
    info = nodes.new('ShaderNodeObjectInfo')
    mix = nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = 1.0
    links.new(src, socket(mix.inputs, 'A_Color', 'A'))
    links.new(info.outputs['Color'], socket(mix.inputs, 'B_Color', 'B'))
    links.new(socket(mix.outputs, 'Result_Color', 'Result'), bsdf.inputs['Base Color'])
    mat['hub_surface'] = 'Palette'
    mat['hub_tinted'] = 1
    return mat


def place(lib, prop_name, x, y, z=0.0, facing=None, yaw=None, tint=None, name=None, scale=None, kind=None,
          zone=''):
    """Places linked duplicates of a prop master. facing: world direction the prop's +Y turns to."""
    spec = lib[prop_name]
    if yaw is None:
        fx, fy = facing if facing is not None else (0.0, 1.0)
        yaw = math.degrees(math.atan2(-fx, fy))
    coll = pkg_collection('HUB_Props')
    idx = sum(1 for o in coll.objects if o.get('hub_prop') == prop_name and o.get('hub_part') == 0) + 1
    objs = []
    for pi, master in enumerate(spec['objects']):
        o = bpy.data.objects.new('%s_%s%03d' % (name or prop_name, master.name.split('_')[-1] if pi else 'P', idx),
                                 master.data)
        o.location = (x, y, z)
        o.rotation_euler = (0.0, 0.0, math.radians(yaw))
        if scale:
            o.scale = scale
        if tint and master.get('hub_tint'):
            o.color = (*lin(tint), 1.0)
        coll.objects.link(o)
        o['hub_stage'] = 3
        o['hub_owned'] = 1
        o['hub_prop'] = prop_name
        o['hub_master'] = master.name
        o['hub_part'] = pi
        o['hub_yaw'] = yaw
        if tint:
            o['hub_tint_hex'] = P['palette'].get(tint, tint)
        if pi == 0 and spec['block'] and z < 0.5:
            o['hub_floor'] = 1
            o['hub_block'] = 1
            o['hub_kind'] = kind or spec['kind']
            if zone:
                o['zone'] = zone
        if pi == 0 and spec['seats']:
            o['hub_seats'] = json.dumps(spec['seats'])
        objs.append(o)
    return objs


def seat_bands(L):
    """The seating edges from the stage 1 plan: (name, rect, facing, zone)."""
    r = P['room']
    x0, x1, y0, y1 = r['x0'], r['x1'], r['y0'], r['y1']
    sd, sm = P['seat_depth'], P['seat_margin']
    z1b, z2b, z3b = L['zone_boxes']['1v1'], L['zone_boxes']['2v2'], L['zone_boxes']['3v3']
    c2, c3 = P['zones']['2v2']['clearance'], P['zones']['3v3']['clearance']
    R = P['arch']['corner_radius']
    t = P['partition']['t']
    col_x = balcony_columns(L)[0]
    ub0, ub1 = z2b[1] - c2 - sm - sd, z2b[1] - c2 - sm
    bands = [('1v1_WestWindow', (x0, z1b[1], x0 + sd, min(z1b[3], y1 - R)), (1, 0), '1v1'),
             ('1v1_NorthWindow', (x0 + R, y1 - sd, z1b[2], y1), (0, -1), '1v1')]
    for i, (a, b) in enumerate(L['part_2n_segs']):
        bands.append(('1v1_Gallery_%d' % i, (a, L['walk_s'], b, L['walk_s'] + sd), (0, 1), '1v1'))
    bands += [('1v1_BarBench', (P['bench'][0], L['walk_s'], P['bench'][1], L['walk_s'] + sd), (0, 1), '1v1'),
              ('2v2_WestWindow', (x0, z2b[1], x0 + sd, z2b[3]), (1, 0), '2v2'),
              ('2v2_UnderBalcony_W', (x0 + sd, ub0, col_x - 1.0, ub1), (0, 1), '2v2'),
              ('2v2_UnderBalcony_E', (col_x + 1.0, ub0, L['x_2v2_seat'], ub1), (0, 1), '2v2'),
              ('2v2_EastGlass', (L['x_2v2_seat'], z2b[1], L['x_part_2e'], L['part_2e_segs'][0][1]), (-1, 0), '2v2'),
              ('3v3_North', (z3b[0] - 4.0, z3b[3] + c3 + sm, z3b[2] + 4.0, z3b[3] + c3 + sm + sd), (0, -1), '3v3')]
    for i, (a, b) in enumerate(L['part_3s_segs']):
        bands.append(('3v3_South_%d' % i, (a + 0.2, L['y_part_3s'] + t, b - 0.2, L['y_part_3s'] + t + sd), (0, 1),
                      '3v3'))
    return bands


def fill_band(lib, band, z=0.0, tints=None):
    """Armchair pairs with a small dark side table between them, centred along the band."""
    name, (bx0, by0, bx1, by1), facing, zone = band
    along_x = (bx1 - bx0) >= (by1 - by0)
    length = (bx1 - bx0) if along_x else (by1 - by0)
    pair, gap = P['furnish']['pair'], P['furnish']['pair_gap']
    n = int((length + gap) // (pair + gap))
    if n < 1:
        return 0
    used = n * pair + (n - 1) * gap
    align = P['furnish']['align'].get(name, 'centre')
    slack = {'min': 0.0, 'centre': (length - used) / 2, 'max': length - used}[align]
    start = (bx0 if along_x else by0) + slack
    cx, cy = (bx0 + bx1) / 2, (by0 + by1) / 2
    colour = zone if zone in ('1v1', '2v2', '3v3') else 'cobalt'
    count = 0
    for i in range(n):
        s0 = start + i * (pair + gap)
        for off in (1.45, pair - 1.45):
            s = s0 + off
            x, y = (s, cy) if along_x else (cx, s)
            place(lib, 'Armchair', x, y, z, facing=facing, tint=tints[count % len(tints)] if tints else colour,
                  zone=zone)
            count += 1
        s = s0 + pair / 2
        x, y = (s, cy) if along_x else (cx, s)
        place(lib, 'SideTable', x, y, z, facing=facing)
    return count


def render_sign(name, size, draw):
    """Renders a flat sign texture with Workbench (text via a Blender font object)."""
    scene = bpy.data.scenes.new('HubSignRender')
    scene.render.engine = 'BLENDER_WORKBENCH'
    sh = scene.display.shading
    sh.light, sh.color_type = 'FLAT', 'MATERIAL'
    sh.show_object_outline = False
    try:
        scene.view_settings.view_transform = 'Standard'
    except TypeError:
        pass
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.film_transparent = False
    world = bpy.data.worlds.new('HubSignWorld')
    world.color = (0, 0, 0)
    scene.world = world
    cam_d = bpy.data.cameras.new('HubSignCam')
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = float(size[0]) / 100.0
    cam = bpy.data.objects.new('HubSignCam', cam_d)
    cam.location = (0, 0, 10)
    scene.collection.objects.link(cam)
    scene.camera = cam
    made = draw(scene)
    path = os.path.join(bpy.app.tempdir or '/tmp', 'hub_sign_%s.png' % name)
    scene.render.filepath = path
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    with bpy.context.temp_override(scene=scene):
        bpy.ops.render.render(write_still=True, scene=scene.name)
    img = read_png(path)
    for o in made + [cam]:
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None:
            if isinstance(data, bpy.types.Camera):
                bpy.data.cameras.remove(data)
            elif isinstance(data, bpy.types.Curve):
                bpy.data.curves.remove(data)
            elif isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
    bpy.data.scenes.remove(scene)
    bpy.data.worlds.remove(world)
    return img


def sign_font():
    for path in ('/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf',
                 '/System/Library/Fonts/Supplemental/Arial Black.ttf'):
        if os.path.exists(path):
            return bpy.data.fonts.load(path, check_existing=True)
    return None


def sign_text(scene, body, size, colour, loc, name):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = body
    cu.size = size
    cu.align_x, cu.align_y = 'CENTER', 'CENTER'
    f = sign_font()
    if f is not None:
        cu.font = f
    o = bpy.data.objects.new(name, cu)
    o.location = loc
    o.data.materials.append(material('HubSign_' + name, colour, 1.0))
    scene.collection.objects.link(o)
    return o


def sign_plane(scene, w, h, colour, z, name, circle=False, r=None):
    if circle:
        segs = 64
        v = [(r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), z) for i in range(segs)]
        f = [tuple(range(segs))]
    else:
        v = [(-w / 2, -h / 2, z), (w / 2, -h / 2, z), (w / 2, h / 2, z), (-w / 2, h / 2, z)]
        f = [(0, 1, 2, 3)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.materials.append(material('HubSign_' + name, colour, 1.0))
    o = bpy.data.objects.new(name, me)
    scene.collection.objects.link(o)
    return o


def rounded_mask(h, w, radius, border):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = np.maximum(np.maximum(radius - xx, xx - (w - 1 - radius)), 0)
    dy = np.maximum(np.maximum(radius - yy, yy - (h - 1 - radius)), 0)
    d = np.sqrt(dx * dx + dy * dy)
    inner = np.clip(radius - d, 0, 1)
    return inner, np.clip(radius - border - d, 0, 1)


def tex_zone_sign(zone):
    def fn():
        w, h = 512, 256

        def draw(scene):
            return [sign_plane(scene, 5.2, 2.6, zone, 0.0, 'bg'),
                    sign_text(scene, zone, 1.55, 'midnight_navy', (0.05, -0.1, 0.1), 'shadow'),
                    sign_text(scene, zone, 1.55, '#FFFFFF', (0.0, -0.04, 0.2), 'text')]
        img = render_sign('zone_' + zone, (w, h), draw).astype(np.float32) / 255.0
        outer, inner = rounded_mask(h, w, 40, 12)
        rim = np.array(hex_rgb('#FFFFFF'), np.float32)
        col = img[..., :3] * inner[..., None] + rim * (outer - inner)[..., None]
        col = col + np.array(hex_rgb('midnight_navy'), np.float32) * (1 - outer)[..., None]
        return {'Color': col}
    return fn


def tex_logo():
    w = 512

    def draw(scene):
        return [sign_plane(scene, 5.2, 5.2, '#FFFFFF', 0.0, 'bg'),
                sign_plane(scene, 0, 0, 'gold', 0.05, 'ring', circle=True, r=2.25),
                sign_plane(scene, 0, 0, '#101418', 0.1, 'ball', circle=True, r=2.0),
                sign_plane(scene, 0, 0, '#FFFFFF', 0.15, 'spot', circle=True, r=0.95),
                sign_text(scene, '8', 1.45, '#101418', (0.0, -0.05, 0.2), 'eight')]
    img = render_sign('logo', (w, w), draw).astype(np.float32) / 255.0
    return {'Color': img[..., :3]}


SIGN_BUILDERS = {'Sign_Zone_1v1': ('sign_1v1', tex_zone_sign('1v1')),
                 'Sign_Zone_2v2': ('sign_2v2', tex_zone_sign('2v2')),
                 'Sign_Zone_3v3': ('sign_3v3', tex_zone_sign('3v3')),
                 'Sign_Logo': ('sign_logo', tex_logo)}
for _k in SIGN_BUILDERS:
    SURFACES[_k] = {'maps': ['Color']}


def screen_quad(name, centre, w, h, facing, material_, props=None, stage=3):
    """A flat quad with clean 0..1 UVs (a SurfaceGui target), facing +X/-X/+Y/-Y."""
    cx, cy, cz = centre
    fx, fy = {'+X': (1, 0), '-X': (-1, 0), '+Y': (0, 1), '-Y': (0, -1)}[facing]
    rx, ry = -fy, fx  # the quad's right as seen by someone standing in front of it
    pts = [(cx - rx * w / 2, cy - ry * w / 2, cz - h / 2), (cx + rx * w / 2, cy + ry * w / 2, cz - h / 2),
           (cx + rx * w / 2, cy + ry * w / 2, cz + h / 2), (cx - rx * w / 2, cy - ry * w / 2, cz + h / 2)]
    b = Batch(name, material_.get('hub_surface', 'Screen'), 'HUB_Screens', stage, uv='explicit', material=material_,
              props=dict(props or {}, hub_screen=1, hub_facing=facing, hub_size=[w, h]))
    b.poly(pts, uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
    return b.emit()[0]


def framed_panel(batch, centre, w, h, facing, depth=0.4, border=0.35, sw='white_gloss'):
    """The frame box behind a screen or sign."""
    cx, cy, cz = centre
    fx, fy = {'+X': (1, 0), '-X': (-1, 0), '+Y': (0, 1), '-Y': (0, -1)}[facing]
    hw, hd = w / 2 + border, depth / 2
    if fx:
        batch.box(cx - fx * depth, cy - hw, cz - h / 2 - border, cx - fx * 0.02, cy + hw, cz + h / 2 + border, sw,
                  chamfer=0.12)
    else:
        batch.box(cx - hw, cy - fy * depth, cz - h / 2 - border, cx + hw, cy - fy * 0.02, cz + h / 2 + border, sw,
                  chamfer=0.12)
    del hd


def stage_furnish():
    scene = hub_scene()
    L = layout()
    for name in list(PKG_COLL.values()) + EXTRA_COLLS:
        pkg_collection(name)
    clear_stage(3)
    remove_blockout()  # the seat proxies and pads go now
    mk = pkg_collection('HUB_Markers')
    for o in list(mk.objects):  # stage 1 anchors are rebuilt here
        if o.get('hub_stage') is None:
            bpy.data.objects.remove(o, do_unlink=True)
    ensure_textures(list(SIGN_BUILDERS), SIGN_BUILDERS)
    r, b, a = P['room'], P['balcony'], P['arch']
    x0, x1, y0, y1, H = r['x0'], r['x1'], r['y0'], r['y1'], r['ceiling']
    w = r['wall']
    bf, pf = L['balcony_front'], L['prow_front']
    px0, px1 = L['prow_x']
    sx0, sx1 = L['stair_x']
    tx0, tx1 = L['seats_x']
    foot = L['stair_foot_y']
    walk_s, walk_n = L['walk_s'], L['walk_n']
    walk_c = (walk_s + walk_n) / 2
    xp13 = L['x_part_13']
    bz = b['z']
    te = P['terrace']
    ty0, ty1 = te['y']
    tex0, tex1 = x1 + w, x1 + w + te['depth']
    fu = P['furnish']
    lib = build_prop_library()
    B = Batches(3)
    furn = B.get('Furn_Lounge', coll='HUB_Furniture')
    barp = B.get('Furn_Bar', coll='HUB_Furniture')
    barm = B.get('Furn_Bar_Marble', 'Marble', 'HUB_Furniture', uv='world', studs=P['textures']['marble']['tiles'] *
                 P['textures']['marble']['tile_studs'])
    kiosk = B.get('Furn_Kiosks', coll='HUB_Furniture')
    signs = B.get('Furn_SignFrames', coll='HUB_Furniture')
    piano = B.get('Placeholder_Piano', coll='HUB_Furniture')
    pbench = B.get('Placeholder_Piano_Bench', coll='HUB_Furniture')
    jbox = B.get('Furn_Jukebox', coll='HUB_Furniture')
    booths = B.get('Furn_Booths', coll='HUB_Furniture')
    fluted = B.get('Glass_Fluted', 'FlutedGlass', 'HUB_Glass', uv='world', studs=P['textures']['fluted']['studs'])
    E = {}
    for k, c in (('LED_Lounge', P['palette']['warm_led']), ('LED_Bar', P['palette']['warm_led']),
                 ('SignGlow_1v1', P['palette']['1v1']), ('SignGlow_2v2', P['palette']['2v2']),
                 ('SignGlow_3v3', P['palette']['3v3']), ('Kiosk_Shop', P['palette']['tangerine']),
                 ('Kiosk_Trade', P['palette']['coral']), ('Jukebox', P['palette']['sunflower']),
                 ('StringLights', P['palette']['warm_led'])):
        E[k] = B.get('Emissive_' + k, 'Neon', 'HUB_Emissive', material=neon_material(k, c), props={'hub_neon': c})
    anchors = []

    def anchor(name, loc, yaw=0.0, **props):
        o = empty(name, loc, mk, yaw, 1.5, 'ARROWS', **props)
        o['hub_stage'] = 3
        o['hub_owned'] = 1
        anchors.append(o)
        return o

    # ---- seating along every edge (armchair pairs with side tables) ---------------------------------
    chairs = 0
    for band in seat_bands(L):
        chairs += fill_band(lib, band)
    for i, rb_ in enumerate(fu['balcony_rail']):  # prospect seats along the balcony rail
        fill_band(lib, ('Balcony_Rail_%d' % i, tuple(rb_), (0, 1), 'balcony'), bz, ['cobalt', 'coral', 'sunflower'])
    for k, (sx_, sy_) in enumerate(fu['window_sofas']):  # 3v3 window lounge: sofas facing the view
        place(lib, 'Sofa', sx_, sy_, facing=(0, 1))
        if k % 2 == 0:
            place(lib, 'Pouf', sx_ + 4.5, sy_ + 4.0, tint=['sunflower', 'tangerine'][k // 2])
    # ---- balcony: armchairs under the featured screen, facing the club -----------------------------
    fs = P['featured_screen']
    fcx = L['stair_foot'][0]
    for i, dx in enumerate((-8.4, -5.0, -1.6, 1.6, 5.0, 8.4)):
        place(lib, 'Armchair', fcx + dx, y0 + 2.0, bz, facing=(0, 1), tint=['cobalt', 'coral', 'sunflower'][i % 3])
    for dx in (-3.3, 3.3):
        place(lib, 'SideTable', fcx + dx, y0 + 2.0, bz)
    # ---- bar: white marble counter, gold footrest, stools, back bar with screens -------------------
    bar = P['bar']
    c = bar['counter']
    ch = bar['counter_h']
    barm.box(c[0], c[2], 0.35, c[1], c[3], ch - 0.25, 'wall', faces={'-x', '+y', '-y'})
    barm.box(c[0] - 0.45, c[2] - 0.3, ch - 0.25, c[1] + 0.2, c[3] + 0.3, ch, 'wall', faces={'+z', '-x', '+y', '-y'})
    barp.box(c[0] + 0.15, c[2] + 0.1, 0.0, c[1], c[3] - 0.1, 0.35, 'navy', kind='bar')
    barp.box(c[0] - 0.45, c[2], 0.9, c[0] - 0.2, c[3], 1.15, 'gold', chamfer=0.08)
    E['LED_Bar'].box(c[0] - 0.44, c[2] - 0.2, ch - 0.55, c[0] - 0.3, c[3] + 0.2, ch - 0.25, 'wall', faces={'-x', '-z'})
    for i in range(fu['stools']):
        yy = c[2] + 1.3 + i * (c[3] - c[2] - 2.6) / (fu['stools'] - 1)
        place(lib, 'BarStool', bar['stand_x'] + 0.4, yy, facing=(1, 0))
    bk = bar['back']
    barp.box(bk[0] - 1.6, bk[2], 0.0, bk[1], bk[3], 3.2, 'navy', chamfer=0.1, kind='bar')
    barp.box(bk[0] - 1.8, bk[2] - 0.1, 3.2, bk[1], bk[3] + 0.1, 3.5, 'white_gloss', chamfer=0.08)
    barp.box(bk[0], bk[2], 3.5, bk[1], bk[3], bar['back_h'], 'navy', faces={'-x', '+z', '-y', '+y'})
    barp.poly([(bk[1] + 0.02, bk[2], 0.0), (bk[1] + 0.02, bk[3], 0.0), (bk[1] + 0.02, bk[3], bar['back_h']),
               (bk[1] + 0.02, bk[2], bar['back_h'])], 'accent')
    rng = random.Random(21)
    candy = ['coral', 'tangerine', 'sunflower', 'emerald_light', 'cobalt', 'z2v2', 'z3v3']
    for zz in (4.4, 5.8):
        barp.box(bk[0] - 0.9, bk[2] + 0.5, zz - 0.25, bk[0], bk[3] - 0.5, zz, 'white_gloss', chamfer=0.06)
        yy = bk[2] + 0.9
        while yy < bk[3] - 0.9:
            if not any(abs(yy - sy_) < bar['screen_w'] / 2 + 0.2 and False for sy_ in bar['screens_y']):
                hgt = rng.uniform(0.7, 1.0)
                barp.box(bk[0] - 0.7, yy - 0.18, zz, bk[0] - 0.34, yy + 0.18, zz + hgt, rng.choice(candy),
                         chamfer=0.1)
            yy += rng.uniform(0.55, 0.8)
    for i, sy_ in enumerate(bar['screens_y']):
        cen = (bk[0] - 0.05, sy_, sum(bar['screen_z']) / 2)
        sw_, sh_ = bar['screen_w'], bar['screen_z'][1] - bar['screen_z'][0]
        framed_panel(barp, (bk[0], sy_, cen[2]), sw_, sh_, '-X', depth=0.3, border=0.25)
        screen_quad('Screen_Leader_%d' % (i + 1), (bk[0] - 0.32, sy_, cen[2]), sw_, sh_, '-X', screen_material())
    lz = bar['screen_z'][1] + 1.2
    framed_panel(barp, (bk[0], (bk[2] + bk[3]) / 2, lz), 6.0, 1.5, '-X', depth=0.3, border=0.2)
    screen_quad('Sign_Logo_Bar', (bk[0] - 0.32, (bk[2] + bk[3]) / 2, lz), 6.0, 1.5, '-X',
                surface_material('Sign_Logo'))
    # the lounge wall behind the sofas: diagonal LED lines (ref_03)
    xw = bk[1] + 0.04
    for k in range(6):
        ya = bk[2] + 1.0 + k * 4.2
        E['LED_Lounge'].poly([(xw, ya, 0.8), (xw, ya + 0.35, 0.8), (xw, ya + 3.6, bar['back_h'] - 0.8),
                              (xw, ya + 3.25, bar['back_h'] - 0.8)])
    # display case at the end of the bar (ref_05): white shelves of snacks
    dc = fu['display_case']
    barp.box(dc[0], dc[1], 0.0, dc[2], dc[3], 7.6, 'white_gloss', faces={'+z', '-x', '+x', '+y', '-y'}, kind='display')
    for zz in (1.6, 3.4, 5.2):
        for k in range(4):
            xx = dc[0] + 0.5 + k * (dc[2] - dc[0] - 1.0) / 3
            barp.box(xx - 0.3, dc[1] - 0.05, zz, xx + 0.3, dc[1] + 0.6, zz + 0.9, candy[(k + int(zz)) % len(candy)],
                     chamfer=0.12)
    # ---- lounge ------------------------------------------------------------------------------------------
    for i in range(3):
        yy = bk[2] + 2.0 + 3.5 + i * 7.2
        place(lib, 'Sofa', bk[1] + 1.8, yy, facing=(1, 0))
        place(lib, 'Pouf', bk[1] + 6.0, yy, tint=['sunflower', 'tangerine', 'coral'][i])
    lc = fu['lounge_cluster']
    for k, (dx, dy, fx, fy, tn) in enumerate(((0, 3.6, 0, -1, 'sunflower'), (0, -3.6, 0, 1, 'coral'),
                                               (3.6, 0, -1, 0, 'tangerine'), (-3.6, 0, 1, 0, 'cobalt'))):
        place(lib, 'Armchair', lc[0] + dx, lc[1] + dy, facing=(fx, fy), tint=tn)
    furn.box(lc[0] - 1.4, lc[1] - 1.4, 1.2, lc[0] + 1.4, lc[1] + 1.4, 1.5, 'marble_flat', chamfer=0.12)
    furn.cylinder(lc[0], lc[1], 0.4, 0.0, 1.2, 12, 'gold', top=False)
    furn.rect(lc[0] - 1.4, lc[1] - 1.4, lc[0] + 1.4, lc[1] + 1.4, 'table_small')
    # capsule fluted glass screens with gold frames (ref_03)
    for k in range(3):
        cx_ = fu['capsules'][0] + k * 3.8
        cy_ = fu['capsules'][1]
        prof = []
        rr = 1.5
        for i in range(13):
            ang = math.pi * i / 12
            prof.append((cx_ + rr * math.cos(ang), 8.6 - rr + rr * math.sin(ang)))
        prof = [(cx_ + rr, 1.0 + rr - rr)] + prof[::-1][::-1]
        pts_top = [(cx_ + rr * math.cos(math.pi * i / 12), 8.6 - rr + rr * math.sin(math.pi * i / 12)) for i in range(13)]
        pts_bot = [(cx_ - rr * math.cos(math.pi * i / 12), 1.2 + rr - rr * math.sin(math.pi * i / 12)) for i in range(13)]
        stadium = pts_top + pts_bot
        for yface, sgn in ((cy_ - 0.12, -1), (cy_ + 0.12, 1)):
            pts = [(x_, yface, z_) for x_, z_ in stadium]
            fluted.poly(pts[::-1] if sgn > 0 else pts)
        n = len(stadium)
        for i in range(n):
            (xa, za), (xb, zb) = stadium[i], stadium[(i + 1) % n]
            furn.poly([(xa, cy_ - 0.2, za), (xb, cy_ - 0.2, zb), (xb, cy_ + 0.2, zb), (xa, cy_ + 0.2, za)], 'gold')
            ex, ez = (xa - cx_), (za - 4.9)
            ln_ = math.hypot(ex, ez) or 1
            o = 0.28
            furn.poly([(xa + ex / ln_ * o, cy_ - 0.2, za + ez / ln_ * o), (xb + (xb - cx_) / (math.hypot(xb - cx_, zb - 4.9) or 1) * o,
                        cy_ - 0.2, zb + (zb - 4.9) / (math.hypot(xb - cx_, zb - 4.9) or 1) * o),
                       (xb + (xb - cx_) / (math.hypot(xb - cx_, zb - 4.9) or 1) * o, cy_ + 0.2,
                        zb + (zb - 4.9) / (math.hypot(xb - cx_, zb - 4.9) or 1) * o),
                       (xa + ex / ln_ * o, cy_ + 0.2, za + ez / ln_ * o)][::-1], 'gold')
        furn.box(cx_ - 1.2, cy_ - 0.6, 0.0, cx_ + 1.2, cy_ + 0.6, 1.2, 'gold', chamfer=0.1, kind='screen')
        del prof
    # white geometric lattice screens (ref_07), see-through dividers by the walkway
    for k, lx in enumerate(fu['lattice_x']):
        ly = fu['lattice_y']
        lw, lh = 4.0, 8.0
        furn.box(lx, ly - 0.2, 0.0, lx + lw, ly + 0.2, 0.3, 'white_gloss', kind='partition')
        for (ax_, az_), (bx_, bz_) in lattice_bars(lx, lw, lh):
            tube(furn, (ax_, ly, az_), (bx_, ly, bz_), 0.28, 'white_gloss')
    # the wavy LED ribbon hanging over the lounge (ref_03)
    rb = fu['ribbon']
    n = 48
    prev = None
    for i in range(n + 1):
        t_ = i / n
        x_ = rb[0] + (rb[1] - rb[0]) * t_
        y_ = rb[2] + math.sin(t_ * math.pi * 2.5) * rb[3]
        z_ = rb[4] + math.sin(t_ * math.pi * 1.5 + 0.6) * 0.8
        if prev is not None:
            px_, py_, pz_ = prev
            E['LED_Lounge'].poly([(px_, py_, pz_), (x_, y_, z_), (x_, y_, z_ + 0.6), (px_, py_, pz_ + 0.6)])
            E['LED_Lounge'].poly([(px_, py_, pz_ + 0.6), (x_, y_, z_ + 0.6), (x_, y_, z_), (px_, py_, pz_)])
        prev = (x_, y_, z_)
    for t_ in (0.1, 0.5, 0.9):
        x_ = rb[0] + (rb[1] - rb[0]) * t_
        y_ = rb[2] + math.sin(t_ * math.pi * 2.5) * rb[3]
        z_ = rb[4] + math.sin(t_ * math.pi * 1.5 + 0.6) * 0.8
        furn.box(x_ - 0.125, y_ - 0.125, z_ + 0.6, x_ + 0.125, y_ + 0.125, H, 'gold')
    # booths under the balcony: coral backs, cobalt seats, marble tables
    bx_ = fu['booths']
    nb = bx_[2]
    bw_ = (bx_[1] - bx_[0]) / nb
    for k in range(nb):
        xa = bx_[0] + k * bw_
        for side, xs in ((-1, xa + 0.3), (1, xa + bw_ - 0.3)):
            xin = xs - side * 2.4
            booths.box(min(xs, xin), y0, 0.0, max(xs, xin), y0 + 7.0, 1.7, 'cobalt', chamfer=0.3, kind='seat', zone='lounge')
            booths.box(min(xs, xs - side * 0.8), y0, 1.7, max(xs, xs - side * 0.8), y0 + 7.0, 4.6, 'coral', chamfer=0.3)
        booths.box(xa + 3.1, y0 + 0.5, 2.3, xa + bw_ - 3.1, y0 + 5.8, 2.6, 'marble_flat', chamfer=0.12)
        booths.cylinder(xa + bw_ / 2, y0 + 3.0, 0.35, 0.0, 2.3, 10, 'gold', top=False)
        anchor('Seat_Booth_%d_W' % (k + 1), (xa + 1.5, y0 + 3.5, 1.7), 90.0)
        anchor('Seat_Booth_%d_E' % (k + 1), (xa + bw_ - 1.5, y0 + 3.5, 1.7), -90.0)
    # ---- kiosks: shop and trade (the cue shop corner) --------------------------------------------------
    kw, kd, kh = P['kiosks']['size']
    for nm, sw_ in (('Kiosk_Shop', 'tangerine'), ('Kiosk_Trade', 'coral')):
        kx, ky = P['kiosks'][nm]
        kiosk.box(kx - kw / 2, ky - kd / 2, 0.0, kx + kw / 2, ky + kd / 2, 3.2, 'white_gloss', chamfer=0.35, kind='kiosk')
        kiosk.box(kx - kw / 2 - 0.05, ky - kd / 2 - 0.05, 2.2, kx + kw / 2 + 0.05, ky + kd / 2 + 0.05, 2.7, sw_, chamfer=0.1)
        kiosk.box(kx - 0.25, ky - 0.25, 3.2, kx + 0.25, ky + 0.25, 6.3, 'gold')
        kiosk.box(kx - kw / 2 - 0.3, ky - 0.35, 6.3, kx + kw / 2 + 0.3, ky + 0.35, 8.2, sw_, chamfer=0.25)
        E[nm].box(kx - kw / 2 - 0.1, ky + 0.36, 6.55, kx + kw / 2 + 0.1, ky + 0.38, 6.85, 'wall')
        screen_quad('Screen_' + nm, (kx, ky + kd / 2 + 0.01, 3.6 + 1.1), 2.2, 1.2, '+Y', screen_material())
        kiosk.box(kx - 1.3, ky + kd / 2 - 0.1, 3.9, kx + 1.3, ky + kd / 2, 5.4, 'white_gloss', chamfer=0.08)
        anchor(nm, (kx, ky, 0.0), 0.0)
    # ---- the jukebox --------------------------------------------------------------------------------------
    jx, jy = fu['jukebox']
    jbox.box(jx - 1.3, jy - 0.8, 0.0, jx + 1.3, jy + 0.8, 3.6, 'coral', chamfer=0.25, kind='jukebox')
    arch = [(jx + 1.3 * math.cos(math.pi * i / 10), 3.6 + 1.3 * math.sin(math.pi * i / 10)) for i in range(11)]
    for yface, sgn in ((jy - 0.8, -1), (jy + 0.8, 1)):
        pts = [(x_, yface, z_) for x_, z_ in arch]
        jbox.poly(pts[::-1] if sgn > 0 else pts, 'coral')
    for i in range(10):
        (xa, za), (xb, zb) = arch[i], arch[i + 1]
        jbox.poly([(xa, jy - 0.8, za), (xa, jy + 0.8, za), (xb, jy + 0.8, zb), (xb, jy - 0.8, zb)], 'sunflower')
        E['Jukebox'].poly([(xa * 0.86 + jx * 0.14, jy + 0.82, (za - 3.6) * 0.86 + 3.6),
                           (xb * 0.86 + jx * 0.14, jy + 0.82, (zb - 3.6) * 0.86 + 3.6),
                           (xb * 0.72 + jx * 0.28, jy + 0.82, (zb - 3.6) * 0.72 + 3.6),
                           (xa * 0.72 + jx * 0.28, jy + 0.82, (za - 3.6) * 0.72 + 3.6)][::-1])
    jbox.box(jx - 0.9, jy + 0.8, 1.2, jx + 0.9, jy + 0.9, 2.8, 'black_gloss')
    anchor('Jukebox', (jx, jy, 0.0), 0.0)
    # ---- the piano stage placeholder --------------------------------------------------------------------
    ps = P['piano_stage']
    pcx, pcy = ps['centre']
    build_piano(piano, pbench, pcx, pcy, ps['height'])
    anchor('Piano', (pcx, pcy, ps['height']), 180.0)
    anchor('Piano_Bench', (pcx - 4.6, pcy - 0.6, ps['height']), -90.0)
    # ---- podium: top-3 statues ---------------------------------------------------------------------------
    pod = P['podium']
    for i, (px_, h_) in enumerate(zip(pod['x'], pod['h'])):
        rank = [2, 1, 3][i]
        place(lib, 'Plinth', px_, pod['y'], scale=(1.0, 1.0, h_), facing=(0, 1))
        anchor('Statue_%d' % rank, (px_, pod['y'], h_), 0.0)
    # ---- cue room: racks on the back wall, showcase slots --------------------------------------------------
    cx0_, cx1_ = L['cue_x']
    k = 0
    for i, rx in enumerate(np.linspace(cx0_ + 3.5, cx1_ - 3.5, 4)):
        place(lib, 'CueRack', float(rx), y0 + 0.02, facing=(0, 1))
        for j in range(3):
            k += 1
            anchor('Showcase_Cue_%d' % k, (float(rx) - 1.2 + j * 1.2, y0 + 0.6, 3.8), 0.0)
    place(lib, 'Plinth', (cx0_ + cx1_) / 2, (y0 + bf) / 2 + 1.0, scale=(1.0, 1.0, 1.4))
    k += 1
    anchor('Showcase_Cue_%d' % k, ((cx0_ + cx1_) / 2, (y0 + bf) / 2 + 1.0, 1.5), 90.0)
    # ---- zone signs and zone screens (overhead, facing the way people arrive) --------------------------------
    for zone, (cx_, cy_), facing, zs in fu['zone_signs']:
        sgn_c = (cx_, cy_, zs + 2.0)
        framed_panel(signs, sgn_c, 8.0, 4.0, facing, depth=0.5, border=0.4)
        mesh = screen_quad('Sign_Zone_' + zone, offset_front(sgn_c, facing, 0.01), 8.0, 4.0, facing,
                           surface_material('Sign_Zone_' + zone), props={'zone': zone})
        mesh['hub_screen'] = 0
        mesh['hub_sign'] = 1
        scr_c = (cx_, cy_, zs - 2.9)
        framed_panel(signs, scr_c, 7.2, 4.05, facing, depth=0.5, border=0.3)
        screen_quad('Screen_Zone_' + zone, offset_front(scr_c, facing, 0.01), 7.2, 4.05, facing, screen_material(),
                    props={'zone': zone})
        # halo in the zone colour around the sign
        g = E['SignGlow_' + zone]
        fr_c = offset_front(sgn_c, facing, -0.26)
        glow_frame(g, fr_c, 8.0 + 1.2, 4.0 + 1.2, facing, 0.3)
        for dx in (-3.0, 3.0):  # hanging rods
            p_ = offset_side((cx_, cy_), facing, dx)
            signs.box(p_[0] - 0.125, p_[1] - 0.125, zs + 4.4, p_[0] + 0.125, p_[1] + 0.125,
                      P['arch']['tray_top'] if L['walk_s'] <= cy_ <= L['walk_n'] else H, 'gold')
    # ---- featured screen on the south wall above the balcony ------------------------------------------------
    fz = (fs['z'][0] + fs['z'][1]) / 2
    fh = fs['z'][1] - fs['z'][0]
    framed_panel(signs, (fcx, y0 + 0.5, fz), fs['w'], fh, '+Y', depth=0.5, border=0.45)
    screen_quad('Screen_Featured', (fcx, y0 + 0.51, fz), fs['w'], fh, '+Y', screen_material())
    # the balcony logo panel on the railing over the lounge
    lg = fu['logo_balcony']
    screen_quad('Sign_Logo_Balcony', (lg[0], bf + 0.02, bz + 1.6), 2.6, 2.6, '+Y', surface_material('Sign_Logo'))
    # ---- plants, terrace, string lights ------------------------------------------------------------------
    for (px_, py_) in fu['plants']:
        place(lib, 'Plant', px_, py_)
    for (px_, py_) in fu['balcony_plants']:
        place(lib, 'Plant', px_, py_, bz)
    for k, (ux, uy) in enumerate(fu['umbrellas']):
        place(lib, 'Umbrella', ux, uy)
        for (dx, dy, fx_, fy_) in ((0, 3.2, 0, -1), (0, -3.2, 0, 1)):
            place(lib, 'Armchair', ux + dx, uy + dy, facing=(fx_, fy_), tint=['coral', 'cobalt', 'tangerine'][k])
        place(lib, 'Pouf', ux + 3.0, uy, tint=['sunflower', 'coral', 'sunflower'][k])
        place(lib, 'SideTable', ux - 2.6, uy)
    for (px_, py_) in fu['terrace_plants']:
        place(lib, 'Plant', px_, py_)
    # string lights: catenaries from the building to the railing posts (glow meshes)
    posts = [(tex1 - 0.6, yy) for yy in np.linspace(ty0 + 2.0, ty1 - 2.0, 4)]
    for (qx, qy) in posts:
        terr_post(furn, qx, qy)
    for i, (qx, qy) in enumerate(posts):
        a_ = (tex0 + 0.2, qy + (-3.0 if i % 2 else 3.0), 11.0)
        b_ = (qx, qy, 9.0)
        catenary(E['StringLights'], a_, b_, 1.6, 24)
    # ---- walkway and plaza extras: plants by the pro door, benches are armchair pairs already --------------
    # ---- anchors: spawn, door, decor, secrets ------------------------------------------------------------
    anchor('Spawn', L['spawn'], 0.0)
    anchor('Door_ProLobby', (x0 + 0.4, walk_c, 0.0), -90.0)
    for i, (dx, dy, dz) in enumerate(fu['decor']):
        anchor('Decor_Seasonal_%d' % (i + 1), (dx, dy, dz), 0.0)
    for i, (dx, dy, dz) in enumerate(fu['secrets']):
        anchor('Secret_%d' % (i + 1), (dx, dy, dz), 0.0)
    for tb in L['tables']:
        anchor('Pad_%d' % tb['n'], (tb['pad'][0], tb['pad'][1], 0.0), tb['yaw'], table=tb['n'], zone=tb['zone'])
    # stair seats: sittable spots along each tier
    ss = P['stair_seats']
    for kk in range(1, ss['tiers'] + 1):
        yb = foot - (kk - 1) * ss['run']
        for j in range(3):
            anchor('Seat_StairSeat_%d_%d' % (kk, j + 1), (tx0 + 1.8 + j * 3.2, yb - 1.1, kk * ss['rise'] + 0.45), 0.0)
    # ---- pendants: one per table, the zone's shape -------------------------------------------------------
    shape = {'1v1': 'Hex', '2v2': 'Square', '3v3': 'Y'}
    for tb in L['tables']:
        place(lib, 'Pendant_' + shape[tb['zone']], tb['x'], tb['y'], P['pendant']['bottom'], yaw=tb['yaw'],
              name='Pendant_T%d' % tb['n'])
    objs = B.emit()
    stage3_collision(L)
    n_props = sum(1 for o in pkg_collection('HUB_Props').objects if o.get('hub_part') == 0)
    print('HUB furnish: %d furniture meshes, %d prop placements (%d armchairs in bands), %d anchors' % (
        len(objs), n_props, chairs, len(anchors)))
    return objs


def offset_front(c, facing, d):
    fx, fy = {'+X': (1, 0), '-X': (-1, 0), '+Y': (0, 1), '-Y': (0, -1)}[facing]
    return (c[0] + fx * d, c[1] + fy * d, c[2])


def offset_side(c, facing, d):
    fx, fy = {'+X': (1, 0), '-X': (-1, 0), '+Y': (0, 1), '-Y': (0, -1)}[facing]
    return (c[0] + fy * d, c[1] - fx * d)


def glow_frame(batch, c, w, h, facing, th):
    """A glowing rectangle outline (the zone-colour halo behind a sign), facing out."""
    fx, fy = {'+X': (1, 0), '-X': (-1, 0), '+Y': (0, 1), '-Y': (0, -1)}[facing]
    rx, ry = -fy, fx

    def pt(u, v):
        return (c[0] + rx * u, c[1] + ry * u, c[2] + v)
    for (u0, v0, u1, v1) in ((-w / 2, -h / 2, w / 2, -h / 2 + th), (-w / 2, h / 2 - th, w / 2, h / 2),
                             (-w / 2, -h / 2, -w / 2 + th, h / 2), (w / 2 - th, -h / 2, w / 2, h / 2)):
        batch.poly([pt(u0, v0), pt(u1, v0), pt(u1, v1), pt(u0, v1)])


def lattice_bars(x0_, w_, h_):
    """A white geometric lattice (ref_07): frame plus an irregular triangle web."""
    pts = [(0.0, 0.3), (w_, 0.3), (w_, h_), (0.0, h_)]
    bars = [(pts[i], pts[(i + 1) % 4]) for i in range(4)]
    web = [((0.0, 2.2), (w_ * 0.7, 0.3)), ((w_ * 0.7, 0.3), (w_, 3.4)), ((0.0, 2.2), (w_, 3.4)),
           ((0.0, 5.1), (w_, 3.4)), ((0.0, 5.1), (w_ * 0.45, h_)), ((w_ * 0.45, h_), (w_, 6.2)),
           ((w_, 6.2), (0.0, 5.1)), ((w_ * 0.3, 3.9), (w_ * 0.7, 0.3))]
    out = []
    for (a_, b_) in bars + web:
        out.append(((x0_ + a_[0], a_[1]), (x0_ + b_[0], b_[1])))
    return out


def terr_post(batch, x, y):
    batch.box(x - 0.3, y - 0.3, 0.0, x + 0.3, y + 0.3, 9.4, 'navy', chamfer=0.08)
    batch.box(x - 0.45, y - 0.45, 9.4, x + 0.45, y + 0.45, 9.7, 'gold', chamfer=0.08)


def catenary(batch, a, b, sag, n):
    """A glowing string of lights between two points: a thin cord plus bulbs (both Neon)."""
    a, b = Vector(a), Vector(b)
    pts = []
    for i in range(n + 1):
        t = i / n
        p = a.lerp(b, t)
        p.z -= sag * 4 * t * (1 - t)
        pts.append(p)
    for i in range(n):
        p, q = pts[i], pts[i + 1]
        batch.poly([(p.x, p.y - 0.13, p.z), (q.x, q.y - 0.13, q.z), (q.x, q.y + 0.13, q.z), (p.x, p.y + 0.13, p.z)])
        batch.poly([(p.x, p.y + 0.13, p.z), (q.x, q.y + 0.13, q.z), (q.x, q.y - 0.13, q.z), (p.x, p.y - 0.13, p.z)])
    for i in range(1, n, 2):
        p = pts[i]
        r = 0.22
        oct_ = [(p.x + r, p.y, p.z - 0.25), (p.x, p.y + r, p.z - 0.25), (p.x - r, p.y, p.z - 0.25), (p.x, p.y - r, p.z - 0.25)]
        top, bot = (p.x, p.y, p.z), (p.x, p.y, p.z - 0.6)
        for j in range(4):
            batch.poly([oct_[j], oct_[(j + 1) % 4], top][::-1])
            batch.poly([oct_[j], oct_[(j + 1) % 4], bot])


def build_piano(piano, bench, cx, cy, z):
    """Placeholder_Piano: a glossy black grand piano silhouette (under 2,000 triangles), keyboard
    facing -X, lid propped open, on three legs; Placeholder_Piano_Bench in front of the keys."""
    # the grand's curved outline, in piano-local coordinates (x: keyboard to tail, y: across)
    outline = [(0.0, -2.1), (1.9, -2.1), (3.6, -1.8), (5.0, -1.05), (5.9, 0.0), (6.3, 1.0), (6.0, 1.7),
               (5.0, 2.1), (0.0, 2.1)]
    fine = []
    for i in range(len(outline) - 1):
        (ax_, ay_), (bx_, by_) = outline[i], outline[i + 1]
        for k in range(3):
            t = k / 3
            fine.append((ax_ + (bx_ - ax_) * t, ay_ + (by_ - ay_) * t))
    fine.append(outline[-1])
    ox, oy = cx - 3.0, cy

    def w(p):
        return (ox + p[0], oy + p[1])
    body = [w(p) for p in fine]
    piano.prism(body, z + 2.0, z + 3.3, 'black_gloss', bottom=True)
    # keyboard and key bed
    piano.box(ox - 1.1, oy - 2.1, z + 2.35, ox, oy + 2.1, z + 2.85, 'black_gloss', chamfer=0.08)
    piano.box(ox - 1.0, oy - 1.95, z + 2.85, ox - 0.05, oy + 1.95, z + 2.95, 'key_white')
    for k in range(18):
        yy = oy - 1.8 + k * 0.21
        if k % 7 in (2, 6):
            continue
        piano.box(ox - 0.45, yy - 0.05, z + 2.95, ox - 0.05, yy + 0.05 + 0.02, z + 3.05, 'black_gloss')
    piano.box(ox - 0.2, oy - 1.6, z + 3.3, ox + 0.05, oy + 1.6, z + 4.0, 'black_gloss')  # music desk
    # lid, propped open along the straight side
    lid = [(ox + p[0], oy + p[1], z + 3.35 + max(0.0, (2.1 - p[1])) * 0.62) for p in fine]
    piano.poly(lid, 'black_gloss')
    piano.poly(lid[::-1], 'black_gloss')
    tube(piano, (ox + 3.8, oy - 1.6, z + 3.3), (ox + 3.8, oy - 1.6, z + 3.35 + 3.7 * 0.62), 0.26, 'gold')
    # three legs with gold castors
    for lx, ly in ((0.6, -1.7), (0.6, 1.7), (5.2, 0.6)):
        piano.box(ox + lx - 0.3, oy + ly - 0.3, z + 0.3, ox + lx + 0.3, oy + ly + 0.3, z + 2.0, 'black_gloss', chamfer=0.1)
        piano.box(ox + lx - 0.32, oy + ly - 0.32, z, ox + lx + 0.32, oy + ly + 0.32, z + 0.3, 'gold', chamfer=0.08)
    piano.box(ox + 1.2, oy - 0.4, z + 0.3, ox + 1.7, oy + 0.4, z + 1.2, 'gold')  # pedals
    piano.rect(ox - 1.1, oy - 2.1, ox + 6.3, oy + 2.1, 'piano', block=True)
    # bench
    bx_ = ox - 2.6
    bench.box(bx_ - 0.8, oy - 1.8, z + 1.5, bx_ + 0.8, oy + 1.8, z + 2.0, 'black_gloss', chamfer=0.15)
    bench.box(bx_ - 0.7, oy - 1.7, z + 2.0, bx_ + 0.7, oy + 1.7, z + 2.3, 'coral', chamfer=0.14)
    for sx in (-1, 1):
        for sy in (-1, 1):
            bench.box(bx_ + sx * 0.55 - 0.13, oy + sy * 1.5 - 0.13, z, bx_ + sx * 0.55 + 0.13, oy + sy * 1.5 + 0.13, z + 1.5,
                      'black_gloss')


def stage3_collision(L):
    s = 3
    bar = P['bar']
    c = bar['counter']
    col_box('COL_BarCounter', c[0] - 0.45, c[2] - 0.3, 0.0, c[1] + 0.2, c[3] + 0.3, bar['counter_h'], s)
    bk = bar['back']
    col_box('COL_BarBack', bk[0] - 1.8, bk[2], 0.0, bk[1], bk[3], bar['back_h'], s)
    dc = P['furnish']['display_case']
    col_box('COL_DisplayCase', dc[0], dc[1], 0.0, dc[2], dc[3], 7.6, s)
    kw, kd, kh = P['kiosks']['size']
    for nm in ('Kiosk_Shop', 'Kiosk_Trade'):
        kx, ky = P['kiosks'][nm]
        col_box('COL_' + nm, kx - kw / 2, ky - kd / 2, 0.0, kx + kw / 2, ky + kd / 2, 8.2, s)
    jx, jy = P['furnish']['jukebox']
    col_box('COL_Jukebox', jx - 1.3, jy - 0.8, 0.0, jx + 1.3, jy + 0.8, 4.9, s)
    fu = P['furnish']
    for k in range(3):
        cx_ = fu['capsules'][0] + k * 3.8
        col_box('COL_Capsule_%d' % k, cx_ - 1.5, fu['capsules'][1] - 0.6, 0.0, cx_ + 1.5, fu['capsules'][1] + 0.6, 8.6, s)
    for k, lx in enumerate(fu['lattice_x']):
        col_box('COL_Lattice_%d' % k, lx, fu['lattice_y'] - 0.2, 0.0, lx + 4.0, fu['lattice_y'] + 0.2, 8.0, s)
    y0 = P['room']['y0']
    bx_ = fu['booths']
    bw_ = (bx_[1] - bx_[0]) / bx_[2]
    for k in range(bx_[2]):
        xa = bx_[0] + k * bw_
        col_box('COL_Booth_%d_W' % k, xa + 0.3, y0, 0.0, xa + 2.7, y0 + 7.0, 1.7, s)
        col_box('COL_Booth_%d_E' % k, xa + bw_ - 2.7, y0, 0.0, xa + bw_ - 0.3, y0 + 7.0, 1.7, s)
        col_box('COL_BoothTable_%d' % k, xa + 3.1, y0 + 0.5, 0.0, xa + bw_ - 3.1, y0 + 5.8, 2.6, s)
    ps = P['piano_stage']
    pcx, pcy = ps['centre']
    col_box('COL_Piano', pcx - 4.1, pcy - 2.1, ps['height'], pcx + 3.3, pcy + 2.1, ps['height'] + 4.0, s)


# =================================================================================================
# Stage 4a: the skybox orientation test (labelled faces, checked in Roblox Studio)
# =================================================================================================
ROBLOX_FACES = ['Bk', 'Dn', 'Ft', 'Lf', 'Rt', 'Up']


def stage_skytest():
    """Six labelled test faces: big face name, an arrow to the image top, corner letters (TL, TR)
    to catch mirroring. Upload them as a Sky in Studio and look along each axis."""
    colours = {'Bk': '#C0392B', 'Dn': '#6D4C41', 'Ft': '#1E88E5', 'Lf': '#43A047', 'Rt': '#8E24AA', 'Up': '#F9A825'}
    out = os.path.join(SKY_DIR, 'test')
    os.makedirs(out, exist_ok=True)
    for face in ROBLOX_FACES:
        def draw(scene, face=face):
            made = [sign_plane(scene, 10.24, 10.24, colours[face], 0.0, 'bg'),
                    sign_text(scene, face, 3.2, '#FFFFFF', (0.0, -1.2, 0.2), 'name'),
                    sign_text(scene, 'TL', 0.9, '#FFFFFF', (-4.3, 4.4, 0.2), 'tl'),
                    sign_text(scene, 'TR', 0.9, '#000000', (4.3, 4.4, 0.2), 'tr'),
                    sign_text(scene, 'TOP', 0.8, '#FFFFFF', (0.0, 3.6, 0.2), 'top')]
            me = bpy.data.meshes.new('arrow')
            me.from_pydata([(-0.9, 1.0, 0.1), (0.9, 1.0, 0.1), (0.0, 2.9, 0.1)], [], [(0, 1, 2)])
            me.materials.append(material('HubSign_arrow', '#FFFFFF', 1.0))
            o = bpy.data.objects.new('arrow', me)
            scene.collection.objects.link(o)
            return made + [o]
        img = render_sign('skytest_' + face, (1024, 1024), draw)
        write_png(os.path.join(out, 'Test_%s.png' % face), img[..., :3])
    print('HUB skytest faces written to', out)


# =================================================================================================
# Stage 4: skyline (skyboxes, cards, towers, haze deck) and lights
# =================================================================================================
class NG:
    """A tiny node-graph helper: numbers or sockets in, sockets out."""

    def __init__(self, tree):
        self.nodes, self.links = tree.nodes, tree.links

    def _in(self, sock, v):
        if isinstance(v, (int, float)):
            sock.default_value = v
        elif isinstance(v, tuple):
            sock.default_value = v
        elif v is not None:
            self.links.new(v, sock)

    def math(self, op, a, b=None, c=None, clamp=False):
        n = self.nodes.new('ShaderNodeMath')
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a, b, c)):
            if v is not None:
                self._in(n.inputs[i], v)
        return n.outputs[0]

    def vmath(self, op, a, b=None):
        n = self.nodes.new('ShaderNodeVectorMath')
        n.operation = op
        self._in(n.inputs[0], a)
        if b is not None:
            self._in(n.inputs[1], b)
        return n.outputs['Value'] if op in ('DOT_PRODUCT', 'LENGTH', 'DISTANCE') else n.outputs['Vector']

    def mix(self, fac, a, b):
        n = self.nodes.new('ShaderNodeMix')
        n.data_type = 'RGBA'
        self._in(socket(n.inputs, 'Factor_Float', 'Factor'), fac)
        self._in(socket(n.inputs, 'A_Color', 'A'), a)
        self._in(socket(n.inputs, 'B_Color', 'B'), b)
        return socket(n.outputs, 'Result_Color', 'Result')

    def sep(self, v):
        n = self.nodes.new('ShaderNodeSeparateXYZ')
        self._in(n.inputs[0], v)
        return n.outputs['X'], n.outputs['Y'], n.outputs['Z']

    def combine(self, x, y, z):
        n = self.nodes.new('ShaderNodeCombineXYZ')
        for i, v in enumerate((x, y, z)):
            self._in(n.inputs[i], v)
        return n.outputs[0]

    def noise(self, v):
        n = self.nodes.new('ShaderNodeTexWhiteNoise')
        n.noise_dimensions = '3D'
        self._in(n.inputs['Vector'], v)
        return n.outputs['Value']


def rgba(h):
    return (*lin(h), 1.0)


def sky_world(name, pr, stars=False):
    """Gradient sky, sun glow and (at night) stars."""
    world = bpy.data.worlds.get(name) or bpy.data.worlds.new(name)
    if world.node_tree is None:
        world.use_nodes = True
    nodes = world.node_tree.nodes
    nodes.clear()
    g = NG(world.node_tree)
    out = nodes.new('ShaderNodeOutputWorld')
    bg = nodes.new('ShaderNodeBackground')
    tc = nodes.new('ShaderNodeTexCoord')
    d = g.vmath('NORMALIZE', tc.outputs['Generated'])
    _x, _y, z = g.sep(d)
    t1 = g.math('POWER', g.math('MAXIMUM', z, 0.0), 0.45)
    c = g.mix(g.math('MULTIPLY', t1, 2.2, clamp=True), rgba(pr['horizon']), rgba(pr['mid']))
    c = g.mix(g.math('MULTIPLY_ADD', t1, 1.6, -0.5, clamp=True), c, rgba(pr['top']))
    below = g.math('LESS_THAN', z, 0.0)
    c = g.mix(below, c, rgba(pr['haze']))
    sd = Vector(pr['sun']).normalized()
    dot = g.vmath('DOT_PRODUCT', d, tuple(sd))
    glow = g.math('POWER', g.math('MAXIMUM', dot, 0.0), 24.0)
    disc = g.math('GREATER_THAN', dot, 0.9994)
    c = g.mix(g.math('MULTIPLY', glow, 0.75, clamp=True), c, rgba(pr['sun_colour']))
    c = g.mix(disc, c, rgba('#FFF4DE'))
    if stars:
        n = g.noise(g.vmath('FLOOR', g.vmath('MULTIPLY', d, (420.0, 420.0, 420.0))))
        st = g.math('MULTIPLY', g.math('GREATER_THAN', n, 0.9965), g.math('GREATER_THAN', z, 0.08))
        c = g.mix(st, c, rgba('#E8EEFF'))
    # Roblox lights a room with a flat Ambient/OutdoorAmbient, not with the skybox, so the preview
    # does the same: the camera (and glossy reflections) see the sky, everything else gets the ambient
    lp = nodes.new('ShaderNodeLightPath')
    see_sky = g.math('MAXIMUM', lp.outputs['Is Camera Ray'], lp.outputs['Is Glossy Ray'])
    c = g.mix(see_sky, rgba(pr['ambient']), c)
    world.node_tree.links.new(c, bg.inputs['Color'])
    bg.inputs['Strength'].default_value = pr['world']
    world.node_tree.links.new(bg.outputs['Background'], out.inputs['Surface'])
    world.color = lin(pr['horizon'])
    return world


def city_material(name, pr):
    """Far-city facade: glass window grid, lit windows at dusk and night, distance haze."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    g = NG(mat.node_tree)
    out = nodes.new('ShaderNodeOutputMaterial')
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    geo = nodes.new('ShaderNodeNewGeometry')
    cam = nodes.new('ShaderNodeCameraData')
    px, py, pz = g.sep(geo.outputs['Position'])
    nx, ny, nz = g.sep(geo.outputs['Normal'])
    side_x = g.math('GREATER_THAN', g.math('ABSOLUTE', nx), 0.5)
    hcoord = g.math('ADD', g.math('MULTIPLY', side_x, py), g.math('MULTIPLY', g.math('SUBTRACT', 1.0, side_x), px))
    cu = g.math('DIVIDE', hcoord, 6.0)
    cv = g.math('DIVIDE', pz, 8.0)
    fu = g.math('FRACT', cu)
    fv = g.math('FRACT', cv)
    win = g.math('MULTIPLY', g.math('MULTIPLY', g.math('GREATER_THAN', fu, 0.18), g.math('LESS_THAN', fu, 0.82)),
                 g.math('MULTIPLY', g.math('GREATER_THAN', fv, 0.28), g.math('LESS_THAN', fv, 0.84)))
    wall = g.math('LESS_THAN', g.math('ABSOLUTE', nz), 0.5)
    win = g.math('MULTIPLY', win, wall)
    cell = g.combine(g.math('FLOOR', cu), g.math('FLOOR', cv), g.math('FLOOR', g.math('DIVIDE', g.math('ADD', px, py), 97.0)))
    lit = g.math('MULTIPLY', win, g.math('LESS_THAN', g.noise(cell), pr['lit']))
    base = g.mix(win, rgba(pr['facade']), rgba(pr['glass']))
    fog = g.math('SUBTRACT', 1.0, g.math('EXPONENT', g.math('DIVIDE', cam.outputs['View Distance'], -2600.0)))
    col = g.mix(fog, base, rgba(pr['haze']))
    mat.node_tree.links.new(col, bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.45
    warm = g.mix(g.math('GREATER_THAN', g.noise(g.vmath('ADD', cell, (3.1, 7.7, 1.3))), 0.7), rgba('#FFC77A'), rgba('#CFE2FF'))
    mat.node_tree.links.new(warm, bsdf.inputs['Emission Color'])
    # street lamps on the ground grid (dusk and night): a lattice of warm dots
    flat = g.math('SUBTRACT', 1.0, wall)
    lamps = g.math('MULTIPLY', g.math('LESS_THAN', g.math('FRACT', g.math('DIVIDE', px, 24.0)), 0.07),
                   g.math('LESS_THAN', g.math('FRACT', g.math('DIVIDE', py, 24.0)), 0.07))
    lamps = g.math('MULTIPLY', g.math('MULTIPLY', lamps, flat), g.math('LESS_THAN', pz, P['sky']['city']['ground'] + 1.0))
    lamps = g.math('MULTIPLY', lamps, 1.0 if pr['lit'] > 0 else 0.0)
    glow = g.math('ADD', lit, lamps)
    mat.node_tree.links.new(g.math('MULTIPLY', glow, g.math('MULTIPLY', g.math('SUBTRACT', 1.0, fog), 3.0)),
                            bsdf.inputs['Emission Strength'])
    mat.node_tree.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat


def flat_emit_material(name, pr, layer):
    """Unlit mountain ridge: colour to haze towards the base."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    g = NG(mat.node_tree)
    out = nodes.new('ShaderNodeOutputMaterial')
    em = nodes.new('ShaderNodeEmission')
    geo = nodes.new('ShaderNodeNewGeometry')
    _x, _y, pz = g.sep(geo.outputs['Position'])
    t = g.math('DIVIDE', g.math('SUBTRACT', pz, -400.0), 2600.0, clamp=True)
    t = g.math('MINIMUM', g.math('MAXIMUM', t, 0.0), 1.0)
    c0, c1 = pr['mtn']
    ridge = g.mix(layer / 2.0, rgba(c0), rgba(c1))
    col = g.mix(t, rgba(pr['haze']), ridge)
    mat.node_tree.links.new(col, em.inputs['Color'])
    em.inputs['Strength'].default_value = 1.0 * pr['world']
    mat.node_tree.links.new(em.outputs[0], out.inputs['Surface'])
    return mat


def build_far_city():
    """The far layer (0 triangles in Roblox): a dense city, mountain ridges and a haze floor, only
    ever rendered into the skyboxes and seen through the windows in the Blender previews."""
    sk = P['sky']
    coll = pkg_collection('HUB_SkyFar')
    for o in list(coll.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    rng = random.Random(sk['city']['seed'])
    c = sk['city']
    verts, faces = [], []
    gz = c['ground']
    for i in range(c['count']):
        rr = math.sqrt(rng.uniform(c['r'][0] ** 2, c['r'][1] ** 2))
        a = rng.uniform(0, 2 * math.pi)
        cx, cy = rr * math.cos(a), rr * math.sin(a)
        # downtown clusters: north-west and north-east get the tallest towers
        boost = max(math.cos(a - math.radians(125)), math.cos(a - math.radians(60)), 0.0) ** 3
        low = rng.random() < 0.72  # a carpet of low blocks, fewer towers
        h = gz + (rng.uniform(25, 140) if low else rng.uniform(140, 330)) + \
            (0.0 if low else boost * rng.uniform(80, 520) * (1.0 - rr / c['r'][1] * 0.6))
        wx, wy = (rng.uniform(40, 130), rng.uniform(40, 130)) if low else (rng.uniform(30, 90), rng.uniform(30, 90))
        base = len(verts)
        x0_, x1_, y0_, y1_ = cx - wx / 2, cx + wx / 2, cy - wy / 2, cy + wy / 2
        verts += [(x0_, y0_, gz), (x1_, y0_, gz), (x1_, y1_, gz), (x0_, y1_, gz),
                  (x0_, y0_, h), (x1_, y0_, h), (x1_, y1_, h), (x0_, y1_, h)]
        faces += [(base + 0, base + 1, base + 5, base + 4), (base + 1, base + 2, base + 6, base + 5),
                  (base + 2, base + 3, base + 7, base + 6), (base + 3, base + 0, base + 4, base + 7),
                  (base + 4, base + 5, base + 6, base + 7)]
    me = bpy.data.meshes.new('SkyFar_City')
    me.from_pydata(verts, [], faces)
    city = bpy.data.objects.new('SkyFar_City', me)
    coll.objects.link(city)
    me2 = bpy.data.meshes.new('SkyFar_Ground')
    me2.from_pydata([(-30000, -30000, gz), (30000, -30000, gz), (30000, 30000, gz), (-30000, 30000, gz)], [],
                    [(0, 1, 2, 3)])
    ground = bpy.data.objects.new('SkyFar_Ground', me2)
    coll.objects.link(ground)
    ridges = []
    for li, (radius, lo, hi) in enumerate(sk['mountains']):
        n = 256
        rv, rf = [], []
        ph = [rng.uniform(0, 6.28) for _ in range(4)]
        for i in range(n):
            a = 2 * math.pi * i / n
            hh = lo + (hi - lo) * (0.5 + 0.22 * math.sin(3 * a + ph[0]) + 0.15 * math.sin(7 * a + ph[1]) +
                                   0.08 * math.sin(17 * a + ph[2]) + 0.05 * math.sin(41 * a + ph[3]))
            rv += [(radius * math.cos(a), radius * math.sin(a), -1500.0), (radius * math.cos(a), radius * math.sin(a), hh)]
        for i in range(n):
            j = (i + 1) % n
            rf.append((2 * j, 2 * i, 2 * i + 1, 2 * j + 1))
        mm = bpy.data.meshes.new('SkyFar_Ridge_%d' % li)
        mm.from_pydata(rv, [], rf)
        ro = bpy.data.objects.new('SkyFar_Ridge_%d' % li, mm)
        ro['layer'] = li
        coll.objects.link(ro)
        ridges.append(ro)
    for o in [city, ground] + ridges:
        o['hub_stage'] = 4
        o['hub_owned'] = 1
    return city, ground, ridges


def apply_time(preset):
    """Switch the whole scene (sky, far city, towers, cards, deck, sun) to Dusk, Day or Night."""
    sk = P['sky']
    pr = sk['presets'][preset]
    scene = bpy.context.scene
    scene.world = sky_world('HubSky_' + preset, pr, stars=(preset == 'Night'))
    coll = bpy.data.collections.get('HUB_SkyFar')
    if coll:
        for o in coll.objects:
            if o.name == 'SkyFar_City':
                mat = city_material('HubCity_' + preset, pr)
            elif o.name == 'SkyFar_Ground':
                mat = city_material('HubCity_' + preset, pr)  # streets: facade colour, lamp dots, haze
            else:
                mat = flat_emit_material('HubRidge_%s_%d' % (preset, o['layer']), pr, o['layer'])
            o.data.materials.clear()
            o.data.materials.append(mat)
    sun = bpy.data.objects.get('HUB_Sun')
    if sun is None:
        sd = bpy.data.lights.new('HUB_Sun', 'SUN')
        sun = bpy.data.objects.new('HUB_Sun', sd)
        pkg_collection('HUB_Preview').objects.link(sun)
        sun['hub_stage'] = 4
    sun.data.energy = pr['sun_strength']
    sun.data.color = lin(pr['sun_colour'])
    sun.data.angle = math.radians(1.0)
    d = Vector(pr['sun'])
    sun.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    # skyline meshes follow the time of day
    fac = {'Dusk': ('Facade_Night', 0.45), 'Day': ('Facade_Day', 0.0), 'Night': ('Facade_Night', 1.0)}[preset]
    tmat = facade_material(fac[0], fac[1], preset)
    cmat = card_material(preset)
    for o in pkg_collection('HUB_Props').objects:
        if o.get('hub_prop', '').startswith('Tower_'):
            o.data.materials.clear()
            o.data.materials.append(tmat)
    for o in pkg_collection('HUB_PropLibrary').objects:
        if o.get('hub_prop', '').startswith('Tower_'):
            o.data.materials.clear()
            o.data.materials.append(tmat)
    for o in pkg_collection('HUB_Skyline').objects:
        if o.name.startswith('Sky_Card'):
            o.data.materials.clear()
            o.data.materials.append(cmat)
        elif o.name == 'Sky_HazeDeck':
            o.data.materials.clear()
            o.data.materials.append(deck_material(preset))
    scene['hub_time'] = preset


# ---- facade trim texture and silhouette cards --------------------------------------------------------
def tex_facade(night, dusk_mask=False):
    tp = P['textures']['facade']
    n, cells = tp['size'], tp['cells']
    cp = n // cells
    rng = np.random.default_rng(P['textures']['seed'] * 1000 + 40)
    lit = rng.random((cells, cells))
    warmth = rng.random((cells, cells))
    shade = rng.random((cells, cells))
    yy, xx = np.mgrid[0:n, 0:n]
    fu, fv = (xx % cp) / cp, (yy % cp) / cp
    win = (fu > 0.12) & (fu < 0.88) & (fv > 0.18) & (fv < 0.78)
    ci, cj = yy // cp, xx // cp
    col = np.zeros((n, n, 3), np.float32)
    if night:
        facade, glass = np.array(hex_rgb('#262C43')), np.array(hex_rgb('#121830'))
    else:
        facade, glass = np.array(hex_rgb('#DCE1EA')), np.array(hex_rgb('#6F8FB8'))
    g_grad = (0.85 + 0.3 * fv)[..., None] if not night else 1.0
    col[:] = facade
    gl = glass[None, None, :] * (0.9 + 0.2 * shade[ci, cj])[..., None] * g_grad
    col = np.where(win[..., None], gl, col)
    rough = np.where(win, 0.12, 0.6).astype(np.float32)
    maps = {'Color': col, 'Roughness': rough}
    if night:
        on = win & (lit[ci, cj] < 0.42)
        on_dusk = win & (lit[ci, cj] < 0.16)
        warm = np.where((warmth[ci, cj] > 0.7)[..., None], np.array(hex_rgb('#CFE2FF')), np.array(hex_rgb('#FFD08A')))
        col = np.where(on[..., None], warm * (0.85 + 0.15 * fv)[..., None], col)
        maps['Color'] = col
        maps['Emissive'] = on.astype(np.float32)
        maps['EmissiveDusk'] = on_dusk.astype(np.float32)
    return maps


def tex_cards(night):
    tp = P['textures']['cards']
    w, h = tp['master'], tp['height']
    rng = random.Random(P['textures']['seed'] * 1000 + 50)
    height = np.zeros(w, np.float32)
    x = 0
    spires = []
    while x < w:
        bw = rng.randint(18, 70)
        bh = rng.randint(60, 300) if rng.random() > 0.12 else rng.randint(300, 440)
        height[x:x + bw] = np.maximum(height[x:x + bw], bh)
        if rng.random() < 0.08:
            spires.append((x + bw // 2, bh + rng.randint(20, 60)))
        x += bw - rng.randint(0, 10)
    alpha = np.zeros((h, w), np.float32)
    rows = np.arange(h)[:, None]
    alpha[(h - rows) <= height[None, :]] = 1.0
    for sx, sh in spires:
        alpha[max(0, h - sh):h, sx - 1:sx + 2] = 1.0
    yy, xx = np.mgrid[0:h, 0:w]
    win = ((xx % 7) < 3) & ((yy % 9) < 4)
    nrng = np.random.default_rng(P['textures']['seed'] * 1000 + 51)
    litmap = nrng.random((h // 9 + 1, w // 7 + 1))
    lit = win & (litmap[yy // 9, xx // 7] < (0.34 if night else 0.0)) & (alpha > 0)
    grad = (yy / h).astype(np.float32)[..., None]
    if night:
        base = np.array(hex_rgb('#141B31'))[None, None, :] * (0.8 + 0.4 * grad)
        col = np.where(lit[..., None], np.array(hex_rgb('#FFD08A')), base)
    else:
        top, bot = np.array(hex_rgb('#6F83A6')), np.array(hex_rgb('#93A7C4'))
        col = top * (1 - grad) + bot * grad
        col = np.where(win[..., None], col * 1.12, col)
    rgba_ = np.concatenate([col, alpha[..., None]], axis=-1).astype(np.float32)
    maps = {'Color': rgba_, 'Roughness': np.full((h, w), 0.9, np.float32)}
    if night:
        maps['Emissive'] = lit.astype(np.float32)
    return maps


SKY_BUILDERS = {'Facade_Day': ('facade', lambda: tex_facade(False)),
                'Facade_Night': ('facade', lambda: tex_facade(True)),
                'Cards_Day': ('cards', lambda: tex_cards(False)),
                'Cards_Night': ('cards', lambda: tex_cards(True))}


def facade_material(set_name, emit, preset):
    name = 'Hub_Facade_' + preset
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
    for m, data in (('Color', False), ('Roughness', True)):
        t = nodes.new('ShaderNodeTexImage')
        t.image = load_image('%s_%s.png' % (set_name, m), data)
        links.new(uv.outputs['UV'], t.inputs['Vector'])
        links.new(t.outputs['Color'], bsdf.inputs['Base Color' if m == 'Color' else 'Roughness'])
        if m == 'Color':
            colour_out = t.outputs['Color']
    if emit > 0:
        t = nodes.new('ShaderNodeTexImage')
        t.image = load_image('Facade_Night_%s.png' % ('EmissiveDusk' if preset == 'Dusk' else 'Emissive'), True)
        links.new(uv.outputs['UV'], t.inputs['Vector'])
        links.new(colour_out, bsdf.inputs['Emission Color'])
        g = NG(mat.node_tree)
        links.new(g.math('MULTIPLY', t.outputs['Color'], 4.0 * emit), bsdf.inputs['Emission Strength'])
    mat['hub_surface'] = set_name
    return mat


def card_material(preset):
    set_name = 'Cards_Day' if preset == 'Day' else 'Cards_Night'
    name = 'Hub_Cards_' + preset
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
    t = nodes.new('ShaderNodeTexImage')
    t.image = load_image(set_name + '_Color.png', False)
    t.interpolation = 'Closest'
    links.new(uv.outputs['UV'], t.inputs['Vector'])
    pr = P['sky']['presets'][preset]
    g = NG(mat.node_tree)
    tinted = g.mix(0.35 if preset == 'Dusk' else 0.0, t.outputs['Color'], rgba(pr['haze']))
    links.new(tinted, bsdf.inputs['Base Color'])
    links.new(g.math('GREATER_THAN', t.outputs['Alpha'], 0.5), bsdf.inputs['Alpha'])
    bsdf.inputs['Roughness'].default_value = 0.9
    if preset != 'Day':
        e = nodes.new('ShaderNodeTexImage')
        e.image = load_image('Cards_Night_Emissive.png', True)
        e.interpolation = 'Closest'
        links.new(uv.outputs['UV'], e.inputs['Vector'])
        links.new(t.outputs['Color'], bsdf.inputs['Emission Color'])
        links.new(g.math('MULTIPLY', e.outputs['Color'], 2.5 if preset == 'Night' else 1.2), bsdf.inputs['Emission Strength'])
    try:
        mat.surface_render_method = 'DITHERED'
    except (AttributeError, TypeError):
        pass
    mat['hub_surface'] = set_name
    return mat


def deck_material(preset):
    """The haze deck: vertex-colour gradient (bare MeshPart in Roblox) times the time's haze colour."""
    name = 'Hub_HazeDeck_' + preset
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new('ShaderNodeOutputMaterial')
    em = nodes.new('ShaderNodeEmission')
    va = nodes.new('ShaderNodeVertexColor')
    va.layer_name = 'Haze'
    g = NG(mat.node_tree)
    pr = P['sky']['presets'][preset]
    col = g.mix(1.0, va.outputs['Color'], rgba(pr['haze']))
    mix = nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    socket(mix.inputs, 'Factor_Float', 'Factor').default_value = 1.0
    links.new(va.outputs['Color'], socket(mix.inputs, 'A_Color', 'A'))
    socket(mix.inputs, 'B_Color', 'B').default_value = rgba(pr['haze'])
    links.new(socket(mix.outputs, 'Result_Color', 'Result'), em.inputs['Color'])
    em.inputs['Strength'].default_value = pr['world']
    links.new(em.outputs[0], out.inputs['Surface'])
    del col
    mat['hub_surface'] = 'VertexColour'
    return mat


# ---- near towers (prop masters) ------------------------------------------------------------------------
def tower_shapes():
    """Masters with no backs, bottoms or hidden faces. Local -Y faces the club."""
    return {
        'Tower_A': [('box', -20, 20, -14, 14, 0, 330), ('box', -14, 14, -10, 10, 330, 380), ('box', -5, 5, -5, 5, 380, 400)],
        'Tower_B': [('box', -15, 15, -15, 15, 0, 420), ('crown', -15, 15, -15, 15, 420, 450)],
        'Tower_C': [('oct', 18.0, 0, 300), ('oct', 12.0, 300, 360)],
        'Tower_D': [('box', -24, 4, -12, 12, 0, 240), ('box', 4, 22, -10, 10, 0, 290), ('box', 8, 18, -6, 6, 290, 320)],
    }


def build_tower(batch, parts, uoff):
    su, sv = P['sky']['facade_studs']
    roof_uv = (uoff + 0.02, 0.07)

    def face(pts):
        # u along the face, v up: windows keep their size on every face
        (ax, ay, az), (bx, by, bz_) = pts[0], pts[1]
        ln = math.hypot(bx - ax, by - ay)
        uvs = []
        for (x_, y_, z_) in pts:
            along = math.hypot(x_ - ax, y_ - ay)
            uvs.append((uoff + along / su, z_ / sv))
        batch.poly(pts, uvs=uvs)
        del ln
    for part in parts:
        if part[0] in ('box', 'crown'):
            _k, x0_, x1_, y0_, y1_, z0_, z1_ = part
            if part[0] == 'box':
                face([(x0_, y0_, z0_), (x1_, y0_, z0_), (x1_, y0_, z1_), (x0_, y0_, z1_)])  # front (-Y)
                face([(x0_, y1_, z0_), (x0_, y0_, z0_), (x0_, y0_, z1_), (x0_, y1_, z1_)])  # -X
                face([(x1_, y0_, z0_), (x1_, y1_, z0_), (x1_, y1_, z1_), (x1_, y0_, z1_)])  # +X
                batch.poly([(x0_, y0_, z1_), (x1_, y0_, z1_), (x1_, y1_, z1_), (x0_, y1_, z1_)], uvs=[roof_uv] * 4)
            else:  # a crown sloping up to the back edge
                batch.poly([(x0_, y0_, z0_), (x1_, y0_, z0_), (x1_, y1_, z1_), (x0_, y1_, z1_)], uvs=[roof_uv] * 4)
                batch.poly([(x0_, y1_, z0_), (x0_, y0_, z0_), (x0_, y1_, z1_)], uvs=[roof_uv] * 3)
                batch.poly([(x1_, y0_, z0_), (x1_, y1_, z0_), (x1_, y1_, z1_)], uvs=[roof_uv] * 3)
        else:
            _k, rr, z0_, z1_ = part
            pts = [(rr * math.cos(math.radians(-90 + 45 * i + 22.5)), rr * math.sin(math.radians(-90 + 45 * i + 22.5)))
                   for i in range(8)]
            for i in range(8):
                a_, b_ = pts[i], pts[(i + 1) % 8]
                mid_y = (a_[1] + b_[1]) / 2
                if mid_y > rr * 0.5:  # the back three faces are never seen
                    continue
                face([(a_[0], a_[1], z0_), (b_[0], b_[1], z0_), (b_[0], b_[1], z1_), (a_[0], a_[1], z1_)])
            batch.poly([(x_, y_, z1_) for x_, y_ in pts], uvs=[roof_uv] * 8)


def stage_skyline():
    scene = hub_scene()
    L = layout()
    clear_stage(4)
    ensure_textures(list(SKY_BUILDERS), SKY_BUILDERS)
    sk = P['sky']
    build_far_city()
    # near towers: masters in the prop library, placements facing the club
    lib = pkg_collection('HUB_PropLibrary')
    for o in list(lib.objects):
        if o.get('hub_prop', '').startswith('Tower_'):
            bpy.data.objects.remove(o, do_unlink=True)
    masters = {}
    for i, (name, parts) in enumerate(tower_shapes().items()):
        b = Batch(name, 'Facade_Night', 'HUB_PropLibrary', 4, uv='explicit',
                  material=facade_material('Facade_Night', 0.45, 'Dusk'))
        build_tower(b, parts, 0.25 * i)
        o = b.emit()[0]
        o['hub_prop'] = name
        o['hub_tint'] = 0
        masters[name] = o
    PROP_SPECS.update({n: {'tint': False, 'seats': [], 'kind': 'tower', 'block': False} for n in masters})
    tw = sk['towers']
    rng = random.Random(tw['seed'])
    coll = pkg_collection('HUB_Props')
    tints = ['#FFFFFF', '#E8EEFA', '#FFF1E0', '#DDE6F5']
    placed = 0
    tries = 0
    spots = []
    while placed < tw['count'] and tries < 5000:
        tries += 1
        a = rng.uniform(math.radians(-15), math.radians(195))  # east, north and west: what the windows see
        rr = rng.uniform(*tw['r'])
        x, y = rr * math.cos(a), rr * math.sin(a)
        if y < -60 and abs(x) < 200:
            continue
        if any(math.hypot(x - sx, y - sy) < 70 for sx, sy in spots):
            continue
        spots.append((x, y))
        name = list(masters)[placed % len(masters)]
        yaw = math.degrees(math.atan2(-x, y))  # local -Y towards the room centre
        sc = rng.uniform(0.85, 1.15)
        o = bpy.data.objects.new('%s_P%03d' % (name, placed + 1), masters[name].data)
        o.location = (x, y, tw['bottom'] + rng.uniform(-70, 30))
        o.rotation_euler = (0, 0, math.radians(yaw))
        o.scale = (sc, sc, rng.uniform(0.7, 1.05))
        coll.objects.link(o)
        o['hub_stage'] = 4
        o['hub_owned'] = 1
        o['hub_prop'] = name
        o['hub_master'] = name
        o['hub_part'] = 0
        o['hub_yaw'] = yaw
        o['hub_tint_hex'] = tints[placed % len(tints)]
        placed += 1
    # mid layer: silhouette cards facing the club
    for i, (cx, cy, wdt, strip) in enumerate(sk['cards']):
        nrm = Vector((-cx, -cy, 0)).normalized()
        right = Vector((-nrm.y, nrm.x, 0))
        z0_, z1_ = sk['card_z']
        c_ = Vector((cx, cy, 0))
        pts = [c_ - right * wdt / 2 + Vector((0, 0, z0_)), c_ + right * wdt / 2 + Vector((0, 0, z0_)),
               c_ + right * wdt / 2 + Vector((0, 0, z1_)), c_ - right * wdt / 2 + Vector((0, 0, z1_))]
        u0 = (strip * 0.37) % 1.0
        u1 = u0 + wdt / 1500.0
        b = Batch('Sky_Card_%d' % (i + 1), 'Cards_Night', 'HUB_Skyline', 4, uv='explicit', material=card_material('Dusk'))
        b.poly([tuple(p_) for p_ in pts], uvs=[(u0, 0.0), (u1, 0.0), (u1, 1.0), (u0, 1.0)])
        b.emit()
    # haze deck: a big flat ring just below the window sills, vertex colour gradient
    dk = sk['deck']
    n = dk['segments']
    b = Batch('Sky_HazeDeck', 'VertexColour', 'HUB_Skyline', 4, uv='explicit', material=deck_material('Dusk'))
    ring_in = [(95.0 * math.cos(2 * math.pi * i / n) * 1.5, 95.0 * math.sin(2 * math.pi * i / n) * 1.5) for i in range(n)]
    ring_out = [(dk['r'] * math.cos(2 * math.pi * i / n), dk['r'] * math.sin(2 * math.pi * i / n)) for i in range(n)]
    for i in range(n):
        j = (i + 1) % n
        b.poly([(*ring_in[i], dk['z']), (*ring_out[i], dk['z']), (*ring_out[j], dk['z']), (*ring_in[j], dk['z'])],
               uvs=[(0, 0)] * 4)
    deck = b.emit()[0]
    vc = deck.data.color_attributes.new('Haze', 'BYTE_COLOR', 'CORNER')
    cols = []
    for poly in deck.data.polygons:
        for li in poly.loop_indices:
            v = deck.data.vertices[deck.data.loops[li].vertex_index].co
            t = min(1.0, math.hypot(v.x, v.y) / dk['r'])
            k = 0.78 + 0.22 * t  # darker (denser) under the building, full haze at the horizon
            cols += [k, k, k, 1.0]
    vc.data.foreach_set('color', cols)
    apply_time('Dusk')
    tris = sum(tri_count(o) for o in pkg_collection('HUB_Skyline').objects) + \
        sum(tri_count(masters[o['hub_prop']]) for o in coll.objects if o.get('hub_prop', '').startswith('Tower_'))
    print('HUB skyline: %d towers, %d cards, skyline triangles %d' % (placed, len(sk['cards']), tris))


def face_camera(name, eye, forward, up, coll):
    cd = bpy.data.cameras.new(name)
    cd.type = 'PERSP'
    cd.sensor_fit = 'HORIZONTAL'
    cd.angle = math.radians(90.0)
    cd.clip_start, cd.clip_end = 1.0, 60000.0
    cam = bpy.data.objects.new(name, cd)
    f, u = Vector(forward).normalized(), Vector(up).normalized()
    r = f.cross(u)
    m = Matrix((r, u, -f)).transposed()  # camera looks down -Z with +Y up
    cam.matrix_world = Matrix.Translation(Vector(eye)) @ m.to_4x4()
    coll.objects.link(cam)
    return cam


# Blender direction of each Roblox skybox face, as found with the labelled test in Studio (see Readme):
# Ft looks towards Roblox -Z (Blender +Y, north), Bk +Z (south), Rt -X (west), Lf +X (east);
# Up and Dn: image top = Roblox +X / -X (Blender east / west), image right = Roblox -Z (north).
SKY_FACES = {'Ft': ((0, 1, 0), (0, 0, 1)), 'Bk': ((0, -1, 0), (0, 0, 1)), 'Rt': ((-1, 0, 0), (0, 0, 1)),
             'Lf': ((1, 0, 0), (0, 0, 1)), 'Up': ((0, 0, 1), (1, 0, 0)), 'Dn': ((0, 0, -1), (-1, 0, 0))}


def stage_skyboxes():
    """Render Dusk, Day and Night: six square faces each, only the far layer visible."""
    scene = bpy.context.scene
    sk = P['sky']
    os.makedirs(SKY_DIR, exist_ok=True)
    cams = pkg_collection('HUB_Cameras')
    set_engine(scene, 'BLENDER_EEVEE')
    scene.eevee.taa_render_samples = 16
    try:
        scene.view_settings.view_transform = 'Standard'
    except TypeError:
        pass
    root = bpy.data.collections[ROOT]
    saved = {c.name: c.hide_render for c in root.children}
    for c in root.children:
        c.hide_render = c.name != 'HUB_SkyFar'
    lib = bpy.data.collections.get('HUB_Lib')
    if lib:
        lib.hide_render = True
    for preset in ('Dusk', 'Day', 'Night'):
        apply_time(preset)
        for face, (fwd, up) in SKY_FACES.items():
            cam = face_camera('CAM_Sky_' + face, sk['eye'], fwd, up, cams)
            path = os.path.join(SKY_DIR, '%s_%s.png' % (preset, face))
            render_to(scene, cam, path, (sk['face_px'], sk['face_px']))
            bpy.data.objects.remove(cam, do_unlink=True)
    for c in root.children:
        c.hide_render = saved.get(c.name, False)
    if lib:
        lib.hide_render = False
    apply_time('Dusk')


# ---- lights: data for Roblox (Markers.json) and the matching Blender preview lights -------------------------
def lights_data(L):
    """Every light the game should create. SurfaceLight on a face, facing out of it; Brightness,
    Range and Angle are Roblox values. Kelvin is the colour temperature the colour stands for."""
    warm, pend = P['palette']['warm_led'], P['lights']['pendant']
    out = []
    shape_face = {'1v1': (16.4, 6.6), '2v2': (14.8, 8.6), '3v3': (14.0, 12.5)}
    for tb in L['tables']:
        w_, d_ = shape_face[tb['zone']]
        if tb['head'] in ('W', 'E'):
            size = (w_, d_)
        else:
            size = (d_, w_)
        out.append({'name': 'Light_Pendant_%d' % tb['n'], 'type': 'SurfaceLight', 'position': [tb['x'], tb['y'], P['pendant']['bottom'] - 0.05],
                    'direction': [0, 0, -1], 'face_size': list(size), 'colour': warm, 'kelvin': 3800,
                    'brightness': pend['brightness'], 'range': pend['range'], 'angle': pend['angle'], 'shadows': False,
                    'attach': 'Pendant_T%d' % tb['n']})
    for a in P['lights']['ambient']:
        out.append(dict(a))
    return out


def build_preview_lights(L):
    coll = pkg_collection('HUB_Preview')
    for o in list(coll.objects):
        if o.get('hub_light'):
            bpy.data.objects.remove(o, do_unlink=True)
    k = P['lights']['preview']
    for d in lights_data(L):
        t = d['type']
        if t == 'SurfaceLight':
            ld = bpy.data.lights.new(d['name'], 'AREA')
            ld.shape = 'RECTANGLE'
            ld.size, ld.size_y = d['face_size']
            ld.energy = d['brightness'] * d['face_size'][0] * d['face_size'][1] * k['surface']
            ld.spread = math.radians(min(180, d['angle'] * 2))
        elif t == 'SpotLight':
            ld = bpy.data.lights.new(d['name'], 'SPOT')
            ld.spot_size = math.radians(d['angle'])
            ld.energy = d['brightness'] * d['range'] ** 2 * k['spot']
        else:
            ld = bpy.data.lights.new(d['name'], 'POINT')
            ld.energy = d['brightness'] * d['range'] ** 2 * k['point']
            ld.shadow_soft_size = 1.0
        ld.color = lin(d['colour'])
        ld.use_shadow = bool(d.get('shadows', False))
        o = bpy.data.objects.new(d['name'], ld)
        o.location = d['position']
        dv = Vector(d.get('direction', (0, 0, -1)))
        o.rotation_euler = dv.to_track_quat('-Z', 'Y').to_euler()
        coll.objects.link(o)
        o['hub_light'] = 1
        o['hub_stage'] = 4


def stage_lighting():
    scene = bpy.context.scene
    L = layout()
    build_preview_lights(L)
    root = bpy.data.collections[ROOT]
    for c in root.children:  # the stage 1 blockout lights are gone; plan overlay stays hidden
        if c.name in ('HUB_Plan', 'HUB_Collision'):
            c.hide_render = True
    set_engine(scene, 'BLENDER_EEVEE')
    ee = scene.eevee
    for attr, val in (('taa_render_samples', P['render']['samples']), ('use_raytracing', True), ('use_shadows', True),
                      ('fast_gi_method', 'GLOBAL_ILLUMINATION'), ('use_fast_gi', True)):
        try:
            setattr(ee, attr, val)
        except (AttributeError, TypeError):
            pass
    try:
        ee.ray_tracing_options.resolution_scale = '1'
    except (AttributeError, TypeError):
        pass
    scene.view_settings.view_transform = 'Standard'  # AgX desaturates; the palette must survive
    try:
        scene.view_settings.look = 'None'
    except TypeError:
        pass
    scene.view_settings.exposure = P['lights']['preview']['exposure']
    for mat in bpy.data.materials:  # the glow meshes: Neon in Roblox, strong emission here
        if mat.get('hub_surface') == 'Neon':
            bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            if bsdf:
                bsdf.inputs['Emission Strength'].default_value = P['lights']['preview']['neon']
    apply_time('Dusk')
    print('HUB lighting preview: %d lights' % len(lights_data(L)))


# ---- review renders ------------------------------------------------------------------------------------
def review_views(L):
    """name: (eye, target, preset, size, fov). Eye heights are avatar eyes (4.5) or the Roblox camera
    just behind and above the avatar."""
    sp = L['spawn']
    eye = P['avatar']['eye']
    rs = tuple(P['render']['size'])
    return {
        'spawn': ((sp[0], sp[1] - 6.0, sp[2] + eye + 2.5), (sp[0] - 6.0, 30.0, 2.0), 'Dusk', rs, 70.0),
        'eye_1v1': ((8.0, 36.0, eye + 0.8), (-60.0, 33.0, 2.5), 'Dusk', rs, 70.0),
        'lounge': ((52.0, -9.0, eye + 2.0), (58.0, -45.0, 2.5), 'Dusk', rs, 70.0),
        'bar_plaza': ((-4.0, -20.0, eye + 2.0), (26.0, -30.0, 4.0), 'Dusk', rs, 70.0),
        'marble_close': ((-2.0, -20.0, eye + 0.5), (-5.0, -8.0, 0.0), 'Dusk', rs, 60.0),
        'carpet_close': ((-36.8, 38.0, eye), (-38.0, 33.5, 0.0), 'Dusk', rs, 55.0),
        'window_day': ((-36.8, 50.0, eye + 1.5), (-52.0, 160.0, 13.0), 'Day', rs, 70.0),
        'window_night': ((-36.8, 50.0, eye + 1.5), (-52.0, 160.0, 13.0), 'Night', rs, 70.0),
        'window_east_dusk': ((70.0, -2.0, eye + 1.5), (200.0, 30.0, 12.0), 'Dusk', rs, 70.0),
        'terrace': ((88.0, -26.0, eye + 2.0), (112.0, -58.0, 2.0), 'Dusk', rs, 70.0),
        'overview': ((150.0, -165.0, 170.0), (5.0, -5.0, 0.0), 'Dusk', rs, 40.0),
        'phone_844x390': ((sp[0], sp[1] - 8.0, sp[2] + eye + 3.0), (sp[0] - 6.0, 30.0, 2.0), 'Dusk', (844, 390), 70.0),
        'phone_390x844': ((sp[0], sp[1] - 8.0, sp[2] + eye + 3.0), (sp[0] - 6.0, 30.0, 2.0), 'Dusk', (390, 844), 70.0),
    }


def stage_render(which='all', prefix='checkpoint_stage4'):
    scene = bpy.context.scene
    L = layout()
    cams = pkg_collection('HUB_Cameras')
    for o in list(cams.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    os.makedirs(RENDER_DIR, exist_ok=True)
    set_engine(scene, 'BLENDER_EEVEE')
    root = bpy.data.collections[ROOT]
    for c in root.children:
        c.hide_render = c.name in ('HUB_Plan', 'HUB_Collision')
    want = None if which in (None, 'all') else set(which.split(','))
    out = {}
    for name, (eye, tgt, preset, size, fov) in review_views(L).items():
        if want is not None and name not in want:
            continue
        apply_time(preset)
        ceiling = bpy.data.collections.get('HUB_Architecture')
        hide = []
        if name == 'overview':  # cut away the roof for the bird's-eye view
            for o in walk_objects(root):
                if o.name.startswith('Arch_Ceiling') or o.name.startswith('Emissive_Downlights') or \
                        o.name.startswith('Emissive_LED_Tray') or o.name.startswith('Emissive_LED_Ceiling') or \
                        o.name.startswith('Emissive_Zone_') or (o.get('hub_prop', '').startswith('Pendant')) or \
                        o.name.startswith('Furn_SignFrames') or o.name.startswith('Sign_Zone') or \
                        o.name.startswith('Screen_Zone') or o.name.startswith('Emissive_SignGlow') or \
                        o.name.startswith('Emissive_LED_Lounge') or o.name.startswith('Emissive_Pendant'):
                    if not o.hide_render:
                        o.hide_render = True
                        hide.append(o)
        del ceiling
        cam = camera('CAM_' + name, eye, tgt, cams, fov_v=fov if size[1] >= size[0] * 0.5 else None)
        cam.data.clip_end = 60000.0
        if size[0] < size[1]:  # portrait: the fov is horizontal
            cam.data.sensor_fit = 'HORIZONTAL'
            cam.data.angle = math.radians(fov)
        path = os.path.join(RENDER_DIR, '%s_%s.png' % (prefix, name))
        render_to(scene, cam, path, size)
        out[name] = path
        for o in hide:
            o.hide_render = False
    apply_time('Dusk')
    return out


# =================================================================================================
# Save and the stage runner
# =================================================================================================
def stage_save(path=None):
    path = path or HUB_BLEND
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile(compress=True)
    backup = path + '1'
    if os.path.exists(backup):
        os.remove(backup)
    print('HUB saved', path)


STAGES = {'blockout': stage_blockout, 'audit': stage_audit, 'render1': stage_render1,
          'architecture': stage_architecture, 'furnish': stage_furnish, 'skytest': stage_skytest, 'skyline': stage_skyline,
          'skyboxes': stage_skyboxes, 'lighting': stage_lighting, 'render': stage_render,
          'save': stage_save}


def main(args):
    if not args:
        args = ['blockout', 'audit']
    for a in args:
        if ':' in a:  # render1:plan renders one view; save:/path saves elsewhere
            name, arg = a.split(':', 1)
            STAGES[name](arg)
        else:
            STAGES[a]()


if __name__ == '__main__':
    _args = globals().get('HUB_ARGS')
    if _args is None:
        _args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    main(_args)
