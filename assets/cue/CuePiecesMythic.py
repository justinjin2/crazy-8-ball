"""The Mythic and Secret pieces (scripted modelling; see CuePieces.py for the kit and export).

Every piece is modelled in the cue's Blender frame: X is the side, Y runs from the tip (0) to
the butt (-7), Z is the top. Heads and masks sit on or past the butt end.
"""
import math
import os

import CuePieces as P
from CuePieces import piece, sweep, metaball_mesh, assign_by_region, apply_modifier, ramp


def _butt(at):
    return -at


# =============================================================================================
# Celestial Dragon (M1)
# =============================================================================================

def _icy_eyes(px):
    """The glowing icy blue of the dragon's eyes (the mane is a paler, greyer blue)."""
    import numpy as np
    h, s_, v = _hsv(px)
    return (np.clip((s_ - 0.45) / 0.15, 0, 1) * np.clip((v - 0.55) / 0.2, 0, 1)
            * ((h > 0.53) & (h < 0.7)))


# the spirit dragon swims (designer, 2026-09-30: "an animated spiritual dragon spiralling around
# the cue", then "slithers around back and forth from the cue from tip to butt and turns around,
# faster, more fluid and smooth"): a closed swimming loop round the cue that circles it all the
# time while running from the tip end to the butt end and back, turning round at each end where
# it flattens into a circle; it runs on the outside (radius r0 + dr) going to the butt and on the
# inside coming back, so the dragon never swims through itself. The body rides the loop like a
# train on a track (each spine bone a Path motion), so it slithers through the same curves the
# head took. The snout stays a few inches short of the tip (designer, 2026-09-30).
SWIM_AT = (0.65, 6.5)     # AtStuds the front of the spine reaches at the tip end and the butt end
SWIM_TURNS = 3.0          # turns round the cue on each leg
SWIM_ROUND = 0.96         # how sharply each end turns round (1 a sharp triangle, 0 a sine)
SWIM_R = (0.40, 0.1)      # the loop's radius round the cue's axis: r0 + dr sin(phase) (0.34 on the 0.2 cue)
SWIM_PERIOD = 10.0        # seconds for a whole lap, tip to butt and back
SWIM_BODY = 4.5           # the spine's length, studs (the head sits on its front)
SWIM_STEP = 0.02          # the path's sample spacing, studs


def _swim_point(phi):
    """The loop at phase phi (0 .. 2 pi): at the tip end at 0, the butt end at pi."""
    mid = (SWIM_AT[0] + SWIM_AT[1]) / 2
    amp = (SWIM_AT[1] - SWIM_AT[0]) / 2
    # a rounded triangle wave: an even pitch along each leg (so it reads as a spiral all the way)
    # and a short smooth turn round at each end
    at = mid - amp * math.asin(SWIM_ROUND * math.cos(phi)) / math.asin(SWIM_ROUND)
    th = 0.4 + 2 * SWIM_TURNS * phi
    r = SWIM_R[0] + SWIM_R[1] * math.sin(phi)
    return (r * math.sin(th), -at, r * math.cos(th))


def _swim_loop():
    """The loop sampled every ~SWIM_STEP of arc length: (frames, step, length), each frame
    (phase, point, tangent, normal away from the cue, side = tangent x normal)."""
    import numpy as np
    from mathutils import Vector
    n_fine = 60000
    ph = np.linspace(0, 2 * math.pi, n_fine, endpoint=False)
    P = np.array([_swim_point(x) for x in ph])
    seg = np.linalg.norm(np.roll(P, -1, 0) - P, axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    length = float(cum[-1])
    n = int(round(length / SWIM_STEP))
    step = length / n
    out = []
    for i in range(n):
        s_ = i * step
        k_ = int(np.searchsorted(cum, s_, side='right') - 1) % n_fine
        f = (s_ - cum[k_]) / max(seg[k_], 1e-9)
        phi = ph[k_] + f * (2 * math.pi / n_fine)
        p = Vector(_swim_point(phi))
        a_ = Vector(_swim_point(phi - 1e-4))
        b_ = Vector(_swim_point(phi + 1e-4))
        tg = (b_ - a_).normalized()
        radial = Vector((p.x, 0, p.z))
        nrm = (radial - tg * tg.dot(radial)).normalized()
        out.append((phi, p, tg, nrm, tg.cross(nrm)))
    return out, step, length


def _dragon_radius(t):
    """The body's radius along it (t = 0 at the tail, 1 at the neck): a thin tail thickening to
    the chest, a little thinner at the neck."""
    grow = min(t / 0.3, 1.0)
    grow = grow * grow * (3 - 2 * grow)
    neck = min(max(t - 0.88, 0.0) / 0.12, 1.0)
    return 0.012 + 0.078 * grow - 0.012 * neck


def _dragon_tube(bm, frames, radius, segs, uv=None, v_per_stud=3.0, flat=0.85):
    """A tube along the dragon's frames (UVs if uv: u round from the dorsal line, v along the
    body, v_per_stud texture repeats per stud); flat squashes it a little, back to belly."""
    rings, v_acc, prev = [], 0.0, None
    for (t, p, tg, nrm, side) in frames:
        if prev is not None:
            v_acc += (p - prev).length * v_per_stud
        prev = p
        r = radius(t)
        ring = []
        for k in range(segs):
            ang = 2 * math.pi * k / segs
            ring.append(bm.verts.new(p + nrm * math.cos(ang) * r * flat + side * math.sin(ang) * r))
        rings.append((ring, v_acc))
    for i in range(len(rings) - 1):
        (a, va), (b, vb) = rings[i], rings[i + 1]
        for k in range(segs):
            k1 = (k + 1) % segs
            f = bm.faces.new((a[k], a[k1], b[k1], b[k]))
            if uv is not None:
                u0, u1 = k / segs, (k + 1) / segs
                for lp, (u, v) in zip(f.loops, ((u0, va), (u1, va), (u1, vb), (u0, vb))):
                    lp[uv].uv = (u, v)
    for (ring, _), rev in ((rings[0], True), (rings[-1], False)):
        c = sum((v.co for v in ring), ring[0].co * 0) / len(ring)
        cv = bm.verts.new(c)
        for k in range(segs):
            q = (ring[k], ring[(k + 1) % segs], cv)
            f = bm.faces.new(q[::-1] if rev else q)
            if uv is not None:
                for lp in f.loops:
                    lp[uv].uv = (0.0, 0.0)


def _dragon_scales_png(k, name, w=256, h=512):
    """The spirit body's SurfaceAppearance (u round the body from the dorsal line, v along it):
    translucent blue scales with glowing rims, a white-hot dorsal line and pale belly plates, so
    the body reads as a dragon of light and not a tube; and its EmissiveMask."""
    import numpy as np
    bpy = k.bpy
    x = (np.arange(w) + 0.5) / w
    y = (np.arange(h) + 0.5) / h
    U, V = np.meshgrid(x, y)
    rows = 12
    row = np.floor(V * rows)
    fy = V * rows - row
    fx = (U * 10 + 0.5 * (row % 2)) % 1.0
    d = np.hypot((fx - 0.5) * 1.0, fy * 1.1)
    rim = np.exp(-((d - 0.5) / 0.07) ** 2) * (d < 0.62)
    inner = np.clip(1 - d / 0.5, 0, 1)
    du = np.minimum(U, 1 - U)                        # distance round from the dorsal line
    stripe = np.exp(-(du / 0.035) ** 2)
    belly = np.exp(-((U - 0.5) / 0.12) ** 2) * (0.5 + 0.5 * (np.cos(2 * np.pi * V * 24) > 0.2))
    base = np.array([0.30, 0.62, 1.0])
    pale = np.array([0.80, 0.92, 1.0])
    col = (base[None, None] * (0.35 + 0.5 * inner[..., None] * 0.4 + 0.6 * rim[..., None])
           + pale[None, None] * (belly[..., None] * 0.5) + np.ones(3)[None, None] * stripe[..., None])
    alpha = np.clip(0.16 + 0.55 * rim + 0.7 * stripe + 0.22 * belly, 0, 0.9)
    emis = np.clip(0.3 + 0.55 * rim + 0.9 * stripe + 0.3 * belly, 0, 1)
    paths = {}
    for key, arr, has_a in (('spirit', np.concatenate([np.clip(col, 0, 1), alpha[..., None]], -1), True),
                            ('emissive', np.concatenate([np.repeat(emis[..., None], 3, -1), np.ones((h, w, 1))], -1), False)):
        img = bpy.data.images.new('%s_%s' % (name, key), w, h, alpha=has_a)
        img.pixels.foreach_set(arr.astype(np.float32).ravel())
        rel = 'pieces/%s/%s_%s.png' % (k.pid, name, key)
        img.filepath_raw = os.path.join(P.HERE, rel)
        img.file_format = 'PNG'
        img.save()
        paths[key] = rel
    return paths


@piece
def celestial_dragon(k):
    """The Celestial Dragon (designer, 2026-09-30): a spirit dragon of blue light swimming round
    the cue, circling it all the time while it runs from the tip end to the butt end and back,
    turning round at each end, the head (Meshy, assets/cue/models/dragon_head) on its front. All
    of it is a spirit, see-through and glowing: the body is translucent blue scales with glowing
    rims, a white-hot dorsal line and pale belly plates (its own SurfaceAppearance), in a
    shimmering ForceField sheath round a bright core, with flame fins along its back and a flame
    tail fin; the head is the hologram of the generated model.

    Moving (all aura: hidden on the shooter's turn): thirty spine bones ride the swimming loop
    (Path motions, piece.json Paths: a lap in SWIM_PERIOD seconds), so the body slithers through
    the curves the head swam; on top a quick wave runs down the body from the neck to the tail
    (each bone a sideways and an outward bob a beat after the one before), the tail flicks, the
    head nods and looks round and every 4.8 s rears back roaring, the jaw gaping; the mane
    streams."""
    import numpy as np
    import bmesh
    from mathutils import Matrix, Vector
    bpy = k.bpy
    k.material('Sheath', 'ForceField', '#8FCBFF')
    k.material('Core', 'Neon', '#D8EEFF', Transparency=0.45)
    k.material('Fin', 'Neon', '#9ACFFF', Transparency=0.35)

    loop, step, length = _swim_loop()
    n = len(loop)
    speed = length / SWIM_PERIOD
    mats = []
    for _, p, tg, nrm, side in loop:
        M = np.eye(4)
        M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = tuple(side), tuple(tg), tuple(nrm), tuple(p)
        mats.append(M)
    k.path('Swim', mats, step)

    # the rest pose: the front of the spine mid-way along the leg back to the tip (phase 1.5 pi)
    i_front = min(range(n), key=lambda i: abs(loop[i][0] - 1.5 * math.pi))
    nb = int(round(SWIM_BODY / step))
    i_tail = i_front - nb
    frames = []                                       # (t along the body 0..1, point, tangent, normal, side)
    for i in range(i_tail, i_front + 1):
        _, p, tg, nrm, side = loop[i % n]
        frames.append(((i - i_tail) / nb, p, tg, nrm, side))

    def arc(t):                                       # the path's arc length at body place t (rest)
        return ((i_tail + t * nb) % n) * step

    def frame_at(t):
        return frames[int(round(t * nb))]

    k.joint('Dragon', pivot=(0, 0, 0), aura=True)

    # the spine: bones riding the loop, a quick wave on top running from the neck to the tail
    NB = 30
    centres = [0.02 + 0.96 * b / (NB - 1) for b in range(NB)]
    width = 0.96 / (NB - 1)
    WAVE = 1.5                                        # the body wave's length, studs
    bone_names = []
    for b, tc in enumerate(centres):
        _, p, tg, nrm, side = frame_at(tc)
        env = (0.035 + 0.025 * (1 - tc)) * (1 - 0.6 * max(0.0, (tc - 0.82) / 0.18))
        ph = 360.0 * tc * SWIM_BODY / WAVE
        nm = 'Spine%d' % (b + 1)
        motion = [{'Kind': 'Path', 'Path': 'Swim', 'Rest': round(arc(tc), 4), 'Speed': round(speed, 4)},
                  {'Kind': 'Bob', 'Dir': tuple(side), 'Amp': round(env, 4), 'Period': 1.1, 'Phase': round(ph, 1)},
                  {'Kind': 'Bob', 'Dir': tuple(nrm), 'Amp': round(0.4 * env, 4), 'Period': 1.1, 'Phase': round(ph + 90, 1)}]
        if b == 0:                                    # the tail flicks
            motion.append({'Kind': 'Hinge', 'Axis': tuple(nrm), 'Amp': 25.0, 'Period': 0.9})
        k.joint(nm, pivot=tuple(p), parent='Dragon', aura=True, motion=motion)
        bone_names.append((nm, tc))

    body_t = np.array([f[0] for f in frames])
    body_p = np.array([tuple(f[1]) for f in frames])

    def t_of(V):
        # each vertex's place along the body: the nearest spine sample
        d2 = ((V[:, None, :] - body_p[None, :, :]) ** 2).sum(-1)
        return body_t[np.argmin(d2, 1)]

    def body_abs(idx, tv):
        # the hats sum to one along the body (flat past the end bones)
        tc = np.clip(tv, centres[0], centres[-1])
        return np.clip(1 - np.abs(tc - centres[idx]) / width, 0, 1)

    def bone_fn(idx):
        # skin_weights hands each bone a share of its parent's remaining weight: the spine bones
        # all ride Dragon, so each takes its absolute weight over what the bones before it left
        def fn(V):
            tv = t_of(V)
            taken = sum(body_abs(j, tv) for j in range(idx)) if idx else np.zeros(len(V))
            return np.where(taken < 0.999, body_abs(idx, tv) / np.maximum(1 - taken, 1e-3), 0.0)
        return fn

    bones = {nm: bone_fn(i) for i, (nm, _) in enumerate(bone_names)}

    # the spirit body (textured), its sheath, its core
    paths = _dragon_scales_png(k, 'DragonBody')
    k.material('DragonBody', 'SmoothPlastic', '#FFFFFF', SurfaceAppearance={
        'ColorMap': paths['spirit'], 'EmissiveMask': paths['emissive'], 'EmissiveTint': '#8CC8FF',
        'EmissiveStrength': 1.8, 'AlphaMode': 'Transparency'})
    rings = frames[::2]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    _dragon_tube(bm, rings, _dragon_radius, 16, uv=uv, v_per_stud=2.4)
    body = k.add('Dragon', k.mesh_object('DragonBody', bm, ['DragonBody']))
    thin = frames[::4]
    bm = bmesh.new()
    _dragon_tube(bm, thin, lambda t: _dragon_radius(t) * 1.3 + 0.006, 12)
    sheath = k.add('Dragon', k.mesh_object('DragonSheath', bm, ['Sheath']))
    bm = bmesh.new()
    _dragon_tube(bm, thin, lambda t: _dragon_radius(t) * 0.28, 6)
    core = k.add('Dragon', k.mesh_object('DragonCore', bm, ['Core']))

    # flame fins along the back (blades raked back from the dorsal line) and a flame tail fin
    bm = bmesh.new()

    def blade(base, back, out, length, w):
        tip = base + (out * 0.75 - back * 0.66).normalized() * length
        a = base + back * w
        c = base - back * w
        s_ = back.cross(out).normalized() * w * 0.25
        vs = [bm.verts.new(v) for v in (a, c, tip, base + s_, base - s_)]
        for f in ((vs[0], vs[1], vs[2]), (vs[3], vs[0], vs[2]), (vs[1], vs[4], vs[2]), (vs[4], vs[3], vs[2]),
                  (vs[1], vs[0], vs[3]), (vs[1], vs[3], vs[4])):
            bm.faces.new(f)
    for i in range(6, len(frames) - 18, 6):
        t, p, tg, nrm, side = frames[i]
        r = _dragon_radius(t)
        blade(p + nrm * r * 0.8, -tg, nrm, 0.05 + 1.1 * r, 0.02 + 0.2 * r)
    t, p, tg, nrm, side = frames[0]
    for ang in (-40, -20, 0, 20, 40):
        out = (Matrix.Rotation(math.radians(ang), 3, tg) @ nrm).normalized()
        blade(p, -tg, out, 0.16, 0.025)
    fins = k.add('Dragon', k.mesh_object('DragonFins', bm, ['Fin'], smooth=False))
    k.skins['DragonBody'] = {'root': 'Dragon', 'bones': bones, 'meshes': [body, sheath, core, fins]}

    # the head on the neck: the model's face looks along -Y with its top +Z (as generated);
    # turned so it looks along the neck, its top away from the cue
    _, pe, tg, nrm, side = frames[-1]
    fwd = tg
    up = nrm
    R = Matrix((tuple(fwd.cross(up) * -1), tuple(-fwd), tuple(up))).transposed()   # columns: X, Y, Z
    HEAD_L = 1.0                                   # snout to the back of the mane, studs
    OLD_L, OLD_T = 0.78, Vector((0, -6.76, -0.1))  # the head's size and place when it sat on the butt
    scale = HEAD_L / OLD_L
    attach = Vector((0, -0.12, 0.12)) * scale      # where the neck meets the back of the head (local)
    C = pe - R @ attach

    def to_cue(p_old):
        return C + R @ ((Vector(p_old) - OLD_T) * scale)

    def from_cue(V):
        Rm = np.array(R)
        loc = (V - np.array(C)) @ Rm          # R^T (V - C), as rows
        return loc / scale + np.array(OLD_T)

    def place(ob):
        V = np.array([v.co[:] for v in ob.data.vertices])
        lo, hi = V.min(0), V.max(0)
        s_ = HEAD_L / (hi[1] - lo[1])
        return (Matrix.Translation(C) @ R.to_4x4() @ Matrix.Scale(s_, 4)
                @ Matrix.Translation((-(lo[0] + hi[0]) / 2, -hi[1], -lo[2])))

    # the head nods, looks round and, every 4.8 s, rears back roaring (a pulse) as the jaw gapes
    # (positive about side lifts the snout away from the cue)
    k.joint('Head', pivot=tuple(pe), parent='Spine%d' % NB, aura=True, motion=[
        {'Kind': 'Hinge', 'Axis': tuple(side), 'Base': 5.0, 'Amp': 8.0, 'Period': 2.2},
        {'Kind': 'Hinge', 'Axis': tuple(up), 'Amp': 16.0, 'Period': 3.1, 'Phase': 40},
        {'Kind': 'Hinge', 'Axis': tuple(side), 'Amp': 14.0, 'Period': 4.8, 'Shape': 'pulse'}])
    k.joint('Jaw', pivot=tuple(to_cue((0, -7.22, 0.02))), parent='Head', aura=True, motion=[
        {'Kind': 'Hinge', 'Axis': tuple(R @ Vector((1, 0, 0))), 'Base': 6.0, 'Amp': 6.0, 'Period': 2.4},
        {'Kind': 'Hinge', 'Axis': tuple(R @ Vector((1, 0, 0))), 'Amp': 16.0, 'Period': 4.8, 'Shape': 'pulse'}])
    k.joint('Mane', pivot=tuple(to_cue((0, -7.1, 0.15))), parent='Head', aura=True, motion=[
        {'Kind': 'Hinge', 'Axis': tuple(R @ Vector((1, 0, 0))), 'Amp': 10.0, 'Period': 1.3, 'Phase': 60}])
    head_bones = {'Jaw': lambda V: (lambda O: ramp(O[:, 1], -7.25, -7.33) * ramp(O[:, 2], 0.03, -0.02))(from_cue(V)),
                  'Mane': lambda V: (lambda O: ramp(O[:, 1], -7.15, -7.0) * ramp(O[:, 2], 0.12, 0.2))(from_cue(V))}
    k.model('Head', 'DragonHead', 'dragon_head', place, target_tris=15000, emissive=_icy_eyes,
            emissive_tint='#7FC8FF', emissive_strength=3.0, cut_below=0.3, bones=head_bones,
            hologram={'Tint': '#8CC8FF', 'Shell': '#CFEAFF', 'Strength': 1.8, 'ShellTris': 6000,
                      'Alpha': (0.14, 0.55)})     # more solid than the pocket spirits: the face must read small
    for nm, tc in bone_names[2::3]:
        _, p, tg, nrm, side = frame_at(tc)
        q = p + nrm * _dragon_radius(tc)
        q2 = q - tg * 0.25
        print('CUE dragon flame host %s: From %s To %s' % (
            nm, [round(-q.y, 3), round(q.z, 3), round(q.x, 3)], [round(-q2.y, 3), round(q2.z, 3), round(q2.x, 3)]))
    print('CUE dragon swim: lap %.2f studs, %.2f studs/s' % (length, speed))
    print('CUE dragon head host: %s' % [round(-pe.y, 3), round(pe.z, 3), round(pe.x, 3)])


@piece
def celestial_dragon_scripted(k):
    """(The first, scripted head: kept to render the pocket's roaring-dragon flipbook until the
    pocket dragon is a 3D piece.)"""
    """A pearl-white dragon head with gold horns resting past the butt end, glowing blue eyes, an
    open jaw that snaps wider now and then (a roar), gold-edged lips and white fangs, a mane of
    blue energy flames sweeping back; its see-through energy body (two ForceField ribbons with
    a Neon core) coils round the cue from the butt to the shaft."""
    import bmesh
    from mathutils import Vector, Quaternion
    bpy = k.bpy
    k.material('Pearl', 'SmoothPlastic', '#F2EFE8', Reflectance=0.15)
    k.material('Gold', 'Foil', '#D4AF37')
    k.material('Fang', 'SmoothPlastic', '#FFFDF6')
    k.material('Eye', 'Neon', '#7FC8FF')
    k.material('Energy', 'ForceField', '#6FB8FF', Transparency=0.35)
    k.material('Core', 'Neon', '#A8D8FF', Transparency=0.55)
    k.material('Mane', 'Neon', '#9ED0FF', Transparency=0.3)

    # head frame: u forward past the butt (-Y), s to the side (+X), w up (+Z)
    U0, W0 = 7.02, 0.05   # the back of the skull, and how high the head's axis sits

    def H(u, s, w):
        return (s, -(U0 + u), W0 + w)

    k.joint('Head', pivot=H(0.0, 0, 0), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 3.0, 'Period': 3.2},             # breathing nod
        {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 4.0, 'Period': 5.1, 'Phase': 40}])  # a slow look round
    k.joint('Jaw', pivot=H(0.1, 0, -0.03), parent='Head', motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Base': 8.0, 'Amp': 18.0, 'Period': 4.0, 'Shape': 'pulse'}])
    k.joint('Body', pivot=(0, 0, 0))

    def E(u, s, w, along, side, up, rot=None, neg=False):
        # an ellipsoid in head terms: half-extents along the head, to the side, up
        return (H(u, s, w), (side, along, up), rot, neg)
    q_down = Quaternion((1, 0, 0), math.radians(8))
    skull = metaball_mesh(bpy, 'DragonSkull', [
        E(0.10, 0, 0.07, 0.15, 0.11, 0.11),                 # cranium
        E(0.33, 0, 0.03, 0.20, 0.07, 0.06, q_down),         # snout
        E(0.51, 0, 0.035, 0.06, 0.055, 0.05),               # nose
        E(0.26, 0.065, 0.10, 0.09, 0.04, 0.035),            # brows
        E(0.26, -0.065, 0.10, 0.09, 0.04, 0.035),
        E(0.15, 0.085, -0.005, 0.09, 0.05, 0.06),           # cheeks
        E(0.15, -0.085, -0.005, 0.09, 0.05, 0.06),
        E(-0.10, 0, 0.0, 0.16, 0.09, 0.09),                 # neck into the cue
        E(0.345, 0.075, 0.075, 0.03, 0.028, 0.025, None, True),   # eye sockets
        E(0.345, -0.075, 0.075, 0.03, 0.028, 0.025, None, True),
    ], resolution=0.008)
    skull.data.materials.append(k.blender_mat('Pearl'))
    skull.data.materials.append(k.blender_mat('Gold'))

    apply_modifier(bpy, skull, 'DECIMATE', ratio=0.16)
    k.add('Head', skull)

    jaw = metaball_mesh(bpy, 'DragonJaw', [
        E(0.30, 0, -0.065, 0.19, 0.055, 0.03, Quaternion((1, 0, 0), math.radians(-8))),
        E(0.13, 0.055, -0.035, 0.07, 0.035, 0.04),
        E(0.13, -0.055, -0.035, 0.07, 0.035, 0.04),
    ], resolution=0.008)
    jaw.data.materials.append(k.blender_mat('Pearl'))
    jaw.data.materials.append(k.blender_mat('Gold'))
    apply_modifier(bpy, jaw, 'DECIMATE', ratio=0.2)
    k.add('Jaw', jaw)
    # gold lip rims: the upper along the snout's lower edge, the lower along the jaw's top
    bm = bmesh.new()
    for side in (-1, 1):
        sweep(bm, [H(0.12 + 0.4 * t, side * (0.07 - 0.035 * t), -0.018 + 0.012 * t) for t in [i / 11 for i in range(12)]],
              [0.009] * 12, segs=8)
    k.add('Head', k.mesh_object('DragonLipUp', bm, ['Gold']))
    bm = bmesh.new()
    for side in (-1, 1):
        sweep(bm, [H(0.12 + 0.36 * t, side * (0.058 - 0.03 * t), -0.047 - 0.01 * t) for t in [i / 11 for i in range(12)]],
              [0.008] * 12, segs=8)
    k.add('Jaw', k.mesh_object('DragonLipLow', bm, ['Gold']))

    # fangs: cones down from the upper jaw, up from the lower
    bm = bmesh.new()
    for side in (-1, 1):
        for i, (u, ln) in enumerate(((0.47, 0.07), (0.41, 0.045), (0.35, 0.04), (0.29, 0.035))):
            s = side * (0.045 - 0.004 * i)
            top = Vector(H(u, s, -0.025))
            bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.013 - 0.002 * i, radius2=0.0,
                                  depth=ln, matrix=_cone_matrix(top, Vector((0, -0.25, -1)).normalized(), ln))
    fangs = k.mesh_object('DragonFangs', bm, ['Fang'])
    k.add('Head', fangs)
    bm = bmesh.new()
    for side in (-1, 1):
        for i, u in enumerate((0.42, 0.34, 0.26)):
            base = Vector(H(u, side * 0.04, -0.07))
            bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.01, radius2=0.0, depth=0.04,
                                  matrix=_cone_matrix(base, Vector((0, -0.2, 1)).normalized(), 0.04))
    k.add('Jaw', k.mesh_object('DragonFangsLow', bm, ['Fang']))

    # eyes
    bm = bmesh.new()
    for side in (-1, 1):
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.024,
                                  matrix=_scale_at(Vector(H(0.345, side * 0.078, 0.075)), (1.0, 1.25, 0.8)))
    k.add('Head', k.mesh_object('DragonEyes', bm, ['Eye']))

    # horns: two long gold horns sweeping back and up, two short ones below
    bm = bmesh.new()
    for side in (-1, 1):
        for (u0, s0, w0, length, rad, rise, spread) in ((0.2, 0.06, 0.13, 0.55, 0.026, 0.22, 0.10), (0.1, 0.1, 0.06, 0.3, 0.018, 0.08, 0.14)):
            path, radii = [], []
            for i in range(14):
                t = i / 13
                path.append(H(u0 - length * t, side * (s0 + spread * t), w0 + rise * math.sin(t * 1.6) + 0.02 * t))
                radii.append(rad * (1 - t) ** 0.8 + 0.002)
            sweep(bm, path, radii, segs=10, profile=lambda a: 1.0 + 0.12 * math.cos(3 * a))
    horns = k.mesh_object('DragonHorns', bm, ['Gold'])
    k.add('Head', horns)

    # the mane: flame spikes of energy sweeping back from the brow, cheeks and chin
    bm = bmesh.new()
    spikes = [(0.22, 0.0, 0.16, 0.45, 0.2), (0.12, 0.05, 0.15, 0.5, 0.25), (0.12, -0.05, 0.15, 0.5, 0.25),
              (0.05, 0.09, 0.1, 0.55, 0.12), (0.05, -0.09, 0.1, 0.55, 0.12), (0.12, 0.12, 0.0, 0.4, -0.02),
              (0.12, -0.12, 0.0, 0.4, -0.02), (0.02, 0.1, -0.06, 0.45, -0.1), (0.02, -0.1, -0.06, 0.45, -0.1),
              (0.3, 0.05, -0.09, 0.25, -0.12), (0.3, -0.05, -0.09, 0.25, -0.12)]
    for (u0, s0, w0, length, lift) in spikes:
        path, radii = [], []
        length *= 0.7
        for i in range(14):
            t = i / 13
            path.append(H(u0 - length * t, s0 * (1 + 0.7 * t), w0 + lift * 0.8 * t + 0.035 * math.sin(t * math.pi * 1.5)))
            radii.append((0.024 * (1 - t) ** 0.8 + 0.0015, 0.009 * (1 - t) + 0.0015))
        sweep(bm, path, radii, segs=8)
    k.add('Head', k.mesh_object('DragonMane', bm, ['Mane']))
    # whiskers from the snout
    bm = bmesh.new()
    for side in (-1, 1):
        path = [H(0.5 - 0.3 * t, side * (0.05 + 0.2 * t), 0.0 - 0.1 * t + 0.08 * t * t) for t in [i / 15 for i in range(16)]]
        sweep(bm, path, [0.006 * (1 - i / 15) + 0.0015 for i in range(16)], segs=6)
    k.add('Head', k.mesh_object('DragonWhiskers', bm, ['Mane']))

    # the energy body: two flat ribbons coiling round the cue from the neck to the shaft, and a
    # thin glowing core in each (the cue's radius from its profile)
    import cue_common as cc
    env = cc.Envelope(cc.load_shape()[0])
    bm_e, bm_c = bmesh.new(), bmesh.new()
    for ph in (0.0, math.pi):
        path, radii, core = [], [], []
        n = 160
        for i in range(n):
            t = i / (n - 1)
            at = 6.95 - 6.35 * t
            rr = float(env(at)) + 0.045 + 0.02 * math.sin(t * 9)
            ang = ph + 2 * math.pi * 3.2 * t
            path.append((rr * math.sin(ang), -at, rr * math.cos(ang)))
            w = 0.058 * (1 - t) ** 0.6 + 0.01
            radii.append((w, w * 0.35))
            core.append(0.011 * (1 - t) + 0.0025)
        sweep(bm_e, path, radii, segs=10)
        sweep(bm_c, path, core, segs=6)
    k.add('Body', k.mesh_object('DragonBody', bm_e, ['Energy']))
    k.add('Body', k.mesh_object('DragonCore', bm_c, ['Core']))


def _cone_matrix(base, direction, depth):
    """create_cone builds along +Z centred on the origin: move its base to `base` pointing along
    `direction`."""
    from mathutils import Vector, Matrix
    z = Vector((0, 0, 1))
    q = z.rotation_difference(direction)
    return Matrix.Translation(base + direction * depth / 2) @ q.to_matrix().to_4x4()


def _scale_at(centre, scale):
    from mathutils import Matrix
    return Matrix.Translation(centre) @ Matrix.Diagonal(tuple(scale) + (1.0,))


def _dragon_roar(i, n):
    """The pocket finisher's spectral dragon head: it lunges up and forward as its jaw drops
    open in a roar (frames 0-9), holds, and pulls back (10-15)."""
    import numpy as np
    k = i / (n - 1)
    lunge = math.sin(math.pi * min(k / 0.7, 1.0))
    jaw = math.radians(8 + 40 * math.sin(math.pi * min(k / 0.75, 1.0)) ** 0.7)
    pivot_head = np.array([0, -7.02, 0.05])
    pivot_jaw = np.array([0, -7.12, 0.02])

    def about(p, R):
        T = np.eye(4); T[:3, 3] = p
        Ti = np.eye(4); Ti[:3, 3] = -p
        return T @ R @ Ti
    head = about(pivot_head, P._rot((1, 0, 0), math.radians(-38 - 14 * lunge)))
    S = np.eye(4) * (0.85 + 0.2 * lunge); S[3, 3] = 1
    head = about(pivot_head, S) @ head
    jaw_m = head @ about(pivot_jaw, P._rot((1, 0, 0), jaw))
    return {'Head': head.tolist(), 'Jaw': jaw_m.tolist()}


P.SPRITES['dragon_roar'] = {'piece': 'celestial_dragon_scripted', 'skin': 'celestial_dragon', 'joints': ['Head', 'Jaw'],
                            'colour': '#8CCBFF', 'rim': 0.3, 'fill': 0.4, 'ortho': 1.4,
                            'cam': ((1.7, -7.4, 0.55), (0, -7.02, 0.33)), 'pose': _dragon_roar}


# =============================================================================================
# Kitsune (M2)
# =============================================================================================

def _surface_ribbon(bm, bvh, centre_fn, path_ua, widths, lift=0.003):
    """A ribbon lying on a sculpt: path_ua is [(u, a_deg)] (along the head and round it from the
    top), each point found by casting a ray at the head's axis; widths per point. Returns
    nothing (adds faces to bm)."""
    from mathutils import Vector
    pts, nrms = [], []
    for u, a in path_ua:
        c = Vector(centre_fn(u))
        d = Vector((math.sin(math.radians(a)), 0.0, math.cos(math.radians(a))))
        hit = bvh.ray_cast(c + d * 0.6, -d)
        if hit[0] is None:
            continue
        pts.append(hit[0])
        nrms.append(hit[1].normalized())
    if len(pts) < 2:
        return
    left, right = [], []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = nrms[i]
        b = t.cross(n).normalized()
        w = widths[min(i, len(widths) - 1)] / 2
        left.append(bm.verts.new(p + n * lift + b * w))
        right.append(bm.verts.new(p + n * lift - b * w))
    for i in range(len(pts) - 1):
        bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))


def _basis_matrix(origin, z_dir, y_hint, scale=(1, 1, 1)):
    """A matrix whose local Z points along z_dir and local Y as near y_hint as it can, scaled."""
    from mathutils import Matrix, Vector
    z = Vector(z_dir).normalized()
    y = Vector(y_hint)
    y = (y - z * z.dot(y)).normalized()
    x = y.cross(z)
    R = Matrix((x, y, z)).transposed().to_4x4()
    return Matrix.Translation(Vector(origin)) @ R @ Matrix.Diagonal(tuple(scale) + (1.0,))


def _hsv(px):
    """HSV (0..1) of an HxWx3 float RGB array."""
    import numpy as np
    mx, mn = px.max(-1), px.min(-1)
    d = mx - mn + 1e-6
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
    return h % 1.0, d / (mx + 1e-6), mx


def _violet_eyes(px):
    """The glowing violet of the fox mask's eyes."""
    import numpy as np
    h, s_, v = _hsv(px)
    return (np.clip((s_ - 0.3) / 0.2, 0, 1) * np.clip((v - 0.35) / 0.2, 0, 1)
            * ((h > 0.72) & (h < 0.93)))


@piece
def kitsune(k):
    """The white porcelain spirit-fox mask on the butt end, looking out past it: a generated model
    (Meshy, from a clean render of the concept; assets/cue/models/fox_mask) with its own colour,
    normal, roughness and metal maps: crimson flame markings, gold trim, a crimson forehead gem,
    crimson inner ears, a crimson neck sleeve ending in an engraved gold collar that fits over the
    butt, and violet eyes that glow (an emissive mask picked from the colour map). The whole mask
    tilts slowly. (Its nine foxfire tails are Beams in the skin's VFX.)"""
    import numpy as np
    from mathutils import Matrix
    U0 = 7.0
    # the collar just wider than the butt: 0.23 on the 0.2 cue, 0.35 on the 0.32 one (2026-10-01);
    # MS scales the hand-placed ear and jaw points with it, about the collar's back (A)
    COLLAR = 0.35
    MS = COLLAR / 0.23
    A = -(U0 - 0.05)

    def m(x, y, z):
        return (x * MS, A + (y - A) * MS, z * MS)

    def my(y):
        return A + (y - A) * MS

    def place(ob):
        V = np.array([v.co[:] for v in ob.data.vertices])
        ymin, ymax = V[:, 1].min(), V[:, 1].max()
        ring = V[V[:, 1] > ymax - 0.04 * (ymax - ymin)]     # the collar at the back of the neck
        cx = (ring[:, 0].max() + ring[:, 0].min()) / 2
        cz = (ring[:, 2].max() + ring[:, 2].min()) / 2
        s = COLLAR / max(np.ptp(ring[:, 0]), np.ptp(ring[:, 2]))
        # the face looks out past the butt (-Y); the collar sleeves 0.05 studs over the butt end
        return Matrix.Translation((0, -(U0 - 0.05), 0)) @ Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -ymax, -cz))

    k.joint('Mask', pivot=(0, -U0, 0), motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 3.0, 'Period': 4.4},             # a slow head tilt
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 2.0, 'Period': 3.1, 'Phase': 70}])
    # rigged (designer, 2026-09-30): the ears twitch now and then, the jaw opens a little;
    # drawn as a spirit of violet light (see-through, glowing, in a shimmer)
    for side, sname in ((1, 'Right'), (-1, 'Left')):
        k.joint('Ear' + sname, pivot=m(0.07 * side, -7.28, 0.07), parent='Mask', motion=[
            {'Kind': 'Hinge', 'Axis': (0, side, 0), 'Amp': 14.0, 'Period': 2.6, 'Phase': 0 if side > 0 else 150,
             'Shape': 'pulse'}])
    k.joint('Jaw', pivot=m(0, -7.3, -0.12), parent='Mask', motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Base': 5.0, 'Amp': 5.0, 'Period': 3.0}])

    def ear(side):
        return lambda V: ramp(V[:, 2], 0.07 * MS, 0.11 * MS) * ramp(V[:, 0] * side, 0.02 * MS, 0.05 * MS)

    bones = {'EarRight': ear(1), 'EarLeft': ear(-1),
             'Jaw': lambda V: ramp(V[:, 1], my(-7.33), my(-7.4)) * ramp(V[:, 2], -0.13 * MS, -0.17 * MS)}
    k.model('Mask', 'FoxMask', 'fox_mask', place, target_tris=14000, emissive=_violet_eyes,
            emissive_tint='#C070FF', emissive_strength=3.0, bones=bones,
            hologram={'Tint': '#D8B8FF', 'Shell': '#C070FF', 'Strength': 1.6})
    _running_fox(k)


# the spirit fox that runs round the Kitsune cue (designer, 2026-09-30: "a small kitsune model
# constantly running, smooth animations"): where it runs, how big, how fast
FOX_AT = 4.3              # round the forearm, AtStuds
FOX_ORBIT = 0.33          # its paws' distance from the cue's axis, studs
FOX_LEN = 0.8             # nose to the tails' tips, studs
FOX_LAP = 200.0           # degrees a second round the cue (a lap in 1.8 s)
FOX_STRIDE = 0.4          # seconds per gallop stride


def _running_fox(k):
    """A small nine-tailed spirit fox galloping round and round the forearm: a generated model
    (Meshy, from a side-view reference of the kitsune mid-gallop; assets/cue/models/running_fox),
    rigged and drawn as a violet hologram like the pocket spirits. Its paws face the cue and its
    back faces out as it runs its lap (FoxRun, a Spin about the cue's axis); every stride the front
    legs reach and the hind legs drive in turn, the body rises and dips and pitches, the head
    bobs, and the nine tails flow a beat behind. All aura: hidden on the shooter's turn."""
    import numpy as np
    from mathutils import Matrix, Vector
    k.joint('FoxRun', pivot=(0, -FOX_AT, 0), aura=True,
            motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': FOX_LAP}])    # carries the top toward +X
    # the fox's own frame at the top of its lap: nose along +X (the way the spin carries it), back up
    fwd, up = Vector((1, 0, 0)), Vector((0, 0, 1))
    R = Matrix((tuple(fwd.cross(up) * -1), tuple(-fwd), tuple(up))).transposed()
    box = {}

    def place(ob):
        V = np.array([v.co[:] for v in ob.data.vertices])
        lo, hi = V.min(0), V.max(0)
        s_ = FOX_LEN / (hi[1] - lo[1])
        box.update(lo=lo, hi=hi, s=s_)
        # paws (the model's lowest point) at FOX_ORBIT from the axis, centred across and along
        return (Matrix.Translation((0, -FOX_AT, FOX_ORBIT)) @ R.to_4x4() @ Matrix.Scale(s_, 4)
                @ Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2])))

    def norm(V):
        """Cue-frame points -> the model's own box coordinates (y 0 at the nose .. 1 at the tails'
        tips, z 0 at the paws .. 1 at the top), for the bone weights."""
        lo, hi, s_ = box['lo'], box['hi'], box['s']
        loc = (V - np.array((0, -FOX_AT, FOX_ORBIT))) @ np.array(R)
        m = loc / s_ + np.array(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]))
        return (m - lo) / (hi - lo)

    def at(y, z):
        """A point given in box coordinates (along from the nose, up from the paws), in the cue
        frame at the top of the lap (before the model is loaded: its box is fixed)."""
        L, H = FOX_LEN, FOX_LEN * 0.782 / 1.908
        return (Vector((0, -FOX_AT, FOX_ORBIT)) + fwd * (L * (0.5 - y)) + up * (H * z))

    side_ax = tuple(fwd.cross(up))                  # the axis legs and head swing about
    T = FOX_STRIDE
    k.joint('FoxBody', pivot=tuple(at(0.4, 0.4)), parent='FoxRun', aura=True, motion=[
        {'Kind': 'Bob', 'Dir': tuple(up), 'Amp': 0.02, 'Period': T},
        {'Kind': 'Hinge', 'Axis': side_ax, 'Amp': 5.0, 'Period': T, 'Phase': 90}])
    k.joint('FoxFront', pivot=tuple(at(0.22, 0.36)), parent='FoxBody', aura=True, motion=[
        {'Kind': 'Hinge', 'Axis': side_ax, 'Amp': 28.0, 'Period': T}])
    k.joint('FoxHind', pivot=tuple(at(0.47, 0.36)), parent='FoxBody', aura=True, motion=[
        {'Kind': 'Hinge', 'Axis': side_ax, 'Amp': 28.0, 'Period': T, 'Phase': 180}])
    k.joint('FoxHead', pivot=tuple(at(0.24, 0.55)), parent='FoxBody', aura=True, motion=[
        {'Kind': 'Hinge', 'Axis': side_ax, 'Amp': 6.0, 'Period': T, 'Phase': 60}])
    k.joint('FoxTails', pivot=tuple(at(0.5, 0.55)), parent='FoxBody', aura=True, motion=[
        {'Kind': 'Hinge', 'Axis': side_ax, 'Amp': 8.0, 'Period': T, 'Phase': 240},
        {'Kind': 'Hinge', 'Axis': tuple(up), 'Amp': 6.0, 'Period': 2 * T, 'Phase': 30}])

    def region(fn):
        return lambda V: (lambda N: fn(N[:, 1], N[:, 2]))(norm(V))

    bones = {'FoxBody': region(lambda y, z: np.ones_like(y)),
             'FoxFront': region(lambda y, z: ramp(z, 0.36, 0.26) * ramp(y, 0.32, 0.26)),
             'FoxHind': region(lambda y, z: ramp(z, 0.3, 0.2) * ramp(y, 0.36, 0.42) * ramp(y, 0.72, 0.66)),
             'FoxHead': region(lambda y, z: ramp(y, 0.3, 0.22) * ramp(z, 0.4, 0.5)),
             'FoxTails': region(lambda y, z: ramp(y, 0.5, 0.6) * ramp(z, 0.24, 0.34))}
    k.model('FoxRun', 'RunningFox', 'running_fox', place, target_tris=12000, emissive=_violet_eyes,
            emissive_tint='#C070FF', emissive_strength=3.0, bones=bones,
            hologram={'Tint': '#C88CFF', 'Shell': '#F0D0FF', 'Strength': 1.8, 'ShellTris': 5000,
                      'Alpha': (0.12, 0.5)})
    q = at(0.3, 0.6)
    print('CUE fox host: %s' % [round(-q.y, 3), round(q.z, 3), round(q.x, 3)])


@piece
def kitsune_scripted(k):
    """(The first, scripted mask: kept to render the pocket's fox-spirit flipbook until the pocket
    fox is a 3D piece.) A white porcelain spirit-fox mask on the butt end, looking out past it: tall pointed ears
    with crimson insides that twitch now and then, violet foxfire eyes, crimson flame markings
    on the brow and cheeks, a gold-framed crimson gem on the forehead, a black nose, a small jaw
    with fangs, gold rims where it meets the cue. (Its nine foxfire tails are Beams in the skin's
    VFX, flowing off the back of the mask.)"""
    import bmesh
    from mathutils import Vector, Quaternion
    from mathutils.bvhtree import BVHTree
    bpy = k.bpy
    k.material('Porcelain', 'SmoothPlastic', '#FAF7F2', Reflectance=0.2)
    k.material('Crimson', 'SmoothPlastic', '#C8102E', Reflectance=0.1)
    k.material('Gold', 'Foil', '#D4AF37')
    k.material('Eye', 'Neon', '#A63CFF')
    k.material('Nose', 'SmoothPlastic', '#141216')
    k.material('Mouth', 'SmoothPlastic', '#3A0A12')
    k.material('Fang', 'SmoothPlastic', '#FFFDF6')

    U0, W0 = 7.0, 0.02

    def H(u, s, w):
        return (s, -(U0 + u), W0 + w)

    def E(u, s, w, along, side, up, rot=None, neg=False):
        return (H(u, s, w), (side, along, up), rot, neg)

    k.joint('Mask', pivot=H(-0.05, 0, 0), motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 3.0, 'Period': 4.4},             # a slow head tilt
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 2.0, 'Period': 3.1, 'Phase': 70}])
    for side, nm, ph in ((1, 'EarR', 0), (-1, 'EarL', 140)):
        k.joint(nm, pivot=H(0.06, side * 0.085, 0.13), parent='Mask', motion=[
            {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': side * 12.0, 'Period': 3.3, 'Phase': ph, 'Shape': 'pulse'}])
    k.joint('Jaw', pivot=H(0.14, 0, -0.05), parent='Mask', motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Base': 4.0, 'Amp': 6.0, 'Period': 5.0, 'Shape': 'pulse', 'Phase': 200}])

    q_dn = Quaternion((1, 0, 0), math.radians(6))
    skull = metaball_mesh(bpy, 'FoxMask', [
        E(0.10, 0, 0.05, 0.13, 0.145, 0.13),            # forehead dome
        E(0.15, 0.075, -0.03, 0.11, 0.07, 0.075),       # cheeks
        E(0.15, -0.075, -0.03, 0.11, 0.07, 0.075),
        E(0.33, 0, -0.01, 0.2, 0.06, 0.055, q_dn),      # snout
        E(0.30, 0, 0.035, 0.14, 0.035, 0.03, q_dn),     # nose bridge
        E(-0.06, 0, 0.0, 0.1, 0.12, 0.12),              # back, into the cue
        E(0.28, 0.068, 0.045, 0.035, 0.022, 0.018, None, True),   # eye sockets
        E(0.28, -0.068, 0.045, 0.035, 0.022, 0.018, None, True),
    ], resolution=0.008)
    apply_modifier(bpy, skull, 'DECIMATE', ratio=0.2)
    skull.data.materials.append(k.blender_mat('Porcelain'))
    k.add('Mask', skull)
    dg = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(skull, dg)

    def centre(u):
        return H(u, 0, 0.0)

    # crimson flame markings on the brow and cheeks, and round the eyes
    bm = bmesh.new()
    for side in (-1, 1):
        for path, w0 in (([(0.32 - 0.26 * t, side * (22 + 55 * t)) for t in [i / 11 for i in range(12)]], 0.03),
                         ([(0.25 - 0.22 * t, side * (10 + 35 * t)) for t in [i / 11 for i in range(12)]], 0.022),
                         ([(0.3 - 0.18 * t, side * (100 + 28 * t)) for t in [i / 9 for i in range(10)]], 0.024),
                         ([(0.24 + 0.08 * math.cos(2 * math.pi * t), side * (68 + 20 * math.sin(2 * math.pi * t))) for t in [i / 20 for i in range(21)]], 0.008)):
            n = len(path)
            widths = [w0 * math.sin(math.pi * (0.15 + 0.85 * i / (n - 1))) ** 0.6 + 0.003 for i in range(n)] if w0 > 0.01 else [w0] * n
            _surface_ribbon(bm, bvh, centre, path, widths)
    red = k.mesh_object('FoxMarks', bm, ['Crimson'], smooth=True)
    apply_modifier(bpy, red, 'SOLIDIFY', thickness=0.003, offset=-1.0)
    k.add('Mask', red)

    # the forehead gem: a gold diamond frame round a crimson gem
    hit = bvh.ray_cast(Vector(centre(0.17)) + Vector((0, 0, 0.6)), Vector((0, 0, -1)))
    top = hit[0] + hit[1] * 0.004
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0,
                               matrix=_basis_matrix(top, hit[1], (0, -1, 0), (0.028, 0.05, 0.012)))
    k.add('Mask', k.mesh_object('FoxGemFrame', bm, ['Gold'], smooth=False))
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0,
                               matrix=_basis_matrix(top + hit[1] * 0.006, hit[1], (0, -1, 0), (0.016, 0.032, 0.01)))
    k.add('Mask', k.mesh_object('FoxGem', bm, ['Crimson'], smooth=False))

    # eyes: slanted almonds of violet foxfire
    bm = bmesh.new()
    for side in (-1, 1):
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=1.0,
                                  matrix=_basis_matrix(Vector(H(0.285, side * 0.07, 0.047)), (side * 0.9, -0.2, 0.4), (0, -1, 0.35 * side),
                                                       (0.014, 0.036, 0.012)))
    k.add('Mask', k.mesh_object('FoxEyes', bm, ['Eye']))
    # nose
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=1.0, matrix=_scale_at(Vector(H(0.525, 0, 0.005)), (0.024, 0.018, 0.016)))
    k.add('Mask', k.mesh_object('FoxNose', bm, ['Nose']))

    # ears: flattened cones, crimson inside
    for side, nm in ((1, 'EarR'), (-1, 'EarL')):
        base = Vector(H(0.06, side * 0.085, 0.1))
        d = Vector((side * 0.32, 0.22, 1.0)).normalized()   # up, out and a little back
        fwd = (0, -1, 0)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=1.0, radius2=0.0, depth=1.0,
                              matrix=_basis_matrix(base + d * 0.11, d, fwd, (0.065, 0.028, 0.22)))
        ear = k.mesh_object('Fox' + nm, bm, ['Porcelain'])
        k.add(nm, ear)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=1.0, radius2=0.0, depth=1.0,
                              matrix=_basis_matrix(base + d * 0.1 + Vector((0, -0.016, 0)), d, fwd, (0.042, 0.016, 0.17)))
        k.add(nm, k.mesh_object('Fox' + nm + 'In', bm, ['Crimson']))
        bm = bmesh.new()
        sweep(bm, [base + d * (0.005 + 0.2 * t) + Vector((side * 0.052 * (1 - t), -0.004, 0)) for t in [i / 8 for i in range(9)]],
              [0.004] * 9, segs=6)
        sweep(bm, [base + d * (0.005 + 0.2 * t) + Vector((-side * 0.052 * (1 - t), -0.004, 0)) for t in [i / 8 for i in range(9)]],
              [0.004] * 9, segs=6)
        k.add(nm, k.mesh_object('Fox' + nm + 'Rim', bm, ['Gold']))

    # the jaw: a dark mouth with a gold edge and small fangs
    jaw = metaball_mesh(bpy, 'FoxJaw', [E(0.3, 0, -0.065, 0.15, 0.045, 0.025, Quaternion((1, 0, 0), math.radians(-6))),
                                         E(0.18, 0, -0.06, 0.08, 0.06, 0.03)], resolution=0.008)
    apply_modifier(bpy, jaw, 'DECIMATE', ratio=0.25)
    jaw.data.materials.append(k.blender_mat('Mouth'))
    k.add('Jaw', jaw)
    bm = bmesh.new()
    for side in (-1, 1):
        for i, u in enumerate((0.42, 0.35)):
            bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.008, radius2=0.0, depth=0.03,
                                  matrix=_cone_matrix(Vector(H(u, side * 0.032, -0.04)), Vector((0, -0.2, -1)).normalized(), 0.03))
    k.add('Mask', k.mesh_object('FoxFangs', bm, ['Fang']))

    # gold rims: a double collar where the mask meets the cue
    bm = bmesh.new()
    for u, rad, tube in ((-0.13, 0.104, 0.012), (-0.155, 0.104, 0.007)):
        path = [H(u, rad * math.sin(2 * math.pi * i / 48), rad * math.cos(2 * math.pi * i / 48) - W0) for i in range(49)]
        sweep(bm, path, [tube] * 49, segs=8, cap=False)
    k.add('Mask', k.mesh_object('FoxRims', bm, ['Gold']))


def _fox_rise(i, n):
    """The pocket finisher's fox spirit: the mask rises tilted up toward the camera, ears flicking,
    jaw parting, then settles (a loop-free 16 frames)."""
    import numpy as np
    k = i / (n - 1)
    up = math.sin(math.pi * min(k / 0.6, 1.0))
    piv = np.array([0, -7.0, 0.02])

    def about(p, R):
        T = np.eye(4); T[:3, 3] = p
        Ti = np.eye(4); Ti[:3, 3] = -p
        return T @ R @ Ti
    mask = about(piv, P._rot((1, 0, 0), math.radians(-30 - 12 * up)) @ P._rot((0, 1, 0), math.radians(8 * math.sin(k * 6))))
    ears = {}
    for side, nm in ((1, 'EarR'), (-1, 'EarL')):
        ep = np.array([side * 0.085, -7.06, 0.15])
        ears[nm] = (mask @ about(ep, P._rot((0, 1, 0), math.radians(side * 14 * math.sin(k * 12))))).tolist()
    jaw = mask @ about(np.array([0, -7.14, -0.03]), P._rot((1, 0, 0), math.radians(6 + 14 * up)))
    out = {'Mask': mask.tolist(), 'Jaw': jaw.tolist()}
    out.update(ears)
    return out


P.SPRITES['fox_spirit'] = {'piece': 'kitsune_scripted', 'skin': 'kitsune', 'joints': ['Mask', 'EarL', 'EarR', 'Jaw'],
                           'colour': '#D08CFF', 'rim': 0.25, 'fill': 0.22, 'ortho': 0.88,
                           'cam': ((1.0, -8.1, 0.45), (0, -7.22, 0.2)), 'pose': _fox_rise, 'drop': ('Mask_Gold',)}


# =============================================================================================
# Apex (M3)
# =============================================================================================

def _frustum(bm, centre, z_dir, y_hint, w, th, length, taper=1.0):
    """A bevel-ready box along z_dir (w across, th thick along y_hint, `length` long), its far
    end scaled by `taper`."""
    from mathutils import Matrix
    import bmesh
    M = _basis_matrix(centre, z_dir, y_hint, (w, th, length)) @ Matrix.Rotation(math.radians(45), 4, 'Z')
    bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=math.sqrt(0.5), radius2=math.sqrt(0.5) * taper,
                          depth=1.0, matrix=M)


def _bevel(bpy, ob, width=0.004, segments=2):
    apply_modifier(bpy, ob, 'BEVEL', width=width, segments=segments, limit_method='ANGLE')
    return ob


@piece
def apex(k):
    """A robotic claw arm on the butt end: a gunmetal housing with orange armour plates and cyan
    light slots, three thruster vents at its back, a cyan lens core in a spinning bezel at its
    front, and three two-jointed claws (orange armoured, steel talons with cyan edges) that flex
    open and snap shut."""
    import bmesh
    from mathutils import Vector
    bpy = k.bpy
    k.material('Gunmetal', 'Metal', '#3A3F47')
    k.material('Dark', 'SmoothPlastic', '#16181C', Reflectance=0.1)
    k.material('Armour', 'SmoothPlastic', '#FF7A1A', Reflectance=0.12)
    k.material('Steel', 'Metal', '#C4CCD6')
    k.material('Cyan', 'Neon', '#19E6FF')
    k.material('Lens', 'Neon', '#8FF6FF')
    k.material('Amber', 'Neon', '#FF8A2A')

    U0 = 7.0
    F = Vector((0, -1, 0))                         # forward, past the butt

    def rad(a):
        return Vector((math.sin(math.radians(a)), 0, math.cos(math.radians(a))))

    def tan(a):                                    # round the cue (the claws' hinge axis)
        return Vector((math.cos(math.radians(a)), 0, -math.sin(math.radians(a))))

    def at(u, r, a):
        return Vector((0, -(U0 + u), 0)) + rad(a) * r

    # the housing: a turned gunmetal body over the end of the cue
    prof = [(-0.15, 0.104), (-0.1, 0.108), (-0.095, 0.121), (-0.02, 0.126), (0.0, 0.13), (0.2, 0.134),
            (0.23, 0.131), (0.255, 0.118), (0.27, 0.1), (0.285, 0.097)]
    k.joint('Housing', pivot=(0, -U0, 0))
    bm = bmesh.new()
    sweep(bm, [(0, -(U0 + u), 0) for u, _ in prof], [r for _, r in prof], segs=40)
    k.add('Housing', k.mesh_object('ApexBody', bm, ['Gunmetal']))

    def r_at(u):
        for (u0, r0), (u1, r1) in zip(prof, prof[1:]):
            if u0 <= u <= u1:
                return r0 + (r1 - r0) * (u - u0) / (u1 - u0)
        return prof[-1][1]

    # armour plates between the claws: hexagonal shells, thick and bevelled
    CLAWS = (0, 120, 240)
    bm = bmesh.new()
    for a in (60, 180, 300):
        rows, cols = 7, 9
        grid = []
        for i in range(rows):
            u = 0.015 + 0.2 * i / (rows - 1)
            half = 40 - 14 * abs(2 * i / (rows - 1) - 1) ** 1.5
            grid.append([bm.verts.new(at(u, r_at(u) + 0.002, a + half * (2 * j / (cols - 1) - 1))) for j in range(cols)])
        for i in range(rows - 1):
            for j in range(cols - 1):
                bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
        # a smaller plate behind it, over the vent
        grid = []
        for i in range(3):
            u = -0.085 + 0.065 * i / 2
            grid.append([bm.verts.new(at(u, 0.123 + 0.002, a + 22 * (2 * j / 4 - 1))) for j in range(5)])
        for i in range(2):
            for j in range(4):
                bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    plates = k.mesh_object('ApexPlates', bm, ['Armour'])
    apply_modifier(bpy, plates, 'SOLIDIFY', thickness=0.014, offset=1.0)
    _bevel(bpy, plates, 0.004, 1)
    k.add('Housing', plates)

    # dark recessed seams and cyan light slots under each claw, amber lights on the plates
    bm = bmesh.new()
    for a in CLAWS:
        _frustum(bm, at(0.1, 0.13, a), F, rad(a), 0.05, 0.012, 0.19)
    seams = _bevel(bpy, k.mesh_object('ApexSeams', bm, ['Dark'], smooth=False), 0.003, 1)
    k.add('Housing', seams)
    bm = bmesh.new()
    for a in CLAWS:
        _frustum(bm, at(0.1, 0.137, a), F, rad(a), 0.022, 0.006, 0.16)
    k.add('Housing', k.mesh_object('ApexSlots', bm, ['Cyan'], smooth=False))
    bm = bmesh.new()
    for a in (60, 180, 300):
        for da in (-24, 24):
            bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=1.0,
                                      matrix=_scale_at(at(0.19, 0.15, a + da), (0.012, 0.012, 0.012)))
    k.add('Housing', k.mesh_object('ApexLights', bm, ['Amber']))
    # a cyan ring where the housing meets the cue
    bm = bmesh.new()
    sweep(bm, [at(-0.097, 0.117, 360 * i / 48) for i in range(49)], [0.008] * 49, segs=8, cap=False)
    k.add('Housing', k.mesh_object('ApexRing', bm, ['Cyan']))

    # thruster vents at the back, angled out and back along the cue; amber glow inside
    bm_n, bm_g = bmesh.new(), bmesh.new()
    for a in (60, 180, 300):
        d = (rad(a) * 0.55 - F * 0.85).normalized()
        base = at(-0.05, 0.1, a)
        bmesh.ops.create_cone(bm_n, cap_ends=True, segments=14, radius1=0.036, radius2=0.03, depth=0.07,
                              matrix=_cone_matrix(base, d, 0.07))
        bmesh.ops.create_cone(bm_g, cap_ends=True, segments=14, radius1=0.022, radius2=0.022, depth=0.004,
                              matrix=_cone_matrix(base + d * 0.069, d, 0.004))
    k.add('Housing', _bevel(bpy, k.mesh_object('ApexVents', bm_n, ['Gunmetal'], smooth=False), 0.004, 1))
    k.add('Housing', k.mesh_object('ApexVentGlow', bm_g, ['Amber'], smooth=False))

    # the front: a gunmetal bezel, a notched ring that turns, the cyan lens
    bm = bmesh.new()
    sweep(bm, [at(0.285, 0.088, 360 * i / 48) for i in range(49)], [0.016] * 49, segs=10, cap=False)
    k.add('Housing', k.mesh_object('ApexBezel', bm, ['Gunmetal']))
    k.joint('Rotor', pivot=(0, -U0, 0), parent='Housing', motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': 50.0}])
    bm = bmesh.new()
    for i in range(10):
        a = 36 * i
        _frustum(bm, at(0.3, 0.08, a), F, rad(a), 0.03, 0.022, 0.02, 0.8)
    k.add('Rotor', _bevel(bpy, k.mesh_object('ApexNotches', bm, ['Dark'], smooth=False), 0.003, 1))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=1.0, matrix=_scale_at(at(0.29, 0, 0), (0.07, 0.026, 0.07)))
    k.add('Housing', k.mesh_object('ApexLens', bm, ['Lens']))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=1.0, matrix=_scale_at(at(0.31, 0, 0), (0.034, 0.02, 0.034)))
    k.add('Housing', k.mesh_object('ApexCore', bm, ['Cyan']))

    # the three claws: a knuckle, an armoured arm, a second knuckle, a curved steel talon
    for n, a in enumerate(CLAWS, 1):
        r_, t_ = rad(a), tan(a)
        K = at(0.235, 0.145, a)
        J2 = K + F * 0.2 + r_ * 0.13
        fname, tname = 'Claw%d' % n, 'Talon%d' % n
        k.joint(fname, pivot=tuple(K), parent='Housing', motion=[
            {'Kind': 'Hinge', 'Axis': tuple(t_), 'Base': 4.0, 'Amp': 12.0, 'Period': 3.0, 'Shape': 'snap'}])
        k.joint(tname, pivot=tuple(J2), parent=fname, motion=[
            {'Kind': 'Hinge', 'Axis': tuple(t_), 'Base': 0.0, 'Amp': 9.0, 'Period': 3.0, 'Phase': 25, 'Shape': 'snap'}])
        d1 = (J2 - K).normalized()
        nrm = t_.cross(d1)
        if nrm.dot(r_) < 0:
            nrm = -nrm
        # knuckles: gunmetal barrels with amber caps
        bm, bm_c = bmesh.new(), bmesh.new()
        for P_, rr in ((K, 0.036), (J2, 0.03)):
            bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=rr, radius2=rr, depth=0.085,
                                  matrix=_cone_matrix(P_ - t_ * 0.0425, t_, 0.085))
            bmesh.ops.create_cone(bm_c, cap_ends=True, segments=12, radius1=rr * 0.5, radius2=rr * 0.5, depth=0.093,
                                  matrix=_cone_matrix(P_ - t_ * 0.0465, t_, 0.093))
        k.add(fname, _bevel(bpy, k.mesh_object(fname + 'Knuckles', bm, ['Gunmetal'], smooth=False), 0.004, 1))
        k.add(fname, k.mesh_object(fname + 'Caps', bm_c, ['Amber'], smooth=False))
        # the arm: a gunmetal strut under an orange armour plate with a cyan slot
        L = (J2 - K).length
        bm = bmesh.new()
        _frustum(bm, (K + J2) / 2, d1, nrm, 0.05, 0.036, L, 0.85)
        k.add(fname, _bevel(bpy, k.mesh_object(fname + 'Strut', bm, ['Gunmetal'], smooth=False)))
        bm = bmesh.new()
        _frustum(bm, (K + J2) / 2 + nrm * 0.026 - d1 * 0.005, d1, nrm, 0.078, 0.022, L * 0.82, 0.72)
        k.add(fname, _bevel(bpy, k.mesh_object(fname + 'Armour', bm, ['Armour'], smooth=False), 0.005))
        bm = bmesh.new()
        _frustum(bm, (K + J2) / 2 + nrm * 0.0375 - d1 * 0.01, d1, nrm, 0.014, 0.004, L * 0.5, 0.7)
        k.add(fname, k.mesh_object(fname + 'Slot', bm, ['Cyan'], smooth=False))

        # the talon: a faceted blade (a diamond section) curving in toward the axis
        steps = 14
        pts, secs = [], []
        for i in range(steps + 1):
            s = i / steps
            pts.append(J2 + F * (0.19 * s) + r_ * (0.04 * s - 0.26 * s ** 1.6))
        blade = bmesh.new()
        armour = bmesh.new()
        edge_pts = []
        rings = []
        for i, p in enumerate(pts):
            s = i / steps
            tg = (pts[min(i + 1, steps)] - pts[max(i - 1, 0)]).normalized()
            m = tg.cross(t_).normalized()          # the talon's back (away from the axis)
            w = 0.05 * (1 - s) ** 0.55 + 0.002
            h = 0.044 * (1 - s) ** 0.7 + 0.002
            rings.append([blade.verts.new(p + t_ * w), blade.verts.new(p + m * h),
                          blade.verts.new(p - t_ * w), blade.verts.new(p - m * h * 1.25)])
            if 0.3 <= s <= 0.93:
                edge_pts.append(p - m * h * 1.25)
            secs.append((p, m, w, h))
        for i in range(steps):
            a_, b_ = rings[i], rings[i + 1]
            for j in range(4):
                blade.faces.new((a_[j], a_[(j + 1) % 4], b_[(j + 1) % 4], b_[j]))
        blade.faces.new(rings[0][::-1])
        blade.faces.new(rings[-1])
        k.add(tname, k.mesh_object(tname + 'Blade', blade, ['Steel'], smooth=False))
        # an orange armour sleeve over the talon's root (a hexagonal section, slightly larger)
        rings = []
        cut = [(p, m, w, h) for (p, m, w, h), i in zip(secs, range(steps + 1)) if i / steps <= 0.58]
        for p, m, w, h in cut:
            rings.append([armour.verts.new(p + t_ * w * 1.25 + m * h * 0.3), armour.verts.new(p + m * h * 1.35),
                          armour.verts.new(p - t_ * w * 1.25 + m * h * 0.3), armour.verts.new(p - t_ * w * 1.1 - m * h * 0.6),
                          armour.verts.new(p + t_ * w * 1.1 - m * h * 0.6)])
        for i in range(len(rings) - 1):
            a_, b_ = rings[i], rings[i + 1]
            for j in range(5):
                armour.faces.new((a_[j], a_[(j + 1) % 5], b_[(j + 1) % 5], b_[j]))
        armour.faces.new(rings[0][::-1])
        armour.faces.new(rings[-1])
        k.add(tname, _bevel(bpy, k.mesh_object(tname + 'Armour', armour, ['Armour'], smooth=False), 0.003, 1))
        bm = bmesh.new()
        sweep(bm, edge_pts, [0.0045 * (1 - 0.6 * i / (len(edge_pts) - 1)) for i in range(len(edge_pts))], segs=6)
        k.add(tname, k.mesh_object(tname + 'Edge', bm, ['Cyan']))
    # modelled on the 0.2 butt: the whole housing and its claws grow with the butt (2026-10-01)
    k.grow((0, -U0, 0), P.butt_growth())


# =============================================================================================
# Eclipse (S1)
# =============================================================================================

@piece
def eclipse(k):
    """A floating total eclipse past the butt: a glossy black sphere (the blazing corona is
    camera-facing particles in the skin's VFX, so it sits on the outline from every side), held by a black-and-gold cup and four slender gold prongs;
    two thin glowing orbit rings precess round it, a small cratered silver moon orbits it,
    obsidian shards drift round the mount."""
    import bmesh
    import random
    from mathutils import Vector, Matrix
    bpy = k.bpy
    k.material('Obsidian', 'SmoothPlastic', '#0B0B0D', Reflectance=0.35)
    k.material('Gold', 'Foil', '#E3A21A')
    k.material('Void', 'SmoothPlastic', '#050505', Reflectance=0.25)
    k.material('Flare', 'Neon', '#FFC940')
    k.material('Moon', 'SmoothPlastic', '#B9BEC6', Reflectance=0.12)

    U0 = 7.0
    RS, UC = 0.36, 0.56                         # the sphere's radius and centre past the butt (0.28 until the
                                                # 2026-09-30 space rework: a bigger, bolder eclipse)

    def rad(a):
        return Vector((math.sin(math.radians(a)), 0, math.cos(math.radians(a))))

    def at(u, r, a):
        return Vector((0, -(U0 + u), 0)) + rad(a) * r

    C = at(UC, 0, 0)

    # the mount: a flared obsidian cup with gold rings, four gold prongs and a cage ring
    k.joint('Mount', pivot=(0, -U0, 0))
    G = P.butt_gain()                           # the cup, rings and prongs sit over the butt (2026-10-01)
    prof = [(u, r + G) for u, r in ((-0.1, 0.104), (-0.06, 0.108), (0.0, 0.114), (0.05, 0.126), (0.09, 0.148),
                                    (0.11, 0.155), (0.115, 0.1))]
    bm = bmesh.new()
    sweep(bm, [(0, -(U0 + u), 0) for u, _ in prof], [r for _, r in prof], segs=40)
    k.add('Mount', k.mesh_object('EclipseCup', bm, ['Obsidian']))
    bm = bmesh.new()
    for u, r, tube in ((-0.085, 0.111, 0.009), (-0.045, 0.114, 0.006), (0.01, 0.12, 0.011), (0.1, 0.156, 0.012)):
        sweep(bm, [at(u, r + G, 360 * i / 56) for i in range(57)], [tube] * 57, segs=10, cap=False)
    for a in (45, 135, 225, 315):
        path, radii = [], []
        for i in range(19):
            s = i / 18
            u = 0.1 + 0.44 * s
            r0 = 0.15 + G
            r = r0 + (max(RS + 0.05, r0) - r0) * math.sin(math.pi / 2 * min(s / 0.75, 1.0)) - 0.03 * max(s - 0.75, 0) / 0.25
            path.append(at(u, r, a + 18 * s))
            radii.append(0.013 * (1 - s) + 0.004)
        sweep(bm, path, radii, segs=10)
    # a thin cage ring round the sphere's back, tying the prongs
    for u, r, tube in ((UC - 0.14, RS + 0.1, 0.006),):
        sweep(bm, [at(u, r, 360 * i / 64) for i in range(65)], [tube] * 65, segs=8, cap=False)
    k.add('Mount', k.mesh_object('EclipseGold', bm, ['Gold']))

    # the eclipse: a black sphere inside two corona shells, floating (a slow bob)
    k.joint('Orb', pivot=tuple(C), parent='Mount', motion=[{'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.012, 'Period': 3.4}])
    for name, mat, r, segs in (('EclipseVoid', 'Void', RS, 48),):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=r, matrix=_scale_at(C, (1, 1, 1)))
        k.add('Orb', k.mesh_object(name, bm, [mat]))

    # two thin gold orbit rings, tilted, precessing
    for n, (tilt, rate, rr) in enumerate(((68, 22.0, RS + 0.2), (-58, -30.0, RS + 0.27)), 1):
        nm = 'Ring%d' % n
        k.joint(nm, pivot=tuple(C), parent='Orb', motion=[{'Kind': 'Spin', 'Axis': (0, 0.25, 1), 'Rate': rate}])
        R = Matrix.Rotation(math.radians(tilt), 3, 'X')
        bm = bmesh.new()
        sweep(bm, [C + R @ Vector((rr * math.cos(2 * math.pi * i / 72), rr * math.sin(2 * math.pi * i / 72), 0)) for i in range(73)],
              [0.004] * 73, segs=6, cap=False)
        k.add(nm, k.mesh_object('Eclipse' + nm, bm, ['Flare']))

    # the moon: a small cratered silver sphere orbiting on a tilted path
    axis = Vector((0.35, 0.2, 1)).normalized()
    k.joint('Moon', pivot=tuple(C), parent='Orb', motion=[{'Kind': 'Spin', 'Axis': tuple(axis), 'Rate': 70.0}])
    side = axis.cross(Vector((0, 1, 0))).normalized()
    M = C + side * (RS + 0.2)
    craters = [(M + Vector(d).normalized() * 0.066, (0.022, 0.022, 0.022), None, True)
               for d in ((1, 0.2, 0.3), (-0.4, 1, 0.5), (0.2, -0.6, 1), (-1, -0.3, -0.2), (0.3, 0.8, -1), (0.9, -0.9, -0.1))]
    moon = metaball_mesh(bpy, 'EclipseMoon', [(M, (0.068, 0.068, 0.068), None, False)] + craters, resolution=0.006)
    moon.data.materials.append(k.blender_mat('Moon'))
    k.add('Moon', moon)

    # obsidian shards drifting round the mount
    k.joint('Debris', pivot=(0, -U0, 0), parent='Mount', motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': 16.0},
                                                               {'Kind': 'Bob', 'Dir': (0, 1, 0), 'Amp': 0.02, 'Period': 2.7}])
    rnd = random.Random(7)
    bm = bmesh.new()
    for i in range(9):
        a = 40 * i + rnd.uniform(-12, 12)
        p = at(rnd.uniform(-0.05, 0.4), rnd.uniform(0.3, 0.46), a)
        geom = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        s = rnd.uniform(0.018, 0.034)
        for v in geom['verts']:
            v.co = Vector((v.co.x * s * rnd.uniform(0.7, 1.3), v.co.y * s * rnd.uniform(1.0, 1.8), v.co.z * s * rnd.uniform(0.6, 1.1)))
            v.co = Matrix.Rotation(rnd.uniform(0, 6.28), 3, 'Z') @ v.co + p
    k.add('Debris', k.mesh_object('EclipseShards', bm, ['Obsidian'], smooth=False))

    # the concept's space round the cue (designer, 2026-09-30: orbital, galaxy vibes, not lightning):
    # gold orbital rings round the cue, tilted every way like an atom's orbits, each precessing
    # slowly with a glowing planet-bead running round it; an asteroid belt of dark rocks orbiting
    # the cue and tumbling
    k.material('OrbitLine', 'Neon', '#FFB84A', Transparency=0.2)
    k.material('OrbitGlow', 'ForceField', '#FFB300')          # a soft glowing sheath round each ring
    k.material('Bead', 'Neon', '#FFE6A0')
    k.material('BeadGlow', 'ForceField', '#FFB300')
    k.material('Rock', 'SmoothPlastic', '#2B2622', Reflectance=0.05)
    orbits = [(1.3, 0.46 + G, 62, 20, 14.0, 150.0), (2.8, 0.62 + G, -55, 110, -11.0, -120.0),
              (4.3, 0.52 + G, 70, 230, 16.0, 135.0), (5.8, 0.7 + G, -64, 320, -9.0, -105.0)]
    for n, (a_, rr, tilt, yaw, prec, run) in enumerate(orbits, 1):
        c = Vector((0, -a_, 0))
        # the ring's normal: tipped `tilt` degrees off the cue's axis, turned `yaw` round it
        nrm = (Matrix.Rotation(math.radians(yaw), 3, 'Y') @ Matrix.Rotation(math.radians(tilt), 3, 'X')
               @ Vector((0, 1, 0))).normalized()
        u = nrm.orthogonal().normalized()
        w = nrm.cross(u)
        ring = [c + (u * math.cos(2 * math.pi * i / 96) + w * math.sin(2 * math.pi * i / 96)) * rr for i in range(97)]
        orb_j, bead_j = 'Orbital%d' % n, 'Planet%d' % n
        k.joint(orb_j, pivot=tuple(c), motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': prec, 'Phase': yaw}])
        for mat, tube, segs in (('OrbitLine', 0.007, 6), ('OrbitGlow', 0.024, 8)):
            bm = bmesh.new()
            sweep(bm, ring, [tube] * len(ring), segs=segs, cap=False)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            k.add(orb_j, k.mesh_object('Eclipse%s%d' % (mat, n), bm, [mat]))
        k.joint(bead_j, pivot=tuple(c), parent=orb_j, motion=[{'Kind': 'Spin', 'Axis': tuple(nrm), 'Rate': run}])
        p0 = ring[0]
        for mat, r_ in (('Bead', 0.03), ('BeadGlow', 0.065)):
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=r_, matrix=Matrix.Translation(p0))
            k.add(bead_j, k.mesh_object('Eclipse%s%d' % (mat, n), bm, [mat]))
    # two huge sweeping loops (designer, 2026-09-30, the concept's long gold orbits round the giant
    # eclipse): ellipses nearly along the cue, the cue running through them, turning slowly round it
    for n, (u0, A, B, tip, roll, prec) in enumerate(((4.2, 3.5, 1.35, 16, 55, 7.0), (4.6, 3.1, 1.1, -12, -65, -5.0)), 1):
        c = Vector((0, -u0, 0))
        d = Matrix.Rotation(math.radians(tip), 3, 'X') @ Vector((0, 1, 0))
        m = Matrix.Rotation(math.radians(roll), 3, d) @ (Matrix.Rotation(math.radians(tip), 3, 'X') @ Vector((0, 0, 1)))
        loop = [c + d * A * math.cos(2 * math.pi * i / 128) + m * B * math.sin(2 * math.pi * i / 128) for i in range(129)]
        j = 'GreatOrbit%d' % n
        k.joint(j, pivot=tuple(c), motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': prec, 'Phase': 90 * n}])
        for mat, tube, segs in (('OrbitLine', 0.009, 6), ('OrbitGlow', 0.03, 8)):
            bm = bmesh.new()
            sweep(bm, loop, [tube] * len(loop), segs=segs, cap=False)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            k.add(j, k.mesh_object('EclipseGreat%s%d' % (mat, n), bm, [mat]))
    rnd = random.Random(23)
    for n in range(1, 11):
        a_ = 0.9 + 6.0 * (n - 0.5) / 10 + rnd.uniform(-0.25, 0.25)
        rr = rnd.uniform(0.5, 0.9)
        ang = rnd.uniform(0, 360)
        c = Vector((rr * math.sin(math.radians(ang)), -a_, rr * math.cos(math.radians(ang))))
        belt, rock = 'Belt%d' % n, 'Asteroid%d' % n
        k.joint(belt, pivot=(0, -a_, 0), motion=[
            {'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': rnd.uniform(14, 26) * (1 if n % 2 else -1)},
            {'Kind': 'Bob', 'Dir': (0, 1, 0), 'Amp': 0.15, 'Period': rnd.uniform(3.5, 5.0), 'Phase': n * 37}])
        k.joint(rock, pivot=tuple(c), parent=belt, motion=[
            {'Kind': 'Spin', 'Axis': (rnd.uniform(-1, 1), rnd.uniform(-1, 1), 1), 'Rate': rnd.uniform(40, 90)}])
        bm = bmesh.new()
        geom = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
        sz = rnd.uniform(0.045, 0.1)
        stretch = Vector((rnd.uniform(0.8, 1.3), rnd.uniform(0.8, 1.4), rnd.uniform(0.6, 1.0)))
        for v in geom['verts']:
            d = v.co.normalized()
            bump = 1 + 0.28 * math.sin(d.x * 5.1 + n) * math.sin(d.y * 4.3 + 2 * n) + 0.12 * math.sin(d.z * 9 + n)
            v.co = c + Vector((d.x * stretch.x, d.y * stretch.y, d.z * stretch.z)) * sz * bump
        k.add(rock, k.mesh_object('EclipseAsteroid%d' % n, bm, ['Rock'], smooth=False))
