#!/usr/bin/env python3
"""The Halloween menu's "Haunted night" background pieces (designer's pick, 2026-10-29: deep
purple fading darker toward the bottom, a soft glowing moon behind the header, a few small bats
and faint stars drifting, an orange-glow edge). Flat vector art in the game's style, drawn as SVG
and rendered with headless Chrome like tools/gui/hw_emblem.py (no generated art: the designer
rejected AI-look art, 2026-10-28). The purple itself is two UIGradients (no picture); these are
the pieces on it, each sized to how big it shows (Config.UI.Menu.Themes.HauntedNight):

    NightMoon.png  192 x 192  the moon (a 92 px disc) with its soft glow baked in; shows 60-110 px
    NightBat.png    96 x 48   a small bat (wings spread, orange eyes); shows 18-34 px wide
    NightStar.png   32 x 32   a white four-point twinkle, tinted in the game; shows 6-14 px
    NightEdge.png   96 x 96   the sheet's orange inner glow, 9-sliced (corners 40 texels, the
                              sheet's 22 px curve at SliceScale 1)

    python3 tools/gui/hw_night.py            # into assets/ui/halloween/
    python3 tools/gui/hw_night.py --sheet D  # also a preview of the pieces on the purple (D/)

Upload: tools/roblox_upload.py --group-id 675425213 --list <file> (Image assets: the asset id is
the image id), ids into Config.UI.Menu.Themes.HauntedNight.Images.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "ui", "halloween")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
INK = "#1B2033"  # UI_STYLE's ink outline


def moon():
    # A cream disc, lit from the top left, three soft craters, and a warm glow fading out.
    s, c, r = 192, 96, 46
    return s, s, f"""
<defs>
  <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
    <stop offset="{r / c:.3f}" stop-color="#FFE7A6" stop-opacity="0.62"/>
    <stop offset="0.66" stop-color="#FFD982" stop-opacity="0.22"/>
    <stop offset="1" stop-color="#FFD982" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="disc" cx="0.38" cy="0.34" r="0.75">
    <stop offset="0" stop-color="#FFFBEA"/>
    <stop offset="0.62" stop-color="#FFF0C2"/>
    <stop offset="1" stop-color="#F6DC98"/>
  </radialGradient>
  <clipPath id="d"><circle cx="{c}" cy="{c}" r="{r}"/></clipPath>
</defs>
<circle cx="{c}" cy="{c}" r="{c}" fill="url(#glow)"/>
<circle cx="{c}" cy="{c}" r="{r}" fill="url(#disc)"/>
<g clip-path="url(#d)">
  <circle cx="{c + 34}" cy="{c + 30}" r="{r}" fill="#EBCB7E" opacity="0.32"/>
  <circle cx="{c + 14}" cy="{c - 12}" r="11" fill="#EED38E" opacity="0.75"/>
  <circle cx="{c - 16}" cy="{c + 16}" r="7.5" fill="#EED38E" opacity="0.7"/>
  <circle cx="{c + 6}" cy="{c + 26}" r="5" fill="#EED38E" opacity="0.65"/>
  <circle cx="{c - 20}" cy="{c - 20}" r="4" fill="#FFFFFF" opacity="0.7"/>
</g>
"""


def bat():
    # Drawn in a 200 x 100 box, shown at 96 x 48: chunky V wings with deep scallops (a thin
    # wing reads as a line at 20-30 px), a round head with pointed ears, near-black purple with a
    # lilac rim (it reads on the deep purple and over the moon), two small orange eyes.
    w, h = 96, 48
    body = "#1D0C33"
    rim = "#8A5CD6"
    wing = ("M106,50 C124,30 152,14 196,6 C194,26 188,44 180,60 "
            "Q168,52 158,66 Q148,56 136,74 Q126,64 114,80 L104,70 Z")
    return w, h, f"""
<g transform="scale({w / 200})">
  <g fill="{body}" stroke="{rim}" stroke-width="5" stroke-linejoin="round">
    <path d="{wing}"/>
    <path d="{wing}" transform="translate(200,0) scale(-1,1)"/>
    <path d="M86,40 L86,16 L97,30 L103,30 L114,16 L114,40 C118,56 112,82 100,88
             C88,82 82,56 86,40 Z"/>
  </g>
  <circle cx="94" cy="42" r="4.2" fill="#FFB238"/>
  <circle cx="106" cy="42" r="4.2" fill="#FFB238"/>
</g>
"""


def star():
    # A white four-point twinkle with a soft white halo (tinted in the game).
    s = 32
    return s, s, f"""
<defs>
  <radialGradient id="h" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.7"/>
    <stop offset="0.45" stop-color="#FFFFFF" stop-opacity="0.16"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </radialGradient>
</defs>
<circle cx="16" cy="16" r="16" fill="url(#h)"/>
<path d="M16,2 Q17.6,14.4 30,16 Q17.6,17.6 16,30 Q14.4,17.6 2,16 Q14.4,14.4 16,2 Z" fill="#FFFFFF"/>
"""


def edge():
    # The sheet's inner glow: orange along a 22 px rounded rectangle's inside, fading inward
    # about 18 px; clear in the middle (9-sliced: SliceCenter 40..56).
    s, r = 96, 22
    return s, s, f"""
<defs>
  <clipPath id="c"><rect x="0" y="0" width="{s}" height="{s}" rx="{r}"/></clipPath>
  <filter id="b" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>
</defs>
<g clip-path="url(#c)">
  <rect x="0" y="0" width="{s}" height="{s}" rx="{r}" fill="none" stroke="#FF8A1E"
        stroke-width="16" filter="url(#b)" opacity="0.95"/>
  <rect x="0" y="0" width="{s}" height="{s}" rx="{r}" fill="none" stroke="#FFB24A"
        stroke-width="5" filter="url(#b)" opacity="0.7"/>
</g>
"""


PIECES = {"NightMoon": moon, "NightBat": bat, "NightStar": star, "NightEdge": edge}


def page(w, h, body):
    return f"""<!doctype html><html><head><style>
html, body {{ margin: 0; background: transparent; }}
</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
{body}
</svg></body></html>"""


def render(w, h, body, out):
    with tempfile.TemporaryDirectory() as tmp:
        html = os.path.join(tmp, "piece.html")
        with open(html, "w") as handle:
            handle.write(page(w, h, body))
        shot = os.path.join(tmp, "piece.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--force-device-scale-factor=1", "--default-background-color=00000000",
                        f"--window-size={w},{h}", f"--screenshot={shot}", "file://" + html],
                       check=True, capture_output=True)
        img = Image.open(shot).convert("RGBA").crop((0, 0, w, h))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, optimize=True)
    return img


def preview(images, folder):
    # The pieces on the theme's purple, at about the size they show, for a look before upload.
    w, h = 900, 360
    sky = Image.new("RGBA", (w, h))
    top, bottom = (74, 33, 140), (22, 9, 44)
    for y in range(h):
        t = y / (h - 1)
        row = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,)
        for x in range(w):
            sky.putpixel((x, y), row)
    sky.alpha_composite(images["NightMoon"].resize((110, 110)), (520, 10))
    for i, (x, y, px) in enumerate([(120, 40, 34), (300, 90, 24), (600, 60, 28)]):
        bat_img = images["NightBat"].resize((px, px // 2))
        sky.alpha_composite(bat_img, (x, y))
    for x, y, px in [(60, 30, 12), (230, 70, 8), (420, 25, 10), (720, 110, 9), (820, 40, 13)]:
        sky.alpha_composite(images["NightStar"].resize((px, px)), (x, y))
    glow = images["NightEdge"]
    frame = Image.new("RGBA", (w - 40, 180))
    # a quick 9-slice of the edge glow
    c = 40
    fw, fh = frame.size
    for (sx0, sx1, dx0, dx1) in [(0, c, 0, c), (c, 96 - c, c, fw - c), (96 - c, 96, fw - c, fw)]:
        for (sy0, sy1, dy0, dy1) in [(0, c, 0, c), (c, 96 - c, c, fh - c), (96 - c, 96, fh - c, fh)]:
            part = glow.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0))
            frame.alpha_composite(part, (dx0, dy0))
    sky.alpha_composite(frame, (20, 160))
    path = os.path.join(folder, "night_preview.png")
    os.makedirs(folder, exist_ok=True)
    sky.save(path)
    return path


def main():
    images = {}
    for name, make in PIECES.items():
        w, h, body = make()
        out = os.path.join(OUT, name + ".png")
        images[name] = render(w, h, body, out)
        print(out, images[name].size)
    if "--sheet" in sys.argv:
        print(preview(images, sys.argv[sys.argv.index("--sheet") + 1]))


if __name__ == "__main__":
    main()
