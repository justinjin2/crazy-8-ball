"""Cue skin previews: the review sheet's stills, the VFX clip, and the tier sheets.

In Blender (headless, EEVEE):
    Blender -b --factory-startup --python-exit-code 1 --python assets/cue/CuePreview.py -- --skin <id> [--stills] [--clip] [--quick]
        renders/skins/<id>/stills/*.png and renders/skins/<id>/clip.mp4
On the Mac's Python (Pillow):
    python3 assets/cue/CuePreview.py --sheet <id>        renders/skins/<id>/sheet.png (stills + concept crops, labelled)
    python3 assets/cue/CuePreview.py --tier <Tier>       renders/tiers/<tier>.png (every skin of the tier)

The clip (1280x720, 30 fps) on a dark Roblox-like scene: a slow turn of the cue with its aura and
moving material; the cue on the back of a blocky avatar (tip over the left shoulder, 36 degrees,
as Config.Cue.Back); the shooting pose striking the cue ball with the ball trail; a ball dropping
into a corner pocket with the finisher. Commons get the turn only. Every effect is drawn from
Roblox's own pieces by CueVfx (see its docstring); EEVEE has no bloom here, as Roblox's Bloom is
modest, so glows read a little softer than in a game with strong bloom.
"""

import json
import math
import os
import sys

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

RENDERS = os.path.join(HERE, 'renders')
SKINS = os.path.join(HERE, 'skins')
TEXTURES = os.path.join(HERE, 'textures')
CONCEPTS = os.path.join(HERE, 'concepts')

PREVIEW = {
    'clip_size': (1280, 720),
    'fps': 30,
    'clip_samples': 16,  # EEVEE TAA samples per clip frame
    'still_samples': 48,
    'background': (0.0085, 0.0095, 0.0125),  # linear: about #16181D, the concept sheets' charcoal
    'floor': (0.006, 0.0065, 0.008),
    'env_strength': 0.55,
    'bloom': (0.8, 0.6, 0.6),  # threshold, strength, size (Blender Glare: Bloom)
    'back': {'tilt_deg': 36.0, 'out': 0.3, 'grip_from_tip': 4.3},  # Config.Cue.Back
    'segments': {'turn': 3.2, 'back': 2.2, 'shot': 2.4, 'pocket': 2.0},  # seconds
    'common_turn': 4.0,
    'prewarm': 2.5,  # seconds of aura simulated before a segment starts
    'pocket_ball': 3,  # the red 3 drops in the pocket segment (the default gust takes its colour)
}

BALL_COLOURS = {0: (245, 240, 225), 1: (250, 200, 40), 2: (30, 80, 200), 3: (210, 40, 40), 4: (100, 40, 150),
                5: (245, 120, 30), 6: (12, 92, 52), 7: (120, 30, 30), 8: (20, 20, 22)}  # Config.Balls.Colors

TIER_ORDER = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic', 'Secret', 'Exclusive',
              'Rank (Exclusive)', 'Unique']


def load_skin(skin_id):
    with open(os.path.join(SKINS, skin_id + '.json')) as handle:
        return json.load(handle)


def skin_dir(skin_id):
    return os.path.join(RENDERS, 'skins', skin_id)


# =============================================================================================
# Blender side
# =============================================================================================

def blender_main(args):
    import bpy
    from mathutils import Matrix, Vector
    import cue_common as cc
    import CueVfx as vfx

    skin_id = args[args.index('--skin') + 1]
    skin = load_skin(skin_id)
    quick = '--quick' in args
    out_dir = skin_dir(skin_id)
    os.makedirs(os.path.join(out_dir, 'stills'), exist_ok=True)
    V = skin.get('vfx') or {}
    surface = skin.get('surface') or {}
    tier = skin.get('tier', 'Common')

    # ---- scene ---------------------------------------------------------------------------------
    scene = cc.clear_scene('CuePreview')
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.fps = PREVIEW['fps']
    # Standard view: colours as authored on the dark charcoal (AgX and PBR Neutral were tried:
    # they wash glows out to peach and crush the background)
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.render.film_transparent = False
    try:
        scene.eevee.use_raytracing = True
        scene.eevee.ray_tracing_options.resolution_scale = '1'
    except Exception:
        pass
    # the camera sees the dark charcoal; reflections and light come from a CC0 studio HDRI
    # (Poly Haven studio_small_09, turned down), so gloss and chrome read as they do in the concept
    add_bloom(bpy, scene)
    world = bpy.data.worlds.new('Dark')
    world.use_nodes = True
    wn, wl = world.node_tree.nodes, world.node_tree.links
    bg = next(n for n in wn if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = PREVIEW['background'] + (1.0,)
    bg.inputs[1].default_value = 1.0
    env = wn.new('ShaderNodeTexEnvironment')
    env.image = bpy.data.images.load(os.path.join(HERE, 'vfx', '_env', 'studio_small_09_1k.hdr'), check_existing=True)
    studio = wn.new('ShaderNodeBackground')
    studio.inputs[1].default_value = PREVIEW['env_strength']
    wl.new(env.outputs['Color'], studio.inputs['Color'])
    lp = wn.new('ShaderNodeLightPath')
    mixw = wn.new('ShaderNodeMixShader')
    wl.new(lp.outputs['Is Camera Ray'], mixw.inputs['Fac'])
    wl.new(studio.outputs[0], mixw.inputs[1])
    wl.new(bg.outputs[0], mixw.inputs[2])
    wout = next(n for n in wn if n.type == 'OUTPUT_WORLD')
    wl.new(mixw.outputs[0], wout.inputs['Surface'])
    scene.world = world

    def new_light(name, kind, loc, energy, size=1.0, color=(1, 1, 1), target=(0, 0, 0)):
        data = bpy.data.lights.new(name, kind)
        data.energy = energy
        data.color = color
        if kind == 'AREA':
            data.size = size
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        look_at(obj, target)
        scene.collection.objects.link(obj)
        return obj

    def look_at(obj, target, up=(0, 0, 1)):
        f = (Vector(target) - obj.location).normalized()
        right = f.cross(Vector(up))
        if right.length < 1e-6:
            right = f.cross(Vector((0, 1, 0)))
        right.normalize()
        true_up = right.cross(f)
        obj.rotation_euler = Matrix((right, true_up, -f)).transposed().to_euler()

    lights = [new_light('Key', 'AREA', (-4, -6, 7), 500, 6, (1.0, 0.97, 0.93)),
              new_light('Fill', 'AREA', (6, -5, 2), 150, 7, (0.85, 0.9, 1.0)),
              new_light('Rim', 'AREA', (1, 7, 4), 500, 5, (0.9, 0.95, 1.0))]

    cam_data = bpy.data.cameras.new('Cam')
    cam_data.clip_start = 0.01
    cam_data.clip_end = 200
    cam = bpy.data.objects.new('Cam', cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    def set_cam(loc, target, lens=50, ortho=None, up=(0, 0, 1)):
        cam.location = loc
        look_at(cam, target, up)
        if ortho:
            cam_data.type = 'ORTHO'
            cam_data.ortho_scale = ortho
        else:
            cam_data.type = 'PERSP'
            cam_data.lens = lens

    # ---- the cue ---------------------------------------------------------------------------------
    cue = cc.load_cue_object()
    cue.name = 'CueSkin'
    maps = {k: os.path.join(TEXTURES, '%s_%s.png' % (skin_id, k)) for k in
            ('color', 'normal', 'roughness', 'metalness', 'emissive')}
    if not os.path.isfile(maps['emissive']):
        maps.pop('emissive')
    mat, cue_nodes = cue_material(bpy, maps, surface, skin_id)
    cue.data.materials.clear()
    cue.data.materials.append(mat)
    frames_spec = (V.get('Moving') or {}).get('Frames')
    frame_images = []
    if frames_spec:
        for f in frames_spec.get('Maps', []):
            frame_images.append({k: bpy.data.images.load(os.path.join(HERE, p), check_existing=True)
                                 for k, p in f.items()})
        for im_set in frame_images:
            for k, im in im_set.items():
                im.colorspace_settings.name = 'sRGB' if k == 'color' else 'Non-Color'

    back_cue = None

    def cue_matrix_on_back(body_m):
        s = PREVIEW['back']
        a = math.radians(s['tilt_deg'])
        tipdir = Vector((-math.sin(a), 0, math.cos(a)))  # toward the left shoulder (body faces +Y)
        grip = Vector((0, -0.5 - s['out'], 3.0))
        tip = grip + tipdir * s['grip_from_tip']
        Y = tipdir  # cue local +Y points past the tip
        Z = Vector((0, -1, 0))  # the top faces away from the back
        X = Y.cross(Z)
        m = Matrix((X, Y, Z)).transposed().to_4x4()
        m.translation = tip
        return body_m @ m

    # ---- effect objects ---------------------------------------------------------------------------
    fx_objs = {}

    def fx_material(key, texture, le, brightness=1.0, extension='CLIP'):
        name = 'FX_%s' % key
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nodes, links = m.node_tree.nodes, m.node_tree.links
        nodes.clear()
        out = nodes.new('ShaderNodeOutputMaterial')
        uv = nodes.new('ShaderNodeUVMap')
        uv.uv_map = 'UVMap'
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(texture, check_existing=True)
        tex.image.alpha_mode = 'STRAIGHT'
        tex.extension = extension
        tex.interpolation = 'Linear'
        links.new(uv.outputs['UV'], tex.inputs['Vector'])
        attr = nodes.new('ShaderNodeAttribute')
        attr.attribute_type = 'GEOMETRY'
        attr.attribute_name = 'fx'
        col = nodes.new('ShaderNodeMix')
        col.data_type = 'RGBA'
        col.blend_type = 'MULTIPLY'
        col.inputs['Factor'].default_value = 1.0
        links.new(tex.outputs['Color'], col.inputs['A'])
        links.new(attr.outputs['Color'], col.inputs['B'])
        alpha = nodes.new('ShaderNodeMath')
        alpha.operation = 'MULTIPLY'
        links.new(tex.outputs['Alpha'], alpha.inputs[0])
        links.new(attr.outputs['Alpha'], alpha.inputs[1])
        # Roblox LightEmission: 0 alpha blends, 1 adds; out = a(1-le) blend + a*le add
        blend = nodes.new('ShaderNodeMath')
        blend.operation = 'MULTIPLY'
        blend.inputs[1].default_value = 1.0 - le
        links.new(alpha.outputs[0], blend.inputs[0])
        em1 = nodes.new('ShaderNodeEmission')
        em1.inputs['Strength'].default_value = brightness
        links.new(col.outputs['Result'], em1.inputs['Color'])
        tr = nodes.new('ShaderNodeBsdfTransparent')
        mixs = nodes.new('ShaderNodeMixShader')
        links.new(blend.outputs[0], mixs.inputs['Fac'])
        links.new(tr.outputs['BSDF'], mixs.inputs[1])
        links.new(em1.outputs['Emission'], mixs.inputs[2])
        add_a = nodes.new('ShaderNodeMath')
        add_a.operation = 'MULTIPLY'
        add_a.inputs[1].default_value = le * brightness
        links.new(alpha.outputs[0], add_a.inputs[0])
        em2 = nodes.new('ShaderNodeEmission')
        links.new(col.outputs['Result'], em2.inputs['Color'])
        links.new(add_a.outputs[0], em2.inputs['Strength'])
        addsh = nodes.new('ShaderNodeAddShader')
        links.new(mixs.outputs[0], addsh.inputs[0])
        links.new(em2.outputs['Emission'], addsh.inputs[1])
        links.new(addsh.outputs[0], out.inputs['Surface'])
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            m.blend_method = 'BLEND'
        m.use_backface_culling = False
        return m

    def fx_object(key, texture, le, brightness=1.0, extension='CLIP'):
        if key in fx_objs:
            return fx_objs[key]
        me = bpy.data.meshes.new('FX_' + key)
        ob = bpy.data.objects.new('FX_' + key, me)
        scene.collection.objects.link(ob)
        me.materials.append(fx_material(key, texture, le, brightness, extension))
        fx_objs[key] = ob
        return ob

    def fill(ob, quads):
        me = ob.data
        me.clear_geometry()
        if quads is None or len(quads[0]) == 0:
            return
        corners, uv, rgba = quads
        n = len(corners)
        verts = corners.reshape(-1, 3)
        faces = np.arange(n * 4).reshape(n, 4)
        me.vertices.add(n * 4)
        me.vertices.foreach_set('co', verts.astype(np.float32).ravel())
        me.loops.add(n * 4)
        me.loops.foreach_set('vertex_index', faces.ravel().astype(np.int32))
        me.polygons.add(n)
        me.polygons.foreach_set('loop_start', (np.arange(n) * 4).astype(np.int32))
        me.update()
        uvl = me.uv_layers.new(name='UVMap') if 'UVMap' not in me.uv_layers else me.uv_layers['UVMap']
        uvl.data.foreach_set('uv', uv.reshape(-1, 2).astype(np.float32).ravel())
        if 'fx' in me.color_attributes:
            me.color_attributes.remove(me.color_attributes['fx'])
        ca = me.color_attributes.new('fx', 'FLOAT_COLOR', 'CORNER')
        lin = rgba.copy()
        # colours are sRGB in Roblox; the attribute is linear
        lin[..., :3] = np.where(lin[..., :3] <= 0.04045, lin[..., :3] / 12.92, ((lin[..., :3] + 0.055) / 1.055) ** 2.4)
        if lin.ndim == 2:  # one colour per quad
            lin = np.repeat(lin[:, None], 4, 1)
        ca.data.foreach_set('color', lin.reshape(-1, 4).astype(np.float32).ravel())

    # ---- world pieces: table, ball, avatar ------------------------------------------------------
    table = {}

    def build_table():
        if table:
            return table
        sys.path.insert(0, os.path.join(ROOT, 'assets', 'table'))
        import TableRender as tr
        objs = tr.load_table(scene)
        tr.dress_look(objs, 'blue')
        objs['Marks'].hide_render = True
        g = json.load(open(os.path.join(ROOT, 'assets', 'table', 'Geometry.json')))
        table['objs'] = objs
        table['g'] = g
        table['cloth_z'] = g['cloth']['above_floor_studs']
        table['r'] = g['ball']['radius'] * g['studs_per_inch']
        table['holes'] = {h['name']: h for h in g['holes']}
        floor = bpy.data.meshes.new('Floor')
        import bmesh
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=60)
        bm.to_mesh(floor)
        bm.free()
        fo = bpy.data.objects.new('Floor', floor)
        fm = bpy.data.materials.new('FloorMat')
        fm.use_nodes = True
        b = next(n for n in fm.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        b.inputs['Base Color'].default_value = PREVIEW['floor'] + (1.0,)
        b.inputs['Roughness'].default_value = 0.8
        floor.materials.append(fm)
        scene.collection.objects.link(fo)
        table['floor'] = fo
        # a warm overhead light over the table, like the game's table lamps
        lamp = new_light('TableLamp', 'AREA', (0, 0, 9), 110, 8, (1.0, 0.95, 0.88), (0, 0, 0))
        table['lamp'] = lamp
        return table

    balls = {}

    def ball(num):
        if num in balls:
            return balls[num]
        before = set(bpy.data.objects)
        bpy.ops.wm.obj_import(filepath=os.path.join(ROOT, 'assets', 'balls', 'ball_sphere.obj'))
        ob = [o for o in bpy.data.objects if o not in before][0]
        ob.name = 'Ball%d' % num
        m = bpy.data.materials.new('BallMat%d' % num)
        m.use_nodes = True
        b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        t = m.node_tree.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(os.path.join(ROOT, 'assets', 'balls', 'tex_%d.png' % num), check_existing=True)
        m.node_tree.links.new(t.outputs['Color'], b.inputs['Base Color'])
        b.inputs['Roughness'].default_value = 0.12
        b.inputs['Coat Weight'].default_value = 0.6
        ob.data.materials.clear()
        ob.data.materials.append(m)
        dims = max(ob.dimensions)
        r = build_table()['r']
        s = 2 * r / dims if dims > 0 else 1
        ob.scale = (s, s, s)
        balls[num] = ob
        return ob

    avatar = {}

    def build_avatar():
        if avatar:
            return avatar
        import bmesh
        parts = {  # name: (size w, d, h), centre, colour (Roblox "noob" colours, softened)
            'Torso': ((2.0, 1.0, 2.0), (0, 0, 3.0), (0.05, 0.28, 0.62)),
            'Head': ((1.2, 1.2, 1.2), (0, 0, 4.62), (0.93, 0.78, 0.18)),
            'LeftArm': ((1.0, 1.0, 2.0), (-1.5, 0, 3.0), (0.93, 0.78, 0.18)),
            'RightArm': ((1.0, 1.0, 2.0), (1.5, 0, 3.0), (0.93, 0.78, 0.18)),
            'LeftLeg': ((1.0, 1.0, 2.0), (-0.5, 0, 1.0), (0.2, 0.55, 0.22)),
            'RightLeg': ((1.0, 1.0, 2.0), (0.5, 0, 1.0), (0.2, 0.55, 0.22)),
        }
        root = bpy.data.objects.new('Avatar', None)
        scene.collection.objects.link(root)
        avatar['root'] = root
        for name, (size, centre, colour) in parts.items():
            me = bpy.data.meshes.new(name)
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.scale(bm, vec=size, verts=bm.verts)
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.08 if name != 'Head' else 0.3,
                            segments=3 if name != 'Head' else 6, affect='EDGES', profile=0.5)
            bm.to_mesh(me)
            bm.free()
            for p in me.polygons:
                p.use_smooth = True
            ob = bpy.data.objects.new(name, me)
            ob.location = centre
            ob.parent = root
            m = bpy.data.materials.new(name + 'Mat')
            m.use_nodes = True
            b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
            b.inputs['Base Color'].default_value = colour + (1.0,)
            b.inputs['Roughness'].default_value = 0.6
            me.materials.append(m)
            scene.collection.objects.link(ob)
            avatar[name] = ob
        return avatar

    # ---- simulation state ---------------------------------------------------------------------
    aura_specs = ((V.get('Aura') or {}).get('Emitters') or [])
    moving = V.get('Moving') or {}
    style_row = V.get('Style') or {}
    style = vfx.merged_style(style_row)

    aura_spec = V.get('Aura') or {}

    def make_aura(rate_scale=1.0, seed=1):
        ems = []
        for i, spec in enumerate(aura_specs + (moving.get('Emitters') or [])):
            ems.append(vfx.Emitter(spec, seed=seed + 31 * i, rate_scale=rate_scale))
        # the scripted pieces (orbiters, arcs) ride along like emitters
        ems += vfx.make_pieces(aura_spec, seed=seed, rate_scale=rate_scale)
        ems += vfx.make_pieces(moving, seed=seed + 7, rate_scale=rate_scale)
        return ems

    # PointLights on the cue (Aura.Lights): a Blender point light each, placed and flickered per
    # frame (Roblox Brightness x LIGHT_W watts; Range is Roblox's falloff, noted for the import)
    LIGHT_W = 14.0
    aura_lights = []
    for i, spec in enumerate(aura_spec.get('Lights') or []):
        ld = bpy.data.lights.new('AuraLight%d' % i, 'POINT')
        ld.color = tuple(vfx.hexf(spec.get('Color', '#FFFFFF')))
        ld.shadow_soft_size = 0.15
        lo = bpy.data.objects.new('AuraLight%d' % i, ld)
        scene.collection.objects.link(lo)
        lo.location = (0, 0, -50)
        aura_lights.append((spec, lo))
    clock = [0.0]

    def update_lights(host_m):
        for spec, lo in aura_lights:
            p = vfx.cue_point(spec.get('AtStuds', 5.0), spec.get('Up', 0.0), spec.get('Side', 0.0))
            lo.location = tuple(host_m[:3, :3] @ p + host_m[:3, 3])
            b = spec.get('Brightness', 1.0)
            if spec.get('Flicker'):
                b = b * vfx.wave(clock[0], spec['Flicker'])
            lo.data.energy = b * LIGHT_W

    def hide_lights():
        for spec, lo in aura_lights:
            lo.location = (0, 0, -50)
    beams = [vfx.Beam(b) for b in (aura_spec.get('Beams') or []) + (moving.get('Beams') or [])]

    def emitter_key(prefix, i, em):
        return '%s%d' % (prefix, i)

    def draw_emitters(prefix, ems, host_m, cam_m):
        for i, em in enumerate(ems):
            ob = fx_object(emitter_key(prefix, i, em), em.texture, em.le, em.brightness,
                           extension=getattr(em, 'extension', 'CLIP'))
            fill(ob, em.quads(host_m, cam_m))
        if prefix == 'Aura':
            update_lights(host_m)

    def clear_prefix(prefix):
        for k, ob in fx_objs.items():
            if k.startswith(prefix):
                ob.data.clear_geometry()
        if prefix == 'Aura':
            hide_lights()

    def set_surface(t):
        """Runtime pulses on the SurfaceAppearance (EmissiveStrength, Color) and frame swaps."""
        clock[0] = t
        pulses = (surface.get('Pulse') or {})
        es = surface.get('EmissiveStrength', 1.0)
        if 'EmissiveStrength' in pulses:
            es = vfx.wave(t, pulses['EmissiveStrength'])
        if cue_nodes.get('em_strength') is not None:
            cue_nodes['em_strength'].outputs[0].default_value = es
        tint = surface.get('Color')
        if 'Hue' in pulses:  # Chroma: the tint's hue runs round the wheel
            import colorsys
            p = pulses['Hue']
            h = (t / p.get('Period', 4.0)) % 1.0
            r, g, b = colorsys.hsv_to_rgb(h, p.get('Saturation', 0.75), p.get('Value', 1.0))
            tint = [r * 255, g * 255, b * 255]
        if tint is not None and cue_nodes.get('tint') is not None:
            c = vfx.hexf(tint) if isinstance(tint, str) else np.array(tint) / 255.0
            lin = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
            cue_nodes['tint'].inputs['B'].default_value = tuple(lin) + (1.0,)
        if frame_images:
            secs = frames_spec.get('FrameSeconds', 0.25)
            k = int(t / secs) % len(frame_images)
            for key, im in frame_images[k].items():
                node = cue_nodes['tex'].get(key)
                if node is not None:
                    node.image = im

    def beam_pulse(t):
        p = moving.get('BeamPulse')
        return vfx.wave(t, p) if p else 1.0

    def draw_beams(t, host_m, cam_m, prefix='Beam'):
        for i, b in enumerate(beams):
            ob = fx_object('%s%d' % (prefix, i), b.texture, b.le, b.brightness, extension='REPEAT')
            fill(ob, b.quads(t, host_m, cam_m, beam_pulse(t)))

    def cam_matrix():
        bpy.context.view_layer.update()
        return np.array(cam.matrix_world)

    def cue_m():
        bpy.context.view_layer.update()
        return np.array(cue.matrix_world)

    def render_to(path, samples):
        scene.eevee.taa_render_samples = samples
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)

    dt = 1.0 / PREVIEW['fps']

    def run_aura(ems, t0, t1, host_fn):
        """Advance emitters from t0 to t1 without drawing (prewarm)."""
        t = t0
        while t < t1 - 1e-9:
            m = host_fn(t)
            for em in ems:
                em.step(dt, m)
            t += dt

    # ---- stills ---------------------------------------------------------------------------------
    still_size = {'full': (2000, 200), 'joint': (900, 330), 'forearm': (900, 330), 'butt': (900, 330),
                  'threeq': (900, 600), 'aura': (1200, 900)}

    def place_cue(loc, rot):
        cue.location = loc
        cue.rotation_euler = rot

    def still(name, cam_args, cue_pose, samples=None, aura_t=None):
        w, h = still_size[name]
        scene.render.resolution_x, scene.render.resolution_y = w, h
        scene.render.resolution_percentage = 100
        place_cue(*cue_pose)
        set_cam(**cam_args)
        set_surface(aura_t or 1.0)
        for ob in fx_objs.values():
            ob.data.clear_geometry()
        hide_lights()
        if aura_t is not None:
            ems = make_aura()
            host = cue_m()
            run_aura(ems, 0, aura_t, lambda t: host)
            cm = cam_matrix()
            draw_emitters('Aura', ems, host, cm)
            draw_beams(aura_t, host, cm)
        elif beams:
            draw_beams(1.0, cue_m(), cam_matrix())
        render_to(os.path.join(out_dir, 'stills', name + '.png'), samples or PREVIEW['still_samples'])

    if '--stills' in args:
        horiz = ((-3.5, 0, 0), (0, 0, math.pi / 2))  # tip at the left, butt +X, top +Z
        e = math.radians(50)
        still('full', dict(loc=(0, -20 * math.cos(e), 20 * math.sin(e)), target=(0, 0, 0), ortho=7.2), horiz)
        # close-ups: (centre x = d - 3.5, width in studs seen)
        for name, x, width in (('joint', 0.35, 1.15), ('forearm', 1.05, 1.9), ('butt', 2.75, 1.7)):
            still(name, dict(loc=(x, -6 * math.cos(e), 6 * math.sin(e)), target=(x, 0, 0), ortho=width), horiz)
        diag = ((-2.6, 0, -1.5), (math.radians(-26), 0, math.pi / 2))
        still('threeq', dict(loc=(-0.2, -2.9, 1.3), target=(2.2, 0, 0.15), lens=40), horiz)
        still('aura', dict(loc=(0.55, -8.6, 0.9), target=(0.55, 0, 0.05), lens=38), diag, aura_t=PREVIEW['prewarm'])
        print('CUE preview stills done', skin_id)

    # ---- clip -----------------------------------------------------------------------------------
    if '--clip' in args:
        W, H = PREVIEW['clip_size']
        scene.render.resolution_x, scene.render.resolution_y = W, H
        frames_dir = os.path.join(out_dir, 'frames')
        os.makedirs(frames_dir, exist_ok=True)
        for f in os.listdir(frames_dir):
            os.remove(os.path.join(frames_dir, f))
        n_frame = [0]
        common = tier == 'Common' and not aura_specs
        samples = 8 if quick else PREVIEW['clip_samples']

        def shoot():
            path = os.path.join(frames_dir, '%05d.png' % n_frame[0])
            render_to(path, samples)
            n_frame[0] += 1

        # segment A: the turn
        seg = PREVIEW['common_turn'] if common else PREVIEW['segments']['turn']
        ems = make_aura()

        def turn_pose(t):
            # the cue turns slowly about the upright through its middle, tilted a little, butt
            # toward the camera side so the handle reads large
            ang = 0.32 * t - 0.55
            tilt = math.radians(14)
            R = Matrix.Rotation(ang, 4, 'Z') @ Matrix.Rotation(tilt, 4, 'Y') @ Matrix.Rotation(math.pi / 2, 4, 'Z')
            m = R.copy()
            m.translation = Vector((0, 0, 0)) - (R.to_3x3() @ Vector((0, -3.9, 0)))
            return m
        run_aura(ems, -PREVIEW['prewarm'], 0, lambda t: np.array(turn_pose(t)))
        t = 0.0
        while t < seg - 1e-9:
            cue.matrix_world = turn_pose(t)
            push = t / seg
            set_cam((0.35 * push, -8.2 + 2.2 * push, 1.9 - 0.4 * push), (0.4 * push, 0, 0.0), lens=40)
            set_surface(t)
            host = cue_m()
            for em in ems:
                em.step(dt, host)
            cm = cam_matrix()
            draw_emitters('Aura', ems, host, cm)
            draw_beams(t, host, cm)
            shoot()
            t += dt
        clear_prefix('Aura')
        clear_prefix('Beam')

        if not common:
            # segment B: on the back
            av = build_avatar()
            back_scale = (V.get('Aura') or {}).get('BackRateScale', 0.5)
            ems = make_aura(rate_scale=back_scale, seed=7)

            def back_pose(t):
                return cue_matrix_on_back(Matrix.Identity(4))
            run_aura(ems, -PREVIEW['prewarm'], 0, lambda t: np.array(back_pose(t)))
            seg = PREVIEW['segments']['back']
            t = 0.0
            while t < seg - 1e-9:
                cue.matrix_world = back_pose(t)
                a = math.radians(-38 + 30 * t / seg)
                dist = 13.0
                set_cam((dist * math.sin(a), -dist * math.cos(a), 5.6), (-0.4, 0, 3.9), lens=40)
                set_surface(t)
                host = cue_m()
                for em in ems:
                    em.step(dt, host)
                cm = cam_matrix()
                draw_emitters('Aura', ems, host, cm)
                draw_beams(t, host, cm)
                shoot()
                t += dt
            clear_prefix('Aura')
            clear_prefix('Beam')

            # segment C: the shot, with the ball trail
            tb = build_table()
            cz, r = tb['cloth_z'], tb['r']
            cue_ball = ball(0)
            start = Vector((-4.0, 0.0, cz + r))
            aim = Vector((1, 0.12, 0)).normalized()
            # the shooter stands behind the butt, leaning over the stroke
            av['root'].location = (-10.9, -1.25, 0)
            av['root'].rotation_euler = (math.radians(-24), 0, math.radians(-90 + 7))
            ems = make_aura(seed=11)
            trail_spec = trail_from_style(style)
            trail = vfx.Trail(trail_spec)
            ball_ems = [vfx.Emitter(s, seed=90 + i) for i, s in enumerate((V.get('Trail') or {}).get('Emitters') or [])]
            seg = PREVIEW['segments']['shot']
            strike = 0.75

            def shot_pose(t):
                # stroke: draw back, then forward through the ball
                if t < strike - 0.35:
                    back = 0.35 + 0.35 * min(t / (strike - 0.35), 1.0)
                else:
                    k = min((t - (strike - 0.35)) / 0.35, 1.0)
                    back = 0.7 - 0.85 * k
                tip = start - aim * (r + back)
                tip.z += 0.06
                Y = (aim + Vector((0, 0, 0.1))).normalized()  # +Y past the tip, the butt raised
                Z = Vector((0, 0, 1))
                X = Y.cross(Z).normalized()
                Z = X.cross(Y)
                m = Matrix((X, Y, Z)).transposed().to_4x4()
                m.translation = tip
                return m
            run_aura(ems, -PREVIEW['prewarm'], 0, lambda t: np.array(shot_pose(0)))
            speed0, decel = 5.2, 2.2
            t = 0.0
            while t < seg - 1e-9:
                cue.matrix_world = shot_pose(t)
                if t > strike:
                    u = t - strike
                    dist_b = speed0 * u - 0.5 * decel * u * u
                    pos = start + aim * dist_b
                else:
                    pos = start
                cue_ball.location = pos
                roll = (pos - start).length / r
                cue_ball.rotation_euler = (0, roll, math.atan2(aim.y, aim.x))
                if t < strike + 0.2:
                    set_cam((-9.6, -5.4, cz + 3.1), (-3.2, 0.5, cz + 0.2), lens=30)
                else:
                    # cut to a close camera riding beside the ball, to see the trail
                    p_ = Vector(pos)
                    set_cam(p_ + Vector((-2.4, -2.5, 1.25)), p_ + Vector((-0.5, 0.1, 0.0)), lens=34)
                set_surface(t)
                host = cue_m()
                for em in ems:
                    em.step(dt, host)
                trail.enabled = t > strike
                trail.step(t, np.array(pos))
                bm_ = np.array(Matrix.Translation(pos))
                for em in ball_ems:
                    em.step(dt, bm_, emitting=t > strike)
                cm = cam_matrix()
                draw_emitters('Aura', ems, host, cm)
                draw_beams(t, host, cm)
                ob = fx_object('Trail', trail.texture, trail.le, trail.brightness, extension='REPEAT')
                fill(ob, trail.quads(t, cm))
                if trail_spec.get('Core'):
                    core = trail_spec['Core']
                    if 'core' not in avatar:
                        avatar['core'] = vfx.Trail(core)
                    avatar['core'].enabled = t > strike
                    avatar['core'].step(t, np.array(pos))
                    ob = fx_object('TrailCore', avatar['core'].texture, avatar['core'].le, 1.0, extension='REPEAT')
                    fill(ob, avatar['core'].quads(t, cm))
                draw_emitters('BallFx', ball_ems, bm_, cm)
                shoot()
                t += dt
            for k in list(fx_objs):
                fx_objs[k].data.clear_geometry()
            hide_lights()
            av['root'].location = (0, 0, -50)
            cue.location = (0, 0, -50)

            # segment D: a ball drops into a corner pocket
            hole = tb['holes']['topRight']
            hx, hy = hole['studs']
            pocket = Vector((hx, hy, cz))
            eight = ball(PREVIEW['pocket_ball'])
            cue_ball.location = (0, 0, -50)
            dirv = Vector((hx, hy, 0)).normalized()
            p0 = pocket - dirv * 2.6
            p0.z = cz + r
            burst = PocketBurst(vfx, V, style_row, pocket, eight=False, ball_rgb=BALL_COLOURS[PREVIEW['pocket_ball']])
            seg = PREVIEW['segments']['pocket']
            trail = vfx.Trail(trail_spec)
            drop_t = 0.5
            t = 0.0
            while t < seg - 1e-9:
                if t < drop_t:
                    k = t / drop_t
                    pos = p0 + (pocket - p0) * k
                    pos.z = cz + r
                else:
                    u = t - drop_t
                    pos = pocket.copy()
                    pos.z = cz + r - 9.8 * 3 * u * u
                eight.location = pos
                cam_t = pocket + Vector((-0.6, -0.4, 1.7))
                set_cam(pocket + Vector((-6.2, -6.4, 3.6)) + Vector((0.4 * t, 0.3 * t, 0)), cam_t, lens=32)
                trail.enabled = t < drop_t
                trail.step(t, np.array(pos))
                cm = cam_matrix()
                ob = fx_object('Trail', trail.texture, trail.le, trail.brightness, extension='REPEAT')
                fill(ob, trail.quads(t, cm))
                burst.step(t - drop_t, dt, cm, fx_object, fill, bpy, scene)
                shoot()
                t += dt

        # encode
        out = os.path.join(out_dir, 'clip.mp4')
        encode(bpy, frames_dir, n_frame[0], out, W, H, PREVIEW['fps'])
        print('CUE preview clip', out, n_frame[0], 'frames')


def trail_from_style(style):
    """Config.Effects Trail keys -> a Roblox Trail spec (what Effects builds for the cue ball)."""
    tr = style['Trail']
    colours = tr.get('Colors')
    if colours:
        color = [[i / max(len(colours) - 1, 1), c] for i, c in enumerate(colours)]
    else:
        color = tr['Color']
    spec = {'Lifetime': tr['Lifetime'], 'WidthStuds': tr['WidthStuds'], 'Color': color,
            'Transparency': [[0, tr['NearTransparency']], [1, tr['FarTransparency']]],
            'WidthScale': tr.get('WidthScale', [[0, 1], [1, 0.35]]), 'LightEmission': tr['LightEmission'],
            'MinLength': tr['MinLengthStuds'], 'Texture': tr.get('Texture') or 'vfx/_shared/trail_soft.png',
            'TextureMode': tr.get('TextureMode', 'Stretch'), 'TextureLength': tr.get('TextureLength', 1)}
    if tr.get('Core'):
        core = tr['Core']
        spec['Core'] = {'Lifetime': tr['Lifetime'], 'WidthStuds': tr['WidthStuds'] * core.get('Width', 0.35),
                        'Color': core['Color'], 'Transparency': [[0, core.get('NearTransparency', 0.2)], [1, 1]],
                        'WidthScale': [[0, 1], [1, 0.3]], 'LightEmission': core.get('LightEmission', 1),
                        'MinLength': tr['MinLengthStuds'], 'Texture': core.get('Texture') or 'vfx/_shared/trail_soft.png'}
    return spec


class PocketBurst:
    """Effects.pocketBurst's layers for a style, plus the skin's extra layers (vfx.Pocket.Layers,
    each an emitter with Burst and Delay; Rings; a Flash)."""

    def __init__(self, vfx, V, style_row, at, eight=False, ball_rgb=(250, 200, 40)):
        self.vfx = vfx
        self.at = at
        base = vfx.pocket_layers(style_row, ball_rgb, eight)
        self.base = base
        extra = (V.get('Pocket') or {})
        self.layers = []
        for i, spec in enumerate(base['layers'] + (extra.get('Layers') or [])):
            spec = dict(spec)
            spec.setdefault('Host', {'Kind': 'Point'})
            self.layers.append((spec.get('Delay', 0.0), spec, vfx.Emitter(spec, seed=500 + i)))
        self.rings = [dict(base['ring'], Delay=0.0)] + list(extra.get('Rings') or [])
        self.ribbons = base['ribbons'] if extra.get('KeepRibbons', True) else None
        self.flash = dict(base['flash'], **(extra.get('Flash') or {}))
        self.fired = set()
        self.ribbon_trails = None
        self.light = None

    def step(self, t, dt, cam_m, fx_object, fill, bpy, scene):
        import numpy as np
        from mathutils import Vector
        vfx = self.vfx
        host = np.eye(4)
        host[:3, 3] = np.array(self.at)
        for i, (delay, spec, em) in enumerate(self.layers):
            if t >= delay and i not in self.fired:
                self.fired.add(i)
                em.emit(int(spec.get('Burst', 0)), host)
            if t >= delay - dt:
                em.step(dt, host, emitting=False)
            ob = fx_object('Pocket%d' % i, em.texture, em.le, em.brightness)
            fill(ob, em.quads(host, cam_m) if t >= delay else None)
        # shockwave rings: a flat decal on the cloth growing and fading (Quart out)
        for j, ring in enumerate(self.rings):
            u = (t - ring.get('Delay', 0.0)) / ring.get('Seconds', 0.45)
            ob = fx_object('Ring%d' % j, os.path.join(HERE, ring['Texture']), ring.get('LightEmission', 1.0), 1.0)
            if 0 <= u <= 1:
                e = 1 - (1 - u) ** 4
                size = ring['Start'] + (ring['End'] - ring['Start']) * e
                h = size / 2
                c = np.array(self.at) + np.array([0, 0, 0.02 + ring.get('Height', 0.0)])
                corners = np.array([[c + [-h, -h, 0], c + [h, -h, 0], c + [h, h, 0], c + [-h, h, 0]]])
                uv = np.array([[[0, 0], [1, 0], [1, 1], [0, 1]]], np.float64)
                col = np.array(ring['Color'], np.float64) / 255.0 if not isinstance(ring['Color'], str) else vfx.hexf(ring['Color'])
                rgba = np.array([list(col) + [1 - e * (1 - ring.get('EndTransparency', 1.0)) if ring.get('EndTransparency') is not None else 1 - e]])
                fill(ob, (corners, uv, rgba))
            else:
                fill(ob, None)
        # the swirl ribbons (Trails on moving attachments)
        rb = self.ribbons
        if rb:
            if self.ribbon_trails is None:
                self.ribbon_trails = [vfx.Trail({'Lifetime': rb['TrailSeconds'], 'WidthStuds': rb['Width'],
                                                 'Color': rb['Color'], 'Transparency': [[0, 0.1], [1, 1]],
                                                 'WidthScale': [[0, 1], [1, 0]], 'LightEmission': rb['LightEmission'],
                                                 'MinLength': 0.01}) for _ in range(rb['Count'])]
            u = max(0.0, min(t / rb['SwirlSeconds'], 1.0))
            rise = 1 - (1 - u) * (1 - u)
            radius = rb['R0'] + (rb['R1'] - rb['R0']) * rise
            height = rb['Height'] * rise
            for n, tr in enumerate(self.ribbon_trails):
                phase = n / rb['Count'] * math.pi * 2
                ang = phase + rb['Turns'] * math.pi * 2 * rise
                p = np.array(self.at) + np.array([math.cos(ang) * radius, math.sin(ang) * radius, height])
                tr.enabled = 0 <= t <= rb['SwirlSeconds']
                if t >= 0:
                    tr.step(t, p)
                ob = fx_object('Ribbon%d' % n, tr.texture, tr.le, 1.0, extension='REPEAT')
                fill(ob, tr.quads(t, cam_m) if t >= 0 else None)
        # the flash: a PointLight tweened to 0 (Roblox Brightness ~ a few hundred W here)
        if self.light is None:
            data = bpy.data.lights.new('PocketFlash', 'POINT')
            data.shadow_soft_size = 0.3
            self.light = bpy.data.objects.new('PocketFlash', data)
            self.light.location = Vector(self.at) + Vector((0, 0, 0.6))
            scene.collection.objects.link(self.light)
            c = self.flash['Color']
            col = np.array(c, np.float64) / 255.0 if not isinstance(c, str) else vfx.hexf(c)
            data.color = tuple(col)
        k = 0.0
        if 0 <= t <= self.flash['Seconds']:
            k = 1 - t / self.flash['Seconds']
        self.light.data.energy = 60.0 * self.flash['Brightness'] * k


def add_bloom(bpy, scene):
    """A modest bloom, like Roblox's Lighting.Bloom on a dark scene: only bright emissive and
    additive light blooms (threshold near white), softly."""
    try:
        tree = bpy.data.node_groups.new('Bloom', 'CompositorNodeTree')
        tree.interface.new_socket('Image', in_out='OUTPUT', socket_type='NodeSocketColor')
        rl = tree.nodes.new('CompositorNodeRLayers')
        gl = tree.nodes.new('CompositorNodeGlare')
        out = tree.nodes.new('NodeGroupOutput')
        gl.inputs['Type'].default_value = 'Bloom'
        gl.inputs['Quality'].default_value = 'High'
        gl.inputs['Threshold'].default_value = PREVIEW['bloom'][0]
        gl.inputs['Strength'].default_value = PREVIEW['bloom'][1]
        gl.inputs['Size'].default_value = PREVIEW['bloom'][2]
        tree.links.new(rl.outputs['Image'], gl.inputs['Image'])
        tree.links.new(gl.outputs['Image'], out.inputs[0])
        scene.compositing_node_group = tree
    except Exception as exc:  # an older Blender: no bloom
        print('CUE preview: no bloom (%s)' % exc)


def cue_material(bpy, maps, surface, skin_id):
    """The SurfaceAppearance, previewed: ColorMap x Color (tint), Normal, Roughness, Metalness, and
    the emissive mask lighting ColorMap x EmissiveTint x EmissiveStrength."""
    mat = bpy.data.materials.new('Skin_' + skin_id)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'UVMap'
    out = {'tex': {}}

    def tex(key, colour):
        node = nodes.new('ShaderNodeTexImage')
        node.image = bpy.data.images.load(maps[key], check_existing=False)
        node.image.colorspace_settings.name = 'sRGB' if colour else 'Non-Color'
        node.interpolation = 'Linear'
        links.new(uv.outputs['UV'], node.inputs['Vector'])
        out['tex'][key] = node
        return node
    col = tex('color', True)
    tint = nodes.new('ShaderNodeMix')
    tint.data_type = 'RGBA'
    tint.blend_type = 'MULTIPLY'
    tint.inputs['Factor'].default_value = 1.0
    links.new(col.outputs['Color'], tint.inputs['A'])
    tint.inputs['B'].default_value = (1, 1, 1, 1)
    out['tint'] = tint
    links.new(tint.outputs['Result'], bsdf.inputs['Base Color'])
    links.new(tex('roughness', False).outputs['Color'], bsdf.inputs['Roughness'])
    links.new(tex('metalness', False).outputs['Color'], bsdf.inputs['Metallic'])
    nm = nodes.new('ShaderNodeNormalMap')
    nm.space = 'TANGENT'
    nm.uv_map = 'UVMap'
    links.new(tex('normal', False).outputs['Color'], nm.inputs['Color'])
    links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    out['em_strength'] = None
    if maps.get('emissive'):
        em = tex('emissive', False)
        lit = nodes.new('ShaderNodeMix')
        lit.data_type = 'RGBA'
        lit.blend_type = 'MULTIPLY'
        lit.inputs['Factor'].default_value = 1.0
        links.new(tint.outputs['Result'], lit.inputs['A'])
        links.new(em.outputs['Color'], lit.inputs['B'])
        et = nodes.new('ShaderNodeMix')
        et.data_type = 'RGBA'
        et.blend_type = 'MULTIPLY'
        et.inputs['Factor'].default_value = 1.0
        links.new(lit.outputs['Result'], et.inputs['A'])
        tint_hex = surface.get('EmissiveTint', '#FFFFFF')
        c = [int(tint_hex[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
        c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
        et.inputs['B'].default_value = tuple(c) + (1.0,)
        links.new(et.outputs['Result'], bsdf.inputs['Emission Color'])
        strength = nodes.new('ShaderNodeValue')
        strength.outputs[0].default_value = surface.get('EmissiveStrength', 1.0)
        # EmissiveStrength 1 adds the colour map once (as Roblox draws it)
        mul = nodes.new('ShaderNodeMath')
        mul.operation = 'MULTIPLY'
        mul.inputs[1].default_value = 1.0
        links.new(strength.outputs[0], mul.inputs[0])
        links.new(mul.outputs[0], bsdf.inputs['Emission Strength'])
        out['em_strength'] = strength
    return mat, out


def encode(bpy, frames_dir, count, out, w, h, fps):
    """PNG frames -> H.264 MP4 through Blender's own FFMPEG (the sequencer)."""
    scene = bpy.data.scenes.new('Encode')
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.resolution_percentage = 100
    scene.render.fps = fps
    scene.frame_start, scene.frame_end = 1, count
    seq = scene.sequence_editor_create()
    files = sorted(f for f in os.listdir(frames_dir) if f.endswith('.png'))
    strips = seq.strips if hasattr(seq, 'strips') else seq.sequences
    strip = strips.new_image('Frames', os.path.join(frames_dir, files[0]), 1, 1)
    for f in files[1:]:
        strip.elements.append(f)
    strip.frame_final_duration = len(files)
    r = scene.render
    try:
        r.image_settings.media_type = 'VIDEO'  # Blender 5: video is a media type first
    except (AttributeError, TypeError):
        pass
    r.image_settings.file_format = 'FFMPEG'
    r.ffmpeg.format = 'MPEG4'
    r.ffmpeg.codec = 'H264'
    r.ffmpeg.constant_rate_factor = 'HIGH'
    r.ffmpeg.ffmpeg_preset = 'GOOD'
    r.filepath = out
    scene.view_settings.view_transform = 'Standard'
    bpy.ops.render.render(animation=True, scene=scene.name)
    # Blender appends the frame range to the name unless the path has an extension it keeps
    base = os.path.dirname(out)
    for f in os.listdir(base):
        if f.startswith('clip') and f.endswith('.mp4') and f != 'clip.mp4':
            os.replace(os.path.join(base, f), out)


# =============================================================================================
# Plain Python side: the labelled sheets
# =============================================================================================

def font(size, bold=False):
    from PIL import ImageFont
    for path in ('/System/Library/Fonts/Avenir Next.ttc', '/System/Library/Fonts/Helvetica.ttc'):
        try:
            return ImageFont.truetype(path, size, index=(5 if bold else 0) if 'Avenir' in path else 0)
        except Exception:
            continue
    return ImageFont.load_default()


def sheet(skin_id):
    from PIL import Image, ImageDraw
    skin = load_skin(skin_id)
    sdir = os.path.join(skin_dir(skin_id), 'stills')
    W = 2000
    bg = (22, 24, 29)
    pieces = []

    def im(name):
        p = os.path.join(sdir, name + '.png')
        return Image.open(p).convert('RGB') if os.path.isfile(p) else None

    canvas = Image.new('RGB', (W, 2400), bg)
    d = ImageDraw.Draw(canvas)
    y = 20
    d.text((30, y), '%s  (%s)' % (skin.get('name', skin_id).upper(), skin.get('tier', '')), fill=(240, 240, 240), font=font(40, True))
    d.text((30, y + 52), skin.get('note', '')[:190], fill=(170, 175, 185), font=font(20))
    y += 100

    def label(text, x, yy):
        d.text((x + 10, yy + 8), text, fill=(235, 235, 235), font=font(22, True))

    full = im('full')
    if full:
        canvas.paste(full, (0, y))
        label('RENDER: FULL CUE (seen from 50 degrees above: the top, which faces you in the hand and on the back)', 0, y)
        y += full.height + 8
    cdir = os.path.join(CONCEPTS, 'cues', skin_id)
    cfull = os.path.join(cdir, 'full.png')
    if os.path.isfile(cfull):
        c = Image.open(cfull).convert('RGB')
        c = c.resize((W - 40, int(c.height * (W - 40) / c.width)))
        canvas.paste(c, (20, y))
        label('CONCEPT', 20, y)
        y += c.height + 12
    row = [im('joint'), im('forearm'), im('butt')]
    names = ['RENDER: JOINT', 'RENDER: FOREARM', 'RENDER: BUTT']
    x = 0
    tw = (W - 16) // 3
    for img, name in zip(row, names):
        if img:
            img = img.resize((tw, int(img.height * tw / img.width)))
            canvas.paste(img, (x, y))
            label(name, x, y)
            h = img.height
        x += tw + 8
    y += (h if row[0] else 0) + 8
    close = os.path.join(cdir, 'closeup.png')
    if os.path.isfile(close):
        c = Image.open(close).convert('RGB')
        cw = W - 40
        c = c.resize((cw, int(c.height * cw / c.width)))
        if c.height > 420:
            c = c.resize((int(c.width * 420 / c.height), 420))
        canvas.paste(c, (20, y))
        label('CONCEPT: HANDLE CLOSE-UP', 20, y)
        y += c.height + 12
    three, aura = im('threeq'), im('aura')
    x = 0
    hrow = 0
    if three:
        t3 = three.resize((900, 600))
        canvas.paste(t3, (0, y))
        label('RENDER: 3/4', 0, y)
        hrow = 600
        x = 908
    if aura:
        a = aura.resize((800, 600))
        canvas.paste(a, (x, y))
        label('RENDER: AURA (a still from the preview)', x, y)
        hrow = 600
    vfxc = os.path.join(cdir, 'vfx.png')
    if os.path.isfile(vfxc) and hrow:
        c = Image.open(vfxc).convert('RGB')
        rest = W - (x + 808)
        if rest > 120:
            c = c.resize((rest - 8, int(c.height * (rest - 8) / c.width)))
            canvas.paste(c, (x + 808, y))
            label('CONCEPT VFX', x + 808, y)
    y += hrow + 12
    extras = [n for n in ('trail', 'pocket') if os.path.isfile(os.path.join(cdir, n + '.png'))]
    if extras:
        x = 20
        for n in extras:
            c = Image.open(os.path.join(cdir, n + '.png')).convert('RGB')
            c = c.resize((int(c.width * 260 / c.height), 260))
            canvas.paste(c, (x, y))
            label('CONCEPT ' + n.upper(), x, y)
            x += c.width + 12
        y += 272
    canvas = canvas.crop((0, 0, W, y + 10))
    out = os.path.join(skin_dir(skin_id), 'sheet.png')
    canvas.save(out, optimize=True)
    print('CUE preview sheet', out)


def tier_sheet(tier):
    from PIL import Image, ImageDraw
    ids = []
    for f in sorted(os.listdir(SKINS)):
        if f.endswith('.json') and not f.startswith('_'):
            s = load_skin(f[:-5])
            if s.get('tier') == tier and os.path.isfile(os.path.join(skin_dir(s['id']), 'stills', 'full.png')):
                ids.append((s.get('order', 99), s['id'], s))
    ids.sort()
    if not ids:
        print('no skins for', tier)
        return
    W = 2000
    row_h, aura_w = 230, 260
    H = 90 + len(ids) * row_h + 40 + ((len(ids) + 6) // 7) * (aura_w + 50)
    canvas = Image.new('RGB', (W, H), (22, 24, 29))
    d = ImageDraw.Draw(canvas)
    d.text((30, 20), tier.upper(), fill=(240, 240, 240), font=font(44, True))
    y = 90
    for _, sid, s in ids:
        full = Image.open(os.path.join(skin_dir(sid), 'stills', 'full.png')).convert('RGB')
        full = full.resize((W - 260, int(full.height * (W - 260) / full.width)))
        canvas.paste(full, (250, y + (row_h - full.height) // 2))
        d.text((30, y + row_h // 2 - 16), s.get('name', sid), fill=(235, 235, 235), font=font(30, True))
        y += row_h
    y += 20
    x = 30
    for i, (_, sid, s) in enumerate(ids):
        p = os.path.join(skin_dir(sid), 'stills', 'aura.png')
        if os.path.isfile(p):
            a = Image.open(p).convert('RGB')
            a = a.crop(((a.width - a.height) // 2, 0, (a.width + a.height) // 2, a.height)).resize((aura_w, aura_w))
            canvas.paste(a, (x, y))
            d.text((x, y + aura_w + 6), s.get('name', sid), fill=(200, 200, 200), font=font(22))
        x += aura_w + 20
        if x + aura_w > W:
            x = 30
            y += aura_w + 50
    canvas = canvas.crop((0, 0, W, min(H, y + aura_w + 50)))
    os.makedirs(os.path.join(RENDERS, 'tiers'), exist_ok=True)
    out = os.path.join(RENDERS, 'tiers', tier.lower().replace(' ', '_').replace('(', '').replace(')', '') + '.png')
    canvas.save(out, optimize=True)
    print('CUE preview tier', out)


def main():
    argv = sys.argv
    args = argv[argv.index('--') + 1:] if '--' in argv else argv[1:]
    try:
        import bpy  # noqa: F401
        in_blender = True
    except ImportError:
        in_blender = False
    if in_blender:
        blender_main(args)
    elif '--sheet' in args:
        sheet(args[args.index('--sheet') + 1])
    elif '--tier' in args:
        tier_sheet(args[args.index('--tier') + 1])
    else:
        print(__doc__)


if __name__ == '__main__':
    main()
