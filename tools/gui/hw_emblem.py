#!/usr/bin/env python3
"""The "Halloween 2026" emblem (designer, 2026-10-29): a small flat badge for the four
Halloween 2026 event cues' cards (the event menu, My Cues, the Index once owned, the YOU GOT
card). A deep-purple pill with the UI's ink outline, a flat pumpkin poking out of its left end
(one cel-shade step, a carved face, a green stem) and "2026" in Fredoka One with the ink
outline. Drawn as SVG and rendered with headless Chrome (real curves and the font), like
tools/gen_badge_icons.py: no generated art (the designer rejected AI-look icons, 2026-10-28).

    python3 tools/gui/hw_emblem.py            # assets/ui/halloween/Emblem2026.png
    python3 tools/gui/hw_emblem.py --variants # also a sheet of colour variants (scratch)

Upload: tools/roblox_upload.py --force-type Image (its id goes in Config.UI.EventEmblem).
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "ui", "halloween", "Emblem2026.png")
FREDOKA = os.path.expanduser("~/Desktop/8ball-refs/gui-v3/tools/fonts/FredokaOne-Regular.ttf")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 320, 128  # the picture (Config.UI.EventEmblem.Aspect = W / H)
INK = "#1B2033"  # UI_STYLE's ink outline
OUTLINE = 9


def emblem(text_fill="#FFFFFF", pill=("#8A4FD8", "#5A2A99", "#3E1A6E")):
    top, mid, bottom = pill
    # The pill: from just right of the pumpkin's middle to the right end.
    px0, py0, px1, py1 = 52, 26, W - 8, H - 14
    r = (py1 - py0) / 2
    # The pumpkin: round, its left edge near the picture's left edge.
    cx, cy, pr = 60, 70, 47
    ridge = "#D9650C"
    orange = "#FF8A1F"
    light = "#FFB15C"
    return f"""
<defs>
  <linearGradient id="pill" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{top}"/><stop offset="0.55" stop-color="{mid}"/>
    <stop offset="1" stop-color="{bottom}"/>
  </linearGradient>
  <clipPath id="pk"><circle cx="{cx}" cy="{cy}" r="{pr}"/></clipPath>
  <clipPath id="pl"><rect x="{px0}" y="{py0}" width="{px1 - px0}" height="{py1 - py0}" rx="{r}"/></clipPath>
</defs>
<rect x="{px0}" y="{py0}" width="{px1 - px0}" height="{py1 - py0}" rx="{r}" fill="url(#pill)"
      stroke="{INK}" stroke-width="{OUTLINE}"/>
<g clip-path="url(#pl)">
  <rect x="{px0}" y="{py0}" width="{px1 - px0}" height="{(py1 - py0) * 0.34}" fill="#FFFFFF" opacity="0.16"/>
</g>
<rect x="{px0}" y="{py0}" width="{px1 - px0}" height="{py1 - py0}" rx="{r}" fill="none"
      stroke="{INK}" stroke-width="{OUTLINE}"/>
<text x="{(px0 + 58 + px1) / 2 + 2}" y="{cy + 24}" text-anchor="middle"
      font-family="Fredoka" font-size="70" fill="{text_fill}" stroke="{INK}" stroke-width="12"
      stroke-linejoin="round" paint-order="stroke">2026</text>
<path d="M{cx - 6},{cy - pr + 8} C{cx - 8},{cy - pr - 6} {cx + 2},{cy - pr - 16} {cx + 16},{cy - pr - 17}
         C{cx + 24},{cy - pr - 17} {cx + 26},{cy - pr - 9} {cx + 19},{cy - pr - 6}
         C{cx + 12},{cy - pr - 4} {cx + 10},{cy - pr + 2} {cx + 10},{cy - pr + 8} Z"
      fill="#3FA34D" stroke="{INK}" stroke-width="7" stroke-linejoin="round"/>
<circle cx="{cx}" cy="{cy}" r="{pr}" fill="{orange}"/>
<g clip-path="url(#pk)">
  <ellipse cx="{cx + 18}" cy="{cy + 22}" rx="{pr}" ry="{pr}" fill="{ridge}" opacity="0.55"/>
  <ellipse cx="{cx}" cy="{cy}" rx="{pr * 0.42}" ry="{pr + 6}" fill="none" stroke="{ridge}" stroke-width="6"/>
  <ellipse cx="{cx - 20}" cy="{cy - 22}" rx="12" ry="6" fill="{light}" transform="rotate(-35 {cx - 20} {cy - 22})"/>
</g>
<g fill="{INK}" stroke="{INK}" stroke-width="3" stroke-linejoin="round">
  <polygon points="{cx - 30},{cy - 2} {cx - 8},{cy - 2} {cx - 19},{cy - 22}"/>
  <polygon points="{cx + 8},{cy - 2} {cx + 30},{cy - 2} {cx + 19},{cy - 22}"/>
  <path d="M{cx - 32},{cy + 10} Q{cx},{cy + 26} {cx + 32},{cy + 10} L{cx + 26},{cy + 30} L{cx + 16},{cy + 24}
           L{cx + 8},{cy + 34} L{cx},{cy + 27} L{cx - 8},{cy + 34} L{cx - 16},{cy + 24} L{cx - 26},{cy + 30} Z"/>
</g>
<circle cx="{cx}" cy="{cy}" r="{pr}" fill="none" stroke="{INK}" stroke-width="{OUTLINE}"/>
"""


def page(body):
    return f"""<!doctype html><html><head><style>
@font-face {{ font-family: Fredoka; src: url("file://{FREDOKA}"); }}
html, body {{ margin: 0; background: transparent; }}
</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
{body}
</svg></body></html>"""


def render(body, out):
    with tempfile.TemporaryDirectory() as tmp:
        html = os.path.join(tmp, "emblem.html")
        with open(html, "w") as handle:
            handle.write(page(body))
        shot = os.path.join(tmp, "emblem.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--allow-file-access-from-files", "--default-background-color=00000000",
                        f"--window-size={W},{H}", f"--screenshot={shot}", "file://" + html],
                       check=True, capture_output=True)
        img = Image.open(shot).convert("RGBA")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, optimize=True)
    return img


def main():
    render(emblem(), OUT)
    print(OUT)
    if "--variants" in sys.argv:
        scratch = sys.argv[sys.argv.index("--variants") + 1] if len(sys.argv) > sys.argv.index("--variants") + 1 else tempfile.gettempdir()
        variants = [emblem(), emblem(text_fill="#FFB238"),
                    emblem(pill=("#3A3550", "#24203A", "#16131F")),
                    emblem(text_fill="#FFB238", pill=("#3A3550", "#24203A", "#16131F"))]
        backs = [(255, 240, 248), (255, 255, 255), (30, 30, 40), (205, 225, 245)]
        sheet = Image.new("RGBA", (W * len(variants) + 20 * len(variants), (H + 20) * len(backs)), (0, 0, 0, 0))
        for i, body in enumerate(variants):
            img = render(body, os.path.join(scratch, f"emblem_v{i}.png"))
            for j, back in enumerate(backs):
                tile = Image.new("RGBA", (W + 20, H + 20), back + (255,))
                tile.alpha_composite(img, (10, 10))
                sheet.alpha_composite(tile, (i * (W + 20), j * (H + 20)))
        path = os.path.join(scratch, "emblem_sheet.png")
        sheet.save(path)
        print(path)


if __name__ == "__main__":
    main()
