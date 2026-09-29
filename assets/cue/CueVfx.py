"""Cue VFX: the sprite and flipbook maker, and a Blender preview built only from Roblox's pieces.

    python3 assets/cue/CueVfx.py sprites            (re)make the shared sprite library, vfx/_shared/
    python3 assets/cue/CueVfx.py sprites <id>       a skin's own sprites (SKIN_SPRITES[<id>])

The preview side (imported by CuePreview.py inside Blender) simulates each effect with Roblox's
own semantics so a clip shows what Roblox will show:
  * ParticleEmitter: Rate or Emit(n), Lifetime, Speed, SpreadAngle round EmissionDirection,
    Acceleration (world), Drag (speed halves every 1/Drag s), Size / Transparency (with
    envelopes) / Color sequences, Rotation, RotSpeed, LockedToPart, ZOffset (toward the camera),
    Orientation, Squash, flipbooks (Grid2x2/4x4/8x8; Loop, OneShot, PingPong, Random),
    LightEmission (0 alpha-blended .. 1 additive), Brightness. Unlit (LightInfluence 0).
  * Trail: a camera-facing ribbon between two attachments, Lifetime, WidthScale / Color /
    Transparency along its age, MinLength, TextureMode Stretch / Wrap / Static.
  * Beam: FaceCamera ribbon between two attachments (curves, Width0/1, Segments), Color and
    Transparency along it, TextureSpeed scrolling, ZOffset.
  * The pocket burst exactly as src/client/Effects.pocketBurst builds it from a Config.Effects
    style (streaks, sparkles, the shockwave decal, the swirl ribbons, the PointLight flash), plus
    a skin's extra layers.

Specs are JSON in Roblox's own property names (see skins/<id>.json "vfx"). Positions on the cue
are "AtStuds" (from the tip; the butt is 7) and "Up"/"Side" offsets in studs (Up = the top of
the cue = Roblox local +Y). The Roblox MeshPart frame is Position = (-Side, Up, 3.5 - AtStuds).
Sequences: a number, or [[t, v], ...] / [[t, v, envelope], ...]; colours "#RRGGBB" or
[[t, "#RRGGBB"], ...]; ranges a number or [min, max].
"""

import json
import math
import os
import sys

sys.dont_write_bytecode = True

import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import cue_common as cc  # noqa: E402

VFX = os.path.join(HERE, 'vfx')
SHARED = os.path.join(VFX, '_shared')

# Config.Effects.Styles.Default (src/shared/Config.luau), copied so the preview draws today's
# trail and pocket burst; a skin's style row lists only what differs, as in the game.
DEFAULT_STYLE = {
    'Trail': {'Enabled': True, 'Color': [255, 255, 255], 'NearTransparency': 0.55, 'FarTransparency': 1,
              'Lifetime': 0.34, 'WidthStuds': 0.21, 'LightEmission': 0.4, 'MinLengthStuds': 0.12,
              'Texture': ''},
    'Pocket': {'Enabled': True, 'EightBallScale': 1.6, 'Scale': 1, 'CoreWhiten': 0.55, 'LightEmission': 1,
               'ParticleTexture': 'sparkles_main', 'SparkleTexture': 'sparkles_main',
               'Ribbons': 3, 'EightBallRibbons': 5, 'RibbonWidthStuds': 0.22, 'TrailSeconds': 0.35,
               'SwirlSeconds': 0.6, 'SwirlHeightStuds': 4.2, 'SwirlStartRadiusStuds': 0.25,
               'SwirlEndRadiusStuds': 1.1, 'SwirlTurns': 1.25, 'Streaks': 16, 'StreakSpeedStuds': 16,
               'StreakSizeStuds': 0.45, 'StreakSquash': -2.2, 'StreakLifetime': 0.5,
               'StreakSpreadDegrees': 18, 'StreakDrag': 3, 'Sparkles': 14, 'SparkleSpeedStuds': 7,
               'SparkleSizeStuds': 0.35, 'SparkleLifetime': 0.9, 'SparkleSpreadDegrees': 40,
               'SparkleFallStuds': 3, 'RingStartStuds': 0.6, 'RingEndStuds': 5, 'RingSeconds': 0.45,
               'FlashBrightness': 6, 'FlashRangeStuds': 12, 'FlashSeconds': 0.35},
}


def merged_style(row):
    out = json.loads(json.dumps(DEFAULT_STYLE))
    for part in ('Trail', 'Pocket'):
        for key, value in ((row or {}).get(part) or {}).items():
            out[part][key] = value
    return out


# =============================================================================================
# Sequences and ranges
# =============================================================================================

def hexf(value):
    """'#RRGGBB' or [r, g, b] (0..255) -> float sRGB 0..1."""
    if isinstance(value, str):
        return np.array(cc.hex_rgb(value), np.float64) / 255.0
    return np.array(value, np.float64) / 255.0


class NumSeq:
    def __init__(self, spec, default=0.0):
        if spec is None:
            spec = default
        if isinstance(spec, (int, float)):
            spec = [[0, spec], [1, spec]]
        self.t = np.array([k[0] for k in spec], np.float64)
        self.v = np.array([k[1] for k in spec], np.float64)
        self.e = np.array([k[2] if len(k) > 2 else 0.0 for k in spec], np.float64)

    def __call__(self, t, rnd=None):
        v = np.interp(t, self.t, self.v)
        if rnd is not None and self.e.any():
            v = v + (rnd * 2 - 1) * np.interp(t, self.t, self.e)
        return v


class ColSeq:
    def __init__(self, spec, default='#FFFFFF'):
        if spec is None:
            spec = default
        if isinstance(spec, str) or (isinstance(spec, list) and spec and isinstance(spec[0], (int, float))):
            spec = [[0, spec], [1, spec]]
        self.t = np.array([k[0] for k in spec], np.float64)
        self.c = np.array([hexf(k[1]) for k in spec], np.float64)

    def __call__(self, t):
        t = np.atleast_1d(t)
        return np.stack([np.interp(t, self.t, self.c[:, i]) for i in range(3)], -1)


def rng_range(rs, spec, n, default=0.0):
    if spec is None:
        spec = default
    if isinstance(spec, (int, float)):
        return np.full(n, float(spec))
    lo, hi = spec
    return lo + (hi - lo) * rs.random_sample(n)


# =============================================================================================
# Frames: the cue's pose, as a 4x4 matrix per time (cue local -> world, Blender axes)
# =============================================================================================

def roblox_to_blender(v):
    """A Roblox world vector (Y up) in Blender world axes (Z up)."""
    x, y, z = v
    return np.array([x, -z, y], np.float64)


def cue_point(at, up=0.0, side=0.0):
    """A point in the cue's Blender local frame (tip at the origin, butt along -Y, top +Z)."""
    return np.array([side, -at, up], np.float64)


# =============================================================================================
# The particle emitter
# =============================================================================================

class Emitter:
    """One Roblox ParticleEmitter, simulated. host(t) -> 4x4 world matrix of its host (the cue, or
    the pocket), for LockedToPart and spawning."""

    LAYOUT = {'None': 1, 'Grid2x2': 2, 'Grid4x4': 4, 'Grid8x8': 8}

    def __init__(self, spec, seed=0, rate_scale=1.0, texture_root=HERE):
        self.spec = spec
        self.rs = np.random.RandomState(seed)
        self.rate = float(spec.get('Rate', 0)) * rate_scale
        self.lifetime = spec.get('Lifetime', [1, 1])
        self.speed = spec.get('Speed', [1, 1])
        self.spread = spec.get('SpreadAngle', [0, 0])
        self.acc = roblox_to_blender(spec.get('Acceleration', [0, 0, 0]))
        self.drag = float(spec.get('Drag', 0))
        self.size = NumSeq(spec.get('Size', 1))
        self.transp = NumSeq(spec.get('Transparency', 0))
        self.color = ColSeq(spec.get('Color', '#FFFFFF'))
        self.squash = NumSeq(spec.get('Squash', 0))
        self.le = float(spec.get('LightEmission', 0))
        self.brightness = float(spec.get('Brightness', 1))
        self.rot = spec.get('Rotation', 0)
        self.rotspeed = spec.get('RotSpeed', 0)
        self.locked = bool(spec.get('LockedToPart', False))
        self.zoffset = float(spec.get('ZOffset', 0))
        self.orient = spec.get('Orientation', 'FacingCamera')
        self.direction = spec.get('EmissionDirection', 'Top')
        self.grid = self.LAYOUT.get(spec.get('FlipbookLayout', 'None'), 1)
        self.fb_mode = spec.get('FlipbookMode', 'Loop')
        self.fb_rate = spec.get('FlipbookFramerate', 1)
        self.fb_random = bool(spec.get('FlipbookStartRandom', False))
        tex = spec.get('Texture', 'vfx/_shared/glow_soft.png')
        self.texture = tex if os.path.isabs(tex) else os.path.join(texture_root, tex)
        self.host = spec.get('Host', {'Kind': 'Attachment', 'AtStuds': 5.5})
        self.carry = 0.0
        self.p = {k: np.zeros((0, 3)) for k in ('pos', 'vel')}
        for k in ('age', 'life', 'rot', 'rots', 'rnd', 'fb0', 'fbr'):
            self.p[k] = np.zeros(0)

    # --- spawning ------------------------------------------------------------------------------
    def spawn_local(self, n):
        """n spawn points and unit directions in the host's local frame."""
        h = self.host
        kind = h.get('Kind', 'Attachment')
        rs = self.rs
        if kind == 'Attachment':
            base = cue_point(h.get('AtStuds', 0.0), h.get('Up', 0.0), h.get('Side', 0.0))
            pos = np.repeat(base[None], n, 0)
        elif kind == 'Part':
            a0, a1 = h.get('FromStuds', 3.8), h.get('ToStuds', 6.9)
            wdt = h.get('Width', 0.3)
            along = a0 + (a1 - a0) * rs.random_sample(n)
            if h.get('Shape', 'Box') == 'Cylinder':
                ang = rs.random_sample(n) * 2 * math.pi
                rad = wdt / 2 * (np.ones(n) if h.get('ShapeStyle', 'Surface') == 'Surface' else np.sqrt(rs.random_sample(n)))
                pos = np.stack([rad * np.sin(ang), -along, -rad * np.cos(ang)], -1)
            else:
                pos = np.stack([(rs.random_sample(n) - 0.5) * wdt, -along, (rs.random_sample(n) - 0.5) * wdt], -1)
            pos = pos + np.array([h.get('Side', 0.0), 0.0, h.get('Up', 0.0)])
        else:  # 'Point' in the host's own frame (the pocket): Offset [x, y, z] Roblox axes
            off = roblox_to_blender(h.get('Offset', [0, 0, 0]))
            size = h.get('Size', 0)
            pos = np.repeat(off[None], n, 0)
            if size:
                pos = pos + (rs.random_sample((n, 3)) - 0.5) * np.array([size, size, 0.0])
        # directions: EmissionDirection with SpreadAngle (x about local X, y about local Z)
        dirs = {'Top': (0, 0, 1), 'Bottom': (0, 0, -1), 'Front': (0, 1, 0), 'Back': (0, -1, 0),
                'Right': (-1, 0, 0), 'Left': (1, 0, 0)}
        base_dir = np.array(dirs.get(self.direction, (0, 0, 1)), np.float64)
        sx, sy = (self.spread if isinstance(self.spread, list) else [self.spread, self.spread])
        ax = np.radians((rs.random_sample(n) * 2 - 1) * sx)
        ay = np.radians((rs.random_sample(n) * 2 - 1) * sy)
        d = np.repeat(base_dir[None], n, 0)
        # rotate about the two axes perpendicular to the base direction
        perp1 = np.cross(base_dir, [1, 0, 0] if abs(base_dir[0]) < 0.9 else [0, 1, 0])
        perp1 /= np.linalg.norm(perp1)
        perp2 = np.cross(base_dir, perp1)
        d = (d * np.cos(ax)[:, None] + perp1[None] * np.sin(ax)[:, None])
        d = (d * np.cos(ay)[:, None] + perp2[None] * np.sin(ay)[:, None])
        d /= np.linalg.norm(d, axis=1, keepdims=True)
        io = self.host.get('ShapeInOut')
        if io in ('Inward', 'Outward') and self.host.get('Kind') == 'Part':
            radial = pos.copy()
            radial[:, 1] = 0
            radial[:, 0] -= self.host.get('Side', 0.0)
            radial[:, 2] -= self.host.get('Up', 0.0)
            ln = np.linalg.norm(radial, axis=1, keepdims=True)
            radial = radial / np.maximum(ln, 1e-6)
            d = -radial if io == 'Inward' else radial
        return pos, d

    def emit(self, n, host_m):
        if n <= 0:
            return
        rs = self.rs
        pos, d = self.spawn_local(n)
        speed = rng_range(rs, self.speed, n)
        if self.locked:
            P, V = pos, d * speed[:, None]
        else:
            R, T = host_m[:3, :3], host_m[:3, 3]
            P = pos @ R.T + T
            V = (d @ R.T) * speed[:, None]
        life = rng_range(rs, self.lifetime, n, 1.0)
        rot = rng_range(rs, self.rot, n)
        rots = rng_range(rs, self.rotspeed, n)
        rnd = rs.random_sample(n)
        fb0 = rs.randint(0, self.grid * self.grid, n) if self.fb_random else np.zeros(n)
        fbr = rng_range(rs, self.fb_rate, n, 1.0)
        for key, val in (('pos', P), ('vel', V), ('age', np.zeros(n)), ('life', life), ('rot', rot),
                         ('rots', rots), ('rnd', rnd), ('fb0', fb0.astype(np.float64)), ('fbr', fbr)):
            self.p[key] = np.concatenate([self.p[key], val])

    def step(self, dt, host_m, emitting=True):
        p = self.p
        if len(p['age']):
            acc = self.acc
            if self.locked:
                # acceleration is world space; bring it into the host frame
                acc = host_m[:3, :3].T @ acc
            p['vel'] = p['vel'] + acc[None] * dt
            if self.drag:
                p['vel'] = p['vel'] * (0.5 ** (self.drag * dt))
            p['pos'] = p['pos'] + p['vel'] * dt
            p['age'] = p['age'] + dt
            p['rot'] = p['rot'] + p['rots'] * dt
            keep = p['age'] < p['life']
            for key in p:
                p[key] = p[key][keep]
        if emitting and self.rate > 0:
            self.carry += self.rate * dt
            n = int(self.carry)
            self.carry -= n
            self.emit(n, host_m)

    # --- drawing -------------------------------------------------------------------------------
    def quads(self, host_m, cam_m):
        """Per live particle: 4 world corners, UVs (flipbook), RGBA; sorted back to front."""
        p = self.p
        n = len(p['age'])
        if n == 0:
            return None
        t = np.clip(p['age'] / p['life'], 0, 1)
        pos = p['pos']
        vel = p['vel']
        if self.locked:
            R, T = host_m[:3, :3], host_m[:3, 3]
            pos = pos @ R.T + T
            vel = vel @ R.T
        cam_pos = cam_m[:3, 3]
        cam_right = cam_m[:3, 0]
        cam_up = cam_m[:3, 1]
        to_cam = cam_pos[None] - pos
        dist = np.linalg.norm(to_cam, axis=1, keepdims=True)
        view = to_cam / np.maximum(dist, 1e-6)
        pos = pos + view * self.zoffset
        size = np.maximum(self.size(t, p['rnd']), 0)
        sq = self.squash(t)
        half_w = size / 2 * np.power(2.0, sq * 0.5)
        half_h = size / 2 * np.power(2.0, -sq * 0.5)
        if self.orient in ('VelocityParallel', 'VelocityPerpendicular'):
            v = vel / np.maximum(np.linalg.norm(vel, axis=1, keepdims=True), 1e-6)
            up = v - view * (v * view).sum(1, keepdims=True)
            up /= np.maximum(np.linalg.norm(up, axis=1, keepdims=True), 1e-6)
            right = np.cross(up, view)
            if self.orient == 'VelocityPerpendicular':
                up, right = right, -up
            ang = np.zeros(n)
        else:
            right = np.repeat(cam_right[None], n, 0)
            up = np.repeat(cam_up[None], n, 0)
            if self.orient == 'FacingCameraWorldUp':
                wu = np.array([0.0, 0.0, 1.0])
                right = np.cross(wu[None], view)
                right /= np.maximum(np.linalg.norm(right, axis=1, keepdims=True), 1e-6)
                up = np.cross(view, right)
            ang = np.radians(p['rot'])
        ca, sa = np.cos(ang)[:, None], np.sin(ang)[:, None]
        r2 = right * ca + up * sa
        u2 = -right * sa + up * ca
        rx, uy = r2 * half_w[:, None], u2 * half_h[:, None]
        corners = np.stack([pos - rx - uy, pos + rx - uy, pos + rx + uy, pos - rx + uy], 1)
        # flipbook frame
        g = self.grid
        if g > 1:
            frames = g * g
            if self.fb_mode == 'OneShot':
                f = np.floor(t * frames)
            elif self.fb_mode == 'PingPong':
                k = np.floor(p['age'] * p['fbr']) + p['fb0']
                period = 2 * frames - 2
                k = np.mod(k, period)
                f = np.where(k < frames, k, period - k)
            elif self.fb_mode == 'Random':
                f = np.floor(np.mod(p['rnd'] * 997 + np.floor(p['age'] * p['fbr']) * 7.31, frames))
            else:
                f = np.mod(np.floor(p['age'] * p['fbr']) + p['fb0'], frames)
            f = np.clip(f, 0, frames - 1)
            col_i, row_i = np.mod(f, g), np.floor(f / g)
        else:
            col_i = row_i = np.zeros(n)
        u0, u1 = col_i / g, (col_i + 1) / g
        v1, v0 = 1 - row_i / g, 1 - (row_i + 1) / g  # image row 0 at the top
        uv = np.stack([np.stack([u0, v0], -1), np.stack([u1, v0], -1), np.stack([u1, v1], -1),
                       np.stack([u0, v1], -1)], 1)
        col = self.color(t)
        alpha = 1 - np.clip(self.transp(t, p['rnd']), 0, 1)
        rgba = np.concatenate([col, alpha[:, None]], 1)
        order = np.argsort(-dist[:, 0])
        return corners[order], uv[order], rgba[order]


# =============================================================================================
# Trails and beams
# =============================================================================================

class Trail:
    """A Roblox Trail with FaceCamera: points laid as its attachments move; drawn as a ribbon
    whose width is the attachments' spacing times WidthScale over the age fraction."""

    def __init__(self, spec, texture_root=HERE):
        self.spec = spec
        self.life = float(spec.get('Lifetime', 0.34))
        self.width = float(spec.get('WidthStuds', 0.21))
        self.wscale = NumSeq(spec.get('WidthScale', 1))
        self.color = ColSeq(spec.get('Color', '#FFFFFF'))
        self.transp = NumSeq(spec.get('Transparency', [[0, 0.55], [1, 1]]))
        self.le = float(spec.get('LightEmission', 0.4))
        self.brightness = float(spec.get('Brightness', 1))
        self.min_len = float(spec.get('MinLength', 0.12))
        self.mode = spec.get('TextureMode', 'Stretch')
        self.tex_len = float(spec.get('TextureLength', 1))
        tex = spec.get('Texture') or 'vfx/_shared/trail_soft.png'
        self.texture = tex if os.path.isabs(tex) else os.path.join(texture_root, tex)
        self.pts = []  # (pos, time)
        self.enabled = True

    def step(self, t, pos):
        if self.enabled:
            if not self.pts or np.linalg.norm(pos - self.pts[-1][0]) >= self.min_len * 0.25:
                self.pts.append((np.array(pos, np.float64), t))
        self.pts = [q for q in self.pts if t - q[1] <= self.life]
        self.head = (np.array(pos, np.float64), t)

    def quads(self, t, cam_m):
        pts = list(self.pts)
        if self.enabled and hasattr(self, 'head'):
            pts = pts + [self.head]
        if len(pts) < 2:
            return None
        P = np.array([q[0] for q in pts])
        age = np.clip(np.array([(t - q[1]) / self.life for q in pts]), 0, 1)
        seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
        if seg.sum() < 1e-4:
            return None
        cam = cam_m[:3, 3]
        tang = np.gradient(P, axis=0)
        tang /= np.maximum(np.linalg.norm(tang, axis=1, keepdims=True), 1e-6)
        view = cam[None] - P
        view /= np.maximum(np.linalg.norm(view, axis=1, keepdims=True), 1e-6)
        side = np.cross(tang, view)
        side /= np.maximum(np.linalg.norm(side, axis=1, keepdims=True), 1e-6)
        w = self.width * np.maximum(self.wscale(age), 0) / 2
        L = P - side * w[:, None]
        R = P + side * w[:, None]
        # texture coordinate along the trail (the newest end is 0)
        along = np.concatenate([[0], np.cumsum(seg)])
        along = along[-1] - along
        if self.mode == 'Wrap':
            u = along / self.tex_len
        elif self.mode == 'Static':
            u = (along[-1] - along) / self.tex_len  # fixed to the world as laid
        else:
            u = age
        col = self.color(age)
        alpha = 1 - np.clip(self.transp(age), 0, 1)
        n = len(P) - 1
        corners = np.stack([L[:-1], R[:-1], R[1:], L[1:]], 1)
        uv = np.stack([np.stack([u[:-1], np.zeros(n)], -1), np.stack([u[:-1], np.ones(n)], -1),
                       np.stack([u[1:], np.ones(n)], -1), np.stack([u[1:], np.zeros(n)], -1)], 1)
        rgba_pt = np.concatenate([col, alpha[:, None]], 1)
        rgba = np.stack([rgba_pt[:-1], rgba_pt[:-1], rgba_pt[1:], rgba_pt[1:]], 1)
        return corners, uv, rgba


class Beam:
    """A Roblox Beam from a0 to a1 (cue local points), FaceCamera, straight or curved, with its
    texture scrolling at TextureSpeed (texture lengths a second) and a ZOffset toward the camera."""

    def __init__(self, spec, texture_root=HERE):
        self.spec = spec
        self.a0 = cue_point(spec.get('FromStuds', 3.8), spec.get('Up', 0.0), spec.get('Side', 0.0))
        self.a1 = cue_point(spec.get('ToStuds', 5.3), spec.get('Up', 0.0), spec.get('Side', 0.0))
        self.w0 = float(spec.get('Width0', 0.18))
        self.w1 = float(spec.get('Width1', self.w0))
        self.segments = int(spec.get('Segments', 10))
        self.color = ColSeq(spec.get('Color', '#FFFFFF'))
        self.transp = NumSeq(spec.get('Transparency', 0))
        self.le = float(spec.get('LightEmission', 1))
        self.brightness = float(spec.get('Brightness', 1))
        self.speed = float(spec.get('TextureSpeed', 0))
        self.tex_len = float(spec.get('TextureLength', 1))
        self.mode = spec.get('TextureMode', 'Wrap')
        self.zoffset = float(spec.get('ZOffset', 0))
        self.face = bool(spec.get('FaceCamera', True))
        self.pulse = spec.get('Pulse')  # a script tweening Transparency: alpha x wave(t)
        # a curved beam: Bezier control points at 1/3 and 2/3 of the way, pushed off the line by
        # Curve0 / Curve1 = [up, side] studs (in Roblox: each attachment's Axis and CurveSize);
        # Twist turns both offsets round the cue at degrees a second (a script)
        self.curve0 = spec.get('Curve0')
        self.curve1 = spec.get('Curve1')
        self.twist = float(spec.get('Twist', 0))
        tex = spec.get('Texture', 'vfx/_shared/glow_soft.png')
        self.texture = tex if os.path.isabs(tex) else os.path.join(texture_root, tex)

    def points(self, t, k):
        """Local points along the beam at fractions k (Bezier when curved)."""
        a0, a1 = self.a0, self.a1
        if not (self.curve0 or self.curve1):
            return a0[None] * (1 - k[:, None]) + a1[None] * k[:, None]
        ang = math.radians(self.twist * t)

        def off(c):
            if not c:
                return np.zeros(3)
            up, side = c[0], c[1]
            ca, sa = math.cos(ang), math.sin(ang)
            up, side = up * ca - side * sa, up * sa + side * ca
            return np.array([-side, 0.0, up])  # cue_point axes: x = -side, z = up
        c1 = a0 + (a1 - a0) / 3 + off(self.curve0)
        c2 = a0 + (a1 - a0) * 2 / 3 + off(self.curve1)
        kk = k[:, None]
        return ((1 - kk) ** 3 * a0 + 3 * (1 - kk) ** 2 * kk * c1 + 3 * (1 - kk) * kk ** 2 * c2 + kk ** 3 * a1)

    def quads(self, t, host_m, cam_m, pulse=1.0):
        R, T = host_m[:3, :3], host_m[:3, 3]
        n = self.segments
        k = np.linspace(0, 1, n + 1)
        P = self.points(t, k) @ R.T + T
        cam = cam_m[:3, 3]
        view = cam[None] - P
        view /= np.maximum(np.linalg.norm(view, axis=1, keepdims=True), 1e-6)
        P = P + view * self.zoffset
        tang = np.gradient(P, axis=0)
        tang = tang / np.maximum(np.linalg.norm(tang, axis=1, keepdims=True), 1e-6)
        if self.face:
            side = np.cross(tang, view)
        else:
            side = np.repeat((np.array([1.0, 0, 0]) @ R.T)[None], n + 1, 0)
        side /= np.maximum(np.linalg.norm(side, axis=1, keepdims=True), 1e-6)
        w = (self.w0 * (1 - k) + self.w1 * k) / 2
        L, Rr = P - side * w[:, None], P + side * w[:, None]
        length = float(np.linalg.norm(np.diff(self.points(t, k), axis=0), axis=1).sum())
        if self.mode == 'Stretch':
            u = k.copy()
        else:
            u = k * length / self.tex_len
        u = u - t * self.speed  # Roblox scrolls the texture along the beam
        col = self.color(k)
        if self.pulse:
            pulse = pulse * wave(t, self.pulse)
        alpha = (1 - np.clip(self.transp(k), 0, 1)) * pulse
        corners = np.stack([L[:-1], Rr[:-1], Rr[1:], L[1:]], 1)
        uv = np.stack([np.stack([u[:-1], np.zeros(n)], -1), np.stack([u[:-1], np.ones(n)], -1),
                       np.stack([u[1:], np.ones(n)], -1), np.stack([u[1:], np.zeros(n)], -1)], 1)
        rgba_pt = np.concatenate([col, alpha[:, None]], 1)
        rgba = np.stack([rgba_pt[:-1], rgba_pt[:-1], rgba_pt[1:], rgba_pt[1:]], 1)
        return corners, uv, rgba


# =============================================================================================
# Scripted pieces: orbiters (a Trail on an attachment pair a script flies round the cue) and
# arcs (lightning: chains of short Beams whose attachments a script re-jitters). Each behaves
# like an Emitter in the preview loops: step(dt, host_m), quads(host_m, cam_m), texture, le.
# =============================================================================================

class Orbiter:
    """An attachment pair flown by a script along a helix round the cue: along the cue from
    FromStuds to ToStuds in TravelSeconds (Loop 'wrap' starts again at FromStuds, 'pingpong' comes
    back), TurnsPerSecond round it at Radius studs (plus Wobble studs in and out), starting at
    Phase degrees and Delay seconds. It carries a Roblox Trail (the spec's Trail keys: Lifetime,
    WidthStuds = the attachments' spacing, Color, Transparency, WidthScale, LightEmission,
    Texture). The trail is laid in the world, so it streams behind as the cue moves."""

    extension = 'REPEAT'

    def __init__(self, spec, texture_root=HERE):
        self.spec = spec
        tr = dict(spec.get('Trail') or {})
        tr.setdefault('MinLength', 0.02)
        self.trail = Trail(tr, texture_root)
        self.texture, self.le, self.brightness = self.trail.texture, self.trail.le, self.trail.brightness
        self.t = -float(spec.get('Delay', 0.0))
        self.last_u = None

    def local(self, t):
        s = self.spec
        a0, a1 = float(s.get('FromStuds', 0.3)), float(s.get('ToStuds', 6.9))
        T = float(s.get('TravelSeconds', 1.5))
        u = (t / T) if T > 0 else 0.0
        if s.get('Loop', 'wrap') == 'pingpong':
            f = u % 2.0
            f = f if f <= 1 else 2 - f
        else:
            f = u % 1.0
        d = a0 + (a1 - a0) * f
        ang = math.radians(float(s.get('Phase', 0))) + 2 * math.pi * float(s.get('TurnsPerSecond', 1.0)) * t
        rad = float(s.get('Radius', 0.2)) + float(s.get('Wobble', 0.0)) * math.sin(2 * math.pi * t * float(s.get('WobbleHz', 1.3)))
        return np.array([rad * math.sin(ang), -d, -rad * math.cos(ang)]), u

    def step(self, dt, host_m, emitting=True):
        self.t += dt
        if self.t < 0:
            return
        loc, u = self.local(self.t)
        if self.spec.get('Loop', 'wrap') != 'pingpong' and self.last_u is not None and int(u) != int(self.last_u):
            self.trail.pts = []  # wrapped back to the start: the attachment jumps, the trail breaks
        self.last_u = u
        R, T = host_m[:3, :3], host_m[:3, 3]
        self.pos = loc @ R.T + T
        self.trail.step(self.t, self.pos)

    def quads(self, host_m, cam_m):
        if self.t < 0:
            return None
        return self.trail.quads(self.t, cam_m)


class OrbiterHead:
    """A glowing sprite riding an orbiter (in Roblox a ParticleEmitter with Rate 0 would not do:
    it is a small camera-facing BillboardGui or a Beam dot on the same attachment)."""

    extension = 'CLIP'

    def __init__(self, orbiter, spec, texture_root=HERE):
        self.o = orbiter
        self.size = float(spec.get('Size', 0.3))
        self.color = hexf(spec.get('Color', '#FFFFFF'))
        self.alpha = 1 - float(spec.get('Transparency', 0.0))
        tex = spec.get('Texture', 'vfx/_shared/glow_core.png')
        self.texture = tex if os.path.isabs(tex) else os.path.join(texture_root, tex)
        self.le = float(spec.get('LightEmission', 1))
        self.brightness = float(spec.get('Brightness', 1))

    def step(self, dt, host_m, emitting=True):
        pass

    def quads(self, host_m, cam_m):
        if self.o.t < 0 or not hasattr(self.o, 'pos'):
            return None
        p = self.o.pos
        r, u = cam_m[:3, 0] * self.size / 2, cam_m[:3, 1] * self.size / 2
        corners = np.array([[p - r - u, p + r - u, p + r + u, p - r + u]])
        uv = np.array([[[0, 0], [1, 0], [1, 1], [0, 1]]], np.float64)
        rgba = np.array([list(self.color) + [self.alpha]])
        return corners, uv, rgba


class Arcs:
    """Lightning arcs crackling over the cue: Count arcs, each a chain of Segments short Beams on
    Segments + 1 attachments. Every Interval seconds a script picks each arc a new start (FromStuds
    to ToStuds, any angle), a length (Length [min, max] studs along the cue), a turn round the cue
    (Around degrees) and a fresh jag (Jitter studs off the surface at Radius); the arc shows for
    Duty of the interval (the flicker). Drawn camera-facing, WidthStuds wide, Texture across."""

    extension = 'CLIP'

    def __init__(self, spec, seed=0, texture_root=HERE):
        self.spec = spec
        self.rs = np.random.RandomState(seed)
        self.t = 0.0
        self.slot = None
        self.paths = []
        tex = spec.get('Texture', 'vfx/_shared/bolt_strip.png')
        self.texture = tex if os.path.isabs(tex) else os.path.join(texture_root, tex)
        self.le = float(spec.get('LightEmission', 1))
        self.brightness = float(spec.get('Brightness', 1))
        self.color = hexf(spec.get('Color', '#C9A0FF'))

    def repick(self):
        s, rs = self.spec, self.rs
        n = int(s.get('Count', 3))
        seg = int(s.get('Segments', 6))
        a0, a1 = float(s.get('FromStuds', 3.6)), float(s.get('ToStuds', 6.9))
        lmin, lmax = s.get('Length', [0.25, 0.7])
        around = math.radians(float(s.get('Around', 90)))
        rad = float(s.get('Radius', 0.12))
        jit = float(s.get('Jitter', 0.05))
        self.paths = []
        for _ in range(n):
            L = lmin + (lmax - lmin) * rs.random_sample()
            d0 = a0 + (a1 - a0 - L) * rs.random_sample()
            th0 = rs.random_sample() * 2 * math.pi
            th1 = th0 + (rs.random_sample() * 2 - 1) * around
            k = np.linspace(0, 1, seg + 1)
            d = d0 + L * k
            th = th0 + (th1 - th0) * k
            # the arc bows out from the surface in the middle and jags
            r = rad + jit * (np.sin(math.pi * k) * (0.6 + 0.8 * rs.random_sample()))
            jag = (rs.random_sample((seg + 1, 3)) * 2 - 1) * jit
            jag[0] = jag[-1] = 0
            pts = np.stack([r * np.sin(th), -d, -r * np.cos(th)], -1) + jag
            self.paths.append(pts)

    def step(self, dt, host_m, emitting=True):
        self.t += dt
        slot = int(self.t / float(self.spec.get('Interval', 0.12)))
        if slot != self.slot:
            self.slot = slot
            self.repick()

    def quads(self, host_m, cam_m):
        s = self.spec
        iv = float(s.get('Interval', 0.12))
        if (self.t % iv) / iv > float(s.get('Duty', 0.6)):
            return None
        R, T = host_m[:3, :3], host_m[:3, 3]
        cam = cam_m[:3, 3]
        w = float(s.get('WidthStuds', 0.05)) / 2
        alpha = 1 - float(s.get('Transparency', 0.0))
        C, U, A = [], [], []
        for pts in self.paths:
            P = pts @ R.T + T
            tang = np.gradient(P, axis=0)
            tang /= np.maximum(np.linalg.norm(tang, axis=1, keepdims=True), 1e-6)
            view = cam[None] - P
            view /= np.maximum(np.linalg.norm(view, axis=1, keepdims=True), 1e-6)
            side = np.cross(tang, view)
            side /= np.maximum(np.linalg.norm(side, axis=1, keepdims=True), 1e-6)
            taper = np.sin(np.linspace(0.15, math.pi - 0.15, len(P)))
            L, Rr = P - side * (w * taper)[:, None], P + side * (w * taper)[:, None]
            n = len(P) - 1
            k = np.linspace(0, 1, n + 1)
            C.append(np.stack([L[:-1], Rr[:-1], Rr[1:], L[1:]], 1))
            U.append(np.stack([np.stack([k[:-1], np.zeros(n)], -1), np.stack([k[:-1], np.ones(n)], -1),
                               np.stack([k[1:], np.ones(n)], -1), np.stack([k[1:], np.zeros(n)], -1)], 1))
            A.append(np.repeat(np.array([list(self.color) + [alpha]])[None], n, 0).repeat(4, 1).reshape(n, 4, 4))
        if not C:
            return None
        return np.concatenate(C), np.concatenate(U), np.concatenate(A)


def make_pieces(aura, seed=1, rate_scale=1.0, texture_root=HERE):
    """The scripted pieces of an aura block: Orbiters (with optional Head) and Arcs. On the back
    (rate_scale < 1) arcs keep their count; orbiters are the same (they cost no particles)."""
    out = []
    for i, spec in enumerate(aura.get('Orbiters') or []):
        o = Orbiter(spec, texture_root)
        out.append(o)
        if spec.get('Head'):
            out.append(OrbiterHead(o, spec['Head'], texture_root))
    for i, spec in enumerate(aura.get('Arcs') or []):
        out.append(Arcs(spec, seed=seed + 101 * i, texture_root=texture_root))
    return out


def wave(t, spec):
    """A runtime pulse (a script tweening a property): {"Min", "Max", "Period", "Shape": sine|flicker|beat}."""
    if not spec:
        return None
    lo, hi = spec.get('Min', 0), spec.get('Max', 1)
    period = spec.get('Period', 2.0)
    shape = spec.get('Shape', 'sine')
    ph = (t / period + spec.get('Phase', 0.0)) % 1.0
    if shape == 'flicker':
        # mostly steady with quick dips, as a neon tube
        k = 0.85 + 0.15 * math.sin(2 * math.pi * ph)
        dip = math.sin(t * 37.0) * math.sin(t * 11.3)
        if dip > 0.93:
            k *= 0.45
        return lo + (hi - lo) * k
    if shape == 'beat':
        k = math.exp(-((ph - 0.1) / 0.08) ** 2) + 0.6 * math.exp(-((ph - 0.32) / 0.08) ** 2)
        return lo + (hi - lo) * min(k, 1.0)
    return lo + (hi - lo) * (0.5 - 0.5 * math.cos(2 * math.pi * ph))


# =============================================================================================
# The pocket burst (Effects.pocketBurst, ported) and a skin's extra layers
# =============================================================================================

def pocket_layers(style_row, ball_rgb=(255, 255, 255), eight=False):
    """The emitters, ribbons, shockwave and flash Effects.pocketBurst makes for a style.
    Returns a dict of specs (in pocket-local Roblox axes) for PocketBurst."""
    spec = merged_style(style_row)['Pocket']
    more = spec['EightBallScale'] if eight else 1
    scale = more * spec['Scale']
    ball = np.array(ball_rgb, np.float64)
    own = spec.get('Colors')
    white = np.array([255.0, 255, 255])
    if own:
        share = spec.get('ColorShare', 1)
        shade = ball + (np.array(own[0], np.float64) - ball) * share
        bright = shade + (white - shade) * spec['CoreWhiten']
        keys = [[0, list(bright)]]
        for i, c in enumerate(own):
            tt = 0.35 if len(own) == 1 else 0.35 + 0.65 * i / (len(own) - 1)
            keys.append([tt, list(ball + (np.array(c, np.float64) - ball) * share)])
        if len(own) == 1:
            keys.append([1, list(shade)])
        tint = keys
    else:
        shade = ball
        bright = shade + (white - shade) * spec['CoreWhiten']
        tint = [[0, list(bright)], [0.35, list(shade)], [1, list(shade)]]
    tint = [[k[0], [float(x) for x in k[1]]] for k in tint]
    glow = spec['LightEmission']
    ptex = texture_for(spec['ParticleTexture'])
    stex = texture_for(spec['SparkleTexture'])
    layers = []
    layers.append({'Name': 'WindStreaks', 'Texture': ptex, 'Color': tint, 'LightEmission': glow,
                   'Orientation': 'VelocityParallel', 'Squash': spec['StreakSquash'],
                   'Size': [[0, spec['StreakSizeStuds'] * scale], [1, 0]],
                   'Transparency': [[0, 0.05], [0.6, 0.35], [1, 1]],
                   'Lifetime': [spec['StreakLifetime'] * 0.6, spec['StreakLifetime']],
                   'Speed': [spec['StreakSpeedStuds'] * 0.6 * scale, spec['StreakSpeedStuds'] * scale],
                   'SpreadAngle': [spec['StreakSpreadDegrees']] * 2, 'EmissionDirection': 'Top',
                   'Drag': spec['StreakDrag'], 'Burst': int(math.floor(spec['Streaks'] * more + 0.5)),
                   'Host': {'Kind': 'Point'}})
    layers.append({'Name': 'Sparkles', 'Texture': stex, 'Color': tint, 'LightEmission': glow,
                   'Size': [[0, spec['SparkleSizeStuds'] * scale], [1, 0]], 'Transparency': [[0, 0], [1, 1]],
                   'Lifetime': [spec['SparkleLifetime'] * 0.6, spec['SparkleLifetime']],
                   'Speed': [spec['SparkleSpeedStuds'] * 0.4 * spec['Scale'], spec['SparkleSpeedStuds'] * spec['Scale']],
                   'SpreadAngle': [spec['SparkleSpreadDegrees']] * 2, 'EmissionDirection': 'Top',
                   'Acceleration': [0, -spec['SparkleFallStuds'], 0], 'Drag': 2, 'RotSpeed': [-180, 180],
                   'Burst': int(math.floor(spec['Sparkles'] * more + 0.5)), 'Host': {'Kind': 'Point'}})
    ring = {'Texture': texture_for('ring'), 'Color': [float(x) for x in bright],
            'Start': spec['RingStartStuds'], 'End': spec['RingEndStuds'] * scale, 'Seconds': spec['RingSeconds']}
    ribbons = {'Count': spec['EightBallRibbons'] if eight else spec['Ribbons'],
               'Width': spec['RibbonWidthStuds'] * scale, 'TrailSeconds': spec['TrailSeconds'],
               'SwirlSeconds': spec['SwirlSeconds'], 'Height': spec['SwirlHeightStuds'] * scale,
               'R0': spec['SwirlStartRadiusStuds'] * scale, 'R1': spec['SwirlEndRadiusStuds'] * scale,
               'Turns': spec['SwirlTurns'], 'Color': tint, 'LightEmission': glow}
    flash = {'Color': [float(x) for x in shade], 'Brightness': spec['FlashBrightness'] * scale,
             'Range': spec['FlashRangeStuds'] * scale, 'Seconds': spec['FlashSeconds']}
    return {'layers': layers, 'ring': ring, 'ribbons': ribbons, 'flash': flash, 'scale': scale}


def texture_for(name):
    """A Config texture name -> a preview sprite. Roblox's built-in sparkles_main.dds is drawn by
    our look-alike; 'ring' is Config.Guideline.RingTextureId's look-alike."""
    if not name:
        return 'vfx/_shared/glow_soft.png'
    if name in ('sparkles_main', 'rbxasset://textures/particles/sparkles_main.dds'):
        return 'vfx/_shared/sparkles_main.png'
    if name == 'ring':
        return 'vfx/_shared/ring.png'
    return name


# =============================================================================================
# Sprites (numpy; run on the Mac's Python or in Blender)
# =============================================================================================

def _grid(n):
    y, x = np.mgrid[0:n, 0:n]
    return (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1


def _rgba(alpha, color=(255, 255, 255), core=None):
    """White (or colour) sprite with alpha; core (0..1) lifts the centre toward white."""
    a = np.clip(alpha, 0, 1)
    c = np.zeros(a.shape + (3,)) + np.array(color, np.float64)
    if core is not None:
        c = c + (255 - c) * np.clip(core, 0, 1)[..., None]
    return np.concatenate([c, a[..., None] * 255], -1)


def sprite_glow_soft(n=128):
    x, y = _grid(n)
    r = np.hypot(x, y)
    return _rgba(np.clip(1 - r, 0, 1) ** 2.2)


def sprite_glow_core(n=128):
    x, y = _grid(n)
    r = np.hypot(x, y)
    return _rgba(np.clip(1 - r, 0, 1) ** 1.2 * 0.6 + np.exp(-(r / 0.12) ** 2) * 0.4)


def sprite_star4(n=128, arms=4, sharp=18.0, halo=0.35):
    x, y = _grid(n)
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    spikes = np.abs(np.cos(th * arms / 2)) ** sharp
    ray = np.clip(1 - r, 0, 1) ** 1.5 * spikes
    core = np.exp(-(r / 0.1) ** 2)
    glow = np.clip(1 - r, 0, 1) ** 3 * halo
    return _rgba(np.clip(ray + core + glow, 0, 1))


def sprite_sparkles_main(n=128):
    """A look-alike of Roblox's built-in sparkles_main: a bright four-point twinkle with a soft
    glow (what Config's pocket burst uses today)."""
    a = sprite_star4(n, 4, 26.0, 0.5)
    x, y = _grid(n)
    th = np.arctan2(y, x) + math.pi / 4
    r = np.hypot(x, y)
    diag = np.clip(1 - r * 1.6, 0, 1) ** 2 * np.abs(np.cos(th * 2)) ** 40 * 0.5
    a[..., 3] = np.clip(a[..., 3] / 255 + diag, 0, 1) * 255
    return a


def sprite_ring(n=256, width=0.08):
    x, y = _grid(n)
    r = np.hypot(x, y)
    a = np.exp(-((r - 0.86) / width) ** 2) + 0.35 * np.exp(-((r - 0.86) / (width * 3)) ** 2)
    return _rgba(np.clip(a, 0, 1))


def sprite_trail_soft(w=256, h=64):
    """A trail/beam strip: bright along the middle row, soft to both edges."""
    y = (np.arange(h) + 0.5) / h * 2 - 1
    a = np.clip(1 - np.abs(y), 0, 1) ** 1.6
    a = np.repeat(a[:, None], w, 1)
    return _rgba(a, core=np.repeat((np.clip(1 - np.abs(y) / 0.25, 0, 1))[:, None], w, 1) * 0.0)


def sprite_spark(n=64):
    """A small hot dot with a tight halo (embers, sparks)."""
    x, y = _grid(n)
    r = np.hypot(x, y)
    return _rgba(np.clip(np.exp(-(r / 0.28) ** 2) + 0.25 * np.clip(1 - r, 0, 1) ** 2, 0, 1))


def sprite_streak(w=128, h=32):
    x = (np.arange(w) + 0.5) / w * 2 - 1
    y = (np.arange(h) + 0.5) / h * 2 - 1
    X, Y = np.meshgrid(x, y)
    a = np.clip(1 - np.abs(Y), 0, 1) ** 2 * np.clip(1 - np.abs(X), 0, 1) ** 0.8
    return _rgba(a)


def flipbook(frames_fn, grid, size=1024, pad=8):
    """Lay grid x grid frames (frames_fn(i, cell_px) -> RGBA cell) into one sheet with padding."""
    cell = size // grid
    sheet = np.zeros((size, size, 4))
    inner = cell - 2 * pad
    for i in range(grid * grid):
        r, c = divmod(i, grid)
        img = frames_fn(i, inner)
        sheet[r * cell + pad:r * cell + pad + inner, c * cell + pad:c * cell + pad + inner] = img
    return sheet


def smoke_frame(i, n, frames=16, seed=7):
    """One frame of a soft billowing puff: it swells, curls and thins over the sheet."""
    k = i / (frames - 1)
    x, y = _grid(n)
    z = np.full_like(x, k * 1.5)
    wx = cc.fbm(x * 1.3 + 4, y * 1.3, z, 3, seed + 1) - 0.5
    wy = cc.fbm(x * 1.3, y * 1.3 + 9, z, 3, seed + 2) - 0.5
    r = np.hypot(x + wx * 0.5, y + wy * 0.5)
    q = cc.fbm(x * 1.8 + 10 + wx, y * 1.8 + 3 + wy, z, 3, seed)
    edge = 0.62 + 0.3 * k
    body = np.clip((edge - r) / (0.45 + 0.2 * k), 0, 1) ** 1.3
    a = body * np.clip(0.35 + 1.1 * q - 0.35 * k, 0, 1) * (1 - 0.45 * k)
    return _rgba(np.clip(a * 1.25, 0, 1))


def sprite_smoke_sheet():
    return flipbook(lambda i, n: smoke_frame(i, n), 4, 1024)


def save_rgba(path, arr):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        from PIL import Image
        Image.fromarray(np.clip(np.round(arr), 0, 255).astype(np.uint8)).save(path, optimize=True)
    except ImportError:
        cc.write_png(path, arr)
    print('CUE vfx wrote', os.path.relpath(path, HERE))


def sprite_halo_strip(w=64, h=256):
    """A beam texture for a halo round the whole cue: v runs across the beam; bright in the middle
    (hidden inside the cue) falling off softly to both edges, so a camera-facing beam wider than
    the cue shows as a glow round its outline."""
    v = (np.arange(h) + 0.5) / h * 2 - 1
    a = np.exp(-(v / 0.42) ** 2) * 0.85 + np.clip(1 - np.abs(v), 0, 1) ** 2 * 0.15
    a = np.repeat(a[:, None], w, 1)
    return _rgba(np.clip(a, 0, 1))


def sprite_wisp_strip(w=1024, h=256, seed=13, lanes=9):
    """A scrolling energy beam texture: long flowing strands along u that swell, thin and break,
    tiling seamlessly along u (for TextureSpeed), soft across v."""
    rs = np.random.RandomState(seed)
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h * 2 - 1

    def per(freq, sd, z=0.0):  # fbm periodic in u
        R = freq / (2 * math.pi)
        return cc.fbm(np.cos(2 * math.pi * u) * R, np.sin(2 * math.pi * u) * R, np.full_like(u, z), 3, sd)
    a = np.zeros((h, w))
    for k in range(lanes):
        vk = rs.uniform(-0.6, 0.6)
        off = 0.35 * (per(3, seed + 3 * k) - 0.5)
        thick = 0.025 + 0.06 * per(5, seed + 3 * k + 1, 2.0)
        inten = np.clip((per(4, seed + 3 * k + 2, 4.0) - 0.38) * 3.0, 0, 1)
        a += np.exp(-((v[:, None] - vk - off[None]) / thick[None]) ** 2) * inten[None] * rs.uniform(0.6, 1.0)
    across = np.clip(1 - np.abs(v), 0, 1)[:, None] ** 0.7
    a = np.clip(a * across, 0, 1)
    core = np.clip(a - 0.6, 0, 1) * 1.5
    return _rgba(a, core=core)


# --- sprites for the Rare auras (all drawn by script: deterministic, no cost) -----------------

def sprite_strip(w=256, h=64, core_w=0.07, glow_w=0.3, glow=0.45, seed=0, flicker=0.0):
    """A glowing line along u: a hot core and a soft glow across v (neon tubes, lightning).
    flicker > 0 breaks the core's brightness along u (periodic)."""
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    U, Vv = np.meshgrid(u, v)
    a = np.exp(-((Vv - 0.5) / core_w) ** 2) + glow * np.exp(-((Vv - 0.5) / glow_w) ** 2)
    if flicker:
        ang = U * 2 * math.pi
        f = cc.fbm(np.cos(ang) * 3, np.sin(ang) * 3, np.zeros_like(U), 3, seed)
        a = a * (1 - flicker + flicker * 1.6 * f)
    core = np.exp(-((Vv - 0.5) / (core_w * 0.6)) ** 2)
    return _rgba(np.clip(a, 0, 1), core=core * 0.6)


def fire_frame(i, n, frames=16, seed=21):
    """One frame of a flame licking upward: a teardrop with a rounded base whose upper part is
    torn into tongues by rising noise; white-yellow at the core, orange, red at the ragged tips.
    Tall and hot early, shorter and redder as it dies (a OneShot flipbook). Colour baked."""
    k = i / (frames - 1)
    x, y = _grid(n)
    v = (0.92 - y) / 1.84  # 0 at the base, 1 at the top of the frame
    t = k * 2.2
    rise = cc.fbm(x * 2.5 + 3, (y + t * 1.6) * 2.5, np.full_like(x, t * 0.5), 3, seed) - 0.5
    xs = x + rise * 0.7 * np.clip(v, 0, 1) ** 1.1
    h = 0.98 - 0.3 * k
    rb = 0.2
    base = np.sqrt(np.clip(rb ** 2 - (rb - v) ** 2, 0, None)) / rb * 0.42
    body = 0.42 * np.clip(1 - (v - rb) / (h - rb), 0, 1) ** 1.25
    w = np.where(v < rb, base, body) * (1.0 - 0.2 * k)
    d = (w - np.abs(xs)) / 0.05
    shape = np.clip(d, 0, 1) * (v > -0.02)
    tongues = cc.fbm(xs * 3.5 + 7, (y + t * 2.4) * 3.2, np.full_like(x, t), 3, seed + 5)
    cut = np.clip((tongues - 0.12 - 0.5 * np.clip(v - 0.35, 0, 1)) * 2.2, 0, 1)
    blend = np.clip((v - 0.12) / 0.4, 0, 1) ** 1.5
    dens = shape * (1 - blend + blend * cut)
    core = np.clip(1 - np.abs(xs) / np.maximum(w * 0.55, 1e-3), 0, 1) * np.clip(1 - v / (h * 0.75), 0, 1) * (1 - 0.6 * k)
    col = np.stack([np.full_like(x, 255.0),
                    np.clip(90 + 150 * core + 40 * (1 - v) - 60 * k, 30, 255),
                    np.clip(20 + 190 * core ** 1.6 - 40 * k, 0, 255)], -1)
    a = np.clip(dens * (1.0 - 0.35 * k) * (0.85 + 0.15 * core), 0, 1)
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_fire_sheet():
    return flipbook(lambda i, n: fire_frame(i, n), 4, 1024)


def sprite_snowflake(n=128):
    """A six-armed snowflake with side branches and a soft glow."""
    x, y = _grid(n)
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    a = np.zeros_like(x)
    for arm in range(6):
        ang = arm * math.pi / 3
        ca, sa = math.cos(ang), math.sin(ang)
        along = x * ca + y * sa
        across = -x * sa + y * ca
        seg = np.where((along > 0) & (along < 0.85), np.abs(across), np.hypot(np.minimum(along, 0) + np.maximum(along - 0.85, 0), across))
        a = np.maximum(a, np.exp(-(seg / 0.045) ** 2))
        for at, ln in ((0.45, 0.28), (0.65, 0.2)):
            for sgn in (1, -1):
                bx, by = at * ca, at * sa
                ba = ang + sgn * math.pi / 4
                cb, sb = math.cos(ba), math.sin(ba)
                px, py = x - bx, y - by
                al = px * cb + py * sb
                ac = -px * sb + py * cb
                d = np.where((al > 0) & (al < ln), np.abs(ac), 9)
                a = np.maximum(a, np.exp(-(d / 0.035) ** 2))
    a = np.maximum(a, np.exp(-(r / 0.12) ** 2))
    a = np.clip(a + 0.25 * np.clip(1 - r, 0, 1) ** 3, 0, 1)
    return _rgba(a, (225, 240, 255), core=a * 0.5)


def sprite_bubble(n=128):
    """A soap bubble: a thin bright rim, a faint body, a highlight and a small second glint."""
    x, y = _grid(n)
    r = np.hypot(x, y)
    rim = np.exp(-((r - 0.86) / 0.06) ** 2)
    body = np.clip(1 - r / 0.9, 0, 1) * 0.1 + np.clip((r - 0.55) / 0.35, 0, 1) * 0.25 * (r < 0.92)
    hi = np.exp(-(((x + 0.35) / 0.18) ** 2 + ((y + 0.38) / 0.12) ** 2))
    hi2 = np.exp(-(((x - 0.4) / 0.07) ** 2 + ((y - 0.42) / 0.07) ** 2)) * 0.6
    a = np.clip(rim * 0.9 + body + hi + hi2, 0, 1)
    return _rgba(a, core=np.clip(hi + hi2, 0, 1))


def ghost_frame(i, n, frames=4):
    """A small friendly cartoon ghost: round head, a wavy hem that ripples frame to frame, two
    big dark eyes and a little round mouth, a soft glow round it. Colour baked (mint white)."""
    x, y = _grid(n)
    ph = i / frames * 2 * math.pi
    tilt = 0.08 * math.sin(ph)
    xr = x * math.cos(tilt) - y * math.sin(tilt)
    yr = x * math.sin(tilt) + y * math.cos(tilt)
    head = np.hypot(xr, (yr + 0.15) * 1.02) < 0.5
    hem = 0.58 + 0.09 * np.sin(xr * 10 + ph * 2)
    body = (np.abs(xr) < 0.5 - 0.06 * np.clip(yr, 0, 1)) & (yr > -0.15) & (yr < hem)
    shape = (head | body).astype(np.float64)
    # soften the edge and add a halo
    from_edge = shape
    glow = np.clip(1 - np.hypot(x, y + 0.05) / 0.95, 0, 1) ** 2 * 0.35
    col = np.zeros(x.shape + (3,)) + np.array([232.0, 255, 250])
    shade = np.clip(0.9 + 0.1 * (-yr), 0.8, 1.0)
    col = col * shade[..., None]
    eyes = ((((xr - 0.17) / 0.075) ** 2 + ((yr + 0.2) / 0.11) ** 2) < 1) | ((((xr + 0.17) / 0.075) ** 2 + ((yr + 0.2) / 0.11) ** 2) < 1)
    mouth = (((xr / 0.06) ** 2 + ((yr - 0.02) / 0.05) ** 2) < 1)
    dark = (eyes | mouth) & (shape > 0)
    col[dark] = np.array([40.0, 70, 82])
    glint = ((((xr - 0.14) / 0.025) ** 2 + ((yr + 0.24) / 0.03) ** 2) < 1) | ((((xr + 0.2) / 0.025) ** 2 + ((yr + 0.24) / 0.03) ** 2) < 1)
    col[glint] = 255
    a = np.clip(shape * 0.92 + glow * (1 - shape), 0, 1)
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_ghost_sheet():
    return flipbook(lambda i, n: ghost_frame(i, n), 2, 512, pad=4)


def leaf_frame(i, n, frames=4, light=(168, 224, 107), dark=(46, 140, 64)):
    """A leaf tumbling: the almond blade squashes across as it turns (the back side darker), with
    a pale midrib and veins. Colour baked."""
    x, y = _grid(n)
    ang = i / frames * 2 * math.pi
    sq = math.cos(ang)
    back = sq < 0
    k = max(abs(sq), 0.12)
    # the leaf lies along the diagonal
    a_ = x * 0.707 + y * 0.707
    b_ = (-x * 0.707 + y * 0.707) / k
    v = (a_ + 0.85) / 1.7
    half = 0.36 * np.sin(math.pi * np.clip(v, 0, 1)) ** 0.8
    blade = (np.abs(b_) < half) & (v > 0) & (v < 1)
    stem = (np.abs(b_) < 0.025 / k) & (v > -0.12) & (v <= 0.02)
    mid = np.exp(-(b_ * k / 0.02) ** 2)
    veins = np.exp(-(((np.abs(b_) * k) - (v - 0.1) * 0.5 + np.round(v * 6) / 6 * 0.0) % 0.14 / 0.02) ** 2) * 0
    t = np.clip(0.3 + 0.7 * v, 0, 1)
    col = np.array(dark, np.float64) + (np.array(light, np.float64) - np.array(dark, np.float64)) * t[..., None] * (0.6 if back else 1.0)
    col = col * (0.75 if back else 1.0)
    col = col + (255 - col) * (mid * 0.35)[..., None]
    shape = (blade | stem).astype(np.float64)
    return np.concatenate([col, shape[..., None] * 255], -1)


def sprite_leaf_sheet():
    return flipbook(lambda i, n: leaf_frame(i, n), 2, 256, pad=4)


def sprite_blossom(n=128):
    """A small white five-petal flower with a golden centre."""
    x, y = _grid(n)
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    edge_r = 0.42 + 0.48 * np.abs(np.cos(2.5 * th)) ** 0.7
    petal = r < edge_r
    centre = r < 0.2
    col = np.zeros(x.shape + (3,)) + np.array([255.0, 255, 250])
    col = col * (0.88 + 0.12 * np.clip(r, 0, 1))[..., None]
    col[centre] = np.array([255.0, 205, 60])
    a = np.clip((edge_r - r) / 0.04, 0, 1)
    return np.concatenate([col, a[..., None] * 255], -1)


def petal_frame(i, n, frames=4, base=(255, 156, 199), tip=(255, 222, 236)):
    """A cherry-blossom petal tumbling: a rounded petal with a notch at its outer end, pink
    deepening to the base; it squashes across as it turns. Colour baked."""
    x, y = _grid(n)
    ang = i / frames * 2 * math.pi
    k = max(abs(math.cos(ang)), 0.15)
    a_ = x * 0.8 + y * 0.6
    b_ = (-x * 0.6 + y * 0.8) / k
    v = (a_ + 0.8) / 1.55
    half = 0.42 * np.sin(math.pi * np.clip(v, 0, 1) ** 0.75) ** 0.7
    notch = (v > 0.86) & (np.abs(b_) < (v - 0.86) * 1.3)
    shape = ((np.abs(b_) < half) & (v > 0) & (v < 1) & ~notch).astype(np.float64)
    t = np.clip(v, 0, 1)
    col = np.array(base, np.float64) + (np.array(tip, np.float64) - np.array(base, np.float64)) * t[..., None]
    if math.cos(ang) < 0:
        col = col * 0.88
    return np.concatenate([col, shape[..., None] * 255], -1)


def sprite_petal_sheet():
    return flipbook(lambda i, n: petal_frame(i, n), 2, 256, pad=4)


SPRINKLE_COLOURS = [(255, 90, 160), (255, 220, 60), (80, 170, 255), (110, 220, 120), (255, 140, 50),
                    (170, 110, 255), (255, 255, 255), (255, 70, 70)]


def sprinkle_frame(i, n):
    """One rainbow sprinkle (a rounded capsule) in its own colour and angle: pick a random frame
    per particle with FlipbookStartRandom and a framerate of 0."""
    x, y = _grid(n)
    ang = (i * 67.0) % 180 * math.pi / 180
    ca, sa = math.cos(ang), math.sin(ang)
    al = x * ca + y * sa
    ac = -x * sa + y * ca
    d = np.hypot(np.clip(np.abs(al) - 0.42, 0, None), ac)
    shape = np.clip((0.2 - d) / 0.03, 0, 1)
    col = np.zeros(x.shape + (3,)) + np.array(SPRINKLE_COLOURS[i % len(SPRINKLE_COLOURS)], np.float64)
    hi = np.exp(-((ac + 0.07) / 0.05) ** 2) * (np.abs(al) < 0.4)
    col = col + (255 - col) * (hi * 0.55)[..., None]
    return np.concatenate([col, shape[..., None] * 255], -1)


def sprite_sprinkle_sheet():
    return flipbook(lambda i, n: sprinkle_frame(i, n), 4, 512, pad=4)



def sprite_stripe_strip(w=256, h=64, red=(224, 32, 46), white=(250, 248, 244)):
    """A candy-stripe ribbon: red and white bands slanting across, periodic along u, with soft
    long edges. Colour baked (the Trail's colour stays white)."""
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    U, Vv = np.meshgrid(u, v)
    f = np.mod(U * 2 + Vv * 0.6, 1.0)
    band = np.clip((np.abs(f - 0.5) - 0.23) / 0.03, 0, 1)
    col = np.array(red, np.float64) * (1 - band[..., None]) + np.array(white, np.float64) * band[..., None]
    shade = 0.8 + 0.2 * np.sin(math.pi * Vv)
    col = col * shade[..., None]
    a = np.clip(np.minimum(Vv, 1 - Vv) / 0.12, 0, 1)
    return np.concatenate([col, a[..., None] * 255], -1)


SHARED_SPRITES = {
    'halo_strip.png': sprite_halo_strip,
    'wisp_strip.png': sprite_wisp_strip,
    'glow_soft.png': sprite_glow_soft,
    'glow_core.png': sprite_glow_core,
    'star4.png': sprite_star4,
    'sparkles_main.png': sprite_sparkles_main,
    'ring.png': sprite_ring,
    'trail_soft.png': sprite_trail_soft,
    'spark.png': sprite_spark,
    'streak.png': sprite_streak,
    'smoke_4x4.png': sprite_smoke_sheet,
    'neon_strip.png': lambda: sprite_strip(256, 64, 0.08, 0.3, 0.5),
    'bolt_strip.png': lambda: sprite_strip(256, 64, 0.05, 0.22, 0.4, seed=5, flicker=0.5),
    'fire_4x4.png': lambda: sprite_fire_sheet(),
}

# A skin's own sprites: SKIN_SPRITES[id] = {file name: function}; filled in below per skin.
SKIN_SPRITES = {}


def sprite_drop(n=128, body=(255, 215, 110), deep=(240, 150, 30)):
    """A glossy falling drop (honey, goo, lava): a round bulb below with a short tail above and a
    white highlight; upright (use FacingCameraWorldUp)."""
    x, y = _grid(n)
    yb = y - 0.28
    bulb = np.hypot(x / 0.5, yb / 0.5)
    tail_w = np.clip((0.28 - y) / 1.1, 0, 1) ** 0.9 * 0.5
    tail = (np.abs(x) < tail_w * 0.9) & (y < 0.28) & (y > -0.85)
    inside = (bulb < 1) | tail
    edge = np.clip((1 - bulb) * 8, 0, 1)
    a = np.where(tail, np.clip((tail_w * 0.9 - np.abs(x)) * 40, 0, 1), edge)
    a = np.clip(np.maximum(a, edge) * inside, 0, 1)
    shade = np.clip(0.5 + 0.5 * (x * -0.6 + yb * -0.4), 0, 1)
    col = np.array(deep, np.float64) + (np.array(body, np.float64) - np.array(deep, np.float64)) * shade[..., None]
    hl = np.exp(-(((x + 0.18) / 0.1) ** 2 + ((yb + 0.12) / 0.14) ** 2))
    col = col + (255 - col) * hl[..., None]
    halo = np.clip(1 - np.hypot(x, yb * 0.8) / 0.95, 0, 1) ** 2 * 0.35
    alpha = np.maximum(a, halo)
    return np.concatenate([col, alpha[..., None] * 255], -1)


SKIN_SPRITES['honeycomb'] = {'honey_drop.png': sprite_drop}


def sprite_swirl(n=512, arms=3, twist=2.6, seed=3, hole=0.16):
    """A glowing spiral vortex (a galaxy / black-hole swirl), white on transparent (tint it with
    Color): arms wind into a dark centre; meant to spin with RotSpeed."""
    x, y = _grid(n)
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    lr = np.log(np.maximum(r, 1e-3))
    phase = th * arms / (2 * math.pi) + lr * twist
    arm = 0.5 + 0.5 * np.cos(2 * math.pi * phase)
    streak = cc.fbm(np.cos(th) * 3 + lr * 4, np.sin(th) * 3 + lr * 4, r * 3, 4, seed)
    a = arm ** 2.2 * (0.55 + 0.9 * streak)
    fade_out = np.clip((1 - r) / 0.45, 0, 1) ** 1.4
    fade_in = np.clip((r - hole) / 0.12, 0, 1)
    ring = np.exp(-((r - hole - 0.04) / 0.035) ** 2) * 0.9
    a = np.clip(a * fade_out * fade_in + ring * fade_out, 0, 1)
    core = np.clip(1 - np.abs(r - hole - 0.06) / 0.12, 0, 1) * 0.6
    return _rgba(a, core=core)


def sprite_accretion(n=512, seed=5):
    """A thin blazing ring with streaky brightness round it (an accretion disc seen face on)."""
    x, y = _grid(n)
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    ring = np.exp(-((r - 0.62) / 0.07) ** 2) + 0.35 * np.exp(-((r - 0.62) / 0.2) ** 2)
    streak = cc.fbm(np.cos(th) * 4, np.sin(th) * 4, r * 6, 4, seed)
    a = np.clip(ring * (0.45 + 0.9 * streak), 0, 1) * np.clip((1 - r) / 0.2, 0, 1)
    return _rgba(a, core=np.exp(-((r - 0.62) / 0.03) ** 2) * 0.8)


def sprite_trail_smoke(w=512, h=128, seed=9):
    """A trail strip of wispy smoke: bright along the middle, torn and streaky toward the edges;
    u runs along the trail (Stretch), so the wisps stretch out behind the ball."""
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h * 2 - 1
    U, Vv = np.meshgrid(u, v)
    n1 = cc.fbm(U * 6, Vv * 2.5, np.zeros_like(U), 4, seed)
    n2 = cc.fbm(U * 14 + 3, Vv * 5, np.ones_like(U), 3, seed + 1)
    wid = 0.55 + 0.35 * n1
    a = np.clip(1 - np.abs(Vv + (n1 - 0.5) * 0.5) / wid, 0, 1) ** 1.3 * (0.5 + 0.8 * n2)
    return _rgba(np.clip(a, 0, 1))


def sprite_shard(n=128, seed=11, rim=(185, 138, 240)):
    """A jagged dark rock shard with a thin glowing rim (debris pulled into a black hole)."""
    rs = np.random.RandomState(seed)
    x, y = _grid(n)
    th = np.arctan2(y, x)
    r = np.hypot(x, y)
    k = 7
    radii = 0.45 + 0.4 * rs.random_sample(k)
    angs = np.sort(rs.random_sample(k) * 2 * math.pi)
    # the polygon's radius at each angle (linear between its corners)
    ang_ext = np.concatenate([angs - 2 * math.pi, angs, angs + 2 * math.pi])
    rad_ext = np.concatenate([radii, radii, radii])
    edge = np.interp(np.mod(th, 2 * math.pi), ang_ext, rad_ext)
    inside = np.clip((edge - r) * 30, 0, 1)
    rimm = np.clip(1 - np.abs(edge - r) * 14, 0, 1) * 0.9
    col = np.zeros(x.shape + (3,)) + 14
    col = col + (np.array(rim, np.float64) - col) * rimm[..., None]
    a = np.clip(inside + rimm * 0.8, 0, 1)
    return np.concatenate([col, a[..., None] * 255], -1)


SKIN_SPRITES['void'] = {'shard.png': sprite_shard, 'swirl.png': lambda: sprite_swirl(512, 3, 1.7, 3, 0.16), 'accretion.png': sprite_accretion,
                        'trail_smoke.png': sprite_trail_smoke}


SKIN_SPRITES['frostbite'] = {'snowflake.png': sprite_snowflake}
SKIN_SPRITES['tidal'] = {'bubble.png': sprite_bubble}
SKIN_SPRITES['phantom'] = {'ghost_2x2.png': sprite_ghost_sheet}
SKIN_SPRITES['nature'] = {'leaf_2x2.png': sprite_leaf_sheet, 'blossom.png': sprite_blossom}
SKIN_SPRITES['sakura'] = {'petal_2x2.png': sprite_petal_sheet}
SKIN_SPRITES['candy'] = {'sprinkles_4x4.png': sprite_sprinkle_sheet, 'stripe_strip.png': sprite_stripe_strip}


# --- sprites for the Epic auras and moving materials (drawn by script) ----------------------

def _uv(w, h):
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    return np.meshgrid(u, v)


def _per(U, V, fu, fv, seed, octaves=3, z=0.0):
    """fbm that tiles along u (u on a circle), fu cycles round, fv per unit v."""
    R = fu / (2 * math.pi)
    return cc.fbm(np.cos(2 * math.pi * U) * R, np.sin(2 * math.pi * U) * R + V * fv, np.full_like(U, z), octaves, seed)


def _dots(w, h, pts, radius_px, soft=1.0):
    """A field of round dots (u tiles): pts is [(u, v, radius scale, brightness)]."""
    U, V = _uv(w, h)
    a = np.zeros((h, w))
    for (pu, pv, rs, br) in pts:
        du = (np.mod(U - pu + 0.5, 1) - 0.5) * w
        dv = (V - pv) * h
        r = np.hypot(du, dv) / (radius_px * rs)
        a = np.maximum(a, np.clip(1 - r, 0, 1) ** soft * br)
    return a


def _overlay_fade(V, lo=0.12, hi=0.88):
    """Across an overlay beam as wide as the cue: fade out at the silhouette so nothing shows past
    the cue's outline."""
    return np.clip((V - lo * 0.4) / (lo * 0.6), 0, 1) * np.clip(((1 - V) - (1 - hi) * 0.4) / ((1 - hi) * 0.6), 0, 1)


def sprite_star5(n=128, inner=0.4, gold=(255, 200, 60), core=(255, 250, 220)):
    """A little gold five-point star with a soft glow and a white-hot centre (colour baked)."""
    x, y = _grid(n)
    r = np.hypot(x, y)
    th = np.arctan2(x, -y)
    k = np.mod(th / (2 * math.pi / 5), 1)
    tri = np.abs(k - 0.5) * 2  # 1 at a point, 0 between
    R = 0.8 * (inner + (1 - inner) * tri ** 3)  # concave sides: sharp points
    star = np.clip((R - r) / 0.04, 0, 1)
    glow = np.clip(1 - r, 0, 1) ** 2.5 * 0.45
    shade = np.clip(1 - r / 0.8, 0, 1)
    col = np.array(gold, np.float64) + (np.array(core, np.float64) - np.array(gold, np.float64)) * (shade ** 1.5)[..., None]
    a = np.clip(star + glow * (1 - star), 0, 1)
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_starfield_strip(w=1024, h=128, seed=31, count=90):
    """Drifting stars for an overlay beam: pin-point white and gold stars (a few with a small
    four-point flare) inside the cue's outline, tiling along u. Colour baked."""
    rs = np.random.RandomState(seed)
    U, V = _uv(w, h)
    a = np.zeros((h, w))
    gold = np.zeros((h, w))
    for i in range(count):
        pu, pv = rs.random_sample(), 0.2 + 0.6 * rs.random_sample()
        big = rs.random_sample() < 0.15
        rad = (2.6 if big else 1.2 + rs.random_sample()) 
        du = (np.mod(U - pu + 0.5, 1) - 0.5) * w
        dv = (V - pv) * h
        rr = np.hypot(du, dv)
        d = np.exp(-(rr / rad) ** 2)
        if big:
            d = d + 0.7 * np.exp(-(du / 9) ** 2 - (dv / 0.8) ** 2) + 0.7 * np.exp(-(dv / 9) ** 2 - (du / 0.8) ** 2)
        d = d * (0.5 + 0.5 * rs.random_sample())
        a = np.maximum(a, d)
        if rs.random_sample() < 0.4:
            gold = np.maximum(gold, d)
    a = np.clip(a, 0, 1) * _overlay_fade(V)
    col = np.zeros((h, w, 3)) + np.array([235.0, 240, 255])
    col = col + (np.array([255.0, 214, 106]) - col) * np.clip(gold * 1.5, 0, 1)[..., None]
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_lava_flow_strip(w=1024, h=128, seed=41):
    """Molten heat moving through the rock, for an overlay beam: soft hot patches and a few
    bright wandering veins, tiling along u, orange to yellow (colour baked)."""
    U, V = _uv(w, h)
    blob = _per(U, V, 6, 3, seed, 4)
    vein = 1 - np.abs(2 * _per(U, V, 10, 5, seed + 1, 4) - 1)
    a = np.clip((blob - 0.5) * 2.2, 0, 1) * 0.6 + np.clip((vein - 0.9) * 10, 0, 1) * np.clip((blob - 0.35) * 3, 0, 1)
    a = np.clip(a, 0, 1) * _overlay_fade(V, 0.15, 0.85)
    hot = np.clip(a * 1.5 - 0.4, 0, 1)
    col = np.stack([np.full_like(a, 255.0), 90 + 150 * hot, 10 + 80 * hot ** 2], -1)
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_trail_lava(w=512, h=128, seed=43):
    """A molten ribbon for a ball trail: a hot yellow core, cracked crust breaking up toward the
    edges, tiling along u; colour baked (the Trail's Color multiplies it)."""
    U, V = _uv(w, h)
    across = 1 - np.abs(V * 2 - 1)
    vein = 1 - np.abs(2 * _per(U, V, 12, 4, seed, 4) - 1)
    crust = np.clip((vein - 0.75) * 4, 0, 1)
    a = np.clip(across * 1.6 - 0.1, 0, 1) ** 1.2 * (0.55 + 0.45 * crust)
    core = np.clip(across * 2 - 1.2, 0, 1)
    col = np.stack([np.full_like(a, 255.0), np.clip(110 + 140 * core + 60 * crust, 0, 255), np.clip(20 + 160 * core ** 2, 0, 255)], -1)
    return np.concatenate([col, np.clip(a, 0, 1)[..., None] * 255], -1)


def sprite_bubble_strip(w=512, h=128, seed=51, count=46):
    """Bubbles rising through goo, for an overlay beam: small ring bubbles with a glint, tiling
    along u (white; tint with Color)."""
    rs = np.random.RandomState(seed)
    U, V = _uv(w, h)
    a = np.zeros((h, w))
    for i in range(count):
        pu, pv = rs.random_sample(), 0.22 + 0.56 * rs.random_sample()
        rad = 2.5 + 7 * rs.random_sample() ** 2
        du = (np.mod(U - pu + 0.5, 1) - 0.5) * w
        dv = (V - pv) * h
        rr = np.hypot(du, dv) / rad
        ring = np.exp(-((rr - 0.85) / 0.18) ** 2) + np.clip(1 - rr, 0, 1) * 0.15
        glint = np.exp(-(((du + rad * 0.35) / (rad * 0.2)) ** 2 + ((dv + rad * 0.35) / (rad * 0.2)) ** 2))
        a = np.maximum(a, np.clip(ring + glint, 0, 1))
    a = a * _overlay_fade(V)
    return _rgba(a)


def bubble_pop_frame(i, n, frames=16):
    """A green bubble that swells, wobbles, then pops into a spray ring (OneShot flipbook): frames
    0-12 the bubble, 13-15 the pop. White; tint with Color."""
    x, y = _grid(n)
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    if i < 13:
        k = i / 12
        rad = 0.55 + 0.25 * k
        wob = 1 + 0.04 * np.sin(th * 3 + i * 0.9)
        rr = r / (rad * wob)
        rim = np.exp(-((rr - 0.9) / 0.1) ** 2)
        body = np.clip(1 - rr, 0, 1) * 0.22
        glint = np.exp(-(((x + 0.28 * rad * 1.3) / 0.12) ** 2 + ((y + 0.3 * rad * 1.3) / 0.09) ** 2))
        a = np.clip(rim * 0.95 + body + glint, 0, 1) * (rr < 1.15)
        return _rgba(a, core=np.clip(glint, 0, 1))
    k = (i - 12) / 3
    ring_r = 0.8 + 0.2 * k
    spikes = np.clip(np.cos(th * 10) * 0.5 + 0.5, 0, 1) ** 3
    a = np.exp(-((r - ring_r) / (0.05 + 0.05 * k)) ** 2) * (0.4 + 0.6 * spikes) * (1 - 0.6 * k)
    drops = 0
    for j in range(8):
        ang = j * math.pi / 4 + 0.2
        cx, cy = math.cos(ang) * (ring_r + 0.1 * k), math.sin(ang) * (ring_r + 0.1 * k)
        drops = drops + np.exp(-(((x - cx) ** 2 + (y - cy) ** 2) / (0.05 ** 2)))
    a = np.clip(a + drops * (1 - 0.5 * k), 0, 1)
    return _rgba(a)


def sprite_bubble_pop_sheet():
    return flipbook(lambda i, n: bubble_pop_frame(i, n), 4, 1024)


def sprite_trail_goo(w=512, h=128, seed=53):
    """A dripping goo ribbon for a ball trail: a thick glossy band whose edges bulge into blobs
    and drips, a lighter core; white-green, tint with Color. Tiles along u."""
    U, V = _uv(w, h)
    edge = 0.62 + 0.22 * (_per(U, V * 0, 9, 0, seed, 3) - 0.5) * 2
    drip = np.clip((_per(U, V * 0, 20, 0, seed + 1, 2) - 0.62) * 5, 0, 1)
    half = np.abs(V * 2 - 1)
    lim = edge + drip * 0.35
    a = np.clip((lim - half) / 0.06, 0, 1)
    core = np.clip(1 - half / 0.35, 0, 1)
    a = np.clip(a * (0.7 + 0.3 * core), 0, 1)
    return _rgba(a, core=core * 0.5)


def sprite_mist_strip(w=1024, h=128, seed=61):
    """Red mist drifting inside the lacquer, for an overlay beam: soft clouds with thin curling
    filaments, tiling along u (white; tint with Color)."""
    U, V = _uv(w, h)
    w0 = _per(U, V, 4, 2, seed, 3)
    cloud = _per(U + (w0 - 0.5) * 0.08, V, 7, 4, seed + 1, 5)
    fil = 1 - np.abs(2 * _per(U + (w0 - 0.5) * 0.1, V, 9, 5, seed + 2, 4) - 1)
    a = np.clip((cloud - 0.45) * 2.2, 0, 1) * 0.7 + np.clip((fil - 0.86) * 7, 0, 1) * 0.8
    a = np.clip(a, 0, 1) * _overlay_fade(V)
    return _rgba(a, core=np.clip((fil - 0.9) * 8, 0, 1) * 0.4)


def sprite_moon(n=256, seed=63, red=(200, 30, 40), bright=(255, 110, 100)):
    """A red full moon with darker maria, craters, a bright limb and a soft red glow (colour baked)."""
    x, y = _grid(n)
    r = np.hypot(x, y)
    R = 0.62
    disc = np.clip((R - r) / 0.012, 0, 1)
    maria = cc.fbm(x * 2.5, y * 2.5, np.zeros_like(x), 4, seed)
    crat = cc.fbm(x * 9, y * 9, np.ones_like(x), 3, seed + 1)
    shade = np.clip(0.7 - (maria - 0.45) * 1.2 - np.clip(crat - 0.6, 0, 1) * 1.2, 0.2, 1)
    col = np.array(red, np.float64) + (np.array(bright, np.float64) - np.array(red, np.float64)) * shade[..., None]
    limb = np.clip((r / R - 0.8) / 0.2, 0, 1) * (r < R)
    col = col + (255 - col) * (limb * 0.3)[..., None]
    glow = np.clip(1 - (r - R) / (1 - R), 0, 1) ** 2 * (r >= R) * 0.6
    a = np.clip(disc + glow, 0, 1)
    col = np.where((r >= R)[..., None], np.array(red, np.float64) + 30, col)
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_rainbow_strip(w=1024, h=128, seed=71, count=14):
    """Rainbow light streaks travelling through crystal, for an overlay beam: short slanted
    spectral bars (red to violet across each bar) at random places, tiling along u (colour baked)."""
    rs = np.random.RandomState(seed)
    U, V = _uv(w, h)
    a = np.zeros((h, w))
    hue = np.zeros((h, w))
    for i in range(count):
        pu, pv = rs.random_sample(), 0.3 + 0.4 * rs.random_sample()
        L = 0.25 + 0.35 * rs.random_sample()  # of the beam's width, along v
        wd = 18 + 30 * rs.random_sample()  # px across
        slant = 0.6 + 0.8 * rs.random_sample()
        du = (np.mod(U - pu + 0.5, 1) - 0.5) * w - (V - pv) * h * slant
        dv = (V - pv) / L
        inside = np.clip(1 - np.abs(dv) * 2, 0, 1) ** 0.6 * np.clip(1 - np.abs(du) / wd, 0, 1)
        hh = np.clip(du / (2 * wd) + 0.5, 0, 1)
        take = inside > a
        hue = np.where(take, hh, hue)
        a = np.maximum(a, inside * (0.6 + 0.4 * rs.random_sample()))
    a = a * _overlay_fade(V)
    col = np.stack([0.5 + 0.5 * np.cos(2 * math.pi * (hue * 0.8 + k / 3)) for k in range(3)], -1) * 255
    col = col * 0.8 + 50
    return np.concatenate([np.clip(col, 0, 255), a[..., None] * 255], -1)


def sprite_crystal(n=128):
    """A small faceted crystal shard: a long diamond cut into lit and dark facets, a white edge and
    a faint rainbow fringe (colour baked, pale ice)."""
    x, y = _grid(n)
    ax, ay = np.abs(x) / 0.42, np.abs(y) / 0.9
    k = ax + ay
    shape = np.clip((1 - k) / 0.04, 0, 1)
    facet = np.where(x > 0, np.where(y > 0, 1.0, 0.7), np.where(y > 0, 0.5, 0.85))
    mid = np.exp(-(x / 0.02) ** 2) * 0.4
    col = np.zeros(x.shape + (3,)) + np.array([205.0, 232, 255]) * facet[..., None]
    col = col + (255 - col) * np.clip(mid + np.exp(-((1 - k) / 0.08) ** 2) * 0.7, 0, 1)[..., None]
    fringe = np.exp(-((k - 1.05) / 0.06) ** 2)
    hue = np.mod(np.arctan2(y, x) / (2 * math.pi) + 0.5, 1)
    rb = np.stack([0.5 + 0.5 * np.cos(2 * math.pi * (hue + q / 3)) for q in range(3)], -1) * 255
    col = np.where((k > 1)[..., None], rb, col)
    a = np.clip(shape + fringe * 0.5, 0, 1)
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_trail_spectrum(w=256, h=64):
    """A rainbow ribbon: the spectrum across its width, soft edges (colour baked)."""
    U, V = _uv(w, h)
    col = np.stack([0.5 + 0.5 * np.cos(2 * math.pi * (V * 0.85 + q / 3)) for q in range(3)], -1) * 255
    col = col * 0.75 + 64
    a = np.clip(1 - np.abs(V * 2 - 1), 0, 1) ** 0.8
    return np.concatenate([np.clip(col, 0, 255), a[..., None] * 255], -1)


def _aurora_colour(t):
    """0..1 -> green, teal, blue, violet."""
    keys = np.array([[43, 240, 176], [40, 220, 220], [61, 184, 255], [122, 92, 255]], np.float64)
    t = np.clip(t, 0, 1) * (len(keys) - 1)
    i = np.minimum(np.floor(t).astype(int), len(keys) - 2)
    f = (t - i)[..., None]
    return keys[i] * (1 - f) + keys[i + 1] * f


def sprite_aurora_strip(w=1024, h=128, seed=81):
    """Aurora ribbons flowing inside the cue, for an overlay beam: wavy bands winding along u with
    fine curtain streaks, green to violet (colour baked), tiling along u."""
    U, V = _uv(w, h)
    w0 = _per(U, V, 3, 1, seed, 3)
    ph = V * 1.5 + (w0 - 0.5) * 2.2 + U * 2
    band = np.exp(-((np.mod(ph, 1) - 0.5) / 0.14) ** 2)
    streak = 1 - np.abs(2 * _per(U, V, 90, 0.5, seed + 1, 2) - 1)
    a = band * (0.45 + 0.55 * streak ** 2) * np.clip(_per(U, V, 4, 1, seed + 2, 2) * 1.6 - 0.2, 0, 1)
    a = np.clip(a, 0, 1) * _overlay_fade(V)
    col = _aurora_colour(_per(U, V, 2, 0.5, seed + 3, 2) * 1.6 - 0.3)
    col = col + (255 - col) * np.clip(a - 0.6, 0, 1)[..., None]
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_curtain_strip(w=512, h=128, seed=83):
    """An aurora curtain for a curved beam: fine vertical rays (across v) bright at one long edge
    and fading to the other, rippling along u; white, tint with Color. Tiles along u."""
    U, V = _uv(w, h)
    rays = 1 - np.abs(2 * _per(U, V * 0, 70, 0, seed, 2) - 1)
    rays = 0.35 + 0.65 * rays ** 3
    body = np.clip(1 - V, 0, 1) ** 1.6 * np.clip(V / 0.08, 0, 1)
    edge = np.exp(-((V - 0.1) / 0.05) ** 2)
    a = np.clip(body * rays + edge * 0.6, 0, 1) * (0.6 + 0.4 * _per(U, V * 0, 5, 0, seed + 1, 2))
    return _rgba(a, core=edge * 0.5)


def sprite_trail_aurora(w=512, h=128, seed=85):
    """An aurora ribbon trail: bands of green, teal and violet across its width with fine
    streaks along it, soft edges; colour baked. Tiles along u."""
    U, V = _uv(w, h)
    streak = 1 - np.abs(2 * _per(U, V, 40, 6, seed, 3) - 1)
    a = np.clip(1 - np.abs(V * 2 - 1), 0, 1) ** 0.7 * (0.55 + 0.45 * streak ** 2)
    col = _aurora_colour(V + (_per(U, V, 4, 1, seed + 1, 2) - 0.5) * 0.4)
    col = col + (255 - col) * (np.clip(streak - 0.85, 0, 1) * 3)[..., None]
    return np.concatenate([np.clip(col, 0, 255), a[..., None] * 255], -1)


DISCO_COLOURS = [(255, 61, 154), (61, 224, 255), (255, 225, 61), (90, 110, 255), (255, 255, 255)]


def sprite_spots_strip(w=1024, h=128, seed=91, count=26):
    """Coloured spotlight specks sweeping over mirror tiles, for an overlay beam: soft round spots
    of pink, cyan, yellow and blue with a hot centre, tiling along u (colour baked)."""
    rs = np.random.RandomState(seed)
    U, V = _uv(w, h)
    a = np.zeros((h, w))
    col = np.zeros((h, w, 3))
    for i in range(count):
        pu, pv = rs.random_sample(), 0.25 + 0.5 * rs.random_sample()
        rad = 8 + 12 * rs.random_sample()
        du = (np.mod(U - pu + 0.5, 1) - 0.5) * w
        dv = (V - pv) * h
        d = np.exp(-(np.hypot(du, dv) / rad) ** 2)
        c = np.array(DISCO_COLOURS[i % 4], np.float64)
        take = d > a
        col = np.where(take[..., None], c + (255 - c) * (d ** 3 * 0.6)[..., None], col)
        a = np.maximum(a, d)
    a = a * _overlay_fade(V)
    return np.concatenate([col, a[..., None] * 255], -1)


def confetti_frame(i, n):
    """One confetti piece (a small rectangle or square, a colour and a tilt per frame): random
    frame per particle with FlipbookStartRandom and framerate 0."""
    x, y = _grid(n)
    ang = (i * 53.0) % 180 * math.pi / 180
    ca, sa = math.cos(ang), math.sin(ang)
    al = x * ca + y * sa
    ac = -x * sa + y * ca
    L = 0.7 if i % 3 else 0.45
    shape = np.clip((L - np.abs(al)) / 0.05, 0, 1) * np.clip((0.35 - np.abs(ac)) / 0.05, 0, 1)
    c = np.array(DISCO_COLOURS[i % len(DISCO_COLOURS)], np.float64)
    shade = 0.8 + 0.2 * np.sign(ac)
    col = np.zeros(x.shape + (3,)) + c * shade[..., None]
    return np.concatenate([np.clip(col, 0, 255), shape[..., None] * 255], -1)


def sprite_confetti_sheet():
    return flipbook(lambda i, n: confetti_frame(i, n), 4, 512, pad=4)


def _glyph_img(key, px_w, px_h):
    """A 3x5 pixel glyph (CuePaint.GLYPHS) as a px_w x px_h mask with a 1-pixel gap."""
    rows = HACK_GLYPHS[key]
    m = np.zeros((px_h, px_w))
    cw, ch = px_w / 4.0, px_h / 6.0
    for r in range(5):
        for c in range(3):
            if rows[r][c] == '1':
                y0, y1 = int(round((r + 0.5) * ch)), int(round((r + 1.5) * ch))
                x0, x1 = int(round((c + 0.5) * cw)), int(round((c + 1.5) * cw))
                m[y0:y1 - 1, x0:x1 - 1] = 1
    return m


HACK_GLYPHS = {
    '0': ['111', '101', '101', '101', '111'], '1': ['010', '110', '010', '010', '111'],
    'a': ['111', '100', '111', '001', '111'], 'b': ['101', '111', '101', '111', '101'],
    'c': ['110', '001', '011', '100', '011'], 'd': ['111', '010', '111', '010', '111'],
    'e': ['100', '111', '101', '111', '001'],
}


def digit_frame(i, n):
    """A green pixel glyph (mostly 0 and 1) with a soft glow: pick a random frame per particle
    (FlipbookStartRandom); a framerate > 0 makes it flicker between glyphs as it falls."""
    keys = ['0', '1', '0', '1', '1', '0', 'a', '1', '0', 'b', '1', '0', 'c', '1', 'd', 'e']
    g = _glyph_img(keys[i], n, n)
    # a soft glow round the pixels (a small box blur)
    glow = g.copy()
    for _ in range(3):
        glow = (glow + np.roll(glow, 3, 0) + np.roll(glow, -3, 0) + np.roll(glow, 3, 1) + np.roll(glow, -3, 1)) / 5
    a = np.clip(g + glow * 0.8, 0, 1)
    col = np.zeros((n, n, 3)) + np.array([43.0, 255, 90])
    col = col + (255 - col) * (g * 0.35)[..., None]
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_digits_sheet():
    return flipbook(lambda i, n: digit_frame(i, n), 4, 512, pad=6)


def sprite_code_strip(w=1024, h=128, seed=101):
    """Green code scrolling along the cue, for an overlay beam: rows of pixel glyphs along u, runs
    of them brighter (a data pulse), tiling along u (colour baked)."""
    rs = np.random.RandomState(seed)
    gw, gh = 16, 22
    cols, rows = w // gw, 4
    a = np.zeros((h, w))
    keys = ['0', '1', '0', '1', 'a', 'b', 'c', 'd', 'e']
    y0 = (h - rows * gh) // 2
    for r in range(rows):
        run = rs.random_sample(cols) < 0.7
        for c in range(cols):
            if not run[c] or rs.random_sample() < 0.2:
                continue
            key = keys[rs.randint(0, 4) if rs.random_sample() < 0.85 else rs.randint(4, len(keys))]
            g = _glyph_img(key, gw, gh) * (0.4 + 0.6 * rs.random_sample())
            a[y0 + r * gh:y0 + (r + 1) * gh, c * gw:(c + 1) * gw] = g
    U, V = _uv(w, h)
    pulse = np.clip(np.cos(2 * math.pi * (U * 3)) * 0.5 + 0.5, 0, 1) ** 4
    a = np.clip(a * (0.55 + 0.6 * pulse), 0, 1) * _overlay_fade(V)
    col = np.zeros((h, w, 3)) + np.array([43.0, 255, 90])
    col = col + (255 - col) * (pulse * 0.4)[..., None]
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_glitch(w=128, h=64, seed=103):
    """A glitch: a few offset horizontal bars and scanlines, green-white (colour baked)."""
    rs = np.random.RandomState(seed)
    a = np.zeros((h, w))
    for _ in range(6):
        y0 = rs.randint(0, h - 6)
        hh = rs.randint(2, 7)
        x0 = rs.randint(0, w // 3)
        x1 = rs.randint(w // 2, w)
        a[y0:y0 + hh, x0:x1] = 0.5 + 0.5 * rs.random_sample()
    scan = (np.arange(h) % 3 == 0)[:, None] * 0.25
    a = np.clip(a - scan, 0, 1)
    col = np.zeros((h, w, 3)) + np.array([120.0, 255, 150])
    return np.concatenate([col, a[..., None] * 255], -1)


def sprite_trail_data(w=512, h=64, seed=105):
    """A pixel data trail: a band of square pixel blocks, full near the ball and breaking up along
    the trail (the texture runs Stretch: u = 0 at the ball), green (colour baked)."""
    rs = np.random.RandomState(seed)
    cell = 8
    cols, rows = w // cell, h // cell
    a = np.zeros((h, w))
    for c in range(cols):
        keep = 1 - c / cols
        for r in range(rows):
            centre = 1 - abs((r + 0.5) / rows * 2 - 1)
            if rs.random_sample() < keep * (0.4 + 0.7 * centre):
                a[r * cell + 1:(r + 1) * cell - 1, c * cell + 1:(c + 1) * cell - 1] = 0.5 + 0.5 * rs.random_sample()
    col = np.zeros((h, w, 3)) + np.array([43.0, 255, 90])
    col = col + (255 - col) * (a > 0.9)[..., None] * 0.5
    return np.concatenate([col, a[..., None] * 255], -1)


SKIN_SPRITES['shooting_star'] = {'starfield_strip.png': sprite_starfield_strip, 'star5.png': sprite_star5}
SKIN_SPRITES['magma'] = {'lava_flow_strip.png': sprite_lava_flow_strip, 'trail_lava.png': sprite_trail_lava,
                         'lava_drip.png': lambda: sprite_drop(128, (255, 205, 80), (230, 70, 10))}
SKIN_SPRITES['toxic'] = {'bubble_strip.png': sprite_bubble_strip, 'bubble_pop_4x4.png': sprite_bubble_pop_sheet,
                         'trail_goo.png': sprite_trail_goo, 'goo_drop.png': lambda: sprite_drop(128, (200, 255, 90), (70, 190, 20))}
SKIN_SPRITES['blood_moon'] = {'mist_strip.png': sprite_mist_strip, 'moon.png': sprite_moon}
SKIN_SPRITES['prism'] = {'rainbow_strip.png': sprite_rainbow_strip, 'crystal.png': sprite_crystal,
                         'trail_spectrum.png': sprite_trail_spectrum}
SKIN_SPRITES['aurora'] = {'aurora_strip.png': sprite_aurora_strip, 'curtain_strip.png': sprite_curtain_strip,
                          'trail_aurora.png': sprite_trail_aurora}
SKIN_SPRITES['disco'] = {'spots_strip.png': sprite_spots_strip, 'confetti_4x4.png': sprite_confetti_sheet}
SKIN_SPRITES['hacked'] = {'code_strip.png': sprite_code_strip, 'digits_4x4.png': sprite_digits_sheet,
                          'glitch.png': sprite_glitch, 'trail_data.png': sprite_trail_data}


def make_sprites(which=None):
    if which is None:
        for name, fn in SHARED_SPRITES.items():
            save_rgba(os.path.join(SHARED, name), fn())
        return
    for name, fn in SKIN_SPRITES.get(which, {}).items():
        save_rgba(os.path.join(VFX, which, name), fn())


def main():
    args = sys.argv[1:]
    if args and args[0] == 'sprites':
        make_sprites(args[1] if len(args) > 1 else None)
    else:
        print(__doc__)


if __name__ == '__main__':
    main()
