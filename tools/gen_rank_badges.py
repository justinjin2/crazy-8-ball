#!/usr/bin/env python3
"""Generate the rank badges (docs/GDD.md section 11, docs/UI_STYLE.md sections 6 and 7).

Drawn in the icon style of tools/gen_ui_art.py (thick ink outline, drop lip, gradients, gloss)
and rendered the same way. Each tier is its own badge after the designer's reference sheet: a
faceted frame round a big 8 ball, with the tier's own ornaments (tall side plates for Bronze,
Silver and Gold; crystal feathers for Platinum; crystal shards for Diamond; fins for Expert; a
laurel for Veteran; a crystal burst for Master; swept black and gold wings for Grandmaster;
rainbow crystals and blades for Reyes). On top of that, the same rules everywhere:
- the 8 ball and its ring are the same size in the same place on every badge;
- a crown from Expert up, bigger each tier (Reyes has the biggest);
- pips in an arc under the ball: 1 to 5 stars from Bronze to Diamond, 1 to 5 gems from Expert
  to Grandmaster (1 pip = division I, 5 = V).
Grandmaster is black and gold. Reyes is a rainbow badge, one badge with no pips. Unranked is a plain grey
badge. No words in any image.

Outputs under assets/ui/ranks/ (see README.md there):
  <tier>_<1..5>.png, reyes.png, unranked.png  512 px badges, plus the .svg source of each
  shine/<name>.png                            white silhouette of the badge's colours, which
                                              the shine sweep is clipped to
  sparkle.png                                 a white four-point twinkle, 128 px
  preview.html                                every badge with its animation (open in Chrome)

Run: python3 tools/gen_rank_badges.py [--sheet path.png]   (--sheet also writes a contact sheet)
"""
import base64
import math
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

import gen_ui_art as ui

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui", "ranks")
SIZE = 512  # output px; everything is drawn on a 256-unit canvas
INK = ui.INK
EDGE = 3.5  # the thin ink lines between parts (the outer outline is ink_filter's)

CX, CY = 128, 138  # the ball's centre, the same on every badge (low, to leave room for crowns)
RING = 58  # the metal ring's outer radius
BALL = 46
PIP_ARC = 74  # pips sit on this radius around the ball...
PIP_STEP = 30  # ...this many degrees apart (so they never overlap), centred under the ball
PIP_SIZE = 18.5  # a star's radius; the pips sit in one curved tray this much wider,
PIP_TRAY = 4.5  # so the count reads even when the badge is small
CROWN_BASE = 80  # the crown's bottom edge, on the ring's top
LIGHT = (-0.55, -0.83)  # towards the light, for the facets: the top left
OUTLINE = 6  # the outer ink outline, a little thinner than the icons' (badges have finer parts)
LIP = 5

GOLD = ("#FFF3A6", "#FFC928", "#C97F00")
# Grandmaster's rainbow: the house rainbow of UI_STYLE section 4, in order round the frame
RAINBOW = ("#FF4D4D", "#FF9F1C", "#FFE14D", "#3DD66B", "#3B9BFF", "#A259FF")
PRISM = ("#FFF4FF", "#B98CFF", "#3A2380")  # stands in for a rainbow tier's light, mid and dark
BLACK = ("#8C8CA2", "#3C3C4C", "#14141C")  # a black-and-gold tier's black: frame and wings
RUBY = ("#FF8A8A", "#E0203A", "#7A0A1E")  # the gem on a gold crown

# name, metal (light, mid, dark), pip kind, crown level (0 = none), frame. Lowest tier first.
TIERS = [
    ("bronze", ("#FFD6AE", "#D8864A", "#8A461C"), "star", 0, "hex"),
    ("silver", ("#FFFFFF", "#C3CCD9", "#77849A"), "star", 0, "hex"),
    ("gold", GOLD, "star", 0, "hex"),
    ("platinum", ("#F2FBFF", "#A6D6F2", "#5588B8"), "star", 0, "hex"),
    ("diamond", ("#C2FDFF", "#27D0E6", "#08789E"), "star", 0, "hex"),
    ("expert", ("#FFB0A8", "#F2413F", "#9A1226"), "gem", 1, "round"),
    ("veteran", ("#C8F7A8", "#4FC93A", "#1A7A28"), "gem", 2, "crest"),
    ("master", ("#DEC4FF", "#9B55F5", "#4C18A8"), "gem", 3, "crest"),
    ("grandmaster", BLACK, "gem", 4, "crest"),
]
REYES = ("reyes", PRISM, None, 5, "round")
UNRANKED = ("unranked", ("#EEF1F6", "#B4BDCB", "#7D889B"), None, 0, "hex")


# ---------------------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------------------


def hex_rgb(h):
    return tuple(int(h[i : i + 2], 16) for i in (1, 3, 5))


def mix(a, b, t):
    ra, rb = hex_rgb(a), hex_rgb(b)
    return "#" + "".join(f"{round(x + (y - x) * t):02X}" for x, y in zip(ra, rb))


def pt(p):
    return f"{p[0]:.1f} {p[1]:.1f}"


def along(p, ang, dist, side=0.0):
    """The point `dist` along direction `ang` (degrees, y down) from p, `side` to its left."""
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    return (p[0] + ux * dist + uy * side, p[1] + uy * dist - ux * side)


def rpoly(points, r):
    """A closed polygon path with every corner rounded by about r."""
    n = len(points)
    d = []
    for i in range(n):
        p0, p1, p2 = points[i - 1], points[i], points[(i + 1) % n]

        def toward(a, b):
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy)
            t = min(r, length / 2) / length
            return (a[0] + dx * t, a[1] + dy * t)

        a, b = toward(p1, p0), toward(p1, p2)
        d.append(("L" if i else "M") + f"{pt(a)} Q{pt(p1)} {pt(b)}")
    return " ".join(d) + " Z"


def scaled(points, k, c=(CX, CY)):
    return [(c[0] + (x - c[0]) * k, c[1] + (y - c[1]) * k) for x, y in points]


def path(d, fill, stroke=True, extra=""):
    s = f' stroke="{INK}" stroke-width="{EDGE}" stroke-linejoin="round"' if stroke else ""
    return f'<path d="{d}" fill="{fill}"{s} {extra}/>'


def poly(points, fill, stroke=True, extra=""):
    return path("M" + " L".join(pt(p) for p in points) + " Z", fill, stroke, extra)


def mirrored(body):
    """The body plus its mirror image across the badge's centre line."""
    return body + f'<g transform="matrix(-1 0 0 1 256 0)">{body}</g>'


# ---------------------------------------------------------------------------------------
# Parts
# ---------------------------------------------------------------------------------------


def linear(gid, stops, x2=0.35, y2=1):
    """A linear gradient from (light) top left to (dark) bottom right. stops: (offset, colour)."""
    body = "".join(f'<stop offset="{o:.2f}" stop-color="{c}"/>' for o, c in stops)
    return f'<linearGradient id="{gid}" x1="0" y1="0" x2="{x2}" y2="{y2}">{body}</linearGradient>'


def rainbow(gid, towards="#FFFFFF", amount=0.0):
    """A diagonal rainbow, optionally mixed towards white (lighter) or a dark (deeper)."""
    n = len(RAINBOW) - 1
    return linear(gid, [(i / n, mix(c, towards, amount)) for i, c in enumerate(RAINBOW)], 1, 1)


def gradients(metal):
    light, mid, dark = metal
    glight, gmid, gdark = GOLD
    if metal == PRISM:  # a rainbow tier: the metal's face, rim, wings and crown are rainbows
        tier = rainbow("m") + rainbow("r", PRISM[2], 0.3) + rainbow("w", PRISM[2], 0.1) + rainbow("c", "#FFFFFF", 0.3)
        for k in range(FEATHER_HUES):  # one gradient per feather colour, red to purple
            hue = feather_hue(k)
            tier += linear(f"h{k}", [(0, mix(hue, "#FFFFFF", 0.45)), (0.5, hue), (1, mix(hue, PRISM[2], 0.35))])
    else:
        tier = (
            # metal face: light top-left to dark bottom-right
            linear("m", [(0, light), (0.5, mid), (1, dark)])
            # metal rim: turned the other way, so a rim round a face reads as a bevel
            + linear("r", [(0, mix(mid, dark, 0.45)), (0.6, mid), (1, mix(light, mid, 0.4))])
            # wings: a little deeper than the face, so they read against it
            + linear("w", [(0, mix(light, mid, 0.35)), (0.55, mid), (1, dark)])
            # crowns: brighter than the metal they sit on
            + linear("c", [(0, mix(light, "#FFFFFF", 0.4)), (0.55, mix(light, mid, 0.55)), (1, mid)], 0.3)
        )
    return (
        "<defs>"
        + tier
        # stars: brighter still
        + linear("s", [(0, "#FFFFFF"), (0.5, mix(light, "#FFFFFF", 0.4)), (1, mix(light, mid, 0.3))], 0.2)
        # gold, for Reyes' trim and crown
        + linear("g", [(0, glight), (0.5, gmid), (1, gdark)])
        + linear("gr", [(0, mix(gmid, gdark, 0.45)), (0.6, gmid), (1, mix(glight, gmid, 0.4))])
        # the 8 ball
        + '<radialGradient id="ball" cx="0.38" cy="0.32" r="0.78"><stop offset="0" stop-color="#5C6275"/>'
        '<stop offset="0.4" stop-color="#23262F"/><stop offset="1" stop-color="#06070B"/></radialGradient>'
        "</defs>"
    )


def gloss(cx, cy, rx, ry, angle=-30, opacity=0.75):
    return ui.gloss(cx, cy, rx, ry, angle, opacity)


def blade(p, ang, length, width, bend=0.0, fill="url(#w)", shade="#000000", rib=None):
    """A pointed, slightly bulging blade or feather from p. bend curls the tip to its left."""
    tip = along(p, ang, length, bend)
    b1, b2 = along(p, ang, 0, width * 0.3), along(p, ang, 0, -width * 0.3)
    c1 = along(p, ang, length * 0.5, width * 0.75 + bend * 0.5)
    c2 = along(p, ang, length * 0.5, -width * 0.75 + bend * 0.5)
    outline = f"M{pt(b1)} Q{pt(c1)} {pt(tip)} Q{pt(c2)} {pt(b2)} Z"
    half = f"M{pt(p)} L{pt(b2)} Q{pt(c2)} {pt(tip)} Z"
    out = path(outline, fill) + path(half, shade, False, 'opacity="0.22"')
    if rib:
        a, b = along(p, ang, length * 0.12, bend * 0.02), along(p, ang, length * 0.72, bend * 0.55)
        out += ui.line([a, b], rib, 2.6, 'opacity="0.7"')
    return out + path(outline, "none")


def shard(p, ang, length, width, fill="url(#w)", light="#FFFFFF"):
    """A crystal: a long six-sided gem with a lit half and a shaded half."""
    tip = along(p, ang, length)
    s1, s2 = along(p, ang, length * 0.7, width / 2), along(p, ang, length * 0.7, -width / 2)
    b1, b2 = along(p, ang, 0, width * 0.3), along(p, ang, 0, -width * 0.3)
    outline = [b1, s1, tip, s2, b2]
    return (
        poly(outline, fill)
        + poly([p, b2, s2, tip], "#000000", False, 'opacity="0.25"')
        + poly([p, b1, s1, tip], light, False, 'opacity="0.18"')
        + ui.line([along(p, ang, length * 0.08), along(p, ang, length * 0.9)], light, 2.2, 'opacity="0.6"')
        + poly(outline, "none")
    )


def star(c, r, fill="url(#s)"):
    pts = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        rr = r if i % 2 == 0 else r * 0.47
        pts.append((c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr))
    return (
        path(rpoly(pts, 1.6), fill)
        + gloss(c[0] - r * 0.22, c[1] - r * 0.3, r * 0.32, r * 0.18, -25, 0.85)
    )


def gem(c, h, light, mid, dark, width=0.72, facets=None):
    """A faceted diamond (rhombus) gem, taller than wide, lit from the top left. facets
    overrides the four facets' colours (top left, top right, bottom left, bottom right)."""
    w = h * width
    top, right, bottom, left = (c[0], c[1] - h), (c[0] + w, c[1]), (c[0], c[1] + h), (c[0] - w, c[1])
    mid_pt = (c[0], c[1] - h * 0.18)
    tl, tr, bl, br = facets or (mix(light, "#FFFFFF", 0.35), light, mid, dark)
    return (
        poly([left, top, mid_pt], tl, False)
        + poly([top, right, mid_pt], tr, False)
        + poly([left, mid_pt, bottom], bl, False)
        + poly([mid_pt, right, bottom], br, False)
        + poly([top, right, bottom, left], "none")
        + f'<path d="M{pt(left)} L{pt(mid_pt)} L{pt(right)} M{pt(mid_pt)} L{pt(bottom)}" fill="none" '
        f'stroke="{INK}" stroke-width="1.4" opacity="0.45"/>'
        + gloss(c[0] - w * 0.3, c[1] - h * 0.45, w * 0.22, h * 0.14, -40, 0.9)
    )


def inset_poly(points, d):
    """The polygon moved d units inwards on every side (points clockwise on screen)."""
    n = len(points)
    lines = []
    for i in range(n):
        a, b = points[i], points[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        lines.append(((a[0] - dy / length * d, a[1] + dx / length * d), (dx, dy)))
    out = []
    for i in range(n):
        (p1, d1), (p2, d2) = lines[i - 1], lines[i]
        cross = d1[0] * d2[1] - d1[1] * d2[0]
        t = ((p2[0] - p1[0]) * d2[1] - (p2[1] - p1[1]) * d2[0]) / cross
        out.append((p1[0] + d1[0] * t, p1[1] + d1[1] * t))
    return out


FEATHER_HUES = 7


def feather_hue(k):
    """The k-th of FEATHER_HUES colours from red to purple."""
    return rainbow_at(k / (FEATHER_HUES - 1) * (len(RAINBOW) - 1) / len(RAINBOW))


def rainbow_at(turn):
    """The rainbow's colour a fraction `turn` of the way round (0 and 1 both red)."""
    x = (turn % 1) * len(RAINBOW)
    i = int(x) % len(RAINBOW)  # a turn a hair below 0 wraps to exactly 1.0
    return mix(RAINBOW[i], RAINBOW[(i + 1) % len(RAINBOW)], x - int(x))


def facet_colour(metal, a, b):
    """A flat facet's colour from which way edge a->b faces: lit from the top left. On a
    rainbow tier the hue also runs round the frame, red at the top."""
    light, mid, dark = metal
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = (dy * LIGHT[0] - dx * LIGHT[1]) / math.hypot(dx, dy)
    if metal == PRISM:
        mx, my = (a[0] + b[0]) / 2 - CX, (a[1] + b[1]) / 2 - CY
        mid = rainbow_at((math.degrees(math.atan2(my, mx)) + 90) / 360)
        light, dark = mix(mid, "#FFFFFF", 0.55), mix(mid, dark, 0.3)
    return mix(mid, light, t * 0.9) if t >= 0 else mix(mid, dark, -t * 0.85)


def faceted(points, metal, bevel, face="url(#m)"):
    """A bevelled plate like the reference's frames: one flat facet per edge round a face."""
    inner = inset_poly(points, bevel)
    out = []
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        colour = facet_colour(metal, points[i], points[j])
        out.append(poly([points[i], points[j], inner[j], inner[i]], colour, False, f'stroke="{colour}" stroke-width="0.8"'))
    out.append(poly(inner, face, False))
    out.append(poly(inner, "none", False, f'stroke="{INK}" stroke-width="1.6" stroke-opacity="0.45" stroke-linejoin="round"'))
    out.append(poly(points, "none"))
    return "".join(out)


def round_frame():
    pts = [along((CX, CY), a, 70) for a in range(120, 421, 20)]
    return pts + [(CX, CY + 90)]


FRAMES = {
    # pointed top and bottom, like Bronze to Diamond in the reference
    "hex": [(128, 42), (198, 84), (198, 180), (128, 228), (58, 180), (58, 84)],
    # a flat top for a crown to sit on
    "crest": [(96, 72), (160, 72), (198, 98), (198, 180), (128, 228), (58, 180), (58, 98)],
    # a ring with a point at the bottom, like Expert and Reyes
    "round": round_frame(),
}


def frame(kind, metal, face="url(#r)"):
    return faceted(FRAMES[kind], metal, 10, face) + gloss(86, 76, 16, 6, -32, 0.75)


def ring(face="url(#m)", rim="url(#r)"):
    return (
        f'<circle cx="{CX}" cy="{CY}" r="{RING}" fill="{rim}" stroke="{INK}" stroke-width="{EDGE}"/>'
        f'<circle cx="{CX}" cy="{CY}" r="{RING - 5}" fill="{face}"/>'
        f'<circle cx="{CX}" cy="{CY}" r="{BALL + 4}" fill="{INK}"/>'
        + gloss(CX - 36, CY - 36, 14, 6, -45, 0.8)
    )


def eight_ball():
    r = BALL
    spot_r = r * 0.44
    sx, sy = CX, CY - r * 0.06
    return (
        f'<circle cx="{CX}" cy="{CY}" r="{r}" fill="url(#ball)"/>'
        f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{spot_r:.1f}" fill="#FFFFFF"/>'
        f'<text x="{sx:.1f}" y="{sy + spot_r * 0.5:.1f}" font-family="Arial Black, Arial, sans-serif" '
        f'font-weight="900" font-size="{spot_r * 1.45:.1f}" text-anchor="middle" fill="{INK}">8</text>'
        + gloss(CX - r * 0.42, CY - r * 0.5, r * 0.34, r * 0.17, -35, 0.85)
        + gloss(CX + r * 0.45, CY + r * 0.5, r * 0.14, r * 0.07, -40, 0.35)
    )


def arc(radius, a0, a1):
    """An SVG arc path round the ball's centre, clockwise from angle a0 to a1 (degrees)."""
    p0, p1 = along((CX, CY), a0, radius), along((CX, CY), a1, radius)
    return f"M{pt(p0)} A{radius} {radius} 0 0 1 {pt(p1)}"


def pips(kind, count, metal):
    """The division: 1 to 5 bright stars or gems set in one curved tray under the ball. The
    tray is darker by the ball and lighter at its rim, like a groove cut into the frame, and
    each pip has a soft glow behind it and a shadow under it, so it sits in the tray."""
    light, mid, dark = metal
    angles = [90 + (i - (count - 1) / 2) * PIP_STEP for i in range(count)]
    centres = [along((CX, CY), a, PIP_ARC) for a in angles]
    half = PIP_SIZE + PIP_TRAY
    a0, a1 = angles[0], angles[-1] + 0.01  # a single pip is a round tray
    groove = arc(PIP_ARC, a0, a1)
    inner, outer = PIP_ARC - half, PIP_ARC + half
    out = [
        '<defs><radialGradient id="tray" gradientUnits="userSpaceOnUse" '
        f'cx="{CX}" cy="{CY}" r="{outer}">'
        f'<stop offset="{inner / outer:.3f}" stop-color="{mix(dark, INK, 0.8)}"/>'
        f'<stop offset="{PIP_ARC / outer:.3f}" stop-color="{mix(dark, INK, 0.6)}"/>'
        f'<stop offset="1" stop-color="{mix(dark, INK, 0.38)}"/></radialGradient>'
        '<radialGradient id="glow"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.5"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient></defs>',
        f'<path d="{groove}" fill="none" stroke="{INK}" stroke-width="{2 * half + EDGE}" stroke-linecap="round"/>',
        f'<path d="{groove}" fill="none" stroke="url(#tray)" stroke-width="{2 * half - EDGE}" stroke-linecap="round"/>',
        # a lit rim along the tray's outer edge and a shadow along its inner edge
        f'<path d="{arc(outer - EDGE - 1.2, a0, a1)}" fill="none" stroke="{light}" stroke-width="1.6" '
        'stroke-opacity="0.45" stroke-linecap="round"/>',
        f'<path d="{arc(inner + EDGE + 1.5, a0, a1)}" fill="none" stroke="#000000" stroke-width="2.4" '
        'stroke-opacity="0.35" stroke-linecap="round"/>',
    ]
    for c in centres:
        out.append(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{PIP_SIZE * 1.15:.1f}" fill="url(#glow)" '
                   f'opacity="0.8"/>')
        shadow = (c[0], c[1] + 2.4)
        if kind == "star":
            out.append(star(shadow, PIP_SIZE, fill="#000000").replace("<path", '<path opacity="0.4"', 1))
            out.append(star(c, PIP_SIZE, fill="url(#s)"))
        else:
            if metal == PRISM:  # a rainbow tier's gems are prismatic: each facet a pale rainbow tint
                facets = tuple(mix(RAINBOW[k], "#FFFFFF", 0.45) for k in (0, 2, 4, 5))
            elif metal == BLACK:  # a black tier's gems are gold
                facets = (mix(GOLD[0], "#FFFFFF", 0.4), GOLD[0], GOLD[1], mix(GOLD[1], GOLD[2], 0.5))
            else:
                facets = (mix(light, "#FFFFFF", 0.7), mix(light, "#FFFFFF", 0.5), light, mix(light, mid, 0.7))
            h = PIP_SIZE + 1.5
            out.append(poly([(shadow[0], shadow[1] - h), (shadow[0] + h * 0.84, shadow[1]), (shadow[0], shadow[1] + h),
                             (shadow[0] - h * 0.84, shadow[1])], "#000000", False, 'opacity="0.4"'))
            out.append(gem(c, h, light, light, mid, 0.84, facets))
    return "".join(out)


def crown(level, face="url(#c)", rim="url(#r)", gem_colours=None):
    """A crown on top of the frame. Level 1 (Expert) to 5 (Reyes): wider, taller, more points."""
    w = [0, 70, 78, 88, 98, 112][level]
    h = [0, 38, 44, 50, 56, 62][level]
    n = 3 if level <= 2 else 5
    band = 13 + level
    tip_r = [0, 5, 5.5, 5.5, 6, 7][level]
    x0, x1 = CX - w / 2, CX + w / 2
    top_band = CROWN_BASE - band
    tips, valleys = [], []
    for i in range(n):
        t = i / (n - 1)
        centre = 1 - abs(t - 0.5) * 2  # 1 in the middle, 0 at the ends
        tips.append((x0 - 6 + (w + 12) * t, CROWN_BASE - h * (0.68 + 0.32 * centre)))
    for i in range(n - 1):
        valleys.append(((tips[i][0] + tips[i + 1][0]) / 2, top_band - h * 0.16))
    outline = [(x0, CROWN_BASE)]
    for i in range(n):
        outline.append(tips[i])
        if i < n - 1:
            outline.append(valleys[i])
    outline.append((x1, CROWN_BASE))
    parts = [path(rpoly(outline, 2.5), face)]
    for i in range(n):  # shade the right side of each point
        right = valleys[i] if i < n - 1 else (x1 + 3, top_band)
        parts.append(poly([tips[i], (tips[i][0], top_band), right], "#000000", False, 'opacity="0.16"'))
    parts.append(path(rpoly(outline, 2.5), "none"))
    for tip in tips:
        parts.append(
            f'<circle cx="{tip[0]:.1f}" cy="{tip[1]:.1f}" r="{tip_r}" fill="{face}" stroke="{INK}" stroke-width="{EDGE}"/>'
        )
    parts.append(path(rpoly([(x0 - 4, top_band), (x1 + 4, top_band), (x1 + 1, CROWN_BASE), (x0 - 1, CROWN_BASE)], 4), rim))
    parts.append(gloss(x0 + w * 0.2, top_band - h * 0.3, 5, 13, -15, 0.75))
    if gem_colours:
        light, mid, dark = gem_colours
        parts.append(gem((CX, top_band + band * 0.2), band * 0.62 + 4, light, mid, dark))
        for side in (-1, 1):
            parts.append(
                f'<circle cx="{CX + side * w * 0.3:.1f}" cy="{top_band + band / 2:.1f}" r="{2.8 + level * 0.4:.1f}" '
                f'fill="{mix(light, "#FFFFFF", 0.3)}" stroke="{INK}" stroke-width="2"/>'
            )
    return "".join(parts)


# ---------------------------------------------------------------------------------------
# Ornaments: one design per tier, after the reference sheet. Each draws the left side
# (mirrored onto the right), behind the frame.
# ---------------------------------------------------------------------------------------


def fan(kind, pivot, specs, width, bend=0.0, **kw):
    """Blades or shards from one pivot. specs: (angle, length), drawn top first so lower overlap."""
    out = []
    for a, length in specs:
        if kind == "blade":
            out.append(blade(pivot, a, length, width, bend=bend, **kw))
        else:
            out.append(shard(pivot, a, length, width, **kw))
    return "".join(out)


def fin(p, ang, length, width, metal):
    """An angular fin: a straight top edge to the tip, a shoulder on the lower edge."""
    tip = along(p, ang, length)
    b1, b2 = along(p, ang, 0, -width * 0.45), along(p, ang, 0, width * 0.45)
    shoulder = along(p, ang, length * 0.55, width * 0.6)
    light, mid, dark = metal
    return (
        poly([b1, tip, shoulder, b2], "url(#w)")
        + poly([b1, tip, p], mix(light, mid, 0.35), False, 'opacity="0.85"')
        + poly([p, tip, shoulder, b2], dark, False, 'opacity="0.35"')
        + poly([b1, tip, shoulder, b2], "none")
    )


def dark_metal(m):
    light, mid, dark = m
    return (mix(light, mid, 0.5), mix(mid, dark, 0.35), mix(dark, "#000000", 0.2))


def orn_bronze(m):
    """One tall plate each side, leaning out, over a darker foot."""
    return faceted([(52, 180), (84, 196), (112, 228), (80, 228)], dark_metal(m), 5) + faceted(
        [(30, 92), (62, 102), (84, 204), (54, 198)], m, 6
    )


def orn_silver(m):
    """A taller plate each side with a pointed top."""
    return faceted([(48, 176), (84, 196), (112, 228), (78, 228)], dark_metal(m), 5) + faceted(
        [(24, 68), (64, 102), (84, 204), (50, 194)], m, 6
    )


def orn_gold(m):
    """A broad plate each side, flaring out like a shoulder."""
    return faceted([(38, 170), (86, 198), (112, 228), (74, 228)], dark_metal(m), 5) + faceted(
        [(12, 74), (60, 90), (86, 206), (40, 186)], m, 6
    )


def orn_platinum(m):
    """Crystal feathers."""
    return fan("blade", (84, 176), ((250, 112), (232, 100), (214, 80), (196, 60)), 28, bend=-10, rib=m[0])


def orn_diamond(m):
    """Big crystal shards rising beside the frame."""
    return fan("shard", (92, 184), ((256, 136), (234, 108), (212, 78), (192, 50)), 30, light=m[0])


def orn_expert(m):
    """Red fins, stacked."""
    return "".join(
        fin((86, 168), a, length, width, m) for a, length, width in ((236, 104, 34), (212, 82, 32), (190, 64, 28), (170, 44, 22))
    )


def orn_veteran(m):
    """A laurel wreath round the frame."""
    out = []
    radius = 86
    stem = [along((CX, CY), 96 + i * 20, radius) for i in range(8)]
    stem_d = "M" + " L".join(pt(p) for p in stem)
    out.append(f'<path d="{stem_d}" fill="none" stroke="{INK}" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>')
    out.append(f'<path d="{stem_d}" fill="none" stroke="{m[2]}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>')
    for i in range(7):
        a = 100 + i * 20
        p = along((CX, CY), a, radius)
        tangent = a + 90  # pointing up the wreath
        length = 42 - i * 0.8
        out.append(blade(p, tangent + 46, length, 25, bend=-3, rib=m[2]))
        out.append(blade(p, tangent - 8, length * 0.8, 19, bend=3, rib=m[2]))
    return "".join(out)


def orn_master(m):
    """A burst of crystals."""
    return fan("shard", (92, 176), ((262, 124), (240, 116), (216, 92), (194, 70), (172, 46)), 30, light=m[0])


def orn_grandmaster(m):
    """Swept wings: long black feathers with gold veins behind, short gold ones in front, and
    gold spikes on the shoulders."""
    back = fan("blade", (88, 170), ((246, 118), (224, 96), (202, 76), (182, 62)), 30, bend=-16, rib=GOLD[0])
    front = fan("blade", (92, 172), ((240, 72), (218, 66), (196, 54)), 22, bend=-10, fill="url(#g)", rib="#FFFFFF")
    return back + front + shard((72, 104), 238, 34, 16, fill="url(#g)", light=GOLD[0])


def rainbow_fills(n):
    """n feather colours, red to purple, as gradient references."""
    return [f"url(#h{round(k * (FEATHER_HUES - 1) / (n - 1))})" for k in range(n)]


def orn_reyes(m):
    """Crystal blades with blades between them, each its own rainbow colour, red at the top."""
    shards = ((240, 112), (212, 80), (186, 66))
    blades = ((258, 96), (226, 96), (199, 74))
    order = sorted([(a, "shard") for a, _ in shards] + [(a, "blade") for a, _ in blades], reverse=True)
    fill = dict(zip(order, rainbow_fills(len(order))))
    out = [shard((86, 170), a, n, 34, fill=fill[(a, "shard")], light="#FFFFFF") for a, n in shards]
    out += [blade((88, 170), a, n, 20, bend=-6, fill=fill[(a, "blade")], rib="#FFFFFF") for a, n in blades]
    return "".join(out)


ORNAMENTS = {
    "bronze": orn_bronze,
    "silver": orn_silver,
    "gold": orn_gold,
    "platinum": orn_platinum,
    "diamond": orn_diamond,
    "expert": orn_expert,
    "veteran": orn_veteran,
    "master": orn_master,
    "grandmaster": orn_grandmaster,
    "reyes": orn_reyes,
}


# ---------------------------------------------------------------------------------------
# Badges
# ---------------------------------------------------------------------------------------


def badge_body(tier, count):
    name, metal, pip, crown_level, frame_kind = tier
    light, mid, dark = metal
    parts = []
    if name in ORNAMENTS:
        parts.append(mirrored(ORNAMENTS[name](metal)))
    if metal == BLACK:
        # a black frame with a gold trim line; the crown and ring gold
        parts.append(frame(frame_kind, metal, face="url(#m)"))
        trim = inset_poly(FRAMES[frame_kind], 10)
        parts.append(poly(trim, "none", False, 'stroke="url(#g)" stroke-width="3" stroke-linejoin="round"'))
        if crown_level:
            parts.append(crown(crown_level, face="url(#g)", rim="url(#gr)", gem_colours=RUBY))
        parts.append(ring(face="url(#g)", rim="url(#gr)"))
    else:
        parts.append(frame(frame_kind, metal))
        if crown_level:
            parts.append(crown(crown_level, gem_colours=(mix(light, "#FFFFFF", 0.4), light, mid)))
        parts.append(ring())
    parts.append(eight_ball())
    if pip:
        parts.append(pips(pip, count, metal))
    return gradients(metal), "".join(parts)


def ink_filter():
    """The outer ink outline and drop lip: like ui's, but thinner and crisper."""
    sigma = 3.2
    # blurred alpha one outline-width outside an edge, from the normal distribution's tail
    tail = 0.5 * math.erfc(OUTLINE / sigma / math.sqrt(2))
    slope = 40
    return f"""<defs><filter id="badgeInk" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB">
  <feGaussianBlur in="SourceAlpha" stdDeviation="{sigma}" result="blur"/>
  <feComponentTransfer in="blur" result="grown"><feFuncA type="linear" slope="{slope}" intercept="{0.5 - slope * tail:.3f}"/></feComponentTransfer>
  <feOffset in="grown" dy="{LIP}" result="lip"/>
  <feMerge result="both"><feMergeNode in="lip"/><feMergeNode in="grown"/></feMerge>
  <feFlood flood-color="{INK}"/>
  <feComposite in2="both" operator="in" result="outline"/>
  <feMerge><feMergeNode in="outline"/><feMergeNode in="SourceGraphic"/></feMerge>
</filter></defs>"""


def svg_badge(defs, body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 256 256">'
        f'{ui.defs()}{ink_filter()}{defs}<g filter="url(#badgeInk)">{body}</g></svg>'
    )


def svg_shine(defs, body):
    """The badge's coloured area in flat white (no ink outline), for clipping the shine."""
    white = (
        '<defs><filter id="shineMask" x="-10%" y="-10%" width="120%" height="120%">'
        '<feFlood flood-color="#FFFFFF"/><feComposite in2="SourceAlpha" operator="in"/></filter></defs>'
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 256 256">'
        f'{ui.defs()}{defs}{white}<g filter="url(#shineMask)">{body}</g></svg>'
    )


def svg_sparkle():
    d = "M64 6 C67 50 78 61 122 64 C78 67 67 78 64 122 C61 78 50 67 6 64 C50 61 61 50 64 6 Z"
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><defs>'
        '<radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.8"/>'
        '<stop offset="0.35" stop-color="#FFFFFF" stop-opacity="0.25"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>'
        f'</radialGradient></defs><circle cx="64" cy="64" r="44" fill="url(#glow)"/><path d="{d}" fill="#FFFFFF"/></svg>'
    )


def all_badges():
    """(file name, tier name, division or None, defs, body), lowest rank first."""
    out = [("unranked", "unranked", None) + badge_body(UNRANKED, 0)]
    for tier in TIERS:
        for division in range(1, 6):
            out.append((f"{tier[0]}_{division}", tier[0], division) + badge_body(tier, division))
    out.append(("reyes", "reyes", None) + badge_body(REYES, 0))
    return out


# ---------------------------------------------------------------------------------------
# Rendering (isolated SVG documents, so every badge can reuse the same gradient ids)
# ---------------------------------------------------------------------------------------


def render(jobs):
    """jobs: list of (svg_text, size, png_path). Chrome screenshots of grids, cropped."""
    columns, batch = 6, 18
    scale = ui.RENDER_SCALE
    for start in range(0, len(jobs), batch):
        chunk = jobs[start : start + batch]
        cell = max(size for _, size, _ in chunk)
        rows = math.ceil(len(chunk) / columns)
        html = ["<html><body style='margin:0;background:transparent'>"]
        for i, (text, size, _) in enumerate(chunk):
            x, y = (i % columns) * cell, (i // columns) * cell
            data = base64.b64encode(text.encode()).decode()
            html.append(
                f"<img src='data:image/svg+xml;base64,{data}' width='{size}' height='{size}' "
                f"style='position:absolute;left:{x}px;top:{y}px'>"
            )
        html.append("</body></html>")
        with tempfile.TemporaryDirectory() as tmp:
            page = os.path.join(tmp, "sheet.html")
            shot = os.path.join(tmp, "sheet.png")
            with open(page, "w") as f:
                f.write("".join(html))
            subprocess.run(
                [
                    ui.CHROME,
                    "--headless=new",
                    "--disable-gpu",
                    "--hide-scrollbars",
                    "--default-background-color=00000000",
                    f"--force-device-scale-factor={scale}",
                    f"--window-size={columns * cell},{rows * cell}",
                    f"--screenshot={shot}",
                    "file://" + page,
                ],
                check=True,
                capture_output=True,
            )
            sheet = Image.open(shot).convert("RGBA")
        for i, (_, size, png) in enumerate(chunk):
            x, y = (i % columns) * cell * scale, (i // columns) * cell * scale
            crop = sheet.crop((x, y, x + size * scale, y + size * scale))
            crop.resize((size, size), Image.LANCZOS).save(png, optimize=True)


def contact_sheet(badges, path_out):
    """Every badge on a pale panel with its name, for reviewing (not a game asset)."""
    cell, pad = 180, 24
    rows = [["unranked", "reyes"]] + [[f"{t[0]}_{d}" for d in range(1, 6)] for t in TIERS]
    width = pad + 5 * cell
    height = pad + len(rows) * (cell + 18)
    sheet = Image.new("RGBA", (width, height), (234, 241, 251, 255))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf", 15)
    except OSError:
        font = ImageFont.load_default()
    for r, row in enumerate(rows):
        for c, name in enumerate(row):
            img = Image.open(os.path.join(ROOT, name + ".png")).resize((cell - 12, cell - 12), Image.LANCZOS)
            x, y = pad // 2 + c * cell, pad // 2 + r * (cell + 18)
            sheet.alpha_composite(img, (x + 6, y))
            label = name.replace("_", " ")
            tw = draw.textlength(label, font=font)
            draw.text((x + (cell - tw) / 2, y + cell - 10), label, fill=(27, 32, 51, 255), font=font)
    sheet.convert("RGB").save(path_out)


PREVIEW = """<!doctype html>
<html><head><meta charset="utf-8"><title>Rank badges</title>
<style>
  body { margin: 0; padding: 24px; background: #EAF1FB; color: #1B2033;
         font: 15px/1.4 "Arial Rounded MT Bold", system-ui, sans-serif; }
  h1 { margin: 0 0 4px; font-size: 22px; }
  p { margin: 0 0 18px; max-width: 70ch; }
  .row { display: flex; flex-wrap: wrap; gap: 8px; align-items: flex-end; margin-bottom: 14px; }
  .row h2 { width: 100%; margin: 6px 0 0; font-size: 15px; text-transform: uppercase; opacity: .7; }
  figure { margin: 0; text-align: center; }
  canvas { width: 150px; height: 150px; display: block; }
  figcaption { font-size: 12px; opacity: .65; }
  label { display: inline-block; margin-bottom: 14px; }
</style></head><body>
<h1>Rank badges</h1>
<p>Made by tools/gen_rank_badges.py. The shine is drawn the way the game will do it: a soft white
band swept across the badge's shine mask, sparkles from Expert up, and turning gold rays behind
Reyes. Timings are starting values (README.md).</p>
<label><input type="checkbox" id="dark"> dark background</label>
<p id="error" hidden><b>Some images did not load.</b> Serve this folder over http (see README.md) or open it in Chrome.</p>
<div id="grid"></div>
<script>
const FX = __FX__;
const ROWS = __ROWS__;
const load = src => new Promise(res => {
  const i = new Image(); i.onload = () => res(i);
  i.onerror = () => { document.getElementById("error").hidden = false; res(null); }; i.src = src;
});
const badges = [];
(async () => {
  const sparkle = await load("sparkle.png");
  const rays = await load("../art/rays.png");
  const grid = document.getElementById("grid");
  for (const row of ROWS) {
    const div = document.createElement("div");
    div.className = "row";
    div.innerHTML = `<h2>${row.title}</h2>`;
    grid.appendChild(div);
    for (const name of row.names) {
      const fig = document.createElement("figure");
      const canvas = document.createElement("canvas");
      const dpr = window.devicePixelRatio || 1;
      canvas.width = canvas.height = 150 * dpr;
      fig.appendChild(canvas);
      fig.insertAdjacentHTML("beforeend", `<figcaption>${name.replace("_", " ")}</figcaption>`);
      div.appendChild(fig);
      const [img, mask] = await Promise.all([load(name + ".png"), load("shine/" + name + ".png")]);
      const off = document.createElement("canvas");
      off.width = off.height = canvas.width;
      badges.push({ canvas, img, mask, off, fx: FX[row.fx], seed: badges.length * 0.37 });
    }
  }
  requestAnimationFrame(frame);
  function frame(ms) {
    const t = ms / 1000;
    for (const b of badges) draw(b, t);
    requestAnimationFrame(frame);
  }
  function draw(b, t) {
    const c = b.canvas.getContext("2d"), s = b.canvas.width, fx = b.fx;
    c.clearRect(0, 0, s, s);
    if (!b.img) return;
    if (fx && fx.rays && rays) {
      c.save(); c.translate(s / 2, s * 0.53); c.rotate(t * 2 * Math.PI / fx.rays.turn);
      c.globalAlpha = fx.rays.alpha; const r = s * 0.62;
      c.drawImage(tint(rays, fx.rays.colour, 256), -r, -r, 2 * r, 2 * r); c.restore(); c.globalAlpha = 1;
    }
    c.drawImage(b.img, 0, 0, s, s);
    if (!fx) return;
    // the sweep: a band along a tilted axis, clipped to the mask
    const phase = ((t + b.seed) % fx.period) / fx.sweep;
    if (phase < 1 && b.mask) {
      const o = b.off.getContext("2d");
      o.globalCompositeOperation = "source-over"; o.clearRect(0, 0, s, s);
      o.drawImage(b.mask, 0, 0, s, s);
      o.globalCompositeOperation = "source-in";
      const a = fx.angle * Math.PI / 180, dx = Math.cos(a) * s, dy = Math.sin(a) * s;
      const cx = s / 2 + (phase * 2 - 1) * dx, cy = s / 2 + (phase * 2 - 1) * dy;
      const g = o.createLinearGradient(cx - dx * fx.width, cy - dy * fx.width, cx + dx * fx.width, cy + dy * fx.width);
      g.addColorStop(0, "rgba(255,255,255,0)");
      g.addColorStop(0.5, `rgba(255,255,255,${fx.strength})`);
      g.addColorStop(1, "rgba(255,255,255,0)");
      o.fillStyle = g; o.fillRect(0, 0, s, s);
      c.drawImage(b.off, 0, 0);
    }
    // sparkles: each twinkles in turn at one of the badge's bright spots
    for (let i = 0; sparkle && i < fx.sparkles; i++) {
      const cycle = (t + b.seed + i * fx.twinkle / fx.sparkles) / fx.twinkle;
      const k = Math.floor(cycle), p = cycle - k;
      if (p > 0.5) continue;
      const spot = fx.spots[(k * 3 + i * 5) % fx.spots.length];
      const size = Math.sin(p * 2 * Math.PI) * s * fx.sparkleSize;
      c.save(); c.translate(spot[0] / 256 * s, spot[1] / 256 * s); c.rotate(p * 1.5);
      c.drawImage(sparkle, -size / 2, -size / 2, size, size); c.restore();
    }
  }
  const tints = new Map();
  function tint(img, colour, n) {
    if (tints.has(colour)) return tints.get(colour);
    const cv = document.createElement("canvas"); cv.width = cv.height = n;
    const x = cv.getContext("2d"); x.drawImage(img, 0, 0, n, n);
    x.globalCompositeOperation = "source-in"; x.fillStyle = colour; x.fillRect(0, 0, n, n);
    tints.set(colour, cv); return cv;
  }
})();
document.getElementById("dark").onchange = e => {
  document.body.style.background = e.target.checked ? "#1B2033" : "#EAF1FB";
  document.body.style.color = e.target.checked ? "#EAF1FB" : "#1B2033";
};
</script></body></html>
"""

# Starting values for the shine (copy into Config when the badges go in the game).
# period: seconds between sweeps; sweep: seconds a sweep takes; width: band half-width
# (fraction of the badge); strength: the band's peak opacity; angle: its travel direction.
# spots: where sparkles may appear, on the 256-unit canvas.
LOW_SPOTS = [[84, 70], [172, 70], [40, 104], [216, 104], [128, 48]]
HIGH_SPOTS = [[128, 24], [98, 42], [158, 42], [36, 90], [220, 90], [30, 150], [226, 150], [72, 96], [184, 96]]
FX = {
    "none": None,
    "low": {"period": 4.0, "sweep": 0.9, "width": 0.16, "strength": 0.55, "angle": 20, "sparkles": 0, "twinkle": 1, "spots": LOW_SPOTS, "sparkleSize": 0},
    "high": {"period": 3.0, "sweep": 0.8, "width": 0.16, "strength": 0.6, "angle": 20, "sparkles": 3, "twinkle": 1.6, "spots": HIGH_SPOTS, "sparkleSize": 0.16},
    "top": {"period": 2.2, "sweep": 0.7, "width": 0.18, "strength": 0.7, "angle": 20, "sparkles": 5, "twinkle": 1.4, "spots": HIGH_SPOTS, "sparkleSize": 0.19,
            "rays": {"turn": 14, "alpha": 0.45, "colour": "#FFC928"}},
}


def preview_html():
    import json

    rows = [{"title": "unranked", "fx": "none", "names": ["unranked"]}]
    for name, _, _, level, _ in TIERS:
        rows.append({"title": name, "fx": "high" if level else "low", "names": [f"{name}_{d}" for d in range(1, 6)]})
    rows.append({"title": "reyes", "fx": "top", "names": ["reyes"]})
    return PREVIEW.replace("__FX__", json.dumps(FX)).replace("__ROWS__", json.dumps(rows))


def main():
    if not os.path.exists(ui.CHROME):
        sys.exit("Google Chrome is needed to render the SVGs: " + ui.CHROME)
    shine_dir = os.path.join(ROOT, "shine")
    os.makedirs(shine_dir, exist_ok=True)
    badges = all_badges()
    jobs = []
    for name, _, _, defs, body in badges:
        text = svg_badge(defs, body)
        with open(os.path.join(ROOT, name + ".svg"), "w") as f:
            f.write(text)
        jobs.append((text, SIZE, os.path.join(ROOT, name + ".png")))
        jobs.append((svg_shine(defs, body), SIZE, os.path.join(shine_dir, name + ".png")))
    jobs.append((svg_sparkle(), 128, os.path.join(ROOT, "sparkle.png")))
    render(jobs)
    for name, *_ in badges:
        box = Image.open(os.path.join(ROOT, name + ".png")).getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        if box[0] < 4 or box[1] < 4 or box[2] > SIZE - 4 or box[3] > SIZE - 4:
            print(f"warning: {name} reaches the edge of the image {box}")
    with open(os.path.join(ROOT, "preview.html"), "w") as f:
        f.write(preview_html())
    if "--sheet" in sys.argv:
        contact_sheet(badges, sys.argv[sys.argv.index("--sheet") + 1])
    print(f"wrote {len(badges)} badges, their shine masks and the sparkle under {os.path.normpath(ROOT)}")


if __name__ == "__main__":
    main()
