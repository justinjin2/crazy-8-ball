"""The Jack-o'-Lantern Cue's body, remade to its concept card (hw-sys lane, coordinator 18:30,
2026-10-28: Justin wants the cues to look like their cards; concept
~/Desktop/8ball-refs/halloween/mocks/v2/C4_jack.jpg). It replaces the first body (Cues A's
`jack_o_lantern` in CuePiecesHalloween_A.py, which no longer runs for this id). Built like the
Witch's Broom (CuePiecesHalloween_B.py): one painted atlas, Cues B's body rules, and the big
signature piece past the butt as an Aim-fade joint (it eases to clear on the owner's own screen
while the stick is drawn for a shot; everyone else sees it whole).

    Blender -b --factory-startup --python-exit-code 1 --python assets/cue/CuePiecesJack.py -- jack_o_lantern

    jack_o_lantern   the body: a dark green tip on a bronze ferrule; a glossy orange shaft with
                     soft wood grain and fine flutes; a chunky green vine spiralling up it with
                     real leaves between the hands; dark wood collars with glowing slits and a
                     bronze band; the carved pumpkin (1.45 across, ten glossy lobes, a glowing
                     face cut through the rind over a flickering core) with big leaves at its
                     base and a curly stem.

Cue frame: X the side, Y from 0 at the tip toward -7 at the butt, Z up (d = -Y).
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from CuePieces import piece  # noqa: E402
import CuePieces  # noqa: E402
import CuePiecesHalloween_B as HB  # noqa: E402  (the atlas, the body rules, the checks and the preview)

PID = 'jack_o_lantern'

# Cues B's rules and checks cover this body too: it is a body, its pumpkin joint fades in the aim
# view, the shaft lathe is the part the hand zones measure.
HB.KIND[PID] = 'body'
HB.AIM[PID] = ['Pumpkin']
HB.BODY_SHAFT[PID] = ('Shaft',)

COL = {
    'orange': '#FF7A1C', 'orange_deep': '#E2600E', 'orange_light': '#FFA44A', 'groove': '#B8460A',
    'gloss': '#FFD9A0', 'rind': '#FF7614', 'rind_deep': '#D2520A', 'rind_light': '#FF9C3A',
    'wood': '#4A2A16', 'wood_dark': '#2A160A', 'wood_light': '#6E4426',
    'bronze': '#9A5F28', 'bronze_dark': '#5A3412', 'bronze_light': '#F2C47E',
    'green': '#3E8E3A', 'green_dark': '#24561F', 'green_light': '#7CC453', 'rib': '#A8DC78',
    'stem': '#4E6E2A', 'stem_dark': '#2E4416', 'stem_light': '#7E9A48',
    'glow': '#FFD45A', 'glow_hot': '#FFF0A0', 'flesh': '#FFA22E', 'core': '#FFB43A',
}

# Where things are (d from the tip).
TIP_END = 0.3          # the tip and ferrule
SHAFT_END = 6.2        # the shaft lathe stops here, under the first collar ring
COLLAR = (6.18, 7.14)  # the collar lathe (its last ring sinks into the pumpkin's flank)
PUMP_C = 7.6           # the pumpkin's centre
PUMP_L = 0.62          # its half length along the cue
PUMP_R = 0.725         # its radius at the equator (1.45 across)
PUMP_Z = 0.08          # raised a little: less of it below the axis (a back's torso)
LOBES = 10
VINE_FROM, VINE_TO, VINE_PITCH = 6.2, 0.78, 0.92   # the vine's run and the d per turn
FACE_ROLL = 62.0       # the face's direction about the cue axis, degrees from +Z toward +X


# =============================================================================================
# Small helpers
# =============================================================================================

def _smoothf(t, a, b):
    t = min(1.0, max(0.0, (t - a) / (b - a)))
    return t * t * (3 - 2 * t)


def _envelope():
    return HB._radius()


def _lathe(bm, uvl, ds, rs, segs, uvf, shape=None, centres=None, close=False, cap_uv=None):
    """Rings along the cue with a real seam at -Z (segs + 1 vertices a ring); loop UV =
    uvf(u, i) for u 0..1 round the ring and ring index i, so a stepped profile maps by its own d."""
    from mathutils import Vector
    rings = []
    for i, (d, r) in enumerate(zip(ds, rs)):
        cx, cz = centres[i] if centres else (0.0, 0.0)
        ring = []
        for k in range(segs + 1):
            a = 2 * math.pi * k / segs
            rr = r * (shape(a, i) if shape else 1.0)
            ring.append(bm.verts.new(Vector((cx + rr * math.sin(a), -d, cz - rr * math.cos(a)))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(segs):
            f = bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
            for lp, (u, ri) in zip(f.loops, ((k / segs, i), ((k + 1) / segs, i), ((k + 1) / segs, i + 1), (k / segs, i + 1))):
                lp[uvl].uv = uvf(u, ri)
    if close:
        for ring, rev, ri in ((rings[0], True, 0), (rings[-1], False, len(rings) - 1)):
            c = sum((x.co for x in ring[:-1]), Vector()) / (len(ring) - 1)
            cv = bm.verts.new(c)
            for k in range(segs):
                q = (ring[k], ring[k + 1], cv)
                f = bm.faces.new(q[::-1] if rev else q)
                for lp in f.loops:
                    lp[uvl].uv = cap_uv if cap_uv else uvf(0.5, ri)
    return rings


def _tube(bm, uvl, pts, radii, minor, uvf, up=(0, 0, 1), cap=True):
    """A tube along a polyline, minor sides, UV uvf(u round, t along 0..1); parallel-transported
    frames so it never twists; capped with a fan at both ends."""
    from mathutils import Vector
    n = len(pts)
    rings = []
    nrm = None
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        if nrm is None:
            u = Vector(up)
            if abs(t.dot(u)) > 0.9:
                u = Vector((1, 0, 0))
            nrm = (u - t * t.dot(u)).normalized()
        else:
            nrm = (nrm - t * t.dot(nrm)).normalized()
        bi = t.cross(nrm)
        ring = [bm.verts.new(p + (nrm * math.cos(2 * math.pi * j / minor) + bi * math.sin(2 * math.pi * j / minor)) * radii[i])
                for j in range(minor + 1)]
        rings.append(ring)
    for i in range(n - 1):
        for j in range(minor):
            f = bm.faces.new((rings[i][j], rings[i + 1][j], rings[i + 1][j + 1], rings[i][j + 1]))
            for lp, (uu, tt) in zip(f.loops, ((j / minor, i / (n - 1)), (j / minor, (i + 1) / (n - 1)),
                                             ((j + 1) / minor, (i + 1) / (n - 1)), ((j + 1) / minor, i / (n - 1)))):
                lp[uvl].uv = uvf(uu, tt)
    if cap:
        for ring, rev, tt, p in ((rings[0], True, 0.0, pts[0]), (rings[-1], False, 1.0, pts[-1])):
            cv = bm.verts.new(p)
            for j in range(minor):
                q = (ring[j], ring[j + 1], cv)
                f = bm.faces.new(q if rev else q[::-1])
                for lp in f.loops:
                    lp[uvl].uv = uvf(0.5, tt)
    return rings


def _leaf(bm, uvl, A, region, base, along, normal, length, width, fold=0.22, droop=0.18, lift=0.25,
          twist=0.0, n=9):
    """A real leaf: an ovate blade with a pointed tip, the two halves folded up along the
    midrib, lifting off its base then drooping toward the tip, double sided (no rim: the
    outline inks its edge). UV u across (0 left edge, 0.5 the midrib, 1 right), v base to tip."""
    from mathutils import Vector, Matrix
    import bmesh
    L = Vector(along).normalized()
    N = Vector(normal)
    N = (N - L * L.dot(N)).normalized()
    if twist:
        N = Matrix.Rotation(math.radians(twist), 3, L) @ N
    S = L.cross(N)
    rows = []
    for i in range(n):
        t = i / (n - 1)
        w = width * 0.5 * (math.sin(math.pi * min(1.0, t ** 0.68)) ** 0.7) * (1 - 0.12 * t)
        if i == n - 1:
            w = 0.0
        mid = Vector(base) + L * (length * t) + N * (length * (lift * t * (1 - t) - droop * t * t))
        row = []
        for s in (-1.0, 0.0, 1.0):
            p = mid + S * (s * w) + N * (fold * abs(s) * w)
            row.append(p)
        rows.append(row)
    vs = [[bm.verts.new(p) for p in row] for row in rows]
    faces = []
    for i in range(n - 1):
        for j in range(2):
            q = (vs[i][j], vs[i][j + 1], vs[i + 1][j + 1], vs[i + 1][j])
            if i == n - 2:
                q = (vs[i][j], vs[i][j + 1], vs[i + 1][1]) if j == 0 else (vs[i][j], vs[i][j + 1], vs[i + 1][1])
                q = tuple(dict.fromkeys(q))
            f = bm.faces.new(q)
            faces.append(f)
            for lp in f.loops:
                # the vertex's place in the grid -> (u, v)
                vi = next((ii, jj) for ii, row in enumerate(vs) for jj, v in enumerate(row) if v is lp.vert)
                lp[uvl].uv = A.uv(region, vi[1] / 2.0, vi[0] / (n - 1))
    ret = bmesh.ops.duplicate(bm, geom=faces)
    bmesh.ops.reverse_faces(bm, faces=[g for g in ret['geom'] if isinstance(g, bmesh.types.BMFace)])
    return faces


# =============================================================================================
# The atlas
# =============================================================================================

def _profile_collar():
    """The collar's stepped profile (d, r): ring 1 dark wood, the slit band, ring 2, the bronze
    band, ring 3 going into the pumpkin's base."""
    return [(6.18, 0.188), (6.215, 0.205), (6.235, 0.242), (6.25, 0.252), (6.35, 0.252), (6.365, 0.238),
            (6.375, 0.226), (6.61, 0.226), (6.62, 0.24), (6.635, 0.268), (6.72, 0.268), (6.73, 0.282),
            (6.74, 0.292), (6.845, 0.292), (6.855, 0.282), (6.865, 0.3), (6.88, 0.31), (7.1, 0.31),
            (7.14, 0.22)]


def jack_atlas(k):
    """Paint and register the body's atlas: SHAFT (the shaft's circumference across, d 0.3 to
    6.2 along), COLLAR (d 6.18 to 7.02 along), RIND (the pumpkin: lobes across, base to stem
    along), GLOW (the carved walls, emissive), LEAF, VINE, STEM, TIP (d 0 to 0.3), BRONZE."""
    import numpy as np
    A = HB.Atlas(PID)
    A.region('SHAFT', 0.0, 0.0, 0.25, 1.0)
    A.region('COLLAR', 0.25, 0.5, 0.5, 1.0)
    A.region('RIND', 0.5, 0.5, 1.0, 1.0)
    A.region('LEAF', 0.25, 0.0, 0.5, 0.25)
    A.region('GLOW', 0.25, 0.25, 0.375, 0.5)
    A.region('BRONZE', 0.375, 0.25, 0.5, 0.5)
    A.region('VINE', 0.5, 0.25, 0.75, 0.5)
    A.region('STEM', 0.75, 0.25, 1.0, 0.5)
    A.region('TIP', 0.5, 0.0, 0.75, 0.25)
    A.region('WOOD', 0.75, 0.0, 1.0, 0.25)
    c = {key: HB._rgb(v) for key, v in COL.items()}
    lerp, sm = HB._lerp, HB._smooth

    # --- SHAFT: glossy orange, soft lengthwise grain, ten fine flutes, a gloss line on top ----
    U, V = A.grid('SHAFT')
    d = TIP_END + V * (SHAFT_END - TIP_END)
    grain = HB._fbm(U * 1.0, V * 0.08, 28.0, octaves=4, seed=11)
    streak = HB._fbm(U * 3.0, V * 0.25, 9.0, octaves=3, seed=4)
    fl = np.abs(np.sin(np.pi * U * 10))
    groove = 1 - sm(fl, 0.0, 0.32)
    col = lerp(c['orange'], c['orange_deep'], np.clip(0.15 + 0.5 * (d / 6.2) * 0.4 + 0.25 * (grain - 0.5), 0, 1))
    col = lerp(col, c['orange_light'], np.clip((streak - 0.55) * 1.6, 0, 1) * 0.45)
    col = lerp(col, c['groove'], groove * 0.55)
    # soft wood-grain lines: thin darker lines running along the cue, wandering a little
    warp = HB._fbm(U * 2.0, V * 0.6, 6.0, octaves=3, seed=7)
    lines = np.abs(np.sin(np.pi * (U * 26 + 1.4 * warp + 0.6 * np.sin(V * 9.0))))
    gl = (1 - sm(lines, 0.0, 0.16)) * (0.55 + 0.45 * streak)
    col = lerp(col, c['orange_deep'], gl * 0.5)
    col = lerp(col, c['groove'], gl * sm(streak, 0.5, 0.8) * 0.3)
    # the gloss: a broad soft sheen on top and a crisp highlight line inside it
    top = np.exp(-((U - 0.5) / 0.11) ** 2)
    col = lerp(col, c['orange_light'], top * 0.45)
    col = lerp(col, c['gloss'], np.exp(-((U - 0.47) / 0.025) ** 2) * 0.7 * (0.75 + 0.25 * streak))
    col = lerp(col, c['orange_deep'], np.exp(-((np.minimum(U, 1 - U)) / 0.12) ** 2) * 0.35)
    h = 0.6 * (1 - groove) + 0.25 * grain - 0.25 * gl
    A.paint('SHAFT', col, height=h, bump=1.4)

    # --- COLLAR: dark wood rings, an orange band with glowing slits, a bronze band ----------
    U, V = A.grid('COLLAR')
    d = COLLAR[0] + V * (COLLAR[1] - COLLAR[0])
    wgrain = HB._fbm(U * 6.0, V * 0.6, 10.0, octaves=4, seed=17)
    wood = lerp(c['wood_dark'], c['wood_light'], np.clip(0.2 + 0.7 * wgrain, 0, 1) ** 1.3)
    ring_light = np.exp(-((U - 0.5) / 0.14) ** 2) * 0.35
    wood = lerp(wood, c['wood_light'], ring_light)
    bronze = lerp(c['bronze_dark'], c['bronze'], 0.5 + 0.5 * np.cos((U - 0.5) * 2 * np.pi))
    bronze = lerp(bronze, c['bronze_light'], np.exp(-((U - 0.5) / 0.08) ** 2) * 0.7)
    band = lerp(c['orange_deep'], c['orange'], 0.5 + 0.5 * np.cos((U - 0.5) * 2 * np.pi))
    col = np.array(wood)
    emi = np.zeros_like(U)
    h = 0.3 * wgrain
    in_band = ((d > 6.37) & (d < 6.61)).astype(np.float32)
    in_bronze = ((d > 6.73) & (d < 6.85)).astype(np.float32)
    in_shaft = (d < 6.225).astype(np.float32)
    col = lerp(col, band, in_band)
    col = lerp(col, bronze, in_bronze)
    col = lerp(col, c['orange'], in_shaft)
    # eight slits round the band, long along the cue, rounded ends
    su = (U * 8) % 1.0
    sx = np.abs(su - 0.5) / 0.16
    sv = np.clip(np.abs(d - 6.49) - 0.055, 0, None) / 0.03
    slit = sm(1 - np.sqrt(sx * sx + sv * sv), 0.0, 0.35) * in_band
    col = lerp(col, c['glow'], slit)
    col = lerp(col, c['glow_hot'], slit * sm(1 - np.sqrt(sx * sx + sv * sv), 0.5, 0.9))
    emi = np.maximum(emi, slit)
    h = h - slit * 0.8
    A.paint('COLLAR', col, height=h, emissive=emi, bump=1.6)

    # --- RIND: ten lobes (creases at u = k/10), a gloss streak on each, darker at both poles ---
    U, V = A.grid('RIND')
    w = (U * LOBES + 0.5) % 1.0
    lobe = np.abs(np.sin(np.pi * w))
    crease = 1 - sm(lobe, 0.0, 0.45)
    mott = HB._fbm(U * 2.0, V, 14.0, octaves=4, seed=23)
    col = lerp(c['rind_deep'], c['rind'], sm(lobe, 0.05, 0.6))
    col = lerp(col, c['rind_light'], np.clip(lobe - 0.55, 0, 1) * 1.2 * (0.6 + 0.4 * mott))
    col = lerp(col, c['groove'], crease * 0.65)
    # the gloss: a soft bright streak a little off each lobe's middle, along the lobe
    g = np.exp(-((w - 0.36) / 0.07) ** 2) * sm(V, 0.18, 0.4) * sm(V, 0.86, 0.62)
    col = lerp(col, c['gloss'], g * 0.75)
    pole = np.maximum(sm(V, 0.22, 0.0), sm(V, 0.8, 1.0))
    col = lerp(col, c['rind_deep'], pole * 0.55)
    col = lerp(col, c['orange_deep'], np.clip(mott - 0.6, 0, 1) * 0.5)
    h = 0.7 * lobe + 0.15 * mott
    A.paint('RIND', col, height=h, bump=0.9)

    # --- GLOW: the carved walls, bright flesh at the rind fading to hot yellow inside --------
    U, V = A.grid('GLOW')
    col = lerp(c['flesh'], c['glow'], sm(V, 0.0, 0.45))
    col = lerp(col, c['glow_hot'], sm(V, 0.55, 1.0))
    A.paint('GLOW', col, emissive=0.35 + 0.65 * sm(V, 0.0, 0.5))

    # --- BRONZE: a polished band (the stem ring, rivets) --------------------------------------
    U, V = A.grid('BRONZE')
    col = lerp(c['bronze_dark'], c['bronze'], 0.5 + 0.5 * np.sin(V * np.pi))
    col = lerp(col, c['bronze_light'], np.exp(-((V - 0.62) / 0.1) ** 2) * 0.8)
    A.paint('BRONZE', col)

    # --- WOOD: dark ring wood (the stem's ring) ------------------------------------------------
    U, V = A.grid('WOOD')
    wg = HB._fbm(U * 4.0, V, 12.0, octaves=4, seed=31)
    col = lerp(c['wood_dark'], c['wood_light'], np.clip(0.15 + 0.75 * wg, 0, 1))
    col = lerp(col, c['wood_light'], np.exp(-((V - 0.65) / 0.12) ** 2) * 0.4)
    A.paint('WOOD', col, height=0.4 * wg)

    # --- LEAF: glossy green, a pale midrib and veins, darker edges ----------------------------
    U, V = A.grid('LEAF')
    across = np.abs(U - 0.5) * 2
    rib = np.exp(-(across / 0.06) ** 2)
    vein = np.clip(1 - np.abs(((V - across * 0.45) * 6.0) % 1.0 - 0.5) / 0.08, 0, 1) * (1 - sm(across, 0.75, 0.95))
    col = lerp(c['green'], c['green_dark'], sm(across, 0.55, 1.0) * 0.8)
    col = lerp(col, c['green_light'], np.exp(-((across - 0.38) / 0.16) ** 2) * 0.45 * sm(V, 0.05, 0.3))
    col = lerp(col, c['rib'], np.maximum(rib, vein * 0.45))
    A.paint('LEAF', col, height=0.6 * rib + 0.3 * vein, bump=1.2)

    # --- VINE: green with a pale stripe on top, a faint twist --------------------------------
    U, V = A.grid('VINE')
    tw = 0.5 + 0.5 * np.sin(2 * np.pi * (U * 2 + V * 14))
    col = lerp(c['green_dark'], c['green'], 0.5 + 0.5 * np.cos((U - 0.5) * 2 * np.pi))
    col = lerp(col, c['green_light'], np.exp(-((U - 0.5) / 0.1) ** 2) * 0.55)
    col = lerp(col, c['green_dark'], tw * 0.18)
    A.paint('VINE', col, height=0.3 * tw)

    # --- STEM: dark green-brown, lengthwise ridges, a paler top ------------------------------
    U, V = A.grid('STEM')
    ridges = 0.5 + 0.5 * np.cos(2 * np.pi * U * 6)
    col = lerp(c['stem_dark'], c['stem'], ridges)
    col = lerp(col, c['stem_light'], np.exp(-((U - 0.5) / 0.12) ** 2) * 0.5)
    col = lerp(col, c['stem_dark'], sm(V, 0.75, 1.0) * 0.5)
    A.paint('STEM', col, height=0.7 * ridges, bump=1.5)

    # --- TIP: the dark green tip on a bronze ferrule (d 0 to 0.3) ----------------------------
    U, V = A.grid('TIP')
    d = V * TIP_END
    sheen = 0.5 + 0.5 * np.cos((U - 0.5) * 2 * np.pi)
    green = lerp(c['green_dark'], c['green'], sheen)
    bronze = lerp(c['bronze_dark'], c['bronze_light'], sheen ** 2)
    col = lerp(green, bronze, sm(d, 0.14, 0.155))
    A.paint('TIP', col)

    A.materials(k, opaque='Jack', emissive_tint='#FFB43A', emissive_strength=1.7, Reflectance=0.06)
    return A


# =============================================================================================
# The body
# =============================================================================================

def _vine_path(R):
    """The vine's centreline: from the collar down to the bridge, VINE_PITCH studs a turn, on the
    shaft's surface; thinner (and flush) in the hand zones. -> [(point, radius, d)]"""
    from mathutils import Vector
    r = HB.RULES
    out = []
    d = VINE_FROM
    while d >= VINE_TO - 1e-6:
        mid = _smoothf(d, r['Bridge'][1], r['Bridge'][1] + 0.3) * _smoothf(d, r['Grip'][0], r['Grip'][0] - 0.3)
        tail = _smoothf(d, VINE_TO, VINE_TO + 0.35)
        # a wide tube sunk into the shaft: in the hand zones it stands out at most 0.034 (the rule
        # is 0.04) yet reads 0.07-0.08 across; between the hands it stands out 0.068
        rv = (min(0.075, 0.5 * R(d)) * (1 - mid) + min(0.08, 0.62 * R(d)) * mid) * (0.4 + 0.6 * tail)
        proud = 0.034 * (1 - mid) + 0.074 * mid
        th = math.pi + 2 * math.pi * (VINE_FROM - d) / VINE_PITCH   # starts on top (+Z: angle pi)
        rho = R(d) + proud - rv
        out.append((Vector((rho * math.sin(th), -d, -rho * math.cos(th))), rv, d, th))
        d -= 0.06
    return out


@piece
def jack_o_lantern(k):
    import bmesh
    from mathutils import Vector
    R = _envelope()
    A = jack_atlas(k)
    k.material('Core', 'Neon', COL['core'])

    # --- the body joint: tip, shaft, collar, vine ---------------------------------------------
    k.joint('Body', pivot=(0, -3.5, 0))

    # the tip: a rounded dark green cap on a bronze ferrule, inside 0.12 across
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    tds = [0.0, 0.004, 0.015, 0.035, 0.1, 0.14, 0.145, 0.155, 0.2, 0.26, 0.3]
    trs = [0.022, 0.034, 0.042, 0.046, 0.048, 0.048, 0.052, 0.054, 0.055, 0.056, R(0.3) + 0.002]
    _lathe(bm, uvl, tds, trs, 16, lambda u, i: A.uv('TIP', u, tds[i] / TIP_END), close=True,
           cap_uv=A.uv('TIP', 0.5, 0.02))
    k.add('Body', k.mesh_object('Tip', bm, ['Jack']))

    # the shaft (the part the hands hold: the envelope + 0.006)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    sds = [TIP_END] + [TIP_END + (SHAFT_END - TIP_END) * (i / 26) ** 1.0 for i in range(1, 27)]
    srs = [R(d) + 0.006 for d in sds]
    srs[0] = R(TIP_END) + 0.002
    _lathe(bm, uvl, sds, srs, 20, lambda u, i: A.uv('SHAFT', u, (sds[i] - TIP_END) / (SHAFT_END - TIP_END)))
    k.add('Body', k.mesh_object('Shaft', bm, ['Jack']))

    # the collar: three dark wood rings, the slit band and the bronze band
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    prof = _profile_collar()
    cds, crs = [p[0] for p in prof], [p[1] for p in prof]
    _lathe(bm, uvl, cds, crs, 24, lambda u, i: A.uv('COLLAR', u, (cds[i] - COLLAR[0]) / (COLLAR[1] - COLLAR[0])), close=True,
           cap_uv=A.uv('COLLAR', 0.5, 0.99))
    k.add('Body', k.mesh_object('Collar', bm, ['Jack']))

    # the vine
    path = _vine_path(R)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    _tube(bm, uvl, [p for p, _, _, _ in path], [rv for _, rv, _, _ in path], 6, lambda u, t: A.uv('VINE', u, t))
    k.add('Body', k.mesh_object('Vine', bm, ['Jack']))

    # --- the leaves on the vine between the hands (joint Leaves: a sway round the shaft) -------
    k.joint('Leaves', pivot=(0, -3.3, 0), parent='Body',
            motion=[{'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 5.0, 'Period': 2.6},
                    {'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.012, 'Period': 1.7, 'Phase': 50}])
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    placed = []
    for want in (2.3, 2.6, 2.9, 3.2, 3.5, 3.8, 4.05, 4.25):
        # the nearest vine point not underneath (no leaf under the shaft: the rails, a back)
        cands = [q for q in path if abs(q[2] - want) < 0.25 and -math.cos(q[3]) > -0.1]
        if not cands:
            continue
        p, rv, d, th = min(cands, key=lambda q: abs(q[2] - want))
        if any(abs(d - x) < 0.2 for x in placed):
            continue
        placed.append(d)
        out = Vector((math.sin(th), 0, -math.cos(th)))
        up = (out + Vector((0, 0, 0.9))).normalized()
        tip_ward = 1 if len(placed) % 2 else -1
        if d > 4.0:
            tip_ward = 1          # never into the grip hand
        if d < 2.5:
            tip_ward = -1         # never into the bridge hand
        along = Vector((0, tip_ward * 0.85, 0)) + up * 0.5
        size = 0.28 + 0.06 * (len(placed) % 2)
        _leaf(bm, uvl, A, 'LEAF', p + out * rv * 0.6, along, up, size, size * 0.66, fold=0.24, droop=0.32, lift=0.5,
              twist=14 * tip_ward)
    k.add('Leaves', k.mesh_object('ShaftLeaves', bm, ['Jack']))

    # --- the pumpkin (joint Pumpkin: Aim fade, a slow wobble) ---------------------------------
    k.joint('Pumpkin', pivot=(0, -COLLAR[1] + 0.02, 0), parent='Body', aim='fade',
            motion=[{'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 1.6, 'Period': 4.0},
                    {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 1.2, 'Period': 5.3, 'Phase': 90}])
    rind = _pumpkin(k, A)
    k.add('Pumpkin', rind)

    # the stem's dark ring and the big leaves at the base ride on the pumpkin
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    top_d = PUMP_C + PUMP_R * PUMP_SB * 0.9
    # the stem's cap: a dark wood ring round the stem's base, standing off the flank (the card's)
    rds = [top_d - 0.05, top_d + 0.005, top_d + 0.02, top_d + 0.06, top_d + 0.075, top_d + 0.08]
    rrs = [0.15, 0.158, 0.16, 0.152, 0.138, 0.118]
    _lathe(bm, uvl, rds, rrs, 18, lambda u, i: A.uv('WOOD', u, i / (len(rds) - 1)), close=True,
           centres=[(0.0, PUMP_Z)] * len(rds), cap_uv=A.uv('WOOD', 0.5, 0.95))
    base_d = COLLAR[1] - 0.03
    for ang, length, width, tw in ((math.pi, 0.7, 0.44, 0), (math.pi - 0.95, 0.64, 0.4, -14), (math.pi + 0.95, 0.66, 0.41, 16),
                                   (math.pi - 1.8, 0.5, 0.32, -22), (math.pi + 1.75, 0.52, 0.33, 22)):
        out = Vector((math.sin(ang), 0, -math.cos(ang)))
        base = Vector((0, -base_d, PUMP_Z * 0.5)) + out * 0.27
        along = Vector((0, 0.95, 0)) + out * 0.42
        _leaf(bm, uvl, A, 'LEAF', base, along, out, length, width, fold=0.22, droop=0.42, lift=0.55, twist=tw, n=10)
    k.add('Pumpkin', k.mesh_object('Fronds', bm, ['Jack']))

    # the core: a flickering Neon ellipsoid inside the rind, seen through the carved face
    k.joint('Core', pivot=(0, -PUMP_C, PUMP_Z), parent='Pumpkin',
            visual=[{'Kind': 'Glow', 'Min': 0.2, 'Max': 0.75, 'Period': 0.55, 'Shape': 'flicker', 'Color': '#FFC040'}])
    bm = bmesh.new()
    nr, ns = 10, 18
    rings = [[bm.verts.new(_pump_point(0.08 + (math.pi - 0.16) * i / nr, 2 * math.pi * j / ns, 0.85, False)) for j in range(ns)]
             for i in range(nr + 1)]
    C = Vector((0, -PUMP_C, PUMP_Z))

    def outward(vs):
        cen = sum((v.co for v in vs), Vector()) / len(vs)
        nrm = (vs[1].co - vs[0].co).cross(vs[2].co - vs[1].co)
        return vs if nrm.dot(cen - C) > 0 else vs[::-1]
    for i in range(nr):
        for j in range(ns):
            bm.faces.new(outward([rings[i][j], rings[i][(j + 1) % ns], rings[i + 1][(j + 1) % ns], rings[i + 1][j]]))
    for ring, th in ((rings[0], 0.0), (rings[-1], math.pi)):
        cv = bm.verts.new(_pump_point(th, 0.0, 0.85, False))
        for j in range(ns):
            bm.faces.new(outward([ring[j], ring[(j + 1) % ns], cv]))
    k.add('Core', k.mesh_object('CoreGlow', bm, ['Core']))

    # the curly stem (joint Stem: a quick sway)
    k.joint('Stem', pivot=(0, -top_d, PUMP_Z), parent='Pumpkin',
            motion=[{'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 5.0, 'Period': 1.6, 'Phase': 30}])
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    ctrl = [(top_d - 0.06, 0.0), (top_d + 0.08, 0.02), (top_d + 0.18, 0.1), (top_d + 0.24, 0.24), (top_d + 0.23, 0.38),
            (top_d + 0.15, 0.47), (top_d + 0.05, 0.46), (top_d + 0.0, 0.38), (top_d + 0.04, 0.31), (top_d + 0.11, 0.33)]
    pts = _catmull([Vector((0, -dd, PUMP_Z + zz)) for dd, zz in ctrl], 6)
    rads = [0.105 * (1 - 0.62 * (i / (len(pts) - 1)) ** 0.9) for i in range(len(pts))]
    _tube(bm, uvl, pts, rads, 8, lambda u, t: A.uv('STEM', u, t), up=(1, 0, 0))
    k.add('Stem', k.mesh_object('StemCurl', bm, ['Jack']))
    print('CUE jack: pumpkin d %.2f..%.2f across %.2f, stem to d %.2f, vine %d points, %d shaft leaves'
          % (PUMP_C - PUMP_R * PUMP_SB, PUMP_C + PUMP_R * PUMP_SB, 2 * PUMP_R, max(-p.y for p in pts), len(path), len(placed)))


def _catmull(points, per):
    """A Catmull-Rom curve through the points, `per` samples a span."""
    from mathutils import Vector
    P = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for s in range(per):
            t = s / per
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
                              (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    out.append(Vector(points[-1]))
    return out


# =============================================================================================
# The carved pumpkin
# =============================================================================================

PUMP_H = 0.6           # the pumpkin's half height along the face's up (its stalk axis on the card)
PUMP_SB = 0.86         # its depth along the cue, a share of PUMP_R (the stem end to the collar)


def _pump_point(th, ps, scale=1.0, lobed=True):
    """The pumpkin's surface, drawn as on the card: its ribs run up and down the face (round the
    face's up axis `a`), th 0 at the bottom pole to pi at the top, ps round that axis from the
    back (ps 0 is behind the face; pi is the face's middle). The cue runs through its sides: the
    collar goes in on the tip side, the curly stem comes out on the butt side. Ten lobes, a lobe
    in the face's middle, dimpled at both poles, squat."""
    n, a, b = _face_frame()
    from mathutils import Vector
    psi = ps - math.pi                       # 0 at the face's middle
    s = (0.925 + 0.075 * abs(math.cos(LOBES * psi / 2)) ** 0.55) if lobed else 1.0
    rho = PUMP_R * scale * (math.sin(th) ** 0.82) * s
    y = -PUMP_H * scale * math.cos(th)
    y += 0.11 * scale * math.exp(-(th / 0.5) ** 2) - 0.12 * scale * math.exp(-((math.pi - th) / 0.5) ** 2)
    C = Vector((0, -PUMP_C, PUMP_Z))
    return C + a * y + (n * math.cos(psi) + b * (math.sin(psi) * PUMP_SB)) * rho


def _face_frame():
    from mathutils import Vector
    rho = math.radians(FACE_ROLL)
    n = Vector((math.sin(rho), 0, math.cos(rho)))     # where the face looks
    a = Vector((-math.cos(rho), 0, math.sin(rho)))    # the face's up
    b = Vector((0, -1, 0))                            # across the face, along the cue
    return n, a, b


def _face_shapes():
    """The carved face in units of PUMP_R: (b across, a up). Two slanted eyes, a wide grin with
    two teeth hanging from its top and one standing in its bottom."""
    eye_r = [(0.08, 0.08), (0.47, 0.13), (0.38, 0.47)]
    eye_l = [(-x, y) for x, y in eye_r][::-1]
    W = 0.58
    top, bot = [], []
    n = 14
    for i in range(n + 1):
        b = -W + 2 * W * i / n
        f = (b / W) ** 2
        top.append((b, -0.15 + 0.2 * f))
        bot.append((b, -0.2 - 0.33 * (1 - f) + 0.2 * f))
    teeth_top = ((-0.26, 0.13, 0.15), (0.26, 0.13, 0.15))   # (centre, width, depth)
    tooth_bot = (0.0, 0.15, 0.14)
    mouth = []
    for b, a in top:
        mouth.append((b, a))
    # notch the top edge with the teeth (walk the top again and cut squares down into the mouth)
    poly = []
    for (b, a) in top:
        poly.append((b, a))
    poly = _notch(poly, teeth_top, down=True)
    lower = _notch(list(reversed(bot[1:-1])), (tooth_bot,), down=False)
    shapes = [eye_l, eye_r, poly + lower]

    def area(pts):
        return sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1])) / 2
    # one winding for all (the boolean needs every cutter outward): the grin's, clockwise
    return [sh if area(sh) < 0 else sh[::-1] for sh in shapes]


def _notch(edge, teeth, down):
    """Insert square teeth into a polyline edge: each (centre b, width, depth) replaces the
    edge's points within the width by a step down (or up) of `depth`."""
    out = list(edge)
    for cb, w, dep in teeth:
        b0, b1 = cb - w / 2, cb + w / 2

        def a_at(b):
            for (x0, y0), (x1, y1) in zip(out, out[1:]):
                if min(x0, x1) <= b <= max(x0, x1) and x1 != x0:
                    return y0 + (y1 - y0) * (b - x0) / (x1 - x0)
            return out[0][1]
        a0, a1 = a_at(b0), a_at(b1)
        s = -1 if down else 1
        tooth = [(b0, a0), (b0, a0 + s * dep), (b1, a1 + s * dep), (b1, a1)]
        if out[0][0] > out[-1][0]:
            tooth = tooth[::-1]
        keep_lo = [p for p in out if (p[0] < b0 if out[0][0] < out[-1][0] else p[0] > b1)]
        keep_hi = [p for p in out if (p[0] > b1 if out[0][0] < out[-1][0] else p[0] < b0)]
        out = keep_lo + tooth + keep_hi
    return out


def _pumpkin(k, A, nr=22, ns=50, inner=(14, 24), keep_inner=False, name='Rind'):
    """The rind: the lobed outer skin and a smooth inner skin as one hollow solid, the face cut
    through it with an exact boolean (the cutter's walls keep its GLOW UVs), then the inner skin
    deleted (the core fills it), or kept (keep_inner: a mini jack, whose glowing inner skin shows
    through the face instead of a Neon core). One object, material Jack."""
    import bmesh
    bpy = k.bpy
    NR, NS = nr, ns
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    mat_l = bm.faces.layers.int.new('jack_tag')   # 0 outer, 1 inner, 2 wall
    eps = 0.06

    from mathutils import Vector
    C = Vector((0, -PUMP_C, PUMP_Z))

    def face(vs, tag, inward, uvs):
        cen = sum((v.co for v in vs), Vector()) / len(vs)
        nrm = (vs[1].co - vs[0].co).cross(vs[2].co - vs[1].co)
        if nrm.length < 1e-12 and len(vs) > 3:
            nrm = (vs[2].co - vs[1].co).cross(vs[3].co - vs[2].co)
        out = nrm.dot(cen - C) > 0
        if out == inward:
            vs, uvs = vs[::-1], uvs[::-1]
        f = bm.faces.new(vs)
        f[mat_l] = tag
        for lp, uv in zip(f.loops, uvs):
            lp[uvl].uv = uv
        return f

    def skin(scale, lobed, nr, ns, tag, inward):
        rings = []
        for i in range(nr + 1):
            th = eps + (math.pi - 2 * eps) * i / nr
            rings.append([bm.verts.new(_pump_point(th, 2 * math.pi * j / ns, scale, lobed)) for j in range(ns + 1)])

        def uv(i, j):
            return A.uv('RIND', j / ns, i / nr) if tag == 0 else A.uv('GLOW', 0.5, 0.95)
        for i in range(nr):
            for j in range(ns):
                face([rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j]], tag, inward,
                     [uv(i, j), uv(i, j + 1), uv(i + 1, j + 1), uv(i + 1, j)])
        for ring, th, vv in ((rings[0], 0.0, 0.0), (rings[-1], math.pi, 1.0)):
            cv = bm.verts.new(_pump_point(th, 0.0, scale, lobed))
            for j in range(ns):
                cuv = A.uv('RIND', (j + 0.5) / ns, vv) if tag == 0 else A.uv('GLOW', 0.5, 0.95)
                face([ring[j], ring[j + 1], cv], tag, inward, [uv(0 if vv == 0 else nr, j), uv(0 if vv == 0 else nr, j + 1), cuv])
    # the seam vertices at j = 0 and j = ns coincide: weld them after, keeping the UV seam
    skin(1.0, True, NR, NS, 0, False)
    skin(0.87, False, inner[0], inner[1], 1, True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)

    # the cutter: each face shape as a prism along the face's direction
    cb = bmesh.new()
    cuv = cb.loops.layers.uv.new('UVMap')
    ctag = cb.faces.layers.int.new('jack_tag')
    n, a, b = _face_frame()
    from mathutils import Vector
    C = Vector((0, -PUMP_C, PUMP_Z))
    for shape in _face_shapes():
        inner = [cb.verts.new(C + n * (PUMP_R * 0.35) + b * (x * PUMP_R) + a * (y * PUMP_R)) for x, y in shape]
        outer = [cb.verts.new(C + n * (PUMP_R * 1.35) + b * (x * PUMP_R) + a * (y * PUMP_R)) for x, y in shape]
        m = len(shape)
        per = [0.0]
        for i in range(m):
            p, q = shape[i], shape[(i + 1) % m]
            per.append(per[-1] + math.hypot(q[0] - p[0], q[1] - p[1]))
        for i in range(m):
            j = (i + 1) % m
            f = cb.faces.new((inner[i], inner[j], outer[j], outer[i]))
            f[ctag] = 2
            for lp, (uu, vv) in zip(f.loops, ((per[i], 1.0), (per[i + 1], 1.0), (per[i + 1], 0.0), (per[i], 0.0))):
                lp[cuv].uv = A.uv('GLOW', (uu / per[-1]) % 1.0, vv)
        for ring, rev in ((inner, True), (outer, False)):
            f = cb.faces.new(ring[::-1] if rev else ring)
            f[ctag] = 2
            for lp in f.loops:
                lp[cuv].uv = A.uv('GLOW', 0.5, 0.95)
    cme = bpy.data.meshes.new('Cutter')
    cb.to_mesh(cme)
    cb.free()
    cutter = bpy.data.objects.new('Cutter', cme)
    bpy.context.scene.collection.objects.link(cutter)
    CuePieces.apply_modifier(bpy, ob, 'BOOLEAN', operation='DIFFERENCE', object=cutter, solver='EXACT')
    bpy.data.objects.remove(cutter)

    # the inner skin goes (the core fills the rind; only the carved walls show inside)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    tag = bm.faces.layers.int.get('jack_tag')
    gone = [f for f in bm.faces if tag is not None and f[tag] == 1 and not keep_inner]
    bmesh.ops.delete(bm, geom=gone, context='FACES')
    bm.to_mesh(ob.data)
    bm.free()
    if 'jack_tag' in ob.data.attributes:
        ob.data.attributes.remove(ob.data.attributes['jack_tag'])
    ob.data.materials.clear()
    ob.data.materials.append(k.blender_mat('Jack'))
    for p in ob.data.polygons:
        p.use_smooth = True
        p.material_index = 0
    print('CUE jack: %s %d faces after the carve (%d inner removed)' % (name, len(ob.data.polygons), len(gone)))
    return ob


# =============================================================================================
# The floating mini jacks (the decor piece jack_o_lantern_jacks)
# =============================================================================================

JACKS_PID = 'jack_o_lantern_jacks'
# (name, d, side X, up Z, scale of the big pumpkin, yaw of the face from +X toward the tip, low)
# (name, d, side X, up Z, scale of the big pumpkin, yaw of the face from +X toward the tip, low,
# spin in degrees a second: each turns slowly round its own stem so its face comes round to
# every side, never parked in front of the big face)
MINI_JACKS = (('Jack1', 3.5, 0.3, 0.56, 0.22, 20, 'hide', 34),
              ('Jack2', 6.55, -0.42, 0.66, 0.22, 165, None, -41),
              ('Jack3', 7.45, -0.15, 0.86, 0.24, 120, None, 29),
              ('Jack4', 8.2, -0.5, 0.62, 0.22, 230, 'hide', -37))


def _mini_jack(k, A, centre, yaw, scale, name):
    """A loose mini jack-o'-lantern (C4's floating jacks; no flat cards, the coordinator 19:08):
    the cue's carved pumpkin built low-poly with its inner skin kept glowing (the atlas GLOW, so
    no Neon core and one part), a short stem curling off the top, stood upright with its face
    toward +X turned by `yaw` (degrees, + toward the tip), scaled and moved to `centre`."""
    import bmesh
    from mathutils import Matrix, Vector
    ob = _pumpkin(k, A, nr=9, ns=20, inner=(6, 12), keep_inner=True, name=name)
    n, a, _ = _face_frame()
    C = Vector((0, -PUMP_C, PUMP_Z))
    across = a.cross(n).normalized()
    ctrl = [C + a * u + across * w for u, w in
            ((0.36, 0.0), (0.52, 0.01), (0.64, 0.05), (0.72, 0.13), (0.73, 0.22), (0.67, 0.28), (0.6, 0.27))]
    pts = _catmull(ctrl, 3)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uvl = bm.loops.layers.uv.active or bm.loops.layers.uv.new('UVMap')
    _tube(bm, uvl, pts, [0.09 - 0.05 * (i / (len(pts) - 1)) ** 1.3 for i in range(len(pts))], 6,
          lambda u, t: A.uv('STEM', u, t), up=tuple(n))
    bm.to_mesh(ob.data)
    bm.free()
    roll = math.atan2(n.z, n.x)        # the face's tilt above +X: stand the jack up
    ob.data.transform(Matrix.Translation(Vector(centre)) @ Matrix.Rotation(math.radians(yaw), 4, 'Z')
                      @ Matrix.Rotation(roll, 4, 'Y') @ Matrix.Scale(scale, 4) @ Matrix.Translation(-C))
    for p in ob.data.polygons:
        p.use_smooth = True
        p.material_index = 0
    return ob


@piece
def jack_o_lantern_jacks(k):
    """Four mini jack-o'-lanterns floating round the back half of the cue and the big pumpkin,
    each its own aura joint bobbing and looking about (C4). Aim joints, so the two past the butt
    may reach 1.5 studs out; Lower effects keeps two. They wear the body's atlas (the same
    uploaded maps: no new texture)."""
    A = jack_atlas(k)
    for i, (name, d, x, z, scale, yaw, low, spin) in enumerate(MINI_JACKS):
        k.joint(name, pivot=(x, -d, z), aura=True, aim='fade', low=low,
                motion=[{'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.05, 'Period': 2.6 + 0.37 * i, 'Phase': 70 * i},
                        {'Kind': 'Spin', 'Axis': (0, 0, 1), 'Rate': spin, 'Phase': 0},
                        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 7.0, 'Period': 3.1 + 0.4 * i, 'Phase': 30 + 50 * i}])
        k.add(name, _mini_jack(k, A, (x, -d, z), yaw, scale, name))


RISE_PID = 'jack_o_lantern_rise'


@piece
def jack_o_lantern_rise(k):
    """The finisher's fiery jack-o'-lantern rising out of the pocket (C4): the cue's own carved
    pumpkin stood up at pocket size, 1.95 studs across, its face toward -Y over a flickering
    Neon core, a curled stem on top, nodding quickly as it laughs and wobbling; three mini jacks
    circle it on one orbit joint (no flat cards, the coordinator 19:08). Pocket frame, upright
    (as cues-a's laughing jack). It wears the body's atlas."""
    from mathutils import Matrix, Vector
    import bmesh
    k.frame = 'pocket'
    k.upright = True
    A = jack_atlas(k)
    k.material('Core', 'Neon', COL['core'])
    n, a, _ = _face_frame()
    C = Vector((0, -PUMP_C, PUMP_Z))
    scale = 1.35
    M = (Matrix.Translation(Vector((0, 0, 1.0))) @ Matrix.Rotation(math.radians(-90), 4, 'Z')
         @ Matrix.Rotation(math.atan2(n.z, n.x), 4, 'Y') @ Matrix.Scale(scale, 4) @ Matrix.Translation(-C))
    k.joint('Head', pivot=(0, 0, 1.0), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Base': 3.0, 'Amp': 4.0, 'Period': 0.3, 'Shape': 'snap'},
        {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 6.0, 'Period': 2.2, 'Phase': 40}])
    rind = _pumpkin(k, A, name='RiseRind')
    across = a.cross(n).normalized()
    ctrl = [C + a * u + across * w for u, w in
            ((0.36, 0.0), (0.52, 0.01), (0.64, 0.05), (0.72, 0.13), (0.73, 0.22), (0.67, 0.28), (0.6, 0.27))]
    pts = _catmull(ctrl, 4)
    bm = bmesh.new()
    bm.from_mesh(rind.data)
    uvl = bm.loops.layers.uv.active or bm.loops.layers.uv.new('UVMap')
    _tube(bm, uvl, pts, [0.085 - 0.045 * (i / (len(pts) - 1)) ** 1.3 for i in range(len(pts))], 8,
          lambda u, t: A.uv('STEM', u, t), up=tuple(n))
    bm.to_mesh(rind.data)
    bm.free()
    rind.data.transform(M)
    for p in rind.data.polygons:
        p.use_smooth = True
        p.material_index = 0
    k.add('Head', rind)
    k.joint('Core', pivot=(0, 0, 1.0), parent='Head',
            visual=[{'Kind': 'Glow', 'Min': 0.2, 'Max': 0.8, 'Period': 0.4, 'Shape': 'flicker', 'Color': '#FFC040'}])
    bm = bmesh.new()
    nr, ns = 10, 18
    rings = [[bm.verts.new(_pump_point(0.08 + (math.pi - 0.16) * i / nr, 2 * math.pi * j / ns, 0.85, False)) for j in range(ns)]
             for i in range(nr + 1)]

    def outward(vs):
        cen = sum((v.co for v in vs), Vector()) / len(vs)
        nrm = (vs[1].co - vs[0].co).cross(vs[2].co - vs[1].co)
        return vs if nrm.dot(cen - C) > 0 else vs[::-1]
    for i in range(nr):
        for j in range(ns):
            bm.faces.new(outward([rings[i][j], rings[i][(j + 1) % ns], rings[i + 1][(j + 1) % ns], rings[i + 1][j]]))
    for ring, th in ((rings[0], 0.0), (rings[-1], math.pi)):
        cv = bm.verts.new(_pump_point(th, 0.0, 0.85, False))
        for j in range(ns):
            bm.faces.new(outward([ring[j], ring[(j + 1) % ns], cv]))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts[:])
    k.add('Core', k.mesh_object('RiseCore', bm, ['Core']))
    # the three mini jacks circling it (one orbit joint: one part), faces outward
    k.joint('Orbit', pivot=(0, 0, 1.0), motion=[{'Kind': 'Spin', 'Axis': (0, 0, 1), 'Rate': 150.0}])
    for i, (ang, z) in enumerate(((20, 1.45), (140, 0.85), (260, 1.2))):
        phi = math.radians(ang)
        centre = (1.7 * math.cos(phi), 1.7 * math.sin(phi), z)
        k.add('Orbit', _mini_jack(k, A, centre, ang, 0.3, 'RiseMini%d' % (i + 1)))


HB.KIND[RISE_PID] = 'pocket'
HB.KIND[JACKS_PID] = 'aura'
HB.AIM[JACKS_PID] = [m[0] for m in MINI_JACKS]


# =============================================================================================

HB.VIEWS[PID] = [((4.6, -3.6, 2.6), (0, -4.0, 0.0), 24),          # the whole cue, three-quarter
                 ((2.6, -8.9, 1.4), (0, -7.4, 0.15), 40),         # the pumpkin, face side
                 ((0.9, -3.7, 0.75), (0, -3.2, 0.05), 45),        # the vine and leaves between the hands
                 ((-1.9, -9.2, 1.2), (0, -7.4, 0.1), 40)]         # the pumpkin's back and the stem


LOOKS = [((5.2, -3.4, 3.0), (0, -4.2, 0.0), 26, 'whole'),
         ((2.2, -9.0, 1.5), (0, -7.5, 0.15), 38, 'pumpkin'),
         ((-1.8, -9.4, 1.4), (0, -7.5, 0.1), 38, 'back'),
         ((1.1, -6.0, 0.9), (0, -6.6, 0.0), 40, 'collar'),
         ((1.0, -3.9, 0.85), (0, -3.2, 0.05), 42, 'vine'),
         ((0.0, -7.4, 2.6), (0, -7.4, 0.0), 40, 'top'),
         (None, None, 40, 'face'),
         ((0.9, -9.6, 1.2), (0, -8.15, 0.15), 40, 'stem')]


def look(kit, size=(900, 600)):
    """Render the built kit's own objects (before anything clears them) in a bright, lobby-like
    light (a warm cream ground, a sun and a sky fill), from LOOKS: pieces/<pid>/_look_<name>.png.
    The game's ink outline is not drawn here; judge colour, shape and size, then the lab."""
    import bpy
    from mathutils import Vector
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('W')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (0.72, 0.66, 0.6, 1)
    bg.inputs[1].default_value = 0.9
    scene.world = world
    sun = bpy.data.objects.new('Sun', bpy.data.lights.new('Sun', 'SUN'))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    cam_d = bpy.data.cameras.new('C')
    cam = bpy.data.objects.new('C', cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = size
    out = os.path.join(HB.PIECES_DIR, kit.pid)
    for ob in scene.objects:      # JACK_HIDE=Name,Name: look without some objects (diagnosis)
        if ob.name in os.environ.get('JACK_HIDE', '').split(','):
            ob.hide_render = True
    only = os.environ.get('JACK_ONLY_LOOK')
    for loc, tgt, lens, name in LOOKS:
        if only and name not in only.split(','):
            continue
        if loc is None:   # straight at the carved face
            n, _, _ = _face_frame()
            c = Vector((0, -PUMP_C, PUMP_Z))
            loc, tgt = tuple(c + n * 3.4), tuple(c)
        cam.location = loc
        cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        cam_d.lens = lens
        scene.render.filepath = os.path.join(out, '_look_%s.png' % name)
        bpy.ops.render.render(write_still=True)
    print('CUE jack looks', out)


FLAMES = 'vfx/jack_o_lantern/flame_4x4.png'


def _hexc(h):
    import numpy as np
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def paint_flames(cell=128, frames=16):
    """The flame wisps round the pumpkin (C4's): a bold cartoon flame, a main tongue and two
    side tongues swaying, deep red-orange outside, orange, a yellow heart and a white-hot core
    low down, opaque (the lobby floor washes a soft additive flame out), 16 frames of a loop as
    a Grid4x4 flipbook at assets/cue/<FLAMES>. Plain numpy."""
    import numpy as np
    import cue_common as cc
    sheet = np.zeros((cell * 4, cell * 4, 4), np.float32)
    ys, xs = np.mgrid[0:cell, 0:cell]
    X = (xs + 0.5) / cell * 2 - 1           # -1..1
    Y = 1 - (ys + 0.5) / cell               # 0 at the bottom, 1 at the top
    deep, mid, hot, core = _hexc('#C42A08'), _hexc('#FF6A12'), _hexc('#FFA62A'), _hexc('#FFDA70')
    for f in range(frames):
        ph = 2 * math.pi * f / frames

        def tongue(x0, y0, h, w, sway, phase):
            # a teardrop tongue: a round bottom at y0, its widest a third up, a tip at y0 + h
            # swaying (more toward the tip); r is the distance from its centre line in widths
            tb = 0.28
            t = (Y - y0) / h
            tt = np.clip(t, 0, 1)
            low = w * np.sqrt(np.clip(1 - ((tt - tb) / tb) ** 2, 0, 1))
            high = w * np.clip((1 - tt) / (1 - tb), 0, 1) ** 0.95 * (1 + 0.06 * np.sin(13 * tt + phase * 1.7 + ph))
            prof = np.where(tt < tb, low, high)
            cx = x0 + sway * np.sin(ph + phase + 2.4 * tt) * tt ** 1.5
            r = np.abs(X - cx) / np.maximum(prof, 1e-4)
            return np.where((t >= 0) & (t <= 1), r, 9.0), tt
        bob = 0.03 * math.sin(ph * 2)
        parts = [tongue(0.0, 0.04, 0.9 + bob, 0.5, 0.2, 0.0),
                 tongue(-0.3, 0.12, 0.55 + 0.07 * math.sin(ph + 1.0), 0.26, 0.16, 2.1),
                 tongue(0.31, 0.1, 0.5 + 0.07 * math.sin(ph + 2.4), 0.24, 0.16, 4.0)]
        r = np.minimum.reduce([q[0] for q in parts])
        rr, t_main = parts[0]
        alpha = np.clip((1 - r) * 10, 0, 1)
        col = np.zeros((cell, cell, 3), np.float32)
        col[:] = deep
        m = np.clip((0.7 - r) * 14, 0, 1)[..., None]
        col = col * (1 - m) + mid * m
        # the hot heart low in the main tongue, the white-hot core at its bottom
        lit = (t_main > 0.02)[..., None]
        m = np.clip((0.62 * np.clip(1 - t_main, 0, 1) ** 0.7 - rr) * 12, 0, 1)[..., None] * lit
        col = col * (1 - m) + hot * m
        m = np.clip((0.4 * np.clip(1 - t_main * 1.9, 0, 1) ** 0.6 - rr) * 12, 0, 1)[..., None] * lit
        col = col * (1 - m) + core * m
        r0, c0 = (f // 4) * cell, (f % 4) * cell
        sheet[r0:r0 + cell, c0:c0 + cell, :3] = col
        sheet[r0:r0 + cell, c0:c0 + cell, 3] = alpha
    cc.write_png(os.path.join(HERE, FLAMES), sheet * 255.0)
    print('CUE jack flames', os.path.join(HERE, FLAMES))


SPRITE = 'vfx/jack_o_lantern/jack_glow_4x4.png'
SPRITE_SHOW = ('Rind', 'CoreGlow', 'SpriteStem')


def sprite(kit, cell=256):
    """The mini jack-o'-lantern sprite (C4's tiny floating jacks, the trail's little pumpkins,
    the finisher's pop): the cue's own carved pumpkin rendered face-on on a clear film, 16
    frames of a slow head wobble with the candle flickering inside, each with a warm painted
    glow round it, as a Grid4x4 flipbook at assets/cue/<SPRITE>."""
    import bpy
    import numpy as np
    import cue_common as cc
    from mathutils import Matrix, Vector
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.resolution_x = scene.render.resolution_y = cell
    world = bpy.data.worlds.new('W')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (0.7, 0.62, 0.55, 1)
    bg.inputs[1].default_value = 0.8
    scene.world = world
    import bmesh
    n, a, _ = _face_frame()
    n, a = Vector(n), Vector(a)
    centre = Vector((0, -PUMP_C, PUMP_Z))
    c = centre + a * 0.1   # the stem in the frame too
    # A loose jack wears its stem on top (the cue's curls off the butt end, which on its own
    # reads as a mug's handle): a short curled stem out of the top dimple, in the face's plane.
    across = a.cross(n).normalized()
    ctrl = [centre + a * u + across * s for u, s in
            ((0.36, 0.0), (0.52, 0.01), (0.64, 0.05), (0.72, 0.13), (0.73, 0.22), (0.67, 0.28), (0.6, 0.27))]
    pts = _catmull(ctrl, 4)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    _tube(bm, uvl, pts, [0.085 - 0.05 * (i / (len(pts) - 1)) ** 1.3 for i in range(len(pts))], 10,
          lambda u, t: (0.5, 0.5), up=tuple(n))
    me = bpy.data.meshes.new('SpriteStem')
    bm.to_mesh(me)
    bm.free()
    stem = bpy.data.objects.new('SpriteStem', me)
    scene.collection.objects.link(stem)
    sm = bpy.data.materials.new('SpriteStem')
    sm.use_nodes = True
    sb = next(nd for nd in sm.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED')
    sb.inputs['Base Color'].default_value = (0.09, 0.2, 0.035, 1)
    sb.inputs['Roughness'].default_value = 0.45
    me.materials.append(sm)
    for p in me.polygons:
        p.use_smooth = True
    for ob in list(scene.objects):
        ob.hide_render = ob.type == 'MESH' and ob.name not in SPRITE_SHOW
    sun = bpy.data.objects.new('Sun', bpy.data.lights.new('Sun', 'SUN'))
    sun.data.energy = 2.6
    scene.collection.objects.link(sun)
    cam_d = bpy.data.cameras.new('C')
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = 1.95
    cam = bpy.data.objects.new('C', cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    core = bpy.data.materials.get('Core')
    core_bsdf = next(nd for nd in core.node_tree.nodes if nd.type == 'BSDF_PRINCIPLED') if core else None
    frames = []
    tmp = os.path.join(HB.PIECES_DIR, kit.pid, '_sprite.png')
    for i in range(16):
        ph = 2 * math.pi * i / 16
        yaw = math.radians(13) * math.sin(ph)
        nod = math.radians(5) * math.sin(2 * ph + 0.7)
        side = a.cross(n).normalized()
        f = (n * math.cos(yaw) + side * math.sin(yaw)).normalized()
        f = (f * math.cos(nod) + a * math.sin(nod)).normalized()
        up = (a - f * a.dot(f)).normalized()
        z = f
        x = up.cross(z).normalized()
        y = z.cross(x)
        loc = c + f * 6.0
        cam.matrix_world = Matrix(((x.x, y.x, z.x, loc.x), (x.y, y.y, z.y, loc.y),
                                   (x.z, y.z, z.z, loc.z), (0, 0, 0, 1)))
        key = (f * 0.6 + up * 0.7 + x * -0.4).normalized()   # the light from the upper left
        sun.rotation_euler = key.to_track_quat('Z', 'Y').to_euler()
        flick = 0.78 + 0.22 * (0.5 + 0.5 * math.sin(ph * 3 + 1.1)) * (0.7 + 0.3 * math.sin(ph * 5))
        if core_bsdf:
            core_bsdf.inputs['Emission Strength'].default_value = 3.2 * flick
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp, check_existing=False)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(cell, cell, 4)[::-1]   # row 0 at the top
        bpy.data.images.remove(img)
        frames.append((px, flick))
    os.remove(tmp)

    def blur(m, r):
        k1 = np.exp(-0.5 * (np.arange(-3 * r, 3 * r + 1) / r) ** 2)
        k1 /= k1.sum()
        out = m
        for ax in (0, 1):
            pad = [(0, 0), (0, 0)]
            pad[ax] = (3 * r, 3 * r)
            p = np.pad(out, pad, mode='constant')
            out = sum(k1[j] * np.take(p, range(j, j + m.shape[ax]), axis=ax) for j in range(len(k1)))
        return out
    sheet = np.zeros((cell * 4, cell * 4, 4), dtype=np.float32)
    warm = np.array((1.0, 0.54, 0.11))
    hot = np.array((1.0, 0.86, 0.38))
    for i, (px, flick) in enumerate(frames):
        rgb, al = px[..., :3], px[..., 3]
        lum = rgb.max(-1)
        lit = np.clip((lum - 0.82) / 0.18, 0, 1) * al * (rgb[..., 2] < 0.75)   # the lit face
        halo = np.clip(blur(al, 9) * 1.15, 0, 1) * (0.5 + 0.2 * flick)
        inner = np.clip(blur(lit, 5) * 2.2, 0, 1) * flick
        # the glow under the jack: orange halo, a hot inner glow from the carved holes
        g_al = np.clip(halo + inner * 0.6, 0, 1)
        g_rgb = (warm[None, None] * halo[..., None] + hot[None, None] * inner[..., None]) / np.maximum(g_al[..., None], 1e-4)
        g_rgb = np.clip(g_rgb, 0, 1)
        out_al = al + g_al * (1 - al)
        out_rgb = (rgb * al[..., None] + g_rgb * g_al[..., None] * (1 - al[..., None])) / np.maximum(out_al[..., None], 1e-4)
        r0, c0 = (i // 4) * cell, (i % 4) * cell
        sheet[r0:r0 + cell, c0:c0 + cell, :3] = np.clip(out_rgb, 0, 1)
        sheet[r0:r0 + cell, c0:c0 + cell, 3] = np.clip(out_al, 0, 1)
    path = os.path.join(HERE, SPRITE)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cc.write_png(path, sheet * 255.0)
    print('CUE jack sprite', path)


def build(pid, render=True):
    import bpy
    import cue_common as cc
    cc.clear_scene('CuePieces')
    kit = CuePieces.Kit(bpy, pid)
    CuePieces.BUILDERS[pid](kit)
    if '--sprite' in sys.argv:
        sprite(kit)
        paint_flames()
        return None
    spec = CuePieces.export(kit)
    HB.check_budget(pid, spec)
    HB.check_envelope(pid, kit)
    HB.patch_aim(pid)
    HB.patch_outline(pid)
    if render:
        look(kit)
    return spec


if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    for pid in (x for x in argv if not x.startswith('--')):
        build(pid, render='--no-look' not in argv)
