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
        tex = spec.get('Texture', 'vfx/_shared/glow_soft.png')
        self.texture = tex if os.path.isabs(tex) else os.path.join(texture_root, tex)

    def quads(self, t, host_m, cam_m, pulse=1.0):
        R, T = host_m[:3, :3], host_m[:3, 3]
        n = self.segments
        k = np.linspace(0, 1, n + 1)
        P = (self.a0[None] * (1 - k[:, None]) + self.a1[None] * k[:, None]) @ R.T + T
        cam = cam_m[:3, 3]
        view = cam[None] - P
        view /= np.maximum(np.linalg.norm(view, axis=1, keepdims=True), 1e-6)
        P = P + view * self.zoffset
        tang = (self.a1 - self.a0) @ R.T
        tang = tang / np.linalg.norm(tang)
        if self.face:
            side = np.cross(tang[None], view)
        else:
            side = np.repeat((np.array([1.0, 0, 0]) @ R.T)[None], n + 1, 0)
        side /= np.maximum(np.linalg.norm(side, axis=1, keepdims=True), 1e-6)
        w = (self.w0 * (1 - k) + self.w1 * k) / 2
        L, Rr = P - side * w[:, None], P + side * w[:, None]
        length = np.linalg.norm(self.a1 - self.a0)
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
