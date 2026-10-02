#!/usr/bin/env python3
"""Generate the UI icons and effect images (docs/UI_STYLE.md sections 6 and 7).

Every image is drawn as an SVG from one shared style: a thick dark-ink outline with a small
drop lip underneath, a light-to-dark gradient on each colour, and a white gloss highlight.
The SVGs are rendered to transparent PNGs by headless Chrome (one screenshot of a grid,
cropped), so nothing but Pillow and the installed Chrome is needed.

Outputs:
  assets/ui/icons/<name>.svg and <name>.png   256 px glossy cartoon icons, no words
                                              (assets/ui/icons/README.md lists each one)
  assets/ui/icons/cue_*.svg and .png          the cue thumbnail layers, one canvas, tinted
                                              in Roblox (see CUE_LAYERS)
  assets/ui/art/<name>.svg and <name>.png     effect images: the panel pattern tile, the ball
                                              gloss and stripe band, the win rays
  assets/ui/art/shadow.png                    9-slice soft shadow (drawn with Pillow)

Upload the PNGs (Studio MCP upload_image, see docs/STUDIO_NOTES.md) and paste the ids into
Config.UI.Kit.Icons and Config.UI.Kit.Art.

Run: python3 tools/gen_ui_art.py                 every image (rewrites them all)
     python3 tools/gen_ui_art.py shop case_rare  only the images named
     python3 tools/gen_ui_art.py economy         a group (GROUPS): column, cases, packs,
                                                 shop_icons, cue_layers, or economy for all five;
                                                 ults for the ultimates' icons and effect art
"""
import math
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
RENDER_SCALE = 2  # drawn at twice the size, then shrunk, for smooth edges

INK = "#1B2033"
OUTLINE = 9  # ink outline width at 256 px
LIP = 6  # the outline drops this far under the shape, so icons look like thick stickers

# name: (light, mid, dark). Close to the rarity and button colours in Config.UI.Kit.
PALETTE = {
    "blue": ("#9ED3FF", "#3B9BFF", "#1F6BD0"),
    "green": ("#A8F5BE", "#3DD66B", "#1E9E47"),
    "red": ("#FFA3A3", "#FF4D4D", "#C9283A"),
    "gold": ("#FFF1A0", "#FFC928", "#DB8E00"),
    "wood": ("#FFD9A0", "#E7A35C", "#A8622A"),
    "darkwood": ("#C07A45", "#8A4B22", "#5E3014"),
    "white": ("#FFFFFF", "#F4F8FF", "#C9D6EA"),
    "grey": ("#E4E9F2", "#AEB8C8", "#7B869A"),
    "steel": ("#D8E6F7", "#9FB2CC", "#6A7D98"),
    "cloth": ("#6FE08E", "#2FA24F", "#1C7A37"),
    "sad": ("#C4D4EE", "#8EA3C7", "#5E7299"),
    "purple": ("#D7B8FF", "#A259FF", "#6E2FD0"),
}


def defs():
    grads = []
    for name, (light, mid, dark) in PALETTE.items():
        grads.append(
            f'<linearGradient id="{name}" x1="0" y1="0" x2="0.35" y2="1">'
            f'<stop offset="0" stop-color="{light}"/><stop offset="0.45" stop-color="{mid}"/>'
            f'<stop offset="1" stop-color="{dark}"/></linearGradient>'
        )
    ink_filter = ink_filter_def("ink", OUTLINE, LIP)
    shine = (
        '<radialGradient id="shine" cx="0.5" cy="0.5" r="0.5">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>'
    )
    return "<defs>" + "".join(grads) + shine + ink_filter + "</defs>"


def ink_filter_def(fid, outline, lip):
    """The ink outline: the shape's alpha grown by `outline` px and dropped `lip` px, in ink,
    under the shape."""
    sigma = outline / 1.3
    return f"""
<filter id="{fid}" x="-30%" y="-30%" width="160%" height="160%" color-interpolation-filters="sRGB">
  <feGaussianBlur in="SourceAlpha" stdDeviation="{sigma:.2f}" result="blur"/>
  <feComponentTransfer in="blur" result="grown"><feFuncA type="linear" slope="7" intercept="-0.35"/></feComponentTransfer>
  <feOffset in="grown" dy="{lip}" result="lip"/>
  <feMerge result="both"><feMergeNode in="lip"/><feMergeNode in="grown"/></feMerge>
  <feFlood flood-color="{INK}"/>
  <feComposite in2="both" operator="in" result="outline"/>
  <feMerge><feMergeNode in="outline"/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>"""


def svg(body):
    """An icon: body inside the ink group. An icon may return (under, body) or (under, body,
    over) instead: under is drawn beneath the ink group and over on top of it, neither with
    the ink outline (a glow; twinkles with a thin edge of their own)."""
    under = over = ""
    if isinstance(body, tuple):
        under, body, *rest = body
        over = rest[0] if rest else ""
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">'
        f'{defs()}{under}<g filter="url(#ink)">{body}</g>{over}</svg>'
    )


def gloss(cx, cy, rx, ry, angle=-30, opacity=0.75):
    """A soft white highlight: the shine that makes a shape look glossy."""
    return (
        f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="url(#shine)" '
        f'opacity="{opacity}" transform="rotate({angle} {cx} {cy})"/>'
    )


def line(points, colour, width, extra=""):
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in points)
    return (
        f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="{width}" '
        f'stroke-linecap="round" stroke-linejoin="round" {extra}/>'
    )


def ink_line(points, width=6):
    return line(points, INK, width)


# ---------------------------------------------------------------------------------------
# Icons
# ---------------------------------------------------------------------------------------


def icon_cue():
    # A cue lying corner to corner, butt bottom-left, with the white ball at its tip.
    bx, by, tx, ty = 40, 206, 178, 68
    ux, uy = (tx - bx), (ty - by)
    length = math.hypot(ux, uy)
    ux, uy = ux / length, uy / length
    nx, ny = -uy, ux

    def band(t0, t1, w0, w1, fill):
        ax, ay = bx + ux * length * t0, by + uy * length * t0
        cx, cy = bx + ux * length * t1, by + uy * length * t1
        pts = [
            (ax + nx * w0, ay + ny * w0),
            (cx + nx * w1, cy + ny * w1),
            (cx - nx * w1, cy - ny * w1),
            (ax - nx * w0, ay - ny * w0),
        ]
        d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
        return f'<path d="{d}" fill="{fill}"/>'

    def width(t):
        return 13 - 7 * t

    parts = [
        f'<circle cx="{bx}" cy="{by}" r="13" fill="url(#darkwood)"/>',
        band(0, 0.34, width(0), width(0.34), "url(#darkwood)"),
        band(0.34, 0.40, width(0.34), width(0.40), "#F4F8FF"),
        band(0.40, 0.93, width(0.40), width(0.93), "url(#wood)"),
        band(0.93, 0.985, width(0.93), width(0.985), "#FFFFFF"),
        band(0.985, 1.0, width(0.985), width(1.0), "#3B9BFF"),
        # a highlight running up the cue
        line(
            [
                (bx + ux * 20 + nx * 5, by + uy * 20 + ny * 5),
                (tx - ux * 30 + nx * 2.5, ty - uy * 30 + ny * 2.5),
            ],
            "#FFFFFF",
            3,
            'opacity="0.55"',
        ),
        '<circle cx="204" cy="46" r="24" fill="url(#white)"/>',
        gloss(196, 38, 11, 7),
    ]
    return "".join(parts)


def icon_hourglass():
    glass = (
        "M78 58 C78 104 116 112 116 128 C116 144 78 152 78 198 "
        "L178 198 C178 152 140 144 140 128 C140 112 178 104 178 58 Z"
    )
    return "".join(
        [
            f'<path d="{glass}" fill="#E6F4FF"/>',
            '<path d="M96 88 L160 88 C152 104 134 112 128 124 C122 112 104 104 96 88 Z" fill="url(#gold)"/>',
            '<path d="M86 196 C92 168 112 160 128 150 C144 160 164 168 170 196 Z" fill="url(#gold)"/>',
            '<rect x="124" y="126" width="8" height="30" rx="4" fill="#FFC928"/>',
            f'<path d="{glass}" fill="none" stroke="{INK}" stroke-width="6"/>',
            '<rect x="56" y="34" width="144" height="28" rx="12" fill="url(#darkwood)"/>',
            '<rect x="56" y="194" width="144" height="28" rx="12" fill="url(#darkwood)"/>',
            gloss(92, 84, 8, 22, angle=-10, opacity=0.8),
        ]
    )


def icon_stopwatch():
    return "".join(
        [
            '<rect x="110" y="26" width="36" height="22" rx="7" fill="url(#blue)"/>',
            '<rect x="120" y="44" width="16" height="16" fill="url(#steel)"/>',
            '<rect x="186" y="56" width="26" height="18" rx="6" fill="url(#blue)" transform="rotate(40 199 65)"/>',
            '<circle cx="128" cy="140" r="84" fill="url(#blue)"/>',
            '<circle cx="128" cy="140" r="64" fill="url(#white)"/>',
            ink_line([(128, 86), (128, 98)], 7),
            ink_line([(128, 182), (128, 194)], 7),
            ink_line([(74, 140), (86, 140)], 7),
            ink_line([(170, 140), (182, 140)], 7),
            line([(128, 140), (158, 104)], "#FF4D4D", 11),
            f'<circle cx="128" cy="140" r="9" fill="{INK}"/>',
            gloss(92, 92, 22, 12),
        ]
    )


def icon_whistle():
    return "".join(
        [
            '<circle cx="206" cy="92" r="20" fill="none" stroke="url(#steel)" stroke-width="10"/>',
            '<rect x="30" y="90" width="118" height="44" rx="14" fill="url(#gold)"/>',
            '<circle cx="146" cy="150" r="64" fill="url(#gold)"/>',
            f'<rect x="30" y="90" width="18" height="44" rx="8" fill="{INK}" opacity="0.85"/>',
            f'<rect x="114" y="88" width="40" height="14" rx="7" fill="{INK}"/>',
            gloss(124, 128, 26, 14),
            gloss(72, 102, 26, 7, angle=0, opacity=0.8),
        ]
    )


def icon_crown():
    body = "M48 178 L36 80 L90 128 L128 58 L166 128 L220 80 L208 178 Z"
    return "".join(
        [
            f'<path d="{body}" fill="url(#gold)" stroke="url(#gold)" stroke-width="10" stroke-linejoin="round"/>',
            '<circle cx="36" cy="78" r="14" fill="url(#gold)"/>',
            '<circle cx="128" cy="54" r="14" fill="url(#gold)"/>',
            '<circle cx="220" cy="78" r="14" fill="url(#gold)"/>',
            '<rect x="42" y="166" width="172" height="44" rx="12" fill="url(#gold)"/>',
            f'<path d="M48 166 L208 166" stroke="{INK}" stroke-width="5" opacity="0.35"/>',
            '<circle cx="128" cy="188" r="12" fill="url(#red)"/>',
            '<circle cx="84" cy="188" r="9" fill="url(#blue)"/>',
            '<circle cx="172" cy="188" r="9" fill="url(#green)"/>',
            gloss(82, 132, 12, 30, angle=-20, opacity=0.7),
        ]
    )


def person(cx, head_y, scale, fill):
    r = 34 * scale
    body = (
        f"M{cx - 64 * scale:.1f} {head_y + 128 * scale:.1f} "
        f"C{cx - 64 * scale:.1f} {head_y + 64 * scale:.1f} {cx - 36 * scale:.1f} {head_y + 44 * scale:.1f} {cx:.1f} {head_y + 44 * scale:.1f} "
        f"C{cx + 36 * scale:.1f} {head_y + 44 * scale:.1f} {cx + 64 * scale:.1f} {head_y + 64 * scale:.1f} {cx + 64 * scale:.1f} {head_y + 128 * scale:.1f} Z"
    )
    return (
        f'<path d="{body}" fill="{fill}"/>'
        f'<circle cx="{cx}" cy="{head_y}" r="{r:.1f}" fill="{fill}"/>'
        + gloss(cx - r * 0.35, head_y - r * 0.35, r * 0.4, r * 0.25)
    )


def icon_people():
    return person(162, 78, 0.9, "url(#sad)") + person(100, 96, 1.0, "url(#blue)")


def icon_person():
    return person(128, 80, 1.15, "url(#blue)")


def icon_person_grey():
    # Play solo on its blue button (designer, 2026-10-02): the blue person blended in.
    return person(128, 80, 1.15, "url(#grey)")


def icon_robot():
    return "".join(
        [
            ink_line([(128, 70), (128, 42)], 8),
            '<circle cx="128" cy="36" r="13" fill="url(#red)"/>',
            '<rect x="30" y="110" width="22" height="52" rx="8" fill="url(#steel)"/>',
            '<rect x="204" y="110" width="22" height="52" rx="8" fill="url(#steel)"/>',
            '<rect x="46" y="68" width="164" height="136" rx="38" fill="url(#steel)"/>',
            '<rect x="66" y="96" width="124" height="60" rx="26" fill="#243049"/>',
            '<circle cx="100" cy="126" r="15" fill="#7FE7FF"/>',
            '<circle cx="156" cy="126" r="15" fill="#7FE7FF"/>',
            '<circle cx="95" cy="121" r="5" fill="#FFFFFF"/>',
            '<circle cx="151" cy="121" r="5" fill="#FFFFFF"/>',
            f'<rect x="100" y="170" width="56" height="12" rx="6" fill="{INK}"/>',
            gloss(80, 84, 24, 10, angle=-10),
        ]
    )


def icon_play():
    tri = "M84 52 L204 128 L84 204 Z"
    return (
        f'<path d="{tri}" fill="url(#green)" stroke="url(#green)" stroke-width="30" stroke-linejoin="round"/>'
        + gloss(96, 92, 14, 30, angle=-25)
    )


def icon_door():
    arrow = "M112 116 L176 116 L176 88 L226 132 L176 176 L176 148 L112 148 Z"
    return "".join(
        [
            '<rect x="40" y="30" width="112" height="190" rx="12" fill="url(#darkwood)"/>',
            '<rect x="56" y="46" width="80" height="174" rx="6" fill="url(#wood)"/>',
            '<circle cx="120" cy="136" r="7" fill="url(#gold)"/>',
            f'<path d="{arrow}" fill="url(#green)" stroke="url(#green)" stroke-width="10" stroke-linejoin="round"/>',
            gloss(80, 80, 10, 26, angle=0, opacity=0.6),
        ]
    )


def icon_flag():
    cloth = "M72 48 C108 30 138 70 204 46 L204 138 C138 162 108 122 72 140 Z"
    return "".join(
        [
            '<rect x="54" y="36" width="16" height="188" rx="8" fill="url(#steel)"/>',
            '<circle cx="62" cy="34" r="13" fill="url(#gold)"/>',
            f'<path d="{cloth}" fill="url(#white)" stroke="url(#white)" stroke-width="6" stroke-linejoin="round"/>',
            f'<path d="M110 70 C130 80 150 88 180 80" stroke="{INK}" stroke-width="4" fill="none" opacity="0.18"/>',
            gloss(104, 70, 22, 9, angle=-10),
        ]
    )


def icon_trophy():
    cup = "M62 40 L194 40 L186 112 C180 150 156 168 128 168 C100 168 76 150 70 112 Z"
    return "".join(
        [
            '<path d="M70 58 C26 58 26 128 84 132" fill="none" stroke="url(#gold)" stroke-width="16" stroke-linecap="round"/>',
            '<path d="M186 58 C230 58 230 128 172 132" fill="none" stroke="url(#gold)" stroke-width="16" stroke-linecap="round"/>',
            f'<path d="{cup}" fill="url(#gold)"/>',
            '<rect x="114" y="164" width="28" height="26" fill="url(#gold)"/>',
            '<rect x="74" y="186" width="108" height="34" rx="10" fill="url(#darkwood)"/>',
            '<rect x="104" y="196" width="48" height="12" rx="4" fill="#FFE27A"/>',
            '<path d="M128 70 L137 92 L160 93 L142 107 L148 130 L128 117 L108 130 L114 107 L96 93 L119 92 Z" fill="#FFFFFF" opacity="0.9"/>',
            gloss(86, 76, 11, 30, angle=-12),
        ]
    )


def icon_sad():
    return "".join(
        [
            '<circle cx="128" cy="130" r="94" fill="url(#sad)"/>',
            f'<ellipse cx="94" cy="118" rx="11" ry="15" fill="{INK}"/>',
            f'<ellipse cx="162" cy="118" rx="11" ry="15" fill="{INK}"/>',
            ink_line([(72, 90), (104, 80)], 8),
            ink_line([(184, 90), (152, 80)], 8),
            '<path d="M88 182 Q128 150 168 182" fill="none" stroke="#1B2033" stroke-width="10" stroke-linecap="round"/>',
            '<path d="M178 136 C170 152 170 162 180 166 C190 162 190 152 182 136 Z" fill="#7FD3FF" stroke="#1B2033" stroke-width="3"/>',
            gloss(94, 76, 30, 16),
        ]
    )


def icon_coin():
    return "".join(
        [
            '<circle cx="128" cy="128" r="100" fill="url(#gold)"/>',
            '<circle cx="128" cy="128" r="74" fill="#FFD84A" stroke="#DB8E00" stroke-width="8"/>',
            gloss(90, 78, 30, 14),
            gloss(166, 176, 10, 5, opacity=0.5),
        ]
    )


def icon_hand():
    # A white cartoon glove, open palm.
    fingers = [(84, 60, 116), (114, 42, 118), (144, 44, 116), (172, 66, 112)]
    parts = []
    for x, top, bottom in fingers:
        parts.append(
            f'<rect x="{x - 14}" y="{top}" width="28" height="{bottom - top + 30}" rx="14" fill="url(#white)"/>'
        )
    parts += [
        '<rect x="44" y="118" width="30" height="74" rx="15" fill="url(#white)" transform="rotate(-38 59 155)"/>',
        '<rect x="68" y="104" width="120" height="98" rx="42" fill="url(#white)"/>',
        '<rect x="78" y="188" width="100" height="34" rx="12" fill="url(#white)"/>',
        ink_line([(92, 198), (164, 198)], 5),
        ink_line([(99, 118), (99, 134)], 5),
        ink_line([(129, 112), (129, 130)], 5),
        ink_line([(158, 116), (158, 134)], 5),
        gloss(104, 150, 22, 12, angle=-20, opacity=0.5),
    ]
    return "".join(parts)


def double_arrow(x0, y0, x1, y1, head=26, stem=13, colour="url(#blue)"):
    """A two-headed arrow from (x0, y0) to (x1, y1): a stem and a triangle at each end."""
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    px, py = -uy, ux  # across the arrow
    parts = []
    for (tx, ty, sx, sy) in ((x1, y1, 1, 1), (x0, y0, -1, -1)):
        bx, by = tx - ux * head * 1.1 * sx, ty - uy * head * 1.1 * sy
        pts = [
            (tx, ty),
            (bx + px * head * 0.85, by + py * head * 0.85),
            (bx - px * head * 0.85, by - py * head * 0.85),
        ]
        d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
        parts.append(f'<path d="{d}" fill="{colour}" stroke-linejoin="round"/>')
    # The stem as a filled quad, not a stroked line: a gradient on a perfectly straight
    # vertical line has a zero-width box and draws nothing.
    a = (x0 + ux * head, y0 + uy * head)
    b = (x1 - ux * head, y1 - uy * head)
    quad = [
        (a[0] + px * stem, a[1] + py * stem),
        (b[0] + px * stem, b[1] + py * stem),
        (b[0] - px * stem, b[1] - py * stem),
        (a[0] - px * stem, a[1] - py * stem),
    ]
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in quad) + " Z"
    parts.insert(0, f'<path d="{d}" fill="{colour}"/>')
    return "".join(parts)


def chevron(cx, cy, w, h, up, colour="url(#blue)"):
    """A fat arrowhead pointing up or down, centred on (cx, cy)."""
    tip, base = (cy - h / 2, cy + h / 2) if up else (cy + h / 2, cy - h / 2)
    pts = [(cx, tip), (cx + w / 2, base), (cx - w / 2, base)]
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
    return f'<path d="{d}" fill="{colour}" stroke-linejoin="round"/>'


def icon_scroll_zoom():
    # A white mouse with a big ridged blue scroll wheel rolling up and down: an arrowhead above
    # and below the wheel, and a red ring circling it. Scroll to zoom.
    parts = [
        '<rect x="58" y="36" width="140" height="196" rx="70" fill="url(#white)"/>',
        ink_line([(62, 118), (194, 118)], 5),
        gloss(90, 176, 18, 34, angle=-8, opacity=0.55),
        # the wheel, big, with ridges across it
        '<rect x="106" y="58" width="44" height="92" rx="22" fill="url(#blue)"/>',
    ]
    for y in (76, 92, 108, 124, 140):
        parts.append(line([(114, y), (142, y)], "#1F6BD0", 5))
    parts += [
        gloss(118, 78, 6, 14, angle=0, opacity=0.6),
        # the roll: up above the wheel, down below it
        chevron(128, 24, 40, 24, up=True),
        chevron(128, 186, 40, 24, up=False),
        # a red ring circling the wheel, so the eye goes straight to it (designer, 2026-09-27)
        '<ellipse cx="128" cy="104" rx="44" ry="58" fill="none" stroke="#FF4D4D" stroke-width="9"/>',
    ]
    return "".join(parts)


def icon_pinch_zoom():
    # A white glove, thumb and finger spread, with arrows pointing out: pinch to zoom.
    return "".join(
        [
            # finger up-right and thumb out right, from a palm at the bottom left
            '<rect x="84" y="46" width="34" height="118" rx="17" fill="url(#white)" transform="rotate(28 101 105)"/>',
            '<rect x="110" y="118" width="34" height="104" rx="17" fill="url(#white)" transform="rotate(-62 127 170)"/>',
            '<rect x="30" y="128" width="104" height="96" rx="44" fill="url(#white)"/>',
            ink_line([(62, 150), (62, 172)], 5),
            ink_line([(86, 146), (86, 170)], 5),
            gloss(66, 196, 22, 12, angle=-15, opacity=0.5),
            # the spread: an arrow out from each fingertip
            double_arrow(150, 108, 214, 40, head=24, stem=10),
            double_arrow(176, 150, 226, 202, head=24, stem=10),
        ]
    )


def icon_target():
    return "".join(
        [
            '<circle cx="128" cy="128" r="98" fill="url(#blue)"/>',
            '<circle cx="128" cy="128" r="72" fill="url(#white)"/>',
            '<circle cx="128" cy="128" r="46" fill="url(#blue)"/>',
            '<circle cx="128" cy="128" r="20" fill="url(#gold)"/>',
            gloss(88, 80, 30, 14),
        ]
    )


def icon_rolling():
    return "".join(
        [
            line([(30, 96), (76, 96)], "#FFFFFF", 14),
            line([(18, 132), (70, 132)], "#FFFFFF", 14),
            line([(34, 168), (78, 168)], "#FFFFFF", 14),
            '<circle cx="152" cy="132" r="72" fill="url(#red)"/>',
            '<circle cx="152" cy="132" r="30" fill="#FFFFFF"/>',
            f'<path d="M142 118 L162 118 L148 150" fill="none" stroke="{INK}" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>',
            gloss(122, 94, 26, 13),
        ]
    )


def icon_lightning():
    bolt = "M150 26 L66 140 L120 140 L100 224 L194 100 L138 100 L164 26 Z"
    return (
        f'<path d="{bolt}" fill="url(#gold)" stroke="url(#gold)" stroke-width="8" stroke-linejoin="round"/>'
        + gloss(124, 76, 9, 30, angle=35)
    )


def icon_check():
    pts = [(50, 132), (104, 186), (206, 72)]
    return line(pts, "url(#green)", 44) + line(
        [(56, 126), (100, 170)], "#FFFFFF", 8, 'opacity="0.45"'
    )


def icon_x():
    return "".join(
        [
            line([(64, 64), (192, 192)], "url(#red)", 46),
            line([(192, 64), (64, 192)], "url(#red)", 46),
            line([(70, 60), (104, 94)], "#FFFFFF", 9, 'opacity="0.45"'),
            line([(178, 60), (150, 88)], "#FFFFFF", 9, 'opacity="0.45"'),
        ]
    )


def icon_arrow():
    shape = "M36 104 L136 104 L136 58 L222 128 L136 198 L136 152 L36 152 Z"
    return (
        f'<path d="{shape}" fill="url(#blue)" stroke="url(#blue)" stroke-width="14" stroke-linejoin="round"/>'
        + gloss(90, 112, 40, 6, angle=0, opacity=0.6)
    )


def chevron_icon(dir):
    """A white chevron pointing right (dir 1) or left (dir -1), drawn as one stroke so its tip
    is a single clean joint: the roadmap's arrow buttons. Two images rather than one turned,
    so the ink lip stays underneath. The invisible square widens the ink filter's box, which
    is the shape's box without its stroke, so the round ends are not cut off."""
    x = lambda v: 128 + dir * (v - 128)
    pts = [(x(96), 52), (x(172), 128), (x(96), 204)]
    frame = '<rect x="8" y="8" width="240" height="240" fill="none"/>'
    return frame + line(pts, "url(#white)", 46) + line(
        [(x(104), 66), (x(150), 112)], "#FFFFFF", 9, 'opacity="0.7"'
    )


def icon_chevron_right():
    return chevron_icon(1)


def icon_chevron_left():
    return chevron_icon(-1)


def icon_chevron_up():
    # Turned inside the ink filter's group, so the lip still drops underneath.
    return f'<g transform="rotate(-90 128 128)">{chevron_icon(1)}</g>'


def icon_chevron_down():
    return f'<g transform="rotate(90 128 128)">{chevron_icon(1)}</g>'


def icon_sliders():
    parts = []
    for y, x, colour in ((68, 92, "blue"), (128, 166, "green"), (188, 112, "red")):
        parts.append(line([(44, y), (212, y)], "#C9D3E3", 16))  # a gradient on a flat line draws nothing
        parts.append(f'<circle cx="{x}" cy="{y}" r="24" fill="url(#{colour})"/>')
        parts.append(gloss(x - 8, y - 9, 9, 5))
    return "".join(parts)


def icon_money():
    """Money is a stack of green cash, never coins (docs/UI_STYLE.md section 6)."""
    parts = []
    for i, (x, y) in enumerate(((52, 150), (40, 118), (28, 86))):
        parts.append(
            f'<rect x="{x}" y="{y}" width="176" height="84" rx="12" fill="url(#green)" transform="rotate(-8 128 128)"/>'
        )
        parts.append(
            f'<rect x="{x + 12}" y="{y + 10}" width="152" height="64" rx="8" fill="none" stroke="#1E9E47" stroke-width="5" transform="rotate(-8 128 128)"/>'
        )
    # The top bill: a round seal in the middle and a paper band round the stack.
    parts += [
        '<ellipse cx="112" cy="130" rx="26" ry="24" fill="#A8F5BE" stroke="#1E9E47" stroke-width="5" transform="rotate(-8 128 128)"/>',
        '<rect x="96" y="76" width="30" height="104" rx="6" fill="#FFF3D6" transform="rotate(-8 128 128)"/>',
        gloss(80, 104, 30, 9, angle=-8, opacity=0.6),
    ]
    return "".join(parts)


# Cash: isometric bundles of green bills, after assets/ui/reference/04-cash-icons.png. The
# bundle is measured off that picture in its own pixels (the long edge, the short edge and the
# thickness), and drawn at a scale. Its greens are sampled from it (deeper than PALETTE's).
CASH_LONG = (278, -142)  # the top face's long edge, left corner to back corner
CASH_SHORT = (177, 75)  # its short edge, left corner to front corner
CASH_THICK = 51  # how tall the bundle stands
CASH_BAND = (0.455, 0.615)  # the paper band, as fractions along the long edge
# The cash gradients live in the two cash icons, not the shared defs(), so the other icons'
# SVGs stay as they are. The render page holds every SVG at once, so an id used in both cash
# icons must mean the same thing in both (these do); anything else gets its own id.
CASH_DEFS = (
    "<defs>"
    '<linearGradient id="cashTop" x1="0" y1="1" x2="1" y2="0">'
    '<stop offset="0" stop-color="#5DAE4E"/><stop offset="0.45" stop-color="#86DC7B"/>'
    '<stop offset="1" stop-color="#D2F7CF"/></linearGradient>'
    '<linearGradient id="cashLeft" x1="0" y1="0" x2="0" y2="1">'
    '<stop offset="0" stop-color="#447A3D"/><stop offset="1" stop-color="#2A5224"/></linearGradient>'
    '<linearGradient id="cashRight" x1="0" y1="0" x2="1" y2="1">'
    '<stop offset="0" stop-color="#346530"/><stop offset="1" stop-color="#1C3D17"/></linearGradient>'
    '<linearGradient id="cashBand" x1="0" y1="0" x2="0" y2="1">'
    '<stop offset="0" stop-color="#FCFDEC"/><stop offset="1" stop-color="#E4F1BA"/></linearGradient>'
    '<linearGradient id="cashBandSide" x1="0" y1="0" x2="0" y2="1">'
    '<stop offset="0" stop-color="#BFD3A4"/><stop offset="1" stop-color="#97AF80"/></linearGradient>'
    "</defs>"
)


def cash_points(x, y, s, long=1.0, thick=1.0):
    """A bundle's corners: (x, y) is the top face's left corner, s the scale; long and thick
    stretch the long edge and the height (the stack's bundles are not all alike)."""
    bx, by = CASH_LONG[0] * s * long, CASH_LONG[1] * s * long
    ax, ay = CASH_SHORT[0] * s, CASH_SHORT[1] * s
    t = CASH_THICK * s * thick
    left, back, front = (x, y), (x + bx, y + by), (x + ax, y + ay)
    right = (x + ax + bx, y + ay + by)
    return left, back, right, front, t


def cash_outline(*bundle):
    """The bundle's silhouette: the top face and the two sides seen from the front."""
    left, back, right, front, t = cash_points(*bundle)
    pts = [left, back, right, (right[0], right[1] + t), (front[0], front[1] + t), (left[0], left[1] + t)]
    return "M" + " L".join(f"{px:.1f} {py:.1f}" for px, py in pts) + " Z"


def cash_bundle(*bundle):
    """One bundle of bills, drawn in the unit square of each face (a matrix per face)."""
    left, back, right, front, t = cash_points(*bundle)
    x, y = left
    bx, by = back[0] - x, back[1] - y
    ax, ay = front[0] - x, front[1] - y
    u0, u1 = CASH_BAND
    thin = 'vector-effect="non-scaling-stroke" fill="none"'

    def edges(colour):
        # The bills' edges down a side: a lit rim at the top, then two faint lines.
        return (
            f'<path d="M0 0.1 L1 0.1" stroke="#8FD684" stroke-width="2.5" opacity="0.45" {thin}/>'
            f'<path d="M0 0.42 L1 0.42" stroke="{colour}" stroke-width="2" opacity="0.28" {thin}/>'
            f'<path d="M0 0.72 L1 0.72" stroke="{colour}" stroke-width="2" opacity="0.2" {thin}/>'
        )

    # The bill's frame: an inset border with a small round notch in each corner.
    fu0, fu1, fv0, fv1, du, dv = 0.05, 0.95, 0.11, 0.89, 0.035, 0.085
    frame = (
        f"M{fu0 + du} {fv0} L{fu1 - du} {fv0} Q{fu1 - du} {fv0 + dv} {fu1} {fv0 + dv} "
        f"L{fu1} {fv1 - dv} Q{fu1 - du} {fv1 - dv} {fu1 - du} {fv1} L{fu0 + du} {fv1} "
        f"Q{fu0 + du} {fv1 - dv} {fu0} {fv1 - dv} L{fu0} {fv0 + dv} Q{fu0 + du} {fv0 + dv} {fu0 + du} {fv0} Z"
    )
    frame_line = "#4FA047"
    parts = [
        # a dark base under the faces, so no ink shows through the seams between them
        f'<path d="{cash_outline(*bundle)}" fill="#2A5224"/>',
        # the short side, front left
        f'<g transform="matrix({ax:.2f} {ay:.2f} 0 {t:.2f} {x:.2f} {y:.2f})">'
        '<rect width="1" height="1" fill="url(#cashLeft)"/>' + edges("#77B86C") + "</g>",
        # the long side, front right, with the band down it
        f'<g transform="matrix({bx:.2f} {by:.2f} 0 {t:.2f} {front[0]:.2f} {front[1]:.2f})">'
        '<rect width="1" height="1" fill="url(#cashRight)"/>'
        + edges("#6AAA60")
        # the band stands a little proud of the bills and shades them just before it
        + f'<rect x="{u0 - 0.035}" y="0" width="0.035" height="1" fill="#0E250B" opacity="0.28"/>'
        + f'<rect x="{u0}" y="0" width="{u1 - u0 + 0.006:.3f}" height="1.02" fill="url(#cashBandSide)"/>'
        "</g>",
        # the top bill: frame, oval medallion, and the band across it
        f'<g transform="matrix({bx:.2f} {by:.2f} {ax:.2f} {ay:.2f} {x:.2f} {y:.2f})">'
        '<rect width="1" height="1" fill="url(#cashTop)"/>'
        f'<path d="{frame}" stroke="{frame_line}" stroke-width="2" {thin}/>'
        f'<ellipse cx="0.5" cy="0.5" rx="0.18" ry="0.29" stroke="{frame_line}" stroke-width="2" {thin}/>'
        f'<rect x="{u0}" y="-0.035" width="{u1 - u0:.3f}" height="1.035" fill="url(#cashBand)"/>'
        f'<path d="M{u0} -0.035 L{u0} 1 M{u1} -0.035 L{u1} 1" stroke="#9FBC86" stroke-width="1.5" opacity="0.8" {thin}/>'
        # the lit fold where the band turns down the side
        f'<path d="M{u0} 1 L{u1} 1" stroke="#FFFFFF" stroke-width="2.5" opacity="0.7" {thin}/>'
        "</g>",
        # soft white highlights: the front corner and a sheen on the back of the top bill
        line([(front[0], front[1] + t * 0.15), (front[0], front[1] + t * 0.85)], "#FFFFFF", 3, 'opacity="0.4"'),
        gloss(x + bx * 0.8 + ax * 0.35, y + by * 0.8 + ay * 0.35, bx * 0.27, t * 0.4, angle=-27, opacity=0.45),
    ]
    return "".join(parts)


def cash_layout(s, bundles):
    """bundles: (x offset, long, thick) per bundle, top first. Returns each bundle's
    cash_points arguments, stacked and centred in the icon."""
    placed, y = [], 0.0
    for dx, long, thick in bundles:
        placed.append((dx, y, s, long, thick))
        y += cash_points(0, 0, s, long, thick)[4]
    xs, ys = [], []
    for bundle in placed:
        left, back, right, front, t = cash_points(*bundle)
        xs += [left[0], right[0]]
        ys += [back[1], front[1] + t]
    ox = 128 - (min(xs) + max(xs)) / 2
    oy = 126 - (min(ys) + max(ys)) / 2
    return [(x + ox, y + oy, s, long, thick) for x, y, s, long, thick in placed]


def icon_cash_single():
    """One bundle of bills: the flying +$10 chip."""
    (bundle,) = cash_layout(0.46, [(0, 1.0, 1.0)])
    return CASH_DEFS + cash_bundle(*bundle)


def icon_cash_stack():
    """Three bundles stacked a little crooked, the band down each: the money icon."""
    bundles = cash_layout(0.44, [(0, 1.0, 1.08), (-3, 1.05, 1.08), (-6, 1.04, 1.08)])
    parts = [CASH_DEFS]
    # Bottom bundle first. Each bundle above another gets an ink line along its lower edges,
    # clipped to the bundles below, so the layers read apart (the outer outline is the filter's).
    for i in range(len(bundles) - 1, -1, -1):
        below = bundles[i + 1 :]
        if below:
            clip = f"cashStackBelow{i}"
            parts.append(
                f'<clipPath id="{clip}">' + "".join(f'<path d="{cash_outline(*b)}"/>' for b in below) + "</clipPath>"
            )
            left, _, right, front, t = cash_points(*bundles[i])
            lower = [left, (left[0], left[1] + t), (front[0], front[1] + t), (right[0], right[1] + t), right]
            parts.append(line(lower, INK, 6, f'clip-path="url(#{clip})"'))
        parts.append(cash_bundle(*bundles[i]))
    return "".join(parts)


# The rank roadmap's chat tag reward tile (designer, 2026-09-27; reference 03). Its gradient
# lives in the icon itself, with an id of its own, like the cash. (The loot case is the
# chest further down, 2026-09-28.)
CHAT_DEFS = (
    "<defs>"
    '<linearGradient id="chatBubble" x1="0" y1="0" x2="0.3" y2="1">'
    '<stop offset="0" stop-color="#E8F4FF"/><stop offset="0.5" stop-color="#A9D4FF"/>'
    '<stop offset="1" stop-color="#6FAEF0"/></linearGradient>'
    "</defs>"
)


def icon_chat_tag():
    """A rounded speech bubble with two rows of short lines: the chat tag."""
    x0, x1, y0, y1, r = 28, 228, 42, 178, 46
    bubble = (
        f"M{x0 + r} {y0} L{x1 - r} {y0} A{r} {r} 0 0 1 {x1} {y0 + r} L{x1} {y1 - r} "
        f"A{r} {r} 0 0 1 {x1 - r} {y1} L122 {y1} L64 222 L80 {y1} L{x0 + r} {y1} "
        f"A{r} {r} 0 0 1 {x0} {y1 - r} L{x0} {y0 + r} A{r} {r} 0 0 1 {x0 + r} {y0} Z"
    )
    dash = "#2B74CF"
    return "".join(
        [
            CHAT_DEFS,
            f'<path d="{bubble}" fill="url(#chatBubble)" stroke="url(#chatBubble)" stroke-width="6" stroke-linejoin="round"/>',
            line([(72, 92), (104, 92)], dash, 17),
            line([(128, 92), (184, 92)], dash, 17),
            line([(72, 130), (140, 130)], dash, 17),
            line([(164, 130), (184, 130)], dash, 17),
            gloss(76, 64, 34, 11, angle=-8, opacity=0.9),
        ]
    )


def mini_table(inner):
    """The difficulty pictures: a little green table seen from above."""
    return (
        '<rect x="26" y="26" width="204" height="204" rx="40" fill="url(#darkwood)"/>'
        '<rect x="44" y="44" width="168" height="168" rx="26" fill="url(#cloth)"/>' + inner
    )


def dots(x0, y0, x1, y1, step=17, r=6):
    n = int(math.hypot(x1 - x0, y1 - y0) // step)
    out = []
    for i in range(n + 1):
        t = i / max(n, 1)
        out.append(
            f'<circle cx="{x0 + (x1 - x0) * t:.1f}" cy="{y0 + (y1 - y0) * t:.1f}" r="{r}" fill="#FFFFFF"/>'
        )
    return "".join(out)


def cue_ball(x, y):
    return f'<circle cx="{x}" cy="{y}" r="17" fill="url(#white)" stroke="{INK}" stroke-width="4"/>'


def object_ball(x, y):
    return f'<circle cx="{x}" cy="{y}" r="17" fill="url(#red)" stroke="{INK}" stroke-width="4"/>'


def ghost(x, y):
    return f'<circle cx="{x}" cy="{y}" r="16" fill="none" stroke="#FFFFFF" stroke-width="5"/>'


def icon_level_classic():
    return mini_table(
        dots(84, 176, 138, 118)
        + ghost(146, 110)
        + line([(170, 88), (196, 62)], "#FFFFFF", 6)
        + dots(150, 120, 190, 160, step=15, r=4)
        + object_ball(170, 86)
        + cue_ball(78, 182)
    )


def icon_level_difficult():
    return mini_table(dots(84, 176, 138, 118) + ghost(146, 110) + object_ball(170, 86) + cue_ball(78, 182))


def icon_level_challenger():
    eye = (
        '<circle cx="176" cy="176" r="40" fill="url(#white)"/>'
        '<path d="M150 176 Q176 150 202 176 Q176 202 150 176 Z" fill="#FFFFFF" stroke="#1B2033" stroke-width="5"/>'
        '<circle cx="176" cy="176" r="8" fill="#1B2033"/>'
        + line([(150, 150), (202, 202)], "#FF4D4D", 10)
    )
    return mini_table(object_ball(160, 84) + cue_ball(84, 150)) + eye


# ---------------------------------------------------------------------------------------
# The economy (2026-09-28, docs/prompts/ECONOMY_UI_PROMPT.md section 10): the left column's
# buttons, the case chests, the money packs, the shop and rewards pictures, and the cue
# thumbnail layers. Every gradient these draw has an id starting with the icon's own name,
# since the render page holds every SVG at once and an id must mean one thing on it.
# ---------------------------------------------------------------------------------------


def poly(points, close=True):
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in points)
    return d + (" Z" if close else "")


def rounded_poly(points, r):
    """A closed path through points with each corner rounded off by about r px."""
    n = len(points)
    d = ""
    for i in range(n):
        px, py = points[i - 1]
        cx, cy = points[i]
        nx, ny = points[(i + 1) % n]
        la, lb = math.hypot(cx - px, cy - py), math.hypot(nx - cx, ny - cy)
        ka, kb = min(r, la / 2) / la, min(r, lb / 2) / lb
        a = (cx + (px - cx) * ka, cy + (py - cy) * ka)
        b = (cx + (nx - cx) * kb, cy + (ny - cy) * kb)
        d += ("M" if i == 0 else "L") + f"{a[0]:.1f} {a[1]:.1f} Q{cx:.1f} {cy:.1f} {b[0]:.1f} {b[1]:.1f} "
    return d + "Z"


def face(points, fill, extra=""):
    return f'<path d="{poly(points)}" fill="{fill}" {extra}/>'


def grad(gid, *colours, x1=0, y1=0, x2=0.35, y2=1):
    """A light-to-dark linear gradient through the given colours, evenly spaced."""
    n = len(colours)
    stops = "".join(f'<stop offset="{i / (n - 1):.2f}" stop-color="{c}"/>' for i, c in enumerate(colours))
    return f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{stops}</linearGradient>'


def inked(d, fill, width=5, extra=""):
    """A shape with its own ink edge inside an icon, where it sits over another part: the ink
    drawn twice as wide under the fill, so only its outer half shows."""
    return (
        f'<path d="{d}" fill="{INK}" stroke="{INK}" stroke-width="{width * 2}" stroke-linejoin="round" {extra}/>'
        f'<path d="{d}" fill="{fill}" {extra}/>'
    )


def sparkle(cx, cy, r, fill="#FFFFFF"):
    """A four-pointed twinkle."""
    k = r * 0.14
    d = (
        f"M{cx:.1f} {cy - r:.1f} Q{cx + k:.1f} {cy - k:.1f} {cx + r:.1f} {cy:.1f} "
        f"Q{cx + k:.1f} {cy + k:.1f} {cx:.1f} {cy + r:.1f} Q{cx - k:.1f} {cy + k:.1f} {cx - r:.1f} {cy:.1f} "
        f"Q{cx - k:.1f} {cy - k:.1f} {cx:.1f} {cy - r:.1f} Z"
    )
    return f'<path d="{d}" fill="{fill}"/>'


def twinkle(cx, cy, r, fill="#FFFFFF"):
    """A twinkle with a thin ink edge of its own, for drawing outside the ink group."""
    return sparkle(cx, cy, r, fill).replace("/>", f' stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>')


def star_points(cx, cy, r, inner=0.48, n=5, turn=-90):
    pts = []
    for i in range(n * 2):
        rr = r if i % 2 == 0 else r * inner
        a = math.radians(turn + i * 180 / n)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


# The case chest, after reference 07: seen from the front right, a flat lid, lighter corner
# caps, a round lock plate on the seam. One drawing, five colours. Each: cap (the corner caps
# and the lock plate), top, front and side faces, the inset panels, all light to dark, and a
# deep colour for the lines between parts. The Standard case is kept grey so it never reads
# as Rare's blue.
CHESTS = {
    "standard": {
        "cap": ("#FFFFFF", "#DCE1E9"),
        "frame": ("#EFF2F6", "#C2C9D4"),
        "top": ("#DCE2EA", "#B3BCC9"),
        "front": ("#AAB4C2", "#8893A4"),
        "side": ("#87919F", "#666F80"),
        "deep": "#4B5364",
    },
    "rare": {
        "cap": ("#F2F9FF", "#B8DCFF"),
        "frame": ("#C8E5FF", "#7FBEFF"),
        "top": ("#8FCAFF", "#58A9FF"),
        "front": ("#3E95F5", "#2977DB"),
        "side": ("#2B73D1", "#1C56AB"),
        "deep": "#134493",
    },
    "epic": {
        "cap": ("#FBF6FF", "#DDC8FF"),
        "frame": ("#E5D0FF", "#BD92FF"),
        "top": ("#CBA7FF", "#AD78FF"),
        "front": ("#985BF3", "#7C3DDF"),
        "side": ("#783BD6", "#5C2AB2"),
        "deep": "#46208A",
    },
    "legendary": {
        "cap": ("#FFFEF5", "#FFEDB0"),
        "frame": ("#FFF4BE", "#FFD55A"),
        "top": ("#FFE47E", "#FFC933"),
        "front": ("#F8B51A", "#DE9600"),
        "side": ("#D48C00", "#AC6B00"),
        "deep": "#835000",
    },
    "event": {
        "cap": ("#FFF7FC", "#FFD3EB"),
        "frame": ("#FFD8EF", "#FF9DD2"),
        "top": ("#FFAADA", "#FF7EC4"),
        "front": ("#F553AD", "#DA3892"),
        "side": ("#CF3E90", "#AA2974"),
        "deep": "#861A58",
    },
}


def chest(c, gid, shine=False):
    """The case chest in the colours c (a CHESTS row). gid names its gradients; shine adds
    twinkles. A box from the front right: recessed panels, a light metal frame along every
    edge (posts, the lid's rim, the bottom, two straps over the lid), a blocky cap on each
    corner, and a round lock plate on the seam."""
    W, LID, H = 152, 44, 116  # the front's width, the lid's height, the whole height
    DX, DY = 58, -32  # the depth, drawn up and to the right
    X0, Y0 = 128 - (W + DX) / 2, 128 - (H + DY) / 2 - 2
    FB, FU = 12, 0.2  # a frame band's width on the front, and in depth shares
    CW, CH, CU = 32, 30, 0.32  # a corner cap's width, height and depth share
    deep = c["deep"]

    def pt(x, y, u):  # x across the front, y down from the lid's top, u into the depth
        return (X0 + x + DX * u, Y0 + y + DY * u)

    def F(x0, y0, x1, y1):  # a quad on the front face
        return [pt(x0, y0, 0), pt(x1, y0, 0), pt(x1, y1, 0), pt(x0, y1, 0)]

    def S(u0, y0, u1, y1):  # on the right side
        return [pt(W, y0, u0), pt(W, y0, u1), pt(W, y1, u1), pt(W, y1, u0)]

    def T(x0, u0, x1, u1):  # on the top
        return [pt(x0, 0, u0), pt(x1, 0, u0), pt(x1, 0, u1), pt(x0, 0, u1)]

    def url(n):
        return f"url(#{gid}{n})"

    rim = f'stroke="{deep}" stroke-width="2.5" stroke-linejoin="round"'
    shade = f'fill="{deep}" opacity="0.28"'
    front, side, top = F(0, 0, W, H), S(0, 0, 1, H), T(0, 0, W, 1)
    # the whole chest is clipped to its outline with the corners rounded, so it looks soft
    hull = [pt(0, 0, 0), pt(0, 0, 1), pt(W, 0, 1), pt(W, H, 1), pt(W, H, 0), pt(0, H, 0)]
    parts = [
        "<defs>"
        + f'<clipPath id="{gid}Hull"><path d="{rounded_poly(hull, 13)}"/></clipPath>'
        + grad(gid + "Cap", *c["cap"], x2=0.4)
        + grad(gid + "Frame", *c["frame"], x2=0.3)
        + grad(gid + "Top", *c["top"], x2=0.3)
        + grad(gid + "Front", *c["front"], x2=0.2)
        + grad(gid + "Side", *c["side"])
        + grad(gid + "Spark", "#FFFFFF", "#FFF3B0")
        + "</defs>",
        "".join(face(f, deep, rim) for f in (front, side, top)),
        face(side, url("Side")),
        face(front, url("Front")),
        face(top, url("Top")),
        # the panels' recess: a shade along their top and left edges
        face(F(FB, LID, FB + 5, H - FB), deep, 'opacity="0.25"'),
        face(F(FB, LID, W - FB, LID + 6), deep, 'opacity="0.3"'),
        face(F(FB, 7, W - FB, 12), deep, 'opacity="0.2"'),
        face(S(FU, LID, 1 - FU, LID + 6), deep, 'opacity="0.3"'),
        # the top's plain middle catches the light
        gloss(*pt(W * 0.42, 0, 0.5), 34, 7, angle=-12, opacity=0.6),
    ]
    frame = [
        F(0, 0, FB, H), F(W - FB, 0, W, H), F(0, H - FB, W, H), F(0, LID - FB, W, LID), F(0, 0, W, 7),
        T(0, 0, FB + 4, 1), T(W - FB - 4, 0, W, 1),
    ]
    frame_side = [S(0, 0, FU, H), S(1 - FU, 0, 1, H), S(0, H - FB, 1, H), S(0, LID - FB, 1, LID), S(0, 0, 1, 7)]
    parts += [face(f, url("Frame")) for f in frame]
    parts += [face(f, url("Frame")) + face(f, deep, 'opacity="0.2"') for f in frame_side]
    parts += [
        # the seam under the lid's rim, the edges between faces
        line([pt(0, LID, 0), pt(W, LID, 0), pt(W, LID, 1)], INK, 5),
        line([pt(W, 3, 0), pt(W, H - 3, 0)], deep, 3, 'opacity="0.7"'),
        line([pt(3, 0, 0), pt(W, 0, 0), pt(W, 0, 1)], deep, 3, 'opacity="0.55"'),
        line([pt(4, 2.5, 0), pt(W - 4, 2.5, 0)], "#FFFFFF", 3, 'opacity="0.7"'),
    ]

    def cap(fronts, tops, sides):
        out = ""
        for f in fronts:
            out += face(f, url("Cap"), rim)
        for f in tops:
            out += face(f, url("Cap"), rim)
        for f in sides:
            out += face(f, url("Cap"), rim) + face(f, deep, 'opacity="0.22"')
        return out

    parts += [
        cap([], [T(0, 1 - CU, CW, 1)], []),
        cap([], [T(W - CW, 1 - CU, W, 1)], [S(1 - CU, 0, 1, CH)]),
        cap([], [], [S(1 - CU, H - CH, 1, H)]),
        cap([F(0, 0, CW, CH)], [T(0, 0, CW, CU)], []),
        cap([F(W - CW, 0, W, CH)], [T(W - CW, 0, W, CU)], [S(0, 0, CU, CH)]),
        cap([F(0, H - CH, CW, H)], [], []),
        cap([F(W - CW, H - CH, W, H)], [], [S(0, H - CH, CU, H)]),
    ]
    # the caps' lit bevels
    for x in (0, W - CW):
        parts.append(line([pt(x + 4, CH - 5, 0), pt(x + 4, 4, 0), pt(x + CW - 5, 4, 0)], "#FFFFFF", 3, 'opacity="0.85"'))
        parts.append(line([pt(x + 4, H - 6, 0), pt(x + 4, H - CH + 4, 0), pt(x + CW - 5, H - CH + 4, 0)], "#FFFFFF", 3, 'opacity="0.7"'))
    xm, ym = W / 2, LID
    px, py = pt(xm, ym, 0)
    parts += [
        f'<rect x="{px - 20:.1f}" y="{py - 25:.1f}" width="40" height="50" rx="14" fill="{url("Cap")}" stroke="{INK}" stroke-width="5"/>',
        f'<circle cx="{px:.1f}" cy="{py + 1:.1f}" r="10.5" fill="{url("Front")}" stroke="{deep}" stroke-width="5"/>',
        gloss(px - 8, py - 14, 7, 4, angle=-20, opacity=0.95),
    ]
    out = parts[0] + f'<g clip-path="url(#{gid}Hull)">' + "".join(parts[1:]) + "</g>"
    if shine:
        out += sparkle(40, 42, 21, url("Spark")) + sparkle(232, 30, 12, url("Spark"))
    return out


def icon_case_standard():
    return chest(CHESTS["standard"], "caseStd")


def icon_case_rare():
    return chest(CHESTS["rare"], "caseRare")


def icon_case_epic():
    return chest(CHESTS["epic"], "caseEpic")


def icon_case_legendary():
    return chest(CHESTS["legendary"], "caseLeg", shine=True)


def icon_case_event():
    return chest(CHESTS["event"], "caseEvent")


def icon_case():
    """The generic case: the Standard chest (the roadmap's reward tile)."""
    return chest(CHESTS["standard"], "caseGeneric")


# The left column's buttons. They sit on a blue candy tile, so none of them is mostly blue
# except the trade arrows' one half, and each keeps the full ink outline to read at 46 px.


def icon_shop():
    """A red shopping basket seen a little from above, a white rim and a white handle, after
    reference 06."""
    g = "shop"
    opening = "M54 62 L202 62 Q220 62 224 80 L230 112 L26 112 L32 80 Q36 62 54 62 Z"
    body = "M28 112 L228 112 L206 204 Q202 218 188 218 L68 218 Q54 218 50 204 Z"
    handle = "M40 96 C40 0 216 0 216 96"
    parts = [
        "<defs>"
        + grad(g + "Red", "#FF9A9A", "#FF4D4D", "#C9283A", x2=0.3)
        + grad(g + "In", "#D2323F", "#8E1626", "#5E0B18", x1=0, y1=0, x2=0, y2=1)
        + grad(g + "Rim", "#FFFFFF", "#F1F4FA", "#C9D3E3")
        + grad(g + "Handle", "#FFFFFF", "#DCE3EE", "#9EABC0", x1=0, y1=0, x2=1, y2=1)
        + "</defs>",
        # the open top: a white rim round the dark inside
        f'<path d="{opening}" fill="url(#{g}In)" stroke="#F1F4FA" stroke-width="12" stroke-linejoin="round"/>',
        f'<path d="M50 74 L206 74" stroke="#5E0B18" stroke-width="4" opacity="0.5"/>',
        # the handle, from side to side over the top
        f'<path d="{handle}" fill="none" stroke="{INK}" stroke-width="27" stroke-linecap="round"/>',
        f'<path d="{handle}" fill="none" stroke="url(#{g}Handle)" stroke-width="16" stroke-linecap="round"/>',
        line([(50, 70), (70, 38)], "#FFFFFF", 5, 'opacity="0.85"'),
        # the body, with two rows of slots
        f'<path d="{body}" fill="url(#{g}Red)"/>',
    ]
    for y, xs, w in ((140, (60, 100, 140, 180), 26), (176, (72, 108, 144, 180), 22)):
        for x in xs:
            cx = x - 6 if y == 140 else x - 4
            parts.append(
                f'<rect x="{cx}" y="{y}" width="{w}" height="24" rx="8" fill="#A01B2E"/>'
                f'<rect x="{cx}" y="{y}" width="{w}" height="8" rx="4" fill="#6E0F1C" opacity="0.6"/>'
            )
    parts += [
        # the front rim, over the body's top edge
        f'<rect x="18" y="102" width="220" height="28" rx="13" fill="url(#{g}Rim)" stroke="{INK}" stroke-width="4"/>',
        line([(34, 110), (150, 110)], "#FFFFFF", 4, 'opacity="0.9"'),
        gloss(60, 170, 8, 26, angle=12, opacity=0.55),
    ]
    return zoom("".join(parts), 0.9, dy=4)


def icon_inventory():
    """An orange backpack: a flap with a buckle, a front pocket, side pockets and a handle."""
    g = "inv"
    parts = [
        "<defs>"
        + grad(g + "Body", "#FFD08A", "#FF9F1C", "#D86E00", x2=0.3)
        + grad(g + "Flap", "#FFB54D", "#F08A0C", "#B85A00", x2=0.3)
        + grad(g + "Pocket", "#FFC873", "#FF9B1A", "#D46C00", x2=0.3)
        + grad(g + "Side", "#E88A1A", "#B25800")
        + grad(g + "Strap", "#A5602E", "#6E3A16")
        + "</defs>",
        # the carry handle
        f'<path d="M104 58 C104 26 152 26 152 58" fill="none" stroke="url(#{g}Strap)" stroke-width="14" stroke-linecap="round"/>',
        # side pockets
        f'<rect x="28" y="130" width="40" height="80" rx="16" fill="url(#{g}Side)"/>',
        f'<rect x="188" y="130" width="40" height="80" rx="16" fill="url(#{g}Side)"/>',
        # the body
        f'<rect x="48" y="46" width="160" height="180" rx="52" fill="url(#{g}Body)"/>',
        # the flap over the top, with a strap down to a gold buckle
        f'<path d="M48 104 C48 62 80 46 128 46 C176 46 208 62 208 104 L208 118 C168 136 88 136 48 118 Z" fill="url(#{g}Flap)"/>',
        f'<path d="M50 118 C88 136 168 136 206 118" fill="none" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>',
        f'<rect x="116" y="110" width="24" height="44" rx="6" fill="url(#{g}Strap)"/>',
        f'<rect x="108" y="138" width="40" height="26" rx="8" fill="url(#gold)" stroke="{INK}" stroke-width="5"/>',
        f'<rect x="122" y="146" width="12" height="10" rx="3" fill="{INK}" opacity="0.8"/>',
        # the front pocket with its zip
        f'<rect x="70" y="170" width="116" height="46" rx="18" fill="url(#{g}Pocket)" stroke="{INK}" stroke-width="5"/>',
        line([(84, 184), (172, 184)], "#B85A00", 5),
        f'<rect x="160" y="182" width="10" height="20" rx="4" fill="url(#steel)" stroke="{INK}" stroke-width="3"/>',
        gloss(80, 78, 18, 9, angle=-25, opacity=0.8),
        gloss(66, 150, 6, 18, angle=0, opacity=0.45),
    ]
    return "".join(parts)


def gift_box(g, box, x0=40, y0=124, w=128, h=94, lid=34, over=9, dx=46, dy=-32, bow=True):
    """A gift box from the front right, like the chest: a lid with an overhang, a gold ribbon
    both ways and a bow on top. box: the front, side and top colour pairs. g names the
    gradients. Returns the body and the middle of the lid's top (for a bow or a cue)."""
    x1 = x0 + w
    lx0, lx1, ly0, ly1 = x0 - over, x1 + over, y0 - lid, y0 + 6
    xm = (x0 + x1) / 2
    rw, ru = 13, 0.17  # half the ribbon's width on the front, and on the side in depth shares

    def d(p, u):
        return (p[0] + dx * u, p[1] + dy * u)

    body_f = [(x0, y0), (x1, y0), (x1, y0 + h), (x0, y0 + h)]
    body_s = [(x1, y0), d((x1, y0), 1), d((x1, y0 + h), 1), (x1, y0 + h)]
    lid_f = [(lx0, ly0), (lx1, ly0), (lx1, ly1), (lx0, ly1)]
    lid_s = [(lx1, ly0), d((lx1, ly0), 1), d((lx1, ly1), 1), (lx1, ly1)]
    lid_t = [(lx0, ly0), (lx1, ly0), d((lx1, ly0), 1), d((lx0, ly0), 1)]

    def url(n):
        return f"url(#{g}{n})"

    def band_side(y_top, y_bot, x):
        return [d((x, y_top), 0.5 - ru), d((x, y_top), 0.5 + ru), d((x, y_bot), 0.5 + ru), d((x, y_bot), 0.5 - ru)]

    parts = [
        "<defs>"
        + grad(g + "Front", *box[0], x2=0.2)
        + grad(g + "Side", *box[1])
        + grad(g + "Top", *box[2], x2=0.3)
        + grad(g + "Rib", "#FFF0A0", "#FFD02E", "#E8A200", x2=0.2)
        + grad(g + "RibSide", "#E8A600", "#B97E00")
        + grad(g + "RibTop", "#FFF7C4", "#FFD84A", x2=0.4)
        + "</defs>",
        face(body_s, url("Side")),
        face(body_f, url("Front")),
        face([(xm - rw, y0), (xm + rw, y0), (xm + rw, y0 + h), (xm - rw, y0 + h)], url("Rib")),
        face(band_side(y0, y0 + h, x1), url("RibSide")),
        line([(x1, y0 + 4), (x1, y0 + h - 2)], INK, 3, 'opacity="0.4"'),
        gloss(x0 + 16, y0 + 44, 6, 22, angle=0, opacity=0.45),
        face(lid_s, url("Side")),
        face(lid_f, url("Front")),
        face(lid_t, url("Top")),
        face([(xm - rw, ly0), (xm + rw, ly0), (xm + rw, ly1), (xm - rw, ly1)], url("Rib")),
        face(band_side(ly0, ly1, lx1), url("RibSide")),
        # the ribbon across the top, both ways
        face([(xm - rw, ly0), (xm + rw, ly0), d((xm + rw, ly0), 1), d((xm - rw, ly0), 1)], url("RibTop")),
        face([d((lx0, ly0), 0.5 - ru), d((lx1, ly0), 0.5 - ru), d((lx1, ly0), 0.5 + ru), d((lx0, ly0), 0.5 + ru)], url("RibTop")),
        line([(lx0, ly1), (lx1, ly1), d((lx1, ly1), 1)], INK, 5),
        line([(lx1, ly0 + 3), (lx1, ly1 - 2)], INK, 3, 'opacity="0.4"'),
        line([(lx0 + 4, ly0), (lx1, ly0), d((lx1, ly0), 1)], INK, 3, 'opacity="0.3"'),
        gloss(lx0 + 22, ly0 + 12, 12, 5, angle=-8, opacity=0.8),
    ]
    top_mid = d((xm, ly0), 0.5)
    if bow:
        parts.append(ribbon_bow(g, *top_mid))
    return "".join(parts), top_mid


def ribbon_bow(g, cx, cy, s=1.0):
    """A gold bow: two loops, two tails and a knot, centred on (cx, cy)."""

    def P(x, y):
        return f"{cx + x * s:.1f} {cy + y * s:.1f}"

    loop_l = f"M{P(0, 0)} C{P(-16, -44)} {P(-66, -46)} {P(-60, -12)} C{P(-56, 10)} {P(-22, 8)} {P(0, 0)} Z"
    loop_r = f"M{P(0, 0)} C{P(16, -44)} {P(66, -46)} {P(60, -12)} C{P(56, 10)} {P(22, 8)} {P(0, 0)} Z"
    tail_l = f"M{P(-4, 2)} L{P(-30, 34)} L{P(-20, 32)} L{P(-14, 42)} L{P(6, 6)} Z"
    tail_r = f"M{P(4, 2)} L{P(28, 30)} L{P(18, 30)} L{P(14, 40)} L{P(-6, 6)} Z"
    hole = 'fill="#C88A00" opacity="0.55"'
    return "".join(
        [
            inked(tail_l, f"url(#{g}Rib)", 3),
            inked(tail_r, f"url(#{g}Rib)", 3),
            inked(loop_l, f"url(#{g}Rib)", 3),
            inked(loop_r, f"url(#{g}Rib)", 3),
            f'<ellipse cx="{cx - 34 * s:.1f}" cy="{cy - 14 * s:.1f}" rx="{12 * s:.1f}" ry="{7 * s:.1f}" transform="rotate(-20 {cx - 34 * s:.1f} {cy - 14 * s:.1f})" {hole}/>',
            f'<ellipse cx="{cx + 34 * s:.1f}" cy="{cy - 14 * s:.1f}" rx="{12 * s:.1f}" ry="{7 * s:.1f}" transform="rotate(20 {cx + 34 * s:.1f} {cy - 14 * s:.1f})" {hole}/>',
            f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{13 * s:.1f}" fill="url(#{g}Rib)" stroke="{INK}" stroke-width="{4 * s:.1f}"/>',
            gloss(cx - 40 * s, cy - 26 * s, 9 * s, 4 * s, angle=-25, opacity=0.9),
            gloss(cx - 4 * s, cy - 5 * s, 4 * s, 3 * s, opacity=0.9),
        ]
    )


PINK_BOX = (("#FF9FD3", "#E9409A"), ("#DC3F92", "#A8246A"), ("#FFC4E4", "#FF86C6"))
BLUE_BOX = (("#86C6FF", "#2F84E8"), ("#2A74D6", "#1A52A6"), ("#C2E3FF", "#72B8FF"))


def icon_rewards():
    """A pink gift box with a gold ribbon and bow."""
    body, _ = gift_box("rew", PINK_BOX)
    return body


def fat_arrow(g, x0, x1, cy, colours, head=64, shaft=24, wing=48, depth=14):
    """A chunky arrow from x0 to x1 (either way) with a darker extrusion under it: colours are
    the top face's light, mid and dark, then the extrusion's."""
    sgn = 1 if x1 > x0 else -1
    hx = x1 - sgn * head
    pts = [(x0, cy - shaft), (hx, cy - shaft), (hx, cy - wing), (x1, cy), (hx, cy + wing), (hx, cy + shaft), (x0, cy + shaft)]
    d = poly(pts)
    round_ = 'stroke-linejoin="round"'
    parts = ["<defs>" + grad(g, *colours[:3], x2=0.1) + "</defs>"]
    for k in range(depth, 0, -2):
        parts.append(
            f'<path d="{d}" transform="translate(0 {k})" fill="{colours[3]}" stroke="{colours[3]}" stroke-width="12" {round_}/>'
        )
    parts += [
        f'<path d="{d}" fill="url(#{g})" stroke="url(#{g})" stroke-width="12" {round_}/>',
        f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="4" stroke-opacity="0.35" {round_} transform="translate(0 1)"/>',
        line([(x0 + sgn * 10, cy - shaft + 8), (hx - sgn * 4, cy - shaft + 8)], "#FFFFFF", 7, 'opacity="0.55"'),
    ]
    return "".join(parts)


def icon_trade():
    """Two fat arrows swapping, blue above going right and orange below going left, after
    reference 06."""
    blue = ("#9EDBFF", "#3BA4FF", "#1668D6", "#0E4A9E")
    orange = ("#FFD98A", "#FF9F1C", "#E06A00", "#A04A00")
    top = fat_arrow("tradeBlue", 30, 226, 88, blue)
    bottom = fat_arrow("tradeOrange", 226, 30, 168, orange)
    return zoom(f'<g transform="rotate(-10 128 128)">{top}{bottom}</g>', 0.88, dy=-6)


# Money packs: they grow from the cash bundle (reference 04).


def zoom(body, k, dx=0.0, dy=0.0):
    """Scale a drawing by k about the icon's middle and nudge it, inside the ink group (so the
    outline keeps its width): to give a drawing the same margin as the other icons."""
    return f'<g transform="translate({128 + dx - 128 * k:.2f} {128 + dy - 128 * k:.2f}) scale({k})">{body}</g>'


def fit(body, points, box=(22, 20, 234, 228)):
    """Scale and move a drawing so the box round `points` fills `box` (x0, y0, x1, y1),
    centred: for drawings built in their own coordinates."""
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    k = min((box[2] - box[0]) / w, (box[3] - box[1]) / h)
    tx = (box[0] + box[2]) / 2 - k * (min(xs) + max(xs)) / 2
    ty = (box[1] + box[3]) / 2 - k * (min(ys) + max(ys)) / 2
    return f'<g transform="translate({tx:.2f} {ty:.2f}) scale({k:.4f})">{body}</g>'


def cash_inked(bundle, width=4.5):
    """A cash bundle with an ink edge of its own, for piles where bundles overlap."""
    return cash_bundle(*bundle) + (
        f'<path d="{cash_outline(*bundle)}" fill="none" stroke="{INK}" stroke-width="{width}" stroke-linejoin="round"/>'
    )


def cash_pile(s, items, centre=(128, 126), thick=1.0):
    """items: (along the long edge, along the short edge, how high) in bundle units. Returns the
    bundles' cash_points arguments, back to front, the pile centred on `centre`."""
    lx, ly = CASH_LONG[0] * s, CASH_LONG[1] * s
    sx, sy = CASH_SHORT[0] * s, CASH_SHORT[1] * s
    t = CASH_THICK * s * thick
    placed = []
    for a, b, level in sorted(items, key=lambda it: (it[2], it[1], -it[0])):
        placed.append((a * lx + b * sx, a * ly + b * sy - level * t, s, 1.0, thick))
    xs, ys = [], []
    for bundle in placed:
        left, back, right, front, tt = cash_points(*bundle)
        xs += [left[0], right[0]]
        ys += [back[1], front[1] + tt]
    ox = centre[0] - (min(xs) + max(xs)) / 2
    oy = centre[1] - (min(ys) + max(ys)) / 2
    return [(x + ox, y + oy, s_, lo, th) for x, y, s_, lo, th in placed]


def icon_pack_1():
    """One bundle."""
    (bundle,) = cash_layout(0.47, [(0, 1.0, 1.0)])
    return CASH_DEFS + cash_bundle(*bundle)


def icon_pack_2():
    """A small stack: three bundles, a little crooked."""
    bundles = cash_layout(0.44, [(0, 1.0, 1.08), (-4, 1.04, 1.08), (-8, 1.02, 1.08)])
    return CASH_DEFS + "".join(cash_inked(b) for b in reversed(bundles))


def icon_pack_3():
    """A bigger stack: a tall stack behind and a shorter one in front."""
    wobble = (0, 0.02, -0.02, 0.01, -0.01)
    items = [(wobble[i], 0, i) for i in range(5)] + [(0.12 + wobble[i], 1.05, i) for i in range(3)]
    bundles = cash_pile(0.305, items, centre=(128, 124))
    return CASH_DEFS + "".join(cash_inked(b) for b in bundles)


def icon_pack_4():
    """An open brown briefcase heaped with cash, drawn on the bundles' own slant."""
    g = "brief"
    s = 0.26
    L = (CASH_LONG[0] * s, CASH_LONG[1] * s)
    S = (CASH_SHORT[0] * s, CASH_SHORT[1] * s)
    CL = (L[0] * 1.22, L[1] * 1.22)  # the case's long edge
    CS = (S[0] * 2.3, S[1] * 2.3)  # its short edge
    H = 44  # its height
    LH = 74  # the lid's height
    A = (0.0, 0.0)  # the rim's left corner

    def add(*ps):
        return (sum(p[0] for p in ps), sum(p[1] for p in ps))

    def mul(p, k):
        return (p[0] * k, p[1] * k)

    back, right, front = add(A, CL), add(A, CL, CS), add(A, CS)
    down = (0, H)
    up = add(mul(CS, -0.16), (0, -LH))

    def on_lid(a, v):  # a along the hinge (0..1), v up the lid (0..1)
        return add(A, mul(CL, a), mul(up, v))

    lid = [A, back, add(back, up), add(A, up)]
    lining = [on_lid(0.08, 0.06), on_lid(0.92, 0.06), on_lid(0.92, 0.88), on_lid(0.08, 0.88)]
    handle = [on_lid(0.36, 1.0), on_lid(0.36, 1.14), on_lid(0.64, 1.14), on_lid(0.64, 1.0)]
    inside = [A, back, right, front]
    parts = [
        CASH_DEFS,
        "<defs>"
        + grad(g + "Out", "#C98A55", "#8A4B22", "#5E3014", x2=0.3)
        + grad(g + "Lining", "#D9475A", "#9E2536", x2=0.3)
        + grad(g + "Floor", "#6E1622", "#4A0C16")
        + "</defs>",
        line(handle, "#5E3014", 9, 'fill="none"'),
        face(lid, f"url(#{g}Out)"),
        face(lining, f"url(#{g}Lining)", f'stroke="#5E0B18" stroke-width="3" stroke-linejoin="round"'),
        line([on_lid(0.14, 0.55), on_lid(0.86, 0.55)], "#7A1F2B", 3, 'opacity="0.6"'),
        gloss(*on_lid(0.3, 0.72), 18, 5, angle=-27, opacity=0.45),
        face(inside, f"url(#{g}Floor)"),
    ]
    # the cash: two bundles side by side, heaped with one more on top, above the rim
    ox, oy = add(A, mul(CL, 0.1), mul(CS, 0.06))
    t = CASH_THICK * s
    for a, b, lvl in ((0, 0.0, 0), (0, 1.12, 0), (0.06, 0.56, 1)):
        x = ox + a * L[0] + b * S[0]
        y = oy + a * L[1] + b * S[1] - t * 0.95 - lvl * t
        parts.append(cash_inked((x, y, s, 1.0, 1.0), 4))
    # the front walls, over the cash's bottom, a light rim and two gold latches
    fl = [A, front, add(front, down), add(A, down)]
    fr = [front, right, add(right, down), add(front, down)]
    parts += [
        face(fl, f"url(#{g}Out)"),
        face(fr, f"url(#{g}Out)"),
        face(fr, "#000000", 'opacity="0.16"'),
        line([A, front, right], "#D79A68", 7),
        line([add(A, (0, 4)), add(front, (0, 4)), add(right, (0, 4))], INK, 3, 'opacity="0.5"'),
        line([front, add(front, down)], INK, 3, 'opacity="0.45"'),
        line([add(front, (0, H - 8)), add(right, (0, H - 8))], "#5E3014", 4, 'opacity="0.6"'),
    ]
    k = CL[1] / CL[0]  # the long edge's slope, so the latches sit on the face
    for f in (0.26, 0.74):
        x, y = add(front, mul(CL, f), (0, 10))
        latch = [(x - 9, y - 9 * k), (x + 9, y + 9 * k), (x + 9, y + 9 * k + 20), (x - 9, y - 9 * k + 20)]
        parts.append(face(latch, "url(#gold)", f'stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"'))
    extent = lid + handle + [add(front, down), add(right, down), add(A, down)]
    return fit("".join(parts), extent, box=(24, 22, 232, 226))


def icon_pack_5():
    """A steel safe with a round vault door, and a stack of cash in front of it."""
    g = "safe"
    parts = [
        CASH_DEFS,
        "<defs>"
        + grad(g + "Body", "#E6ECF4", "#A9B5C6", "#6E7B90", x2=0.3)
        + grad(g + "Door", "#C8D2E0", "#8997AC", "#5A667A", x2=0.4)
        + grad(g + "Ring", "#7B879B", "#4A5467")
        + "</defs>",
        # feet
        f'<rect x="46" y="186" width="30" height="26" rx="6" fill="#4A5467"/>',
        f'<rect x="150" y="186" width="30" height="26" rx="6" fill="#4A5467"/>',
        # the body and the door
        f'<rect x="28" y="26" width="170" height="170" rx="26" fill="url(#{g}Body)"/>',
        f'<rect x="28" y="26" width="170" height="170" rx="26" fill="none" stroke="#6E7B90" stroke-width="4" opacity="0.5"/>',
        f'<circle cx="113" cy="108" r="66" fill="url(#{g}Ring)"/>',
        f'<circle cx="113" cy="108" r="54" fill="url(#{g}Door)" stroke="{INK}" stroke-width="4"/>',
    ]
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        parts.append(f'<circle cx="{113 + 60 * math.cos(a):.1f}" cy="{108 + 60 * math.sin(a):.1f}" r="4" fill="#C9D3E3"/>')
    # the wheel: three gold spokes and a hub
    for i in range(3):
        a = math.radians(i * 60 - 30)
        x0, y0 = 113 + 36 * math.cos(a), 108 + 36 * math.sin(a)
        x1, y1 = 113 - 36 * math.cos(a), 108 - 36 * math.sin(a)
        parts.append(line([(x0, y0), (x1, y1)], INK, 14))
        parts.append(line([(x0, y0), (x1, y1)], "#FFC928", 8))
    parts += [
        f'<circle cx="113" cy="108" r="14" fill="url(#gold)" stroke="{INK}" stroke-width="4"/>',
        # the hinge
        f'<rect x="184" y="62" width="14" height="30" rx="5" fill="#6E7B90" stroke="{INK}" stroke-width="3"/>',
        f'<rect x="184" y="128" width="14" height="30" rx="5" fill="#6E7B90" stroke="{INK}" stroke-width="3"/>',
        gloss(60, 52, 22, 8, angle=-20, opacity=0.8),
        gloss(92, 84, 16, 7, angle=-35, opacity=0.6),
    ]
    bundles = cash_pile(0.3, [(0, 0, 0), (0.05, 0, 1)], centre=(170, 196))
    parts += [cash_inked(b) for b in bundles]
    return zoom("".join(parts), 0.9, dy=-6)


GOLD_BAR = (0.8, 0.9, 1.7, 0.16)  # an ingot's long edge, short edge and height (in bundle
# units: CASH_LONG, CASH_SHORT, CASH_THICK) and how far its top is drawn in from its bottom


def gold_bar_corners(x, y, s):
    lf, sf, hf, k = GOLD_BAR
    L = (CASH_LONG[0] * s * lf, CASH_LONG[1] * s * lf)
    S = (CASH_SHORT[0] * s * sf, CASH_SHORT[1] * s * sf)
    H = CASH_THICK * s * hf

    def at(a, b, h=0.0):
        return (x + L[0] * a + S[0] * b, y + L[1] * a + S[1] * b - h)

    return at, k, H, L


def gold_bar(x, y, s, g):
    """An ingot on the bundles' slant: (x, y) its bottom's left corner, s the scale."""
    at, k, H, _ = gold_bar_corners(x, y, s)
    top = [at(k, k, H), at(1 - k, k, H), at(1 - k, 1 - k, H), at(k, 1 - k, H)]
    left = [at(0, 0), at(k, k, H), at(k, 1 - k, H), at(0, 1)]
    frontf = [at(0, 1), at(k, 1 - k, H), at(1 - k, 1 - k, H), at(1, 1)]
    outline = [at(0, 0), at(k, k, H), at(1 - k, k, H), at(1 - k, 1 - k, H), at(1, 1), at(0, 1)]
    return "".join(
        [
            face(left, f"url(#{g}Left)"),
            face(frontf, f"url(#{g}Front)"),
            face(top, f"url(#{g}Top)"),
            line([at(k, 1 - k, H), at(0, 1)], "#B87800", 2.5, 'opacity="0.7"'),
            line([at(k + 0.04, k + 0.08, H), at(1 - k - 0.04, k + 0.08, H)], "#FFFFFF", 3, 'opacity="0.7"'),
            gloss(*at(0.4, 0.5, H), 14, 3.5, angle=-27, opacity=0.8),
            f'<path d="{poly(outline)}" fill="none" stroke="{INK}" stroke-width="4.5" stroke-linejoin="round"/>',
        ]
    )


def icon_pack_6():
    """Three gold bars stacked (two below end to end, one on top) behind a stack of cash."""
    g = "bars"
    s = 0.34
    _, _, H, L = gold_bar_corners(0, 0, s)
    bars = [(L[0] * a, L[1] * a - H * lvl * 0.92) for a, lvl in ((1.04, 0), (0, 0), (0.52, 1))]
    parts = [
        CASH_DEFS,
        "<defs>"
        + grad(g + "Top", "#FFF6B8", "#FFD84A", x2=0.5)
        + grad(g + "Left", "#FFCB2E", "#E09A00")
        + grad(g + "Front", "#F0AC00", "#B87800")
        + "</defs>",
    ]
    extent = []
    for x, y in bars:
        parts.append(gold_bar(x, y, s, g))
        at = gold_bar_corners(x, y, s)[0]
        extent += [at(0, 0), at(1, 0, H), at(1, 1), at(0, 1), at(0.5, 0.2, H)]
    # a stack of cash in front, at the lower left
    for lvl in range(2):
        b = (-30 + 3 * lvl, 40 - CASH_THICK * 0.3 * lvl, 0.3, 1.0, 1.0)
        parts.append(cash_inked(b))
        left, back, right, front, t = cash_points(*b)
        extent += [left, back, right, (front[0], front[1] + t), (left[0], left[1] + t)]
    return fit("".join(parts), extent, box=(24, 36, 232, 220))


def icon_pack_7():
    """A heap of cash, tallest at the back, in a golden glow with twinkles: the biggest pack."""
    heights = {(0, 0): 4, (-1.04, 0): 2, (0, 1.04): 2, (-1.04, 1.04): 1}
    items = [(a + 0.03 * (lvl % 2), b, lvl) for (a, b), n in heights.items() for lvl in range(n)]
    bundles = cash_pile(0.22, items, centre=(128, 136))
    glow = (
        "<defs>"
        '<radialGradient id="pack7Glow" cx="0.5" cy="0.5" r="0.5">'
        '<stop offset="0" stop-color="#FFF6B0" stop-opacity="0.95"/>'
        '<stop offset="0.55" stop-color="#FFD84A" stop-opacity="0.55"/>'
        '<stop offset="1" stop-color="#FFC928" stop-opacity="0"/></radialGradient>'
        "</defs>"
        '<circle cx="128" cy="126" r="126" fill="url(#pack7Glow)"/>'
    )
    parts = [CASH_DEFS] + [cash_inked(b, 3.5) for b in bundles]
    over = twinkle(44, 60, 18, "#FFE14D") + twinkle(206, 40, 13, "#FFE14D") + twinkle(226, 142, 10, "#FFE14D")
    return glow, "".join(parts), over


# Shop and rewards pictures.

RAINBOW_GEMS = [  # the house rainbow (UI_STYLE 4's VIP colours): light, mid, dark
    ("#FF9A9A", "#FF4D4D", "#C4202F"),
    ("#FFCB7A", "#FF9F1C", "#D06A00"),
    ("#FFF3A6", "#FFE14D", "#D9AE00"),
    ("#9AF0B4", "#3DD66B", "#1B9A44"),
    ("#9ED0FF", "#3B9BFF", "#1A62C8"),
    ("#D2B0FF", "#A259FF", "#6A26CC"),
]


def icon_vip():
    """A gold crown set with gems in the house rainbow: bold and saturated, never pastel, so it
    is never taken for Mythic."""
    g = "vip"
    defs = "<defs>" + "".join(grad(f"{g}Gem{i}", *c, x2=0.6) for i, c in enumerate(RAINBOW_GEMS))
    defs += grad(g + "Gold", "#FFF1A0", "#FFC928", "#DB8E00", x2=0.3) + grad(g + "Band", "#FFD84A", "#E8A200", "#B87200") + "</defs>"
    body = "M46 184 L28 88 L70 122 L82 70 L108 116 L128 54 L148 116 L174 70 L186 122 L228 88 L210 184 Z"
    parts = [
        defs,
        f'<path d="{body}" fill="url(#{g}Gold)" stroke="url(#{g}Gold)" stroke-width="10" stroke-linejoin="round"/>',
        f'<path d="M60 150 L196 150" stroke="#DB8E00" stroke-width="5" opacity="0.5"/>',
        gloss(76, 140, 10, 26, angle=-18, opacity=0.7),
    ]
    tips = [(28, 84, 15), (82, 64, 12), (128, 46, 17), (174, 64, 12), (228, 84, 15)]
    for i, (x, y, r) in enumerate(tips):
        parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#{g}Gem{i})" stroke="{INK}" stroke-width="4.5"/>')
        parts.append(f'<circle cx="{x - r * 0.35:.1f}" cy="{y - r * 0.35:.1f}" r="{r * 0.28:.1f}" fill="#FFFFFF" opacity="0.9"/>')
    parts += [
        f'<rect x="36" y="164" width="184" height="50" rx="14" fill="url(#{g}Band)" stroke="{INK}" stroke-width="4"/>',
        line([(50, 172), (206, 172)], "#FFF1A0", 4, 'opacity="0.8"'),
    ]
    # the band's gems: a big purple one in the middle, a red and a blue either side
    gem = "M128 170 L148 189 L128 208 L108 189 Z"
    parts.append(f'<path d="{gem}" fill="url(#{g}Gem5)" stroke="{INK}" stroke-width="4.5" stroke-linejoin="round"/>')
    parts.append(f'<path d="M128 176 L138 189 L128 189 Z" fill="#FFFFFF" opacity="0.7"/>')
    for x, i in ((72, 4), (184, 0)):
        parts.append(f'<ellipse cx="{x}" cy="189" rx="15" ry="12" fill="url(#{g}Gem{i})" stroke="{INK}" stroke-width="4.5"/>')
        parts.append(f'<circle cx="{x - 5}" cy="185" r="3.5" fill="#FFFFFF" opacity="0.9"/>')
    for x, i in ((100, 3), (156, 1)):
        parts.append(f'<circle cx="{x}" cy="189" r="7" fill="url(#{g}Gem{i})" stroke="{INK}" stroke-width="3.5"/>')
    return zoom("".join(parts), 0.9)


def cue_stick(x0, y0, x1, y1, w0, w1, ink=5):
    """A small wooden cue from the butt (x0, y0) to the tip (x1, y1), half widths w0 and w1,
    with an ink edge of its own so it reads over other parts."""
    ux, uy = x1 - x0, y1 - y0
    length = math.hypot(ux, uy)
    ux, uy = ux / length, uy / length
    nx, ny = -uy, ux

    def w(t):
        return w0 + (w1 - w0) * t

    def quad(t0, t1):
        a = (x0 + ux * length * t0, y0 + uy * length * t0)
        b = (x0 + ux * length * t1, y0 + uy * length * t1)
        return [(a[0] + nx * w(t0), a[1] + ny * w(t0)), (b[0] + nx * w(t1), b[1] + ny * w(t1)),
                (b[0] - nx * w(t1), b[1] - ny * w(t1)), (a[0] - nx * w(t0), a[1] - ny * w(t0))]

    outline = poly(quad(0, 1))
    return "".join(
        [
            f'<path d="{outline}" fill="{INK}" stroke="{INK}" stroke-width="{ink * 2}" stroke-linejoin="round"/>',
            f'<circle cx="{x0}" cy="{y0}" r="{w0 + ink}" fill="{INK}"/>',
            f'<circle cx="{x0}" cy="{y0}" r="{w0}" fill="url(#darkwood)"/>',
            face(quad(0, 0.32), "url(#darkwood)"),
            face(quad(0.32, 0.37), "#F4F8FF"),
            face(quad(0.37, 0.93), "url(#wood)"),
            face(quad(0.93, 0.975), "#FFFFFF"),
            face(quad(0.975, 1.0), "#3B9BFF"),
            line([(x0 + ux * 10 + nx * w0 * 0.4, y0 + uy * 10 + ny * w0 * 0.4),
                  (x1 - ux * 20 + nx * w1 * 0.4, y1 - uy * 20 + ny * w1 * 0.4)], "#FFFFFF", 2.5, 'opacity="0.55"'),
        ]
    )


def icon_starter_pack():
    """A blue gift box with a cue standing out of it."""
    body, (tx, ty) = gift_box("starter", BLUE_BOX, x0=36, y0=132, w=124, h=88, lid=32, bow=False)
    cue = cue_stick(tx - 6, ty + 4, 226, 24, 8.5, 4.5)
    slot = f'<ellipse cx="{tx - 6:.1f}" cy="{ty + 4:.1f}" rx="16" ry="8" fill="{INK}" transform="rotate(-20 {tx - 6:.1f} {ty + 4:.1f})"/>'
    return zoom(body + slot + cue + ribbon_bow("starter", 62, 96, 0.62), 0.92, dy=6)


def mini_bill(cx, cy, w, h, angle, g="party"):
    """A single flying bill for confetti: green, a paper band, an ink edge of its own."""
    x, y = cx - w / 2, cy - h / 2
    return (
        f'<g transform="rotate({angle} {cx} {cy})">'
        f'<rect x="{x - 3.5}" y="{y - 3.5}" width="{w + 7}" height="{h + 7}" rx="7" fill="{INK}"/>'
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="4" fill="url(#{g}Bill)"/>'
        f'<rect x="{x + 4}" y="{y + 4}" width="{w - 8}" height="{h - 8}" rx="3" fill="none" stroke="#4FA047" stroke-width="2"/>'
        f'<ellipse cx="{cx}" cy="{cy}" rx="{h * 0.3:.1f}" ry="{h * 0.28:.1f}" fill="none" stroke="#4FA047" stroke-width="2"/>'
        f'<rect x="{cx + w * 0.12:.1f}" y="{y}" width="{w * 0.16:.1f}" height="{h}" fill="#F4F8DE"/>'
        "</g>"
    )


def icon_money_party():
    """A party popper bursting with cash: a striped cone, bills, streamers and dots."""
    g = "party"
    tip = (40, 222)
    mouth = (112, 150)
    r = 40
    ax, ay = mouth[0] - tip[0], mouth[1] - tip[1]
    al = math.hypot(ax, ay)
    ux, uy = ax / al, ay / al
    nx, ny = -uy, ux
    p1 = (mouth[0] + nx * r, mouth[1] + ny * r)
    p2 = (mouth[0] - nx * r, mouth[1] - ny * r)
    cone = poly([tip, p1, p2])
    stripes = []
    for i, (t0, t1) in enumerate(((0.18, 0.36), (0.54, 0.72))):
        a0 = (tip[0] + ax * t0, tip[1] + ay * t0)
        a1 = (tip[0] + ax * t1, tip[1] + ay * t1)
        stripes.append(face([(a0[0] + nx * r * t0 * 1.2, a0[1] + ny * r * t0 * 1.2), (a1[0] + nx * r * t1 * 1.2, a1[1] + ny * r * t1 * 1.2),
                             (a1[0] - nx * r * t1 * 1.2, a1[1] - ny * r * t1 * 1.2), (a0[0] - nx * r * t0 * 1.2, a0[1] - ny * r * t0 * 1.2)],
                            f"url(#{g}Stripe)", f'clip-path="url(#{g}Clip)"'))
    ang = math.degrees(math.atan2(uy, ux))
    parts = [
        "<defs>"
        + grad(g + "Cone", "#FF9A9A", "#FF4D4D", "#C4202F", x2=0.6)
        + grad(g + "Stripe", "#FFF3A6", "#FFD02E", "#E0A000", x2=0.6)
        + grad(g + "Bill", "#D2F7CF", "#86DC7B", "#5DAE4E", x2=0.4)
        + f'<clipPath id="{g}Clip"><path d="{cone}"/></clipPath>'
        + "</defs>",
        # streamers behind the bills
        f'<path d="M122 120 C126 84 104 70 118 44" fill="none" stroke="#3B9BFF" stroke-width="10" stroke-linecap="round"/>',
        f'<path d="M142 140 C170 128 176 104 206 102" fill="none" stroke="#FF5CB8" stroke-width="10" stroke-linecap="round"/>',
        mini_bill(160, 70, 56, 32, -28),
        mini_bill(206, 150, 52, 30, 18),
        mini_bill(84, 50, 46, 26, -58),
        f'<circle cx="222" cy="78" r="9" fill="#FFE14D"/>',
        f'<circle cx="184" cy="30" r="8" fill="#A259FF"/>',
        f'<circle cx="46" cy="104" r="8" fill="#3DD66B"/>',
        f'<circle cx="198" cy="206" r="7" fill="#FF9F1C"/>',
        # the cone and its mouth
        f'<path d="{cone}" fill="url(#{g}Cone)" stroke="url(#{g}Cone)" stroke-width="8" stroke-linejoin="round"/>',
        "".join(stripes),
        f'<ellipse cx="{mouth[0]}" cy="{mouth[1]}" rx="{r + 5}" ry="15" fill="url(#{g}Stripe)" stroke="{INK}" stroke-width="4.5" transform="rotate({ang + 90:.1f} {mouth[0]} {mouth[1]})"/>',
        f'<ellipse cx="{mouth[0]}" cy="{mouth[1]}" rx="{r - 6}" ry="9" fill="#5E0B18" transform="rotate({ang + 90:.1f} {mouth[0]} {mouth[1]})"/>',
        gloss(tip[0] + ax * 0.45 + nx * 14, tip[1] + ay * 0.45 + ny * 14, 22, 5, angle=ang, opacity=0.6),
    ]
    return "".join(parts)


def icon_fast_open():
    """A case chest with a big lightning bolt: open a case at once."""
    chest_art = chest(CHESTS["standard"], "fastChest")
    bolt = "M178 18 L118 118 L156 118 L128 232 L220 96 L180 96 L204 18 Z"
    art = "".join(
        [
            f'<g transform="translate(6 30) scale(0.8)">{chest_art}</g>',
            f'<path d="{bolt}" fill="{INK}" stroke="{INK}" stroke-width="18" stroke-linejoin="round"/>',
            f'<path d="{bolt}" fill="url(#gold)" stroke="url(#gold)" stroke-width="6" stroke-linejoin="round"/>',
            line([(184, 28), (140, 104)], "#FFFFFF", 6, 'opacity="0.6"'),
        ]
    )
    return zoom(art, 0.9)


def icon_limited():
    """A red ticket with a gold star and a torn-off stub: limited stock."""
    g = "lim"
    ticket = (
        "M44 72 L212 72 A14 14 0 0 1 226 86 L226 112 A16 16 0 0 0 226 144 L226 170 "
        "A14 14 0 0 1 212 184 L44 184 A14 14 0 0 1 30 170 L30 144 A16 16 0 0 0 30 112 "
        "L30 86 A14 14 0 0 1 44 72 Z"
    )
    star = poly(star_points(104, 130, 40, inner=0.5))
    parts = [
        "<defs>" + grad(g + "Red", "#FF9AA8", "#FF4D6A", "#C8203F", x2=0.3) + grad(g + "Star", "#FFF6B0", "#FFD02E", "#E8A200", x2=0.4) + "</defs>",
        f'<g transform="rotate(-12 128 128)">',
        f'<path d="{ticket}" fill="url(#{g}Red)"/>',
        f'<path d="M44 84 L212 84" stroke="#FFFFFF" stroke-width="4" opacity="0.45"/>',
        f'<path d="M172 84 L172 172" stroke="#FFFFFF" stroke-width="5" stroke-dasharray="9 8" stroke-linecap="round" opacity="0.85"/>',
        f'<path d="{star}" fill="url(#{g}Star)" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>',
        gloss(92, 114, 9, 5, angle=-30, opacity=0.9),
        # a # on the stub: the ticket's number, without any digit
        line([(192, 112), (188, 148)], "#FFFFFF", 5),
        line([(206, 112), (202, 148)], "#FFFFFF", 5),
        line([(183, 124), (211, 124)], "#FFFFFF", 5),
        line([(181, 137), (209, 137)], "#FFFFFF", 5),
        "</g>",
    ]
    return "".join(parts)


def icon_calendar():
    """A calendar page: done days ticked green, today a flame for the streak."""
    g = "cal"
    parts = [
        "<defs>" + grad(g + "Head", "#FF9A9A", "#FF4D4D", "#C9283A", x2=0.2) + grad(g + "Flame", "#FFE14D", "#FF9F1C", "#FF4D4D", x1=0, y1=0, x2=0, y2=1) + "</defs>",
        f'<rect x="30" y="46" width="196" height="180" rx="24" fill="url(#white)"/>',
        f'<path d="M30 102 L30 70 A24 24 0 0 1 54 46 L202 46 A24 24 0 0 1 226 70 L226 102 Z" fill="url(#{g}Head)"/>',
        line([(30, 102), (226, 102)], INK, 5),
        gloss(66, 64, 22, 7, angle=-6, opacity=0.7),
    ]
    for x in (82, 174):
        parts.append(f'<rect x="{x - 9}" y="24" width="18" height="40" rx="9" fill="url(#steel)" stroke="{INK}" stroke-width="4"/>')
    cells = [(48, 114), (104, 114), (160, 114), (48, 166), (104, 166), (160, 166)]
    for i, (x, y) in enumerate(cells):
        if i < 4:
            parts.append(f'<rect x="{x}" y="{y}" width="48" height="44" rx="11" fill="url(#green)"/>')
            parts.append(line([(x + 12, y + 23), (x + 21, y + 32), (x + 36, y + 13)], "#FFFFFF", 6))
        elif i == 4:
            parts.append(f'<rect x="{x}" y="{y}" width="48" height="44" rx="11" fill="#FFF1C2" stroke="#FF9F1C" stroke-width="4"/>')
            flame = f"M{x + 24} {y + 5} C{x + 38} {y + 18} {x + 40} {y + 28} {x + 36} {y + 34} C{x + 32} {y + 41} {x + 16} {y + 41} {x + 12} {y + 34} C{x + 8} {y + 26} {x + 14} {y + 20} {x + 18} {y + 24} C{x + 18} {y + 16} {x + 22} {y + 12} {x + 24} {y + 5} Z"
            parts.append(f'<path d="{flame}" fill="url(#{g}Flame)" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>')
        else:
            parts.append(f'<rect x="{x}" y="{y}" width="48" height="44" rx="11" fill="#DCE4F0"/>')
    return "".join(parts)


def icon_code():
    """A purple code card with a dark slot of hidden letters: promo codes (after reference 06)."""
    g = "code"
    parts = [
        "<defs>" + grad(g + "Card", "#D7B8FF", "#A259FF", "#6E2FD0", x2=0.25) + grad(g + "Slot", "#1F2440", "#34395E") + "</defs>",
        f'<rect x="22" y="62" width="212" height="132" rx="28" fill="url(#{g}Card)"/>',
        f'<rect x="42" y="96" width="172" height="66" rx="16" fill="url(#{g}Slot)" stroke="{INK}" stroke-width="4"/>',
    ]
    for x in (80, 118, 156):
        parts.append(sparkle(x, 129, 13, "#FFFFFF"))
    parts += [
        f'<rect x="186" y="112" width="7" height="34" rx="3.5" fill="#7FE7FF"/>',
        line([(50, 76), (140, 76)], "#FFFFFF", 5, 'opacity="0.55"'),
        gloss(56, 82, 18, 6, angle=-4, opacity=0.8),
    ]
    return "".join(parts)


def icon_index():
    """A green book with gold corners, a bookmark and a cue on its cover: the cue index."""
    g = "idx"
    parts = [
        "<defs>" + grad(g + "Cover", "#6FE08E", "#2FA24F", "#1C7A37", x2=0.3) + grad(g + "Pages", "#FFFFFF", "#F2EBD6") + "</defs>",
        # the bookmark, under the pages
        f'<path d="M156 206 L180 206 L180 244 L168 234 L156 244 Z" fill="url(#red)"/>',
        # the pages' edge, to the right and below the cover
        f'<rect x="58" y="40" width="160" height="186" rx="16" fill="url(#{g}Pages)"/>',
    ]
    for y in (76, 108, 140, 172):
        parts.append(line([(206, y), (214, y + 4)], "#C9B98E", 3))
    parts += [
        f'<rect x="36" y="28" width="164" height="186" rx="18" fill="url(#{g}Cover)" stroke="{INK}" stroke-width="4"/>',
        f'<rect x="36" y="28" width="28" height="186" rx="12" fill="#1C7A37" opacity="0.55"/>',
        line([(64, 34), (64, 208)], INK, 3, 'opacity="0.4"'),
        f'<rect x="76" y="44" width="110" height="154" rx="12" fill="none" stroke="#FFD84A" stroke-width="4" opacity="0.9"/>',
        f'<path d="M168 28 L200 28 L200 60 Z" fill="url(#gold)" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>',
        f'<path d="M200 182 L200 214 L168 214 Z" fill="url(#gold)" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>',
        cue_stick(94, 180, 170, 64, 8.5, 4.5, ink=4),
        f'<circle cx="112" cy="78" r="15" fill="url(#white)" stroke="{INK}" stroke-width="4"/>',
        gloss(106, 72, 5, 3, opacity=0.9),
        gloss(84, 56, 16, 6, angle=-10, opacity=0.6),
    ]
    return zoom("".join(parts), 0.92, dy=-6)


def icon_sell():
    """A gold price tag on a string, with a bill on it: sell for money."""
    g = "sell"
    tag = "M92 70 L206 70 A18 18 0 0 1 224 88 L224 168 A18 18 0 0 1 206 186 L92 186 L38 128 Z"
    hole = "M78 128 m-13 0 a13 13 0 1 0 26 0 a13 13 0 1 0 -26 0 Z"
    parts = [
        "<defs>" + grad(g + "Tag", "#FFF1A0", "#FFC928", "#DB8E00", x2=0.3) + grad(g + "Bill", "#D2F7CF", "#86DC7B", "#5DAE4E", x2=0.4) + "</defs>",
        f'<g transform="rotate(-32 128 128)">',
        f'<path d="M78 128 C50 118 32 82 58 56 C74 40 96 46 104 60" fill="none" stroke="#F4F8FF" stroke-width="7" stroke-linecap="round"/>',
        f'<path d="{tag} {hole}" fill="url(#{g}Tag)" fill-rule="evenodd" stroke="url(#{g}Tag)" stroke-width="8" stroke-linejoin="round"/>',
        f'<circle cx="78" cy="128" r="13" fill="none" stroke="#B87200" stroke-width="4"/>',
        f'<rect x="108.5" y="96.5" width="99" height="63" rx="10" fill="{INK}"/>',
        f'<rect x="112" y="100" width="92" height="56" rx="7" fill="url(#{g}Bill)"/>',
        f'<rect x="118" y="106" width="80" height="44" rx="5" fill="none" stroke="#4FA047" stroke-width="2.5"/>',
        f'<ellipse cx="158" cy="128" rx="14" ry="13" fill="none" stroke="#4FA047" stroke-width="2.5"/>',
        f'<rect x="168" y="100" width="14" height="56" fill="#F4F8DE"/>',
        gloss(120, 84, 26, 6, angle=0, opacity=0.7),
        "</g>",
    ]
    return "".join(parts)


def icon_lock():
    """A gold padlock with a steel shackle."""
    g = "lock"
    parts = [
        "<defs>" + grad(g + "Shackle", "#F2F5FA", "#AEB8C8", "#6E7B90", x1=0, y1=0, x2=1, y2=0.4) + "</defs>",
        f'<path d="M82 124 L82 88 C82 30 174 30 174 88 L174 124" fill="none" stroke="url(#{g}Shackle)" stroke-width="28" stroke-linecap="round"/>',
        line([(74, 92), (82, 58)], "#FFFFFF", 5, 'opacity="0.7"'),
        f'<rect x="44" y="106" width="168" height="124" rx="30" fill="url(#gold)"/>',
        line([(66, 120), (190, 120)], "#FFFFFF", 5, 'opacity="0.55"'),
        f'<circle cx="128" cy="156" r="17" fill="{INK}"/>',
        f'<path d="M120 162 L136 162 L140 196 L116 196 Z" fill="{INK}" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>',
        gloss(74, 150, 9, 24, angle=0, opacity=0.6),
    ]
    return "".join(parts)


def icon_odds():
    """A pie chart in the rarity colours with the rarest slice pulled out: the drop odds."""
    cx, cy, r = 124, 134, 94
    slices = [("grey", 0.36), ("green", 0.25), ("blue", 0.18), ("purple", 0.12), ("gold", 0.09)]
    parts = []
    a0 = -90.0
    for i, (colour, share) in enumerate(slices):
        a1 = a0 + share * 360
        mid = math.radians((a0 + a1) / 2)
        pull = 20 if i == len(slices) - 1 else 0
        ox, oy = cx + pull * math.cos(mid), cy + pull * math.sin(mid)
        rr = r + (6 if pull else 0)
        x0, y0 = ox + rr * math.cos(math.radians(a0)), oy + rr * math.sin(math.radians(a0))
        x1, y1 = ox + rr * math.cos(math.radians(a1)), oy + rr * math.sin(math.radians(a1))
        large = 1 if share > 0.5 else 0
        d = f"M{ox:.1f} {oy:.1f} L{x0:.1f} {y0:.1f} A{rr} {rr} 0 {large} 1 {x1:.1f} {y1:.1f} Z"
        parts.append(f'<path d="{d}" fill="url(#{colour})" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>')
        a0 = a1
    parts.append(gloss(88, 84, 30, 13, angle=-35, opacity=0.7))
    return zoom("".join(parts), 0.94, dy=4)


# ---------------------------------------------------------------------------------------
# Cue thumbnail layers. One chunky cue, butt bottom-left and tip top-right, split into layers
# that share one canvas and line up exactly. The white layers are tinted in Roblox with a
# cue's look colours (ImageColor3 multiplies, so white becomes the colour); the outline,
# rainbow, gloss and silhouette layers are drawn in their own colours, untinted.
# Draw order, bottom to top: outline, shaft, tip, ring, forearm, accent (or rainbow instead
# of forearm and accent), wrap, cap, gloss. The ferrule is not tinted: Catalog.style gives
# every cue the same ferrule colour, so it is painted into the outline layer in that colour.
# ---------------------------------------------------------------------------------------

CUE_TIP = (222, 34)  # the tip's middle
CUE_BUTT = (38, 218)  # the butt's middle
CUE_HALF = 15.0  # half the cue's width at the butt (chunkier than real, to read at 64 px)
CUE_OUTLINE, CUE_LIP = 7, 4  # a thinner ink than the icons', for so slim a shape
CUE_TIP_SHARE = 0.42  # the tip's width as a share of the butt's (Catalog.style TipWidth)
CUE_FERRULE = "#F2EEE2"  # Catalog's FERRULE, 242 238 226
# Tip to butt, as shares of the length: Catalog.style's proportions, but the small parts (tip,
# ferrule, joint collar, ring) are drawn longer so they still show at 64 px, taken out of
# the shaft. The accent band sits in the middle of the forearm.
CUE_PARTS = [
    ("tip", 0.025),
    ("ferrule", 0.03),
    ("shaft", 0.45),
    ("joint", 0.03),
    ("forearm", 0.22),
    ("ring", 0.02),
    ("wrap", 0.17),
    ("cap", 0.055),
]
CUE_ACCENT = 0.04
CUE_RAINBOW = ["#FF4D4D", "#FF9F1C", "#FFE14D", "#3DD66B", "#3B9BFF", "#A259FF"]


def cue_spans():
    spans, s = {}, 0.0
    for name, share in CUE_PARTS:
        spans[name] = (s, s + share)
        s += share
    f0, f1 = spans["forearm"]
    mid = (f0 + f1) / 2
    spans["accent"] = (mid - CUE_ACCENT / 2, mid + CUE_ACCENT / 2)
    return spans


def cue_frame():
    tx, ty = CUE_TIP
    bx, by = CUE_BUTT
    length = math.hypot(bx - tx, by - ty)
    ax, ay = (bx - tx) / length, (by - ty) / length  # along the cue, tip to butt
    nx, ny = ay, -ax  # across it, toward the upper left (the lit side)
    return length, ax, ay, nx, ny


def cue_pt(s, k):
    """The point s along the cue (0 tip, 1 butt) and k across it (+ toward the upper left)."""
    length, ax, ay, nx, ny = cue_frame()
    return (CUE_TIP[0] + ax * length * s + nx * k, CUE_TIP[1] + ay * length * s + ny * k)


def cue_half(s):
    return CUE_HALF * (CUE_TIP_SHARE + (1 - CUE_TIP_SHARE) * s)


def cue_piece(s0, s1, grow=0.0, k0=None, k1=None):
    """The cue between s0 and s1 as a path: the tip's end is a round dome, the butt's a flat
    one. grow lengthens a piece past its ends (in px) so neighbours overlap with no seam.
    k0/k1 limit it to a strip across the cue, as shares of the half width (-1..1)."""
    length = cue_frame()[0]
    g = grow / length
    a, b = max(0.0, s0 - g), min(1.0, s1 + g)
    lo, hi = (-1.0 if k0 is None else k0), (1.0 if k1 is None else k1)
    pts = []
    steps = 10
    for i in range(steps + 1):  # the upper-left edge, tip to butt
        s = a + (b - a) * i / steps
        pts.append(cue_pt(s, hi * cue_half(s)))
    if b >= 1.0 and k0 is None and k1 is None:  # the butt's dome
        for i in range(1, 16):
            t = math.pi / 2 - math.pi * i / 16
            pts.append(cue_pt(1.0 + 0.4 * CUE_HALF * math.cos(t) / length, CUE_HALF * math.sin(t)))
    for i in range(steps, -1, -1):  # the lower-right edge, butt to tip
        s = a + (b - a) * i / steps
        pts.append(cue_pt(s, lo * cue_half(s)))
    if a <= 0.0 and k0 is None and k1 is None:  # the tip's dome
        r = cue_half(0)
        for i in range(1, 16):
            t = -math.pi / 2 + math.pi * i / 16
            pts.append(cue_pt(-r * math.cos(t) / length, r * math.sin(t)))
    return poly(pts)


def cue_whole():
    return cue_piece(0.0, 1.0)


def cue_layer_svg(body, extra_defs=""):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">'
        f"<defs>{ink_filter_def('cueInk', CUE_OUTLINE, CUE_LIP)}{extra_defs}</defs>{body}</svg>"
    )


def cue_white(*names):
    spans = cue_spans()
    return cue_layer_svg(
        "".join(f'<path d="{cue_piece(*spans[n], grow=1.2)}" fill="#FFFFFF"/>' for n in names)
    )


def cue_shadow(gid):
    """A soft shadow under the cue, down and to the right."""
    f = (
        f'<filter id="{gid}" x="-20%" y="-20%" width="140%" height="140%">'
        '<feGaussianBlur stdDeviation="3"/></filter>'
    )
    return f, (
        f'<path d="{cue_whole()}" fill="#0B1020" opacity="0.2" transform="translate(3 9)" filter="url(#{gid})"/>'
    )


def cue_layer_outline():
    f, shadow = cue_shadow("cueOutlineShadow")
    ferrule = cue_piece(*cue_spans()["ferrule"], grow=1.2)
    return cue_layer_svg(
        shadow + f'<g filter="url(#cueInk)"><path d="{cue_whole()}" fill="{INK}"/></g>' + f'<path d="{ferrule}" fill="{CUE_FERRULE}"/>',
        f,
    )


def cue_layer_rainbow():
    f0, f1 = cue_spans()["forearm"]
    n = len(CUE_RAINBOW)
    parts = []
    for i, colour in enumerate(CUE_RAINBOW):
        a = f0 + (f1 - f0) * i / n
        b = f0 + (f1 - f0) * (i + 1) / n
        parts.append(f'<path d="{cue_piece(a, b, grow=1.2)}" fill="{colour}"/>')
    return cue_layer_svg("".join(parts))


def cue_layer_gloss():
    """The shading: a shine along the lit side, a shade along the far side, and a thin line
    between each part (so no seam shows where two tinted layers meet)."""
    spans = cue_spans()
    clip = f'<clipPath id="cueGlossClip"><path d="{cue_whole()}"/></clipPath>'
    parts = [
        f'<g clip-path="url(#cueGlossClip)">',
        f'<path d="{cue_piece(0.0, 1.0, k0=-1.2, k1=-0.45)}" fill="#0B1020" opacity="0.22"/>',
        f'<path d="{cue_piece(0.0, 1.0, k0=-1.2, k1=-0.78)}" fill="#0B1020" opacity="0.14"/>',
        f'<path d="{cue_piece(0.02, 0.985, k0=0.2, k1=0.62)}" fill="#FFFFFF" opacity="0.38"/>',
        f'<path d="{cue_piece(0.04, 0.96, k0=0.34, k1=0.5)}" fill="#FFFFFF" opacity="0.55"/>',
    ]
    for name in ("tip", "ferrule", "shaft", "joint", "forearm", "ring", "wrap"):
        s = spans[name][1]
        h = cue_half(s)
        parts.append(line([cue_pt(s, -h - 2), cue_pt(s, h + 2)], INK, 2, 'opacity="0.5"'))
    parts.append("</g>")
    return cue_layer_svg("".join(parts), clip)


def cue_layer_silhouette():
    f, shadow = cue_shadow("cueSilShadow")
    return cue_layer_svg(shadow + f'<g filter="url(#cueInk)"><path d="{cue_whole()}" fill="#4A5470"/></g>', f)


CUE_LAYERS = {
    "cue_outline": cue_layer_outline,
    "cue_shaft": lambda: cue_white("shaft"),
    "cue_tip": lambda: cue_white("tip"),
    "cue_ring": lambda: cue_white("joint", "ring"),
    "cue_forearm": lambda: cue_white("forearm"),
    "cue_accent": lambda: cue_white("accent"),
    "cue_rainbow": cue_layer_rainbow,
    "cue_wrap": lambda: cue_white("wrap"),
    "cue_cap": lambda: cue_white("cap"),
    "cue_gloss": cue_layer_gloss,
    "cue_silhouette": cue_layer_silhouette,
}


# ---------------------------------------------------------------------------------------
# Ultimates (2026-09-28, docs/prompts/ULTIMATES_PROMPT.md): the column's Ults button, the ult
# bar's badge (reference 08), the spin screen's LUCKY SPINS and SPIN symbols. Their effect
# images (the cutscene backdrop, the aura flipbook, Magnet's beam, ring, spark and glow) are
# with the effect art below.
# ---------------------------------------------------------------------------------------


def polar_path(cx, cy, radius, n=240, sy=1.0):
    """A closed outline round (cx, cy): radius(a) gives the distance at angle a (radians, 0 to
    the right, going clockwise on screen). radius may return (r, dx, dy) to push a point, as a
    flame's tips lean up. sy squashes it vertically."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        r = radius(a)
        dx = dy = 0.0
        if isinstance(r, tuple):
            r, dx, dy = r
        pts.append((cx + r * math.cos(a) + dx, cy + r * math.sin(a) * sy + dy))
    return poly(pts)


def peak(x, width, power=1.6):
    """A pointed bump: 1 at x = 0 falling to 0 at |x| = width (x in radians, wrapped)."""
    x = (x + math.pi) % (2 * math.pi) - math.pi
    return max(0.0, 1 - abs(x) / width) ** power


def ult_ball(g, cx, cy, r, rim="#7FE7FF"):
    """The black 8 ball: a glossy body lit from the upper left, a thin rim of coloured light on
    its lower right (the splash's glow), the white number disc with an 8 (two stacked rings,
    like the pattern's balls) and a big shine."""
    d = r * 0.47  # the disc's radius
    dx, dy = cx - r * 0.06, cy - r * 0.08
    parts = [
        "<defs>"
        f'<radialGradient id="{g}Ball" cx="0.36" cy="0.3" r="0.78">'
        '<stop offset="0" stop-color="#626A84"/><stop offset="0.3" stop-color="#2A3044"/>'
        '<stop offset="0.75" stop-color="#10131D"/><stop offset="1" stop-color="#05060B"/></radialGradient>'
        + grad(g + "Disc", "#FFFFFF", "#F4F7FC", "#CFD8E6", x2=0.3)
        + "</defs>",
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#{g}Ball)"/>',
    ]
    # the rim light: a thin crescent of coloured light on the lower-right edge, between the
    # ball's edge and the same circle nudged up and left (through the two points they cross)
    o = r * 0.07
    h = math.sqrt(r * r - o * o / 2)
    mx, my = cx - o / 2, cy - o / 2
    p1 = (mx + h / math.sqrt(2), my - h / math.sqrt(2))  # upper right
    p2 = (mx - h / math.sqrt(2), my + h / math.sqrt(2))  # lower left
    parts.append(
        f'<path d="M{p1[0]:.1f} {p1[1]:.1f} A{r} {r} 0 1 1 {p2[0]:.1f} {p2[1]:.1f} '
        f'A{r} {r} 0 0 0 {p1[0]:.1f} {p1[1]:.1f} Z" fill="{rim}" opacity="0.5"/>'
    )
    parts += [
        f'<circle cx="{dx:.1f}" cy="{dy:.1f}" r="{d:.1f}" fill="url(#{g}Disc)"/>',
        f'<ellipse cx="{dx:.1f}" cy="{dy - d * 0.25:.1f}" rx="{d * 0.24:.1f}" ry="{d * 0.21:.1f}" '
        f'fill="none" stroke="{INK}" stroke-width="{d * 0.16:.1f}"/>',
        f'<ellipse cx="{dx:.1f}" cy="{dy + d * 0.23:.1f}" rx="{d * 0.29:.1f}" ry="{d * 0.25:.1f}" '
        f'fill="none" stroke="{INK}" stroke-width="{d * 0.16:.1f}"/>',
        gloss(cx - r * 0.5, cy - r * 0.52, r * 0.3, r * 0.14, angle=-42, opacity=0.95),
        gloss(cx + r * 0.46, cy + r * 0.5, r * 0.12, r * 0.06, angle=-42, opacity=0.4),
    ]
    return "".join(parts)


def icon_ults():
    """The column's Ults button: the black 8 ball in front of a jagged burst of electric
    energy, cyan and blue outside and gold inside, flaring toward the upper right where a gold
    lightning bolt strikes past it. Big and simple, like the column's other icons, so it reads
    at 52 px."""
    g = "ults"
    bx, by = 128, 128  # the burst's middle

    def burst(spikes, base, width):
        # spikes: (angle in degrees, length); straight-sided points of uneven length
        def f(a):
            return base + max(k * peak(a - math.radians(t), width, 1.0) for t, k in spikes)

        return f

    outer = burst(
        [(-150, 34), (-118, 50), (-86, 38), (-58, 54), (-30, 40), (-2, 46), (24, 32), (52, 40),
         (82, 30), (112, 40), (140, 28), (170, 42), (196, 30)],
        78, 0.36,
    )
    inner = burst(
        [(-134, 26), (-102, 34), (-72, 44), (-44, 36), (-16, 48), (10, 30), (38, 34), (68, 24),
         (98, 30), (128, 22), (156, 30), (184, 24)],
        70, 0.3,
    )
    bolt = "M190 14 L146 92 L172 92 L140 170 L222 74 L192 74 L214 14 Z"
    parts = [
        "<defs>"
        + grad(g + "Cyan", "#E6FDFF", "#6FE9FF", "#2F9BFF", "#1F5FD0", x1=0.2, y1=0, x2=0.6, y2=1)
        + grad(g + "Gold", "#FFFBD6", "#FFE45C", "#FFB21C", x2=0.4)
        + grad(g + "Bolt", "#FFF7C4", "#FFD84A", "#F29A00", x2=0.3)
        + "</defs>",
        f'<path d="{polar_path(bx, by, outer, n=720)}" fill="url(#{g}Cyan)" stroke="url(#{g}Cyan)" stroke-width="3" stroke-linejoin="round"/>',
        f'<path d="{polar_path(bx, by, inner, n=720)}" fill="url(#{g}Gold)"/>',
        ult_ball(g, 116, 142, 74, rim="#3FB8FF"),
        inked(bolt, f"url(#{g}Bolt)", 4.5, 'stroke-linejoin="round"'),
        line([(196, 26), (164, 84)], "#FFFFFF", 5, 'opacity="0.7"'),
    ]
    return zoom("".join(parts), 0.88, dx=-4, dy=-2)


def ult_badge(g, splash_back, splash_front, drops, rim):
    """The ult bar's badge (reference 08): the 8 ball on the right, a splash behind it
    reaching up and left, and drops flying off its top left. The bar's pill starts under the
    ball's right half."""
    art = "".join([splash_back, splash_front, drops, ult_ball(g, 146, 146, 80, rim=rim)])
    return zoom(art, 0.88, dx=4, dy=8)


def icon_ult_badge():
    """The badge with its blue paint splash: a lumpy cloud behind the ball, lighter lumps on
    top, and three drops flying off to the upper left."""
    g = "ultBadge"
    cx, cy = 124, 124

    def cloud(a):
        # round lumps all round, one big lobe reaching to the upper left
        lumps = 0.07 * math.cos(7 * a + 0.4) + 0.04 * math.cos(11 * a + 1.3)
        lobe = 0.2 * peak(a - math.radians(-135), 1.3, 1.2)
        return 86 * (1 + lumps + lobe)

    def cap(a):
        lumps = 0.08 * math.cos(6 * a + 1.1) + 0.04 * math.cos(9 * a)
        return 58 * (1 + lumps + 0.18 * peak(a - math.radians(-130), 1.2, 1.2))

    back = (
        "<defs>"
        + grad(g + "Splash", "#D8F4FF", "#7ACDFF", "#3B9BFF", "#2A74D6", x2=0.4)
        + grad(g + "Cap", "#FFFFFF", "#CFF0FF", x2=0.4)
        + "</defs>"
        + f'<path d="{polar_path(cx, cy, cloud)}" fill="url(#{g}Splash)"/>'
    )
    front = f'<path d="{polar_path(cx - 22, cy - 22, cap)}" fill="url(#{g}Cap)" opacity="0.75"/>'
    drops = "".join(
        f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#{g}Splash)"/>' + gloss(x - r * 0.3, y - r * 0.3, r * 0.45, r * 0.3, opacity=0.95)
        for x, y, r in ((34, 30, 13), (70, 16, 9), (18, 70, 8))
    )
    return ult_badge(g, back, front, drops, "#5FC4FF")


def icon_ult_badge_gold():
    """The ready badge: the same ball with a gold and orange flame bursting up behind it, and
    embers flying off its top left."""
    g = "ultBadgeGold"
    cx, cy = 132, 142
    tongues = [  # angle (degrees), length
        (-178, 0.22), (-152, 0.4), (-126, 0.56), (-100, 0.48), (-76, 0.54), (-50, 0.4), (-22, 0.24),
    ]

    def flame(scale, lean):
        def f(a):
            reach = sum(k * peak(a - math.radians(t), 0.4, 1.7) for t, k in tongues)
            lumps = 0.04 * math.cos(9 * a)
            r = 84 * scale * (1 + lumps)
            out = r * reach
            # the tips lean up and curl a little clockwise, like fire in a draught
            return (r + out * 0.55, out * lean, -out * 0.75)

        return f

    back = (
        "<defs>"
        + grad(g + "Outer", "#FFE27A", "#FFB21C", "#FF7A00", "#E05500", x1=0, y1=0, x2=0.2, y2=1)
        + grad(g + "Inner", "#FFFFFF", "#FFF4B0", "#FFD84A", x2=0.3)
        + "</defs>"
        + f'<path d="{polar_path(cx, cy, flame(1.0, 0.25))}" fill="url(#{g}Outer)"/>'
    )
    front = f'<path d="{polar_path(cx - 6, cy + 4, flame(0.74, 0.2))}" fill="url(#{g}Inner)" opacity="0.9"/>'
    drops = "".join(
        f'<path d="M{x} {y - r * 1.6} Q{x + r} {y - r * 0.2} {x} {y + r} Q{x - r} {y - r * 0.2} {x} {y - r * 1.6} Z" '
        f'fill="url(#{g}Outer)" transform="rotate(-30 {x} {y})"/>'
        for x, y, r in ((32, 44, 11), (64, 18, 8), (16, 90, 7))
    )
    return ult_badge(g, back, front, drops, "#FFB21C")


def icon_lucky():
    """A four-leaf clover, green to teal, on a short stem, with a twinkle: LUCKY SPINS."""
    g = "lucky"
    cx, cy = 124, 112
    tilt = math.radians(-12)

    def heart(turn, L=92, w=50):
        # a heart with its tip at the clover's middle and its lobes outward
        pts = [
            (0, 0), (-w * 0.25, -L * 0.3), (-w, -L * 0.42), (-w * 0.98, -L * 0.76),
            (-w * 0.94, -L * 1.08), (-w * 0.22, -L * 1.12), (0, -L * 0.84),
            (w * 0.22, -L * 1.12), (w * 0.94, -L * 1.08), (w * 0.98, -L * 0.76),
            (w, -L * 0.42), (w * 0.25, -L * 0.3), (0, 0),
        ]
        c, s = math.cos(turn + tilt), math.sin(turn + tilt)
        q = [(cx + x * c - y * s, cy + x * s + y * c) for x, y in pts]
        f = lambda p: f"{p[0]:.1f} {p[1]:.1f}"  # noqa: E731
        d = f"M{f(q[0])} C{f(q[1])} {f(q[2])} {f(q[3])} C{f(q[4])} {f(q[5])} {f(q[6])} C{f(q[7])} {f(q[8])} {f(q[9])} C{f(q[10])} {f(q[11])} {f(q[12])} Z"
        vein = [(cx + x * c - y * s, cy + x * s + y * c) for x, y in ((0, -12), (0, -L * 0.74))]
        lobe = (cx + (-w * 0.45) * c - (-L * 0.8) * s, cy + (-w * 0.45) * s + (-L * 0.8) * c)
        return d, vein, lobe

    parts = [
        "<defs>"
        + grad(g + "Leaf", "#C8FFD2", "#48E07A", "#16BFA0", "#0B8C82", x1=0, y1=0, x2=0.5, y2=1)
        + grad(g + "Stem", "#3DD66B", "#15A585", x2=1, y2=0.3)
        + "</defs>",
        f'<path d="M{cx} {cy} C{cx + 18} {cy + 50} {cx + 42} {cy + 90} {cx + 86} {cy + 116}" fill="none" '
        f'stroke="url(#{g}Stem)" stroke-width="20" stroke-linecap="round"/>',
    ]
    for turn in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
        d, vein, lobe = heart(turn)
        parts.append(inked(d, f"url(#{g}Leaf)", 3.5))
        parts.append(line(vein, "#0B8C82", 5, 'opacity="0.45"'))
        parts.append(gloss(lobe[0], lobe[1], 13, 8, angle=math.degrees(turn + tilt) - 30, opacity=0.8))
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="10" fill="#1FB98C" stroke="{INK}" stroke-width="3.5"/>')
    over = twinkle(214, 42, 26, "#FFFBD6") + twinkle(40, 206, 13, "#FFFFFF")
    return "", zoom("".join(parts), 0.94, dx=-2, dy=0), over


def icon_ult_spin():
    """The SPIN symbol: a thick gold arrow going round clockwise, and a small lightning bolt in
    its middle."""
    g = "ultSpin"
    cx, cy, r, w = 128, 132, 82, 30
    a0, a1 = math.radians(-58), math.radians(222)  # the arc's start and end (the arrow's head)
    p0 = (cx + r * math.cos(a0), cy + r * math.sin(a0))
    p1 = (cx + r * math.cos(a1), cy + r * math.sin(a1))
    arc = f"M{p0[0]:.1f} {p0[1]:.1f} A{r} {r} 0 1 1 {p1[0]:.1f} {p1[1]:.1f}"
    # the head at the arc's end, pointing along the way round (clockwise: the tangent is
    # (-sin a, cos a))
    tx, ty = -math.sin(a1), math.cos(a1)
    nx, ny = math.cos(a1), math.sin(a1)
    tip = (p1[0] + tx * 50, p1[1] + ty * 50)
    head = [
        tip,
        (p1[0] + nx * 40 - tx * 4, p1[1] + ny * 40 - ty * 4),
        (p1[0] - nx * 40 - tx * 4, p1[1] - ny * 40 - ty * 4),
    ]
    bolt = "M142 70 L96 138 L124 138 L108 196 L162 118 L134 118 L154 70 Z"
    hi_r = r + w * 0.22
    h0, h1 = math.radians(150), math.radians(215)
    hi = (
        f'<path d="M{cx + hi_r * math.cos(h0):.1f} {cy + hi_r * math.sin(h0):.1f} '
        f'A{hi_r} {hi_r} 0 0 1 {cx + hi_r * math.cos(h1):.1f} {cy + hi_r * math.sin(h1):.1f}" '
        'fill="none" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round" opacity="0.7"/>'
    )
    hi2_0, hi2_1 = math.radians(-50), math.radians(-5)
    hi2 = (
        f'<path d="M{cx + hi_r * math.cos(hi2_0):.1f} {cy + hi_r * math.sin(hi2_0):.1f} '
        f'A{hi_r} {hi_r} 0 0 1 {cx + hi_r * math.cos(hi2_1):.1f} {cy + hi_r * math.sin(hi2_1):.1f}" '
        'fill="none" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round" opacity="0.55"/>'
    )
    parts = [
        "<defs>"
        + grad(g + "Gold", "#FFF1A0", "#FFC928", "#DB8E00", x2=0.3)
        + grad(g + "Bolt", "#FFFBD6", "#FFE45C", "#F2A200", x2=0.3)
        + "</defs>",
        f'<path d="{arc}" fill="none" stroke="url(#{g}Gold)" stroke-width="{w}" stroke-linecap="round"/>',
        f'<path d="{poly(head)}" fill="url(#{g}Gold)" stroke="url(#{g}Gold)" stroke-width="8" stroke-linejoin="round"/>',
        hi,
        hi2,
        f'<path d="{bolt}" fill="url(#{g}Bolt)" stroke="url(#{g}Bolt)" stroke-width="5" stroke-linejoin="round"/>',
        line([(144, 80), (118, 122)], "#FFFFFF", 4, 'opacity="0.7"'),
    ]
    return zoom("".join(parts), 0.96, dy=-4)


ICONS = {
    "cue": icon_cue,
    "hourglass": icon_hourglass,
    "stopwatch": icon_stopwatch,
    "whistle": icon_whistle,
    "crown": icon_crown,
    "people": icon_people,
    "person": icon_person,
    "person_grey": icon_person_grey,
    "robot": icon_robot,
    "play": icon_play,
    "door": icon_door,
    "flag": icon_flag,
    "trophy": icon_trophy,
    "sad": icon_sad,
    "coin": icon_coin,
    "hand": icon_hand,
    "target": icon_target,
    "rolling": icon_rolling,
    "lightning": icon_lightning,
    "check": icon_check,
    "x": icon_x,
    "arrow": icon_arrow,
    "chevron_right": icon_chevron_right,
    "chevron_left": icon_chevron_left,
    "chevron_up": icon_chevron_up,
    "chevron_down": icon_chevron_down,
    "sliders": icon_sliders,
    "money": icon_money,
    "cash_single": icon_cash_single,
    "cash_stack": icon_cash_stack,
    "case": icon_case,
    "chat_tag": icon_chat_tag,
    "level_classic": icon_level_classic,
    "level_difficult": icon_level_difficult,
    "level_challenger": icon_level_challenger,
    "scroll_zoom": icon_scroll_zoom,
    "pinch_zoom": icon_pinch_zoom,
    # the economy (2026-09-28)
    "shop": icon_shop,
    "inventory": icon_inventory,
    "rewards": icon_rewards,
    "trade": icon_trade,
    "case_standard": icon_case_standard,
    "case_rare": icon_case_rare,
    "case_epic": icon_case_epic,
    "case_legendary": icon_case_legendary,
    "case_event": icon_case_event,
    "pack_1": icon_pack_1,
    "pack_2": icon_pack_2,
    "pack_3": icon_pack_3,
    "pack_4": icon_pack_4,
    "pack_5": icon_pack_5,
    "pack_6": icon_pack_6,
    "pack_7": icon_pack_7,
    "vip": icon_vip,
    "starter_pack": icon_starter_pack,
    "money_party": icon_money_party,
    "fast_open": icon_fast_open,
    "limited": icon_limited,
    "calendar": icon_calendar,
    "code": icon_code,
    "index": icon_index,
    "sell": icon_sell,
    "lock": icon_lock,
    "odds": icon_odds,
    # the ultimates (2026-09-28)
    "ults": icon_ults,
    "ult_badge": icon_ult_badge,
    "ult_badge_gold": icon_ult_badge_gold,
    "lucky": icon_lucky,
    "ult_spin": icon_ult_spin,
}

# Group names on the command line stand for these icons (python3 tools/gen_ui_art.py economy).
GROUPS = {
    "column": ["shop", "inventory", "rewards", "trade"],
    "cases": ["case", "case_standard", "case_rare", "case_epic", "case_legendary", "case_event"],
    "packs": [f"pack_{i}" for i in range(1, 8)],
    "shop_icons": [
        "vip", "starter_pack", "money_party", "fast_open", "limited", "calendar", "code",
        "index", "sell", "lock", "odds",
    ],
    "cue_layers": list(CUE_LAYERS),
}
GROUPS["economy"] = [name for group in list(GROUPS.values()) for name in group]
# The ultimates' icons and effect images (not part of "economy").
GROUPS["ults"] = [
    "ults", "ult_badge", "ult_badge_gold", "lucky", "ult_spin",
    "ult_backdrop", "aura_flame", "field_lines", "ring_glow", "spark", "soft_glow",
]

# ---------------------------------------------------------------------------------------
# Effect art (no ink outline: these sit inside or behind other shapes)
# ---------------------------------------------------------------------------------------


def pattern_ball(cx, cy, r, tilt, n):
    """One soft 8 ball for the panel pattern: a shaded body, its number disc toward the upper
    left and turned by `tilt` degrees, a small 8 and a shine. In its own pale blues and white,
    so the disc and shine stay lighter than the ball; Config only sets how faint."""
    g = f"pb{n}"
    dx, dy = -0.3 * r, -0.28 * r  # the disc sits up and left, as if the ball has rolled
    return (
        f'<radialGradient id="{g}" cx="0.36" cy="0.32" r="0.72">'
        '<stop offset="0" stop-color="#EEF3FB"/><stop offset="0.6" stop-color="#C8D6EC"/>'
        '<stop offset="1" stop-color="#9FB4D6"/></radialGradient>'
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#{g})"/>'
        f'<g transform="translate({cx + dx:.1f} {cy + dy:.1f}) rotate({tilt})">'
        f'<ellipse rx="{r * 0.42:.1f}" ry="{r * 0.38:.1f}" fill="#F7F8FA"/>'
        # The 8: two small stacked rings.
        f'<circle cy="{-r * 0.11:.1f}" r="{r * 0.085:.1f}" fill="none" stroke="#A3B6D6" stroke-width="{r * 0.06:.1f}"/>'
        f'<circle cy="{r * 0.1:.1f}" r="{r * 0.11:.1f}" fill="none" stroke="#A3B6D6" stroke-width="{r * 0.06:.1f}"/>'
        "</g>"
        f'<ellipse cx="{cx + r * 0.32:.1f}" cy="{cy + r * 0.42:.1f}" rx="{r * 0.34:.1f}" ry="{r * 0.16:.1f}" '
        f'fill="#FFFFFF" opacity="0.35" transform="rotate(-35 {cx + r * 0.32:.1f} {cy + r * 0.42:.1f})"/>'
    )


def art_pattern():
    """The panel pattern tile, after the designer's reference (2026-09-27): soft 8 balls of a
    few sizes, each turned its own way, and a few small bubbles, scattered so the repeat does
    not show. Drawn in colour on clear; Config.UI.Kit sets how faint."""
    size = 512
    balls = [  # x, y, radius, tilt
        (90, 80, 46, -20),
        (300, 60, 30, 15),
        (430, 175, 40, -8),
        (200, 215, 26, 22),
        (62, 330, 34, 8),
        (330, 345, 48, -28),
        (170, 455, 30, -14),
        (472, 425, 24, 18),
    ]
    bubbles = [(250, 128, 9), (425, 300, 7), (36, 205, 8), (290, 480, 6)]
    parts = []
    n = 0
    for x, y, r, tilt in balls:
        # Draw each at every wrap-around position so the tile repeats seamlessly.
        for dx in (-size, 0, size):
            for dy in (-size, 0, size):
                cx, cy = x + dx, y + dy
                if -r <= cx <= size + r and -r <= cy <= size + r:
                    parts.append(pattern_ball(cx, cy, r, tilt, n))
                    n += 1
    for x, y, r in bubbles:
        parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#C4D3EA"/>')
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 {size} {size}">' + "".join(parts) + "</svg>"
    )


def art_gloss():
    """Laid over a round HUD ball: shading toward the lower right and a highlight."""
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><defs>'
        '<radialGradient id="glossShade" cx="0.4" cy="0.35" r="0.72">'
        '<stop offset="0" stop-color="#000000" stop-opacity="0"/>'
        '<stop offset="0.72" stop-color="#000000" stop-opacity="0.04"/>'
        '<stop offset="1" stop-color="#000000" stop-opacity="0.34"/></radialGradient>'
        '<radialGradient id="glossHi" cx="0.5" cy="0.5" r="0.5">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.95"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient></defs>'
        '<circle cx="128" cy="128" r="128" fill="url(#glossShade)"/>'
        '<ellipse cx="86" cy="70" rx="54" ry="32" fill="url(#glossHi)" transform="rotate(-32 86 70)"/>'
        '<ellipse cx="190" cy="196" rx="16" ry="8" fill="url(#glossHi)" opacity="0.35" transform="rotate(-40 190 196)"/>'
        "</svg>"
    )


def art_band():
    """A stripe ball's band: white between 19% and 81% of the height, clipped to the ball."""
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">'
        '<defs><clipPath id="bandClip"><circle cx="128" cy="128" r="128"/></clipPath></defs>'
        '<rect x="0" y="49" width="256" height="158" fill="#FFFFFF" clip-path="url(#bandClip)"/></svg>'
    )


def art_rays():
    """Spinning rays behind the win trophy, white (tinted in Roblox), fading outward."""
    wedges = []
    count = 14
    for i in range(count):
        a0 = (i / count) * 2 * math.pi
        a1 = a0 + math.pi / count
        x0, y0 = 256 + 256 * math.cos(a0), 256 + 256 * math.sin(a0)
        x1, y1 = 256 + 256 * math.cos(a1), 256 + 256 * math.sin(a1)
        wedges.append(f'<path d="M256 256 L{x0:.1f} {y0:.1f} L{x1:.1f} {y1:.1f} Z" fill="#FFFFFF"/>')
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><defs>'
        '<radialGradient id="rayFade" cx="0.5" cy="0.5" r="0.5">'
        '<stop offset="0.1" stop-color="#FFFFFF" stop-opacity="1"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>'
        '<mask id="rayMask"><rect width="512" height="512" fill="url(#rayFade)"/></mask></defs>'
        '<g mask="url(#rayMask)">' + "".join(wedges) + "</g></svg>"
    )


def art_svg(w, h, body, extra_defs=""):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
        f"<defs>{extra_defs}</defs>{body}</svg>"
    )


def blur_def(fid, sigma):
    return (
        f'<filter id="{fid}" x="-50%" y="-50%" width="200%" height="200%">'
        f'<feGaussianBlur stdDeviation="{sigma}"/></filter>'
    )


def brush_stroke(points, width, taper=(0.25, 0.45)):
    """A brush stroke along points: widest in the middle, tapering to a point at both ends
    (taper: the share of the length each end takes to reach full width)."""
    n = len(points)
    left, right = [], []
    for i, (x, y) in enumerate(points):
        s = i / (n - 1)
        k = min(1.0, s / taper[0], (1 - s) / taper[1])
        hw = width / 2 * math.sin(k * math.pi / 2)
        ax, ay = points[max(i - 1, 0)]
        bx, by = points[min(i + 1, n - 1)]
        tx, ty = bx - ax, by - ay
        length = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / length, tx / length
        left.append((x + nx * hw, y + ny * hw))
        right.append((x - nx * hw, y - ny * hw))
    return poly(left + right[::-1])


def ink_splash(rng, cx, cy, r, fill, drops=5, turn=0.0):
    """A white ink splash: an uneven blob stretched along `turn` (radians), with a few ragged
    lumps and drops thrown off it."""
    k = [(rng.uniform(0.06, 0.12), f, rng.uniform(0, 6.3)) for f in (2, 3)]
    k += [(rng.uniform(0.05, 0.1), rng.randint(4, 6), rng.uniform(0, 6.3))]
    k += [(rng.uniform(0.03, 0.07), rng.randint(8, 12), rng.uniform(0, 6.3))]
    stretch = rng.uniform(1.25, 1.6)

    def f(a):
        rr = r * (1 + sum(amp * math.cos(freq * a + ph) for amp, freq, ph in k))
        # stretched along the turn, like paint thrown by the swirl
        along = (stretch - 1) * rr * math.cos(a - turn)
        return rr, along * math.cos(turn), along * math.sin(turn)

    out = f'<path d="{polar_path(cx, cy, f, n=160)}" fill="{fill}"/>'
    for _ in range(drops):
        a = turn + rng.choice((0, math.pi)) + rng.uniform(-0.6, 0.6)
        d = r * rng.uniform(1.5, 2.4)
        out += f'<circle cx="{cx + d * math.cos(a):.1f}" cy="{cy + d * math.sin(a):.1f}" r="{r * rng.uniform(0.07, 0.2):.1f}" fill="{fill}"/>'
    return out


def art_ult_backdrop():
    """The cutscene's manga panel backdrop (reference 10's swirling domain, as ink): a vortex of
    brush strokes round a calm dark eye left of the middle (the avatar stands in front of it),
    speed lines rushing outward and white ink splashes. White and greys on near-black, so
    ImageColor3 tints it per rarity (white takes the colour, black stays black). The panel
    shows a wide strip (about 3:1) across the middle, and it drifts, so the whole square is
    filled."""
    import random

    size = 1024
    rng = random.Random(8)
    ex, ey = 420, 512  # the eye
    parts = []
    # the depth: a soft grey haze round the eye, dark in the corners
    defs = (
        f'<radialGradient id="ubdHaze" cx="{ex / size:.3f}" cy="{ey / size:.3f}" r="0.62">'
        '<stop offset="0" stop-color="#1A1B22"/><stop offset="0.16" stop-color="#2C2E38"/>'
        '<stop offset="0.36" stop-color="#4A4D5A"/><stop offset="0.7" stop-color="#1C1D24"/>'
        '<stop offset="1" stop-color="#08090D"/></radialGradient>'
        f'<radialGradient id="ubdEye" cx="{ex / size:.3f}" cy="{ey / size:.3f}" r="0.2">'
        '<stop offset="0" stop-color="#050608" stop-opacity="0.85"/>'
        '<stop offset="0.55" stop-color="#050608" stop-opacity="0.55"/>'
        '<stop offset="1" stop-color="#050608" stop-opacity="0"/></radialGradient>'
        # the speed lines fade in away from the eye
        f'<radialGradient id="ubdFade" cx="{ex / size:.3f}" cy="{ey / size:.3f}" r="0.75">'
        '<stop offset="0.3" stop-color="#FFFFFF" stop-opacity="0"/>'
        '<stop offset="0.55" stop-color="#FFFFFF" stop-opacity="1"/></radialGradient>'
        f'<mask id="ubdMask"><rect width="{size}" height="{size}" fill="url(#ubdFade)"/></mask>'
        + blur_def("ubdSoft", 6)
        + blur_def("ubdSofter", 14)
    )
    parts.append(f'<rect width="{size}" height="{size}" fill="url(#ubdHaze)"/>')

    def spiral(r0, a0, sweep, k=0.32, steps=40):
        # a log spiral going clockwise and outward from radius r0 at angle a0
        pts = []
        for i in range(steps):
            t = i / (steps - 1)
            a = a0 + sweep * t
            r = r0 * math.exp(k * sweep * t)
            pts.append((ex + r * math.cos(a), ey + r * math.sin(a) * 0.86))
        return pts

    # back layer: wide soft grey swirls
    back = []
    for _ in range(26):
        r0 = rng.uniform(130, 420)
        pts = spiral(r0, rng.uniform(0, 2 * math.pi), rng.uniform(1.4, 2.6))
        grey = rng.choice(["#6C7080", "#80848F", "#9A9DA8", "#5A5E6C"])
        back.append(f'<path d="{brush_stroke(pts, rng.uniform(26, 70))}" fill="{grey}" opacity="{rng.uniform(0.35, 0.7):.2f}"/>')
    parts.append(f'<g filter="url(#ubdSofter)">{"".join(back)}</g>')
    # speed lines: thin wedges from far out toward the eye
    lines_ = []
    for _ in range(110):
        a = rng.uniform(0, 2 * math.pi)
        r_in, r_out = rng.uniform(240, 420), 900
        w = rng.uniform(2, 9)
        c, s = math.cos(a), math.sin(a)
        pts = [
            (ex + r_in * c, ey + r_in * s),
            (ex + r_out * c - s * w, ey + r_out * s + c * w),
            (ex + r_out * c + s * w, ey + r_out * s - c * w),
        ]
        lines_.append(f'<path d="{poly(pts)}" fill="#FFFFFF" opacity="{rng.uniform(0.25, 0.8):.2f}"/>')
    parts.append(f'<g mask="url(#ubdMask)">{"".join(lines_)}</g>')
    # middle layer: lighter swirls, a little soft
    mid = []
    for _ in range(40):
        r0 = rng.uniform(120, 520)
        pts = spiral(r0, rng.uniform(0, 2 * math.pi), rng.uniform(0.9, 2.0))
        grey = rng.choice(["#B8BBC4", "#D0D2D9", "#A4A7B2"])
        mid.append(f'<path d="{brush_stroke(pts, rng.uniform(10, 30) * (0.6 + r0 / 500))}" fill="{grey}" opacity="{rng.uniform(0.5, 0.9):.2f}"/>')
    parts.append(f'<g filter="url(#ubdSoft)">{"".join(mid)}</g>')
    # front layer: crisp white ink strokes, the manga lines
    front = []
    for _ in range(46):
        r0 = rng.uniform(135, 560)
        pts = spiral(r0, rng.uniform(0, 2 * math.pi), rng.uniform(0.6, 1.6))
        front.append(
            f'<path d="{brush_stroke(pts, rng.uniform(3, 12) * (0.6 + r0 / 400), taper=(0.15, 0.6))}" fill="#FFFFFF" opacity="{rng.uniform(0.75, 1):.2f}"/>'
        )
    parts.append("".join(front))
    # the calm eye: darkened so the avatar stands out
    parts.append(f'<rect width="{size}" height="{size}" fill="url(#ubdEye)"/>')
    # white ink splashes, kept off the eye (none in the avatar's third)
    splashes = [
        (830, 560, 50), (955, 420, 34), (690, 372, 26), (128, 640, 48), (70, 380, 28),
        (900, 700, 24), (640, 700, 30), (300, 230, 40), (720, 180, 34), (520, 840, 44),
        (180, 860, 30), (980, 900, 36), (60, 120, 30), (860, 90, 26), (150, 470, 18),
        (760, 470, 16),
    ]
    for x, y, r in splashes:
        # each splash stretches along the swirl (square to the line from the eye)
        turn = math.atan2(y - ey, x - ex) + math.pi / 2
        parts.append(ink_splash(rng, x, y, r, "#FFFFFF", turn=turn))
    return art_svg(size, size, "".join(parts), defs)


def art_aura_flame():
    """The aura's flipbook (ParticleEmitter FlipbookLayout Grid4x4, 16 frames of 256 px, left
    to right then top to bottom): one flame wisp, white with soft edges (the emitter's Color
    tints it), growing from a small flicker to a tall curling tongue, then lifting off, thinning
    and fading out."""
    size, cell = 1024, 256
    defs = blur_def("afBody", 7) + blur_def("afCore", 3.5)
    frames = []
    for i in range(16):
        t = i / 15
        grow = min(1.0, t / 0.6)
        ease = 1 - (1 - grow) ** 2
        lift = max(0.0, (t - 0.6) / 0.4)  # 0 until frame 9, then 0 to 1
        base = 234 - 120 * lift  # it lifts off as it dies, burning away from the bottom
        h = 46 + 154 * ease - 120 * lift + 24 * lift  # the tongue's height (its tip stays in)
        wid = (30 + 12 * ease) * (1 - 0.55 * lift)  # half the width at the widest
        curl = 6 + 26 * ease + 18 * lift  # how far the tip bends
        alpha = 1.0 - lift**1.3
        phase = 0.8 * t

        def axis(s):
            x = 128 + curl * math.sin(math.pi * s * 1.15 + phase) * s - 4 * math.sin(phase * 3) * (1 - s)
            return x, base - s * h

        def half(s):
            body = (1 - s) ** 1.25 * min(1.0, (s + 0.06) / 0.3) ** 0.5
            return wid * body * (1 - 0.35 * lift * (1 - s))

        def outline(scale):
            n = 36
            left, right = [], []
            for j in range(n + 1):
                s = j / n
                x, y = axis(s)
                x2, y2 = axis(min(1.0, s + 0.01))
                tx, ty = x2 - x, y2 - y
                length = math.hypot(tx, ty) or 1.0
                nx, ny = -ty / length, tx / length
                hw = half(s) * scale
                left.append((x + nx * hw, y + ny * hw))
                right.append((x - nx * hw, y - ny * hw))
            return poly(left + right[::-1])

        x0, y0 = (i % 4) * cell, (i // 4) * cell
        # the round foot of the tongue
        fx, fy = axis(0.04)
        foot_r = wid * 0.62 * (1 - 0.6 * lift)
        frames.append(
            f'<svg x="{x0}" y="{y0}" width="{cell}" height="{cell}" viewBox="0 0 {cell} {cell}" overflow="hidden">'
            f'<g opacity="{alpha:.3f}">'
            f'<g filter="url(#afBody)" opacity="0.6"><path d="{outline(1.0)}" fill="#FFFFFF"/>'
            f'<circle cx="{fx:.1f}" cy="{fy:.1f}" r="{foot_r:.1f}" fill="#FFFFFF"/></g>'
            f'<g filter="url(#afCore)" opacity="0.95"><path d="{outline(0.48)}" fill="#FFFFFF"/></g>'
            "</g></svg>"
        )
    return art_svg(size, size, "".join(frames), defs)


def art_field_lines():
    """Magnet's beam texture, 512 x 128: four thin wavy field lines with a soft glow, white on
    clear. Every wave has a whole number of periods across the width, so it tiles left to
    right (the Beam repeats it along its length; U runs along the beam)."""
    w, h = 512, 128
    glow, core = [], []
    for i, yc in enumerate((37, 55, 73, 91)):
        # the same two waves on every line, each a little behind the one above, so they stay
        # parallel and never cross
        ph = 0.35 * i

        def y(x):
            u = 2 * math.pi * x / w
            return yc + 8 * math.sin(2 * u + ph) + 3 * math.sin(3 * u + 1.7 + ph * 1.5)

        pts = [(x, y(x)) for x in range(-64, w + 65, 4)]
        glow.append(line(pts, "#FFFFFF", 9, 'opacity="0.55"'))
        core.append(line(pts, "#FFFFFF", 2.6))
    defs = blur_def("flGlow", 3.5)
    return art_svg(w, h, f'<g filter="url(#flGlow)">{"".join(glow)}</g>' + "".join(core), defs)


def art_ring_glow():
    """A soft white ring, clear in the middle: a bright line at 72% of the radius with a glow
    fading inward and outward. Tinted red or blue in Roblox."""
    stops = [(0, 0), (0.48, 0), (0.58, 0.12), (0.65, 0.4), (0.7, 0.9), (0.72, 1), (0.74, 0.9),
             (0.79, 0.4), (0.87, 0.12), (0.97, 0)]
    grad_ = "".join(f'<stop offset="{o}" stop-color="#FFFFFF" stop-opacity="{a}"/>' for o, a in stops)
    defs = f'<radialGradient id="rgRing" cx="0.5" cy="0.5" r="0.5">{grad_}</radialGradient>'
    return art_svg(256, 256, '<rect width="256" height="256" fill="url(#rgRing)"/>', defs)


def art_spark():
    """A small four-pointed sparkle, white, with a soft glow round it: particle bursts."""
    defs = (
        '<radialGradient id="spkGlow" cx="0.5" cy="0.5" r="0.5">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.75"/>'
        '<stop offset="0.3" stop-color="#FFFFFF" stop-opacity="0.3"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>'
        + blur_def("spkBlur", 3)
    )
    body = (
        '<circle cx="64" cy="64" r="60" fill="url(#spkGlow)"/>'
        f'<g filter="url(#spkBlur)" opacity="0.8">{sparkle(64, 64, 50)}</g>'
        + sparkle(64, 64, 46)
        + '<circle cx="64" cy="64" r="7" fill="#FFFFFF"/>'
    )
    return art_svg(128, 128, body, defs)


def art_soft_glow():
    """A round soft glow: bright in the middle, falling smoothly to clear at the edge."""
    stops = "".join(
        f'<stop offset="{x:.2f}" stop-color="#FFFFFF" stop-opacity="{(1 - x * x) ** 2.2:.3f}"/>'
        for x in [i / 10 for i in range(11)]
    )
    defs = f'<radialGradient id="sgGlow" cx="0.5" cy="0.5" r="0.5">{stops}</radialGradient>'
    return art_svg(256, 256, '<rect width="256" height="256" fill="url(#sgGlow)"/>', defs)


# name: (draw, size); size is one number for a square or (width, height).
ART = {
    "pattern": (art_pattern, 512),
    "ball_gloss": (art_gloss, 256),
    "ball_band": (art_band, 256),
    "rays": (art_rays, 512),
    # the ultimates (2026-09-28)
    "ult_backdrop": (art_ult_backdrop, 1024),
    "aura_flame": (art_aura_flame, 1024),
    "field_lines": (art_field_lines, (512, 128)),
    "ring_glow": (art_ring_glow, 256),
    "spark": (art_spark, 128),
    "soft_glow": (art_soft_glow, 256),
}


def shadow_png(path):
    """9-slice soft shadow: a blurred rounded square, black; SliceCenter 48..80."""
    size, pad, radius, blur = 128, 32, 20, 10
    img = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(img).rounded_rectangle(
        (pad * 4, pad * 4, (size - pad) * 4, (size - pad) * 4), radius * 4, fill=255
    )
    img = img.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.putalpha(img)
    out.save(path)


# ---------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------


def render(jobs):
    """jobs: list of (svg_text, size, png_path); size is one number for a square or (width,
    height). One Chrome screenshot of a grid, cropped."""
    jobs = [(text, size if isinstance(size, tuple) else (size, size), path) for text, size, path in jobs]
    cell = max(max(size) for _, size, _ in jobs)
    columns = 6
    rows = math.ceil(len(jobs) / columns)
    html = [
        "<html><body style='margin:0;background:transparent'>",
    ]
    for i, (text, (w, h), _) in enumerate(jobs):
        x, y = (i % columns) * cell, (i // columns) * cell
        html.append(
            f"<div style='position:absolute;left:{x}px;top:{y}px;width:{w}px;height:{h}px'>{text}</div>"
        )
    html.append("</body></html>")
    with tempfile.TemporaryDirectory() as tmp:
        page = os.path.join(tmp, "sheet.html")
        shot = os.path.join(tmp, "sheet.png")
        with open(page, "w") as f:
            f.write("".join(html))
        subprocess.run(
            [
                CHROME,
                "--headless=new",
                "--disable-gpu",
                "--hide-scrollbars",
                "--default-background-color=00000000",
                f"--force-device-scale-factor={RENDER_SCALE}",
                f"--window-size={columns * cell},{rows * cell}",
                f"--screenshot={shot}",
                "file://" + page,
            ],
            check=True,
            capture_output=True,
        )
        sheet = Image.open(shot).convert("RGBA")
    for i, (_, (w, h), path) in enumerate(jobs):
        x, y = (i % columns) * cell * RENDER_SCALE, (i // columns) * cell * RENDER_SCALE
        crop = sheet.crop((x, y, x + w * RENDER_SCALE, y + h * RENDER_SCALE))
        crop.resize((w, h), Image.LANCZOS).save(path)


def main():
    if not os.path.exists(CHROME):
        sys.exit("Google Chrome is needed to render the SVGs: " + CHROME)
    icons_dir = os.path.join(ROOT, "icons")
    art_dir = os.path.join(ROOT, "art")
    os.makedirs(icons_dir, exist_ok=True)
    os.makedirs(art_dir, exist_ok=True)
    jobs = []
    # Names on the command line draw only those icons or effect images (and no shadow), so
    # adding or redrawing one does not rewrite every other image.
    # A group's name (GROUPS) stands for all its icons.
    only = set()
    for arg in sys.argv[1:]:
        only.update(GROUPS.get(arg, [arg]))
    for name, draw in ICONS.items():
        if only and name not in only:
            continue
        text = svg(draw())
        with open(os.path.join(icons_dir, name + ".svg"), "w") as f:
            f.write(text)
        jobs.append((text, 256, os.path.join(icons_dir, name + ".png")))
    # The cue thumbnail layers: whole SVGs of their own (no shared ink group), 256 px.
    for name, draw in CUE_LAYERS.items():
        if only and name not in only:
            continue
        text = draw()
        with open(os.path.join(icons_dir, name + ".svg"), "w") as f:
            f.write(text)
        jobs.append((text, 256, os.path.join(icons_dir, name + ".png")))
    for name, (draw, size) in ART.items():
        if only and name not in only:
            continue
        text = draw()
        with open(os.path.join(art_dir, name + ".svg"), "w") as f:
            f.write(text)
        jobs.append((text, size, os.path.join(art_dir, name + ".png")))
    render(jobs)
    if only:
        print(f"wrote {len(jobs)} images under {ROOT}")
        return
    shadow_png(os.path.join(art_dir, "shadow.png"))
    print(f"wrote {len(ICONS) + len(CUE_LAYERS)} icons and {len(ART) + 1} effect images under {ROOT}")


if __name__ == "__main__":
    main()
