"""Geometry builders for the Spider cue v2: candidate D's procedural kit (the judged winner,
2026-10-28, ~/Desktop/8ball-refs/halloween/spider_v2/cand_D/build_spider.py) adapted for the
lane builder. A plain vertex/face builder (MB) with a material slot per face (CH black chrome,
SV silver edge, RD red gem, WH white), lathes of rings with a material per band, D's faceted
crescent blade (a razor edge, two silver bevels, a black face, a silver fuller strip on the
centre ridge), the petal root plates on the hub, bevelled fins (the ferrule's barbs and
spikes), the gem bezel and the faceted hourglass gem. The lane builder turns an MB into a
bmesh with one atlas UV swatch per face (CuePiecesHalloween_B.spider): the silver is baked into
the atlas, so no part is added for it.

Frame: the cue's own (Y = -d along the cue, the tip at 0; +Z up); polar(r, phi, y) =
(r cos phi, y, r sin phi), so phi = pi/2 is up.
"""

import math

from mathutils import Vector

TAU = 2 * math.pi
CH, SV, RD, WH = 0, 1, 2, 3


class MB:
    """Vertices, faces (index lists) and a material slot per face."""

    def __init__(self):
        self.v = []
        self.f = []
        self.m = []

    def add(self, p):
        self.v.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.v) - 1

    def face(self, idx, mat=CH):
        out = []
        for i in idx:
            if not out or out[-1] != i:
                out.append(i)
        while len(out) > 1 and out[0] == out[-1]:
            out.pop()
        if len(set(out)) < 3 or len(set(out)) != len(out):
            return
        self.f.append(out)
        self.m.append(mat)

    def scale_radial(self, s):
        self.v = [(x * s, y, z * s) for (x, y, z) in self.v]


def polar(r, phi, y):
    return (r * math.cos(phi), y, r * math.sin(phi))


def loops_mesh(mb, loops, mats, cap_start=True, cap_end=True, cap_mat=CH):
    """loops: rings (each a list of M points). mats[k] is the material of strip k -> k+1."""
    idx = [[mb.add(p) for p in ring] for ring in loops]
    M = len(loops[0])
    for k in range(len(idx) - 1):
        a, b = idx[k], idx[k + 1]
        for j in range(M):
            j1 = (j + 1) % M
            mb.face([a[j], a[j1], b[j1], b[j]], mats[k])
    for which, do in ((0, cap_start), (len(idx) - 1, cap_end)):
        if not do:
            continue
        ring = idx[which]
        c = Vector((0, 0, 0))
        for i in ring:
            c += Vector(mb.v[i])
        c /= len(ring)
        ci = mb.add(c)
        for j in range(M):
            j1 = (j + 1) % M
            if which == 0:
                mb.face([ring[j1], ring[j], ci], cap_mat)
            else:
                mb.face([ring[j], ring[j1], ci], cap_mat)
    return idx


def lathe(mb, profile, M, mats=None, phase=0.0, cap_start=True, cap_end=True, rfun=None):
    """profile: (y, r[, k_chevron]) per ring, drawn at y - k * |sin(phi)| (an apex at +-X)."""
    loops = []
    for st in profile:
        y0, r0 = st[0], st[1]
        kc = st[2] if len(st) > 2 else 0.0
        ring = []
        for j in range(M):
            ph = phase + TAU * j / M
            y = y0 - kc * abs(math.sin(ph))
            r = rfun(y, r0) if rfun else r0
            ring.append(polar(r, ph, y))
        loops.append(ring)
    if mats is None:
        mats = [CH] * (len(loops) - 1)
    return loops_mesh(mb, loops, mats, cap_start, cap_end)


def _raycast(P, i, d):
    n = len(P)
    p = P[i]
    best = 10.0
    for j in range(n):
        if j == i or (j + 1) % n == i:
            continue
        q0, q1 = P[j], P[(j + 1) % n]
        e = q1 - q0
        det = -d.x * e.y + e.x * d.y
        if abs(det) < 1e-12:
            continue
        rhs = q0 - p
        t = (-rhs.x * e.y + e.x * rhs.y) / det
        s = (d.x * rhs.y - d.y * rhs.x) / det
        if t > 1e-7 and -1e-7 <= s <= 1 + 1e-7:
            best = min(best, t)
    return best


def plane_axes(phi):
    er = Vector((math.cos(phi), 0, math.sin(phi)))
    et = Vector((-math.sin(phi), 0, math.cos(phi)))
    return er, et


def fin(mb, outline, phi, rows, plate_mat=CH, tipdeg=58.0, wref=0.10):
    """A bevelled flat blade in the radial plane at angle phi. outline: closed list of (a, r),
    a along the cue (Y), r from the axis. rows: (inset D, max fraction of the local width,
    half-thickness H, material of the band rising to this row)."""
    P = [Vector(p) for p in outline]
    n = len(P)
    area = sum(P[i].x * P[(i + 1) % n].y - P[(i + 1) % n].x * P[i].y for i in range(n)) / 2
    if area < 0:
        P.reverse()
    en = []
    for i in range(n):
        d = (P[(i + 1) % n] - P[i]).normalized()
        en.append(Vector((-d.y, d.x)))
    info = []
    for i in range(n):
        e_prev = (P[i] - P[i - 1]).normalized()
        e_next = (P[(i + 1) % n] - P[i]).normalized()
        cross = e_prev.x * e_next.y - e_prev.y * e_next.x
        dot = max(-1.0, min(1.0, e_prev.dot(e_next)))
        turn = math.degrees(math.acos(dot))
        interior = 180 - turn if cross > 0 else 180 + turn
        dv = en[i - 1] + en[i]
        if dv.length < 1e-6:
            dv = en[i].copy()
        dv.normalize()
        c = max(0.35, dv.dot(en[i]))
        miter = min(2.2, 1.0 / c)
        w = _raycast(P, i, dv)
        tip = cross > 0 and interior < tipdeg
        info.append((dv, miter, w, tip))
    er, et = plane_axes(phi)

    def to3(p2, h):
        return er * p2.y + et * h + Vector((0, p2.x, 0))

    R0 = [mb.add(to3(P[i], 0.0)) for i in range(n)]
    for side in (1, -1):
        prev = R0
        rows_idx = [R0]
        for (D, frac, H, _m) in rows:
            cur = []
            for i in range(n):
                dv, miter, w, tip = info[i]
                if tip:
                    cur.append(prev[i])
                    continue
                d = min(D * miter, frac * w)
                h = H * max(0.22, min(1.0, w / wref))
                cur.append(mb.add(to3(P[i] + dv * d, side * h)))
            rows_idx.append(cur)
            prev = cur
        for k in range(len(rows)):
            A, B = rows_idx[k], rows_idx[k + 1]
            mat = rows[k][3]
            for i in range(n):
                i1 = (i + 1) % n
                q = [A[i], A[i1], B[i1], B[i]]
                if side < 0:
                    q.reverse()
                mb.face(q, mat)
        last = rows_idx[-1]
        poly = list(last) if side > 0 else list(reversed(last))
        mb.face(poly, plate_mat)


def crescent(mb, O, I, phi, scale=1.0, wref=0.075, thick=1.0, fuller=0.04, curl=0.0, curl_r0=0.25):
    """A thin blade lofted between an outer and an inner edge: O and I are matching lists of
    (a, r) stations (a along the cue, r from the axis), both running from the rear horn to the
    forward hook; a station whose two edges meet is a point (the horn and the hook tips).
    The cross-section is faceted so the chrome throws crisp lines: razor edge -> steep silver
    bevel -> second silver bevel -> black face -> a silver fuller strip over the centre ridge ->
    face -> bevels -> edge. curl: a tangential sweep of the sheet, curl * (r - curl_r0)^2."""
    d1, d2 = 0.0055 * scale, 0.018 * scale
    h1, h2, hr = 0.0100 * scale * thick, 0.0165 * scale * thick, 0.0215 * scale * thick
    O = [Vector(p) for p in O]
    I = [Vector(p) for p in I]
    er, et = plane_axes(phi)

    def to3(p2, h):
        off = curl * max(0.0, p2.y - curl_r0) ** 2
        return er * p2.y + et * (h + off) + Vector((0, p2.x, 0))

    ncol = 8
    stations = []
    for o, i in zip(O, I):
        w = (o - i).length
        if w < 1e-5:
            vi = mb.add(to3(o, 0.0))
            stations.append(([vi] * ncol, [vi] * ncol))
            continue
        f = min(1.0, w / wref)
        v1 = min(0.13, d1 / w)
        v2 = min(0.34, max(v1 + 0.05, d2 / w))
        fu = min(fuller, 0.5 - v2 - 0.02)
        e0 = mb.add(to3(o, 0.0))
        e1 = mb.add(to3(i, 0.0))
        cols = []
        for side in (1, -1):
            row = [e0]
            for v, h in ((v1, h1), (v2, h2), (0.5 - fu, hr), (0.5 + fu, hr), (1 - v2, h2), (1 - v1, h1)):
                row.append(mb.add(to3(o.lerp(i, v), side * h * f)))
            row.append(e1)
            cols.append(row)
        stations.append((cols[0], cols[1]))
    mats = [SV, SV, CH, SV, CH, SV, SV]
    for k in range(len(stations) - 1):
        for side in (0, 1):
            A, B = stations[k][side], stations[k + 1][side]
            for c in range(ncol - 1):
                q = [A[c], B[c], B[c + 1], A[c + 1]]
                if side == 1:
                    q.reverse()
                mb.face(q, mats[c])


def petal(mb, phi, a_rear, a_front, hw0, hub_r, n=8, sweep=0.0, h_wall=0.019, h_top=0.027, h_crest=0.034):
    """A raised, pointed root plate on the hub (the flowing base each blade grows from): a
    steep silver wall, a gently rising black top, a sharp crest; it tapers to a point at a_front
    and sweeps sideways by `sweep` radians at the point. hub_r(a) is the hub's radius at a."""
    rows = []
    for k in range(n):
        t = k / (n - 1)
        a = a_rear + t * (a_front - a_rear)
        hw = hw0 * (1 - t) ** 0.8
        sc = min(1.0, 0.35 + 1.3 * (1 - t))
        r = hub_r(a)
        ph = phi + sweep * t * t
        if hw < 1e-6:
            vi = mb.add(polar(r + 0.003, ph, a))
            rows.append([vi] * 7)
            continue
        row = []
        for c, h in ((-1.0, -0.007), (-0.90, h_wall), (-0.45, h_top), (0.0, h_crest),
                     (0.45, h_top), (0.90, h_wall), (1.0, -0.007)):
            row.append(mb.add(polar(r + h * sc, ph + c * hw / r, a)))
        rows.append(row)
    mats = [SV, CH, CH, CH, CH, SV]
    for k in range(n - 1):
        A, B = rows[k], rows[k + 1]
        for c in range(6):
            mb.face([A[c], A[c + 1], B[c + 1], B[c]], mats[c])
        mb.face([A[6], B[6], B[0], A[0]], CH)   # the underside, inside the hub: keeps it closed
    mb.face(list(reversed(rows[0])), CH)


def cyl_map(R, Y, phi0):
    """(u, v, h) on a cylinder of radius R at station Y, u round it from angle phi0, v along
    the cue, h out of the surface."""
    def fn(u, v, h):
        th = phi0 + u / R
        return ((R + h) * math.cos(th), Y + v, (R + h) * math.sin(th))
    return fn


def dome_map(Y, R, SY=1.0):
    """(u, v, h) on the end face of a dome (centre Y, radius R, squashed SY along the cue):
    (u, v) in the pole's tangent plane, h along the surface normal."""
    def fn(u, v, h):
        x, z = v, u
        s = max(1e-6, R ** 2 - x * x - z * z)
        y = Y - SY * math.sqrt(s)
        nrm = Vector((x / R ** 2, (y - Y) / (SY * R) ** 2, z / R ** 2)).normalized()
        return tuple(Vector((x, y, z)) + nrm * h)
    return fn


def bezel(mb, mapfn, outer, inner_scale, h_top, mat_top=SV, subdiv=2):
    """A raised frame round a gem: outer polygon as (u, v), its edges subdivided to hug the
    surface, the top mat_top, the walls black."""
    pts = []
    for i in range(len(outer)):
        (u0, v0), (u1, v1) = outer[i], outer[(i + 1) % len(outer)]
        for k in range(subdiv):
            t = k / subdiv
            pts.append((u0 + t * (u1 - u0), v0 + t * (v1 - v0)))
    outer = pts
    inner = [(u * inner_scale, v * inner_scale) for (u, v) in outer]
    n = len(outer)
    ob = [mb.add(mapfn(u, v, -0.004)) for (u, v) in outer]
    ot = [mb.add(mapfn(u, v, h_top)) for (u, v) in outer]
    it = [mb.add(mapfn(u, v, h_top)) for (u, v) in inner]
    ib = [mb.add(mapfn(u, v, -0.004)) for (u, v) in inner]
    for i in range(n):
        i1 = (i + 1) % n
        mb.face([ob[i], ob[i1], ot[i1], ot[i]], CH)
        mb.face([ot[i], ot[i1], it[i1], it[i]], mat_top)
        mb.face([it[i], it[i1], ib[i1], ib[i]], CH)
        mb.face([ib[i], ib[i1], ob[i1], ob[i]], CH)


def hourglass(mb, mapfn, H, W, waist, h_apex, h_mid):
    """A faceted red hourglass: two triangles point to point, each a low pyramid."""
    for sgn in (1, -1):
        tri = [(sgn * H / 2, -W / 2), (sgn * H / 2, W / 2), (sgn * waist, 0.0)]
        if sgn < 0:
            tri = [tri[1], tri[0], tri[2]]
        cu = sum(p[0] for p in tri) / 3
        cv = sum(p[1] for p in tri) / 3
        base = [mb.add(mapfn(u, v, -0.003)) for (u, v) in tri]
        mid = [mb.add(mapfn(cu + (u - cu) * 0.72, cv + (v - cv) * 0.72, h_mid)) for (u, v) in tri]
        apex = mb.add(mapfn(cu, cv, h_apex))
        mb.face([base[2], base[1], base[0]], RD)
        for i in range(3):
            i1 = (i + 1) % 3
            mb.face([base[i], base[i1], mid[i1], mid[i]], RD)
            mb.face([mid[i], mid[i1], apex], RD)


HEX = [(0.112, 0.0), (0.080, 0.060), (-0.080, 0.060), (-0.112, 0.0), (-0.080, -0.060), (0.080, -0.060)]
HEX_SMALL = [(0.084, 0.0), (0.060, 0.045), (-0.060, 0.045), (-0.084, 0.0), (-0.060, -0.045), (0.060, -0.045)]


def ferrule(mb, y0=-0.25, rscale=0.98):
    """D's spearhead ferrule: a short lathe neck, a four-flanged faceted broadhead with the
    corners on the axes, four backward barbs, a silver ring and four rear spikes on the
    diagonals; rscale trims it across (0.98: 0.20 across, the lane's limit)."""
    lathe(mb, [(y0, 0.050), (y0 - 0.01, 0.0575), (-0.30, 0.050)], 12, mats=[SV, CH])
    stations = [(-0.25, 0.049, 0.048), (-0.33, 0.064, 0.050), (-0.45, 0.085, 0.053),
                (-0.565, 0.0985, 0.056), (-0.615, 0.086, 0.059), (-0.655, 0.066, 0.060)]
    loops = []
    for (y, rc, rm) in stations:
        ring = []
        for j in range(8):
            ph = TAU * j / 8
            ring.append(polar(rc if j % 2 == 0 else rm, ph, y))
        loops.append(ring)
    loops_mesh(mb, loops, [CH, CH, CH, CH, CH])
    BARB = [(-0.555, 0.0985), (-0.64, 0.0995), (-0.72, 0.1005), (-0.79, 0.1015),
            (-0.745, 0.086), (-0.70, 0.074), (-0.655, 0.064), (-0.60, 0.050)]
    for k in range(4):
        fin(mb, BARB, TAU * k / 4, [(0.006, 0.40, 0.0045, SV)], wref=0.03, tipdeg=70)
    lathe(mb, [(-0.69, 0.057), (-0.696, 0.0785), (-0.754, 0.0785), (-0.76, 0.057)], 12,
          mats=[SV, SV, SV])
    SPIKE = [(-0.77, 0.084), (-0.835, 0.090), (-0.925, 0.0965), (-0.875, 0.079), (-0.835, 0.071),
             (-0.80, 0.054), (-0.77, 0.056)]
    for k in range(4):
        fin(mb, SPIKE, TAU * k / 4 + TAU / 8, [(0.005, 0.40, 0.004, SV)], wref=0.03, tipdeg=70)
    mb.scale_radial(rscale)


def to_bmesh(mb, bm, uvl, uv_of):
    """Add an MB's geometry to a bmesh; every loop of a face gets the same atlas UV from
    uv_of(material, centre, normal) (a flat swatch per facet)."""
    verts = [bm.verts.new(Vector(v)) for v in mb.v]
    made = 0
    for idx, mat in zip(mb.f, mb.m):
        try:
            f = bm.faces.new([verts[i] for i in idx])
        except ValueError:
            continue
        f.normal_update()
        uv = uv_of(mat, f.calc_center_median(), f.normal)
        if uvl is not None:
            for lp in f.loops:
                lp[uvl].uv = uv
        made += 1
    return made
