#!/usr/bin/env python3
"""Tutorial v2: when and from where should the disguised tutorial bot walk in?

A brand-new player spawns, follows the arrow to an empty 1v1 table and steps onto its queue pad.
A bot dressed as a player must step onto the same pad 0.5-2 s later, walking in like a real
player, and must never be seen popping into existence. This script simulates thousands of joins
(seeded, deterministic: same seed, same numbers) and measures:

  * the wait from "player steps on" to "bot steps on" (target: >= 95% under 2 s),
  * every time the bot appears or vanishes (first placement, teleports): was it on the new
    player's real screen at that moment (target: never), or on any other player's screen,
  * how often the new player saw the bot standing while it waited.

Two plans are simulated in full, then variants that change one thing each:
  Plan A  open roof: the bot waits at a "home" spot off the new player's screen and teleports
          only where the server, from camera reports, knows nobody can see it appear;
  Plan B  one small closed kiosk at (0, 36): the bot is built inside and walks out.
Both use the same trigger: start walking when the bot's walk time >= the player's time to
arrive + 1.0 s.

Map, tables, pads, cameras and player behaviour follow the tutorial-v2 brief (2026-10-09). World
studs, Y up, seconds; angles are degrees in the comments. Python 3.9 standard library only;
pictures are hand-written SVG.

Usage:
  python3 tools/tutorial_v2_bot_arrival.py                       # 3000 joins a plan + variants
  python3 tools/tutorial_v2_bot_arrival.py --runs 6000 --seed 7
  python3 tools/tutorial_v2_bot_arrival.py --quick               # small smoke test
  python3 tools/tutorial_v2_bot_arrival.py --out DIR             # where results go
Writes results.md, map.svg and waits.svg to --out (default:
~/Desktop/8ball-refs/tutorial/sim-2026-10-09/bot-arrival).
"""

import argparse
import bisect
import heapq
import math
import os
import random
import sys
import time

DEG = math.pi / 180.0
BIG = 1.0e9

# ------------------------------------------------------------------------------- the map --
X_MIN, X_MAX, Z_MIN, Z_MAX = -94.0, 94.0, -103.0, 107.0
# id, X, Z, players a side
TABLES = [
    (1, -54.0, 47.25, 1), (2, -18.0, 47.25, 1), (3, 18.0, 47.25, 1), (4, 54.0, 47.25, 1),
    (5, -54.0, 15.75, 1), (6, -18.0, 15.75, 1), (7, 18.0, 15.75, 1), (8, 54.0, 15.75, 1),
    (9, -54.0, -15.75, 2), (10, -18.0, -15.75, 2), (11, 18.0, -15.75, 1), (12, 54.0, -15.75, 1),
    (13, -54.0, -47.25, 2), (14, -18.0, -47.25, 2), (15, 18.0, -47.25, 3), (16, 54.0, -47.25, 3),
]
TABLE_BY_ID = {t[0]: t for t in TABLES}
ONE_V_ONE = [t[0] for t in TABLES if t[3] == 1]
TEAM_TABLES = [t[0] for t in TABLES if t[3] > 1]
TABLE_HX, TABLE_HZ = 9.5, 5.5           # the solid block: 19 x 11
PAD_DZ, PAD_HX, PAD_HZ = 10.55, 9.5, 4.0  # the queue pad: 19 x 8, on the spawn (+Z) side
SPAWN_X, SPAWN_Z, SPAWN_HX, SPAWN_HZ = 0.0, 76.75, 8.0, 3.0  # 16 x 6


def _props():
    """Small collidable props: (centre X, centre Z, half X, half Z)."""
    p = []
    for sx in (-1, 1):
        p.append((36.0 * sx, 35.0, 2.0, 2.0))     # planters
        p.append((36.0 * sx, -28.0, 2.0, 2.0))
        p.append((15.0 * sx, 79.5, 1.0, 1.0))     # tall lanterns by the spawn
        p.append((20.0 * sx, 80.0, 2.0, 2.0))     # palm planters by the spawn
    for z in range(-96, 100, 16):                 # lantern posts along both side edges
        p.append((-89.5, float(z), 1.0, 1.0))
        p.append((88.0, float(z), 1.0, 1.0))
    for z in (-64.0, -32.0, 0.0, 32.0, 64.0):      # planter beds along both side edges
        p.append((-90.5, z, 1.5, 4.0))
        p.append((90.5, z, 1.5, 4.0))
    for z in (47.0, 16.0, -16.0, -47.0):           # couches and umbrellas (east edge)
        p.append((87.5, z, 4.5, 4.0))
    return p


PROPS = _props()
AGENT_R = 1.5   # a character's half-width plus a little clearance, for walking past blocks


def table_rect(k):
    _, x, z, _ = TABLE_BY_ID[k]
    return (x - TABLE_HX, x + TABLE_HX, z - TABLE_HZ, z + TABLE_HZ)


def pad_rect(k):
    _, x, z, _ = TABLE_BY_ID[k]
    return (x - PAD_HX, x + PAD_HX, z + PAD_DZ - PAD_HZ, z + PAD_DZ + PAD_HZ)


def in_rect(r, x, z, grow=0.0):
    return r[0] - grow <= x <= r[1] + grow and r[2] - grow <= z <= r[3] + grow


OBSTACLES = [table_rect(t[0]) for t in TABLES] + [
    (cx - hx, cx + hx, cz - hz, cz + hz) for (cx, cz, hx, hz) in PROPS]
SPAWN_RECT = (SPAWN_X - SPAWN_HX, SPAWN_X + SPAWN_HX, SPAWN_Z - SPAWN_HZ, SPAWN_Z + SPAWN_HZ)

# ----------------------------------------------------------------------- people & camera --
PLAYER_SPEED = 20.8       # Config.Hub.WalkSpeed
NAT_RANGE = (1.15, 1.25)  # the bot's natural-walk overhead: stop-and-go, slight curves
NAT_EST = 1.20            # what the server assumes for that overhead when it plans
FOCUS_Y = 3.6             # the follow camera looks at about chest height (camera at Y ~8)
FOLLOW_DIST = 13.0        # Roblox default follow distance
FOLLOW_PITCH = -20.0      # degrees: camera ~4.8 studs above the root, 12 behind
BODY_Y, BODY_HW, BODY_HH = 2.7, 1.0, 2.7  # an avatar as a 2 x 5.4 box centred at Y 2.7
PHONE_ASPECT, PC_ASPECT = 2.16, 16.0 / 9.0

# ------------------------------------------------------------------------ the simulation --
DT = 0.05                 # physics step
SERVER_EVERY = 2          # the bot's brain runs every 0.1 s
T_START = -3.0            # the bot is ready (in a hidden room) 3 s before the player's first frame
WARMUP = 1.0              # the other players run this long first, so the server has reports
SEARCH_RETRY = 0.3        # after a failed spot search, wait this long before searching again
PLACE_SLACK = 0.6         # a first spot may be up to this much farther (seconds) than the home
HOME_WALK_MARGIN = 5.0 * DEG  # a home stays this far outside the view of a player walking to it
TIMEOUT = 15.0            # a wait this long counts as "never came"
HEAD_COS = math.cos(35.0 * DEG)  # "heading toward a pad": within 35 degrees of its path
MOVE_MIN = 6.0            # studs/s (smoothed) before the player counts as walking
HOLD_DIST = 3.0           # an early bot idles this far (path) from the pad's edge
MIN_WAIT = 0.5            # never step on sooner than this after the player
MIN_WALK = 0.8            # a re-staged bot walks at least this long before stepping on
LATE_TOL = 0.5            # re-stage when the plan would arrive this much after the target
MIN_TP_GAP = 0.5          # seconds between two teleports
TP_STABLE = 0.3           # a "late" teleport only once the predicted pad held this long
MIN_GAIN = 1.0            # ... and only if it saves at least this many seconds of walking
NEAR_CHAR = 10.0          # never appear this close to any character
NEAR_SEEN = 50.0          # a pop-in closer than this to a camera is hard to miss
DODGE_EXTRA = 30.0 * DEG  # dodge when the new player's view comes this close to the bot
NET_LAT = (0.03, 0.12)    # one-way network delay (camera reports up, teleports down)
TURN_UNKNOWN = 90.0 * DEG  # turn speed assumed (rad/s) before two reports have arrived
LOOKER_TURN = 60.0 * DEG   # a new player who turned the camera faster than this (rad/s) ...
LOOKER_WINDOW = 1.5        # ... within this many seconds counts as "looking around" ...
LOOKER_MARGIN = 45.0 * DEG  # ... and their view is widened this much more on both sides
HEADING_MARGIN = 20.0 * DEG  # a walking camera points along the walk, +- this
MAX_SWING = 200.0 * DEG   # a camera swing never goes further than this
CAND_STEP = 3.0           # staging candidates: a grid this many studs apart
# Variant "doors": small closed huts (stairwell / lift doors, about 4 x 4 x 8) the bot appears
# inside, unseen by anyone, and walks out of. Door fronts (X, Z), clear of every route.
DOORS = [(-28.0, 86.0), (28.0, 86.0), (-80.0, 36.0), (80.0, 36.0), (-80.0, 4.0), (80.0, 4.0)]
SPAWN_SPOTS = [(x, z) for x in (-6.0, -3.0, 0.0, 3.0, 6.0) for z in (74.5, 76.75, 79.0)]


class Policy:
    """The bot's server rules. Defaults are the recommended rules."""

    def __init__(self, name="recommended", **kw):
        self.name = name
        self.bot_speed = 20.8        # studs/s, same as real players
        self.trigger = "eta"         # "eta": time-to-arrive matching; "dist": distance D
        self.trigger_dist = 0.0
        self.target_delay = 1.0      # aim to step on this long after the player
        self.restage = True          # teleport (unseen) when it would be late
        self.dodge = False           # teleport away (unseen) when the new player turns to it
        self.margin_deg = 15.0       # safety margin around every reported camera view
        self.report_hz = 4.0         # camera CFrame reports a second, per player
        self.view_range = 120.0      # beyond this a pop-in is too small to notice
        self.place_check = True      # place from the hidden room only where nobody looks
        self.home_mode = "auto"      # "auto": a home per arrow table; "behind": one spot;
        #                              "doors": appear only inside small closed huts (DOORS);
        #                              "spawnpad": stay hidden, then appear on the spawn pad
        #                              like a joining player once the new player has left it
        self.pre_spawn = 3.0         # seconds the bot is ready before the player's first frame
        self.late_level = 3          # most lenient spot level a "late" teleport may use
        self.doors = None            # door list for home_mode "doors" (default DOORS)
        for k, v in kw.items():
            if not hasattr(self, k):
                raise KeyError(k)
            setattr(self, k, v)

    @property
    def stale(self):
        # the oldest a camera report can be by the time the teleport shows on that screen
        return 1.0 / self.report_hz + 2 * NET_LAT[1]


# ======================================================================= walking grid =====
CELL = 1.0
NX = int(round((X_MAX - X_MIN) / CELL))
NZ = int(round((Z_MAX - Z_MIN) / CELL))
BORDER = 2
GW = NX + 2 * BORDER
GH = NZ + 2 * BORDER


def cell_of(x, z):
    i = int((x - X_MIN) / CELL) + BORDER
    j = int((z - Z_MIN) / CELL) + BORDER
    i = min(max(i, BORDER), BORDER + NX - 1)
    j = min(max(j, BORDER), BORDER + NZ - 1)
    return j * GW + i


def cell_centre(c):
    j, i = divmod(c, GW)
    return X_MIN + (i - BORDER + 0.5) * CELL, Z_MIN + (j - BORDER + 0.5) * CELL


def build_blocked():
    blk = bytearray([1]) * (GW * GH)
    for j in range(NZ):
        z = Z_MIN + (j + 0.5) * CELL
        if z < Z_MIN + AGENT_R or z > Z_MAX - AGENT_R:
            continue
        row = (j + BORDER) * GW + BORDER
        for i in range(NX):
            x = X_MIN + (i + 0.5) * CELL
            if X_MIN + AGENT_R <= x <= X_MAX - AGENT_R:
                blk[row + i] = 0
    for (x0, x1, z0, z1) in OBSTACLES:
        x0 -= AGENT_R
        x1 += AGENT_R
        z0 -= AGENT_R
        z1 += AGENT_R
        i0 = max(0, int(math.ceil((x0 - X_MIN) / CELL - 0.5)))
        i1 = min(NX - 1, int(math.floor((x1 - X_MIN) / CELL - 0.5)))
        j0 = max(0, int(math.ceil((z0 - Z_MIN) / CELL - 0.5)))
        j1 = min(NZ - 1, int(math.floor((z1 - Z_MIN) / CELL - 0.5)))
        for j in range(j0, j1 + 1):
            row = (j + BORDER) * GW + BORDER
            for i in range(i0, i1 + 1):
                blk[row + i] = 1
    return blk


BLK = build_blocked()


def _neighbours():
    """16 moves (4 straight, 4 diagonal, 8 knight) with the cells each must not cut."""
    out = []
    for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        out.append((dj * GW + di, 1.0, 0, 0))
    for si in (-1, 1):
        for sj in (-1, 1):
            out.append((sj * GW + si, math.sqrt(2.0), si, sj * GW))
            out.append((sj * GW + 2 * si, math.sqrt(5.0), si, sj * GW + si))
            out.append((2 * sj * GW + si, math.sqrt(5.0), sj * GW, sj * GW + si))
    return out


NBRS = _neighbours()


def distance_field(rect):
    """Shortest walking distance from every cell to the nearest point of `rect` (a pad)."""
    dist = [BIG] * (GW * GH)
    heap = []
    for j in range(NZ):
        for i in range(NX):
            c = (j + BORDER) * GW + i + BORDER
            if BLK[c]:
                continue
            x, z = cell_centre(c)
            if in_rect(rect, x, z):
                dist[c] = 0.0
                heap.append((0.0, c))
    heapq.heapify(heap)
    blk = BLK
    nbrs = NBRS
    pop = heapq.heappop
    push = heapq.heappush
    while heap:
        d, u = pop(heap)
        if d > dist[u]:
            continue
        for off, cost, r1, r2 in nbrs:
            v = u + off
            if blk[v] or blk[u + r1] or blk[u + r2]:
                continue
            nd = d + cost
            if nd < dist[v]:
                dist[v] = nd
                push(heap, (nd, v))
    return dist


def fval(F, x, z):
    """Walking distance to the field's pad from a point (bilinear between cell centres)."""
    fx = (x - X_MIN) / CELL - 0.5 + BORDER
    fz = (z - Z_MIN) / CELL - 0.5 + BORDER
    i0 = int(fx)
    j0 = int(fz)
    tx = fx - i0
    tz = fz - j0
    k = j0 * GW + i0
    a = F[k]
    b = F[k + 1]
    c = F[k + GW]
    d = F[k + GW + 1]
    if a < BIG and b < BIG and c < BIG and d < BIG:
        return (a * (1 - tx) + b * tx) * (1 - tz) + (c * (1 - tx) + d * tx) * tz
    best = BIG
    for dj in (-2, -1, 0, 1, 2, 3):
        for di in (-2, -1, 0, 1, 2, 3):
            kk = (j0 + dj) * GW + i0 + di
            if 0 <= kk < len(F):
                v = F[kk]
                if v < BIG:
                    cx, cz = cell_centre(kk)
                    dd = v + math.hypot(x - cx, z - cz)
                    if dd < best:
                        best = dd
    return best


def grid_path(F, x, z, rect):
    """A walking route from (x, z) to the pad: cell centres down the field, then a point
    well inside the pad. Agents follow it with a short look-ahead, which smooths it."""
    u = cell_of(x, z)
    if F[u] >= BIG:
        best, bu = BIG, u
        for dj in range(-4, 5):
            for di in range(-4, 5):
                v = u + dj * GW + di
                if 0 <= v < len(F) and F[v] < best and not BLK[v]:
                    best, bu = F[v] + math.hypot(di, dj), v
        u = bu
    pts = [(x, z)]
    guard = 0
    while F[u] > 0.0 and guard < 3000:
        guard += 1
        best, bv = BIG, -1
        for off, cost, r1, r2 in NBRS:
            v = u + off
            if BLK[v] or BLK[u + r1] or BLK[u + r2]:
                continue
            val = F[v] + cost
            if val < best:
                best, bv = val, v
        if bv < 0 or F[bv] >= F[u]:
            break
        u = bv
        pts.append(cell_centre(u))
    lx, lz = pts[-1]
    pts.append((min(max(lx, rect[0] + 2.5), rect[1] - 2.5), min(max(lz, rect[2] + 2.0), rect[3] - 2.0)))
    return pts


def line_clear(x0, z0, x1, z1):
    n = int(math.hypot(x1 - x0, z1 - z0) / 0.5) + 1
    for s in range(n + 1):
        t = s / n
        if BLK[cell_of(x0 + (x1 - x0) * t, z0 + (z1 - z0) * t)]:
            return False
    return True


def free_at(x, z):
    return not BLK[cell_of(x, z)]


# ============================================================================= cameras =====
def fov_consts(vfov_half_deg, aspect):
    tv = math.tan(vfov_half_deg * DEG)
    th = tv * aspect
    return (th, tv, math.atan(th), math.atan(tv))


PHONE_FOLLOW = fov_consts(35.0, PHONE_ASPECT)
PC_FOLLOW = fov_consts(35.0, PC_ASPECT)
PHONE_MATCH = fov_consts(30.0, PHONE_ASPECT)   # the in-match aim view (Config.Camera.View)
PC_MATCH = fov_consts(30.0, PC_ASPECT)


def build_cam(fx, fy, fz, yaw, pitch, dist, consts):
    """Camera looking at focus (fx, fy, fz) from `dist` away. yaw 0 looks along -Z, 90 along
    +X; pitch < 0 looks down. Returns the tuple the visibility tests read."""
    cp = math.cos(pitch)
    sp = math.sin(pitch)
    hx = math.sin(yaw)
    hz = -math.cos(yaw)
    f0, f1, f2 = cp * hx, sp, cp * hz
    th, tv, hh, hv = consts
    return (fx - dist * f0, fy - dist * f1, fz - dist * f2, f0, f1, f2,
            -hz, hx, -sp * hx, cp, -sp * hz, th, tv, hh, hv)


def true_seen(cam, px, pz, rng):
    """Is an avatar standing at (px, pz) on this screen right now (exact frustum)?"""
    cx, cy, cz, f0, f1, f2, r0, r2, u0, u1, u2, th, tv, hh, hv = cam
    dx = px - cx
    dy = BODY_Y - cy
    dz = pz - cz
    if dx * dx + dy * dy + dz * dz > rng * rng:
        return False
    zc = dx * f0 + dy * f1 + dz * f2
    if zc <= 0.3:
        return False
    xc = dx * r0 + dz * r2
    if abs(xc) > zc * th + BODY_HW:
        return False
    yc = dx * u0 + dy * u1 + dz * u2
    return abs(yc) <= zc * tv + BODY_HH


def server_seen(cam, px, pz, rng, m_lo, m_hi, mv):
    """The server's cautious test on a reported camera: the view widened by m_lo radians on
    its left, m_hi on its right (more on the side it is turning toward) and mv up and down."""
    cx, cy, cz, f0, f1, f2, r0, r2, u0, u1, u2, th, tv, hh, hv = cam
    dx = px - cx
    dy = BODY_Y - cy
    dz = pz - cz
    d = math.sqrt(dx * dx + dy * dy + dz * dz) + 1e-6
    if d > rng + 10.0:
        return False
    zc = dx * f0 + dy * f1 + dz * f2
    xc = dx * r0 + dz * r2
    w = math.atan2(BODY_HW, d)
    a = math.atan2(xc, zc)          # + is right of the screen centre
    right = hh + m_hi + w
    left = hh + m_lo + w
    if a >= 0.0:
        inside = a <= right or (2 * math.pi - a) <= left
    else:
        inside = -a <= left or (2 * math.pi + a) <= right
    if not inside:
        return False
    yc = dx * u0 + dy * u1 + dz * u2
    return math.atan2(abs(yc), math.hypot(xc, zc)) <= hv + mv + math.atan2(BODY_HH, d)


def outside_margin(cam, px, pz, rng):
    """How many radians outside this view a point is (negative: inside)."""
    cx, cy, cz, f0, f1, f2, r0, r2, u0, u1, u2, th, tv, hh, hv = cam
    dx = px - cx
    dy = BODY_Y - cy
    dz = pz - cz
    d = math.sqrt(dx * dx + dy * dy + dz * dz) + 1e-6
    if d > rng:
        return math.pi / 2
    zc = dx * f0 + dy * f1 + dz * f2
    xc = dx * r0 + dz * r2
    yc = dx * u0 + dy * u1 + dz * u2
    oh = math.atan2(abs(xc), zc) - hh - math.atan2(BODY_HW, d)
    ov = math.atan2(abs(yc), math.hypot(xc, zc)) - hv - math.atan2(BODY_HH, d)
    return max(oh, ov)


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def heading_yaw(vx, vz):
    return math.atan2(vx, -vz)


# =========================================================================== precompute =====
class World:
    """Everything that does not change between runs: distance fields, candidate spots."""

    def __init__(self):
        t0 = time.time()
        self.F = {k: distance_field(pad_rect(k)) for k in ONE_V_ONE}
        self.t_fields = time.time() - t0
        cands = []
        x = -CAND_STEP * int((X_MAX - 3.0) / CAND_STEP)       # symmetric about X = 0
        while x <= X_MAX - 3.0:
            z = -CAND_STEP * int((-Z_MIN - 3.0) / CAND_STEP)
            while z <= Z_MAX - 3.0:
                ok = all(free_at(x + ox, z + oz) for ox, oz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)))
                if ok and not any(in_rect(pad_rect(t[0]), x, z, 2.0) for t in TABLES) \
                        and not in_rect(SPAWN_RECT, x, z, 4.0):
                    cands.append((x, z))
                z += CAND_STEP
            x += CAND_STEP
        self.cands = cands
        self.CF = {k: [fval(self.F[k], cx, cz) for (cx, cz) in cands] for k in ONE_V_ONE}
        self.by_dist = {k: sorted((d, ci) for ci, d in enumerate(self.CF[k])) for k in ONE_V_ONE}
        self.by_dist_keys = {k: [d for d, _ in self.by_dist[k]] for k in ONE_V_ONE}
        # how far outside the new player's first view (spawn, facing the tables) each spot is
        spawn_cams = []
        for sx in (-7.0, -3.5, 0.0, 3.5, 7.0):
            for sz in (74.5, 76.75, 79.0):
                spawn_cams.append(build_cam(sx, FOCUS_Y, sz, 0.0, FOLLOW_PITCH * DEG,
                                            FOLLOW_DIST, PHONE_FOLLOW))
        self.spawn_margin = [min(outside_margin(c, cx, cz, 120.0) for c in spawn_cams)
                             for (cx, cz) in cands]
        self.homes = {}
        self.walk_margin = {}

    def walk_margins(self, k):
        """How far outside the view of a player walking from the spawn toward pad k (camera
        along the walk +-20 degrees, first 10 studs) each candidate spot is."""
        if k in self.walk_margin:
            return self.walk_margin[k]
        cams = []
        for sx in (-6.0, 0.0, 6.0):
            path = grid_path(self.F[k], sx, SPAWN_Z, pad_rect(k))
            pts = [(sx, SPAWN_Z)]
            acc = 0.0
            for i in range(1, len(path)):
                acc += math.hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1])
                if acc >= 5.0 * len(pts):
                    pts.append(path[i])
                if len(pts) == 3:
                    break
            for j in range(len(pts) - 1):
                hy = heading_yaw(pts[j + 1][0] - pts[j][0], pts[j + 1][1] - pts[j][1])
                for off in (-20.0, 0.0, 20.0):
                    cams.append(build_cam(pts[j][0], FOCUS_Y, pts[j][1], hy + off * DEG,
                                          FOLLOW_PITCH * DEG, FOLLOW_DIST, PHONE_FOLLOW))
        out = [min(outside_margin(c, cx, cz, 120.0) for c in cams) for (cx, cz) in self.cands]
        self.walk_margin[k] = out
        return out

    def homes_for(self, speed):
        """The waiting spot for each arrow table: out of the spawn view by a margin and close
        enough that the bot can arrive about 1 s after a player who walks straight there."""
        if speed in self.homes:
            return self.homes[speed]
        out = {}
        for k in ONE_V_ONE:
            Wk = fval(self.F[k], SPAWN_X, SPAWN_Z) / PLAYER_SPEED
            wm = self.walk_margins(k)
            best, bkey = None, None
            for ci, (cx, cz) in enumerate(self.cands):
                m = self.spawn_margin[ci]
                if m < 20.0 * DEG or wm[ci] < HOME_WALK_MARGIN:
                    continue
                if math.hypot(cx - SPAWN_X, cz - SPAWN_Z) < 22.0:
                    continue
                T = self.CF[k][ci] * NAT_EST / speed
                if T <= Wk + 0.6:   # fits: prefer hidden by angle (not just by distance), margin
                    key = (2, 1 if m < 89.0 * DEG else 0, min(m, 40.0 * DEG), -abs(T - (Wk + 0.3)))
                else:               # nothing fits: the shortest walk
                    key = (1, 0, 0.0, -T)
                if bkey is None or key > bkey:
                    best, bkey = ci, key
            cx, cz = self.cands[best]
            out[k] = (cx, cz, self.CF[k][best] * NAT_EST / speed, self.spawn_margin[best] / DEG, Wk)
        self.homes[speed] = out
        return out


# =================================================================== moving people =========
class Agent:
    """A person on the roof: position, camera and (for the server) camera reports."""
    __slots__ = ("kind", "x", "z", "yaw", "pitch", "dist", "consts", "focus", "tyaw", "tpitch",
                 "rate", "hold", "drift", "tx", "tz", "pause", "speed", "next_send", "pend",
                 "snap", "psnap", "vx", "vz")

    def __init__(self, kind, x, z, consts):
        self.kind = kind
        self.x, self.z = x, z
        self.yaw = 0.0
        self.pitch = FOLLOW_PITCH * DEG
        self.dist = FOLLOW_DIST
        self.consts = consts
        self.focus = None      # (x, y, z) for a match camera
        self.tyaw = 0.0
        self.tpitch = self.pitch
        self.rate = 0.0
        self.hold = 0.0
        self.drift = 0.0
        self.tx = self.tz = 0.0
        self.pause = 0.0
        self.speed = 0.0
        self.next_send = 0.0
        self.pend = []
        self.snap = None
        self.psnap = None
        self.vx = self.vz = 0.0

    def cam(self):
        if self.focus is not None:
            return build_cam(self.focus[0], self.focus[1], self.focus[2], self.yaw, self.pitch,
                             self.dist, self.consts)
        return build_cam(self.x, FOCUS_Y, self.z, self.yaw, self.pitch, self.dist, self.consts)


def look_around(a, rs, dt, holds=(0.3, 1.5), rates=(120.0, 360.0), pitches=(-45.0, 5.0)):
    """Drag the camera: hold, then swing to a new direction, repeat."""
    if a.hold > 0.0:
        a.hold -= dt
        return
    dy = wrap(a.tyaw - a.yaw)
    step = a.rate * dt
    if abs(dy) <= step:
        a.yaw = a.tyaw
        a.pitch = a.tpitch
        a.hold = rs.uniform(*holds)
        a.tyaw = wrap(a.yaw + rs.choice((-1.0, 1.0)) * rs.uniform(30.0, 180.0) * DEG)
        a.tpitch = rs.uniform(*pitches) * DEG
        a.rate = rs.uniform(*rates) * DEG
    else:
        frac = step / abs(dy)
        a.yaw = wrap(a.yaw + math.copysign(step, dy))
        a.pitch += (a.tpitch - a.pitch) * frac


def follow_camera(a, rs, dt, vx, vz):
    """A walking player's camera swings to point along the walk, +-20 degrees."""
    a.drift += (-a.drift * 0.8 + rs.gauss(0.0, 1.0) * 60.0 * DEG) * dt
    a.drift = max(-20.0 * DEG, min(20.0 * DEG, a.drift))
    want = wrap(heading_yaw(vx, vz) + a.drift)
    d = wrap(want - a.yaw)
    step = 240.0 * DEG * dt
    a.yaw = want if abs(d) <= step else wrap(a.yaw + math.copysign(step, d))
    a.pitch += (FOLLOW_PITCH * DEG - a.pitch) * min(1.0, 4.0 * dt)


def random_free_point(rs, near=None, rmin=0.0, rmax=40.0):
    for _ in range(200):
        if near is None:
            x = rs.uniform(X_MIN + 3, X_MAX - 3)
            z = rs.uniform(Z_MIN + 3, Z_MAX - 3)
        else:
            ang = rs.uniform(0, 2 * math.pi)
            r = rs.uniform(rmin, rmax)
            x = near[0] + math.cos(ang) * r
            z = near[1] + math.sin(ang) * r
            if not (X_MIN + 3 <= x <= X_MAX - 3 and Z_MIN + 3 <= z <= Z_MAX - 3):
                continue
        if free_at(x, z):
            return x, z
    return SPAWN_X, SPAWN_Z - 8


def make_others(rs, n, busy):
    """Other players: some playing at tables (aim camera), some walking, some idling."""
    others = []
    left = n
    for k in busy:                                   # each busy 1v1 table: 1 or 2 humans
        for _ in range(1 if rs.random() < 0.4 else 2):
            if left <= 0:
                break
            others.append(("match", k))
            left -= 1
    for _ in range(left):
        r = rs.random()
        if r < 0.35:
            others.append(("match", rs.choice(TEAM_TABLES)))
        elif r < 0.75:
            others.append(("walker", None))
        else:
            others.append(("idle", None))
    agents = []
    for kind, k in others:
        phone = rs.random() < 0.5
        if kind == "match":
            _, tx, tz, _ = TABLE_BY_ID[k]
            a = Agent("match", tx + rs.choice((-12.0, 12.0)), tz, PHONE_MATCH if phone else PC_MATCH)
            a.focus = (tx + rs.uniform(-3, 3), 3.0, tz + rs.uniform(-2, 2))
            a.dist = rs.uniform(15.0, 22.0)
            a.yaw = rs.uniform(-math.pi, math.pi)
            a.pitch = -rs.uniform(50.0, 65.0) * DEG
            a.tyaw, a.tpitch = a.yaw, a.pitch
            a.hold = rs.uniform(0.0, 4.0)
        else:
            consts = PHONE_FOLLOW if phone else PC_FOLLOW
            if rs.random() < 0.4:
                x, z = random_free_point(rs, (SPAWN_X, SPAWN_Z), 4.0, 25.0)
            elif kind == "idle" and rs.random() < 0.5:
                pk = rs.choice(ONE_V_ONE)
                pr = pad_rect(pk)
                x, z = rs.uniform(pr[0] - 3, pr[1] + 3), pr[3] + rs.uniform(1.0, 5.0)
            else:
                x, z = random_free_point(rs)
            a = Agent(kind, x, z, consts)
            a.dist = rs.uniform(11.0, 16.0)
            a.yaw = rs.uniform(-math.pi, math.pi)
            a.tyaw = a.yaw
            a.tpitch = a.pitch
            a.hold = rs.uniform(0.0, 2.0)
            if kind == "walker":
                a.tx, a.tz = random_free_point(rs)
                a.pause = 0.0 if rs.random() < 0.6 else rs.uniform(0.0, 2.0)
        agents.append(a)
    return agents


def update_other(a, rs, dt):
    a.vx = a.vz = 0.0
    if a.kind == "match":
        look_around(a, rs, dt, holds=(1.5, 5.0), rates=(90.0, 240.0), pitches=(-65.0, -50.0))
        a.speed = 0.0
    elif a.kind == "idle":
        look_around(a, rs, dt, holds=(1.0, 6.0))
        a.speed = 0.0
    else:
        if a.pause > 0.0:
            a.pause -= dt
            a.speed = 0.0
            look_around(a, rs, dt)
            if a.pause <= 0.0:
                a.tx, a.tz = random_free_point(rs)
        else:
            dx, dz = a.tx - a.x, a.tz - a.z
            d = math.hypot(dx, dz)
            step = PLAYER_SPEED * dt
            if d <= step:
                a.x, a.z = a.tx, a.tz
                a.pause = rs.uniform(0.5, 3.0)
                a.tyaw = a.yaw
                a.hold = 0.0
                a.speed = 0.0
            else:
                a.x += dx / d * step
                a.z += dz / d * step
                a.speed = PLAYER_SPEED
                a.vx, a.vz = dx / d * PLAYER_SPEED, dz / d * PLAYER_SPEED
                follow_camera(a, rs, dt, dx, dz)


# ======================================================================== one join ========
P_LOOK, P_STRAIGHT, P_PAUSE, P_PATH, P_PAD = range(5)
B_HIDDEN, B_STAGED, B_WALK, B_HOLD, B_DONE = range(5)


class Run:
    """One new player joining, with one bot, simulated from 2 s before spawn to the bot
    stepping onto the player's pad."""

    def __init__(self, world, pol, seed, trace=False):
        self.w = world
        self.pol = pol
        self.rs = random.Random(seed)              # the world: players, cameras, network
        self.rb = random.Random(seed * 7 + 1)      # the bot's own noise
        self.trace = trace
        self.homes = world.homes_for(pol.bot_speed)

    # -------------------------------------------------------------- set the scene -----
    def setup(self):
        rs = self.rs
        self.n_other = rs.randint(0, 25)
        n_busy = min(int(round(rs.uniform(0.0, 0.6) * len(ONE_V_ONE))), self.n_other)
        self.busy = sorted(rs.sample(ONE_V_ONE, n_busy))
        self.empty = [k for k in ONE_V_ONE if k not in self.busy]
        self.others = make_others(rs, self.n_other, self.busy)
        for a in self.others:
            a.next_send = -self.pol.pre_spawn - WARMUP - rs.uniform(0.0, 1.0 / self.pol.report_hz)
        # the new player
        self.phone = rs.random() < 0.5
        self.sx = rs.uniform(SPAWN_X - SPAWN_HX + 1, SPAWN_X + SPAWN_HX - 1)
        self.sz = rs.uniform(SPAWN_Z - SPAWN_HZ + 0.75, SPAWN_Z + SPAWN_HZ - 0.75)
        p = Agent("new", self.sx, self.sz, PHONE_FOLLOW if self.phone else PC_FOLLOW)
        p.next_send = rs.uniform(0.0, 1.0 / self.pol.report_hz)
        self.p = p
        self.turner = rs.random() < 0.5
        self.speed_factor = rs.uniform(0.75, 0.95) if (self.phone and rs.random() < 0.3) else 1.0
        self.t_look = rs.uniform(0.5, 3.0)
        # the server picks the arrow's table when the player joins (nearest empty 1v1 to the
        # spawn centre), so the bot knows where to wait before the player's first frame
        self.arrow = self.nearest_empty(SPAWN_X, SPAWN_Z, 1)[0]
        r = rs.random()
        legs = [(P_LOOK, self.t_look)]
        if r < 0.75:
            self.behaviour = "arrow"
            final = self.arrow
        elif r < 0.95:
            self.behaviour = "other table"
            opts = [k for k in self.nearest_empty(self.sx, self.sz, 4) if k != self.arrow][:3]
            final = rs.choice(opts)
        else:
            self.behaviour = "wander first"
            final = self.arrow
            for _ in range(50):
                wx, wz = random_free_point(rs, (self.sx, self.sz), 15.0, 40.0)
                if line_clear(self.sx, self.sz, wx, wz) and \
                        not any(in_rect(pad_rect(k), wx, wz, 1.0) for k in ONE_V_ONE):
                    break
            legs.append((P_STRAIGHT, (wx, wz)))
            legs.append((P_PAUSE, rs.uniform(0.5, 2.0)))
        self.switch_at = rs.uniform(0.3, 0.7) if rs.random() < 0.10 else None
        legs.append((P_PATH, final))
        self.legs = legs
        self.final_first = final
        self.wob_a = rs.uniform(0.0, 1.0)
        self.wob_l = rs.uniform(12.0, 30.0)
        self.wob_p = rs.uniform(0.0, 2 * math.pi)
        # the bot
        self.bot_nat = self.rb.uniform(*NAT_RANGE)

    def nearest_empty(self, x, z, n):
        return sorted(self.empty, key=lambda k: (fval(self.w.F[k], x, z), k))[:n]

    # -------------------------------------------------------------------- run it -----
    def go(self):
        self.setup()
        rs, rb, pol = self.rs, self.rb, self.pol
        p = self.p
        # player state
        self.leg_i = -1
        self.pstate = None
        self.leg_t = 0.0
        self.path = None
        self.ci = 0
        self.travel = 0.0
        self.path_len = 0.0
        self.cur_k = None
        self.bx, self.bz = self.sx, self.sz      # path-following ("base") position
        self.vsx = self.vsz = 0.0                # smoothed velocity the server sees
        self.prev_px, self.prev_pz = self.sx, self.sz
        self.t_on = None
        self.pad_on = None
        self.onpad_face = rs.random() < 0.5
        self.switched = False
        # bot state
        self.b_state = B_HIDDEN
        self.b_x = self.b_z = None
        self.b_k = None
        self.b_path = None
        self.b_ci = 0
        self.b_paused = False
        self.b_hold_until = None
        self.last_tp = -99.0
        self.last_dodge = -99.0
        self.events = []          # (t, kind, old, new)
        self.pending = []         # (t_show, old, new, kind)
        self.popin_new = 0
        self.popin_other = 0
        self.spawnpad_seen_other = 0
        self.popin_other_near = 0
        self.popout_new = 0
        self.popout_other = 0
        self.seen_kinds_new = []
        self.seen_kinds_other = []
        self.levels = []
        self.n_tp = 0
        self.n_restage_fail = 0
        self.seen_idle_new = False
        self.seen_idle_any = False
        self.k_pred = None
        self.committed = False
        self.wait = None
        self.reason_late = None
        self.trace_p = []
        self.trace_b = []
        self.started_walk_t = None
        self.first_commit_t = None
        self.p_spawned = False
        self.next_search = -99.0
        self.p_last_turn = -99.0
        self.pred_since = 99.0
        self.hold_before = 0.0
        t0_bot = -self.pol.pre_spawn
        t = t0_bot - WARMUP
        step = 0
        end_t = 60.0
        while t < end_t:
            if t >= 0.0 and not self.p_spawned:
                self.p_spawned = True
                self.next_leg(t)
            # world
            if step % SERVER_EVERY == 0:
                for a in self.others:
                    update_other(a, rs, DT * SERVER_EVERY)
            if self.p_spawned:
                self.update_player(t)
            # pending "did anyone see that appear?" checks
            if self.pending:
                self.check_pending(t)
            if step % SERVER_EVERY == 0:
                self.reports(t)
                if t >= t0_bot - 1e-9:
                    self.server(t)
            self.update_bot(t)
            if self.trace and step % 4 == 0:
                if self.p_spawned:
                    self.trace_p.append((t, p.x, p.z))
                if self.b_state != B_HIDDEN:
                    self.trace_b.append((t, self.b_x, self.b_z, self.b_state))
            if self.b_state == B_DONE:
                break
            if self.t_on is not None and t > self.t_on + TIMEOUT:
                self.wait = TIMEOUT
                self.reason_late = self.reason_late or "timeout"
                break
            t += DT
            step += 1
        if self.wait is None:
            self.wait = TIMEOUT
            self.reason_late = "player never arrived"
        return self

    # ---------------------------------------------------------------- the player -----
    def next_leg(self, t):
        self.leg_i += 1
        kind, arg = self.legs[self.leg_i]
        self.pstate = kind
        self.leg_t = 0.0
        p = self.p
        if kind == P_LOOK:
            p.yaw = 0.0
            p.pitch = FOLLOW_PITCH * DEG
            p.tyaw, p.tpitch = p.yaw, p.pitch
            p.hold = self.rs.uniform(0.0, 0.6)
            self.leg_len = arg
        elif kind == P_PAUSE:
            p.tyaw = p.yaw
            p.hold = 0.0
            self.leg_len = arg
        elif kind == P_STRAIGHT:
            self.path = [(self.bx, self.bz), arg]
            self.ci = 1
            self.cur_k = None
        elif kind == P_PATH:
            self.set_target(arg)

    def set_target(self, k):
        self.cur_k = k
        self.path = grid_path(self.w.F[k], self.bx, self.bz, pad_rect(k))
        self.ci = 1
        self.travel = 0.0
        self.path_len = sum(math.hypot(self.path[i + 1][0] - self.path[i][0],
                                       self.path[i + 1][1] - self.path[i][1])
                            for i in range(len(self.path) - 1))

    def update_player(self, t):
        p = self.p
        rs = self.rs
        st = self.pstate
        vx = vz = 0.0
        if st in (P_LOOK, P_PAUSE):
            self.leg_t += DT
            if st == P_PAUSE or self.turner:
                look_around(p, rs, DT)
            if self.leg_t >= self.leg_len:
                self.next_leg(t)
        elif st in (P_STRAIGHT, P_PATH):
            spd = PLAYER_SPEED * self.speed_factor * DT
            done = follow_path(self, spd)
            self.travel += spd
            dx = self.path[min(self.ci, len(self.path) - 1)][0] - self.bx
            dz = self.path[min(self.ci, len(self.path) - 1)][1] - self.bz
            if abs(dx) + abs(dz) > 1e-6:
                vx, vz = dx, dz
            if vx or vz:
                follow_camera(p, rs, DT, vx, vz)
            if st == P_STRAIGHT and done:
                self.next_leg(t)
            elif st == P_PATH and self.switch_at is not None and not self.switched \
                    and self.travel >= self.switch_at * self.path_len:
                self.switched = True
                opts = [k for k in self.nearest_empty(self.bx, self.bz, 4) if k != self.cur_k][:3]
                self.set_target(rs.choice(opts))
        elif st == P_PAD:
            if self.onpad_face:
                p.yaw += (0.0 - p.yaw) * min(1.0, 3.0 * DT)
            else:
                look_around(p, rs, DT)
        # wobble around the route
        if st in (P_STRAIGHT, P_PATH) and (vx or vz):
            d = math.hypot(vx, vz)
            nx, nz = -vz / d, vx / d
            off = self.wob_a * math.sin(2 * math.pi * self.travel / self.wob_l + self.wob_p)
            p.x, p.z = self.bx + nx * off, self.bz + nz * off
        elif st != P_PAD:
            p.x, p.z = self.bx, self.bz
        # smoothed velocity (what the server can measure)
        ivx = (p.x - self.prev_px) / DT
        ivz = (p.z - self.prev_pz) / DT
        al = DT / 0.15
        self.vsx += (ivx - self.vsx) * al
        self.vsz += (ivz - self.vsz) * al
        self.prev_px, self.prev_pz = p.x, p.z
        p.speed = math.hypot(self.vsx, self.vsz)
        p.vx, p.vz = self.vsx, self.vsz
        # stepping onto any empty 1v1 pad joins it
        if st in (P_STRAIGHT, P_PATH):
            for k in self.empty:
                if in_rect(pad_rect(k), p.x, p.z, 0.5):
                    self.t_on = t
                    self.pad_on = k
                    self.pstate = P_PAD
                    p.tyaw = p.yaw
                    p.hold = rs.uniform(0.2, 1.0)
                    break

    # ------------------------------------------------------- camera reports & checks -----
    def reports(self, t):
        """Each client sends its camera a few times a second; each report lands after a
        network delay. The server keeps the newest two (the pair gives the turn speed)."""
        rs = self.rs
        iv = 1.0 / self.pol.report_hz
        agents = self.others + ([self.p] if self.p_spawned else [])
        for a in agents:
            while t >= a.next_send:
                a.pend.append((t + rs.uniform(*NET_LAT), a.next_send, a.cam(), a.yaw, a.pitch,
                               a.vx, a.vz, a.x, a.z))
                a.next_send += iv
            if a.pend:
                keep = []
                for r in a.pend:
                    if r[0] <= t:
                        if a.snap is None or r[1] > a.snap[1]:
                            if a is self.p and a.snap is not None:
                                dtt = max(1e-3, r[1] - a.snap[1])
                                if abs(wrap(r[3] - a.snap[3])) / dtt > LOOKER_TURN:
                                    self.p_last_turn = r[1]
                            a.psnap = a.snap
                            a.snap = r
                    else:
                        keep.append(r)
                a.pend = keep

    def view_of(self, a, base):
        """The server's cautious picture of one screen: the last reported view widened by
        `base` all round, plus (on the side it was turning toward) turn speed x staleness,
        and also tested from where a walking camera will have moved to."""
        s = a.snap
        st = self.pol.stale
        m_lo = m_hi = mv = base
        if a.psnap is None:
            m_lo += TURN_UNKNOWN * st
            m_hi += TURN_UNKNOWN * st
        else:
            dtt = max(1e-3, s[1] - a.psnap[1])
            wy = wrap(s[3] - a.psnap[3]) / dtt
            mv += abs(s[4] - a.psnap[4]) / dtt * st
            if wy > 0:
                m_hi += min(wy * st, MAX_SWING)
            else:
                m_lo += min(-wy * st, MAX_SWING)
        c = s[2]
        cam2 = None
        if abs(s[5]) + abs(s[6]) > 1e-3:
            cam2 = (c[0] + s[5] * st, c[1], c[2] + s[6] * st) + c[3:]
        return (c, m_lo, m_hi, mv, cam2)

    def new_views(self, t, extra=0.0):
        """The new player's screen, the one that must never see the bot appear."""
        base = self.pol.margin_deg * DEG + extra
        st = self.pol.stale
        if t < 0.0:  # still loading: guard the view they will spawn with (facing the tables)
            out = []
            for sx in (-7.0, 0.0, 7.0):
                c = build_cam(sx, FOCUS_Y, SPAWN_Z, 0.0, FOLLOW_PITCH * DEG, FOLLOW_DIST, PHONE_FOLLOW)
                out.append((c, base + 5.0 * DEG, base + 5.0 * DEG, base, None))
            return out
        if self.p.snap is None:  # spawned, first report not in yet
            c = build_cam(self.sx, FOCUS_Y, self.sz, 0.0, FOLLOW_PITCH * DEG, FOLLOW_DIST, PHONE_FOLLOW)
            m = base + TURN_UNKNOWN * st
            return [(c, m, m, base, None)]
        s = self.p.snap
        if s[1] - self.p_last_turn <= LOOKER_WINDOW:   # they have been dragging the camera
            base += LOOKER_MARGIN
        out = [self.view_of(self.p, base)]
        # walking (the server sees the character move, with no camera-report delay): the
        # camera will swing to point along the walk, sweeping everything in between
        vx, vz = self.vsx, self.vsz
        if math.hypot(vx, vz) >= MOVE_MIN:
            hy = heading_yaw(vx, vz)
            m = base + HEADING_MARGIN
            px, pz = self.p.x + vx * st, self.p.z + vz * st
            diff = wrap(hy - s[3])
            steps = int(abs(diff) / (60.0 * DEG)) + 1
            for i in range(1, steps + 1):
                yaw = wrap(s[3] + diff * i / steps)
                c = build_cam(px, FOCUS_Y, pz, yaw, FOLLOW_PITCH * DEG, FOLLOW_DIST, self.p.consts)
                out.append((c, m, m, base, None))
        return out

    def other_views(self, cautious=True):
        """Everyone else's screens: with turning margins (cautious) or as last reported."""
        base = self.pol.margin_deg * DEG
        out = []
        for a in self.others:
            if a.snap is None:
                continue
            if cautious:
                out.append(self.view_of(a, base))
            else:
                out.append((a.snap[2], base, base, base, None))
        return out

    def unseen(self, views, x, z):
        rng = self.pol.view_range
        for (c, m_lo, m_hi, mv, c2) in views:
            if server_seen(c, x, z, rng, m_lo, m_hi, mv):
                return False
            if c2 is not None and server_seen(c2, x, z, rng, m_lo, m_hi, mv):
                return False
        return True

    def near_character(self, x, z):
        r2 = NEAR_CHAR * NEAR_CHAR
        for a in self.others:
            if (a.x - x) ** 2 + (a.z - z) ** 2 < r2:
                return True
        px, pz = (self.p.x, self.p.z) if self.p_spawned else (SPAWN_X, SPAWN_Z)
        return (px - x) ** 2 + (pz - z) ** 2 < r2

    def check_pending(self, t):
        """A teleport shows on screens a network delay after the server does it: was the
        new spot (pop-in) or the old spot (pop-out) on anyone's real screen then?"""
        keep = []
        rng = self.pol.view_range
        for item in self.pending:
            t_show, old, new, kind = item
            if t_show > t + 1e-9:
                keep.append(item)
                continue
            pcam = self.p.cam() if self.p_spawned else None
            ocams = [a.cam() for a in self.others]
            if new is not None and pcam is not None and true_seen(pcam, new[0], new[1], rng):
                self.popin_new += 1
                self.seen_kinds_new.append(kind)
            if new is not None and any(true_seen(c, new[0], new[1], rng) for c in ocams):
                if kind == "spawnpad":
                    self.spawnpad_seen_other += 1   # looks like a player joining
                else:
                    self.popin_other += 1
                    self.seen_kinds_other.append(kind)
                    if any(true_seen(c, new[0], new[1], NEAR_SEEN) for c in ocams):
                        self.popin_other_near += 1
            if old is not None:
                if pcam is not None and true_seen(pcam, old[0], old[1], rng):
                    self.popout_new += 1
                if any(true_seen(c, old[0], old[1], rng) for c in ocams):
                    self.popout_other += 1
        self.pending = keep

    # --------------------------------------------------------------- the bot's brain -----
    def teleport(self, t, x, z, kind, level):
        old = None if self.b_state == B_HIDDEN else (self.b_x, self.b_z)
        self.events.append((t, kind, old, (x, z), level))
        doors = self.pol.home_mode == "doors"
        # in the doors variant the bot appears inside a closed hut, and a waiting bot is
        # inside one too, so only a walking bot leaving can be seen
        seen_old = None if (doors and self.b_state == B_STAGED) else old
        seen_new = None if doors else (x, z)
        self.pending.append((t + self.rb.uniform(*NET_LAT), seen_old, seen_new, kind))
        self.b_x, self.b_z = x, z
        self.last_tp = t
        self.n_tp += 1
        self.levels.append(level)

    def bot_time(self, k, x, z):
        return fval(self.w.F[k], x, z) * NAT_EST / self.pol.bot_speed

    def find_spot(self, t, k, t_lo, t_hi, t_ideal, newv, max_level=3, avoid=None):
        """A spot whose walk time to pad k is in [t_lo, t_hi], nearest t_ideal first, at
        least NEAR_CHAR from everyone and hidden from the new player (strict). Level 1: also
        hidden from every other screen (turning margins too); level 2: hidden from the other
        screens as last reported; level 3: hidden from the new player only."""
        if t < self.next_search:
            return None, 0
        if self.pol.home_mode == "doors":
            best = None
            for (dx, dz) in (self.pol.doors or DOORS):
                T = self.bot_time(k, dx, dz)
                if avoid is not None and (dx - avoid[0]) ** 2 + (dz - avoid[1]) ** 2 < 100.0:
                    continue
                if T >= MIN_WALK and (best is None or abs(T - t_ideal) < best[0]):
                    best = (abs(T - t_ideal), (dx, dz))
            return (best[1], 1) if best else (None, 0)
        f = NAT_EST / self.pol.bot_speed
        keys = self.w.by_dist_keys[k]
        rows = self.w.by_dist[k]
        i0 = bisect.bisect_left(keys, t_lo / f)
        i1 = bisect.bisect_right(keys, t_hi / f)
        lst = sorted((abs(rows[i][0] * f - t_ideal), rows[i][1]) for i in range(i0, i1))
        cands = self.w.cands
        othv = self.other_views(True)
        othb = self.other_views(False)
        chars = [(a.x, a.z) for a in self.others]
        chars.append((self.p.x, self.p.z) if self.p_spawned else (SPAWN_X, SPAWN_Z))
        r2 = NEAR_CHAR * NEAR_CHAR
        fb2 = fb3 = None
        tried = 0
        for _, ci in lst:
            x, z = cands[ci]
            if avoid is not None and (x - avoid[0]) ** 2 + (z - avoid[1]) ** 2 < 100.0:
                continue
            if not self.unseen(newv, x, z):
                continue
            near = False
            for (cx, cz) in chars:
                if (cx - x) * (cx - x) + (cz - z) * (cz - z) < r2:
                    near = True
                    break
            if near:
                continue
            tried += 1
            if self.unseen(othv, x, z):
                return (x, z), 1
            if fb2 is None and self.unseen(othb, x, z):
                fb2 = (x, z)
            if fb3 is None:
                fb3 = (x, z)
            if tried >= 60:
                break
        if fb2 is not None and max_level >= 2:
            return fb2, 2
        if fb3 is not None and max_level >= 3:
            return fb3, 3
        self.next_search = t + SEARCH_RETRY
        return None, 0

    def home_free(self, newv, x, z):
        if self.pol.home_mode == "doors":
            return True
        return not self.near_character(x, z) and self.unseen(newv, x, z) and \
            self.unseen(self.other_views(True), x, z)

    def predict(self, t):
        """Which pad is the player heading for?"""
        p = self.p
        if self.pad_on is not None:
            if self.k_pred != self.pad_on:
                self.pred_since = t - TP_STABLE    # standing on it: certain
            self.k_pred = self.pad_on
            self.committed = True
            return
        if not self.p_spawned:
            self.k_pred = self.arrow
            self.committed = False
            return
        spd = math.hypot(self.vsx, self.vsz)
        if spd >= MOVE_MIN:
            ux, uz = self.vsx / spd, self.vsz / spd
            best = None
            for k in self.empty:
                F = self.w.F[k]
                f1 = fval(F, p.x, p.z)
                if f1 >= BIG:
                    continue
                f0 = fval(F, p.x - ux * 2.0, p.z - uz * 2.0)
                r = (f0 - f1) / 2.0
                if r >= HEAD_COS and (best is None or f1 < best[0]):
                    best = (f1, k)
            if best is not None:
                if best[1] != self.k_pred or not self.committed:
                    self.pred_since = t
                self.k_pred = best[1]
                self.committed = True
                if self.first_commit_t is None:
                    self.first_commit_t = t
                return
        self.committed = False
        if self.first_commit_t is None:
            self.k_pred = self.arrow          # not heading anywhere yet: trust the arrow

    def desired(self, t, k):
        """Seconds from now until the bot should step on pad k."""
        if self.pad_on is not None:
            return self.t_on + self.pol.target_delay - t
        eta = fval(self.w.F[k], self.p.x, self.p.z) / PLAYER_SPEED
        if not self.committed:
            eta += 0.5
        return eta + self.pol.target_delay

    def home_spot(self, k):
        if self.pol.home_mode == "behind":
            return (0.0, 100.0)
        if self.pol.home_mode == "doors":   # the door the bot can walk from in about the time
            Wk = self.homes[k][4]           # a player needs from the spawn, plus 0.3 s
            return min(self.pol.doors or DOORS,
                       key=lambda d: (abs(self.bot_time(k, d[0], d[1]) - (Wk + 0.3)), d))
        h = self.homes[k]
        return (h[0], h[1])

    def server(self, t):
        pol = self.pol
        self.predict(t)
        k = self.k_pred
        st = self.b_state
        can_tp = t - self.last_tp >= MIN_TP_GAP
        sure = t - self.pred_since >= TP_STABLE - 1e-9
        if st == B_HIDDEN and pol.home_mode == "spawnpad":
            # hidden until it is time to go, then "join" on the spawn pad out of the new
            # player's view (other players see what looks like a player spawning)
            if not self.committed or not can_tp:
                return
            d = self.desired(t, k)
            newv = self.new_views(t)
            best = None
            due = False
            for (x, z) in SPAWN_SPOTS:
                T = self.bot_time(k, x, z)
                if T < d - 0.05:
                    continue                  # not time yet from this spot
                due = True
                if self.near_character(x, z) or not self.unseen(newv, x, z):
                    continue
                if best is None or abs(T - d) < best[0]:
                    best = (abs(T - d), x, z)
            if best is not None:
                self.teleport(t, best[1], best[2], "spawnpad", 1)
                self.b_state = B_STAGED
                self.start_walk(t, k)
                return
            if pol.restage and due and sure:  # time to go but the spawn pad is in view
                spot, lvl = self.find_spot(t, k, max(MIN_WALK, d - 0.35), max(d, MIN_WALK) + 0.35, max(d, MIN_WALK), newv, 3)
                if spot is not None:
                    self.teleport(t, spot[0], spot[1], "late", lvl)
                    self.b_state = B_STAGED
                    self.start_walk(t, k)
            return
        if st == B_HIDDEN:
            # in the hidden room: come out at the arrow table's home when nobody looks there
            if not can_tp:
                return
            hx, hz = self.home_spot(k)
            if not pol.place_check:
                self.teleport(t, hx, hz, "place", 0)
                self.b_state = B_STAGED
                self.b_k = k
                return
            newv = self.new_views(t)
            # before the first frame there is no hurry: wait for a spot nobody sees, then
            # settle for one only the others' turning margins cover, then any
            lvl_ok = 1 if t < -1.0 else (2 if t < -0.5 else 3)
            if self.pol.home_mode == "doors":
                lvl_ok = 3
            if self.committed:
                d = self.desired(t, k)
                spot, lvl = self.find_spot(t, k, max(MIN_WALK, d - 0.35), max(d, MIN_WALK) + 0.35, max(d, MIN_WALK), newv, 3)
            elif self.home_free(newv, hx, hz):
                spot, lvl = (hx, hz), 1
            else:
                T = self.bot_time(k, hx, hz)
                spot, lvl = self.find_spot(t, k, MIN_WALK, T + PLACE_SLACK, T, newv, lvl_ok)
            if spot is not None:
                self.teleport(t, spot[0], spot[1], "place", lvl)
                self.b_state = B_STAGED
                self.b_k = k
            else:
                self.n_restage_fail += 1
            return
        if st == B_STAGED:
            if self.committed:
                d = self.desired(t, k)
                T = self.bot_time(k, self.b_x, self.b_z)
                if pol.trigger == "eta":
                    go = T >= d - 0.05
                else:
                    go = self.pad_on is not None or \
                        fval(self.w.F[k], self.p.x, self.p.z) <= pol.trigger_dist
                if go:
                    if pol.restage and T > d + LATE_TOL and can_tp and sure and \
                            T - max(d, MIN_WALK) >= MIN_GAIN:
                        newv = self.new_views(t)
                        # (in the doors variant a waiting bot is inside a hut: always free)
                        if pol.home_mode == "doors" or self.unseen(newv, self.b_x, self.b_z):
                            spot, lvl = self.find_spot(t, k, max(MIN_WALK, d - 0.35), max(d, MIN_WALK) + 0.35, max(d, MIN_WALK), newv,
                                                       pol.late_level)
                            if spot is not None:
                                self.teleport(t, spot[0], spot[1], "late", lvl)
                            else:
                                self.n_restage_fail += 1
                    self.start_walk(t, k)
                return
            # the player is still looking around: just wait (the "dodge" variant moves away
            # when the new player's camera comes close, if both spots are off their screen)
            if not pol.dodge or pol.home_mode == "doors" or not can_tp or t < 0.0 \
                    or t - self.last_dodge < 0.6:
                return
            if self.unseen(self.new_views(t, DODGE_EXTRA), self.b_x, self.b_z):
                return
            newv = self.new_views(t)
            if not self.unseen(newv, self.b_x, self.b_z):
                return                          # may be on their screen: stay put
            T_now = self.bot_time(k, self.b_x, self.b_z)
            spot, lvl = self.find_spot(t, k, T_now - 0.6, T_now + 0.3, T_now,
                                       self.new_views(t, DODGE_EXTRA), 2, avoid=(self.b_x, self.b_z))
            if spot is not None:
                self.teleport(t, spot[0], spot[1], "dodge", lvl)
                self.last_dodge = t
            else:
                self.n_restage_fail += 1
            return
        if st in (B_WALK, B_HOLD):
            if k != self.b_k:
                self.start_walk(t, k)       # the player changed their mind: re-route
            d = self.desired(t, k)
            T = self.bot_time(k, self.b_x, self.b_z)
            if pol.restage and T > d + LATE_TOL and can_tp and sure and self.b_state == B_WALK \
                    and pol.home_mode != "doors" and T - max(d, MIN_WALK) >= MIN_GAIN:
                newv = self.new_views(t)
                if self.unseen(newv, self.b_x, self.b_z):
                    spot, lvl = self.find_spot(t, k, max(MIN_WALK, d - 0.35), max(d, MIN_WALK) + 0.35, max(d, MIN_WALK), newv,
                                               pol.late_level)
                    if spot is not None:
                        self.teleport(t, spot[0], spot[1], "late", lvl)
                        self.start_walk(t, k)
                    else:
                        self.n_restage_fail += 1
            self.b_paused = (pol.trigger == "eta" and self.pad_on is None and T < d - 0.4)

    def start_walk(self, t, k):
        self.b_k = k
        self.b_path = grid_path(self.w.F[k], self.b_x, self.b_z, pad_rect(k))
        self.b_ci = 1
        self.b_state = B_WALK
        self.b_hold_until = None
        if self.started_walk_t is None:
            self.started_walk_t = t

    def update_bot(self, t):
        st = self.b_state
        if st == B_STAGED and t >= 0.0:
            if self.pol.home_mode != "doors" and \
                    true_seen(self.p.cam(), self.b_x, self.b_z, self.pol.view_range):
                self.seen_idle_new = True
            return
        if st not in (B_WALK, B_HOLD):
            return
        k = self.b_k
        on_mine = self.pad_on == k
        if on_mine and self.b_hold_until is None:
            self.b_hold_until = self.t_on + MIN_WAIT + self.rb.uniform(0.0, 0.25)
        dist = fval(self.w.F[k], self.b_x, self.b_z)
        if st == B_HOLD:
            if not on_mine:
                self.hold_before += DT          # idling by a pad the player is not on yet
            if on_mine and t >= self.b_hold_until:
                self.b_state = B_WALK
            else:
                return
        if dist <= HOLD_DIST and not (on_mine and t >= self.b_hold_until):
            self.b_state = B_HOLD
            return
        if self.b_paused:
            return
        spd = self.pol.bot_speed / self.bot_nat * DT
        b = _Mover(self.b_x, self.b_z, self.b_path, self.b_ci)
        follow_path(b, spd)
        self.b_x, self.b_z, self.b_ci = b.bx, b.bz, b.ci
        if on_mine and in_rect(pad_rect(k), self.b_x, self.b_z, 0.5):
            self.b_state = B_DONE
            self.wait = t - self.t_on


    def strip(self):
        """Drop the heavy per-run state once a join is finished (keeps the numbers)."""
        for name in ("others", "p", "w", "path", "b_path", "pending", "homes", "rs", "rb"):
            setattr(self, name, None)


class _Mover:
    __slots__ = ("bx", "bz", "path", "ci")

    def __init__(self, x, z, path, ci):
        self.bx, self.bz, self.path, self.ci = x, z, path, ci


LOOKAHEAD2 = 3.0 * 3.0


def follow_path(m, step):
    """Move `step` studs toward a carrot a few studs ahead on the route. True at the end."""
    path = m.path
    ci = m.ci
    x, z = m.bx, m.bz
    last = len(path) - 1
    while ci < last:
        px, pz = path[ci]
        if (px - x) ** 2 + (pz - z) ** 2 < LOOKAHEAD2:
            ci += 1
        else:
            break
    tx, tz = path[ci]
    dx, dz = tx - x, tz - z
    d = math.hypot(dx, dz)
    done = False
    if d <= step:
        x, z = tx, tz
        done = ci == last
    else:
        x += dx / d * step
        z += dz / d * step
    m.bx, m.bz, m.ci = x, z, ci
    return done


# ============================================================================ batches =====
def pct(sorted_vals, q):
    if not sorted_vals:
        return float("nan")
    i = q * (len(sorted_vals) - 1)
    lo = int(math.floor(i))
    hi = min(lo + 1, len(sorted_vals) - 1)
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * (i - lo)


def run_batch(world, pol, runs, seed):
    """Run `runs` joins; join i uses the same world seed under every policy, so policies are
    compared on identical players, servers and cameras."""
    out = []
    for i in range(runs):
        r = Run(world, pol, seed * 1000003 + i).go()
        r.strip()
        out.append(r)
    return out


def summarise(rs_):
    waits = sorted(r.wait for r in rs_)
    n = len(waits)
    s = {
        "n": n,
        "median": pct(waits, 0.5),
        "p90": pct(waits, 0.9),
        "p95": pct(waits, 0.95),
        "p99": pct(waits, 0.99),
        "over2": sum(1 for w in waits if w > 2.0) / n,
        "under05": sum(1 for w in waits if w < 0.5) / n,
        "timeouts": sum(1 for w in waits if w >= TIMEOUT) / n,
        "popin_new_runs": sum(1 for r in rs_ if r.popin_new > 0) / n,
        "popin_other_runs": sum(1 for r in rs_ if r.popin_other > 0) / n,
        "popin_other_near_runs": sum(1 for r in rs_ if r.popin_other_near > 0) / n,
        "popin_new_events": sum(r.popin_new for r in rs_),
        "popin_other_events": sum(r.popin_other for r in rs_),
        "popout_new_runs": sum(1 for r in rs_ if r.popout_new > 0) / n,
        "popout_other_runs": sum(1 for r in rs_ if r.popout_other > 0) / n,
        "level3_share": sum(1 for r in rs_ for lv in r.levels if lv == 3) / max(1, sum(r.n_tp for r in rs_)),
        "appear_events": sum(r.n_tp for r in rs_),
        "tp_per_run": sum(r.n_tp for r in rs_) / n,
        "restage_runs": sum(1 for r in rs_ if r.n_tp > 1) / n,
        "seen_idle_new": sum(1 for r in rs_ if r.seen_idle_new) / n,
        "loiter": sum(1 for r in rs_ if r.hold_before >= 1.0) / n,
        "place_seen_new": sum(1 for r in rs_ if "place" in r.seen_kinds_new) / n,
        "place_seen_other": sum(1 for r in rs_ if "place" in r.seen_kinds_other) / n,
        "fail_search_runs": sum(1 for r in rs_ if r.n_restage_fail > 0) / n,
        "waits": waits,
    }
    return s


def by_group(rs_, keyf):
    groups = {}
    order = []
    for r in rs_:
        g = keyf(r)
        if g not in groups:
            groups[g] = []
            order.append(g)
        groups[g].append(r)
    return [(g, summarise(groups[g])) for g in sorted(order, key=str)]


# =============================================================================== SVG ======
SVG_FONT = 'font-family="system-ui, -apple-system, Segoe UI, sans-serif"'


def _wrap_words(text, width):
    lines, cur = [], ""
    for wd in text.split(" "):
        if cur and len(cur) + len(wd) + 1 > width:
            lines.append(cur)
            cur = wd
        else:
            cur = (cur + " " + wd).strip()
    lines.append(cur)
    return lines


def svg_map(world, pol, traces, kiosk, path):
    """Top-down map: tables, pads, spawn, the new player's first view, Plan A's waiting spots,
    Plan B's kiosk and a few sample joins (player route, bot route, teleports)."""
    homes = world.homes_for(pol.bot_speed)
    S = 3.3
    PADL, PADT = 20.0, 70.0
    LEG_W = 270.0
    MW = (X_MAX - X_MIN) * S
    MH = (Z_MAX - Z_MIN) * S
    W = MW + PADL * 2 + LEG_W
    H = MH + PADT + 24.0

    def X(x):
        return PADL + (x - X_MIN) * S

    def Y(z):  # -Z (the far tables) at the top, the spawn near the bottom
        return PADT + (z - Z_MIN) * S

    o = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.0f %.0f" width="%.0f" height="%.0f" %s>'
         % (W, H, W, H, SVG_FONT)]
    o.append("""<style>
  .bg{fill:#f9f9f7} .roof{fill:#fcfcfb;stroke:#c3c2b7;stroke-width:1}
  .t1{fill:#d6d4cb} .t2{fill:#b9b7ad} .t3{fill:#9d9b92}
  .pad{fill:#e7f0fb;stroke:#86b6ef;stroke-width:1}
  .prop{fill:#c3c2b7} .spawn{fill:#d3efe2;stroke:#1baf7a;stroke-width:1.5}
  .ink{fill:#0b0b0b} .ink2{fill:#52514e} .mute{fill:#898781}
  .view{fill:#2a78d6;fill-opacity:0.07;stroke:#2a78d6;stroke-opacity:0.35;stroke-width:1}
  .ppath{fill:none;stroke:#2a78d6;stroke-width:2;stroke-linejoin:round;stroke-linecap:round}
  .bpath{fill:none;stroke:#eb6834;stroke-width:2;stroke-linejoin:round;stroke-linecap:round}
  .kpath{fill:none;stroke:#4a3aa7;stroke-width:2;stroke-linejoin:round;stroke-linecap:round}
  .tp{fill:none;stroke:#eb6834;stroke-width:1.5;stroke-dasharray:3 3}
  .home{fill:#eb6834;stroke:#fcfcfb;stroke-width:2} .lbl{fill:#0b0b0b;font-size:10px;font-weight:600}
  .kiosk{fill:#4a3aa7;stroke:#fcfcfb;stroke-width:2}
  .pdot{fill:#2a78d6;stroke:#fcfcfb;stroke-width:2} .bdot{fill:#eb6834;stroke:#fcfcfb;stroke-width:2}
  .kdot{fill:#4a3aa7;stroke:#fcfcfb;stroke-width:2}
  @media (prefers-color-scheme: dark){
    .bg{fill:#0d0d0d} .roof{fill:#1a1a19;stroke:#383835} .t1{fill:#4a4a46} .t2{fill:#5c5c57} .t3{fill:#6e6e68}
    .pad{fill:#1c2a3b;stroke:#3987e5} .prop{fill:#383835} .spawn{fill:#16352a;stroke:#199e70}
    .ink{fill:#ffffff} .ink2{fill:#c3c2b7} .lbl{fill:#ffffff}
    .view{fill:#3987e5;stroke:#3987e5} .ppath{stroke:#3987e5} .pdot{fill:#3987e5;stroke:#1a1a19}
    .bpath{stroke:#d95926} .tp{stroke:#d95926} .home{fill:#d95926;stroke:#1a1a19} .bdot{fill:#d95926;stroke:#1a1a19}
    .kpath{stroke:#9085e9} .kiosk{fill:#9085e9;stroke:#1a1a19} .kdot{fill:#9085e9;stroke:#1a1a19}
  }
</style>""")
    o.append('<rect class="bg" x="0" y="0" width="%.0f" height="%.0f"/>' % (W, H))
    o.append('<text class="ink" x="%.0f" y="26" font-size="17" font-weight="600">Rooftop from above: where '
             'the tutorial bot waits and how it walks in</text>' % PADL)
    o.append('<text class="ink2" x="%.0f" y="46" font-size="12">The far (-Z) end is at the top; players spawn '
             'at the bottom and walk up. Bot at %.1f studs/s. Hover a mark for details.</text>'
             % (PADL, pol.bot_speed))
    o.append('<rect class="roof" x="%.1f" y="%.1f" width="%.1f" height="%.1f"/>' % (X(X_MIN), Y(Z_MIN), MW, MH))
    # the new player's first view (phone, facing the tables), from the spawn centre
    cx, cz = SPAWN_X, SPAWN_Z + FOLLOW_DIST * math.cos(FOLLOW_PITCH * DEG)
    hh = PHONE_FOLLOW[2]
    pts = [(cx, cz)]
    for i in range(0, 25):
        ang = -hh + 2 * hh * i / 24.0
        pts.append((cx + math.sin(ang) * 120.0, cz - math.cos(ang) * 120.0))
    poly = " ".join("%.1f,%.1f" % (X(max(X_MIN, min(X_MAX, x))), Y(max(Z_MIN, min(Z_MAX, z)))) for x, z in pts)
    o.append('<polygon class="view" points="%s"><title>What a new player on a phone sees on their first '
             'frame (facing the tables, out to 120 studs)</title></polygon>' % poly)
    for t in TABLES:
        k = t[0]
        pr = pad_rect(k)
        o.append('<rect class="pad" x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="2"><title>Queue pad of '
                 'table %d</title></rect>' % (X(pr[0]), Y(pr[2]), (pr[1] - pr[0]) * S, (pr[3] - pr[2]) * S, k))
        tr = table_rect(k)
        o.append('<rect class="t%d" x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="3"><title>Table %d (%dv%d)'
                 '</title></rect>' % (t[3], X(tr[0]), Y(tr[2]), (tr[1] - tr[0]) * S, (tr[3] - tr[2]) * S,
                                      k, t[3], t[3]))
        o.append('<text class="ink" x="%.1f" y="%.1f" font-size="11" font-weight="600" text-anchor="middle">%d'
                 '</text>' % (X(t[1]), Y(t[2]) + 4, k))
        if t[3] > 1:
            o.append('<text class="ink2" x="%.1f" y="%.1f" font-size="9" text-anchor="middle">%dv%d</text>'
                     % (X(t[1]), Y(t[2]) + 14, t[3], t[3]))
    for (px, pz, hx, hz) in PROPS:
        o.append('<rect class="prop" x="%.1f" y="%.1f" width="%.1f" height="%.1f"/>'
                 % (X(px - hx), Y(pz - hz), 2 * hx * S, 2 * hz * S))
    o.append('<rect class="spawn" x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="2"/>'
             % (X(SPAWN_RECT[0]), Y(SPAWN_RECT[2]), 2 * SPAWN_HX * S, 2 * SPAWN_HZ * S))
    o.append('<text class="ink" x="%.1f" y="%.1f" font-size="10" text-anchor="middle">spawn</text>'
             % (X(SPAWN_X), Y(SPAWN_Z) + 4))
    # sample joins
    for tr in traces:
        pp = tr["p"]
        if len(pp) > 1:
            o.append('<polyline class="ppath" points="%s"><title>%s</title></polyline>'
                     % (" ".join("%.1f,%.1f" % (X(x), Y(z)) for _, x, z in pp), tr["label"]))
            o.append('<circle class="pdot" cx="%.1f" cy="%.1f" r="4"/>' % (X(pp[-1][1]), Y(pp[-1][2])))
        cls, dot = ("kpath", "kdot") if tr["kiosk"] else ("bpath", "bdot")
        tp_times = [e[0] for e in tr["events"] if e[2] is not None]
        segs, cur, prev_t = [], [], None
        for (t, x, z, _) in tr["b"]:
            if prev_t is not None and any(prev_t < tt <= t for tt in tp_times):
                segs.append(cur)
                cur = []
            cur.append((x, z))
            prev_t = t
        segs.append(cur)
        for sg in segs:
            if len(sg) > 1:
                o.append('<polyline class="%s" points="%s"><title>Bot: %s</title></polyline>'
                         % (cls, " ".join("%.1f,%.1f" % (X(x), Y(z)) for x, z in sg), tr["label"]))
        if not tr["kiosk"]:
            for e in tr["events"]:
                if e[2] is None:
                    continue
                (ox, oz), (nx, nz) = e[2], e[3]
                o.append('<line class="tp" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"><title>Teleport while '
                         'the new player could not see either end (%s)</title></line>'
                         % (X(ox), Y(oz), X(nx), Y(nz), e[1]))
        if tr["b"]:
            o.append('<circle class="%s" cx="%.1f" cy="%.1f" r="4"/>' % (dot, X(tr["b"][-1][1]), Y(tr["b"][-1][2])))
    # Plan A homes
    spots = {}
    for k in ONE_V_ONE:
        spots.setdefault((homes[k][0], homes[k][1]), []).append(k)
    for (hx, hz), ks in spots.items():
        o.append('<circle class="home" cx="%.1f" cy="%.1f" r="6"><title>Plan A waiting spot (%.0f, %.0f) when '
                 'the arrow points at table %s</title></circle>' % (X(hx), Y(hz), hx, hz, ", ".join(map(str, ks))))
    # one label per cluster of nearby spots (the front-table homes sit side by side)
    clusters = []
    for (hx, hz), ks in spots.items():
        for c in clusters:
            if abs(c["x"] - hx) < 12 and abs(c["z"] - hz) < 12:
                c["ks"] += ks
                c["x"] = max(c["x"], hx)
                break
        else:
            clusters.append({"x": hx, "z": hz, "ks": list(ks)})
    for c in clusters:
        right = c["x"] < 70
        o.append('<text class="lbl" x="%.1f" y="%.1f" text-anchor="%s">%s</text>'
                 % (X(c["x"]) + (9 if right else -9), Y(c["z"]) + 4, "start" if right else "end",
                    ", ".join("H%d" % k for k in sorted(c["ks"]))))
    for (kx, kz) in kiosk:
        o.append('<rect class="kiosk" x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="2"><title>Plan B: closed '
                 'kiosk (about 4 x 4 x 8 studs) at (%.0f, %.0f); the bot waits inside</title></rect>'
                 % (X(kx - 2), Y(kz - 2), 4 * S, 4 * S, kx, kz))
        o.append('<text class="lbl" x="%.1f" y="%.1f" text-anchor="start">kiosk</text>' % (X(kx) + 10, Y(kz) + 4))
    # legend
    lx = X(X_MAX) + 20
    ly = PADT + 8
    items = [
        ("home", "Plan A waiting spot Hk: used when the arrow points at table k"),
        ("kiosk", "Plan B: one closed kiosk; the bot waits inside and walks out"),
        ("ppath", "New player's route (sample joins)"),
        ("bpath", "Plan A bot route"),
        ("tp", "Plan A bot teleport, never on the new player's screen"),
        ("kpath", "Plan B bot route (from the kiosk)"),
        ("view", "New player's first view (phone), 120 studs"),
        ("pad", "Queue pad (step on to join)"),
        ("t1", "Table block (1v1; darker: 2v2, 3v3)"),
    ]
    for cls, label in items:
        if cls in ("ppath", "bpath", "tp", "kpath"):
            o.append('<line class="%s" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>' % (cls, lx, ly, lx + 22, ly))
        elif cls == "home":
            o.append('<circle class="home" cx="%.1f" cy="%.1f" r="6"/>' % (lx + 11, ly))
        elif cls == "kiosk":
            o.append('<rect class="kiosk" x="%.1f" y="%.1f" width="13" height="13" rx="2"/>' % (lx + 4.5, ly - 6.5))
        else:
            o.append('<rect class="%s" x="%.1f" y="%.1f" width="22" height="12" rx="2"/>' % (cls, lx, ly - 6))
        lines = _wrap_words(label, 32)
        for j, ln in enumerate(lines):
            o.append('<text class="ink2" x="%.1f" y="%.1f" font-size="11">%s</text>' % (lx + 30, ly + 4 + j * 14, ln))
        ly += 12 + 14 * len(lines)
    ly += 10
    o.append('<text class="ink" x="%.1f" y="%.1f" font-size="12" font-weight="600">Plan A waiting spots (X, Z)'
             '</text>' % (lx, ly))
    ly += 16
    for (hx, hz), ks in spots.items():
        o.append('<text class="ink2" x="%.1f" y="%.1f" font-size="11">H%s: (%.0f, %.0f)</text>'
                 % (lx, ly, "/".join(map(str, ks)), hx, hz))
        ly += 14
    ly += 10
    o.append('<text class="ink" x="%.1f" y="%.1f" font-size="12" font-weight="600">Sample joins</text>' % (lx, ly))
    ly += 16
    for tr in traces:
        for j, ln in enumerate(_wrap_words(tr["label"], 40)):
            o.append('<text class="ink2" x="%.1f" y="%.1f" font-size="10">%s</text>' % (lx, ly, ln))
            ly += 12
        ly += 3
    o.append("</svg>")
    with open(path, "w") as fh:
        fh.write("\n".join(o))


def svg_hist(panels, path):
    """Wait histograms, one panel per plan: bars = bot at 20.8 studs/s, outline = 16."""
    BIN = 0.1
    MAXW = 4.0
    nb = int(MAXW / BIN)

    def shares(waits):
        c = [0] * (nb + 1)
        for w in waits:
            c[min(int(w / BIN) if w < MAXW else nb, nb)] += 1
        n = float(len(waits))
        return [v / n * 100.0 for v in c], c

    W = 780.0
    PH = 210.0
    L, R = 56.0, 24.0
    top0 = 136.0
    gap = 82.0
    H = top0 + len(panels) * (PH + gap) - 10
    pw = W - L - R
    slot = pw / (nb + 2)
    top = 0.0
    for p in panels:
        top = max(top, max(shares(p["main"])[0]), max(shares(p["alt"])[0][:nb]) if p["alt"] else 0.0)
    step = 10.0 if top > 30 else 5.0
    top = math.ceil(top * 1.05 / step) * step
    o = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.0f %.0f" width="%.0f" height="%.0f" %s>'
         % (W, H, W, H, SVG_FONT)]
    o.append("""<style>
  .bg{fill:#fcfcfb} .ink{fill:#0b0b0b} .ink2{fill:#52514e} .mute{fill:#898781}
  .grid{stroke:#e1e0d9;stroke-width:1} .axis{stroke:#c3c2b7;stroke-width:1}
  .bar{fill:#2a78d6} .bar:hover{fill:#1c5cab} .over{fill:#e34948}
  .band{fill:#1baf7a;fill-opacity:0.08} .ref{stroke:#52514e;stroke-width:1}
  .alt{fill:none;stroke:#eb6834;stroke-width:2;stroke-linejoin:round}
  @media (prefers-color-scheme: dark){
    .bg{fill:#1a1a19} .ink{fill:#ffffff} .ink2{fill:#c3c2b7} .grid{stroke:#2c2c2a} .axis{stroke:#383835}
    .bar{fill:#3987e5} .bar:hover{fill:#86b6ef} .over{fill:#e66767} .band{fill:#199e70;fill-opacity:0.14}
    .ref{stroke:#c3c2b7} .alt{stroke:#d95926}
  }
</style>""")
    o.append('<rect class="bg" x="0" y="0" width="%.0f" height="%.0f"/>' % (W, H))
    o.append('<text class="ink" x="%.0f" y="28" font-size="17" font-weight="600">Wait from "player steps on" to '
             '"bot steps on"</text>' % L)
    o.append('<text class="ink2" x="%.0f" y="48" font-size="12">Share of simulated joins per 0.1 s. Green band: '
             'the 0.5-2 s target. Last bar (red): over 4 s. Hover a bar for its count.</text>' % L)
    # legend (two series)
    o.append('<rect class="bar" x="%.0f" y="60" width="14" height="10" rx="2"/>' % L)
    o.append('<text class="ink2" x="%.0f" y="69" font-size="12">bot walks at 20.8 studs/s (recommended)</text>'
             % (L + 20))
    o.append('<line class="alt" x1="%.0f" y1="65" x2="%.0f" y2="65"/>' % (L + 290, L + 310))
    o.append('<text class="ink2" x="%.0f" y="69" font-size="12">bot walks at 16 studs/s (Roblox default)</text>'
             % (L + 316))
    for pi, p in enumerate(panels):
        T = top0 + pi * (PH + gap)

        def xof(v):
            return L + v / BIN * slot

        def yof(sv):
            return T + PH - sv / top * PH

        st = p["stats"]
        o.append('<text class="ink" x="%.0f" y="%.0f" font-size="13" font-weight="600">%s</text>' % (L, T - 30, p["title"]))
        o.append('<text class="ink2" x="%.0f" y="%.0f" font-size="11">%d joins: median %.2f s, 95th percentile '
                 '%.2f s, %.1f%% over 2 s. At 16 studs/s: 95th %.2f s, %.1f%% over 2 s.</text>'
                 % (L, T - 14, st["n"], st["median"], st["p95"], st["over2"] * 100,
                    p["alt_stats"]["p95"], p["alt_stats"]["over2"] * 100))
        o.append('<rect class="band" x="%.1f" y="%.1f" width="%.1f" height="%.1f"/>'
                 % (xof(0.5), T, xof(2.0) - xof(0.5), PH))
        v = 0.0
        while v <= top + 1e-9:
            o.append('<line class="grid" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>' % (L, yof(v), L + pw, yof(v)))
            o.append('<text class="mute" x="%.1f" y="%.1f" font-size="11" text-anchor="end">%d%%</text>'
                     % (L - 8, yof(v) + 4, int(v)))
            v += step
        sh, cnt = shares(p["main"])
        for i in range(nb + 1):
            if sh[i] <= 0:
                continue
            x0 = L + i * slot + (slot + 1.0 if i == nb else 1.0)
            bw = slot - 2.0
            y0 = yof(min(sh[i], top))
            hgt = T + PH - y0
            r = min(3.0, bw / 2, hgt)
            d = ("M%.2f,%.2f L%.2f,%.2f Q%.2f,%.2f %.2f,%.2f L%.2f,%.2f Q%.2f,%.2f %.2f,%.2f L%.2f,%.2f Z"
                 % (x0, T + PH, x0, y0 + r, x0, y0, x0 + r, y0, x0 + bw - r, y0, x0 + bw, y0, x0 + bw,
                    y0 + r, x0 + bw, T + PH))
            lab = ("%.1f-%.1f s" % (i * BIN, (i + 1) * BIN)) if i < nb else ("over %.0f s" % MAXW)
            o.append('<path class="%s" d="%s"><title>%s: %.1f%% of joins (%d)</title></path>'
                     % ("over" if i == nb else "bar", d, lab, sh[i], cnt[i]))
        if p["alt"]:
            ash, _ = shares(p["alt"])
            ptsx = []
            for i in range(nb):
                ptsx.append((L + i * slot, yof(min(ash[i], top))))
                ptsx.append((L + (i + 1) * slot, yof(min(ash[i], top))))
            o.append('<polyline class="alt" points="%s"><title>Same joins, bot at 16 studs/s</title></polyline>'
                     % " ".join("%.1f,%.1f" % q for q in ptsx))
        o.append('<line class="axis" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>' % (L, T + PH, L + pw, T + PH))
        for v in range(0, int(MAXW) + 1):
            o.append('<text class="mute" x="%.1f" y="%.1f" font-size="11" text-anchor="middle">%d s</text>'
                     % (xof(v), T + PH + 16, v))
        o.append('<text class="mute" x="%.1f" y="%.1f" font-size="11" text-anchor="middle">&gt;%d</text>'
                 % (L + nb * slot + slot * 1.5, T + PH + 16, int(MAXW)))
        for name, v, dy in (("median", st["median"], 0), ("95th", st["p95"], 12)):
            if v < MAXW:
                o.append('<line class="ref" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f"/>' % (xof(v), T - 2 + dy, xof(v), T + PH))
                o.append('<text class="ink2" x="%.1f" y="%.1f" font-size="10" text-anchor="start">%s %.2f s</text>'
                         % (xof(v) + 4, T + 8 + dy, name, v))
    o.append("</svg>")
    with open(path, "w") as fh:
        fh.write("\n".join(o))


# =========================================================================== report =======
def f2(v):
    return "%.2f" % v


def pc(v):
    if 0.0 < v < 0.001:
        return "%.2f%%" % (v * 100.0)
    return "%.1f%%" % (v * 100.0)


KIOSK = [(0.0, 36.0)]   # Plan B: one closed kiosk at the central crossing in front of tables 2/3
STAIRS = [(-28.0, 86.0), (28.0, 86.0)]

# (plan, name, policy settings): every variant changes one thing from its plan
VARIANTS = [
    ("A", "bot walks at 16 studs/s (Roblox default)", dict(bot_speed=16.0)),
    ("A", "start the moment the player heads to a pad (no time matching)", dict(trigger="dist", trigger_dist=1e9)),
    ("A", "distance trigger: start when the player is 30 studs from the pad", dict(trigger="dist", trigger_dist=30.0)),
    ("A", "distance trigger: start at 15 studs", dict(trigger="dist", trigger_dist=15.0)),
    ("A", "aim for 0.75 s after the player (not 1.0 s)", dict(target_delay=0.75)),
    ("A", "no re-staging when late (one placement only)", dict(restage=False)),
    ("A", "late teleports must also be hidden from other players", dict(late_level=2)),
    ("A", "dodge: move away when the new player's camera turns toward it", dict(dodge=True)),
    ("A", "no safety margin around views (0 deg)", dict(margin_deg=0.0)),
    ("A", "safety margin 30 deg", dict(margin_deg=30.0)),
    ("A", "camera reports 2 a second (not 4)", dict(report_hz=2.0)),
    ("A", "camera reports 10 a second", dict(report_hz=10.0)),
    ("A", "bot ready only 1 s before the player's first frame (not 3)", dict(pre_spawn=1.0)),
    ("A", "bot ready 0.5 s AFTER the first frame", dict(pre_spawn=-0.5)),
    ("A", "bot ready 0.5 s after the first frame, put on its spot with no camera check",
     dict(pre_spawn=-0.5, place_check=False)),
    ("A", "bot put on its spot before the first frame with no camera check", dict(place_check=False)),
    ("A", "one waiting spot behind the spawn (0, 100) for every table", dict(home_mode="behind")),
    ("A", "count pop-ins at any distance (no 120-stud limit)", dict(view_range=1000.0)),
    ("A", "appear on the spawn pad like a joining player", dict(home_mode="spawnpad")),
    ("B", "kiosk, bot at 16 studs/s", dict(home_mode="doors", doors=KIOSK, bot_speed=16.0)),
    ("B", "kiosk, start the moment the player heads to a pad (no time matching)",
     dict(home_mode="doors", doors=KIOSK, trigger="dist", trigger_dist=1e9)),
    ("B", "kiosk, distance trigger: start when the player is 30 studs from the pad",
     dict(home_mode="doors", doors=KIOSK, trigger="dist", trigger_dist=30.0)),
    ("B", "two stairwell huts beside the spawn instead of the kiosk", dict(home_mode="doors", doors=STAIRS)),
    ("B", "kiosk plus the two stairwell huts", dict(home_mode="doors", doors=KIOSK + STAIRS)),
]


def plan_policy(plan, name="", **kw):
    if plan == "B":
        base = dict(home_mode="doors", doors=KIOSK)
        base.update(kw)
        return Policy(name or "Plan B", **base)
    return Policy(name or "Plan A", **kw)


def pick_traces(world, polA, polB, seed):
    """A handful of varied joins for the map."""
    out = []
    wanted = [("arrow", False), ("other table", True), ("arrow", True), ("wander first", None)]
    i = 0
    got = set()
    while len(out) < 4 and i < 600:
        r = Run(world, polA, seed * 1000003 + 700000 + i, trace=True).go()
        i += 1
        key = (r.behaviour, r.n_tp > 1)
        for wb, wtp in wanted:
            if (wb, wtp) in got or r.pad_on is None or r.behaviour != wb:
                continue
            if wtp is not None and (r.n_tp > 1) != wtp:
                continue
            if wb == "arrow" and wtp is False and r.pad_on not in (2, 3):
                continue
            got.add((wb, wtp))
            lab = "Plan A: %s to table %d%s, bot %s, waited %.1f s" % (
                "followed the arrow" if wb == "arrow" else ("picked another table" if wb == "other table"
                                                            else "wandered first, then went"),
                r.pad_on, " (switched mid-way)" if r.switched else "",
                "teleported once" if r.n_tp > 1 else "walked from its waiting spot", r.wait)
            out.append({"p": r.trace_p, "b": r.trace_b, "events": r.events, "label": lab, "kiosk": False})
            break
        del key
    for j in range(200):
        r = Run(world, polB, seed * 1000003 + 800000 + j, trace=True).go()
        if r.pad_on in (6, 7) or (j > 150 and r.pad_on is not None):
            out.append({"p": r.trace_p, "b": r.trace_b, "events": r.events, "kiosk": True,
                        "label": "Plan B: player went to table %d, bot came out of the kiosk, waited %.1f s"
                        % (r.pad_on, r.wait)})
            break
    return out


def main():
    ap = argparse.ArgumentParser(description="Tutorial v2: simulate the disguised bot walking in.")
    ap.add_argument("--runs", type=int, default=3000, help="joins for each of the two plans")
    ap.add_argument("--variant-runs", type=int, default=400, help="joins for each variant")
    ap.add_argument("--seed", type=int, default=1, help="world seed (same seed, same numbers)")
    ap.add_argument("--out", default=os.path.expanduser("~/Desktop/8ball-refs/tutorial/sim-2026-10-09/bot-arrival"),
                    help="folder for results.md, map.svg and waits.svg")
    ap.add_argument("--quick", action="store_true", help="a small smoke test (300 / 60 joins)")
    ap.add_argument("--no-variants", action="store_true", help="skip the variant table")
    args = ap.parse_args()
    if args.quick:
        args.runs, args.variant_runs = 300, 60
    t0 = time.time()
    world = World()
    polA = plan_policy("A")
    polB = plan_policy("B")
    runsA = run_batch(world, polA, args.runs, args.seed)
    SA = summarise(runsA)
    runsB = run_batch(world, polB, args.runs, args.seed)
    SB = summarise(runsB)
    for name, S in (("Plan A (open roof)", SA), ("Plan B (kiosk)", SB)):
        print("%-19s n=%d  wait median %.2f  p90 %.2f  p95 %.2f  p99 %.2f  over 2 s %s  | new player saw "
              "pop-in %s  other players %s" % (name, S["n"], S["median"], S["p90"], S["p95"], S["p99"],
                                              pc(S["over2"]), pc(S["popin_new_runs"]), pc(S["popin_other_runs"])))
    var = []
    if not args.no_variants:
        for plan, name, kw in VARIANTS:
            pol = plan_policy(plan, name, **kw)
            vs = summarise(run_batch(world, pol, args.variant_runs, args.seed))
            var.append((plan, name, pol, vs))
            print("  %s %-70s p95 %5.2f over2 %6s new-pop %5s other-pop %6s [%3.0fs]" % (
                plan, name[:70], vs["p95"], pc(vs["over2"]), pc(vs["popin_new_runs"]),
                pc(vs["popin_other_runs"]), time.time() - t0))
    baseA = summarise(runsA[:args.variant_runs])
    baseB = summarise(runsB[:args.variant_runs])
    os.makedirs(args.out, exist_ok=True)
    traces = pick_traces(world, polA, polB, args.seed)
    svg_map(world, polA, traces, KIOSK, os.path.join(args.out, "map.svg"))
    alt = {plan: v[3] for (plan, name, pol, v) in [(x[0], x[1], x[2], x) for x in var]
           if pol.bot_speed == 16.0 and (plan == "A" or pol.doors == KIOSK)}
    altA = alt.get("A") or summarise(run_batch(world, plan_policy("A", bot_speed=16.0), args.variant_runs, args.seed))
    altB = alt.get("B") or summarise(run_batch(world, plan_policy("B", bot_speed=16.0), args.variant_runs, args.seed))
    svg_hist([
        {"title": "Plan A: open roof, camera-aware waiting spots", "main": SA["waits"], "stats": SA,
         "alt": altA["waits"], "alt_stats": altA},
        {"title": "Plan B: one closed kiosk at (0, 36)", "main": SB["waits"], "stats": SB,
         "alt": altB["waits"], "alt_stats": altB},
    ], os.path.join(args.out, "waits.svg"))
    write_report(args, world, polA, runsA, SA, runsB, SB, baseA, baseB, var, altA, altB,
                 os.path.join(args.out, "results.md"), time.time() - t0)
    print("wrote %s in %.0f s" % (args.out, time.time() - t0))


def write_report(args, world, polA, runsA, SA, runsB, SB, baseA, baseB, var, altA, altB, path, secs):
    homes = world.homes_for(polA.bot_speed)
    L = []
    a = L.append
    a("# Tutorial bot arrival: simulation results (2026-10-09)")
    a("")
    a("Made by `tools/tutorial_v2_bot_arrival.py` in %.0f s: %d simulated joins for each plan, %d for each "
      "variant, seed %d. Same seed, same numbers. Rerun: `python3 tools/tutorial_v2_bot_arrival.py "
      "--runs %d --seed %d`." % (secs, SA["n"], args.variant_runs, args.seed, args.runs, args.seed))
    a("")
    a("Pictures: `map.svg` (the roof from above: waiting spots, the kiosk, sample joins) and `waits.svg` "
      "(how long players wait, both plans).")
    a("")
    a("**What a join looks like in the model.** A new player spawns, looks around, walks to a table and "
      "steps on its queue pad. A bot dressed as a player must step on the same pad 0.5-2 s later, walking "
      "in like a real player. It may teleport, but never where the new player's camera could see it appear "
      "or vanish. Targets: at least 95% of players wait under 2 s; the bot is never seen popping in.")
    a("")
    a("## The answer in one minute")
    a("")
    a("Two ways to do it were modelled. Both meet both targets for the new player.")
    a("")
    a("| | Plan A: open roof (no map change) | Plan B: one closed kiosk at (0, 36) |")
    a("|---|---|---|")
    a("| Median wait | %s s | %s s |" % (f2(SA["median"]), f2(SB["median"])))
    a("| 90th / 95th / 99th percentile | %s / %s / %s s | %s / %s / %s s |" % (
        f2(SA["p90"]), f2(SA["p95"]), f2(SA["p99"]), f2(SB["p90"]), f2(SB["p95"]), f2(SB["p99"])))
    a("| Waits over 2 s (target: at most 5%%) | %s | %s |" % (pc(SA["over2"]), pc(SB["over2"])))
    a("| New player saw the bot appear | %s (%d of %d joins) | %s (impossible: it appears inside) |" % (
        pc(SA["popin_new_runs"]), int(round(SA["popin_new_runs"] * SA["n"])), SA["n"], pc(SB["popin_new_runs"])))
    a("| New player saw the bot vanish (a teleport away) | %s | %s |" % (pc(SA["popout_new_runs"]),
                                                                       pc(SB["popout_new_runs"])))
    a("| Some *other* player could have seen it appear | %s of joins (%s within 50 studs) | %s |" % (
        pc(SA["popin_other_runs"]), pc(SA["popin_other_near_runs"]), pc(SB["popin_other_runs"])))
    a("| New player saw it *standing* while it waited | %s | 0%% (inside) |" % pc(SA["seen_idle_new"]))
    a("| Camera reports from clients needed | yes, 4 a second | no |")
    a("")
    a("**Recommendation.** If a small closed building on the roof is acceptable, use **Plan B**: build "
      "one closed kiosk (a snack bar, stairwell or lift, about 4 x 4 x 8 studs, door shut or curtained) at "
      "the central crossing (0, 36) in front of tables 2 and 3. The bot is created inside it when the player "
      "joins, waits there, and walks out on the trigger below. Nobody can ever see it appear, no camera "
      "code is needed, and the waits are the best of everything tried. If the roof must stay as it is, use "
      "**Plan A** below: it also meets the targets for the new player, but in busy servers another player "
      "can sometimes see the bot appear at the edge of their screen (there is no spot on an open roof "
      "that 25 cameras all miss).")
    a("")
    a("**Bot speed: 20.8 studs/s**, the same as players (Config.Hub.WalkSpeed), with 15-25%% natural "
      "stop-and-go. At Roblox's default 16 the bot is visibly slower than every other avatar and later: "
      "Plan A goes to %s over 2 s (95th %s s), Plan B to %s (95th %s s)." % (
          pc(altA["over2"]), f2(altA["p95"]), pc(altB["over2"]), f2(altB["p95"])))
    a("")
    a("**Trigger (both plans): start walking when the bot's walk time is at least the player's time to "
      "arrive plus 1.0 s.** Walk time = the bot's walking distance to the pad x 1.2 / 20.8. Time to arrive "
      "= the player's walking distance to the pad / 20.8. Details in section 2.")
    a("")
    # ---------------------------------------------------------------- Plan A
    a("## Plan A: open roof")
    a("")
    a("### 1. Where the bot waits, and when it re-stages")
    a("")
    a("The bot's avatar is built in a **hidden room** off the roof (a closed box under the floor, for "
      "example) as soon as the player joins, so nobody watches it load. The server picks the arrow's table "
      "at the same moment (the nearest empty 1v1 table to the spawn centre), so it knows where the bot "
      "should wait before the player's first frame. The bot is then teleported to that table's **home**, "
      "only when the home is off every screen:")
    a("")
    a("| Arrow table | Home (X, Z) | Bot's walk to the pad | Player's walk from the spawn | Off the first view by |")
    a("|---|---|---|---|---|")
    for k in ONE_V_ONE:
        hx, hz, T, m, Wk = homes[k]
        far = " (more than 120 studs from the spawn view)" if m >= 89.0 else ""
        a("| %d | (%.0f, %.0f) | %.1f s | %.1f s | %s |" % (k, hx, hz, T, Wk, ("%.0f deg" % m) if m < 89 else
                                                           "out of range" + far))
    a("")
    a("How the homes were chosen (by the script, from every free spot on a 3-stud grid): out of the new "
      "player's first view (spawned facing the tables, camera behind them; a phone shows about 56 deg each "
      "side, a PC 51) by at least 20 deg, out of the view of a player walking from the spawn toward that "
      "table (camera along the walk +-20 deg), at least 22 studs from the spawn centre, and then the "
      "shortest walk to the pad. For the two front tables that is just behind the spawn: the bot walks in "
      "from behind the player, the way someone coming up from the spawn would. For deeper tables the "
      "only spots no spawn camera covers are far away at the back, so the bot usually re-stages closer "
      "once the player is walking (rule 3).")
    a("")
    a("**When it teleports (re-stages):**")
    a("")
    a("1. *Placement*: from the hidden room to the home, in the 3 s before the player's first frame, only "
      "when the home is off every reported screen (with the turning margins below). If it is on one, the "
      "nearest spot that is off every screen and at most 0.6 s farther is used. From 1 s before the first "
      "frame it accepts a spot off every screen as last reported (no turning margins), and in the last "
      "half second a spot only the new player cannot see (they are still loading, facing the tables).")
    a("2. *Never* while the player is still looking around at the spawn: it just waits.")
    a("3. *Late*: once the player has been heading to the same pad for 0.3 s, if the bot's walk would end "
      "more than 0.5 s after the target (player's arrival + 1.0 s), and a teleport would save at least "
      "1 s of walking, it teleports to a spot whose walk time matches (at most 0.35 s off), then walks in "
      "from there. The old and the new spot must both be off "
      "the new player's screen (strict test below) and at least 10 studs from every character; it prefers "
      "spots off every other screen too, but takes one only the new player cannot see if that is all "
      "there is. It always walks at least 0.8 s, so it never appears at the pad.")
    a("4. At most one teleport every 0.5 s.")
    a("")
    a("**The strict 'off the new player's screen' test.** The client reports its camera %d times a second "
      "(position and direction). The server widens that view by %.0f deg on every side, plus, on the side "
      "the camera was turning toward, its turn speed x %.2f s (the oldest a report can be by the time a "
      "teleport shows on that screen). If the player dragged the camera in the last 1.5 s it adds 45 deg "
      "more on both sides. If the character is walking (the server sees that at once, before any camera "
      "report), it also blocks the view the camera will swing to: along the walk, +-20 deg, and everything "
      "in between. Before the first report it assumes the camera faces the tables and may be turning. "
      "Other players' screens get the same widening but no extra safety." % (
          int(polA.report_hz), polA.margin_deg, polA.stale))
    a("")
    a("### 2. When the bot starts walking (the trigger)")
    a("")
    a("Every 0.1 s the server decides where the player is going:")
    a("")
    a("- The player is *heading to* pad k when they are moving (over %d studs/s, smoothed over 0.15 s) and "
      "their direction is within 35 deg of the shortest route to pad k (the walking distance to the pad "
      "shrinks by at least 0.82 studs per stud walked). If several pads qualify, the nearest by walking "
      "distance wins. Before the player moves, the arrow's table is assumed." % int(MOVE_MIN))
    a("- **Start walking when the bot's walk time >= the player's time to arrive + 1.0 s.** If the player "
      "stops, add 0.5 s to their time.")
    a("- While walking, the bot pauses (a natural stop) whenever it is more than 0.4 s early, re-routes the "
      "moment the predicted pad changes, and idles 3 studs short of the pad until the player is on it. It "
      "steps on 0.5-0.75 s after the player at the earliest.")
    a("")
    T2 = homes[2][2]
    a("In distances: from the table-2 home (%.0f studs of walking, %.1f s), the bot leaves when the player "
      "is %.1f s, or about %.0f studs, from the pad. The front pads are only 15-25 studs from the spawn, "
      "so for them the bot in practice sets off the moment the player starts walking that way; the rule "
      "matters for the deeper tables and after teleports. A fixed distance cannot do both (variants "
      "table): the right distance depends on where the bot is and how far the player has to go." % (
          T2 * polA.bot_speed / NAT_EST, T2, T2 - polA.target_delay, (T2 - polA.target_delay) * PLAYER_SPEED))
    a("")
    a("### 3. Speed and natural movement")
    a("")
    a("- 20.8 studs/s, like players. Walking includes 15-25% overhead for stop-and-go and slight curves, "
      "so the bot covers about 17 studs per second of walking. The server plans with 1.2; the real "
      "overhead varies from 1.15 to 1.25 per walk, and the plan absorbs it.")
    a("- Use the pauses as the timing knob: stop for a moment when early, skip pauses when late. Never "
      "faster than a player.")
    a("")
    a("### 4. How long players wait")
    a("")
    a("| | Median | 90th | 95th | 99th | Over 2 s | Under 0.5 s | Never came (15 s) |")
    a("|---|---|---|---|---|---|---|---|")
    for nm, S in (("Plan A", SA), ("Plan B", SB)):
        a("| %s, %d joins | %s s | %s s | %s s | %s s | %s | %s | %s |" % (
            nm, S["n"], f2(S["median"]), f2(S["p90"]), f2(S["p95"]), f2(S["p99"]), pc(S["over2"]),
            pc(S["under05"]), pc(S["timeouts"])))
    for title, keyf in (
            ("By what the player did (Plan A)", lambda r: r.behaviour + (" + switched mid-way" if r.switched else "")),
            ("By other players in the server (Plan A)", lambda r: "a. 0 others" if r.n_other == 0 else (
                "b. 1-8 others" if r.n_other <= 8 else ("c. 9-16 others" if r.n_other <= 16 else "d. 17-25 others"))),
            ("By the table the player stepped on (Plan A)", lambda r: "table %02d" % (r.pad_on or 0))):
        a("")
        a("**%s**" % title)
        a("")
        a("| Group | Joins | Median | 95th | Over 2 s | Other players could see it appear | Saw it standing |")
        a("|---|---|---|---|---|---|---|")
        for g, s in by_group(runsA, keyf):
            a("| %s | %d | %s s | %s s | %s | %s | %s |" % (g, s["n"], f2(s["median"]), f2(s["p95"]), pc(s["over2"]),
                                                        pc(s["popin_other_runs"]), pc(s["seen_idle_new"])))
    late = [r for r in runsA if r.wait > 2.0]
    if late:
        groups = {}
        for r in late:
            g = r.behaviour + (" + switched" if r.switched else "")
            groups[g] = groups.get(g, 0) + 1
        a("")
        a("The %d Plan A joins over 2 s: %s. They are players who changed their mind (another table, a "
          "switch, a detour) at a moment when no spot near the new pad was off their screen, so the bot "
          "had to walk the long way." % (len(late), ", ".join("%s %d" % (g, n) for g, n in
                                                              sorted(groups.items(), key=lambda x: -x[1]))))
    a("")
    a("### 5. The risk of being seen at spawn, and how to avoid it")
    a("")
    naive_late = next((v for v in var if v[2].pre_spawn < 0 and not v[2].place_check), None)
    naive_pre = next((v for v in var if v[2].pre_spawn > 0 and not v[2].place_check), None)
    if naive_late:
        a("- The homes sit behind the new player, so the first placement is safe for them even when it is "
          "late: an avatar that finished loading 0.5 s *after* the first frame and was put on its home with "
          "no camera check was seen appearing by the new player in %s of %d joins. Still build it the moment "
          "the player joins, in the hidden room: the camera check is what keeps the later teleports (rule 3) "
          "off their screen, and the variants with a 0 deg margin or 2 reports a second are where "
          "pop-ins start." % (pc(naive_late[3]["popin_new_runs"]), naive_late[3]["n"]))
    if naive_pre:
        a("- Put on its home before the first frame but with no camera check, *other* players could see it "
          "appear in %s of joins (%s with the check)." % (pc(naive_pre[3]["popin_other_runs"]),
                                                          pc(baseA["popin_other_runs"])))
    a("- With the hidden room, the placement before the first frame and the strict test, the new player "
      "saw an appearance in %s and a disappearance in %s of %d joins. That rests on the camera model "
      "(how fast people swing the camera, how late reports are); the margins in the variants table show "
      "how much room there is." % (pc(SA["popin_new_runs"]), pc(SA["popout_new_runs"]), SA["n"]))
    a("- Other players are the weak spot of Plan A: %s of joins had *some* other player whose screen "
      "covered the spot when the bot appeared (%s within 50 studs, where it is hard to miss). With 0 others "
      "it never happens; with 17-25 others it is most joins (table above). Most of it is the first "
      "placement near the busy spawn. Plan B (or the spawn-pad variant, where it looks like a player "
      "joining) fixes it." % (pc(SA["popin_other_runs"]), pc(SA["popin_other_near_runs"])))
    a("- The new player saw the bot *standing* at its waiting spot in %s of joins (mostly players who "
      "drag the camera around at the spawn). That is not a pop-in: it looks like any player idling near "
      "the spawn. Give it the normal idle animation." % pc(SA["seen_idle_new"]))
    a("")
    # ---------------------------------------------------------------- Plan B
    a("## Plan B: one closed kiosk")
    a("")
    a("- Build one small closed building at **(0, 36)**: the crossing of the middle aisle and the walkway "
      "between the first and second rows, in front of tables 2 and 3 (map.svg). About 4 x 4 x 8 studs, "
      "solid walls, a door that opens when the bot walks out (or a curtain). A snack bar, a lift or a "
      "stairwell all fit a rooftop.")
    a("- When the player joins, build the bot inside it. It waits there (invisible) and walks out using "
      "the same trigger as Plan A. No teleports, no camera reports, no visibility math.")
    a("- Why it works so well: the bot's walk from the kiosk is never more than %.1f s longer than the "
      "player's walk from the spawn, and for the deeper tables it is shorter. With a 1.0 s target the bot "
      "can always make it, and the trigger only has to hold it back:" % max(
          fval(world.F[k], KIOSK[0][0], KIOSK[0][1]) * NAT_EST / polA.bot_speed
          - fval(world.F[k], SPAWN_X, SPAWN_Z) / PLAYER_SPEED for k in ONE_V_ONE))
    a("")
    a("| Table | Bot's walk from the kiosk | Player's walk from the spawn |")
    a("|---|---|---|")
    for k in ONE_V_ONE:
        a("| %d | %.1f s | %.1f s |" % (k, fval(world.F[k], KIOSK[0][0], KIOSK[0][1]) * NAT_EST / polA.bot_speed,
                                     fval(world.F[k], SPAWN_X, SPAWN_Z) / PLAYER_SPEED))
    a("")
    a("- Results: median %s s, 95th %s s, 99th %s s, %s over 2 s, never seen appearing by anyone. "
      "At 16 studs/s: 95th %s s, %s over 2 s." % (
          f2(SB["median"]), f2(SB["p95"]), f2(SB["p99"]), pc(SB["over2"]), f2(altB["p95"]), pc(altB["over2"])))
    nomatch = next((v for v in var if v[0] == "B" and v[2].trigger == "dist" and v[2].trigger_dist > 1e6), None)
    if nomatch:
        a("- The time matching matters most here, because the kiosk is close: if the bot simply walks "
          "out the moment the player heads to a pad, it gets there first and idles beside the pad for "
          "1 s or more in %s of joins, and its waits look rushed (median %s s)." % (
              pc(nomatch[3]["loiter"]), f2(nomatch[3]["median"])))
    a("- The bot always comes from the same building. Each new player only meets it once, so that is "
      "fine; several bots can share it.")
    a("")
    # ---------------------------------------------------------------- variants
    a("## Variants (same joins, %d each; one change from the plan)" % args.variant_runs)
    a("")
    a("| Plan | Change | Median | 95th | Over 2 s | New player saw it appear | Others could see it appear | "
      "Saw it standing | Idled 1 s+ by the pad first | Appearances per join |")
    a("|---|---|---|---|---|---|---|---|---|---|")
    for nm, S in (("A", baseA), ("B", baseB)):
        a("| %s | **as recommended** | %s s | %s s | %s | %s | %s | %s | %s | %.2f |" % (
            nm, f2(S["median"]), f2(S["p95"]), pc(S["over2"]), pc(S["popin_new_runs"]), pc(S["popin_other_runs"]),
            pc(S["seen_idle_new"]), pc(S["loiter"]), S["tp_per_run"]))
    for plan, name, pol, vs in var:
        a("| %s | %s | %s s | %s s | %s | %s | %s | %s | %s | %.2f |" % (
            plan, name, f2(vs["median"]), f2(vs["p95"]), pc(vs["over2"]), pc(vs["popin_new_runs"]),
            pc(vs["popin_other_runs"]), pc(vs["seen_idle_new"]), pc(vs["loiter"]), vs["tp_per_run"]))
    a("")
    slow = [name for (plan, name, pol, vs) in var if vs["over2"] > 0.05]
    pops = ["%s (%s)" % (name, pc(vs["popin_new_runs"])) for (plan, name, pol, vs) in var if vs["popin_new_runs"] > 0]
    a("Reading it: more than 5%% of waits go over 2 s with: %s. %s With %d joins per variant, 0%% means "
      "it did not happen in those joins (roughly: fewer than %d in 1000)." % (
          "; ".join(slow) if slow else "none of the variants",
          ("The new player saw an appearance with: %s." % "; ".join(pops)) if pops else
          "No variant made the new player see an appearance.",
          args.variant_runs, max(1, int(math.ceil(3000.0 / args.variant_runs)))))
    a("")
    # ---------------------------------------------------------------- assumptions
    a("## What the model assumed, and why")
    a("")
    a("- **Map**: the brief's layout. Tables are solid 19 x 11 blocks; pads 19 x 8 on the spawn side; "
      "props roughly placed (planters, spawn lanterns and palms, edge posts, couches). Routes are shortest "
      "paths on a 1-stud grid around the blocks, characters kept 1.5 studs clear; players add a small "
      "side-to-side wobble. The kiosk is not modelled as an obstacle (at 4 x 4 it barely changes routes).")
    a("- **New player**: spawns anywhere on the spawn pad facing the tables; looks around for 0.5-3 s (half "
      "drag the camera around); then 75% follow the arrow (nearest empty 1v1 table, picked at join), 20% "
      "pick one of the 3 nearest other empty 1v1 tables, 5% wander 15-40 studs first; 10% switch to "
      "another nearby table 30-70% of the way. Speed 20.8; 30% of phone players push the stick only "
      "75-95%.")
    a("- **Cameras**: Roblox follow camera 13 studs back, vertical field of view 70 deg, phone 2.16:1 or PC "
      "16:9. Walking: along the walk +-20 deg. Standing: dragged around (swings of 30-180 deg at 120-360 "
      "deg/s, held 0.3-1.5 s; idle players hold 1-6 s). Players in a match use the aim view (field of view "
      "60, looking 50-65 deg down at their table). An avatar counts as seen if any part of a 2 x 5.4 stud "
      "box is in a view within 120 studs (a 5-stud avatar at 120 studs is about 35 pixels tall on a 1080p "
      "screen). Nothing hides it except being behind the camera (tables are too low).")
    a("- **Server**: 0-25 other players (uniform), 0-60%% of 1v1 tables busy (1-2 humans each); the rest "
      "play 2v2/3v3, walk around (many near the spawn) or idle (some by pads). Cameras are reported %d "
      "times a second; network delay 0.03-0.12 s each way; a teleport shows on a screen 0.03-0.12 s after "
      "the server does it, and the pop-in check uses the real camera at that moment." % int(polA.report_hz))
    a("- **Bot**: ready in the hidden room 3 s before the player's first frame (Roblox loading takes "
      "longer than that; see the variants for 1 s and for after). Its real walking overhead is 15-25%.")
    a("- **Not modelled**: players bumping into the bot; Roblox pathfinding hiccups beyond the overhead; a "
      "player stepping on and off again; StreamingEnabled (it could hide far avatars anyway); the player "
      "list (a disguised bot is not a real Player, so it is missing from the Tab list; a separate design "
      "question).")
    a("")
    with open(path, "w") as fh:
        fh.write("\n".join(L) + "\n")


if __name__ == "__main__":
    sys.exit(main())
