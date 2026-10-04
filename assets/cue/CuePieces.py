"""Custom 3D pieces: scripted modelling of the moving 3D piece a cue carries (the dragon head,
the fox mask and tails, the claw arm, the eclipse, the phoenix wings), built in headless Blender.

    Blender -b --factory-startup --python-exit-code 1 --python assets/cue/CuePieces.py -- <id>

writes assets/cue/pieces/<id>/:
  <Joint>_<Material>.obj   one mesh per moving joint and per material (a Roblox MeshPart each)
  piece.json               every part: its file, Roblox Material, Color, Transparency,
                           Reflectance, its joint; every joint: its parent, pivot and motion
  preview.png              a quick look at the piece on the cue's butt

The Roblox side is mechanical:
  * Each OBJ is a MeshPart (Roblox recentres a mesh on its bounding box: the part's Offset in
    piece.json is where that centre sits, in the cue's own frame: X = -Side, Y = Up,
    Z = 3.5 - AtStuds, the cue MeshPart's frame).
  * Material, Color, Transparency, Reflectance are plain MeshPart properties (Neon glows,
    ForceField is the see-through energy look); no SurfaceAppearance needed.
  * A joint is a set of parts moving together: a LocalScript sets every part's CFrame each frame
    to cue.CFrame * jointCFrame(t) * restOffset, where jointCFrame(t) is the joint's parent
    chain of motions (see `joint_matrix`): Hinge (a sine swing about an axis through the
    pivot), Spin (a steady turn), Bob (a sine slide), Sway (a swing that travels down a chain
    of joints, for tails), Path (riding a looping path stored in piece.json's Paths, for a
    creature that swims along a track, see `path_frame`). The preview plays the same maths.

Modelling is by script only (no AI generators here): bmesh solids and sweeps, and metaball
sculpts turned to meshes for organic heads, then bevelled/smoothed; materials are assigned to
faces by region functions, so one sculpt can carry gold horns and pearl scales.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
PIECES_DIR = os.path.join(HERE, 'pieces')

# Roblox materials as the preview draws them (Blender Principled settings); Roblox's own look:
# Metal is a rough brushed metal, Foil a bright one, Neon glows its Color (and ignores light),
# Glass is clear and glossy, ForceField a see-through glowing shimmer.
ROBLOX_LOOK = {
    'SmoothPlastic': {'metal': 0.0, 'rough': 0.32},
    'Plastic': {'metal': 0.0, 'rough': 0.5},
    'Marble': {'metal': 0.0, 'rough': 0.22},
    'Metal': {'metal': 1.0, 'rough': 0.3},
    'Foil': {'metal': 1.0, 'rough': 0.14},
    'DiamondPlate': {'metal': 1.0, 'rough': 0.35},
    'Glass': {'metal': 0.0, 'rough': 0.05, 'glass': True},
    'Neon': {'neon': 2.4},
    'ForceField': {'neon': 1.3, 'field': True},
}

BUILDERS = {}

# The pieces were first modelled on a cue with a 0.2 stud butt (radius 0.1); the cue grew 1.6x
# with the tip kept (designer, 2026-10-01). Pieces that sit on the butt read the gain from
# Shape.json, so they follow Config.Cue.
OLD_BUTT_RADIUS = 0.1


def butt_radius():
    import cue_common as cc
    return cc.load_shape()[0]['butt_diameter_studs'] / 2


def butt_gain():
    """How much wider (studs, radius) the butt is than the one the pieces were modelled on."""
    return butt_radius() - OLD_BUTT_RADIUS


def butt_growth():
    """The butt's radius over the one the pieces were modelled on."""
    return butt_radius() / OLD_BUTT_RADIUS
ZOFF = {'cue': 3.5, 'pocket': 0.0}   # Roblox Z = ZOFF + Blender Y (the cue MeshPart's centre is 3.5 from the tip)


def piece(fn):
    BUILDERS[fn.__name__] = fn
    return fn


def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb_to_lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


# =============================================================================================
# Motion (pure maths, shared by the preview and described for the Roblox script)
# =============================================================================================

def _wave(t, m):
    period = float(m.get('Period', 2.0))
    ph = math.radians(float(m.get('Phase', 0.0)))
    x = 2 * math.pi * t / period + ph
    shape = m.get('Shape', 'sine')
    if shape == 'snap':  # quick close, slow open (a claw clicking): a sharpened sine
        s = math.sin(x)
        return math.copysign(abs(s) ** 0.35, s)
    if shape == 'pulse':  # rest most of the time, a quick swing once a period
        u = (x / (2 * math.pi)) % 1.0
        return math.sin(math.pi * min(u / 0.3, 1.0)) if u < 0.3 else 0.0
    return math.sin(x)


def _rot(axis, ang):
    import numpy as np
    a = np.asarray(axis, float)
    a = a / (np.linalg.norm(a) + 1e-12)
    x, y, z = a
    c, s = math.cos(ang), math.sin(ang)
    C = 1 - c
    R = np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                  [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                  [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])
    M = np.eye(4)
    M[:3, :3] = R
    return M


def path_frame(path, s):
    """A looping path's frame at arc length s (studs): a 4x4 whose columns are the side, the
    tangent (the way along the path), the normal (away from the cue) and the point, in the
    piece's Blender frame. The path is sampled every Step studs as [x, y, z, qw, qx, qy, qz];
    between samples the point is lerped and the turn slerped (the runtime: CFrame:Lerp)."""
    import numpy as np
    from mathutils import Quaternion
    F = path['Frames']
    n = len(F)
    u = (s / path['Step']) % n
    i = int(math.floor(u)) % n
    j = (i + 1) % n
    f = u - math.floor(u)
    a, b = F[i], F[j]
    q = Quaternion(a[3:7]).slerp(Quaternion(b[3:7]), f)
    M = np.eye(4)
    M[:3, :3] = np.array(q.to_matrix())
    M[:3, 3] = [a[k] + (b[k] - a[k]) * f for k in range(3)]
    return M


def motion_matrix(motions, t, pivot=(0, 0, 0)):
    """One joint's own motion at time t, about its pivot (a 4x4 in the cue's Blender frame,
    applied as T(pivot) @ M @ T(-pivot) by joint_matrix)."""
    import numpy as np
    M = np.eye(4)
    for m in motions or []:
        kind = m.get('Kind')
        if kind == 'Path':
            # ride a looping path (piece.json Paths): the joint sits on the path at arc length
            # Rest at rest and travels along it at Speed studs a second, turning with it:
            # X = F(Rest + Speed t) F(Rest)^-1, about the pivot (the path's point at Rest)
            path = m['_Path']
            X = path_frame(path, m['Rest'] + m['Speed'] * t) @ np.linalg.inv(path_frame(path, m['Rest']))
            P = np.eye(4)
            P[:3, 3] = pivot
            Pi = np.eye(4)
            Pi[:3, 3] = -np.asarray(pivot, float)
            M = M @ Pi @ X @ P
            continue
        if kind == 'Hinge' or kind == 'Sway':
            ang = math.radians(float(m.get('Base', 0.0)) + float(m.get('Amp', 10.0)) * _wave(t, m))
            M = M @ _rot(m.get('Axis', (1, 0, 0)), ang)
        elif kind == 'Spin':
            M = M @ _rot(m.get('Axis', (0, 1, 0)), math.radians(float(m.get('Rate', 90.0)) * t + float(m.get('Phase', 0.0))))
        elif kind == 'Bob':
            d = np.asarray(m.get('Dir', (0, 0, 1)), float) * float(m.get('Amp', 0.02)) * _wave(t, m)
            T = np.eye(4)
            T[:3, 3] = d
            M = M @ T
    return M


def joint_matrix(joints, name, t):
    """A joint's full transform in the cue frame: its parent's, then its own motion about its
    pivot (pivots are in the cue frame at rest)."""
    import numpy as np
    j = joints[name]
    P = np.eye(4)
    P[:3, 3] = j.get('Pivot', (0, 0, 0))
    Pi = np.eye(4)
    Pi[:3, 3] = -np.asarray(j.get('Pivot', (0, 0, 0)), float)
    own = P @ motion_matrix(j.get('Motion'), t, j.get('Pivot', (0, 0, 0))) @ Pi
    parent = j.get('Parent')
    return (joint_matrix(joints, parent, t) if parent else np.eye(4)) @ own


def link_paths(spec):
    """Point every Path motion in a loaded piece.json at its path (spec['Paths']), in memory."""
    for j in spec.get('Joints', {}).values():
        for m in j.get('Motion') or []:
            if m.get('Kind') == 'Path':
                m['_Path'] = spec['Paths'][m['Path']]
    return spec


# =============================================================================================
# The modelling kit (inside Blender)
# =============================================================================================

class Kit:
    """Holds the joints and materials of one piece while it is modelled."""

    def __init__(self, bpy, pid):
        self.bpy = bpy
        self.pid = pid
        self.joints = {}   # name -> {'Parent', 'Pivot', 'Motion', 'objects': [...]}
        self.mats = {}     # name -> roblox spec
        # 'cue': modelled in the cue's frame (a piece on the cue); 'pocket': in a frame of its own
        # with the origin at the pocket's mouth, Z up, the front toward -Y (a pocket finisher's
        # creature, placed and turned by the finisher)
        self.frame = 'cue'
        # skinned models: name -> {'root': joint, 'bones': {bone: weight fn}, 'meshes': [objects]}
        self.skins = {}
        # looping paths a joint can ride (Path motions): name -> {'Step', 'Loop', 'Frames'}
        self.paths = {}

    # ---- materials ----------------------------------------------------------------------------
    def material(self, name, Material='SmoothPlastic', Color='#FFFFFF', Transparency=0.0, Reflectance=0.0,
                 SurfaceAppearance=None):
        self.mats[name] = {'Material': Material, 'Color': Color, 'Transparency': Transparency, 'Reflectance': Reflectance}
        if SurfaceAppearance:
            self.mats[name]['SurfaceAppearance'] = SurfaceAppearance
        return name

    def model(self, joint, name, model, place, target_tris=14000, emissive=None, emissive_tint='#FFFFFF',
              emissive_strength=1.0, texture_px=1024, cut_below=None, bones=None, hologram=None):
        """A generated model (assets/cue/models/<model>/, tools/meshy_generate.py) as one textured
        part on `joint`: imported, placed by place(obs) -> 4x4 Matrix (the caller measures the model
        and returns where it goes in the cue frame), reduced to target_tris (a collapse decimate,
        which keeps the UVs so its own maps still fit), its maps copied into pieces/<pid>/ at
        texture_px (Roblox's SurfaceAppearance limit is 1024) and worn as a SurfaceAppearance.
        emissive(rgb float array HxWx3) -> mask HxW in 0..1 makes the EmissiveMask from the colour
        map (the eyes, a gem). cut_below (0..1) removes everything below that fraction of the
        model's own height and closes the hole (a bust's collar and lower neck).

        bones (designer, 2026-09-30: the creatures rigged and animated, not static models): an
        ordered {bone: weight(V) -> 0..1} of bones already declared with joint() (parent first,
        each under `joint` or another listed bone). The model becomes one skinned mesh: `joint` is
        the root bone and each bone takes weight(V) of its parent's share of every vertex (V the
        vertex positions, n x 3, in the piece's frame), so the mesh bends smoothly; the bones move
        by their joints' motions (Hinge, Spin, Bob, Sway) exactly as rigid joints do. It is exported
        as a skinned GLB (see export_skin).

        hologram (designer, 2026-09-30: spiritual energy, holograms, not solid models): {'Tint',
        'Strength', 'Shell', 'ShellOffset', 'ShellTris', 'Alpha'}. The SurfaceAppearance becomes a
        see-through glowing spirit of the model's own texture (ColorMap in the tint, its alpha from
        the brightness, AlphaMode Transparency, glowing all over, the emissive() parts brightest),
        and a ForceField shell (the same mesh pushed out by ShellOffset of its height, reduced to
        ShellTris) gives the shimmering hologram rim. Returns the object."""
        import numpy as np
        bpy = self.bpy
        src = os.path.join(HERE, 'models', model)
        # the full download if it is here, else the committed copy (CueModels.compact)
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
        ob.name = name
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        if cut_below is not None:
            import bmesh
            tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
            if tris > target_tris * 4:
                apply_modifier(bpy, ob, 'DECIMATE', decimate_type='COLLAPSE', ratio=target_tris * 4 / tris,
                               use_collapse_triangulate=True)
            zs = [v.co.z for v in ob.data.vertices]
            z_cut = min(zs) + cut_below * (max(zs) - min(zs))
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5,
                                         plane_co=(0, 0, z_cut), plane_no=(0, 0, 1), clear_inner=True)
            cut_edges = [e for e in res['geom_cut'] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
            bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
            bm.to_mesh(ob.data)
            bm.free()
        ob.matrix_world = place(ob) @ ob.matrix_world
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        if tris > target_tris:
            apply_modifier(bpy, ob, 'DECIMATE', decimate_type='COLLAPSE', ratio=target_tris / tris,
                           use_collapse_triangulate=True)
        out = os.path.join(PIECES_DIR, self.pid)
        os.makedirs(out, exist_ok=True)
        sa = {}
        for key, fname in (('ColorMap', 'base_color'), ('NormalMap', 'normal'), ('RoughnessMap', 'roughness'),
                           ('MetalnessMap', 'metallic')):
            path = os.path.join(src, fname + '.png')
            if not os.path.isfile(path):
                path = os.path.join(src, 'maps', fname + '.png')
            if not os.path.isfile(path):
                continue
            img = bpy.data.images.load(path)
            if img.size[0] > texture_px:
                img.scale(texture_px, texture_px)
            rel = 'pieces/%s/%s_%s.png' % (self.pid, name, fname)
            img.filepath_raw = os.path.join(HERE, rel)
            img.file_format = 'PNG'
            img.save()
            sa[key] = rel
            if key == 'ColorMap' and emissive is not None:
                w, h = img.size
                px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3]
                mask = np.clip(emissive(px), 0, 1)
                em = bpy.data.images.new(name + '_emissive', w, h, alpha=False)
                em.pixels.foreach_set(np.concatenate([np.repeat(mask[..., None], 3, -1),
                                                      np.ones((h, w, 1), np.float32)], -1).ravel())
                rel_e = 'pieces/%s/%s_emissive.png' % (self.pid, name)
                em.filepath_raw = os.path.join(HERE, rel_e)
                em.file_format = 'PNG'
                em.save()
                sa.update({'EmissiveMask': rel_e, 'EmissiveTint': emissive_tint, 'EmissiveStrength': emissive_strength})
        if hologram:
            sa = self._spirit_maps(name, sa, emissive, hologram, ob)
        self.material(name, 'SmoothPlastic', '#FFFFFF', SurfaceAppearance=sa)
        ob.data.materials.clear()
        ob.data.materials.append(self.blender_mat(name))
        for poly in ob.data.polygons:
            poly.material_index = 0
        self.add(joint, ob)
        meshes = [ob]
        if hologram:
            meshes.append(self._shell(ob, joint, name, hologram))
        if bones:
            self.skins[name] = {'root': joint, 'bones': bones, 'meshes': meshes}
        return ob

    def _spirit_maps(self, name, sa, emissive, holo, ob):
        """The hologram's SurfaceAppearance: the colour map redrawn as glowing see-through energy in
        the tint (bright details more solid, dark ones faint, never white-out), thin level scanlines
        cut through it (baked from each texel's height on the model, so they run level across the
        whole creature, as a hologram's do), an emissive mask glowing all over with the emissive()
        parts (eyes) brightest; the normal map kept for the surface detail."""
        import numpy as np
        bpy = self.bpy
        img = bpy.data.images.load(os.path.join(HERE, sa['ColorMap']), check_existing=False)
        w, h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3]
        luma = np.clip(px[..., 0] * 0.3 + px[..., 1] * 0.59 + px[..., 2] * 0.11, 0, 1)
        tint = np.array(srgb_to_lin(hexrgb(holo['Tint'])), np.float32)
        lo, hi = holo.get('Alpha', (0.04, 0.32))
        col = tint[None, None, :] * (0.25 + 0.6 * luma[..., None]) + (luma[..., None] ** 3) * 0.12
        eyes = np.clip(emissive(px), 0, 1) if emissive is not None else np.zeros_like(luma)
        col = col + eyes[..., None] * 0.6
        alpha = np.clip(lo + (hi - lo) * luma ** 1.1 + 0.4 * eyes, 0, 0.95)
        zmap = texel_heights(ob, w, h)
        ok = np.isfinite(zmap)
        zs = [v.co.z for v in ob.data.vertices]
        step = (max(zs) - min(zs)) / float(holo.get('Lines', 48))
        band = (0.5 + 0.5 * np.cos(2 * np.pi * np.where(ok, zmap, 0) / step)) ** 6
        lines = np.where(ok, band, 0.0)
        alpha = np.clip(alpha * (0.6 + 0.4 * (1 - lines)) + 0.35 * lines, 0, 0.95)
        col = np.clip(col + lines[..., None] * tint[None, None, :] * 0.5, 0, 1)
        out = bpy.data.images.new(name + '_spirit', w, h, alpha=True)
        out.pixels.foreach_set(np.concatenate([np.clip(col, 0, 1), alpha[..., None]], -1).astype(np.float32).ravel())
        rel = 'pieces/%s/%s_spirit.png' % (self.pid, name)
        out.filepath_raw = os.path.join(HERE, rel)
        out.file_format = 'PNG'
        out.save()
        mask = np.clip(0.22 + 0.4 * luma + 0.3 * lines + eyes, 0, 1)
        em = bpy.data.images.new(name + '_spirit_emissive', w, h, alpha=False)
        em.pixels.foreach_set(np.concatenate([np.repeat(mask[..., None], 3, -1), np.ones((h, w, 1), np.float32)],
                                             -1).astype(np.float32).ravel())
        rel_e = 'pieces/%s/%s_emissive.png' % (self.pid, name)
        em.filepath_raw = os.path.join(HERE, rel_e)
        em.file_format = 'PNG'
        em.save()
        for key in ('RoughnessMap', 'MetalnessMap'):
            p = sa.pop(key, None)
            if p and os.path.isfile(os.path.join(HERE, p)):
                os.remove(os.path.join(HERE, p))
        old = os.path.join(HERE, sa['ColorMap'])
        if os.path.isfile(old):
            os.remove(old)
        sa.update({'ColorMap': rel, 'AlphaMode': 'Transparency', 'EmissiveMask': rel_e,
                   'EmissiveTint': holo['Tint'], 'EmissiveStrength': float(holo.get('Strength', 1.8))})
        return sa

    def _shell(self, ob, joint, name, holo):
        """The hologram's shimmering ForceField shell: a reduced copy pushed out along its normals."""
        bpy = self.bpy
        sh = ob.copy()
        sh.data = ob.data.copy()
        sh.name = name + 'Shell'
        bpy.context.scene.collection.objects.link(sh)
        tris = sum(len(p.vertices) - 2 for p in sh.data.polygons)
        target = int(holo.get('ShellTris', 8000))
        if tris > target:
            apply_modifier(bpy, sh, 'DECIMATE', decimate_type='COLLAPSE', ratio=target / tris,
                           use_collapse_triangulate=True)
        zs = [v.co.z for v in sh.data.vertices]
        ys = [v.co.y for v in sh.data.vertices]
        size = max(max(zs) - min(zs), max(ys) - min(ys))
        apply_modifier(bpy, sh, 'DISPLACE', strength=float(holo.get('ShellOffset', 0.012)) * size, mid_level=0.0)
        mname = name + 'Shell'
        self.material(mname, 'ForceField', holo.get('Shell', holo['Tint']))
        sh.data.materials.clear()
        sh.data.materials.append(self.blender_mat(mname))
        for poly in sh.data.polygons:
            poly.material_index = 0
        self.add(joint, sh)
        return sh

    def blender_mat(self, name):
        bpy = self.bpy
        key = 'PM_%s_%s' % (self.pid, name)
        if key in bpy.data.materials:
            return bpy.data.materials[key]
        return make_blender_material(bpy, key, self.mats[name])

    # ---- joints ---------------------------------------------------------------------------------
    def joint(self, name, pivot=(0, 0, 0), parent=None, motion=None, aura=False):
        """aura: this joint and everything on it (and its child joints) is part of the aura, hidden
        on the player's turn to shoot with the rest of the aura (designer, 2026-09-30), not a fixed
        part of the cue (the Celestial Dragon's coiling spirit, the Kitsune's running fox)."""
        self.joints[name] = {'Parent': parent, 'Pivot': list(pivot), 'Motion': motion or [], 'objects': [],
                             'Aura': aura}
        for m in motion or []:
            if m.get('Kind') == 'Path':
                m['_Path'] = self.paths[m['Path']]
        return name

    def path(self, name, frames, step):
        """A looping path for Path motions: frames are 4x4 matrices (columns side, tangent,
        normal, point) every `step` studs of arc length round the loop (the last joins the first)."""
        from mathutils import Matrix
        rows = []
        for M in frames:
            M = Matrix([list(r) for r in M])
            q = M.to_3x3().to_quaternion()
            if rows and sum(a * b for a, b in zip(rows[-1][3:7], q)) < 0:
                q = -q                     # keep neighbours in the same hemisphere for the slerp
            rows.append([round(float(x), 5) for x in (M[0][3], M[1][3], M[2][3], q.w, q.x, q.y, q.z)])
        self.paths[name] = {'Step': step, 'Loop': True, 'Frames': rows}
        return name

    def add(self, joint, ob):
        self.joints[joint]['objects'].append(ob)
        return ob

    def grow(self, about, s):
        """Scale everything built so far by s about the point `about` (cue frame): a sleeve over
        the butt kept in proportion when the butt grew. Only for pieces whose motions turn
        (Hinge, Spin): it scales pivots and meshes, not Bob or Path distances."""
        from mathutils import Matrix, Vector
        a = Vector(about)
        M = Matrix.Translation(a) @ Matrix.Scale(s, 4) @ Matrix.Translation(-a)
        for j in self.joints.values():
            assert all(m.get('Kind') in ('Hinge', 'Spin') for m in j['Motion']), 'grow: turning motions only'
            j['Pivot'] = list(a + (Vector(j['Pivot']) - a) * s)
            for ob in j['objects']:
                if ob.parent is None:
                    ob.matrix_world = M @ ob.matrix_world

    # ---- mesh from bmesh ------------------------------------------------------------------------
    def mesh_object(self, name, bm, mats, smooth=True):
        bpy = self.bpy
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        for m in mats:
            ob.data.materials.append(self.blender_mat(m))
        if smooth:
            for p in me.polygons:
                p.use_smooth = True
        return ob


def make_textured_material(bpy, key, sa):
    """A SurfaceAppearance as Blender draws it: ColorMap, NormalMap (OpenGL, as Roblox), RoughnessMap,
    MetalnessMap, and EmissiveMask x EmissiveTint x EmissiveStrength (paths from assets/cue)."""
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')

    def tex(path, colour=False):
        img = bpy.data.images.load(os.path.join(HERE, path), check_existing=True)
        if not colour:
            img.colorspace_settings.name = 'Non-Color'
        node = nt.nodes.new('ShaderNodeTexImage')
        node.image = img
        return node
    if sa.get('ColorMap'):
        cm = tex(sa['ColorMap'], True)
        nt.links.new(cm.outputs['Color'], bsdf.inputs['Base Color'])
        if sa.get('AlphaMode') == 'Transparency':
            # a hologram: the colour map's alpha is the surface's transparency
            nt.links.new(cm.outputs['Alpha'], bsdf.inputs['Alpha'])
            try:
                mat.surface_render_method = 'BLENDED'
            except Exception:
                mat.blend_method = 'BLEND'
            try:
                mat.use_transparency_overlap = True
            except Exception:
                pass
    if sa.get('RoughnessMap'):
        nt.links.new(tex(sa['RoughnessMap']).outputs['Color'], bsdf.inputs['Roughness'])
    else:
        bsdf.inputs['Roughness'].default_value = 0.5
    if sa.get('MetalnessMap'):
        nt.links.new(tex(sa['MetalnessMap']).outputs['Color'], bsdf.inputs['Metallic'])
    if sa.get('NormalMap'):
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nt.links.new(tex(sa['NormalMap']).outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    if sa.get('EmissiveMask'):
        mask = tex(sa['EmissiveMask'])
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        mix.inputs['Factor'].default_value = 1.0
        nt.links.new(mask.outputs['Color'], mix.inputs['A'])
        mix.inputs['B'].default_value = srgb_to_lin(hexrgb(sa.get('EmissiveTint', '#FFFFFF'))) + (1.0,)
        nt.links.new(mix.outputs['Result'], bsdf.inputs['Emission Color'])
        bsdf.inputs['Emission Strength'].default_value = float(sa.get('EmissiveStrength', 1.0))
    return mat


def make_blender_material(bpy, key, spec):
    if spec.get('SurfaceAppearance'):
        return make_textured_material(bpy, key, spec['SurfaceAppearance'])
    look = ROBLOX_LOOK.get(spec['Material'], ROBLOX_LOOK['SmoothPlastic'])
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    col = srgb_to_lin(hexrgb(spec['Color']))
    alpha = 1.0 - float(spec.get('Transparency', 0.0))
    bsdf.inputs['Base Color'].default_value = col + (1.0,)
    if 'neon' in look:
        bsdf.inputs['Base Color'].default_value = (0, 0, 0, 1)
        bsdf.inputs['Emission Color'].default_value = col + (1.0,)
        bsdf.inputs['Emission Strength'].default_value = look['neon']
        bsdf.inputs['Roughness'].default_value = 1.0
    else:
        bsdf.inputs['Metallic'].default_value = look['metal']
        rough = look['rough'] * (1 - 0.8 * float(spec.get('Reflectance', 0.0)))
        bsdf.inputs['Roughness'].default_value = rough
    if look.get('glass'):
        alpha = min(alpha, 0.35)
    if look.get('field'):
        # ForceField: brightest at the silhouette (a fresnel shimmer), clear face-on
        lw = nodes.new('ShaderNodeLayerWeight')
        lw.inputs['Blend'].default_value = 0.45
        mul = nodes.new('ShaderNodeMath')
        mul.operation = 'MULTIPLY'
        mul.inputs[1].default_value = alpha
        mat.node_tree.links.new(lw.outputs['Facing'], mul.inputs[0])
        add = nodes.new('ShaderNodeMath')
        add.operation = 'ADD'
        add.inputs[1].default_value = 0.12 * alpha
        mat.node_tree.links.new(mul.outputs[0], add.inputs[0])
        mat.node_tree.links.new(add.outputs[0], bsdf.inputs['Alpha'])
        alpha = None
    if alpha is not None:
        bsdf.inputs['Alpha'].default_value = alpha
    if alpha is None or alpha < 0.999:
        try:
            mat.surface_render_method = 'BLENDED'
        except Exception:
            mat.blend_method = 'BLEND'
        try:
            mat.use_transparency_overlap = True
        except Exception:
            pass
    return mat


# ---- shape helpers -------------------------------------------------------------------------------

def texel_heights(ob, w, h):
    """The height (Z in the piece's frame) of the surface under each texel of a w x h texture
    (NaN where no face covers it): the faces rasterised in UV space with barycentric heights."""
    import numpy as np
    me = ob.data
    nl = len(me.loops)
    uv = np.zeros(nl * 2, np.float32)
    me.uv_layers.active.data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2)
    vi = np.zeros(nl, np.int32)
    me.loops.foreach_get('vertex_index', vi)
    co = np.zeros(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    M = np.array(ob.matrix_world)
    z = (co @ M[:3, :3].T + M[:3, 3])[:, 2]
    Z = np.full((h, w), np.nan, np.float32)
    for poly in me.polygons:
        ls = list(range(poly.loop_start, poly.loop_start + poly.loop_total))
        for k in range(1, len(ls) - 1):
            tri = [ls[0], ls[k], ls[k + 1]]
            P = uv[tri] * [w, h]
            zz = z[vi[tri]]
            x0, y0 = np.floor(P.min(0)).astype(int)
            x1, y1 = np.ceil(P.max(0)).astype(int)
            x0, y0 = max(x0, 0), max(y0, 0)
            x1, y1 = min(x1, w - 1), min(y1, h - 1)
            if x1 < x0 or y1 < y0:
                continue
            gy, gx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
            px, py = gx + 0.5, gy + 0.5
            (ax, ay), (bx, by), (cx, cy) = P
            den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(den) < 1e-9:
                continue
            l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
            l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
            l3 = 1 - l1 - l2
            inside = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
            Z[gy[inside], gx[inside]] = (l1 * zz[0] + l2 * zz[1] + l3 * zz[2])[inside]
    return Z


def ramp(v, a, b):
    """A smoothstep weight: 0 at a, 1 at b (either way round), for bone weight functions."""
    import numpy as np
    t = np.clip((np.asarray(v, float) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def frame_along(p0, p1, up_hint=(0, 0, 1)):
    from mathutils import Vector
    t = (Vector(p1) - Vector(p0)).normalized()
    u = Vector(up_hint)
    if abs(t.dot(u)) > 0.95:
        u = Vector((1, 0, 0))
    n = (u - t * t.dot(u)).normalized()
    b = t.cross(n)
    return t, n, b


def sweep(bm, path, radii, segs=12, cap=True, profile=None, twist=0.0):
    """A tube along a polyline `path` (points) with a radius per point (or (rx, ry) per point),
    parallel-transported frames, capped. profile(angle) -> radius scale (e.g. a flattened or
    ridged section). Returns the new faces."""
    from mathutils import Vector
    import bmesh  # noqa: F401
    pts = [Vector(p) for p in path]
    n = len(pts)
    tangents = []
    for i in range(n):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, n - 1)]
        tangents.append((b - a).normalized())
    _, nrm, _ = frame_along(pts[0], pts[1])
    rings = []
    faces = []
    for i in range(n):
        t = tangents[i]
        nrm = (nrm - t * t.dot(nrm)).normalized()
        bin_ = t.cross(nrm)
        r = radii[i]
        rx, ry = (r, r) if not isinstance(r, (tuple, list)) else r
        ring = []
        for k in range(segs):
            ang = 2 * math.pi * k / segs + twist * i
            sc = profile(ang) if profile else 1.0
            v = pts[i] + (nrm * math.cos(ang) * rx + bin_ * math.sin(ang) * ry) * sc
            ring.append(bm.verts.new(v))
        rings.append(ring)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(segs):
            faces.append(bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k])))
    if cap:
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            c = sum((v.co for v in ring), Vector()) / len(ring)
            cv = bm.verts.new(c)
            for k in range(segs):
                q = (ring[k], ring[(k + 1) % segs], cv)
                faces.append(bm.faces.new(q[::-1] if rev else q))
    return faces


MB_REACH = 0.574  # a metaball's surface sits at radius x size x this (stiffness 2, threshold 0.6)


def metaball_mesh(bpy, name, blobs, resolution=0.01, blend=1.6):
    """A metaball sculpt turned into a mesh. blobs: [(centre, (hx, hy, hz), rot_quat or None,
    negative)], each an ellipsoid with those half-extents along the cue frame's X, Y, Z (before
    rot). Neighbours melt together smoothly; `blend` widens each blob's reach (the surface still
    lands on its half-extents when alone) so they merge more. Returns the mesh object."""
    mb = bpy.data.metaballs.new(name + '_mb')
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = 0.6
    for b in blobs:
        co, half = b[0], b[1]
        rot = b[2] if len(b) > 2 else None
        neg = b[3] if len(b) > 3 else False
        R = max(half) * blend
        el = mb.elements.new(type='ELLIPSOID')
        el.co = co
        el.stiffness = 2.0
        el.radius = R
        # reach scales with the radius, so shrink the size to land on the half-extents
        el.size_x, el.size_y, el.size_z = (h / (R * MB_REACH) for h in half)
        if rot is not None:
            el.rotation = rot
        if neg:
            el.use_negative = True
    ob = bpy.data.objects.new(name + '_mbo', mb)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.metaballs.remove(mb)
    out = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(out)
    for p in me.polygons:
        p.use_smooth = True
    return out


def assign_by_region(ob, fn):
    """Set each face's material index from fn(centre (x, y, z), normal) -> index."""
    for p in ob.data.polygons:
        p.material_index = fn(tuple(p.center), tuple(p.normal))


def apply_modifier(bpy, ob, kind, **props):
    mod = ob.modifiers.new(kind, kind)
    for k, v in props.items():
        setattr(mod, k, v)
    bpy.context.view_layer.objects.active = ob
    with bpy.context.temp_override(object=ob, active_object=ob):
        bpy.ops.object.modifier_apply(modifier=mod.name)


# =============================================================================================
# Export and the spec
# =============================================================================================

def export(kit):
    """Split every joint's objects by material into one OBJ per (joint, material) and write
    piece.json. Mesh files are in the Roblox cue frame (see the module docstring)."""
    import bmesh
    import numpy as np
    bpy = kit.bpy
    out = os.path.join(PIECES_DIR, kit.pid)
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith('.obj') or f.endswith('.glb'):
            os.remove(os.path.join(out, f))
    parts = []
    tris_total = 0
    skinned = {o.name for sk in kit.skins.values() for o in sk['meshes']}
    for sname, sk in kit.skins.items():
        sp = export_skin(kit, sname, sk, out)
        parts += sp
        tris_total += sum(x['Triangles'] for x in sp)
    for jname, j in kit.joints.items():
        by_mat = {}
        for ob in j['objects']:
            if ob.name in skinned:
                continue
            me = ob.data
            for mi, slot in enumerate(ob.material_slots):
                mname = slot.material.name.split('PM_%s_' % kit.pid, 1)[-1]
                bm = bmesh.new()
                bm.from_mesh(me)
                bm.transform(ob.matrix_world)
                bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != mi], context='FACES')
                if not bm.faces:
                    bm.free()
                    continue
                by_mat.setdefault(mname, []).append(bm)
        for mname, bms in by_mat.items():
            textured = bool(kit.mats[mname].get('SurfaceAppearance'))
            verts, faces, uvs, fuv = [], [], [], []
            for bm in bms:
                bmesh.ops.triangulate(bm, faces=bm.faces[:])
                bm.verts.ensure_lookup_table()
                base = len(verts)
                verts += [tuple(v.co) for v in bm.verts]
                faces += [[base + v.index for v in f.verts] for f in bm.faces]
                uvl = bm.loops.layers.uv.active if textured else None
                if uvl is not None:
                    for f in bm.faces:
                        fuv.append([len(uvs) + i for i in range(len(f.loops))])
                        uvs += [tuple(lp[uvl].uv) for lp in f.loops]
                bm.free()
            V = np.array(verts)
            # Blender cue frame (side, -at, up) -> Roblox cue frame (-side, up, 3.5 - at)
            R = np.stack([-V[:, 0], V[:, 2], ZOFF[kit.frame] + V[:, 1]], 1)
            lo, hi = R.min(0), R.max(0)
            centre = (lo + hi) / 2
            fname = '%s_%s.obj' % (jname, mname)
            with open(os.path.join(out, fname), 'w') as fh:
                fh.write('# %s %s: Roblox cue frame, recentred on its bounding box\n' % (kit.pid, fname))
                for v in R - centre:
                    fh.write('v %.5f %.5f %.5f\n' % tuple(v))
                if fuv:
                    for uv in uvs:
                        fh.write('vt %.5f %.5f\n' % uv)
                    for f, t in zip(faces, fuv):
                        fh.write('f %s\n' % ' '.join('%d/%d' % (i + 1, j + 1) for i, j in zip(f, t)))
                else:
                    for f in faces:
                        fh.write('f %s\n' % ' '.join(str(i + 1) for i in f))
            tris_total += len(faces)
            spec = dict(kit.mats[mname])
            spec.update({'Name': '%s_%s' % (jname, mname), 'File': 'pieces/%s/%s' % (kit.pid, fname), 'Joint': jname,
                         'Offset': [round(float(x), 4) for x in centre], 'Size': [round(float(x), 4) for x in hi - lo],
                         'Triangles': len(faces)})
            parts.append(spec)
    joints = {}
    for jname, j in kit.joints.items():
        p = j['Pivot']
        joints[jname] = {'Parent': j['Parent'], 'Pivot': p, 'PivotRoblox': [round(-p[0], 4), round(p[2], 4), round(ZOFF[kit.frame] + p[1], 4)],
                         'Motion': [{k_: v_ for k_, v_ in m.items() if not k_.startswith('_')} for m in j['Motion']]}
        if j.get('Aura'):
            joints[jname]['Aura'] = True
    spec = {'id': kit.pid, 'Frame': kit.frame, 'frame': 'Blender cue frame for Pivot/Motion axes: X side, Y toward the butt (-AtStuds), Z up; '
                                   'PivotRoblox and Offset are in the cue MeshPart frame (X = -Side, Y = Up, Z = 3.5 - AtStuds)',
            'Triangles': tris_total, 'Parts': parts, 'Joints': joints}
    if kit.paths:
        spec['Paths'] = kit.paths
    with open(os.path.join(out, 'piece.json'), 'w') as fh:
        json.dump(spec, fh, indent=2)
        fh.write('\n')
    print('CUE pieces wrote %s: %d parts, %d triangles' % (kit.pid, len(parts), tris_total))
    return spec


def export_matrix(frame):
    """E: the piece's Blender frame -> the frame a skinned GLB is written in, chosen so that the
    glTF exporter's Z-up to Y-up turn (x, y, z) -> (x, z, -y) lands it in the Roblox cue frame
    (X = -Side, Y = Up, Z = ZOFF - Blender Y... that is 3.5 - AtStuds on the cue), not recentred."""
    from mathutils import Matrix
    return Matrix(((-1, 0, 0, 0), (0, -1, 0, -ZOFF[frame]), (0, 0, 1, 0), (0, 0, 0, 1)))


def skin_weights(kit, sk, V):
    """Each bone's weight per vertex: all on the root, then each bone (parent first) takes its
    weight function's share of its parent's weight."""
    import numpy as np
    W = {sk['root']: np.ones(len(V))}
    for b, fn in sk['bones'].items():
        parent = kit.joints[b]['Parent']
        share = np.clip(np.asarray(fn(V), float), 0, 1) * W[parent]
        W[b] = share
        W[parent] = W[parent] - share
    return W


def export_skin(kit, sname, sk, out):
    """One skinned model as pieces/<pid>/<name>.glb: an armature of the root joint and its bones
    (each bone's head at its joint's pivot, pointing up, unrotated), the model and its hologram
    shell bound to it with the procedural weights, UVs and normals, no materials (they are the
    SurfaceAppearance and Material in piece.json). Written in the Roblox cue frame (export_matrix):
    Roblox's importer gives a Model of skinned MeshParts sharing the Bones; each frame a script sets
    every Bone's Transform = Rest^-1 * J_parent(t)^-1 * J_bone(t) * Rest, J the joint's matrix
    (joint_matrix, the same maths as the rigid parts) turned into the Roblox cue frame and Rest the
    bone's rest CFrame in the model. Returns the part specs."""
    import numpy as np
    from mathutils import Matrix, Vector
    bpy = kit.bpy
    E = export_matrix(kit.frame)
    names = [sk['root']] + list(sk['bones'])
    arm_data = bpy.data.armatures.new(sname + 'Rig')
    arm = bpy.data.objects.new(sname + 'Rig', arm_data)
    bpy.context.scene.collection.objects.link(arm)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    ebs = {}
    for n in names:
        eb = arm_data.edit_bones.new(n)
        head = E @ Vector(kit.joints[n]['Pivot'])
        eb.head = head
        eb.tail = head + Vector((0, 0, 0.06))
        ebs[n] = eb
    for n in names:
        par = kit.joints[n]['Parent']
        if par in ebs and n != sk['root']:
            ebs[n].parent = ebs[par]
    bpy.ops.object.mode_set(mode='OBJECT')
    copies, specs = [], []
    for ob in sk['meshes']:
        V = np.array([ob.matrix_world @ v.co for v in ob.data.vertices])
        W = skin_weights(kit, sk, V)
        cp = ob.copy()
        cp.data = ob.data.copy()
        cp.data.materials.clear()
        cp.name = cp.data.name = ob.name + 'Skin'
        bpy.context.scene.collection.objects.link(cp)
        cp.data.transform(E @ ob.matrix_world)
        cp.matrix_world = Matrix.Identity(4)
        for n in names:
            vg = cp.vertex_groups.new(name=n)
            w = W[n]
            for i in np.nonzero(w > 1e-3)[0]:
                vg.add([int(i)], float(w[i]), 'REPLACE')
        cp.parent = arm
        mod = cp.modifiers.new('Rig', 'ARMATURE')
        mod.object = arm
        copies.append(cp)
        mname = ob.data.materials[0].name.split('PM_%s_' % kit.pid, 1)[-1]
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        spec = dict(kit.mats[mname])
        X = np.array([v.co[:] for v in cp.data.vertices])
        R = np.stack([X[:, 0], X[:, 2], -X[:, 1]], 1)          # as glTF writes it: the Roblox cue frame
        lo, hi = R.min(0), R.max(0)
        spec.update({'Name': ob.name, 'File': 'pieces/%s/%s.glb' % (kit.pid, sname), 'Mesh': cp.name,
                     'Joint': sk['root'], 'Skinned': True, 'Bones': names, 'Triangles': tris,
                     'Offset': [round(float(x), 4) for x in (lo + hi) / 2],
                     'Size': [round(float(x), 4) for x in hi - lo]})
        specs.append((spec, cp))
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    for cp in copies:
        cp.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, sname + '.glb'), export_format='GLB', use_selection=True,
                              export_skins=True, export_materials='NONE', export_texcoords=True,
                              export_normals=True, export_animations=False, export_yup=True)
    for spec, cp in specs:
        spec['Mesh'] = cp.name
    result = [spec for spec, _ in specs]
    for cp in copies:
        bpy.data.objects.remove(cp)
    bpy.data.objects.remove(arm)
    return result


# =============================================================================================
# The preview side: load a built piece onto the cue and move it
# =============================================================================================

def _import_skin(bpy, path, parent, frame):
    """Import a skinned piece GLB under a holder that turns it back from the Roblox cue frame
    into the piece's Blender frame. Returns (armature, {mesh name: object})."""
    from mathutils import Matrix
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    holder = bpy.data.objects.new('PS_' + os.path.basename(path), None)
    bpy.context.scene.collection.objects.link(holder)
    holder.parent = parent
    holder.matrix_parent_inverse = Matrix.Identity(4)
    holder.matrix_basis = export_matrix(frame).inverted()
    for o in new:
        if o.parent is None:
            mb = o.matrix_basis.copy()
            o.parent = holder
            o.matrix_parent_inverse = Matrix.Identity(4)
            o.matrix_basis = mb
    arm = next(o for o in new if o.type == 'ARMATURE')
    meshes = {}
    for o in new:
        if o.type == 'MESH':
            meshes[o.name] = o
            meshes[o.data.name] = o
    return arm, meshes


def attach(bpy, pid, cue_obj):
    """Import pieces/<pid>/ onto cue_obj (parented, so it follows the cue). Returns
    animate(t), which sets every joint's transform for time t."""
    import numpy as np
    from mathutils import Matrix
    path = os.path.join(PIECES_DIR, pid, 'piece.json')
    if not os.path.isfile(path):
        return None
    spec = link_paths(json.load(open(path)))
    joints = spec['Joints']
    empties = {}
    parts = []
    for jname in joints:
        e = bpy.data.objects.new('PJ_' + jname, None)
        bpy.context.scene.collection.objects.link(e)
        e.parent = cue_obj
        empties[jname] = e
    rigs = []                      # (armature, holder) of each skinned GLB
    imported = {}
    for part in spec['Parts']:
        if part.get('Skinned'):
            if part['File'] not in imported:
                imported[part['File']] = _import_skin(bpy, os.path.join(HERE, part['File']), cue_obj,
                                                      spec.get('Frame', 'cue'))
                rigs.append(imported[part['File']][0])
            arm, meshes = imported[part['File']]
            ob = meshes.get(part['Mesh']) or meshes.get(part['Name'])
            ob.data.materials.clear()
            ob.data.materials.append(make_blender_material(bpy, 'PMv_%s_%s' % (pid, part['Name']), part))
            parts.append(ob)
            continue
        V, F, VT, FT = [], [], [], []
        for line in open(os.path.join(HERE, part['File'])):
            if line.startswith('v '):
                V.append([float(x) for x in line.split()[1:4]])
            elif line.startswith('vt '):
                VT.append([float(x) for x in line.split()[1:3]])
            elif line.startswith('f '):
                F.append([int(x.split('/')[0]) - 1 for x in line.split()[1:]])
                if '/' in line:
                    FT.append([int(x.split('/')[1]) - 1 for x in line.split()[1:]])
        R = np.array(V) + np.array(part['Offset'])
        B = np.stack([-R[:, 0], R[:, 2] - ZOFF[spec.get('Frame', 'cue')], R[:, 1]], 1)  # back to Blender
        me = bpy.data.meshes.new(part['Name'])
        me.from_pydata(B.tolist(), [], F)
        me.update()
        if VT and FT:
            uvl = me.uv_layers.new(name='UVMap')
            flat = [VT[i] for f in FT for i in f]
            uvl.data.foreach_set('uv', [c for uv in flat for c in uv])
        for p in me.polygons:
            p.use_smooth = True
        try:
            me.set_sharp_from_angle(angle=math.radians(40))
        except Exception:
            pass
        ob = bpy.data.objects.new('P_' + part['Name'], me)
        bpy.context.scene.collection.objects.link(ob)
        ob.data.materials.append(make_blender_material(bpy, 'PMv_%s_%s' % (pid, part['Name']), part))
        ob.parent = empties[part['Joint']]
        parts.append(ob)
    E = export_matrix(spec.get('Frame', 'cue'))
    Ei = E.inverted()

    def animate(t):
        for jname, e in empties.items():
            e.matrix_parent_inverse = Matrix.Identity(4)
            e.matrix_basis = Matrix(joint_matrix(joints, jname, t).tolist())
        for arm in rigs:
            # pose = K_bone @ Rest in armature space, K = A^-1 E J E^-1 A (J the joint's matrix in
            # the piece frame, A the armature's own transform under its holder)
            A = arm.matrix_basis
            Ai = A.inverted()
            K = {}
            for pb in arm.pose.bones:
                if pb.name in joints:
                    K[pb.name] = Ai @ E @ Matrix(joint_matrix(joints, pb.name, t).tolist()) @ Ei @ A
            for pb in arm.pose.bones:
                if pb.name not in K:
                    continue
                B = pb.bone.matrix_local
                Kp = K.get(pb.parent.name) if pb.parent else None
                rel = K[pb.name] if Kp is None else Kp.inverted() @ K[pb.name]
                pb.matrix_basis = B.inverted() @ rel @ B
    animate(0.0)
    animate.parts = parts          # the part objects, for a finisher that fades them
    return animate


# =============================================================================================
# Pieces
# =============================================================================================

def build(pid, render_preview=True):
    import bpy
    import cue_common as cc
    cc.clear_scene('CuePieces')
    import CuePiecesMythic  # noqa: F401  (registers the builders on the imported CuePieces module)
    import CuePiecesLegendary  # noqa: F401
    import CuePiecesPocket  # noqa: F401
    import CuePiecesUnique  # noqa: F401
    import CuePieces
    kit = CuePieces.Kit(bpy, pid)
    CuePieces.BUILDERS[pid](kit)
    spec = CuePieces.export(kit)
    if render_preview:
        preview(pid)
    return spec


def preview(pid, t_list=(0.0, 1.3)):
    """pieces/<pid>/preview.png: the plain cue with the exported piece (as the preview loads it),
    from the side and from above-behind, at a couple of moments."""
    import bpy
    import cue_common as cc
    from mathutils import Vector
    cc.clear_scene('PiecePreview')
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('W')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (0.02, 0.022, 0.03, 1)
    bg.inputs[1].default_value = 1.0
    scene.world = world
    cue = cc.load_cue_object()
    m = bpy.data.materials.new('plain')
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (0.5, 0.5, 0.55, 1)
    cue.data.materials.clear()
    cue.data.materials.append(m)
    for loc, e in (((3, -4, 6), 2.5), ((-4, -9, 3), 2.0), ((2, -10, -3), 1.0)):
        ld = bpy.data.lights.new('L', 'AREA')
        ld.energy = 300 * e
        ld.size = 4
        lo = bpy.data.objects.new('L', ld)
        lo.location = loc
        scene.collection.objects.link(lo)
        lo.rotation_euler = (Vector((0, -6.5, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    animate = attach(bpy, pid, cue)
    cam_d = bpy.data.cameras.new('C')
    cam = bpy.data.objects.new('C', cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 800, 500
    tiles = []
    out = os.path.join(PIECES_DIR, pid)
    views = (((1.6, -6.3, 0.35), (0, -6.95, 0.05), 45), ((-0.9, -8.6, 0.9), (0, -6.9, 0.05), 45), ((2.8, -3.5, 1.6), (0, -4.6, 0), 30))
    for vi, (loc, tgt, lens) in enumerate(views):
        for ti, t in enumerate(t_list if vi == 0 else t_list[:1]):
            animate(t)
            cam.location = loc
            cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            cam_d.lens = lens
            path = os.path.join(out, '_v%d_%d.png' % (vi, ti))
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            tiles.append(path)
    try:  # Blender's own Python has no PIL: then `python3 CuePieces.py --sheet <id>` stitches them
        stitch(pid)
    except ImportError:
        pass
    print('CUE pieces preview', os.path.join(out, 'preview.png'))


SPRITES = {}  # sprite name -> spec (registered by the builders' module): a flipbook rendered from a piece


def render_sprite(name):
    """Render a flipbook from a built piece (Blender side): only spec['joints'] are kept, every
    material becomes a spectral glow (spec['colour'] at the rim fading to clear face-on, plus a
    faint fill), the film is transparent; spec['pose'](i, frames) -> {joint: 4x4 list} poses
    each frame; frames land in vfx/<skin>/_frames_<name>/ for `--sheet-sprite` to join."""
    import bpy
    import cue_common as cc
    from mathutils import Matrix, Vector
    import CuePiecesMythic  # noqa: F401
    import CuePiecesLegendary  # noqa: F401
    import CuePiecesPocket  # noqa: F401
    import CuePieces
    spec = CuePieces.SPRITES[name]
    cc.clear_scene('Sprite')
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = 'RGBA'
    root = bpy.data.objects.new('Root', None)
    scene.collection.objects.link(root)
    attach(bpy, spec['piece'], root)
    keep = set(spec['joints'])
    col = srgb_to_lin(hexrgb(spec['colour']))
    glow = bpy.data.materials.new('Spectral')
    glow.use_nodes = True
    nt = glow.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    outn = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = col + (1,)
    em.inputs['Strength'].default_value = 2.0
    tr = nt.nodes.new('ShaderNodeBsdfTransparent')
    lw = nt.nodes.new('ShaderNodeLayerWeight')
    lw.inputs['Blend'].default_value = spec.get('rim', 0.35)
    ramp = nt.nodes.new('ShaderNodeMath')
    ramp.operation = 'MULTIPLY_ADD'
    ramp.inputs[1].default_value = 0.8
    ramp.inputs[2].default_value = spec.get('fill', 0.3)
    nt.links.new(lw.outputs['Facing'], ramp.inputs[0])
    mix = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(ramp.outputs[0], mix.inputs['Fac'])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], outn.inputs['Surface'])
    try:
        glow.surface_render_method = 'BLENDED'
    except Exception:
        glow.blend_method = 'BLEND'
    joints_obj = {}
    for ob in list(bpy.data.objects):
        if ob.name.startswith('PJ_'):
            joints_obj[ob.name[3:]] = ob
        if ob.name.startswith('P_'):
            if (ob.parent is not None and ob.parent.name[3:] not in keep) or any(d in ob.name for d in spec.get('drop', ())):
                bpy.data.objects.remove(ob)
            else:
                ob.data.materials.clear()
                ob.data.materials.append(glow)
    cam_d = bpy.data.cameras.new('C')
    cam = bpy.data.objects.new('C', cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = spec['ortho']
    loc, tgt = Vector(spec['cam'][0]), Vector(spec['cam'][1])
    cam.location = loc
    cam.rotation_euler = (tgt - loc).to_track_quat('-Z', 'Y').to_euler()
    n = spec.get('frames', 16)
    px = spec.get('px', 240)
    scene.render.resolution_x = scene.render.resolution_y = px
    out = os.path.join(HERE, 'vfx', spec['skin'], '_frames_' + name)
    os.makedirs(out, exist_ok=True)
    for i in range(n):
        poses = spec['pose'](i, n)
        for jn, e in joints_obj.items():
            e.matrix_parent_inverse = Matrix.Identity(4)
            e.matrix_basis = Matrix(poses.get(jn, Matrix.Identity(4)))
        scene.render.filepath = os.path.join(out, '%02d.png' % i)
        bpy.ops.render.render(write_still=True)
    print('CUE pieces sprite frames', out)


def sheet_sprite(name, skin, frames=16, grid=4, size=1024, pad=8, fade=None):
    """Join vfx/<skin>/_frames_<name>/NN.png into vfx/<skin>/<name>_4x4.png (a 1024 sheet with
    padding, as CueVfx.flipbook lays them), with an optional per-frame alpha fade."""
    from PIL import Image
    src = os.path.join(HERE, 'vfx', skin, '_frames_' + name)
    cell = size // grid
    sheet = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    for i in range(frames):
        im = Image.open(os.path.join(src, '%02d.png' % i)).convert('RGBA').resize((cell - 2 * pad, cell - 2 * pad), Image.LANCZOS)
        if fade:
            a = im.getchannel('A').point(lambda v, f=fade(i, frames): int(v * f))
            im.putalpha(a)
        r, c = divmod(i, grid)
        sheet.paste(im, (c * cell + pad, r * cell + pad))
    path = os.path.join(HERE, 'vfx', skin, '%s_4x4.png' % name)
    sheet.save(path, optimize=True)
    import shutil
    shutil.rmtree(src)
    print('CUE pieces sheet', path)


def stitch(pid):
    """Join the preview tiles (_v*_*.png) into preview.png and remove them."""
    from PIL import Image
    out = os.path.join(PIECES_DIR, pid)
    tiles = sorted(f for f in os.listdir(out) if f.startswith('_v') and f.endswith('.png'))
    ims = [Image.open(os.path.join(out, f)) for f in tiles]
    w, h = ims[0].size
    sheet = Image.new('RGB', (w * 2, h * ((len(ims) + 1) // 2)))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % 2) * w, (i // 2) * h))
    sheet.save(os.path.join(out, 'preview.png'))
    for f in tiles:
        os.remove(os.path.join(out, f))


def main():
    if '--sprite' in sys.argv:  # Blender side
        render_sprite(sys.argv[sys.argv.index('--sprite') + 1])
        return
    if '--sheet-sprite' in sys.argv:  # system python: name skin
        i = sys.argv.index('--sheet-sprite')
        sheet_sprite(sys.argv[i + 1], sys.argv[i + 2])
        return
    if '--sheet' in sys.argv:
        stitch(sys.argv[sys.argv.index('--sheet') + 1])
        return
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    for pid in (arg for arg in argv if not arg.startswith('--')):
        build(pid, render_preview='--no-preview' not in argv)


if __name__ == '__main__':
    main()
