#!/usr/bin/env python3
"""The game's Roblox badge icons (hw-sys lane, 2026-10-28; v2 after the designer's look).

    python3 tools/gen_badge_icons.py --compose [Key ...]               assets/ui/badges/<Key>.png
    python3 tools/gen_badge_icons.py --sheet out.png [Key ...]         contact sheet, 150 px circles
    python3 tools/gen_badge_icons.py --list out.png                    the badges: icon, name, how

The designer (2026-10-28): the first set looked AI-made and did not match the game, so every
icon is now drawn here as vector art, no image generation: a flat cartoon pool ball in the
game's colours with UI_STYLE's thick ink outline (#1B2033), one cel-shade step, a white shine
and a white number disc holding a Fredoka One numeral and/or a small flat symbol. Solid balls
for single badges, striped balls for a family's steps. The rank badges keep the rank emblems
(assets/ui/ranks) on a light disc in the tier's ring. Each icon is an SVG page rendered by
headless Chrome (it has the font and real curves) to a 512 px PNG; Roblox crops a badge to a
circle, so everything sits inside a 460 px circle.
"""

import argparse
import base64
import math
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "ui", "badges")
RANK_DIR = os.path.join(ROOT, "assets", "ui", "ranks")
FREDOKA = os.path.expanduser("~/Desktop/8ball-refs/gui-v3/tools/fonts/FredokaOne-Regular.ttf")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SIZE = 512
C = SIZE / 2
SAFE_RADIUS = 230  # Roblox's circle crop: keep everything inside a 460 px circle
BALL_R = 212
INK = "#1B2033"  # UI_STYLE's ink outline
OUTLINE = 14
WHITE = "#FFFFFF"
PALE = "#DCE7F5"  # the white parts' shade step (the panels' pale blue)


def shade(hex_colour, k):
    """`hex_colour` darkened (k < 1) or lightened toward white (k > 1)."""
    r, g, b = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    if k <= 1:
        r, g, b = (int(v * k) for v in (r, g, b))
    else:
        f = k - 1
        r, g, b = (int(v + (255 - v) * f) for v in (r, g, b))
    return f"#{r:02X}{g:02X}{b:02X}"


# --- the small flat symbols, drawn round (0, 0), about 90 x 90 ------------------------------

def trophy(colour):
    dark = shade(colour, 0.78)
    return f"""
    <g stroke="{INK}" stroke-width="7" stroke-linejoin="round" stroke-linecap="round">
      <path d="M-28,-30 C-52,-32 -54,0 -22,4" fill="none"/>
      <path d="M28,-30 C52,-32 54,0 22,4" fill="none"/>
      <rect x="-8" y="16" width="16" height="16" fill="{dark}"/>
      <rect x="-26" y="30" width="52" height="14" rx="5" fill="{colour}"/>
      <path d="M-34,-40 H34 V-14 C34,10 18,22 0,22 C-18,22 -34,10 -34,-14 Z" fill="{colour}"/>
    </g>
    <path d="M-22,-32 V-16 C-22,-4 -16,4 -8,8" stroke="#FFFFFF" stroke-width="6" fill="none"
          stroke-linecap="round" opacity="0.85"/>"""


def flame(colour="#FF7A1A", core="#FFD23F"):
    return f"""
    <path d="M2,-46 C18,-28 38,-14 34,12 C31,34 16,44 0,44 C-17,44 -33,33 -34,12
             C-35,-6 -22,-14 -16,-30 C-8,-20 -6,-12 -4,-6 C2,-20 4,-32 2,-46 Z"
          fill="{colour}" stroke="{INK}" stroke-width="7" stroke-linejoin="round"/>
    <path d="M1,-2 C10,8 17,16 15,27 C13,36 7,40 0,40 C-8,40 -14,34 -14,26 C-14,15 -5,10 1,-2 Z"
          fill="{core}"/>"""


def star(colour="#FFC400"):
    pts = []
    for i in range(10):
        r = 46 if i % 2 == 0 else 21
        a = -math.pi / 2 + i * math.pi / 5
        pts.append(f"{r * math.cos(a):.1f},{r * math.sin(a):.1f}")
    return (f'<polygon points="{" ".join(pts)}" fill="{colour}" stroke="{INK}" stroke-width="7" '
            'stroke-linejoin="round"/>')


def cue(colour):
    """A cue stick across the disc, its butt in `colour`."""
    return f"""
    <g transform="rotate(-45)" stroke="{INK}" stroke-width="7" stroke-linejoin="round">
      <path d="M-56,-13 H-4 V13 H-56 C-64,13 -68,7 -68,0 C-68,-7 -64,-13 -56,-13 Z" fill="{colour}"/>
      <path d="M-4,-13 L52,-8 V8 L-4,13 Z" fill="#F1D3A1"/>
      <rect x="52" y="-8" width="14" height="16" rx="3" fill="#3B9BFF"/>
    </g>"""


def crossed_cues(colour):
    return (f'<g transform="scale(0.92)"><g transform="rotate(90)">{cue(colour)}</g>{cue(colour)}</g>')


def pocket():
    """A ball dropping into a pocket."""
    return f"""
    <path d="M-44,16 C-44,46 44,46 44,16 Z" fill="{INK}" stroke="{INK}" stroke-width="7" stroke-linejoin="round"/>
    <ellipse cx="0" cy="16" rx="44" ry="12" fill="#22A35A" stroke="{INK}" stroke-width="7"/>
    <ellipse cx="0" cy="18" rx="30" ry="7" fill="{INK}"/>
    <circle cx="0" cy="-16" r="22" fill="#FFFFFF" stroke="{INK}" stroke-width="7"/>
    <path d="M-34,-44 L-24,-30 M0,-58 V-46 M34,-44 L24,-30" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>"""


def table():
    """A little pool table from above."""
    pockets = "".join(f'<circle cx="{x}" cy="{y}" r="7" fill="{INK}"/>'
                      for x in (-40, 0, 40) for y in (-24, 24))
    return f"""
    <rect x="-50" y="-34" width="100" height="68" rx="12" fill="#9C5B2E" stroke="{INK}" stroke-width="7"/>
    <rect x="-38" y="-22" width="76" height="44" rx="4" fill="#22A35A"/>
    {pockets}
    <circle cx="-12" cy="2" r="7" fill="#FFFFFF" stroke="{INK}" stroke-width="3"/>
    <circle cx="14" cy="-4" r="7" fill="#FFC928" stroke="{INK}" stroke-width="3"/>"""


def cash():
    """A bill with a coin-round middle."""
    return f"""
    <rect x="-50" y="-30" width="100" height="60" rx="8" fill="#3DD66B" stroke="{INK}" stroke-width="7"/>
    <rect x="-38" y="-18" width="76" height="36" rx="5" fill="none" stroke="#1F8A3E" stroke-width="5"/>
    <circle cx="0" cy="0" r="14" fill="#1F8A3E"/>"""


def three_balls():
    """A team: three balls together."""
    balls = (("#E0464E", -26, 14), ("#3B9BFF", 26, 14), ("#FFC928", 0, -28))
    return "".join(f'<circle cx="{x}" cy="{y}" r="27" fill="{c}" stroke="{INK}" stroke-width="7"/>'
                   f'<circle cx="{x}" cy="{y}" r="10" fill="#FFFFFF"/>' for c, x, y in balls)


def bolt():
    return (f'<path d="M10,-50 L-30,6 H-4 L-14,50 L30,-10 H4 Z" fill="#FFD23F" stroke="{INK}" '
            'stroke-width="7" stroke-linejoin="round"/>')


def crown(colour="#FFC400"):
    return f"""
    <path d="M-46,30 L-50,-24 L-24,0 L0,-36 L24,0 L50,-24 L46,30 Z" fill="{colour}" stroke="{INK}"
          stroke-width="7" stroke-linejoin="round"/>
    <circle cx="0" cy="10" r="8" fill="#E0464E" stroke="{INK}" stroke-width="4"/>
    <circle cx="-26" cy="14" r="6" fill="#3B9BFF" stroke="{INK}" stroke-width="4"/>
    <circle cx="26" cy="14" r="6" fill="#3B9BFF" stroke="{INK}" stroke-width="4"/>"""


def crown_beat():
    """The owner's crown knocked off: tilted, with a hit star."""
    return f"""<g transform="translate(6,8) rotate(-24) scale(0.86)">{crown()}</g>
    <g transform="translate(-36,-34) scale(0.42)">{star("#FFFFFF")}</g>"""


def broom():
    return f"""
    <g transform="rotate(-40)" stroke="{INK}" stroke-width="7" stroke-linejoin="round">
      <rect x="-60" y="-6" width="74" height="12" rx="6" fill="#9C5B2E"/>
      <path d="M12,-10 L56,-26 C62,-8 62,8 56,26 L12,10 Z" fill="#F2C14E"/>
      <path d="M12,-12 V12" stroke-width="9"/>
    </g>
    <circle cx="-38" cy="38" r="8" fill="#B79CFF" stroke="{INK}" stroke-width="4"/>"""


# --- the pieces of a ball -------------------------------------------------------------------

PRISM = "prism"  # the Mythic shimmer as a flat gradient (UI_STYLE section 4)
RAINBOW = "rainbow"  # Reyes' VIP rainbow
FILLS = {PRISM: ("url(#prism)", "#9A86D9"), RAINBOW: ("url(#rainbow)", "#B0507A")}


def defs():
    return f"""<defs><clipPath id="ball"><circle cx="{C}" cy="{C}" r="{BALL_R}"/></clipPath>
    <linearGradient id="prism" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#7FE7FF"/><stop offset="0.5" stop-color="#B79CFF"/>
      <stop offset="1" stop-color="#FF9CE6"/></linearGradient>
    <linearGradient id="rainbow" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#FF4D4D"/><stop offset="0.2" stop-color="#FFA41B"/>
      <stop offset="0.4" stop-color="#FFE14D"/><stop offset="0.6" stop-color="#3DD66B"/>
      <stop offset="0.8" stop-color="#3B9BFF"/><stop offset="1" stop-color="#A259FF"/></linearGradient>
    </defs>"""


def fill_of(colour):
    """(lit fill, shade fill) for a hex colour or a gradient name."""
    if colour in FILLS:
        return FILLS[colour]
    return colour, (PALE if colour == WHITE else shade(colour, 0.8))


def ball_body(colour, stripe=None):
    """A solid ball in `colour`, or (stripe set) a white ball with a `stripe` band."""
    lit, dark = fill_of(WHITE if stripe else colour)
    out = [f'<g clip-path="url(#ball)">',
           # one cel step: the dark shade, then the lit colour offset up-left over it
           f'<circle cx="{C}" cy="{C}" r="{BALL_R}" fill="{dark}"/>',
           f'<circle cx="{C - 16}" cy="{C - 18}" r="{BALL_R - 6}" fill="{lit}"/>']
    if stripe:
        band_lit, band_dark = fill_of(stripe)
        band = 128  # half the band's height
        out.append(f'<rect x="0" y="{C - band}" width="{SIZE}" height="{band * 2}" fill="{band_dark}"/>')
        out.append(f'<clipPath id="lit"><circle cx="{C - 16}" cy="{C - 18}" r="{BALL_R - 6}"/></clipPath>')
        out.append(f'<rect x="0" y="{C - band}" width="{SIZE}" height="{band * 2}" fill="{band_lit}" clip-path="url(#lit)"/>')
        out.append(f'<path d="M0,{C - band} H{SIZE} M0,{C + band} H{SIZE}" stroke="{INK}" stroke-width="8"/>')
    out.append("</g>")
    return "\n".join(out)


def shine():
    return f"""
    <ellipse cx="{C - 92}" cy="{C - 112}" rx="54" ry="26" fill="#FFFFFF" opacity="0.9"
             transform="rotate(-38 {C - 92} {C - 112})"/>
    <circle cx="{C - 150}" cy="{C - 50}" r="11" fill="#FFFFFF" opacity="0.9"/>"""


def rim():
    return f'<circle cx="{C}" cy="{C}" r="{BALL_R}" fill="none" stroke="{INK}" stroke-width="{OUTLINE}"/>'


def disc(r=124):
    return f"""
    <circle cx="{C}" cy="{C}" r="{r}" fill="{PALE}"/>
    <circle cx="{C - 7}" cy="{C - 8}" r="{r - 6}" fill="#FFFFFF"/>
    <circle cx="{C}" cy="{C}" r="{r}" fill="none" stroke="{INK}" stroke-width="9"/>"""


def numeral(text, y, size):
    return (f'<text x="{C}" y="{y}" font-family="Fredoka" font-size="{size}" text-anchor="middle" '
            f'fill="{INK}">{text}</text>')


def disc_content(num=None, symbol=None):
    """The disc's inside: a numeral, a symbol, or a small symbol over a numeral."""
    if num and symbol:
        size = {1: 116, 2: 106, 3: 86}.get(len(num), 76)
        return (f'<g transform="translate({C},{C - 56}) scale(0.98)">{symbol}</g>'
                + numeral(num, C + 84, size))
    if num:
        size = {1: 170, 2: 140, 3: 104}.get(len(num), 86)
        return numeral(num, C + size * 0.36, size)
    return f'<g transform="translate({C},{C + 2}) scale(1.7)">{symbol}</g>'


def pool_ball(colour, num=None, symbol=None, stripe=None):
    return "\n".join([defs(), ball_body(colour, stripe), disc(), disc_content(num, symbol), shine(), rim()])


def eight_ball():
    return pool_ball("#2B2F45", num="8")


def pumpkin(crowned=False):
    """The Halloween ball: a pumpkin-orange ball, ridges, a stem and a carved face; the Pumpkin
    King's wears a crown in place of the stem."""
    orange = "#FF8A1F"
    ridges = "".join(
        f'<ellipse cx="{C}" cy="{C}" rx="{rx}" ry="{BALL_R + 10}" fill="none" stroke="{shade(orange, 0.78)}" stroke-width="9"/>'
        for rx in (70, 150))
    face = f"""
    <g stroke="{INK}" stroke-width="8" stroke-linejoin="round" fill="{INK}">
      <polygon points="{C - 104},{C - 2} {C - 26},{C - 2} {C - 65},{C - 76}"/>
      <polygon points="{C + 26},{C - 2} {C + 104},{C - 2} {C + 65},{C - 76}"/>
      <path d="M{C - 122},{C + 38} Q{C},{C + 90} {C + 122},{C + 38}
               L{C + 98},{C + 114} L{C + 62},{C + 98} L{C + 40},{C + 130} L{C},{C + 110}
               L{C - 40},{C + 130} L{C - 62},{C + 98} L{C - 98},{C + 114} Z"/>
    </g>"""
    top = C - BALL_R
    stem = f"""
    <path d="M{C - 22},{top + 26} C{C - 24},{top - 6} {C - 8},{top - 34} {C + 20},{top - 40}
             C{C + 30},{top - 42} {C + 36},{top - 30} {C + 28},{top - 22} C{C + 14},{top - 12} {C + 18},{top + 4} {C + 20},{top + 26} Z"
          fill="#3FA34D" stroke="{INK}" stroke-width="9" stroke-linejoin="round"/>"""
    if crowned:
        stem = f'<g transform="translate({C},{top + 12}) scale(1.25)">{crown()}</g>'
    body = "\n".join([ball_body(orange), f'<g clip-path="url(#ball)">{ridges}</g>', face, shine(), rim(), stem])
    # a little smaller and lower than a ball, so the stem stays inside the circle crop
    return f'{defs()}<g transform="translate({C},{C + 14}) scale(0.92) translate({-C},{-C})">{body}</g>'


def rank_disc(key, ring):
    """A rank emblem on a light disc with the tier's ring (the old dark disc was off)."""
    with open(os.path.join(RANK_DIR, RANK_FILES[key]), "rb") as handle:
        data = base64.b64encode(handle.read()).decode()
    box = 330
    return f"""{defs()}
    <circle cx="{C}" cy="{C}" r="{BALL_R}" fill="{ring}"/>
    <circle cx="{C}" cy="{C}" r="{BALL_R - 30}" fill="{PALE}"/>
    <circle cx="{C - 8}" cy="{C - 10}" r="{BALL_R - 40}" fill="#FFFFFF"/>
    <circle cx="{C}" cy="{C}" r="{BALL_R - 30}" fill="none" stroke="{INK}" stroke-width="8"/>
    <image href="data:image/png;base64,{data}" x="{C - box / 2}" y="{C - box / 2 - 4}" width="{box}" height="{box}"
           preserveAspectRatio="xMidYMid meet"/>
    <ellipse cx="{C - 120}" cy="{C - 140}" rx="34" ry="14" fill="#FFFFFF" opacity="0.8"
             transform="rotate(-40 {C - 120} {C - 140})"/>
    {rim()}"""


RANK_FILES = {
    "RankBronze": "bronze_1.png", "RankSilver": "silver_1.png", "RankGold": "gold_1.png",
    "RankPlatinum": "platinum_1.png", "RankDiamond": "diamond_1.png", "RankExpert": "expert_1.png",
    "RankVeteran": "veteran_1.png", "RankMaster": "master_1.png",
    "RankGrandmaster": "grandmaster_1.png", "RankReyes": "reyes.png",
}
# Each tier's colour (Config's rank Colors); Grandmaster's gold, as its black would vanish
RANK_RINGS = {
    "RankBronze": "#CD7F46", "RankSilver": "#AAB6C8", "RankGold": "#FFC428", "RankPlatinum": "#78B0E6",
    "RankDiamond": "#3CD6E6", "RankExpert": "#E84048", "RankVeteran": "#40C460", "RankMaster": "#9E5CE6",
    "RankGrandmaster": "#FFC428", "RankReyes": RAINBOW,
}

GOLD = "#F2B200"
BRONZE = "#D9883C"
SILVER = "#B8C2CF"
ORANGE = "#FF7A1A"  # the 5 ball
TEAL = "#14B8A6"
GREEN = "#22A35A"  # the 6 ball
BLUE = "#2F6FE0"  # the 2 ball
RED = "#E0464E"  # the 3 ball
INDIGO = "#5B5BFF"
RARITY = {"Rare": "#3B9BFF", "Epic": "#A259FF", "Legendary": "#F2B200", "Mythic": PRISM,
          "Secret": "#2A2230", "Unique": "#FF5CB8"}
CUE_BUTT = {"Mythic": "#B79CFF", "Secret": "#FF283C"}


def wins(num, band):
    return lambda: pool_ball(band, num=num, symbol=trophy(GOLD if band in FILLS else band), stripe=band)


def rarity(name):
    return lambda: pool_ball(RARITY[name], symbol=cue(CUE_BUTT.get(name, RARITY[name])))


# Key -> a function that returns the icon's SVG body, in Config.Badges order
BADGES = {
    "Welcome": eight_ball,
    "FirstWin": lambda: pool_ball("#FFC928", num="1", symbol=trophy(GOLD)),
    "Wins5": wins("5", BRONZE),
    "Wins10": wins("10", BRONZE),
    "Wins25": wins("25", SILVER),
    "Wins50": wins("50", SILVER),
    "Wins100": wins("100", GOLD),
    "Wins250": wins("250", GOLD),
    "Wins500": wins("500", PRISM),
    "Wins1000": wins("1K", PRISM),
    **{key: (lambda k=key: rank_disc(k, RANK_RINGS[k])) for key in RANK_FILES},
    "Streak3": lambda: pool_ball(ORANGE, num="3", symbol=flame()),
    "Streak5": lambda: pool_ball(ORANGE, num="5", symbol=flame()),
    "Streak10": lambda: pool_ball(ORANGE, num="10", symbol=flame()),
    "CueRare": rarity("Rare"),
    "CueEpic": rarity("Epic"),
    "CueLegendary": rarity("Legendary"),
    "CueMythic": rarity("Mythic"),
    "CueSecret": rarity("Secret"),
    "CueUnique": rarity("Unique"),
    "Cues5": lambda: pool_ball(TEAL, num="5", symbol=crossed_cues(TEAL), stripe=TEAL),
    "Cues10": lambda: pool_ball(TEAL, num="10", symbol=crossed_cues(TEAL), stripe=TEAL),
    "Cues25": lambda: pool_ball(TEAL, num="25", symbol=crossed_cues(TEAL), stripe=TEAL),
    "Cues50": lambda: pool_ball(TEAL, num="50", symbol=crossed_cues(TEAL), stripe=TEAL),
    "Balls100": lambda: pool_ball(GREEN, num="100", symbol=pocket(), stripe=GREEN),
    "Balls1000": lambda: pool_ball(GREEN, num="1K", symbol=pocket(), stripe=GREEN),
    "Balls10000": lambda: pool_ball(GREEN, num="10K", symbol=pocket(), stripe=GREEN),
    "Matches10": lambda: pool_ball(BLUE, num="10", symbol=table(), stripe=BLUE),
    "Matches100": lambda: pool_ball(BLUE, num="100", symbol=table(), stripe=BLUE),
    "Matches1000": lambda: pool_ball(BLUE, num="1K", symbol=table(), stripe=BLUE),
    "Nice10": lambda: pool_ball(RED, num="10", symbol=star(), stripe=RED),
    "Nice100": lambda: pool_ball(RED, num="100", symbol=star(), stripe=RED),
    "Money1M": lambda: pool_ball("#2FBF4F", num="1M", symbol=cash()),
    "Squad": lambda: pool_ball("#22C1E6", symbol=three_balls()),
    "Ability1": lambda: pool_ball(INDIGO, symbol=bolt()),
    "Ability100": lambda: pool_ball(INDIGO, num="100", symbol=bolt(), stripe=INDIGO),
    "MetOwner": lambda: pool_ball("#7B4BD6", symbol=crown()),
    "BeatOwner": lambda: pool_ball("#FF3B5C", symbol=crown_beat()),
    "Halloween2026": pumpkin,
    "PumpkinSlayer": lambda: pumpkin(crowned=True),
    "BroomRider": lambda: pool_ball("#5B2A86", symbol=broom()),
}
assert len(BADGES) == 50


def page(body):
    return f"""<!doctype html><html><head><style>
@font-face {{ font-family: Fredoka; src: url("file://{FREDOKA}"); }}
html, body {{ margin: 0; background: transparent; }}
</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
{body}
</svg></body></html>"""


def render(body, out):
    """One SVG page to a 512 px PNG through headless Chrome, clipped to Roblox's safe circle."""
    with tempfile.TemporaryDirectory() as tmp:
        html = os.path.join(tmp, "icon.html")
        with open(html, "w") as handle:
            handle.write(page(body))
        shot = os.path.join(tmp, "icon.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--allow-file-access-from-files", "--default-background-color=00000000",
                        f"--window-size={SIZE},{SIZE}", f"--screenshot={shot}", "file://" + html],
                       check=True, capture_output=True)
        img = Image.open(shot).convert("RGBA")
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse([C - SAFE_RADIUS, C - SAFE_RADIUS, C + SAFE_RADIUS, C + SAFE_RADIUS], fill=255)
    img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    img.save(out, optimize=True)


def compose(key, out_dir=OUT_DIR):
    os.makedirs(out_dir, exist_ok=True)
    render(BADGES[key](), os.path.join(out_dir, key + ".png"))
    return True


def sheet(out, keys, src_dir=OUT_DIR):
    """Every badge at 150 px in a circle (how the game page shows them), with its key, on
    Roblox's light and dark page colours."""
    cols = min(8, len(keys))
    cell = 170
    rows = math.ceil(len(keys) / cols)
    band = rows * (cell + 22)
    img = Image.new("RGBA", (cols * cell, band * 2), (255, 255, 255, 255))
    ImageDraw.Draw(img).rectangle([0, band, cols * cell, band * 2], fill=(25, 27, 29, 255))
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 12)
    mask = Image.new("L", (150, 150), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 149, 149], fill=255)
    for half, text_fill in ((0, (40, 44, 60, 255)), (1, (220, 222, 228, 255))):
        for i, key in enumerate(keys):
            path = os.path.join(src_dir, key + ".png")
            if not os.path.exists(path):
                continue
            icon = Image.open(path).convert("RGBA").resize((150, 150), Image.LANCZOS)
            icon.putalpha(ImageChops.multiply(icon.getchannel("A"), mask))
            x = (i % cols) * cell + 10
            y = half * band + (i // cols) * (cell + 22) + 8
            img.alpha_composite(icon, (x, y))
            tw = draw.textlength(key, font=font)
            draw.text((x + 75 - tw / 2, y + 154), key, font=font, fill=text_fill)
    img.save(out)
    print("wrote", out)


def badge_list(out):
    """Every badge in registry order: its icon, name and description (tools/export_badges.luau)."""
    import json
    rows = json.loads(subprocess.run(["lune", "run", "tools/export_badges.luau"], cwd=ROOT,
                                     capture_output=True, text=True, check=True).stdout)["rows"]
    cols, row_h, col_w = 2, 84, 760
    per_col = math.ceil(len(rows) / cols)
    img = Image.new("RGBA", (cols * col_w + 20, per_col * row_h + 70), (246, 247, 251, 255))
    draw = ImageDraw.Draw(img)
    bold = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 24)
    small = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 19)
    title = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Black.ttf", 30)
    draw.text((20, 14), f"Crazy 8 Ball badges ({len(rows)})", font=title, fill=(27, 32, 51, 255))
    mask = Image.new("L", (72, 72), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 71, 71], fill=255)
    for i, row in enumerate(rows):
        x = 20 + (i // per_col) * col_w
        y = 64 + (i % per_col) * row_h
        path = os.path.join(ROOT, row["icon"])
        if os.path.exists(path):
            icon = Image.open(path).convert("RGBA").resize((72, 72), Image.LANCZOS)
            icon.putalpha(ImageChops.multiply(icon.getchannel("A"), mask))
            img.alpha_composite(icon, (x, y))
        draw.text((x + 86, y + 8), f"{i + 1}. {row['name']}", font=bold, fill=(27, 32, 51, 255))
        draw.text((x + 86, y + 42), row["description"], font=small, fill=(70, 76, 96, 255))
    img.save(out)
    print("wrote", out)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compose", nargs="*", default=None, help="badge keys (default all)")
    parser.add_argument("--out-dir", default=OUT_DIR, help="where --compose writes (default assets/ui/badges)")
    parser.add_argument("--sheet", nargs="+", default=None, help="out.png [keys...]")
    parser.add_argument("--list", default=None, help="out.png: the badge list with names")
    args = parser.parse_args()
    if args.compose is not None:
        for key in args.compose or list(BADGES):
            compose(key, args.out_dir)
    if args.sheet:
        out, keys = args.sheet[0], args.sheet[1:] or list(BADGES)
        sheet(out, keys, args.out_dir)
    if args.list:
        badge_list(args.list)
    return 0


if __name__ == "__main__":
    sys.exit(main())
