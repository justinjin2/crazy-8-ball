#!/usr/bin/env python3
"""The game's 52 Roblox badge icons (hw-sys lane, 2026-10-28; HW_SYS_PROMPT section 2.3).

    python3 tools/gen_badge_icons.py --gen trophy_gold cue_epic ...   generate those motifs
    python3 tools/gen_badge_icons.py --gen-all                         every motif not made yet
    python3 tools/gen_badge_icons.py --compose [Key ...]               assets/ui/badges/<Key>.png
    python3 tools/gen_badge_icons.py --sheet out.png [Key ...]         contact sheet, 150 px circles
    python3 tools/gen_badge_icons.py --list out.png                    the 52: icon, name, how (Strings)

One look for all of them: a glossy cartoon motif (UI_STYLE sections 1 and 6: chunky shapes, a
thick ink outline, a shine, a small drop lip, no words) generated once per motif by
tools/openai_image.py and kept outside git (RAW_DIR), set on one shared round frame drawn here
with one ring colour per family. Roblox crops a badge to a circle, so everything sits inside a
460 px circle of the 512 px canvas. Milestone badges add a bold numeral drawn here (it reads at
150 px). The rank badges reuse the rank emblems (assets/ui/ranks/<tier>_1.png, reyes.png): no
generation.
"""

import argparse
import math
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "ui", "badges")
RANK_DIR = os.path.join(ROOT, "assets", "ui", "ranks")
RAW_DIR = os.path.expanduser("~/Desktop/8ball-refs/halloween/badges_raw")
SIZE = 512
CENTER = SIZE / 2
SAFE_RADIUS = 230  # Roblox's circle crop: keep everything inside a 460 px circle
RING_OUTER = 226
RING_WIDTH = 24
INK = (27, 32, 51, 255)  # #1B2033, UI_STYLE's ink outline
FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"

STYLE = (
    "A single glossy cartoon mobile-game icon of {subject}. Chunky rounded shapes, a thick dark "
    "navy ink outline (#1B2033) around every shape, bright saturated colours, soft cel shading, "
    "a crisp white shine highlight on the upper left, a small darker drop lip along the bottom "
    "edge. The whole object is centred and fully visible with a generous empty margin all "
    "round. No text, no letters, no numbers, no frame, no badge, no circle behind it, no "
    "ground shadow: only the object on a fully transparent background."
)

# motif -> what is drawn (one generation each; several badges share a motif)
MOTIFS = {
    "welcome": "a night city rooftop with a big glossy black 8 ball sitting on it, purple sky glow behind the rooftop edge",
    "trophy_bronze": "a chunky bronze trophy cup with two handles and a little 8 ball on its lid",
    "trophy_silver": "a chunky shiny silver trophy cup with two handles and a little 8 ball on its lid",
    "trophy_gold": "a chunky shiny gold trophy cup with two handles and a little 8 ball on its lid",
    "trophy_prism": "a chunky crystal trophy cup with two handles, holographic rainbow pastel shimmer, sparkles, a little 8 ball on its lid",
    "trophy_first": "a chunky gold trophy cup with two handles, a blue ribbon bow tied on it and confetti bits round it",
    "flame": "a big fiery cartoon flame, orange and yellow, wrapped round a glossy black 8 ball",
    "cue_rare": "a pool cue stick crossed diagonally behind a glossy 8 ball, the cue glowing bright blue (#3B9BFF) with small blue sparkles",
    "cue_epic": "a pool cue stick crossed diagonally behind a glossy 8 ball, the cue glowing vivid purple (#A259FF) with small purple sparkles",
    "cue_legendary": "a pool cue stick crossed diagonally behind a glossy 8 ball, the cue shining gold (#F2B200) with golden rays and sparkles",
    "cue_mythic": "a pool cue stick crossed diagonally behind a glossy 8 ball, the cue pale holographic pastel cyan, lilac and pink with twinkling white stars",
    "cue_secret": "a pool cue stick crossed diagonally behind a glossy 8 ball, the cue near-black with a glitchy red (#FF283C) and white shimmer",
    "cue_unique": "a pool cue stick crossed diagonally behind a glossy 8 ball, the cue hot pink (#FF5CB8) with a single star charm and pink sparkles",
    "rack": "a wooden wall rack holding five colourful pool cue sticks standing upright side by side",
    "pocket": "a pool ball dropping into a pool table's corner pocket with a little motion swoosh, green cloth and brown wood rail",
    "table": "a small chunky green pool table seen from a three-quarter angle with a few colourful balls on it",
    "star": "a big golden star burst with a white sparkle and a little 8 ball in its centre",
    "cash": "a fat stack of green paper cash bills with a paper band round the middle",
    "squad": "three glossy pool balls side by side like a team, a blue one, a red one and a black 8 ball, two crossed cue sticks behind them",
    "bolt": "a big glowing yellow lightning bolt with electric blue sparks",
    "crown": "a chunky shiny gold royal crown with red and blue gems",
    "crown_beat": "a chunky gold royal crown knocked tilted sideways with a pool cue tapping it, little stars of impact",
    "shield": "a blue and white heraldic shield with a glossy black 8 ball in its centre",
    "pumpkin_night": "a glowing carved jack-o'-lantern pumpkin with a crescent moon and purple night sparkles behind it",
    "pumpkin_king": "a carved jack-o'-lantern pumpkin head wearing a spiky gold crown, glowing orange eyes, fierce but kid-friendly",
    "broom": "a witch's broom with a crooked wooden handle, straw bristles and a glowing violet crystal at the tip",
}

PRISM = [(127, 231, 255), (183, 156, 255), (255, 156, 230), (255, 255, 255)]
RAINBOW = [(255, 60, 60), (255, 170, 0), (255, 230, 0), (60, 220, 90), (40, 170, 255), (150, 90, 255)]

# family -> (ring colour or gradient list, disc inner colour, disc outer colour)
FAMILIES = {
    "welcome": ((139, 92, 246), (92, 60, 190), (40, 24, 92)),
    "first": ((59, 155, 255), (52, 66, 120), (16, 22, 48)),
    "bronze": ((205, 127, 50), (60, 62, 100), (18, 20, 40)),
    "silver": ((192, 199, 208), (60, 66, 104), (18, 20, 40)),
    "gold": ((242, 178, 0), (60, 62, 100), (18, 20, 40)),
    "prism": (PRISM, (70, 60, 150), (26, 20, 70)),
    "rank": ((44, 54, 88), (60, 72, 120), (20, 24, 44)),
    "streak": ((255, 106, 26), (200, 70, 20), (80, 20, 10)),
    "rare": ((59, 155, 255), (40, 110, 210), (12, 34, 80)),
    "epic": ((162, 89, 255), (110, 50, 200), (40, 16, 84)),
    "legendary": ((242, 178, 0), (110, 70, 20), (40, 24, 8)),
    "mythic": (PRISM, (60, 50, 140), (26, 20, 70)),
    "secret": ((255, 40, 60), (60, 40, 50), (30, 24, 32)),
    "unique": ((255, 92, 184), (210, 60, 150), (90, 16, 64)),
    "collection": ((20, 184, 166), (14, 130, 120), (6, 50, 48)),
    "balls": ((34, 163, 90), (24, 120, 66), (8, 50, 26)),
    "matches": ((59, 155, 255), (40, 110, 210), (12, 34, 80)),
    "nice": ((255, 196, 0), (50, 80, 170), (14, 24, 60)),
    "money": ((47, 191, 79), (30, 140, 60), (10, 56, 24)),
    "squad": ((34, 193, 230), (20, 140, 180), (6, 50, 70)),
    "ability": ((91, 91, 255), (60, 60, 210), (20, 20, 90)),
    "owner": ((255, 196, 0), (150, 40, 60), (50, 10, 24)),
    "beat": ((255, 59, 92), (200, 40, 70), (80, 12, 28)),
    "crew": ((47, 123, 255), (30, 90, 220), (10, 30, 90)),
    "halloween": ((255, 122, 26), (90, 40, 150), (34, 14, 70)),
}

RANK_FILES = {
    "RankBronze": "bronze_1.png", "RankSilver": "silver_1.png", "RankGold": "gold_1.png",
    "RankPlatinum": "platinum_1.png", "RankDiamond": "diamond_1.png", "RankExpert": "expert_1.png",
    "RankVeteran": "veteran_1.png", "RankMaster": "master_1.png",
    "RankGrandmaster": "grandmaster_1.png", "RankReyes": "reyes.png",
}

# Key -> (family, motif or None for a rank emblem, numeral or None), in Config.Badges order
BADGES = {
    "Welcome": ("welcome", "welcome", None),
    "FirstWin": ("first", "trophy_first", None),
    "Wins5": ("bronze", "trophy_bronze", "5"),
    "Wins10": ("bronze", "trophy_bronze", "10"),
    "Wins25": ("silver", "trophy_silver", "25"),
    "Wins50": ("silver", "trophy_silver", "50"),
    "Wins100": ("gold", "trophy_gold", "100"),
    "Wins250": ("gold", "trophy_gold", "250"),
    "Wins500": ("prism", "trophy_prism", "500"),
    "Wins1000": ("prism", "trophy_prism", "1K"),
    **{key: ("rank", None, None) for key in RANK_FILES},
    "Streak3": ("streak", "flame", "3"),
    "Streak5": ("streak", "flame", "5"),
    "Streak10": ("streak", "flame", "10"),
    "CueRare": ("rare", "cue_rare", None),
    "CueEpic": ("epic", "cue_epic", None),
    "CueLegendary": ("legendary", "cue_legendary", None),
    "CueMythic": ("mythic", "cue_mythic", None),
    "CueSecret": ("secret", "cue_secret", None),
    "CueUnique": ("unique", "cue_unique", None),
    "Cues5": ("collection", "rack", "5"),
    "Cues10": ("collection", "rack", "10"),
    "Cues25": ("collection", "rack", "25"),
    "Cues50": ("collection", "rack", "50"),
    "Balls100": ("balls", "pocket", "100"),
    "Balls1000": ("balls", "pocket", "1K"),
    "Balls10000": ("balls", "pocket", "10K"),
    "Matches10": ("matches", "table", "10"),
    "Matches100": ("matches", "table", "100"),
    "Matches1000": ("matches", "table", "1K"),
    "Nice10": ("nice", "star", "10"),
    "Nice100": ("nice", "star", "100"),
    "Money1M": ("money", "cash", "1M"),
    "Money10M": ("money", "cash", "10M"),
    "Squad": ("squad", "squad", None),
    "Ability1": ("ability", "bolt", None),
    "Ability100": ("ability", "bolt", "100"),
    "Crew": ("crew", "shield", None),
    "MetOwner": ("owner", "crown", None),
    "BeatOwner": ("beat", "crown_beat", None),
    "Halloween2026": ("halloween", "pumpkin_night", None),
    "PumpkinSlayer": ("halloween", "pumpkin_king", None),
    "BroomRider": ("halloween", "broom", None),
}
assert len(BADGES) == 52


def raw_path(motif):
    return os.path.join(RAW_DIR, motif + ".png")


def generate(motif):
    """One motif through tools/openai_image.py (1024, transparent, high), kept outside git."""
    os.makedirs(RAW_DIR, exist_ok=True)
    cmd = [sys.executable, os.path.join(ROOT, "tools", "openai_image.py"),
           "--prompt", STYLE.format(subject=MOTIFS[motif]), "--out", raw_path(motif),
           "--size", "1024x1024", "--background", "transparent", "--quality", "high",
           "--tag", "badge_" + motif]
    print("generating", motif, flush=True)
    return subprocess.run(cmd).returncode


def gradient_ring(colours, size, inner, outer):
    """An RGBA ring whose colour sweeps round through `colours` (the prismatic families)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = size / 2
    n = len(colours)
    for y in range(size):
        for x in range(size):
            dx, dy = x + 0.5 - c, y + 0.5 - c
            d = math.hypot(dx, dy)
            if inner <= d <= outer:
                a = (math.atan2(dy, dx) / (2 * math.pi) + 0.5) * n
                i = int(a) % n
                f = a - int(a)
                c0, c1 = colours[i], colours[(i + 1) % n]
                px[x, y] = tuple(int(c0[k] + (c1[k] - c0[k]) * f) for k in range(3)) + (255,)
    return img


def frame(family):
    """The shared round frame: a radial disc, the family ring with a shine, ink outlines."""
    ring, inner_col, outer_col = FAMILIES[family]
    scale = 4  # draw big, then downscale, for smooth edges
    big = SIZE * scale
    c = big / 2
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    r_out = RING_OUTER * scale
    r_in = (RING_OUTER - RING_WIDTH) * scale
    ink = 7 * scale
    # ink rim behind everything
    draw.ellipse([c - r_out - ink, c - r_out - ink, c + r_out + ink, c + r_out + ink], fill=INK)
    # disc: radial gradient from inner_col (centre) to outer_col (edge)
    disc = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disc)
    steps = 60
    for i in range(steps):
        f = i / (steps - 1)
        r = r_in * (1 - f) + 1
        col = tuple(int(outer_col[k] + (inner_col[k] - outer_col[k]) * f) for k in range(3)) + (255,)
        oy = -r_in * 0.18 * f  # the light centre sits a little high
        dd.ellipse([c - r, c - r + oy, c + r, c + r + oy], fill=col)
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse([c - r_in, c - r_in, c + r_in, c + r_in], fill=255)
    img.paste(disc, (0, 0), mask)
    # ring
    if isinstance(ring, list):
        ring_img = gradient_ring(ring, SIZE, RING_OUTER - RING_WIDTH, RING_OUTER).resize((big, big), Image.LANCZOS)
        img.alpha_composite(ring_img)
    else:
        ring_mask = Image.new("L", (big, big), 0)
        rm = ImageDraw.Draw(ring_mask)
        rm.ellipse([c - r_out, c - r_out, c + r_out, c + r_out], fill=255)
        rm.ellipse([c - r_in, c - r_in, c + r_in, c + r_in], fill=0)
        solid = Image.new("RGBA", (big, big), ring + (255,))
        img.paste(solid, (0, 0), ring_mask)
        # drop lip: the ring's lower half a shade darker
        lip = Image.new("L", (big, big), 0)
        ImageDraw.Draw(lip).ellipse([c - r_out, c - r_out + 10 * scale, c + r_out, c + r_out + 10 * scale], fill=0)
        dark = Image.new("RGBA", (big, big), tuple(int(v * 0.72) for v in ring) + (255,))
        lower = ImageChops.subtract(ring_mask, Image.new("L", (big, big), 0))
        ImageDraw.Draw(lower).rectangle([0, 0, big, c + r_out * 0.35], fill=0)
        img.paste(dark, (0, 0), lower)
    # shine on the ring's upper left
    shine = Image.new("L", (big, big), 0)
    sd = ImageDraw.Draw(shine)
    sd.arc([c - r_out + 6 * scale, c - r_out + 6 * scale, c + r_out - 6 * scale, c + r_out - 6 * scale],
           200, 290, fill=200, width=7 * scale)
    shine = shine.filter(ImageFilter.GaussianBlur(2 * scale))
    img.paste(Image.new("RGBA", (big, big), (255, 255, 255, 255)), (0, 0), shine)
    # ink line between ring and disc
    draw = ImageDraw.Draw(img)
    draw.ellipse([c - r_in, c - r_in, c + r_in, c + r_in], outline=INK, width=5 * scale)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def fit(img, box):
    """`img` cropped to its content and scaled to fit a box x box square."""
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    w, h = img.size
    k = box / max(w, h)
    return img.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)


def numeral(img, text):
    """A bold white numeral with an ink outline, at the bottom of the disc."""
    draw = ImageDraw.Draw(img)
    size = 104 if len(text) <= 2 else 86
    font = ImageFont.truetype(FONT, size)
    bbox = draw.textbbox((0, 0), text, font=font, stroke_width=12)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = CENTER - w / 2 - bbox[0]
    y = SIZE - 70 - h - bbox[1] - 14
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((x, y + 7), text, font=font, fill=INK, stroke_width=12, stroke_fill=INK)
    img.alpha_composite(shadow)
    draw.text((x, y), text, font=font, fill=(255, 255, 255, 255), stroke_width=12, stroke_fill=INK)


def compose(key):
    family, motif, num = BADGES[key]
    img = frame(family)
    if motif is None:
        art = Image.open(os.path.join(RANK_DIR, RANK_FILES[key])).convert("RGBA")
        art = fit(art, 340)
        oy = -6
    else:
        path = raw_path(motif)
        if not os.path.exists(path):
            print(f"{key}: motif {motif} not generated yet")
            return False
        art = fit(Image.open(path).convert("RGBA"), 300 if num else 330)
        oy = -34 if num else -4
    x = int(CENTER - art.size[0] / 2)
    y = int(CENTER - art.size[1] / 2 + oy)
    img.alpha_composite(art, (x, y))
    if num:
        numeral(img, num)
    # Roblox shows a circle: clear anything past the safe radius
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse([CENTER - SAFE_RADIUS, CENTER - SAFE_RADIUS, CENTER + SAFE_RADIUS, CENTER + SAFE_RADIUS], fill=255)
    alpha = ImageChops.multiply(img.getchannel("A"), mask)
    img.putalpha(alpha)
    os.makedirs(OUT_DIR, exist_ok=True)
    img.save(os.path.join(OUT_DIR, key + ".png"), optimize=True)
    return True


def sheet(out, keys):
    """Every badge at 150 px in a circle (how the game page shows them), with its key."""
    cols = 8
    cell = 170
    rows = math.ceil(len(keys) / cols)
    img = Image.new("RGBA", (cols * cell, rows * (cell + 22)), (238, 240, 246, 255))
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 12)
    mask = Image.new("L", (150, 150), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 149, 149], fill=255)
    for i, key in enumerate(keys):
        path = os.path.join(OUT_DIR, key + ".png")
        if not os.path.exists(path):
            continue
        icon = Image.open(path).convert("RGBA").resize((150, 150), Image.LANCZOS)
        icon.putalpha(ImageChops.multiply(icon.getchannel("A"), mask))
        x = (i % cols) * cell + 10
        y = (i // cols) * (cell + 22) + 8
        img.alpha_composite(icon, (x, y))
        tw = draw.textlength(key, font=font)
        draw.text((x + 75 - tw / 2, y + 154), key, font=font, fill=(40, 44, 60, 255))
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
    parser.add_argument("--gen", nargs="*", default=None, help="motifs to generate")
    parser.add_argument("--gen-all", action="store_true", help="every motif not generated yet")
    parser.add_argument("--compose", nargs="*", default=None, help="badge keys (default all)")
    parser.add_argument("--sheet", nargs="+", default=None, help="out.png [keys...]")
    parser.add_argument("--list", default=None, help="out.png: the badge list with names")
    args = parser.parse_args()
    if args.gen:
        for motif in args.gen:
            generate(motif)
    if args.gen_all:
        for motif in MOTIFS:
            if not os.path.exists(raw_path(motif)):
                generate(motif)
    if args.compose is not None:
        for key in args.compose or list(BADGES):
            compose(key)
    if args.sheet:
        out, keys = args.sheet[0], args.sheet[1:] or list(BADGES)
        sheet(out, keys)
    if args.list:
        badge_list(args.list)
    return 0


if __name__ == "__main__":
    sys.exit(main())
