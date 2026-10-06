#!/usr/bin/env python3
"""The Firework Cue's gold ribbons as one still picture (designer, 2026-10-06: a still picture,
not the choppy loop, and only the ribbons move: a slow rock like the 8-ball flair).

    python3 tools/gui/firework_still.py [--renders ~/Desktop/8ball-refs/gui-lively/work/renders/tip_left]

Reads one frame of the loose ribbon loop from the tip-left renders (tools/gui/render_cues.py),
on the same 2304 x 640 canvas as the card's cue picture (assets/ui/grand_opening/
firework_cue.png is that canvas shrunk), and writes assets/ui/grand_opening/firework_ribbons.png:
the ribbons cropped to their box, at most 1024 px. Prints the box on the cue canvas
(Layout.FireworkRibbons), so the card lays the ribbons exactly where the render put them.
"""
import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/ui/grand_opening/firework_ribbons.png"
RENDERS = Path.home() / "Desktop/8ball-refs/gui-lively/work/renders/tip_left"
FRAME = 0  # the ribbon frame kept: the cleanest (few stray sparkles, the burst emblem clear)
MAX_PX = 1024
PAD_PX = 4  # clear canvas pixels kept round the ribbons


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--renders", default=str(RENDERS))
    args = ap.parse_args()
    d = Path(args.renders).expanduser()
    ribbons = Image.open(d / "firework_ribbons_loose" / f"frame_{FRAME:02d}.png").convert("RGBA")
    canvas_w, canvas_h = ribbons.size
    left, top, right, bottom = ribbons.getchannel("A").getbbox()
    left, top = max(0, left - PAD_PX), max(0, top - PAD_PX)
    right, bottom = min(canvas_w, right + PAD_PX), min(canvas_h, bottom + PAD_PX)
    crop = ribbons.crop((left, top, right, bottom))
    s = min(1, MAX_PX / max(crop.size))
    size = (round(crop.width * s), round(crop.height * s))
    # Resized in premultiplied alpha, so the glow keeps no dark fringe.
    crop.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA").save(OUT)
    print(f"{size[0]} x {size[1]} px")
    print(
        "FireworkRibbons = { %.4f, %.4f, %.4f, %.4f }"
        % (left / canvas_w, top / canvas_h, right / canvas_w, bottom / canvas_h)
    )


if __name__ == "__main__":
    main()
