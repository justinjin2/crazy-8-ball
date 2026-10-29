"""The Halloween Sword Cue (Halloween 2026's top prize, 7000 Candy; coordinator 19:2x 2026-10-28,
Justin: "use this purple model, completely different from the cue model, try to replicate this
exactly"): the sword IS the cue body, drawn in place of the shared cue mesh.

Built from the Meshy image-to-3D model of the concept's three-quarter reference
(assets/cue/models/halloween_sword, from ~/Desktop/8ball-refs/halloween/sword/sword_34_ref.png),
split along its length and re-proportioned onto the cue frame (Y 0 at the tip, -7 at the butt):

  * the blade, tip to 3.85 studs (the Meshy blade at one scale), its first 0.3 studs pinched to
    the tip rule and its thickness flattened to the cue envelope through the bridge hand
    (0.3-2.1), so the hand holds a solid part no thicker than a cue: part Body_Steel;
  * the flame edges, the same blade faces that are violet in the texture and outside the dark
    core, on their own joint with "Aim": "fade": they overlap the bridge hand (allowed, brief
    2.2 exception below) and clear on the owner's screen while aiming: part Flames_Flame;
  * the pumpkin guard with its bat wings, 3.76-4.38 (before the grip hand at 4.4), wide like
    the art, short along the cue and flattened so it stays within the +Z and -Z allowances:
    part Body_Guard, its carved face glowing through the emissive mask;
  * a wrapped grip, a lathe at the envelope from 4.4 to 6.8 (the hand rule, unchanged) with a
    painted criss-cross binding (vfx/halloween_sword/wrap_256.png): part Body_Wrap;
  * the socket and faceted crystal pommel, 6.8 to 7.28 (0.28 past the butt, within the plain
    0.3, so it never fades): part Body_Pommel.

Five MeshParts, about 7,900 triangles, one 512 px colour atlas (the Meshy colour rebaked onto
clean UVs, see _rebake) and a 512 px emissive mask shared by the four textured parts, plus a
256 wrap tile for the grip.

The §2.2 rules this body relaxes, by name (CuePiecesHalloween_A.BODY_EXCEPTIONS, checked by
check_body): up to 4.4 studs the sideways width may exceed envelope +0.08 (the blade and the
wings: Justin's silhouette wins; nothing sits beside a cue but a rail); in the bridge hand zone
the radius rule applies only in Z (up/down) and only to the solid core's joints (Body), the
flames being free to overlap the hand. Kept everywhere: the tip (0.12 across for 0.3), the
centreline through both hands, the downward reach (envelope +0.08), the +Z allowance, the grip
hand zone 4.4-6.75 at the envelope, the butt and past-butt limits, the budget.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import CuePiecesHalloween_A as A  # noqa: E402
from CuePieces import piece, PIECES_DIR, apply_modifier  # noqa: E402
from CuePiecesHalloween_A import envelope, check_body, _revolve, _finish  # noqa: E402
from CuePiecesGhostLantern import _ghost_glow, _ghost_place  # noqa: E402

MODEL = 'halloween_sword'
SWORD = {'Black': '#1A1424', 'Deep': '#3B1F5C', 'Violet': '#7B2FF7', 'Orchid': '#B05CFF', 'Lavender': '#D9C2FF'}

# The Meshy model's regions along its own Z (the tip at +0.95, the pommel's point at -0.95;
# measured 2026-10-28 19:31: |x| 0.2 along the blade, the wings 0.35, the grip 0.035).
M_TIP, M_GUARD0, M_GUARD1, M_GRIP1, M_END = 0.95, -0.30, -0.58, -0.78, -0.95
BLADE_END = 4.32          # the blade meets the guard here (one scale for the whole blade)
GUARD0, GUARD1 = 4.23, 4.85   # the guard ends where the grip hand's full wind-up reaches (4.92 measured, 20:5x)
GUARD_X, GUARD_Z = 2.6, 1.6   # the guard's own scales: wide like the art, flattened in Z
GUARD_LIFT = 0.055          # the pumpkin and wings lifted so their underside stays within envelope + 0.08 at 4.2-4.3
GRIP0, GRIP1 = 4.87, 6.80
POMMEL1 = 7.28            # the crystal's point: 0.28 past the butt (plain limit 0.3)
POMMEL_S = (POMMEL1 - GRIP1) / (M_GRIP1 - M_END)
BLADE_S = BLADE_END / (M_TIP - M_GUARD0)
ATLAS_PX = 512            # the baked atlas: 512 read the same as 1024 up close in the lab (20:08), so phones get 512
CORE_BEVEL = 0.018        # model units: the light bevel line along the dark core's edge stays on the blade
A.BODY_EXCEPTIONS['halloween_sword'] = {'WideX': 4.9, 'BridgeCore': ('Body',), 'GuardInGripZone': (4.4, 4.9)}


def _smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def _emissive(px):
    """The violet flames, the carved face, the crystal and the ridge's light glow: the bright
    pixels of the Meshy colour map."""
    import numpy as np
    v = px.max(axis=2)
    return np.clip((v - 0.42) / 0.33, 0.0, 1.0) ** 1.2


def wrap_map(bpy, size=256):
    """vfx/halloween_sword/wrap_256.png: the grip's criss-cross binding, a diamond lattice of
    deep purple cord over near-black leather, seamless both ways (two bands each way a tile).
    Written through bpy (Blender's Python has no PIL)."""
    import numpy as np
    rel = 'vfx/halloween_sword/wrap_256.png'
    path = os.path.join(os.path.dirname(PIECES_DIR), rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    u = (np.arange(size) + 0.5) / size
    U, V = np.meshgrid(u, u)
    rng = np.random.default_rng(11)
    noise = rng.random((size, size)).astype(np.float32)

    def band(phase):
        # distance to the nearest cord centre line, two cords a tile each way
        f = (phase * 2.0) % 1.0
        return np.abs(f - 0.5) * 2.0          # 0 on the cord's centre, 1 between cords
    a, b = band(U + V), band(U - V)
    cord = np.minimum(a, b)
    on = np.clip((0.42 - cord) / 0.1, 0, 1)   # the cord's width
    shade = 1.0 - 0.6 * np.clip((cord - 0.25) / 0.17, 0, 1)   # a rounded cord: bright centre
    leather = np.array((26, 20, 36), np.float32)[None, None, :] * (0.85 + 0.3 * noise[..., None])
    cordc = np.array((70, 38, 110), np.float32)[None, None, :] * shade[..., None] + np.array((40, 18, 60), np.float32)
    img = leather * (1 - on[..., None]) + cordc * on[..., None]
    # the lattice's crossings lifted
    cross = np.clip((0.2 - np.maximum(a, b)) / 0.1, 0, 1)
    img += cross[..., None] * np.array((60, 30, 90), np.float32)
    rgb = np.clip(img, 0, 255).astype(np.float32) / 255.0
    out = bpy.data.images.new('wrap_256', size, size, alpha=False)
    out.pixels.foreach_set(np.concatenate([rgb, np.ones((size, size, 1), np.float32)], -1).ravel())
    out.filepath_raw = path
    out.file_format = 'PNG'
    out.save()
    return rel


def _import(k):
    bpy = k.bpy
    src = os.path.join(HERE, 'models', MODEL)
    glb = os.path.join(src, 'model.glb')
    if not os.path.isfile(glb):
        glb = os.path.join(src, 'source.glb')
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    obs = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
    for o in [o for o in bpy.data.objects if o not in before and o.type != 'MESH']:
        for c in o.children:
            mw = c.matrix_world.copy()
            c.parent = None
            c.matrix_world = mw
        bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob, src


def _meshy_colour(src):
    path = os.path.join(src, 'base_color.png')
    if not os.path.isfile(path):
        path = os.path.join(src, 'maps', 'base_color.png')
    return path


def _maps(k, img, name='Sword'):
    """The baked atlas saved at its size and its emissive mask at 512, once, shared by the parts."""
    import numpy as np
    bpy = k.bpy
    out = os.path.join(PIECES_DIR, k.pid)
    os.makedirs(out, exist_ok=True)
    rel = 'pieces/%s/%s_base_color.png' % (k.pid, name)
    img.filepath_raw = os.path.join(HERE, rel)
    img.file_format = 'PNG'
    img.save()
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3]
    mask = _emissive(px)
    em = bpy.data.images.new(name + '_emissive', w, h, alpha=False)
    em.pixels.foreach_set(np.concatenate([np.repeat(mask[..., None], 3, -1), np.ones((h, w, 1), np.float32)], -1).ravel())
    em.scale(512, 512)
    rel_e = 'pieces/%s/%s_emissive.png' % (k.pid, name)
    em.filepath_raw = os.path.join(HERE, rel_e)
    em.file_format = 'PNG'
    em.save()
    return rel, rel_e, px


def _face_classes(ob, px):
    """Per face: its region ('blade', 'flame', 'guard', 'grip', 'pommel') from where it sits on
    the model. On the blade the split is geometric: the dark core's half-width is measured
    band by band from the faces the texture paints dark (plus the light bevel line along its
    edge), and a face outside that outline is a flame. A split by each face's own colour put
    the blade's bright bevel faces into the flames and left pale wedges on the core (lab
    19:52)."""
    import numpy as np
    me = ob.data
    h, w = px.shape[:2]
    uvl = me.uv_layers.active.data
    V = np.array([v.co[:] for v in me.vertices])
    centres, out = [], []
    for p in me.polygons:
        centres.append(V[list(p.vertices)].mean(axis=0))
    centres = np.array(centres)
    # the core's outline: per 0.05 band of the blade, the widest dark face centre
    band = 0.05
    nb = int(math.ceil((M_TIP - M_GUARD0) / band)) + 1
    core = np.zeros(nb)
    for p, c in zip(me.polygons, centres):
        if c[2] > M_GUARD0:
            uv = np.mean([uvl[l].uv[:] for l in p.loop_indices], axis=0)
            col = px[int(np.clip(uv[1] * h, 0, h - 1)), int(np.clip(uv[0] * w, 0, w - 1))]
            if col.max() < 0.33:
                b = int((M_TIP - c[2]) / band)
                core[b] = max(core[b], abs(c[0]))
    # fill empty bands from their neighbours and smooth a little
    for i in range(nb):
        if core[i] == 0:
            near = [core[j] for j in (i - 1, i + 1, i - 2, i + 2) if 0 <= j < nb and core[j] > 0]
            core[i] = max(near) if near else 0.0
    core = np.maximum(core, np.concatenate([[0], core[:-1]]) * 0.9)
    for c in centres:
        if c[2] > M_GUARD0:
            b = int((M_TIP - c[2]) / band)
            out.append('flame' if abs(c[0]) > core[b] + CORE_BEVEL else 'blade')
        elif c[2] > M_GUARD1:
            out.append('guard')
        elif c[2] > M_GRIP1:
            out.append('grip')
        else:
            out.append('pommel')
    return out


def _region_object(k, ob, classes, region, name, mapping, target):
    """A copy of `ob` keeping only `region`'s faces, every vertex moved by mapping(x, y, z) ->
    (X, Y, Z) in the Blender cue frame, reduced to about `target` triangles (each region on its
    own: a collapse across the whole model made slivers from the pommel to the blade)."""
    import bmesh
    bpy = k.bpy
    me = ob.data.copy()
    new = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(new)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    drop = [f for f in bm.faces if classes[f.index] != region]
    bmesh.ops.delete(bm, geom=drop, context='FACES')
    # Meshy duplicates every vertex along its chart borders (5,600 vertices for 2,400 places):
    # welded, the part is one connected surface, so the cube projection packs a few big islands
    # instead of one per chart, and the decimate collapses cleanly (loop UVs stay per corner)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
    odd = []
    for v in bm.verts:
        src = (v.co.x, v.co.y, v.co.z)
        v.co = mapping(*src)
        if os.environ.get('SWORD_DEBUG') and region in ('guard', 'pommel') and -v.co.y > GUARD1 and -v.co.y < GRIP1:
            odd.append((round(src[0], 3), round(src[1], 3), round(src[2], 3), round(-v.co.y, 3)))
    if odd:
        print('SWORD', region, len(odd), 'vertices land in the grip zone; model (x, y, z) -> d:', sorted(odd, key=lambda t: t[3])[:8], '...', sorted(odd, key=lambda t: t[3])[-4:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > target:
        # delimit UV: never collapse an edge across a UV island's border (a collapse that did
        # left white triangles sampling the atlas's padding, lab 19:48)
        apply_modifier(bpy, new, 'DECIMATE', decimate_type='COLLAPSE', ratio=target / tris,
                       use_collapse_triangulate=True, delimit={'UV'})
    for p in me.polygons:
        p.use_smooth = True
    return new


def _rebake(k, objs, src_path, size=1024):
    """One clean atlas for the four textured parts. Meshy's UVs are a soup of tiny charts (the
    blade: 1,236 islands for 3,300 faces); in Roblox their mipmaps blend neighbouring charts
    and the dark core came out in pale wedges (lab 20:05). So each part gets fresh UVs (a smart
    projection: few large islands) packed into its own rectangle of a new `size` atlas, and the
    Meshy colour is baked into it (Cycles, colour only; baked at 1024 and reduced to `size`, so
    the 512 keeps its lines). The old UV layer is dropped. Returns the atlas image."""
    import numpy as np
    bpy = k.bpy
    rects = {'Blade': (0.0, 0.0, 0.5, 1.0), 'Flames': (0.5, 0.5, 0.5, 0.5), 'Guard': (0.5, 0.0, 0.25, 0.5), 'Pommel': (0.75, 0.0, 0.25, 0.5)}
    src = bpy.data.images.load(src_path)
    bake_px = max(size, 1024)
    target = bpy.data.images.new('SwordAtlas', bake_px, bake_px, alpha=False)
    target.pixels.foreach_set(np.tile(np.array([0.1, 0.06, 0.16, 1.0], np.float32), bake_px * bake_px))
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 4
    sc.cycles.device = 'CPU'
    bake = sc.render.bake
    bake.use_pass_direct = False
    bake.use_pass_indirect = False
    bake.use_pass_color = True
    bake.margin = 6
    bake.use_clear = False
    bake.use_selected_to_active = False
    for ob in objs:
        me = ob.data
        orig = me.uv_layers.active.name
        new = me.uv_layers.new(name='Baked')
        me.uv_layers.active = new
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        # a cube projection (one island per run of faces facing the same axis: the flat blade
        # is two big islands) packed without overlap; a smart projection on Meshy's bumpy
        # triangulation made thousands of specks instead
        bpy.ops.uv.cube_project(cube_size=1.0, correct_aspect=True, clip_to_bounds=False, scale_to_bounds=False)
        bpy.ops.uv.pack_islands(rotate=True, margin=0.012)
        bpy.ops.object.mode_set(mode='OBJECT')
        x0, y0, w, h = rects[ob.name]
        for l in me.uv_layers['Baked'].data:
            l.uv = (x0 + l.uv[0] * w, y0 + l.uv[1] * h)
        mat = bpy.data.materials.new('bake_' + ob.name)
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
        uvn = nt.nodes.new('ShaderNodeUVMap')
        uvn.uv_map = orig
        srcn = nt.nodes.new('ShaderNodeTexImage')
        srcn.image = src
        nt.links.new(uvn.outputs['UV'], srcn.inputs['Vector'])
        nt.links.new(srcn.outputs['Color'], bsdf.inputs['Base Color'])
        tgt = nt.nodes.new('ShaderNodeTexImage')
        tgt.image = target
        nt.nodes.active = tgt
        me.materials.clear()
        me.materials.append(mat)
        me.uv_layers['Baked'].active_render = True
        me.uv_layers.active = me.uv_layers['Baked']
        bpy.ops.object.bake(type='DIFFUSE')
        me.uv_layers.remove(me.uv_layers[orig])
    if bake_px != size:
        target.scale(size, size)
    return target


@piece
def halloween_sword(k):
    """The Halloween Sword body (see the module docstring)."""
    import bmesh
    import numpy as np
    from mathutils import Vector
    R = envelope()
    ob, src = _import(k)
    meshy = k.bpy.data.images.load(_meshy_colour(src))
    w, h = meshy.size
    px = np.array(meshy.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3]
    classes = _face_classes(ob, px)
    k.material('Wrap', 'SmoothPlastic', '#FFFFFF', Reflectance=0.02, SurfaceAppearance={'ColorMap': wrap_map(k.bpy)})

    k.joint('Body', pivot=(0, -3.5, 0))
    # the flame edges clear for the aiming owner; a slow shimmer: they hinge a hair about the axis
    k.joint('Flames', pivot=(0, -1.9, 0), parent='Body', aim='fade',
            motion=[{'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 1.2, 'Period': 1.6}])

    thick = 0.037 * BLADE_S     # the Meshy blade's half thickness on the cue, before flattening

    def blade(x, y, z):
        d = min((M_TIP - z) * BLADE_S, GUARD1 - 0.01)
        pinch = 0.5 + 0.5 * _smooth(0.3, 0.75, d)              # the tip rule: 0.12 across for 0.3
        flat = min(1.0, (R(min(d, 7.0)) + 0.012) / thick)      # no thicker than the cue in the hand
        zz = y * BLADE_S * flat * pinch
        # The root flares under the guard (|y| 0.07 in the model, 0.25 at this scale): its
        # underside is held to the downward clearance (envelope + 0.08, SIDE_EXTRA), hidden
        # under the pumpkin; the ridge on +Z keeps its height (UP_EXTRA 0.25 there).
        zz = max(zz, -(R(min(d, 7.0)) + 0.07))
        return Vector((x * BLADE_S * pinch, -d, zz))

    def guard(x, y, z):
        d = min(GUARD0 + (M_GUARD0 - z) / (M_GUARD0 - M_GUARD1) * (GUARD1 - GUARD0), GUARD1 - 0.01)
        return Vector((x * GUARD_X, -d, y * GUARD_Z + GUARD_LIFT))

    def pommel(x, y, z):
        d = max(GRIP1 + (M_GRIP1 - z) * POMMEL_S, GRIP1 + 0.01)
        return Vector((x * POMMEL_S, -d, y * POMMEL_S))

    parts = [
        ('Body', _region_object(k, ob, classes, 'blade', 'Blade', blade, 3300)),
        ('Flames', _region_object(k, ob, classes, 'flame', 'Flames', blade, 2600)),
        ('Body', _region_object(k, ob, classes, 'guard', 'Guard', guard, 2000)),
        ('Body', _region_object(k, ob, classes, 'pommel', 'Pommel', pommel, 500)),
    ]
    k.bpy.data.objects.remove(ob)
    atlas = _rebake(k, [o for _, o in parts], _meshy_colour(src), ATLAS_PX)
    colour, emissive, _ = _maps(k, atlas)
    sa = {'ColorMap': colour, 'EmissiveMask': emissive}
    k.material('Steel', 'SmoothPlastic', '#FFFFFF', Reflectance=0.05,
               SurfaceAppearance=dict(sa, EmissiveTint=SWORD['Orchid'], EmissiveStrength=0.5))
    k.material('Flame', 'SmoothPlastic', '#FFFFFF', Transparency=0.12,
               SurfaceAppearance=dict(sa, EmissiveTint=SWORD['Lavender'], EmissiveStrength=1.1))
    k.material('Guard', 'SmoothPlastic', '#FFFFFF', Reflectance=0.04,
               SurfaceAppearance=dict(sa, EmissiveTint=SWORD['Orchid'], EmissiveStrength=0.9))
    k.material('Pommel', 'SmoothPlastic', '#FFFFFF', Reflectance=0.06,
               SurfaceAppearance=dict(sa, EmissiveTint=SWORD['Orchid'], EmissiveStrength=1.0))
    for (joint, o), mat in zip(parts, ('Steel', 'Flame', 'Guard', 'Pommel')):
        o.data.materials.clear()
        o.data.materials.append(k.blender_mat(mat))
        for p in o.data.polygons:
            p.material_index = 0
        k.add(joint, o)

    # the grip: a lathe at the envelope through the grip hand, closed at both ends
    rows = [(GRIP0, 0.0)] + [(d, R(d)) for d in [GRIP0 + i * 0.1 for i in range(int((GRIP1 - GRIP0) / 0.1) + 1)]] + [(GRIP1, R(GRIP1)), (GRIP1, 0.0)]
    bm = bmesh.new()
    _revolve(bm, rows, 18, uv=lambda d, share: (share * 2.0, (d - GRIP0) / 0.6))
    _finish(bm)
    k.add('Body', k.mesh_object('Grip', bm, ['Wrap']))
    check_body(k)



def _ghost_whole(k, ob, target):
    """Meshy's ghost comes as a triangle soup (every texture chart its own vertices): the kit's
    collapse decimate of it tears holes, and at 900 triangles the three pocket ghosts read as
    shattered glass in the lobby lab (20:3x). Weld the duplicate vertices first, then collapse
    to `target` on the closed surface (the loops keep their UVs; a face merged across two
    charts samples a smear of the pale ghost map, which the finisher's tint and outline hide)."""
    import bmesh
    bpy = k.bpy
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(ob.data)
    bm.free()
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > target:
        apply_modifier(bpy, ob, 'DECIMATE', decimate_type='COLLAPSE', ratio=target / tris,
                       use_collapse_triangulate=True)
    for poly in ob.data.polygons:
        poly.use_smooth = True

@piece
def halloween_sword_pocket(k):
    """The win effect's small cute ghosts (C8's WIN EFFECT panel): three little ghosts, the
    Ghost Lantern's Meshy ghost at 0.7 studs tinted lavender, swirling up out of the pocket on
    a helix (three turns over 3 studs, a lap in 2.6 s) and bobbing."""
    import numpy as np
    from mathutils import Matrix, Vector
    k.frame = 'pocket'
    k.upright = True
    nF = 150
    frames = []

    def at(s):
        a = 2 * math.pi * 3 * s
        r = 0.4 + 0.35 * s
        return np.array([r * math.sin(a), r * math.cos(a), 3.0 * s])
    for j in range(nF):
        s = j / nF
        p = at(s)
        tang = at((j + 1) / nF) - p
        tang /= np.linalg.norm(tang)
        nrm = np.array([0.0, 0.0, 1.0])
        nrm -= tang * float(nrm @ tang)
        nrm /= np.linalg.norm(nrm)
        side = np.cross(tang, nrm)
        M = np.eye(4)
        M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = side, tang, nrm, p
        frames.append(M)
    seg = [float(np.linalg.norm(frames[(j + 1) % nF][:3, 3] - frames[j][:3, 3])) for j in range(nF - 1)]
    step = sum(seg) / (nF - 1)
    L = step * nF
    k.path('Swirl', frames, step)
    speed = L / 2.6
    for i, share in enumerate((0.0, 0.09, 0.18)):
        name = 'Ghost%d' % (i + 1)
        rest = share * L
        F = frames[int(round(rest / step)) % nF]
        side, tang, nrm, pt = (Vector(F[:3, c]) for c in range(4))
        k.joint(name, pivot=tuple(pt), low=None if i == 0 else 'hide',   # Lower effects keeps one ghost
                motion=[{'Kind': 'Path', 'Path': 'Swirl', 'Rest': rest, 'Speed': speed},
                        {'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.05, 'Period': 0.6 + 0.1 * i, 'Phase': 120 * i}])
        basis = Matrix(((side.x, tang.x, nrm.x, pt.x), (side.y, tang.y, nrm.y, pt.y),
                        (side.z, tang.z, nrm.z, pt.z), (0, 0, 0, 1)))
        ob = k.model(name, name, 'ghost', _ghost_place(0.7, basis), target_tris=10 ** 8, texture_px=256,
                     emissive=_ghost_glow, emissive_tint='#D9C2FF', emissive_strength=0.7)
        _ghost_whole(k, ob, 900)
