"""The map's skybox: a sky gradient and stylised cumulus clouds, rendered in Blender to the six
faces of a Roblox Sky (brief section 9, Stage 4; Spec section 2 for the colours).

    B=/Applications/Blender.app/Contents/MacOS/Blender
    $B -b --factory-startup --python-exit-code 1 --python assets/map/gen_sky.py            # Day
    $B -b --factory-startup --python-exit-code 1 --python assets/map/gen_sky.py -- sunset  # (Stage 7)

Writes textures/sky_<light>_<Face>.png (1024 square) and checkpoints/sky/<light>-cross.png, a
preview with the faces unfolded round the front.

The clouds are "toon" emission: each point's colour comes from its normal against the sun (the
Spec's Day sun, so they are lit from the side the real sun is on) and its height in the cloud,
so the render has no noise, needs no denoising and the faces meet without seams. The same
cloud scene (same seed) renders the sunset sky in Stage 7, so the swap reads as a colour
change. No sun is painted: Roblox draws it.

Face directions (docs/STUDIO_NOTES.md "Sky faces", tested): Ft looks toward Roblox -Z, Bk +Z,
Rt -X, Lf +X, all upright; Up has its image top toward +X and its right toward -Z; Dn its top
toward -X and its right toward -Z. Roblox (x, y, z) is Blender (x, -z, y) (map_common.rb).
"""

import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import city_plan as cp  # noqa: E402
import map_common as mc  # noqa: E402

sys.path.insert(0, os.path.join(HERE, 'backdrop'))
import islands as near_islands  # noqa: E402  (the Island generator, reused for the far islands)

SEED = 4026
SIZE = 1024  # each face; Cycles' samples antialias it (Roblox shows 1024 at most)
SAMPLES = 48

P = {
    'radius': 50000.0,  # the dome the clouds sit on: behind the painted far world (Stage 6)
    'count': 30,
    # (lowest, highest elevation in degrees, share of the clouds): low down, as in the art, whose
    # upper sky is mostly clear (Stage 4 critic: they filled the top half at eye height).
    'bands': ((0.3, 4.0, 0.6), (4.0, 9.0, 0.3), (9.0, 14.0, 0.1)),
    'width_deg': (4.5, 11.0),  # a cloud's angular width: small puffy cumulus sitting on the horizon
    'squash': 0.92,  # clouds are a little wider than tall
    'base_flat': 0.3,  # the flat base sits this far (of a base ball's radius) below its centre
    'horizon_haze': 0.15,  # clouds at the horizon blend this far toward the horizon colour...
    'haze_top_deg': 14.0,  # ...fading out by this elevation
    'sky_curve': 0.7,  # the gradient's power (with sky_mid: the pale band over the lowest third)
    'sky_mid': (0.35, 0.45),  # at this far up the gradient, this much of the way to the top colour
    'sea_band': 0.015,  # below the horizon the sky turns to the far sea over this much of sin(elevation)
    'land_blend': 0.09,  # below it, land toward -X and sea toward +X, blended over this much of the x direction
}

# The Spec's Day sun (latitude 45, clock 10), toward the sun, Roblox axes.
SUN = {'day': (0.465, 0.806, 0.367)}

COLOURS = {
    'day': {
        # Roblox's tone mapping renders a skybox paler and greyer than painted (#3894FC came out
        # #56A9DD), so these are painted deeper and more saturated than the art's measured
        # sky_top_day and sky_horizon_day to render near them (Stage 4 critic).
        'top': '#1480FF',
        'horizon': '#D4EAFA',  # pale with a touch of warmth, as the art's horizon (critic 2)
        # Below the horizon: the Terrain water's rendered blue (between #349BD6 at high quality
        # and #1791D8 at low). At low quality Roblox draws the water only near the camera and
        # the sky shows beyond it, so the two must match; the art's far sea is #3187DE.
        # The far sea at the horizon: painted to render a touch deeper than the Terrain water
        # beside it (#1E78D7 rendered #0C76CB, a dark band; critic 2).
        'sea': '#3490DE',
        # Below the horizon toward the city (Roblox -X, where the land runs past the world's
        # edge): the far land's rendered colour (sampled in Studio, Stage 4), so the city's
        # ground meets the sky with no strip of painted sea.
        # (only past the painted land plane's far edge, 0.17 degrees under the horizon: the
        # horizon's own colour, so no line shows there; Stage 6)
        'land': '#D4EAFA',
        'cloud_lit': '#F7F8FF',  # the art's sunlit tops read near white; cloud_day is their average
        'cloud_mid': mc.hexc('cloud_day'),
        'cloud_shade': mc.hexc('cloud_day', 'shade'),
    },
}

# Face -> (forward, image up) in Blender axes (see the docstring).
FACES = {
    'Ft': ((0, 1, 0), (0, 0, 1)),
    'Bk': ((0, -1, 0), (0, 0, 1)),
    'Rt': ((-1, 0, 0), (0, 0, 1)),
    'Lf': ((1, 0, 0), (0, 0, 1)),
    'Up': ((0, 0, 1), (1, 0, 0)),
    'Dn': ((0, 0, -1), (-1, 0, 0)),
}


def linear(hex_colour):
    return tuple(mc.srgb_to_linear(c) for c in mc.rgb(hex_colour)) + (1.0,)


def node(tree, kind, **inputs):
    n = tree.nodes.new(kind)
    for key, value in inputs.items():
        n.inputs[key].default_value = value
    return n


def ramp(tree, stops):
    """A colour ramp through (position, hex) stops."""
    n = tree.nodes.new('ShaderNodeValToRGB')
    elements = n.color_ramp.elements
    while len(elements) > len(stops):
        elements.remove(elements[-1])
    while len(elements) < len(stops):
        elements.new(0.5)
    for element, (pos, colour) in zip(elements, stops):
        element.position = pos
        element.color = linear(colour)
    return n


def math_node(tree, op, a=None, b=None, clamp=False):
    n = tree.nodes.new('ShaderNodeMath')
    n.operation = op
    n.use_clamp = clamp
    if isinstance(a, (int, float)):
        n.inputs[0].default_value = a
    if isinstance(b, (int, float)):
        n.inputs[1].default_value = b
    return n


def world(scene, c):
    """The sky gradient by the ray's elevation; below the horizon, the far land toward the city
    (-X) and the far sea toward the ocean (+X). Ahead (-Z) the split leans left to where the
    painted land's far edge is (its shore turns away past the far city), so the sea shows there
    and no pale wedge of land colour sits between the city and the sea (Stage 6 critic 3)."""
    W = cp.WORLD
    L = FAR['ground_to']
    lean = -(cp.city_edge_x(-L) - (L - W['far_reach']) * FAR['shore_turn']) / L  # tan of the far edge's bearing
    w = bpy.data.worlds.new('Sky')
    scene.world = w
    w.use_nodes = True
    t = w.node_tree
    t.nodes.clear()
    coord = t.nodes.new('ShaderNodeTexCoord')
    sep = t.nodes.new('ShaderNodeSeparateXYZ')
    t.links.new(coord.outputs['Generated'], sep.inputs[0])
    up = math_node(t, 'MAXIMUM', b=0.0)
    t.links.new(sep.outputs['Z'], up.inputs[0])
    curve = math_node(t, 'POWER', b=P['sky_curve'])
    t.links.new(up.outputs[0], curve.inputs[0])
    mid = '#%02X%02X%02X' % tuple(int(round(v)) for v in mc.mix(mc.rgb(c['horizon']), mc.rgb(c['top']), P['sky_mid'][1]))
    sky = ramp(t, [(0.0, c['horizon']), (P['sky_mid'][0], mid), (1.0, c['top'])])
    t.links.new(curve.outputs[0], sky.inputs['Fac'])
    below = t.nodes.new('ShaderNodeMapRange')
    below.clamp = True
    below.inputs['From Min'].default_value = 0.0
    below.inputs['From Max'].default_value = -P['sea_band']
    t.links.new(sep.outputs['Z'], below.inputs['Value'])
    ahead = math_node(t, 'MAXIMUM', b=0.0)  # Blender +Y is Roblox -Z, straight ahead
    t.links.new(sep.outputs['Y'], ahead.inputs[0])
    leaned = math_node(t, 'MULTIPLY_ADD', b=lean)
    t.links.new(ahead.outputs[0], leaned.inputs[0])
    t.links.new(sep.outputs['X'], leaned.inputs[2])
    ground = t.nodes.new('ShaderNodeMapRange')
    ground.clamp = True
    ground.inputs['From Min'].default_value = -P['land_blend']
    ground.inputs['From Max'].default_value = P['land_blend']
    t.links.new(leaned.outputs[0], ground.inputs['Value'])
    below_col = t.nodes.new('ShaderNodeMix')
    below_col.data_type = 'RGBA'
    below_col.inputs['A'].default_value = linear(c['land'])
    below_col.inputs['B'].default_value = linear(c['sea'])
    t.links.new(ground.outputs['Result'], below_col.inputs['Factor'])
    mix = t.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    t.links.new(below_col.outputs['Result'], mix.inputs['B'])
    t.links.new(below.outputs['Result'], mix.inputs['Factor'])
    t.links.new(sky.outputs['Color'], mix.inputs['A'])
    bg = node(t, 'ShaderNodeBackground', Strength=1.0)
    t.links.new(mix.outputs['Result'], bg.inputs['Color'])
    out = t.nodes.new('ShaderNodeOutputWorld')
    t.links.new(bg.outputs[0], out.inputs['Surface'])


def cloud_material(c, sun):
    """Emission by sunlit side and height in the cloud, hazed toward the horizon colour low down."""
    m = bpy.data.materials.new('Cloud')
    m.use_nodes = True
    t = m.node_tree
    t.nodes.clear()
    geo = t.nodes.new('ShaderNodeNewGeometry')
    dot = t.nodes.new('ShaderNodeVectorMath')
    dot.operation = 'DOT_PRODUCT'
    dot.inputs[1].default_value = sun
    t.links.new(geo.outputs['Normal'], dot.inputs[0])
    lit = t.nodes.new('ShaderNodeMapRange')
    lit.clamp = True
    lit.inputs['From Min'].default_value = -0.35
    lit.inputs['From Max'].default_value = 0.9
    t.links.new(dot.outputs['Value'], lit.inputs['Value'])
    coord = t.nodes.new('ShaderNodeTexCoord')
    sep = t.nodes.new('ShaderNodeSeparateXYZ')
    t.links.new(coord.outputs['Generated'], sep.inputs[0])
    # 60% which way the surface faces, 40% how high in the cloud it is (the flat base is shaded).
    a = math_node(t, 'MULTIPLY', b=0.6)
    t.links.new(lit.outputs['Result'], a.inputs[0])
    b = math_node(t, 'MULTIPLY', b=0.4)
    t.links.new(sep.outputs['Z'], b.inputs[0])
    f = math_node(t, 'ADD', clamp=True)
    t.links.new(a.outputs[0], f.inputs[0])
    t.links.new(b.outputs[0], f.inputs[1])
    tone = ramp(t, [(0.0, c['cloud_shade']), (0.45, c['cloud_mid']), (0.8, c['cloud_lit'])])
    t.links.new(f.outputs[0], tone.inputs['Fac'])
    # Haze: the point's elevation from the dome's centre (the camera).
    norm = t.nodes.new('ShaderNodeVectorMath')
    norm.operation = 'NORMALIZE'
    t.links.new(geo.outputs['Position'], norm.inputs[0])
    sep2 = t.nodes.new('ShaderNodeSeparateXYZ')
    t.links.new(norm.outputs['Vector'], sep2.inputs[0])
    haze = t.nodes.new('ShaderNodeMapRange')
    haze.clamp = True
    haze.inputs['From Min'].default_value = 0.0
    haze.inputs['From Max'].default_value = math.sin(math.radians(P['haze_top_deg']))
    haze.inputs['To Min'].default_value = P['horizon_haze']
    haze.inputs['To Max'].default_value = 0.0
    t.links.new(sep2.outputs['Z'], haze.inputs['Value'])
    mix = t.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.inputs['B'].default_value = linear(c['horizon'])
    t.links.new(haze.outputs['Result'], mix.inputs['Factor'])
    t.links.new(tone.outputs['Color'], mix.inputs['A'])
    em = node(t, 'ShaderNodeEmission', Strength=1.0)
    t.links.new(mix.outputs['Result'], em.inputs['Color'])
    out = t.nodes.new('ShaderNodeOutputMaterial')
    t.links.new(em.outputs[0], out.inputs['Surface'])
    return m


def pick_clouds(rng):
    """(azimuth, elevation, width) in degrees for every cloud: stratified round the sky so they
    never bunch, most of them low."""
    n = P['count']
    elevs = []
    for lo, hi, share in P['bands']:
        elevs += [(lo, hi)] * round(n * share)
    elevs = elevs[:n] + [P['bands'][0][:2]] * max(0, n - len(elevs))
    rng.shuffle(elevs)
    clouds = []
    for k in range(n):
        az = 360.0 * (k + rng.uniform(0.15, 0.85)) / n
        lo, hi = elevs[k]
        el = rng.uniform(lo, hi)
        width = rng.uniform(*P['width_deg']) * (1.0 - 0.3 * (el / 40.0))
        clouds.append((az, el, width))
    return clouds


def cloud_mesh(name, rng, width):
    """A cumulus: a row of base balls, a tier above, a crown; metaballs meshed, the base cut flat.
    Local axes: X across, Y away from the camera, Z up; the base at Z 0."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = width * 0.03
    mb.render_resolution = width * 0.03
    mb.threshold = 0.5  # low enough that neighbouring puffs merge without holes
    obj = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(obj)
    base_r = []
    n_base = rng.randint(5, 8)
    for k in range(n_base):
        x = (k / (n_base - 1) - 0.5) * width * 0.8 + rng.uniform(-0.04, 0.04) * width
        r = width * rng.uniform(0.17, 0.25) * (1.0 - 0.35 * abs(x) / width)
        base_r.append(r)
        e = mb.elements.new()
        e.co = (x, rng.uniform(-0.08, 0.08) * width, 0.0)
        e.radius = r
    for _ in range(rng.randint(3, 5)):
        e = mb.elements.new()
        e.co = (rng.uniform(-0.3, 0.3) * width, rng.uniform(-0.06, 0.06) * width, width * rng.uniform(0.14, 0.24))
        e.radius = width * rng.uniform(0.18, 0.26)
    for _ in range(rng.randint(2, 3)):
        e = mb.elements.new()
        e.co = (rng.uniform(-0.18, 0.18) * width, 0.0, width * rng.uniform(0.3, 0.4))
        e.radius = width * rng.uniform(0.15, 0.21)
    # Small puffs along the upper edge: the art's cauliflower tops.
    for _ in range(rng.randint(5, 8)):
        a = rng.uniform(0.15, 0.85) * math.pi
        e = mb.elements.new()
        e.co = (math.cos(a) * width * 0.36, rng.uniform(-0.05, 0.05) * width, math.sin(a) * width * 0.3 + width * 0.05)
        e.radius = width * rng.uniform(0.07, 0.11)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.metaballs.remove(mb)
    floor = -min(base_r) * P['base_flat']
    for v in mesh.vertices:
        if v.co.z < floor:
            v.co.z = floor
        v.co.z = (v.co.z - floor) * P['squash']
    mesh.update()
    return mesh


def build(scene, light):
    c = COLOURS[light]
    sun = Vector(mc.rb(SUN[light])).normalized()
    world(scene, c)
    build_far(scene, c, sun)
    material = cloud_material(c, sun)
    rng = random.Random(SEED)
    R = P['radius']
    for k, (az, el, w) in enumerate(pick_clouds(rng)):
        width = 2 * R * math.tan(math.radians(w) / 2)
        mesh = cloud_mesh('Cloud%02d' % k, rng, width)
        mesh.materials.append(material)
        obj = bpy.data.objects.new('Cloud%02d' % k, mesh)
        scene.collection.objects.link(obj)
        a, e = math.radians(az), math.radians(el)
        d = Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))
        depth = Vector((d.x, d.y, 0.0)).normalized()
        up = Vector((0.0, 0.0, 1.0))
        right = depth.cross(up)
        basis = Matrix((right, depth, up)).transposed().to_4x4()
        obj.matrix_world = Matrix.Translation(d * R) @ basis


# ---------------------------------------------------------------------------------------------
# The far world, painted (Stage 6): at graphics levels 1 to 10 Roblox draws nothing beyond a few
# hundred studs, so everything past the 3D world's reach lives in the skybox: the far city, the
# far islands and the coast point, on painted land and sea, faded into the horizon by distance.
# Rendered from the roof's eye at the true positions (Roblox axes through map_common.rb).
# ---------------------------------------------------------------------------------------------

EYE = (0.0, 5.0, 0.0)  # the roof's eye, Roblox studs: the sky is painted from here
FAR = {
    'ground_from': 500.0,  # the painted land and sea start this far out (the 3D covers the overlap)
    'ground_to': 100000.0,  # and run to here (0.17 degrees under the horizon)
    'fade_start': 1500.0,  # the aerial fade (toward the horizon colour) starts here...
    'fade_length': 14000.0,  # ...and closes 63% of the way by this far past it (Stage 6 critic:
                             # at 7,000 the far world read washed out and ghostly)
    'light_ambient': 0.74,  # a face's light: this, plus light_sun x its sun angle
    'light_sun': 0.26,
    'foot_shade': 0.86,  # a wall's colour at its foot, of its colour at its top
    'spire_every': 37,  # every this-many tall towers wears a spire
    'landmarks': 2,  # the tallest far towers at each downtown's heart (city_plan.FAR_DOWNTOWNS)...
    'landmark_rise': (300.0, 480.0),  # ...raised into landmarks this tall over the roof
    'landmark_heart': 0.6,  # a landmark's lot is at least this near its downtown's heart (city_plan.downtown)
    # The far islands: stronger light and shade and less haze than the city, so they read as green
    # mountains with a shaded flank, not milky cut-outs (Stage 6 critic 2).
    'island_ambient': 0.6,
    'island_sun': 0.4,
    'island_fade_length': 22000.0,
    'far_blend': 0.3,  # the far islands' greens blended this far toward the art's far island blue-green
    'rock_green': 0.5,  # far islands' rock this far toward the dark jungle green (no grey skirt)
    # Beyond the far city the shore turns away left, this many studs outward per stud further
    # out, so the sea runs on to the horizon behind the pergola as in the art (Stage 6 critic 3:
    # the land running straight on read as a pale wedge there).
    'shore_turn': 0.34,
    'hills': (11000.0, 16000.0),  # low blue hills behind the city on the horizon, this far out...
    'hill_height': (180.0, 520.0),  # ...this tall over the street...
    'hills_az': (-175.0, -12.0),  # ...from behind the spawn round to here, where the turned shore is
}
FAR_COLOURS = {
    # The Stage 5 skyline's facade family, flat (a far tower is a few pixels wide).
    'glass': '#8AA4C2', 'white': '#EDE3D7', 'stone': '#D8C8B6', 'terracotta': '#B8917A',
    'roof': '#E4E0DC', 'land': '#9BA592', 'sand': '#F2DCC0',
    'jungle_dark': '#3F6E44', 'jungle': '#4E8550', 'jungle_lit': '#66985A', 'rock': '#8A7F84',
    'island_far': mc.hexc('island_far'), 'hills': mc.hexc('mountain_far'),
}


class Painted:
    """Faces with a colour per corner, for one Blender mesh."""

    def __init__(self):
        self.verts, self.faces, self.cols = [], [], []

    def face(self, pts, cols):
        base = len(self.verts)
        self.verts += [mc.rb(p) for p in pts]
        self.faces.append(tuple(range(base, base + len(pts))))
        self.cols += [c for c in cols]

    def box(self, x0, z0, x1, z1, y0, y1, side, top):
        foot = tuple(v * FAR['foot_shade'] for v in side)
        for a, b in ((( x0, z0), (x0, z1)), ((x0, z1), (x1, z1)), ((x1, z1), (x1, z0)), ((x1, z0), (x0, z0))):
            self.face([(a[0], y0, a[1]), (b[0], y0, b[1]), (b[0], y1, b[1]), (a[0], y1, a[1])], [foot, foot, side, side])
        self.face([(x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0)], [top] * 4)

    def spire(self, x, z, r, y0, y1, colour):
        pts = [(x - r, z - r), (x - r, z + r), (x + r, z + r), (x + r, z - r)]
        for i in range(4):
            a, b = pts[i], pts[(i + 1) % 4]
            self.face([(a[0], y0, a[1]), (b[0], y0, b[1]), (x, y1, z)], [colour] * 3)

    def to_object(self, name, material):
        """A Blender mesh of these faces, its corner colours (sRGB 0..1) as a linear point
        attribute: every face has its own vertices, so a point colour is a corner colour."""
        import numpy as np
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        cols = np.asarray(self.cols, dtype=np.float64)
        lin = np.where(cols <= 0.04045, cols / 12.92, ((cols + 0.055) / 1.055) ** 2.4)
        rgba = np.concatenate([lin, np.ones((len(lin), 1))], axis=1).astype(np.float32)
        attr = mesh.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='POINT')
        attr.data.foreach_set('color', rgba.ravel())
        mesh.materials.append(material)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def unit(hex_colour):
    return tuple(v / 255.0 for v in mc.rgb(hex_colour))


def far_material(c, sun, lit=True, ambient=None, sun_light=None, fade_length=None):
    """Emission: the corner colour times the light (ambient plus the sun on the face), faded
    toward the horizon colour with distance from the eye (aerial perspective). The light and
    the fade default to FAR's."""
    ambient = FAR['light_ambient'] if ambient is None else ambient
    sun_light = FAR['light_sun'] if sun_light is None else sun_light
    fade_length = FAR['fade_length'] if fade_length is None else fade_length
    m = bpy.data.materials.new('Far')
    m.use_nodes = True
    t = m.node_tree
    t.nodes.clear()
    col = t.nodes.new('ShaderNodeVertexColor')
    col.layer_name = 'Col'
    geo = t.nodes.new('ShaderNodeNewGeometry')
    shade = t.nodes.new('ShaderNodeMix')
    shade.data_type = 'RGBA'
    shade.blend_type = 'MULTIPLY'
    shade.inputs['Factor'].default_value = 1.0
    t.links.new(col.outputs['Color'], shade.inputs['A'])
    if lit:
        dot = t.nodes.new('ShaderNodeVectorMath')
        dot.operation = 'DOT_PRODUCT'
        dot.inputs[1].default_value = sun
        t.links.new(geo.outputs['Normal'], dot.inputs[0])
        pos = math_node(t, 'MAXIMUM', b=0.0)
        t.links.new(dot.outputs['Value'], pos.inputs[0])
        light = t.nodes.new('ShaderNodeMapRange')
        light.inputs['From Min'].default_value = 0.0
        light.inputs['From Max'].default_value = 1.0
        light.inputs['To Min'].default_value = ambient
        light.inputs['To Max'].default_value = ambient + sun_light
        t.links.new(pos.outputs[0], light.inputs['Value'])
        comb = t.nodes.new('ShaderNodeCombineColor')
        for i in range(3):
            t.links.new(light.outputs['Result'], comb.inputs[i])
        t.links.new(comb.outputs['Color'], shade.inputs['B'])
    else:
        shade.inputs['B'].default_value = (1.0, 1.0, 1.0, 1.0)
    dist = t.nodes.new('ShaderNodeVectorMath')
    dist.operation = 'DISTANCE'
    dist.inputs[1].default_value = mc.rb(EYE)
    t.links.new(geo.outputs['Position'], dist.inputs[0])
    past = math_node(t, 'SUBTRACT', b=FAR['fade_start'])
    t.links.new(dist.outputs['Value'], past.inputs[0])
    clampd = math_node(t, 'MAXIMUM', b=0.0)
    t.links.new(past.outputs[0], clampd.inputs[0])
    scaled = math_node(t, 'DIVIDE', b=-fade_length)
    t.links.new(clampd.outputs[0], scaled.inputs[0])
    ex = math_node(t, 'EXPONENT')
    t.links.new(scaled.outputs[0], ex.inputs[0])
    fade = math_node(t, 'SUBTRACT', a=1.0)
    t.links.new(ex.outputs[0], fade.inputs[1])
    mix = t.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.inputs['B'].default_value = linear(c['horizon'])
    t.links.new(fade.outputs[0], mix.inputs['Factor'])
    t.links.new(shade.outputs['Result'], mix.inputs['A'])
    em = node(t, 'ShaderNodeEmission', Strength=1.0)
    t.links.new(mix.outputs['Result'], em.inputs['Color'])
    out = t.nodes.new('ShaderNodeOutputMaterial')
    t.links.new(em.outputs[0], out.inputs['Surface'])
    return m


def far_ground(painted):
    """The land (under the city: left of the coast, the bending shore behind) as strips over Z;
    the sea is the world's own colour below the horizon. At the street's height."""
    W = cp.WORLD
    L = FAR['ground_to']
    y = W['street_y']
    colour = unit(FAR_COLOURS['land'])
    edges = [(L, cp.land_x()), (cp.land_z(), cp.land_x()), (cp.land_z(), W['city_back_x']),
             (W['shore_z'], W['city_back_x'])]
    z = W['shore_z']
    while z > -L:
        z1 = max(-L, z - (150.0 if z > -3000 else 1000.0 if z > -20000 else 10000.0))
        beyond = max(0.0, -z1 - W['far_reach'])
        edges.append((z1, cp.city_edge_x(z1) - beyond * FAR['shore_turn']))
        z = z1
    for (za, xa), (zb, xb) in zip(edges, edges[1:]):
        if za == zb:
            continue
        painted.face([(-L, y, za), (-L, y, zb), (xb, y, zb), (xa, y, za)], [colour] * 4)


def far_city(painted):
    """Every far lot: a podium, a shaft and a crown, in the skyline's facade colours; every
    few tall towers a spire."""
    W = cp.WORLD
    street = W['street_y']
    styles = [unit(FAR_COLOURS[k]) for k in ('glass', 'white', 'stone', 'terracotta')]
    roof = unit(FAR_COLOURS['roof'])
    tall = 0
    count = 0
    blocks = cp.far_blocks()
    # The tallest lots at each downtown's heart become the far landmarks, rising in turn.
    picks = []
    for bearing, dist, radius in cp.FAR_DOWNTOWNS:
        a = math.radians(bearing)
        cx, cz = -math.sin(a) * dist, -math.cos(a) * dist
        ranked = sorted(((lot['height'], b['i'], b['j'], k) for b in blocks for k, lot in enumerate(b['lots'])
                         if lot['shaft'] and math.hypot(lot['x'] - cx, lot['z'] - cz) < radius
                         and cp.downtown(lot['x'], lot['z']) >= FAR['landmark_heart']), reverse=True)
        assert len(ranked) >= FAR['landmarks'], ('a downtown without landmark lots', bearing)
        picks += [r[1:] for r in ranked[:FAR['landmarks']]]
    lo, hi = FAR['landmark_rise']
    marks = {pick: -W['street_y'] + lo + (hi - lo) * ((n * 5) % len(picks)) / max(1, len(picks) - 1)
             for n, pick in enumerate(picks)}
    for b in blocks:
        for k, lot in enumerate(b['lots']):
            if (b['i'], b['j'], k) in marks:
                lot = dict(lot, height=marks[(b['i'], b['j'], k)], crown=30.0)
            assert lot['dist'] >= W['city_reach'] - 60.0, ('a far lot too near', lot['dist'])
            style = styles[0] if lot['glass'] else styles[1 + (b['i'] * 7 + b['j'] * 3 + k) % 3]
            x, z, w, d = lot['x'], lot['z'], lot['w'], lot['d']
            base = street
            painted.box(x - w / 2, z - d / 2, x + w / 2, z + d / 2, base, base + lot['podium'], style, roof)
            count += 1
            if lot['shaft'] is None:
                continue
            sw, sd = lot['shaft']
            top = street + lot['height'] - lot['crown']
            painted.box(x - sw / 2, z - sd / 2, x + sw / 2, z + sd / 2, base + lot['podium'], top, style, roof)
            if lot['crown']:
                painted.box(x - sw * 0.3, z - sd * 0.3, x + sw * 0.3, z + sd * 0.3, top, top + lot['crown'],
                            tuple(min(1.0, v * 1.08) for v in style), roof)
                top += lot['crown']
            if lot['height'] > 560:
                tall += 1
                if tall % FAR['spire_every'] == 0:
                    painted.spire(x, z, sw * 0.12, top, top + lot['height'] * 0.18, roof)
    return count


def paint_island(painted, isle, far):
    """One island from backdrop/islands.py's shape (grid and shore rings), coloured by its
    material() per vertex. Far islands lean toward the art's far island blue-green, their rock
    toward the jungle and their shore the dark green, with no white beach rim or grey skirt
    (Stage 6 critics)."""
    dark, mid, lit = (unit(FAR_COLOURS[k]) for k in ('jungle_dark', 'jungle', 'jungle_lit'))
    rock, sand = unit(FAR_COLOURS['rock']), unit(FAR_COLOURS['sand'])
    tint = unit(FAR_COLOURS['island_far'])

    def blend(a, b, t):
        return tuple(x + (y - x) * t for x, y in zip(a, b))

    if far:
        rock = blend(rock, dark, FAR['rock_green'])

    grid = []
    for row in isle.grid:
        out = []
        for p, t, s in row:
            green, rk = isle.material(t, s)
            g = blend(dark, mid, green * 2) if green < 0.5 else blend(mid, lit, green * 2 - 1)
            col = blend(g, rock, rk)
            if far:
                col = blend(col, tint, FAR['far_blend'])
            out.append((p, col))
        grid.append(out)

    def up_face(pts, cols):
        ux, uy, uz = (pts[1][i] - pts[0][i] for i in range(3))
        vx, vy, vz = (pts[2][i] - pts[0][i] for i in range(3))
        if (uz * vx - ux * vz) < 0:
            pts, cols = pts[::-1], cols[::-1]
        painted.face(pts, cols)

    m = len(isle.spokes)
    for k in range(len(grid) - 1):
        for j in range(m):
            jn = (j + 1) % m
            a0, a1, b0, b1 = grid[k][j], grid[k][jn], grid[k + 1][j], grid[k + 1][jn]
            for tri in ([(a0, b0, b1)] if k == 0 else [(a0, b0, b1), (a0, b1, a1)]):
                up_face([v[0] for v in tri], [v[1] for v in tri])
    edge = [v[0] for v in grid[-1]]
    shore = blend(dark, tint, FAR['far_blend']) if far else sand
    for j in range(m):
        jn = (j + 1) % m
        for ring_a, ring_b in ((edge, isle.water), (isle.water, isle.floor)):
            up_face([ring_a[j], ring_b[j], ring_b[jn], ring_a[jn]], [shore] * 4)


def far_islands(painted):
    """The far islands and the coast point (city_plan.FAR_ISLANDS). The near islands are 3D
    only: painted twins showed as ghost peaks behind them from the roof's edges (a 90-stud
    step off the painting's eye moves a 2,000-stud island 2.6 degrees; Stage 6)."""
    for n, (kind, az, dist, radius, height) in enumerate(cp.FAR_ISLANDS):
        assert cp.far_island_at_sea(az, dist, radius), ('a far island off the sea', kind, az)
        isle = near_islands.Island(100 + n, 9, kind, az, dist, radius, height)
        isle.shape()
        paint_island(painted, isle, far=True)


def far_hills(painted, rng):
    """Low blue hills along the city side's horizon, far behind the city (the art's distant
    ranges): a ridge line of peaks round the city's arc, faded almost to the sky."""
    W = cp.WORLD
    colour = unit(FAR_COLOURS['hills'])
    d0, d1 = FAR['hills']
    h0, h1 = FAR['hill_height']
    base = W['street_y'] - 20.0
    steps = 90
    prev = None
    for k in range(steps + 1):
        az0, az1 = FAR['hills_az']
        az = az0 + (az1 - az0) * k / steps  # from behind the spawn round toward straight ahead, via the city
        a = math.radians(az)
        d = rng.uniform(d0, d1)
        h = W['street_y'] + rng.uniform(h0, h1) * (0.6 + 0.4 * math.sin(k * 0.37) ** 2)
        top = (d * math.sin(a), h, -d * math.cos(a))
        foot = ((d - 800.0) * math.sin(a), base, -(d - 800.0) * math.cos(a))
        if prev:
            pts = [prev[1], foot, top, prev[0]]
            ux, uy, uz = (pts[1][i] - pts[0][i] for i in range(3))
            vx, vy, vz = (pts[2][i] - pts[0][i] for i in range(3))
            nx = uy * vz - uz * vy
            nz = ux * vy - uy * vx
            # face the eye (the origin): the normal points toward -position
            if nx * top[0] + nz * top[2] > 0:
                pts = pts[::-1]
            painted.face(pts, [colour] * 4)
        prev = (top, foot)


def build_far(scene, c, sun):
    lit_mat, flat_mat = far_material(c, sun, lit=True), far_material(c, sun, lit=False)
    ground = Painted()
    far_ground(ground)
    ground.to_object('FarGround', flat_mat)
    city = Painted()
    lots = far_city(city)
    city.to_object('FarCity', lit_mat)
    isles = Painted()
    far_islands(isles)
    isles.to_object('FarIslands', far_material(c, sun, lit=True, ambient=FAR['island_ambient'],
                                               sun_light=FAR['island_sun'],
                                               fade_length=FAR['island_fade_length']))
    hills = Painted()
    far_hills(hills, random.Random(SEED + 7))
    hills.to_object('FarHills', flat_mat)
    print('far world: %d lots, %d city faces, %d island faces' % (lots, len(city.faces), len(isles.faces)))


def render_faces(scene, light):
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.image_settings.color_depth = '8'
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    cam_data = bpy.data.cameras.new('SkyCam')
    cam_data.sensor_fit = 'HORIZONTAL'
    cam_data.angle = math.pi / 2
    cam_data.clip_start = 1.0
    cam_data.clip_end = max(P['radius'], FAR['ground_to']) * 3
    cam = bpy.data.objects.new('SkyCam', cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    paths = {}
    for face, (forward, up) in FACES.items():
        f, u = Vector(forward), Vector(up)
        r = f.cross(u)
        cam.matrix_world = Matrix.Translation(Vector(mc.rb(EYE))) @ Matrix((r, u, -f)).transposed().to_4x4()
        path = os.path.join(HERE, 'textures', 'sky_%s_%s.png' % (light, face))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths[face] = path
        print('rendered', os.path.relpath(path, HERE))
    return paths


def preview(paths, light):
    """The faces unfolded round Ft: Rt Ft Lf Bk across, Up above Ft and Dn below, each turned
    so its edge meets Ft's (a seam check)."""
    import numpy as np

    def load(face):
        img = bpy.data.images.load(paths[face])
        a = np.empty(SIZE * SIZE * 4, dtype=np.float32)
        img.pixels.foreach_get(a)
        bpy.data.images.remove(img)
        return a.reshape(SIZE, SIZE, 4)[::-1]  # Blender rows run bottom to top; flip to top-down

    cross = np.zeros((SIZE * 3, SIZE * 4, 4), dtype=np.float32)
    cross[..., 3] = 1.0
    for col, face in enumerate(('Rt', 'Ft', 'Lf', 'Bk')):
        cross[SIZE:2 * SIZE, col * SIZE:(col + 1) * SIZE] = load(face)
    # Up's right edge faces -Z, the edge it shares with Ft's top: turn it clockwise. Dn's right
    # edge meets Ft's bottom: turn it anticlockwise.
    cross[0:SIZE, SIZE:2 * SIZE] = np.rot90(load('Up'), k=-1)
    cross[2 * SIZE:3 * SIZE, SIZE:2 * SIZE] = np.rot90(load('Dn'), k=1)
    out = bpy.data.images.new('Cross', SIZE * 4, SIZE * 3)
    out.pixels.foreach_set(np.ascontiguousarray(cross[::-1]).ravel())
    folder = os.path.join(HERE, 'checkpoints', 'sky')
    os.makedirs(folder, exist_ok=True)
    out.filepath_raw = os.path.join(folder, '%s-cross.png' % light)
    out.file_format = 'PNG'
    out.save()
    print('preview', os.path.relpath(out.filepath_raw, HERE))


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    light = 'sunset' if 'sunset' in args else 'day'
    if light not in COLOURS:
        raise SystemExit('no %s sky yet (Stage 7)' % light)
    scene = mc.clear_scene()
    build(scene, light)
    paths = render_faces(scene, light)
    if 'nopreview' not in args:
        preview(paths, light)


main()
