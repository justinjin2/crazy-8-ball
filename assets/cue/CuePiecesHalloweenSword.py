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
BLADE_END = 5.03          # the blade meets the guard here (one scale for the whole blade)
BLADE_X, BLADE_Z = 0.86, 0.86   # the core's width and thickness kept at v4's (the length grew 16%: designer 20:5x)
GUARD0, GUARD1 = 4.97, 5.55   # the guard just in front of the hand at rest (designer 20:5x: the hilt short and slim)
GUARD_X, GUARD_Z = 2.6, 1.6   # the guard's own scales: wide like the art, flattened in Z
GUARD_LIFT = 0.055          # the pumpkin and wings lifted so their underside stays within envelope + 0.08 at 4.2-4.3
GRIP0, GRIP1 = 5.57, 6.85     # only as long as the hand at rest needs (its box 5.57-6.81 measured)
GRIP_R = 0.115                # a sword handle, slimmer than the cue envelope (about 0.18 here)
POMMEL1 = 7.29            # the crystal's point: 0.29 past the butt (plain limit 0.3)
POMMEL_S = (POMMEL1 - GRIP1) / (M_GRIP1 - M_END)
BLADE_S = BLADE_END / (M_TIP - M_GUARD0)
ATLAS_PX = 512            # the baked atlas: 512 read the same as 1024 up close in the lab (20:08), so phones get 512
# The clean silhouette (v5, designer 20:5x: the flame border is VFX, not the model). The Meshy
# blade's tongues thin gradually (no fin plateau to split on), sweep toward the point with a
# notch under each, and differ side to side, so a split or a per-length scaling leaves
# scallops (lab 21:3x-21:5x). Instead every vertex is pressed onto a designed core profile that
# sits inside the deepest valley: a straight taper from CORE_ROOT_W under the guard to
# CORE_MID_W at CORE_MID_D, then the model's own point (the tip rule's pinch). Studs on the cue.
CORE_ROOT_W = 0.42
CORE_MID_W = 0.32
CORE_MID_D = 1.2
# The paint: the source texture's flame tongues are painted over before the bake, by where a
# texel sits between the spine (0) and the core's rim (1): inside PAINT_CORE_R the Meshy paint
# stays (the dark core with its ridge glow), beyond it a dark mottled steel, and from
# PAINT_BEVEL_R a thin lavender bevel that the emissive mask picks up.
PAINT_CORE_R = 0.5
PAINT_BEVEL_R = 0.9
A.BODY_EXCEPTIONS['halloween_sword'] = {'WideX': 5.55, 'BridgeCore': ('Body',), 'GuardInGripZone': (4.4, 5.55),
                                        'SlimGrip': GRIP_R}


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


def _core_w(d):
    """The core's half-width at `d` studs from the tip (see CORE_ROOT_W)."""
    if d >= CORE_MID_D:
        return CORE_MID_W + (CORE_ROOT_W - CORE_MID_W) * min(1.0, (d - CORE_MID_D) / (BLADE_END - CORE_MID_D))
    return CORE_MID_W * (d / CORE_MID_D) ** 0.8


def _blade_xd(x, z):
    """A model blade vertex's x on the cue before the press (the tip rule's pinch in) and its d."""
    d = min((M_TIP - z) * BLADE_S, GUARD1 - 0.01)
    pinch = 0.5 + 0.5 * _smooth(0.3, 0.75, d)              # the tip rule: 0.12 across for 0.3
    return x * BLADE_S * BLADE_X * pinch, d, pinch


def _face_classes(ob):
    """Per face: its region ('blade', 'guard', 'grip', 'pommel') from where it sits along the
    model (v5: the whole flame-edged blade is 'blade'; its outline is pressed onto the core
    profile in blade() and its tongue paint covered by _paint_core)."""
    import numpy as np
    me = ob.data
    V = np.array([v.co[:] for v in me.vertices])
    out = []
    for p in me.polygons:
        c = V[list(p.vertices)].mean(axis=0)
        if c[2] > M_GUARD0:
            out.append('blade')
        elif c[2] > M_GUARD1:
            out.append('guard')
        elif c[2] > M_GRIP1:
            out.append('grip')
        else:
            out.append('pommel')
    return out


def _paint_core(k, ob, classes, src_path):
    """The source colour with the blade's flame paint covered (see PAINT_CORE_R): each blade
    face is rasterised in the source UV space with its corners' rim fraction r = |x| / core(d)
    (the pressed rim is 1) interpolated, and a texel past PAINT_CORE_R is repainted dark steel,
    past PAINT_BEVEL_R the lavender bevel. Written as a temporary file; returns its path."""
    import tempfile
    import numpy as np
    bpy = k.bpy
    img = bpy.data.images.load(src_path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = px[..., :3]
    black = np.array(_hex(SWORD['Black']), np.float32)
    lav = np.array(_hex(SWORD['Lavender']), np.float32)
    me = ob.data
    uvl = me.uv_layers.active.data
    V = np.array([v.co[:] for v in me.vertices])
    painted = 0
    for p in me.polygons:
        if classes[p.index] != 'blade':
            continue
        vs = [V[i] for i in p.vertices]
        r = []
        for v in vs:
            xx0, d, _ = _blade_xd(v[0], v[2])
            r.append(min(1.2, abs(xx0) / max(_core_w(d), 1e-4)))
        r = np.array(r)
        if r.max() < PAINT_CORE_R - 0.08:
            continue
        uv = np.array([uvl[l].uv[:] for l in p.loop_indices]) * (w, h)
        x0, y0 = np.floor(uv.min(axis=0) - 1).astype(int)
        x1, y1 = np.ceil(uv.max(axis=0) + 1).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, w - 1), min(y1, h - 1)
        if x1 <= x0 or y1 <= y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, ay), (bx, by), (cx, cy) = uv
        det = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if abs(det) < 1e-6:
            continue
        l1 = ((bx - xs) * (cy - ys) - (cx - xs) * (by - ys)) / det
        l2 = ((cx - xs) * (ay - ys) - (ax - xs) * (cy - ys)) / det
        l3 = 1.0 - l1 - l2
        slack = 1.5 / max(1.0, math.sqrt(abs(det)))  # about a pixel and a half past each edge
        inside = (l1 >= -slack) & (l2 >= -slack) & (l3 >= -slack)
        if not inside.any():
            continue
        rr = np.clip(l1 * r[0] + l2 * r[1] + l3 * r[2], 0.0, 1.2)
        sub = rgb[y0:y1 + 1, x0:x1 + 1]
        lum = sub.mean(axis=-1, keepdims=True)
        dark = black * (0.75 + 0.5 * np.minimum(lum, 0.5))
        t_core = np.clip((rr - (PAINT_CORE_R - 0.08)) / 0.08, 0.0, 1.0)[..., None]
        t_bev = np.clip((rr - PAINT_BEVEL_R) / (1.0 - PAINT_BEVEL_R), 0.0, 1.0)[..., None]
        new = sub * (1 - t_core) + dark * t_core
        new = new * (1 - t_bev) + lav * t_bev
        sub[inside] = new[inside]
        painted += 1
    img.pixels.foreach_set(px.ravel())
    out = os.path.join(tempfile.gettempdir(), '%s_core_paint.png' % k.pid)
    img.filepath_raw = out
    img.file_format = 'PNG'
    img.save()
    print('SWORD paint: %d blade faces repainted -> %s' % (painted, out))
    return out


def _hex(s):
    s = s.lstrip('#')
    return tuple(int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


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
    rects = {'Blade': (0.0, 0.0, 0.5, 1.0), 'Guard': (0.5, 0.0, 0.5, 0.5), 'Pommel': (0.5, 0.5, 0.25, 0.5)}
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


def _recentre_z(ob, step=0.1):
    """The blade's core centred up and down in every 0.1-stud band (the hand rule's 0.02): the
    Meshy blade's faces are not quite symmetric in thickness, and with the bevel widened the
    core's z-centre drifted 0.022 at 2.0 studs (v5). Each band's vertices shift by its own
    mid-thickness, at most a few hundredths."""
    from collections import defaultdict
    bands = defaultdict(list)
    for v in ob.data.vertices:
        bands[int(-v.co.y / step)].append(v)
    for vs in bands.values():
        zs = [v.co.z for v in vs]
        mid = (max(zs) + min(zs)) / 2
        for v in vs:
            v.co.z -= mid


@piece
def halloween_sword(k):
    """The Halloween Sword body (see the module docstring)."""
    import bmesh
    import numpy as np
    from mathutils import Vector
    R = envelope()
    ob, src = _import(k)
    classes = _face_classes(ob)
    painted = _paint_core(k, ob, classes, _meshy_colour(src))
    k.material('Wrap', 'SmoothPlastic', '#FFFFFF', Reflectance=0.02, SurfaceAppearance={'ColorMap': wrap_map(k.bpy)})

    k.joint('Body', pivot=(0, -3.5, 0))
    # the flame edges clear for the aiming owner; a slow shimmer: they hinge a hair about the axis
    thick = 0.037 * BLADE_S     # the Meshy blade's half thickness on the cue, before flattening

    def blade(x, y, z):
        xx0, d, pinch = _blade_xd(x, z)
        flat = min(1.0, (R(min(d, 7.0)) + 0.012) / thick)      # no thicker than the cue in the hand
        zz = y * BLADE_S * BLADE_Z * flat * pinch
        # The root flares under the guard (|y| 0.07 in the model, 0.25 at this scale): its
        # underside is held to the downward clearance (envelope + 0.08, SIDE_EXTRA), hidden
        # under the pumpkin; the ridge on +Z keeps its height (UP_EXTRA 0.25 there).
        zz = max(zz, -(R(min(d, 7.0)) + 0.07))
        w = _core_w(d)
        xx = math.copysign(min(abs(xx0), w), xx0)              # pressed onto the core profile
        return Vector((xx, -d, zz))

    def guard(x, y, z):
        d = min(GUARD0 + (M_GUARD0 - z) / (M_GUARD0 - M_GUARD1) * (GUARD1 - GUARD0), GUARD1 - 0.01)
        return Vector((x * GUARD_X, -d, y * GUARD_Z + GUARD_LIFT))

    def pommel(x, y, z):
        d = max(GRIP1 + (M_GRIP1 - z) * POMMEL_S, GRIP1 + 0.01)
        return Vector((x * POMMEL_S, -d, y * POMMEL_S))

    parts = [
        ('Body', _region_object(k, ob, classes, 'blade', 'Blade', blade, 3300)),
        ('Body', _region_object(k, ob, classes, 'guard', 'Guard', guard, 2000)),
        ('Body', _region_object(k, ob, classes, 'pommel', 'Pommel', pommel, 500)),
    ]
    k.bpy.data.objects.remove(ob)
    _recentre_z(parts[0][1])
    atlas = _rebake(k, [o for _, o in parts], painted, ATLAS_PX)
    colour, emissive, _ = _maps(k, atlas)
    sa = {'ColorMap': colour, 'EmissiveMask': emissive}
    k.material('Steel', 'SmoothPlastic', '#FFFFFF', Reflectance=0.05,
               SurfaceAppearance=dict(sa, EmissiveTint=SWORD['Orchid'], EmissiveStrength=0.5))
    k.material('Guard', 'SmoothPlastic', '#FFFFFF', Reflectance=0.04,
               SurfaceAppearance=dict(sa, EmissiveTint=SWORD['Orchid'], EmissiveStrength=0.9))
    k.material('Pommel', 'SmoothPlastic', '#FFFFFF', Reflectance=0.06,
               SurfaceAppearance=dict(sa, EmissiveTint=SWORD['Orchid'], EmissiveStrength=1.0))
    for (joint, o), mat in zip(parts, ('Steel', 'Guard', 'Pommel')):
        o.data.materials.clear()
        o.data.materials.append(k.blender_mat(mat))
        for p in o.data.polygons:
            p.material_index = 0
        k.add(joint, o)

    # the grip: a lathe at the envelope through the grip hand, closed at both ends
    rows = [(GRIP0, 0.0), (GRIP0, GRIP_R), (GRIP1, GRIP_R), (GRIP1, 0.0)]
    bm = bmesh.new()
    _revolve(bm, rows, 18, uv=lambda d, share: (share * 2.0, (d - GRIP0) / 0.4))
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
