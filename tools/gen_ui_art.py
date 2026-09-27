#!/usr/bin/env python3
"""Generate the UI icons and effect images (docs/UI_STYLE.md sections 6 and 7).

Every image is drawn as an SVG from one shared style: a thick dark-ink outline with a small
drop lip underneath, a light-to-dark gradient on each colour, and a white gloss highlight.
The SVGs are rendered to transparent PNGs by headless Chrome (one screenshot of a grid,
cropped), so nothing but Pillow and the installed Chrome is needed.

Outputs:
  assets/ui/icons/<name>.svg and <name>.png   256 px glossy cartoon icons, no words
  assets/ui/art/<name>.svg and <name>.png     effect images: the panel pattern tile, the ball
                                              gloss and stripe band, the win rays
  assets/ui/art/shadow.png                    9-slice soft shadow (drawn with Pillow)

Upload the PNGs (Studio MCP upload_image, see docs/STUDIO_NOTES.md) and paste the ids into
Config.UI.Kit.Icons and Config.UI.Kit.Art. Run: python3 tools/gen_ui_art.py
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
    sigma = OUTLINE / 1.3
    ink_filter = f"""
<filter id="ink" x="-30%" y="-30%" width="160%" height="160%" color-interpolation-filters="sRGB">
  <feGaussianBlur in="SourceAlpha" stdDeviation="{sigma:.2f}" result="blur"/>
  <feComponentTransfer in="blur" result="grown"><feFuncA type="linear" slope="7" intercept="-0.35"/></feComponentTransfer>
  <feOffset in="grown" dy="{LIP}" result="lip"/>
  <feMerge result="both"><feMergeNode in="lip"/><feMergeNode in="grown"/></feMerge>
  <feFlood flood-color="{INK}"/>
  <feComposite in2="both" operator="in" result="outline"/>
  <feMerge><feMergeNode in="outline"/><feMergeNode in="SourceGraphic"/></feMerge>
</filter>"""
    shine = (
        '<radialGradient id="shine" cx="0.5" cy="0.5" r="0.5">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>'
    )
    return "<defs>" + "".join(grads) + shine + ink_filter + "</defs>"


def svg(body):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">'
        f'{defs()}<g filter="url(#ink)">{body}</g></svg>'
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


# The rank roadmap's reward tiles (designer, 2026-09-27; reference 03): a loot case and a chat
# tag. Their gradients live in the icons themselves, with ids of their own, like the cash.
CASE_DEFS = (
    "<defs>"
    '<linearGradient id="caseLid" x1="0" y1="0" x2="0.2" y2="1">'
    '<stop offset="0" stop-color="#F4F9FF"/><stop offset="0.5" stop-color="#C3DCF6"/>'
    '<stop offset="1" stop-color="#93B6DE"/></linearGradient>'
    '<linearGradient id="caseFront" x1="0" y1="0" x2="0.25" y2="1">'
    '<stop offset="0" stop-color="#D9EAFC"/><stop offset="0.5" stop-color="#A6C6EA"/>'
    '<stop offset="1" stop-color="#7A9DC8"/></linearGradient>'
    '<linearGradient id="caseSide" x1="0" y1="0" x2="0.3" y2="1">'
    '<stop offset="0" stop-color="#9DBBDF"/><stop offset="1" stop-color="#5F80AC"/></linearGradient>'
    '<linearGradient id="caseEnd" x1="0" y1="0" x2="0.3" y2="1">'
    '<stop offset="0" stop-color="#C9DDF4"/><stop offset="1" stop-color="#86A6D0"/></linearGradient>'
    '<linearGradient id="caseStrap" x1="0" y1="0" x2="0.3" y2="1">'
    '<stop offset="0" stop-color="#7E9CC4"/><stop offset="1" stop-color="#48648E"/></linearGradient>'
    "</defs>"
)


def icon_case():
    """A chunky closed loot case seen from the front right: a box with a barrel lid, two dark
    straps over it and a gold latch at the seam. Pale blue steel, not any one tier's colour."""
    s, ox, oy = 1.08, 128, 132  # scale, and where the drawing's middle lands
    width, height, lid = 138, 80, 50  # the front face, and how high the lid's barrel rises
    dx, dy = 44, -28  # the depth, drawn up and to the right
    # The drawing runs from x 0 (the front's left) to width + dx, and from the barrel's top
    # (dy / 2 - lid) to the front's bottom (height).
    mid_x, mid_y = (width + dx) / 2, (height + dy / 2 - lid) / 2

    def p(x, y):
        return (ox + (x - mid_x) * s, oy + (y - mid_y) * s)

    def path(points, close=True):
        d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in points)
        return d + (" Z" if close else "")

    # The lid's end: half an ellipse on the right face's plane, over the body's top edge.
    def end_curve(shift, steps=14, front_half=False):
        pts = []
        last = steps // 2 if front_half else steps
        for i in range(last + 1):
            t = math.pi * i / steps  # 0 = the front corner, pi = the back one
            u = 0.5 - 0.5 * math.cos(t)  # 0..1 front to back
            x = shift + dx * u
            y = dy * u - lid * math.sin(t)
            pts.append(p(x, y))
        return pts

    front = [p(0, 0), p(width, 0), p(width, height), p(0, height)]
    side = [p(width, 0), p(width + dx, dy), p(width + dx, dy + height), p(width, height)]
    # The barrel's face seen from the front: up the left end to its top, along, down the right.
    left_rise = end_curve(0, front_half=True)
    right_rise = end_curve(width, front_half=True)
    barrel = left_rise + right_rise[::-1]
    lid_end = end_curve(width)

    def strap(at, w=15):
        # A strap over the barrel and down the front, `at` from the left end.
        up = end_curve(at, front_half=True)
        down = end_curve(at + w, front_half=True)[::-1]
        return path(up + down) + " " + path([p(at, 0), p(at + w, 0), p(at + w, height), p(at, height)])

    rim = 13
    latch_w, latch_h = 30, 36
    lx, ly = width / 2 - latch_w / 2, -10
    base = '" fill="#48648E" stroke="#48648E" stroke-width="3" stroke-linejoin="round"/>'
    parts = [
        CASE_DEFS,
        # a dark base under every face, so no light seams show between them
        "".join(f'<path d="{path(face)}{base}' for face in (front, side, barrel, lid_end)),
        f'<path d="{path(side)}" fill="url(#caseSide)"/>',
        f'<path d="{path(front)}" fill="url(#caseFront)"/>',
        f'<path d="{path(lid_end)}" fill="url(#caseEnd)"/>',
        f'<path d="{path(barrel)}" fill="url(#caseLid)"/>',
        f'<path d="{strap(18)}" fill="url(#caseStrap)"/>',
        f'<path d="{strap(width - 33)}" fill="url(#caseStrap)"/>',
        # the lid's darker rim, along its bottom edge, front and end
        f'<path d="{path([p(0, -rim), p(width, -rim), p(width, 0), p(0, 0)])}" fill="#6F8FBA"/>',
        line([p(3, -rim + 2.5), p(width - 3, -rim + 2.5)], "#FFFFFF", 2.5, 'opacity="0.45"'),
        f'<path d="{path([p(width, -rim), p(width + dx, dy - rim), p(width + dx, dy), p(width, 0)])}" fill="#48648E"/>',
        # the seam between lid and body, and the body's front right edge
        line([p(0, 0), p(width, 0), p(width + dx, dy)], INK, 5),
        line([p(width, 0), p(width, height)], INK, 4, 'opacity="0.55"'),
        line(right_rise, INK, 4, 'opacity="0.55"'),
        # a lit rim along the barrel's top and the front's top edge
        line([p(8, -lid + 3), p(width - 8, -lid + 3)], "#FFFFFF", 4, 'opacity="0.7"'),
        # the latch: a gold plate over the seam with a keyhole
        f'<rect x="{p(lx, ly)[0]:.1f}" y="{p(lx, ly)[1]:.1f}" width="{latch_w * s:.1f}" '
        f'height="{latch_h * s:.1f}" rx="{8 * s:.1f}" fill="url(#gold)" stroke="{INK}" stroke-width="5"/>',
        f'<circle cx="{p(width / 2, ly + 13)[0]:.1f}" cy="{p(width / 2, ly + 13)[1]:.1f}" r="{5 * s:.1f}" fill="{INK}"/>',
        line([p(width / 2, ly + 15), p(width / 2, ly + 25)], INK, 5),
        gloss(*p(40, -lid + 14), 26, 8, angle=-4, opacity=0.8),
        gloss(*p(30, 26), 14, 22, angle=0, opacity=0.35),
        gloss(*p(lx + 8, ly + 6), 6, 4, opacity=0.8),
    ]
    return "".join(parts)


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


ICONS = {
    "cue": icon_cue,
    "hourglass": icon_hourglass,
    "stopwatch": icon_stopwatch,
    "whistle": icon_whistle,
    "crown": icon_crown,
    "people": icon_people,
    "person": icon_person,
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
}

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


ART = {
    "pattern": (art_pattern, 512),
    "ball_gloss": (art_gloss, 256),
    "ball_band": (art_band, 256),
    "rays": (art_rays, 512),
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
    """jobs: list of (svg_text, size, png_path). One Chrome screenshot of a grid, cropped."""
    cell = max(size for _, size, _ in jobs)
    columns = 6
    rows = math.ceil(len(jobs) / columns)
    html = [
        "<html><body style='margin:0;background:transparent'>",
    ]
    for i, (text, size, _) in enumerate(jobs):
        x, y = (i % columns) * cell, (i // columns) * cell
        html.append(
            f"<div style='position:absolute;left:{x}px;top:{y}px;width:{size}px;height:{size}px'>{text}</div>"
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
    for i, (_, size, path) in enumerate(jobs):
        x, y = (i % columns) * cell * RENDER_SCALE, (i // columns) * cell * RENDER_SCALE
        crop = sheet.crop((x, y, x + size * RENDER_SCALE, y + size * RENDER_SCALE))
        crop.resize((size, size), Image.LANCZOS).save(path)


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
    only = set(sys.argv[1:])
    for name, draw in ICONS.items():
        if only and name not in only:
            continue
        text = svg(draw())
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
    print(f"wrote {len(ICONS)} icons and {len(ART) + 1} effect images under {ROOT}")


if __name__ == "__main__":
    main()
