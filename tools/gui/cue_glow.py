#!/usr/bin/env python3
"""A soft glow round a Grand Opening card cue (designer, 2026-10-06: the Firework Cue was
hard to see on its background; a yellow aura like the in-game one).

    python3 tools/gui/cue_glow.py

Reads assets/ui/grand_opening/firework_cue_mask.png (the cue body's white silhouette, 1024 x 284),
grows it, blurs it and writes firework_cue_glow.png on the same canvas: white, so the game tints it
(Config.UI.GrandOpeningCard.Layout.FireworkGlow).
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

DIR = Path(__file__).resolve().parents[2] / "assets/ui/grand_opening"
GROW_PX = 10  # the silhouette grows this much before the blur
BLUR_PX = 14
GAIN = 2.2  # the blurred edge brightened, so the glow is strong near the cue


def main():
    alpha = Image.open(DIR / "firework_cue_mask.png").getchannel("A")
    grown = alpha.filter(ImageFilter.MaxFilter(GROW_PX * 2 + 1))
    soft = grown.filter(ImageFilter.GaussianBlur(BLUR_PX))
    a = np.clip(np.asarray(soft, dtype=np.float32) * GAIN, 0, 255).astype(np.uint8)
    out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    out.putalpha(Image.fromarray(a))
    out.save(DIR / "firework_cue_glow.png")
    print(out.size, out.getchannel("A").getbbox())


if __name__ == "__main__":
    main()
