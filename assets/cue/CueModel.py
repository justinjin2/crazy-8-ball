"""The shared cue mesh: a lathe of one tip-to-butt profile, 32 around, with its UV atlas, every
check in the brief (docs/prompts/CUE_MESH_PROMPT.md 3.6), the glb and Parameters.json.

Run from the repo root:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
        --python assets/cue/CueModel.py

Reads only assets/cue/Shape.json (tools/export_cue_shape.luau writes it). Writes
assets/cue/Cue.glb, CueModel.blend and Parameters.json. Prints CUE ... lines and exits 1 on any
failed check. Headless-safe: bmesh and data calls only; the only operators are glTF export and
import, and save. Deterministic: no randomness, fixed orders.

The frame: 1 unit = 1 stud; the tip at the origin, the cue along Blender -Y (tip toward butt),
which the glTF exporter (+Y up) writes as +Z: Roblox local +Z. The UV seam runs along Blender -Z
(Roblox local -Y), down in the hand. See cue_common.py for theta.
"""

import math
import os
import sys

sys.dont_write_bytecode = True

import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import cue_common as cc  # noqa: E402

TAG = 'CUE'

PARAMETERS = {
    # Around the cue: round in the Index close-up, cheap at this size (brief 3.3).
    'radial_segments': 32,
    # Curved parts of the profile get a ring wherever the chord would sag more than this (studs).
    'chord_tolerance': 0.0002,
    # The tip's dome: a nickel's radius (0.4175 in) over a real tip's radius (0.256 in, 13 mm),
    # times our tip radius, so the dome is as shallow as a real one on this fatter tip.
    'dome_radius_ratio': 0.4175 / 0.256,
    'tip_edge_radius': 0.005,  # the rounded edge where the dome meets the side
    'ferrule_chamfer': 0.0015,  # the ferrule's edge chamfer at the tip
    # V grooves at the joint collar's ends and the ring's tip end (depth, half width).
    'groove_depth': 0.002,
    'groove_half_width': 0.002,
    # The hairline seam in the middle of the joint collar, where the halves screw together.
    'seam_depth': 0.0015,
    'seam_half_width': 0.0012,
    # The wrap sits this far below the envelope (brief: at most 0.004) between steep steps
    # this long.
    'wrap_inset': 0.003,
    'wrap_edge': 0.001,
    # The butt: the sleeve's rounded end, then a rubber bumper slightly smaller in diameter.
    'butt_round_radius': 0.01,
    'bumper_radius': 0.0875,
    'bumper_length': 0.035,
    'bumper_edge_radius': 0.006,
    'max_taper_step': 1.06,  # the most a straight face may widen from ring to ring
    'sharp_degrees': 30.0,  # a profile turn sharper than this is a crisp edge
    'triangle_budget': 4000,
    # The atlas (brief 3.4).
    'atlas_px': 1024,
    'padding_px': 16,  # between strips; each map is then bled at least 8 px (half of it)
    'handle_ratio': 1.6,  # handle texel density over the shaft's (brief: at least 1.5)
    'shaft_strip_choices': [2, 3, 4],  # the shaft is cut into this many strips (best fit wins)
    # Texel shape: each strip's area-weighted anisotropy must be under stretch_limit (brief:
    # 5%); single faces may reach face_stretch_limit (only tiny steep faces in the grooves, steps
    # and fillets, where no flat triangle can be square in a conformal map, come near it).
    'stretch_limit': 1.05,
    'face_stretch_limit': 1.15,
    'min_handle_share': 0.60,
    # Validation (brief 3.6).
    'envelope_slack': 0.0005,
    'min_envelope_ratio': 0.9,
    'zone_tolerance': 0.002,
    'roundtrip_tolerance': 1e-5,
    # Paint-kit panels (brief 4.2): 512 px tall; widths are multiples of 16, at most 3:1.
    'panel_height': 512,
    'panel_max_aspect': 3.0,
    'shaft_tile_px': [1024, 512],
    'cap_end_px': 512,
    'cap_end_margin_px': 8,
}

HANDLE_REGIONS = ('joint', 'forearm', 'ring', 'wrap', 'cap', 'bumper', 'end')


# ---------------------------------------------------------------------------------------------
# The profile: (d, r) points tip to butt, each segment tagged with its region
# ---------------------------------------------------------------------------------------------

class Profile:
    def __init__(self):
        self.d, self.r, self.region, self.free = [], [], [], []

    def add(self, d, r, region, free=False):
        """A point reached by a segment of `region`. free: the point may sit under 0.9 of the
        envelope (the tip's dome and the butt's end)."""
        if self.d and abs(d - self.d[-1]) < 1e-12 and abs(r - self.r[-1]) < 1e-12:
            return
        self.d.append(float(d))
        self.r.append(max(float(r), 0.0))
        self.region.append(region)
        self.free.append(free)

    def arc(self, center_d, center_r, radius, a0, a1, region, free, tol):
        """Points on a circle in the (d, r) plane from angle a0 to a1 (radians, a0 excluded)."""
        step = 2 * math.acos(max(1 - tol / radius, -1))
        n = max(2, int(math.ceil(abs(a1 - a0) / step)))
        for i in range(1, n + 1):
            a = a0 + (a1 - a0) * i / n
            self.add(center_d + radius * math.cos(a), center_r + radius * math.sin(a), region, free)


def zone_bounds(shape):
    return {z['name']: (z['from_studs'], z['to_studs']) for z in shape['zones']}


def build_profile(shape, E, cuts):
    P = PARAMETERS
    tol = P['chord_tolerance']
    Z = zone_bounds(shape)
    L = E.length
    kinks = list(shape['kinks_studs'])
    prof = Profile()

    def straight_to(d_end, region, r_off=0.0):
        """Follow the envelope (less r_off) to d_end, with a ring at every kink or cut passed."""
        d0 = prof.d[-1]
        stops = [k for k in sorted(set(kinks + cuts)) if d0 + 1e-9 < k < d_end - 1e-9] + [d_end]
        at = d0
        for stop in stops:
            # A long taper gets rings so no face widens by more than max_taper_step: the
            # conformal UVs are then square to within a few percent on every big face.
            grow = (E(stop) - r_off) / (E(at) - r_off)
            n = max(1, int(math.ceil(math.log(grow) / math.log(P['max_taper_step']) - 1e-9)))
            for j in range(1, n):
                dj = at + (stop - at) * j / n
                prof.add(dj, E(dj) - r_off, region)
            prof.add(stop, E(stop) - r_off, region)
            at = stop

    # Tip: a dome of radius R, a rounded edge of radius rf, the side on the envelope.
    R = P['dome_radius_ratio'] * E.tip_radius
    rf = P['tip_edge_radius']
    c_d = 0.01
    for _ in range(6):
        r_s = E(c_d)
        c_r = r_s - rf
        c_d = R - math.sqrt((R - rf) ** 2 - c_r ** 2)
    r_s = E(c_d)
    c_r = r_s - rf
    # Where the edge circle touches the dome: on the line from the dome's centre (R, 0) through c.
    vd, vr = c_d - R, c_r
    n = math.hypot(vd, vr)
    t_d, t_r = R + R * vd / n, R * vr / n
    phi_t = math.atan2(t_r, R - t_d)
    prof.add(0.0, 0.0, 'tip', True)
    prof.arc(R, 0.0, R, math.pi, math.pi - phi_t, 'tip', True, tol)
    psi0 = math.atan2(t_r - c_r, t_d - c_d)
    prof.arc(c_d, c_r, rf, psi0, math.pi / 2, 'tip', True, tol)
    tip_end = Z['tip'][1]
    straight_to(tip_end, 'tip')
    # Ferrule: a small step in at the tip, a chamfer back out to the envelope.
    ch = P['ferrule_chamfer']
    prof.add(tip_end, E(tip_end) - ch, 'ferrule')
    prof.add(tip_end + ch, E(tip_end + ch), 'ferrule')
    straight_to(Z['ferrule'][1], 'ferrule')
    # Shaft to the joint's V groove.
    g, gd = P['groove_half_width'], P['groove_depth']
    j0, j1 = Z['joint']
    straight_to(j0 - g, 'shaft')
    prof.add(j0, E(j0) - gd, 'shaft')
    # Joint collar: V grooves at both ends, the hairline seam in the middle.
    prof.add(j0 + g, E(j0 + g), 'joint')
    mid, sw, sd = (j0 + j1) / 2, P['seam_half_width'], P['seam_depth']
    straight_to(mid - sw, 'joint')
    prof.add(mid, E(mid) - sd, 'joint')
    prof.add(mid + sw, E(mid + sw), 'joint')
    straight_to(j1 - g, 'joint')
    prof.add(j1, E(j1) - gd, 'joint')
    # Forearm, then the ring's V groove.
    f1 = Z['forearm'][1]
    prof.add(j1 + g, E(j1 + g), 'forearm')
    straight_to(f1 - g, 'forearm')
    prof.add(f1, E(f1) - gd, 'forearm')
    # The trim ring, then a steep step down into the wrap.
    r1 = Z['ring'][1]
    wi, we = P['wrap_inset'], P['wrap_edge']
    prof.add(f1 + g, E(f1 + g), 'ring')
    straight_to(r1 - we, 'ring')
    prof.add(r1, E(r1) - wi, 'ring')
    # The wrap, inset, then a steep step back up to the sleeve.
    w1 = Z['wrap'][1]
    straight_to(w1, 'wrap', r_off=wi)
    prof.add(w1 + we, E(w1 + we), 'cap')
    # The sleeve, its rounded end, a small shoulder, the bumper, its rounded edge, the end face.
    Rb, rb, Lb, rbe = (P['butt_round_radius'], P['bumper_radius'], P['bumper_length'],
                       P['bumper_edge_radius'])
    f0 = L - Lb - Rb
    straight_to(f0, 'cap')
    top = E(f0)
    prof.arc(f0, top - Rb, Rb, math.pi / 2, 0.0, 'cap', True, tol)
    prof.add(L - Lb, rb, 'cap', True)
    prof.add(L - rbe, rb, 'bumper', True)
    prof.arc(L - rbe, rb - rbe, rbe, math.pi / 2, 0.0, 'bumper', True, tol)
    face = rb - rbe
    prof.add(L, face / 2, 'end', True)
    prof.add(L, 0.0, 'end', True)
    return prof


# ---------------------------------------------------------------------------------------------
# UV strips and packing
# ---------------------------------------------------------------------------------------------

def ring_index(prof, d, r=None, region=None):
    best, best_err = None, 1e9
    for i, (pd, pr) in enumerate(zip(prof.d, prof.r)):
        err = abs(pd - d) + (abs(pr - r) if r is not None else 0.0)
        if region is not None and prof.region[i] != region:
            continue
        if err < best_err:
            best, best_err = i, err
    assert best is not None and best_err < 1e-9, ('no ring at', d, r, region, best_err)
    return best


def strip_ranges(shape, prof, E, cuts):
    """(name, first ring, last ring, handle?, kind) tip to butt; consecutive strips share a
    ring. kind 'disc': a pole's island (the tip's dome, the butt's end face); 'strip' otherwise."""
    Z = zone_bounds(shape)
    dome_end = next(i for i in range(len(prof.d)) if not prof.free[i]) - 1
    tip_end = ring_index(prof, Z['tip'][1], E(Z['tip'][1]))
    ferrule_end = ring_index(prof, Z['ferrule'][1])
    joint0 = ring_index(prof, Z['joint'][0], region='shaft')
    forearm_end = ring_index(prof, Z['forearm'][1], region='forearm')
    face0 = ring_index(prof, E.length, PARAMETERS['bumper_radius'] - PARAMETERS['bumper_edge_radius'],
                       region='bumper')
    strips = [('tip_face', 0, dome_end, False, 'disc'), ('tip', dome_end, tip_end, False, 'strip'),
              ('ferrule', tip_end, ferrule_end, False, 'strip')]
    prev = ferrule_end
    for i, cut in enumerate(cuts):
        at = ring_index(prof, cut)
        strips.append(('shaft_%d' % (i + 1), prev, at, False, 'strip'))
        prev = at
    strips.append(('shaft_%d' % (len(cuts) + 1), prev, joint0, False, 'strip'))
    strips.append(('forearm', joint0, forearm_end, True, 'strip'))
    strips.append(('butt', forearm_end, face0, True, 'strip'))
    strips.append(('end_face', face0, len(prof.d) - 1, True, 'disc'))
    return strips


def maxrects(sizes, width, height):
    """Place (w, h) rectangles, in the given order, top-left first; None if one does not fit."""
    free = [(0, 0, width, height)]
    placed = []
    for w, h in sizes:
        best = None
        for fx, fy, fw, fh in free:
            if w <= fw and h <= fh and (best is None or (fy, fx) < (best[1], best[0])):
                best = (fx, fy)
        if best is None:
            return None
        x, y = best
        placed.append((x, y))
        rect = (x, y, x + w, y + h)
        nxt = []
        for fx, fy, fw, fh in free:
            f = (fx, fy, fx + fw, fy + fh)
            if rect[0] >= f[2] or rect[2] <= f[0] or rect[1] >= f[3] or rect[3] <= f[1]:
                nxt.append((fx, fy, fw, fh))
                continue
            if rect[0] > f[0]:
                nxt.append((f[0], f[1], rect[0] - f[0], fh))
            if rect[2] < f[2]:
                nxt.append((rect[2], f[1], f[2] - rect[2], fh))
            if rect[1] > f[1]:
                nxt.append((f[0], f[1], fw, rect[1] - f[1]))
            if rect[3] < f[3]:
                nxt.append((f[0], rect[3], fw, f[3] - rect[3]))
        free = [a for a in nxt if not any(
            b != a and b[0] <= a[0] and b[1] <= a[1] and b[0] + b[2] >= a[0] + a[2]
            and b[1] + b[3] >= a[1] + a[3] for b in nxt)]
        free = sorted(set(free))
    return placed


def arc_lengths(prof):
    s = [0.0]
    for i in range(1, len(prof.d)):
        s.append(s[-1] + math.hypot(prof.d[i] - prof.d[i - 1], prof.r[i] - prof.r[i - 1]))
    return s


def segment_sigma(prof, i):
    """The integral of ds / r over the straight profile segment from ring i to i + 1: the step of
    the conformal coordinate (a lathe's isothermal coordinates are (sigma, theta))."""
    ds = math.hypot(prof.d[i + 1] - prof.d[i], prof.r[i + 1] - prof.r[i])
    r0, r1 = prof.r[i], prof.r[i + 1]
    if abs(r1 - r0) < 1e-12:
        return ds / r0
    return ds / (r1 - r0) * math.log(r1 / r0)


def strip_geometry(prof, strip):
    """Per ring of a strip, its conformal position. A 'strip': sigma from its first ring, drawn
    at the widest radius's scale, so the texel density is D at the widest point and rises as
    r_max / r where the cue is thinner, with square texels everywhere (even on the grooves and
    the rounded butt, where a plain unrolling would shear). A 'disc': rho, a radius in studs,
    with the pole at 0 and rho = r at the rim (a stereographic-style conformal disc)."""
    name, a, b, handle, kind = strip
    if kind == 'strip':
        sig = {a: 0.0}
        for i in range(a, b):
            sig[i + 1] = sig[i] + segment_sigma(prof, i)
        return sig, max(prof.r[a:b + 1])
    pole = a if prof.r[a] == 0.0 else b
    rim = b if pole == a else a
    step = 1 if pole == a else -1
    # log rho climbs by the sigma step ring to ring; the first ring out from the pole starts at
    # its arc distance (the first segment is a straight cone, where rho ~ s).
    first = pole + step
    logrho = {first: math.log(math.hypot(prof.d[first] - prof.d[pole], prof.r[first]))}
    i = first
    while i != rim:
        j = i + step
        logrho[j] = logrho[i] + segment_sigma(prof, min(i, j))
        i = j
    k = prof.r[rim] / math.exp(logrho[rim])
    rho = {i: k * math.exp(v) for i, v in logrho.items()}
    rho[pole] = 0.0
    return rho, prof.r[rim]


def layout(shape, E, n_shaft):
    """The profile with `n_shaft` shaft strips, and the best packing: the highest handle density
    at which every strip fits the atlas with the padding."""
    P = PARAMETERS
    Z = zone_bounds(shape)
    s0, s1 = Z['ferrule'][1], Z['joint'][0]
    cuts = [s0 + (s1 - s0) * i / n_shaft for i in range(1, n_shaft)]
    prof = build_profile(shape, E, cuts)
    s = arc_lengths(prof)
    strips = strip_ranges(shape, prof, E, cuts)
    geo = [strip_geometry(prof, st) for st in strips]
    W, pad = P['atlas_px'], P['padding_px']
    for dh in range(900, 200, -1):
        ds = dh / P['handle_ratio']
        sizes = []
        for st, (pos, r_ref) in zip(strips, geo):
            dens = dh if st[3] else ds
            if st[4] == 'strip':
                w = int(math.ceil(max(pos.values()) * r_ref * dens)) + 1
                h = int(math.ceil(2 * math.pi * r_ref * dens)) + 1
            else:
                w = h = int(math.ceil(2 * max(pos.values()) * dens)) + 1
            sizes.append((w, h))
        order = sorted(range(len(strips)), key=lambda i: (-sizes[i][1], -sizes[i][0], i))
        # Each rectangle carries the padding on its right and bottom, and is shifted by half of
        # it, so the atlas keeps a half-padding margin on every side.
        placed = maxrects([(sizes[i][0] + pad, sizes[i][1] + pad) for i in order], W, W)
        if placed is None:
            continue
        rects = {}
        for k, i in enumerate(order):
            x, y = placed[k]
            rects[i] = (x + pad // 2, y + pad // 2, sizes[i][0], sizes[i][1])
        return prof, s, strips, cuts, dh, ds, rects, geo
    raise AssertionError('no packing found')


# ---------------------------------------------------------------------------------------------
# The mesh
# ---------------------------------------------------------------------------------------------

def radial(theta):
    return math.sin(theta), -math.cos(theta)  # (x, z) of the outward direction at theta


def build_mesh(prof, s, strips, rects, dens, geo):
    P = PARAMETERS
    N = P['radial_segments']
    W = P['atlas_px']
    bm = bmesh.new()
    rings = []
    for d, r in zip(prof.d, prof.r):
        if r == 0.0:
            rings.append([bm.verts.new((0.0, -d, 0.0))])
        else:
            ring = []
            for k in range(N):
                x, z = radial(2 * math.pi * k / N)
                ring.append(bm.verts.new((r * x, -d, r * z)))
            rings.append(ring)
    bm.verts.index_update()
    uv_layer = bm.loops.layers.uv.new('UVMap')
    s_layer = bm.loops.layers.float.new('cue_s')
    th_layer = bm.loops.layers.float.new('cue_theta')
    region_layer = bm.faces.layers.int.new('cue_region')

    strip_of_segment = {}
    for si, st in enumerate(strips):
        for i in range(st[1], st[2]):
            strip_of_segment[i] = si

    def uv_of(si, i, theta):
        name, a, b, handle, kind = strips[si]
        x0, y0, w, h = rects[si]
        pos, r_ref = geo[si]
        D = dens[si]
        if kind == 'strip':
            # Conformal: u along sigma, v around, both at r_ref's scale. Row 0 is the seam.
            u = x0 + 0.5 + pos[i] * r_ref * D
            v = y0 + 0.5 + theta * r_ref * D
        else:
            cx, cy = x0 + w / 2, y0 + h / 2
            rho = pos[i] * D
            if name == 'tip_face':  # seen from in front of the tip, top up
                u, v = cx - rho * math.sin(theta), cy + rho * math.cos(theta)
            else:  # seen from behind the butt, top up (the cap_end panel's view)
                u, v = cx + rho * math.sin(theta), cy + rho * math.cos(theta)
        return (u / W, 1.0 - v / W)

    wrong = 0
    face_strip = []
    for i in range(len(rings) - 1):
        si = strip_of_segment[i]
        region = cc.REGIONS.index(prof.region[i + 1])
        A, B = rings[i], rings[i + 1]
        # The segment's outward direction in the (d, r) plane is (-dr, dd).
        dd, dr = prof.d[i + 1] - prof.d[i], prof.r[i + 1] - prof.r[i]
        tris = []
        for k in range(N):
            k1 = k + 1
            ta, tb = 2 * math.pi * k / N, 2 * math.pi * k1 / N
            if len(A) == 1:
                tris.append([(i, A[0], (ta + tb) / 2), (i + 1, B[k % N], ta), (i + 1, B[k1 % N], tb)])
            elif len(B) == 1:
                tris.append([(i, A[k % N], ta), (i + 1, B[0], (ta + tb) / 2), (i, A[k1 % N], tb)])
            else:
                tris.append([(i, A[k % N], ta), (i + 1, B[k % N], ta), (i + 1, B[k1 % N], tb)])
                tris.append([(i, A[k % N], ta), (i + 1, B[k1 % N], tb), (i, A[k1 % N], tb)])
        for tri in tris:
            tri = [tri[0], tri[2], tri[1]]  # counter-clockwise seen from outside
            face = bm.faces.new([t[1] for t in tri])
            face[region_layer] = region
            for loop, (ri, _v, theta) in zip(face.loops, tri):
                loop[uv_layer].uv = uv_of(si, ri, theta)
                loop[s_layer] = s[ri]
                loop[th_layer] = theta
            face.normal_update()
            x, z = radial(sum(t[2] for t in tri) / 3)
            expected = (dd * x, dr, dd * z)  # -dr along -Y is +dr along Y
            n = face.normal
            if n.x * expected[0] + n.y * expected[1] + n.z * expected[2] <= 0:
                wrong += 1
            face_strip.append(si)
    return bm, wrong, face_strip


def finish(bm, name):
    sharp = math.radians(PARAMETERS['sharp_degrees'])
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = len(e.link_faces) == 2 and e.calc_face_angle(math.pi) < sharp
    mesh = bpy.data.meshes.new(name + 'Mesh')
    bm.to_mesh(mesh)
    bm.free()
    mesh.uv_layers.active = mesh.uv_layers['UVMap']
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mesh.materials.append(mat)
    return obj


# ---------------------------------------------------------------------------------------------
# Validation (brief 3.6)
# ---------------------------------------------------------------------------------------------

def check_topology(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    tris_only = all(len(f.verts) == 3 for f in bm.faces)
    manifold = all(e.is_manifold for e in bm.edges)
    boundary = sum(1 for e in bm.edges if e.is_boundary)
    loose = sum(1 for v in bm.verts if not v.link_faces)
    min_area = min(f.calc_area() for f in bm.faces)
    volume = bm.calc_volume(signed=True)
    bm.free()
    return {'triangles_only': tris_only, 'manifold': manifold, 'boundary_edges': boundary,
            'loose_vertices': loose, 'min_face_area': min_area, 'signed_volume': volume,
            'triangles': len(obj.data.polygons), 'vertices': len(obj.data.vertices)}


def check_envelope(obj, prof, E):
    P = PARAMETERS
    free_d = []  # d ranges where a point may sit under 0.9 of the envelope
    for i in range(1, len(prof.d)):
        if prof.free[i] or prof.free[i - 1]:
            free_d.append((min(prof.d[i - 1], prof.d[i]), max(prof.d[i - 1], prof.d[i])))
    worst_excess, worst_ratio, worst_at = -1.0, 9.0, None
    for v in obj.data.vertices:
        d = -v.co.y
        r = math.hypot(v.co.x, v.co.z)
        e = E(d)
        worst_excess = max(worst_excess, r - e)
        if not any(a - 1e-9 <= d <= b + 1e-9 for a, b in free_d):
            ratio = r / e
            if ratio < worst_ratio:
                worst_ratio, worst_at = ratio, d
    return {'max_excess': worst_excess, 'min_ratio': worst_ratio, 'min_ratio_at_d': worst_at,
            'ok': worst_excess <= P['envelope_slack'] and worst_ratio >= P['min_envelope_ratio']}


def check_zones(shape, prof):
    out, ok = [], True
    for zone in shape['zones'][1:]:
        b = zone['from_studs']
        # The ring where the region's zone changes to this zone.
        at = None
        for i in range(1, len(prof.d)):
            if cc.zone_of(prof.region[i]) == zone['name'] and cc.zone_of(prof.region[i - 1]) != zone['name']:
                at = prof.d[i - 1]
                break
        err = abs(at - b) if at is not None else 1e9
        ok = ok and err <= PARAMETERS['zone_tolerance']
        out.append({'zone': zone['name'], 'from_studs': b, 'ring_d': at, 'error': err})
    return out, ok


def check_uvs(obj, strips, rects, face_strip):
    P = PARAMETERS
    W = P['atlas_px']
    mesh = obj.data
    uv = np.empty(len(mesh.loops) * 2)
    mesh.uv_layers['UVMap'].data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2) * W
    co = np.array([v.co[:] for v in mesh.vertices])
    names = [st[0] for st in strips]
    stretch = {n: 1.0 for n in names}
    weighted = {n: 0.0 for n in names}
    mirrored = 0
    area_px = {n: 0.0 for n in names}
    area_3d = {n: 0.0 for n in names}
    dmin = {n: 1e9 for n in names}
    dmax = {n: 0.0 for n in names}
    for poly in mesh.polygons:
        name = names[face_strip[poly.index]]
        li = list(poly.loop_indices)
        p = co[list(poly.vertices)]
        t = uv[li]
        e1, e2 = p[1] - p[0], p[2] - p[0]
        n = np.cross(e1, e2)
        a3 = np.linalg.norm(n) / 2
        ex = e1 / np.linalg.norm(e1)
        ey = np.cross(n / np.linalg.norm(n), ex)
        P3 = np.array([[e1 @ ex, e2 @ ex], [e1 @ ey, e2 @ ey]])
        T2 = np.array([[t[1, 0] - t[0, 0], t[2, 0] - t[0, 0]], [t[1, 1] - t[0, 1], t[2, 1] - t[0, 1]]])
        det_uv = np.linalg.det(T2)
        if det_uv <= 0:
            mirrored += 1
            continue
        sv = np.linalg.svd(T2 @ np.linalg.inv(P3), compute_uv=False)
        stretch[name] = max(stretch[name], sv[0] / sv[1])
        weighted[name] += a3 * sv[0] / sv[1]
        area_px[name] += det_uv / 2
        area_3d[name] += a3
        dens = math.sqrt(det_uv / 2 / a3)
        dmin[name], dmax[name] = min(dmin[name], dens), max(dmax[name], dens)
    gap = 1e9
    boxes = [rects[i] for i in range(len(strips))]
    for i in range(len(boxes)):
        x, y, w, h = boxes[i]
        gap = min(gap, x, y, W - (x + w), W - (y + h))
        for j in range(i + 1, len(boxes)):
            X, Y, Wd, H = boxes[j]
            dx = max(X - (x + w), x - (X + Wd))
            dy = max(Y - (y + h), y - (Y + H))
            gap = min(gap, max(dx, dy))
    shaft_names = [st[0] for st in strips if st[0].startswith('shaft')]
    handle_names = [st[0] for st in strips if st[3]]
    shaft_px = sum(area_px[st[0]] for st in strips if not st[3])
    handle_px = sum(area_px[n] for n in handle_names)
    density = {n: math.sqrt(area_px[n] / area_3d[n]) for n in names}
    shaft_density = sum(area_px[n] for n in shaft_names) / sum(area_3d[n] for n in shaft_names)
    handle_density = sum(area_px[n] for n in handle_names) / sum(area_3d[n] for n in handle_names)
    mean_stretch = {n: weighted[n] / area_3d[n] for n in names}
    return {'mirrored_faces': mirrored, 'worst_stretch': max(stretch.values()), 'stretch': stretch,
            'mean_stretch': mean_stretch, 'worst_mean_stretch': max(mean_stretch.values()),
            'min_gap_px': gap, 'used_px': shaft_px + handle_px,
            'handle_share': handle_px / (shaft_px + handle_px),
            'measured_density': density, 'density_range': {n: [dmin[n], dmax[n]] for n in names},
            'shaft_density': math.sqrt(shaft_density), 'handle_density': math.sqrt(handle_density),
            'handle_over_shaft': math.sqrt(handle_density / shaft_density), 'area_px': area_px}


def export_glb(path, obj):
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_yup=True, export_apply=True, export_texcoords=True,
                              export_normals=True, export_tangents=False, export_materials='EXPORT',
                              export_image_format='NONE', export_vertex_color='NONE',
                              export_attributes=False, export_extras=False, export_cameras=False,
                              export_lights=False, export_animations=False, export_skins=False,
                              export_morph=False)
    obj.select_set(False)


def roundtrip(path, obj):
    def bounds(o):
        pts = np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices])
        return pts.min(axis=0), pts.max(axis=0)
    lo, hi = bounds(obj)
    scratch = bpy.data.scenes.new('CueReimport')
    with bpy.context.temp_override(scene=scratch, view_layer=scratch.view_layers[0]):
        bpy.ops.import_scene.gltf(filepath=path)
    scratch.view_layers[0].update()
    meshes = [o for o in scratch.objects if o.type == 'MESH']
    assert len(meshes) == 1, ('the glb holds', len(meshes), 'meshes')
    imp = meshes[0]
    ilo, ihi = bounds(imp)
    err = float(max(np.abs(ilo - lo).max(), np.abs(ihi - hi).max()))
    result = {'name': imp.name, 'materials': len(imp.data.materials), 'uv_layers': len(imp.data.uv_layers),
              'bounds_error': err, 'triangles': len(imp.data.polygons)}
    for o in list(scratch.objects):
        mesh = o.data if o.type == 'MESH' else None
        bpy.data.objects.remove(o, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    bpy.data.scenes.remove(scratch)
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat)
    return result


# ---------------------------------------------------------------------------------------------
# The paint-kit panels (brief 4.2), from the profile
# ---------------------------------------------------------------------------------------------

def circumference_mean(prof, s, s_from, s_to):
    """The mean circumference over an arc-length range (the profile is piecewise linear)."""
    total, n = 0.0, 400
    for k in range(n):
        at = s_from + (s_to - s_from) * (k + 0.5) / n
        total += 2 * math.pi * r_at_s(prof, s, at)
    return total / n


def r_at_s(prof, s, at):
    for i in range(1, len(s)):
        if at <= s[i] or i == len(s) - 1:
            k = (at - s[i - 1]) / (s[i] - s[i - 1]) if s[i] > s[i - 1] else 0.0
            return prof.r[i - 1] + (prof.r[i] - prof.r[i - 1]) * min(max(k, 0.0), 1.0)
    return prof.r[-1]


def d_at_s(prof, s, at):
    for i in range(1, len(s)):
        if at <= s[i] or i == len(s) - 1:
            k = (at - s[i - 1]) / (s[i] - s[i - 1]) if s[i] > s[i - 1] else 0.0
            return prof.d[i - 1] + (prof.d[i] - prof.d[i - 1]) * min(max(k, 0.0), 1.0)
    return prof.d[-1]


def panel_size(aspect):
    P = PARAMETERS
    h = P['panel_height']
    w = min(int(round(h * aspect / 16.0)) * 16, int(h * P['panel_max_aspect']))
    return w, h


def build_panels(shape, prof, s, E):
    P = PARAMETERS
    Z = zone_bounds(shape)

    def s_of(i):
        return s[i]

    i_ferrule_end = ring_index(prof, Z['ferrule'][1])
    i_joint0 = ring_index(prof, Z['joint'][0], region='shaft')
    i_seam = ring_index(prof, (Z['joint'][0] + Z['joint'][1]) / 2,
                        E((Z['joint'][0] + Z['joint'][1]) / 2) - P['seam_depth'])
    i_joint1 = ring_index(prof, Z['joint'][1], region='joint')
    i_forearm1 = ring_index(prof, Z['forearm'][1], region='forearm')
    i_ring1 = ring_index(prof, Z['ring'][1], region='ring')
    i_wrap1 = ring_index(prof, Z['wrap'][1], region='wrap')
    L = E.length
    i_round = ring_index(prof, L - P['bumper_length'] - P['butt_round_radius'], region='cap')
    i_bumper0 = ring_index(prof, L - P['bumper_length'], P['bumper_radius'], region='cap')
    face_r = P['bumper_radius'] - P['bumper_edge_radius']
    i_face0 = ring_index(prof, L, face_r, region='bumper')

    shaft0, joint0 = s_of(i_ferrule_end), s_of(i_joint0)
    # shaft_top: the stretch before the joint whose unrolled aspect is the panel's 3:1.
    target = P['panel_max_aspect']
    lo, hi = shaft0, joint0 - 0.01
    for _ in range(60):
        mid = (lo + hi) / 2
        aspect = (joint0 - mid) / circumference_mean(prof, s, mid, joint0)
        if aspect > target:
            lo = mid
        else:
            hi = mid
    top0 = (lo + hi) / 2

    def panel(name, s_from, s_to, lines, note):
        circ = circumference_mean(prof, s, s_from, s_to)
        aspect = (s_to - s_from) / circ
        w, h = panel_size(aspect)
        c0, c1 = 2 * math.pi * r_at_s(prof, s, s_from), 2 * math.pi * r_at_s(prof, s, s_to)
        return {'name': name, 'size_px': [w, h], 's_from': s_from, 's_to': s_to,
                'd_from': d_at_s(prof, s, s_from), 'd_to': d_at_s(prof, s, s_to),
                'length_studs': s_to - s_from, 'circumference_studs': [c0, c1],
                'mean_circumference_studs': circ, 'real_aspect': aspect, 'panel_aspect': w / h,
                'aspect_error': abs((w / h) / aspect - 1),
                'taper_squeeze': min(c0, c1) / max(c0, c1),
                'lines': [{'x': (sl - s_from) / (s_to - s_from), 'name': ln} for sl, ln in lines],
                'note': note}

    # The shaft tile repeats with square texels: each tile is 2 circumferences long where it
    # lies, so tiles shorten toward the tip with the taper (a log spiral of repeats).
    tw, th = P['shaft_tile_px']
    steps, integral = 2000, 0.0
    for k in range(steps):
        at = shaft0 + (top0 - shaft0) * (k + 0.5) / steps
        integral += (top0 - shaft0) / steps / ((tw / th) * 2 * math.pi * r_at_s(prof, s, at))
    tile = panel('shaft_tile', shaft0, top0, [], 'repeats along the shaft, seamless on all four edges')
    tile['size_px'] = [tw, th]
    tile['panel_aspect'] = tw / th
    tile['natural_repeats'] = integral
    tile['default_repeats'] = max(1, int(round(integral)))
    tile['real_aspect'] = (top0 - shaft0) / tile['default_repeats'] / tile['mean_circumference_studs']
    tile['aspect_error'] = 0.0  # each repeat is laid with square texels (its length follows the taper)
    panels = [
        tile,
        panel('shaft_top', top0, joint0, [], 'its right edge meets the joint collar'),
        panel('forearm', joint0, s_of(i_forearm1),
              [(s_of(i_seam), 'joint seam'), (s_of(i_joint1), 'collar | forearm')],
              'the joint collar, then the forearm, to the ring'),
        panel('butt', s_of(i_forearm1), s_of(i_bumper0),
              [(s_of(i_ring1), 'ring | wrap'), (s_of(i_wrap1), 'wrap | sleeve'),
               (s_of(i_round), 'rounded end')],
              'the ring, the wrap, the sleeve and its rounded end'),
    ]
    size = P['cap_end_px']
    panels.append({'name': 'cap_end', 'size_px': [size, size], 's_from': s_of(i_face0), 's_to': s[-1],
                   'd_from': L, 'd_to': L, 'face_radius_studs': face_r,
                   'disc_radius_px': size / 2 - P['cap_end_margin_px'], 'real_aspect': 1.0,
                   'panel_aspect': 1.0, 'aspect_error': 0.0, 'lines': [],
                   'note': 'the flat end of the bumper, seen from behind the butt with the top up'})
    regions = {
        'tip_colour': [0.0, s_of(ring_index(prof, Z['tip'][1], E(Z['tip'][1])))],
        'ferrule_colour': [s_of(ring_index(prof, Z['tip'][1], E(Z['tip'][1]))), shaft0],
        'bumper_colour': [s_of(i_bumper0), s_of(i_face0)],
    }
    return panels, regions


# ---------------------------------------------------------------------------------------------

def main():
    P = PARAMETERS
    shape, shape_sha = cc.load_shape()
    E = cc.Envelope(shape)
    cc.log(TAG, 'shape', shape_sha[:12], 'length', E.length)

    best = None
    for n in P['shaft_strip_choices']:
        result = layout(shape, E, n)
        cc.log(TAG, 'layout', n, 'shaft strips: handle', result[4], 'px/stud')
        if best is None or result[4] > best[4]:
            best = result
    prof, s, strips, cuts, dh, ds, rects, geo = best
    dens = [dh if st[3] else ds for st in strips]
    cc.log(TAG, 'profile', len(prof.d), 'points; strips', [st[0] for st in strips], 'handle', dh, 'shaft', round(ds, 2))

    cc.clear_scene('Cue')
    bm, wrong, face_strip = build_mesh(prof, s, strips, rects, dens, geo)
    obj = finish(bm, 'Cue')
    results = {}
    failures = []

    topo = check_topology(obj)
    results['topology'] = topo
    cc.log(TAG, 'topology', topo)
    if not (topo['triangles_only'] and topo['manifold'] and topo['boundary_edges'] == 0
            and topo['loose_vertices'] == 0 and topo['min_face_area'] > 1e-10 and topo['signed_volume'] > 0
            and wrong == 0):
        failures.append('topology (inward faces: %d)' % wrong)
    results['outward_faces_wrong'] = wrong
    cc.log(TAG, 'inward faces', wrong)
    if topo['triangles'] > P['triangle_budget']:
        failures.append('triangle budget')

    env = check_envelope(obj, prof, E)
    results['envelope'] = env
    cc.log(TAG, 'envelope: max excess %.6f, min ratio %.4f at d=%s' % (env['max_excess'], env['min_ratio'], env['min_ratio_at_d']))
    if not env['ok']:
        failures.append('envelope')

    zones, zones_ok = check_zones(shape, prof)
    results['zones'] = zones
    cc.log(TAG, 'zones', 'ok' if zones_ok else 'FAIL', max(z['error'] for z in zones))
    if not zones_ok:
        failures.append('zone boundaries')

    uvs = check_uvs(obj, strips, rects, face_strip)
    raster = cc.rasterize(obj, P['atlas_px'])
    uvs['overlap_px'] = int(raster['overlap'].sum())
    results['uv'] = uvs
    cc.log(TAG, 'uv: mean stretch %.4f' % uvs['worst_mean_stretch'], {k: round(v, 3) for k, v in uvs['stretch'].items()})
    cc.log(TAG, 'uv: face stretch %.4f mirrored %d gap %d handle share %.3f handle/shaft %.3f overlap %d' % (
        uvs['worst_stretch'], uvs['mirrored_faces'], uvs['min_gap_px'], uvs['handle_share'],
        uvs['handle_over_shaft'], uvs['overlap_px']))
    if (uvs['worst_mean_stretch'] > P['stretch_limit'] or uvs['worst_stretch'] > P['face_stretch_limit'] or uvs['mirrored_faces'] or uvs['min_gap_px'] < 8
            or uvs['handle_share'] < P['min_handle_share'] or uvs['handle_over_shaft'] < 1.5
            or uvs['overlap_px']):
        failures.append('uv rules')

    radii = [math.hypot(v.co.x, v.co.z) for v in obj.data.vertices]
    length = max(-v.co.y for v in obj.data.vertices) - min(-v.co.y for v in obj.data.vertices)
    results['size'] = {'length': length, 'butt_diameter': 2 * max(radii)}
    if abs(length - 7) > 1e-9 or abs(2 * max(radii) - 0.2) > 0.001:
        failures.append('size')

    glb = os.path.join(HERE, 'Cue.glb')
    export_glb(glb, obj)
    rt = roundtrip(glb, obj)
    results['glb_roundtrip'] = rt
    cc.log(TAG, 'glb round trip', rt)
    if rt['bounds_error'] > P['roundtrip_tolerance'] or rt['materials'] != 1 or rt['uv_layers'] != 1:
        failures.append('glb round trip')

    panels, colour_regions = build_panels(shape, prof, s, E)
    for p in panels:
        cc.log(TAG, 'panel', p['name'], p['size_px'], 'real aspect %.3f error %.3f' % (p['real_aspect'], p['aspect_error']))
        if p['aspect_error'] > 0.05 or p['panel_aspect'] > 3.0 + 1e-9:
            failures.append('panel ' + p['name'])

    uv_layout = []
    for si, (name, a, b, handle, kind) in enumerate(strips):
        zones_in = []
        for i in range(a + 1, b + 1):
            z = cc.zone_of(prof.region[i])
            if z not in zones_in:
                zones_in.append(z)
        x, y, w, h = rects[si]
        uv_layout.append({'strip': name, 'kind': kind, 'zones': zones_in, 'rect_px': [x, y, w, h],
                          'density_range': uvs['density_range'][name], 'worst_face_stretch': uvs['stretch'][name],
                          'mean_stretch': uvs['mean_stretch'][name],
                          'rings': [a, b], 's_studs': [s[a], s[b]], 'd_studs': [prof.d[a], prof.d[b]],
                          'studs_covered': s[b] - s[a], 'density_px_per_stud': dens[si],
                          'measured_density': uvs['measured_density'][name], 'handle': handle})

    params = {
        'shape_source': {'file': 'Shape.json', 'sha256': shape_sha, 'inputs_sha256': shape['inputs_sha256'],
                         'schema': shape['schema_version']},
        'frame': ('1 Blender unit = 1 stud. The tip is at the origin and the cue runs along Blender -Y '
                  '(tip to butt); the glTF exporter (+Y up) maps Blender (x, y, z) to glTF (x, z, -y), '
                  'so the cue runs along glTF/Roblox local +Z with the tip at z = 0. The UV seam is at '
                  'theta = 0, Blender -Z = Roblox local -Y (down in the hand). theta runs seam -> +X -> +Z '
                  '(top) -> -X. Studio (checked 2026-09-29): Roblox\'s glTF importer turns the model 180 '
                  'degrees about Y and centres the MeshPart on its bounds, so in the MeshPart the tip '
                  'is at local +Z = length / 2 and the seam still at -Y; PivotOffset = '
                  'CFrame.new(0, 0, length / 2) * CFrame.Angles(0, pi, 0) puts the pivot on the tip '
                  'with +Z toward the butt.'),
        'axes': {'blender_tip_to_butt': [0, -1, 0], 'roblox_tip_to_butt': [0, 0, 1],
                 'blender_seam': [0, 0, -1], 'roblox_seam': [0, -1, 0],
                 'roblox_mesh_tip': [0, 0, E.length / 2], 'roblox_pivot_offset': [0, 0, E.length / 2],
                 'roblox_pivot_turn_degrees_about_y': 180},
        'parameters': P,
        'profile': [{'d': d, 'r': r, 'region': g, 's': sv} for d, r, g, sv in zip(prof.d, prof.r, prof.region, s)],
        'shaft_cuts_studs': cuts,
        'density_px_per_stud': {'handle': dh, 'shaft': ds},
        'uv_layout': uv_layout,
        'panels': panels,
        'colour_regions_s': colour_regions,
        'validation': results,
        'failures': failures,
    }
    cc.write_json(cc.PARAMETERS_PATH, params)
    cc.embed_scripts(['CueModel.py', 'cue_common.py'])
    cc.save_blend(cc.BLEND_PATH)
    if failures:
        cc.fail(TAG, ', '.join(failures))
    cc.log(TAG, 'OK', topo['triangles'], 'triangles')


main()
