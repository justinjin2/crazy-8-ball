#!/usr/bin/env python3
"""The Firework Cue's card picture as one still image (designer, 2026-10-06: the gold ribbons as
a still picture, not a choppy loop, breathing and shining like the lucky block).

    python3 tools/gui/firework_still.py [--renders ~/Desktop/8ball-refs/gui-lively/work/renders/tip_left]

Reads the tip-left renders (tools/gui/render_cues.py): firework_cue.png and firework_cue_mask.png
(the cue and its body's silhouette on the 2304 x 640 canvas; the card's firework_cue.png is the
same picture shrunk) and one frame of the loose ribbon loop. Writes into
assets/ui/grand_opening/, all the same size with a clear border (the breathe zooms inside it):

  firework_still.png        the cue with its ribbons baked on, at most 1024 px
  firework_still_mask.png   its white silhouette (the shine sweep)
  firework_still_glow.png   a soft glow round the cue body only, white (the game tints it), as
                            tools/gui/cue_glow.py made it

and prints the picture's box on the cue canvas (Layout.FireworkStill) and its size (FireworkStillPx).
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/ui/grand_opening"
RENDERS = Path.home() / "Desktop/8ball-refs/gui-lively/work/renders/tip_left"
FRAME = 0  # the ribbon frame kept: the cleanest (few stray sparkles, the burst emblem clear)
MAX_PX = 1024
BORDER_PX = 48  # clear border: room for the glow's blur and the breathe
# The glow as cue_glow.py made it at the card's old scale (1024 px over the 2304 canvas).
GROW_PX, BLUR_PX, GAIN = 10, 14, 2.2
OLD_SCALE = 1024 / 2304


def premultiplied_resize(im, size):
    return im.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--renders", default=str(RENDERS))
    args = ap.parse_args()
    d = Path(args.renders).expanduser()
    cue = Image.open(d / "firework_cue.png").convert("RGBA")
    body = Image.open(d / "firework_cue_mask.png").convert("RGBA").getchannel("A")
    ribbons = Image.open(d / "firework_ribbons_loose" / f"frame_{FRAME:02d}.png").convert("RGBA")
    canvas_w, canvas_h = cue.size
    baked = cue.copy()
    baked.alpha_composite(ribbons)
    left, top, right, bottom = baked.getchannel("A").getbbox()
    s = (MAX_PX - 2 * BORDER_PX) / max(right - left, bottom - top)  # output px per canvas px
    w = round((right - left) * s) + 2 * BORDER_PX
    h = round((bottom - top) * s) + 2 * BORDER_PX
    inner = (round((right - left) * s), round((bottom - top) * s))

    def place(im):
        out = Image.new(im.mode, (w, h), 0 if im.mode == "L" else (0, 0, 0, 0))
        if im.mode == "L":
            out.paste(im.crop((left, top, right, bottom)).resize(inner, Image.LANCZOS),
                      (BORDER_PX, BORDER_PX))
        else:
            out.alpha_composite(premultiplied_resize(im.crop((left, top, right, bottom)), inner),
                                (BORDER_PX, BORDER_PX))
        return out

    picture = place(baked)
    picture.save(OUT / "firework_still.png")
    mask = Image.new("RGBA", picture.size, (255, 255, 255, 0))
    mask.putalpha(picture.getchannel("A"))
    mask.save(OUT / "firework_still_mask.png")
    k = s / OLD_SCALE
    alpha = place(body)
    grown = alpha.filter(ImageFilter.MaxFilter(round(GROW_PX * k) * 2 + 1))
    soft = grown.filter(ImageFilter.GaussianBlur(BLUR_PX * k))
    a = np.clip(np.asarray(soft, dtype=np.float32) * GAIN, 0, 255).astype(np.uint8)
    glow = Image.new("RGBA", picture.size, (255, 255, 255, 0))
    glow.putalpha(Image.fromarray(a))
    glow.save(OUT / "firework_still_glow.png")
    # The picture's box (border included) in shares of the cue canvas, which the card's cue
    # holder spans.
    b = BORDER_PX / s
    box = ((left - b) / canvas_w, (top - b) / canvas_h, (right + b) / canvas_w,
           (bottom + b) / canvas_h)
    print(f"{w} x {h} px, border {BORDER_PX} px; glow reaches {glow.getchannel('A').getbbox()}")
    print("FireworkStill = { %.4f, %.4f, %.4f, %.4f }" % box)
    print("FireworkStillPx = { %d, %d, %d }" % (w, h, BORDER_PX))


if __name__ == "__main__":
    main()
