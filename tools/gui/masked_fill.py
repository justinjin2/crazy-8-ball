"""Fill the hidden part of a cut layer with a masked GPT Image edit (lively GUI pipeline).

A piece cut out of a flat picture (13b) is partly hidden by what lay over it (the crown on the
block, a button over a ball). cut_pieces.py marks those pixels in the layer's fill mask. This
crops the source picture round the layer into a square, asks tools/openai_image.py to repaint
only the masked pixels, and pastes back only those pixels into the layer's colour, so every
pixel that was visible stays the original's. The layer's alpha is kept.

  tools/gui/.venv/bin/python tools/gui/masked_fill.py LAYER_ID "what the hidden part is" \
      [--pieces ~/Desktop/8ball-refs/gui-lively/work/pieces] [--grow 6] [--quality high]

Writes <pieces>/filled/<id>.png and keeps the edit's input, mask and raw output beside it.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SIZE = 1024  # the edit's square


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("layer")
    ap.add_argument("what")
    ap.add_argument("--pieces", default=os.path.expanduser("~/Desktop/8ball-refs/gui-lively/work/pieces"))
    ap.add_argument("--grow", type=int, default=6, help="px the repaint reaches past the mask")
    ap.add_argument("--quality", default="high")
    a = ap.parse_args()
    pieces = Path(a.pieces)
    info = json.loads((pieces / "layers.json").read_text())
    layer = next(L for L in info["layers"] if L["id"] == a.layer)
    if not layer.get("fill_mask"):
        sys.exit(f"{a.layer} has no fill mask")
    source = Image.open(os.path.expanduser(info["source"])).convert("RGB")
    cut = Image.open(pieces / layer["file"]).convert("RGBA")
    fill = Image.open(pieces / layer["fill_mask"]).convert("L")
    x, y, w, h = layer["x"], layer["y"], layer["w"], layer["h"]

    # A square crop of the source centred on the layer, with room round it for context.
    side = int(max(w, h) * 1.15)
    cx, cy = x + w / 2, y + h / 2
    box = (int(cx - side / 2), int(cy - side / 2), int(cx - side / 2) + side, int(cy - side / 2) + side)
    crop = Image.new("RGB", (side, side), (10, 16, 50))
    crop.paste(source.crop(box), (0, 0))
    # The repaint area in the crop: the fill mask, grown a little so the seam blends.
    area = Image.new("L", (side, side), 0)
    area.paste(fill, (x - box[0], y - box[1]))
    area = area.point(lambda v: 255 if v > 20 else 0).filter(ImageFilter.MaxFilter(a.grow * 2 + 1))

    out = pieces / "filled"
    out.mkdir(exist_ok=True)
    scale = SIZE / side
    crop.resize((SIZE, SIZE), Image.LANCZOS).save(out / f"{a.layer}_input.png")
    # OpenAI's mask: clear (alpha 0) where to repaint.
    mask = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    hole = area.resize((SIZE, SIZE), Image.NEAREST)
    mask.putalpha(Image.eval(hole, lambda v: 255 - v))
    mask.save(out / f"{a.layer}_mask.png")

    prompt = (
        "Repaint ONLY the transparent (masked) area of this picture so it continues the "
        f"picture seamlessly: {a.what}. Match the surrounding art exactly: the same painted "
        "style, colours, lighting, edges and detail size. Do not add anything else there. "
        "Everything outside the masked area stays exactly as it is."
    )
    raw = out / f"{a.layer}_raw.png"
    subprocess.run(
        ["python3", str(ROOT / "tools/openai_image.py"),
         "--image", str(out / f"{a.layer}_input.png"), "--mask", str(out / f"{a.layer}_mask.png"),
         "--size", f"{SIZE}x{SIZE}", "--quality", a.quality, "--stop", "500", "--note-every", "50",
         "--tag", f"shop-lively-fill-{a.layer}", "--out", str(raw), "--prompt", prompt],
        check=True,
    )

    # Back to the crop's size, then the layer's own pixels; paste only the masked ones.
    painted = Image.open(raw).convert("RGB").resize((side, side), Image.LANCZOS)
    painted = painted.crop((x - box[0], y - box[1], x - box[0] + w, y - box[1] + h))
    soft = area.crop((x - box[0], y - box[1], x - box[0] + w, y - box[1] + h)).filter(
        ImageFilter.GaussianBlur(2)
    )
    rgb = np.asarray(cut.convert("RGB")).astype(float)
    new = np.asarray(painted).astype(float)
    k = np.asarray(soft).astype(float)[..., None] / 255
    mixed = (rgb * (1 - k) + new * k).round().astype(np.uint8)
    result = Image.fromarray(mixed, "RGB")
    result.putalpha(cut.getchannel("A"))
    result.save(out / f"{a.layer}.png")
    print(out / f"{a.layer}.png", f"(edit scale {scale:.2f})")


if __name__ == "__main__":
    main()
