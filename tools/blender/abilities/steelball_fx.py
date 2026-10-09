"""Steel Ball rework images (ABILITIES_REWORK_PLAN step 6): the golden spiral the hit draws on
the cloth, and the spin-up overlays. Plain Python (numpy + PIL), no Blender:

    python3 tools/blender/abilities/steelball_fx.py

Writes to assets/abilities/SteelBall/ (RGBA PNG, straight alpha, transparent background):

  golden_spiral.png       1024 x 640: the golden-ratio diagram (golden rectangle, the nested
                          squares and the spiral) in thick bright gold-yellow (#FFD200) lines
                          with a pale hot core and a soft orange-gold glow. Layout as
                          SteelBall/ref/golden_spiral_ref.png: the biggest square on the left,
                          the spiral's eye low right of centre.
  golden_spiral_only.png  the same size and alignment, the spiral alone (so the game can fade
                          the squares and the spiral separately).
  spin_blur.png           512 x 512: arc streaks round a clear middle, like the motion blur of a
                          fast spinning disc (white, alpha), to lay on a disc round the ball.
  spin_arrows.png         256 x 256: two curved arrows chasing each other round a circle
                          (white), turning counter-clockwise as drawn.

Previews on a cloth green go to SteelBall/renders/ (not committed).
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "abilities", "SteelBall")
RENDERS = os.path.join(OUT, "renders")
os.makedirs(RENDERS, exist_ok=True)

PHI = (1 + math.sqrt(5)) / 2
SS = 4  # supersampling for the line art

GOLD = (255, 210, 0)       # #FFD200, the lines
CORE = (255, 246, 196)     # the pale hot core inside the lines
GLOW = (255, 170, 0)       # the soft glow round them

# The golden rectangle in the 1024 x 640 frame: 900 wide, centred, leaving room for the glow.
W, H = 1024, 640
RECT_W = 900.0
RECT_H = RECT_W / PHI
X0, Y0 = (W - RECT_W) / 2, (H - RECT_H) / 2
RECT_LINE = 11   # px at 1024 wide: thick enough to read on a phone
SPIRAL_LINE = 18
MIN_SQUARE = 34  # squares smaller than this (px) are not outlined (they would blur into a dot)
MIN_ARC = 7      # the spiral stops at squares smaller than this


def golden_steps():
    """The squares and quarter arcs, biggest first: (square (x, y, side), arc centre, start
    angle, end angle) in image pixels (y down), turning clockwise round the eye like the
    reference (left, top, right, bottom, ...)."""
    x, y, w, h = X0, Y0, RECT_W, RECT_H
    steps = []
    k = 0
    while min(w, h) > 0.5:
        d = k % 4
        if d == 0:  # a square off the left (side h); arc centre its bottom-right
            sq = (x, y, h)
            centre, a0, a1 = (x + h, y + h), 180, 270
            x, w = x + h, w - h
        elif d == 1:  # off the top (side w); centre its bottom-left
            sq = (x, y, w)
            centre, a0, a1 = (x, y + w), 270, 360
            y, h = y + w, h - w
        elif d == 2:  # off the right (side h); centre its top-left
            sq = (x + w - h, y, h)
            centre, a0, a1 = (x + w - h, y), 0, 90
            w = w - h
        else:  # off the bottom (side w); centre its top-right
            sq = (x, y + h - w, w)
            centre, a0, a1 = (x + w, y + h - w), 90, 180
            h = h - w
        steps.append((sq, centre, a0, a1))
        k += 1
    return steps


def spiral_points(steps):
    pts = []
    for sq, (cx, cy), a0, a1 in steps:
        r = sq[2]
        if r < MIN_ARC:
            break
        n = max(8, int(r / 3))
        for i in range(n + 1):
            # PIL angles: degrees clockwise from +x in image space (y down).
            a = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def draw_mask(width, draw_fn):
    """A float mask (H, W) in 0..1 from line art drawn at SS x and scaled down."""
    img = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(img)
    draw_fn(d, width * SS)
    return np.asarray(img.resize((W, H), Image.LANCZOS), dtype=np.float32) / 255


def neon(masks_and_widths, size):
    """Compose gold lines with a pale core and a soft glow from (mask_fn, width) pairs."""
    w, h = size
    body = np.zeros((h, w), np.float32)
    core = np.zeros((h, w), np.float32)
    for draw_fn, width in masks_and_widths:
        body = np.maximum(body, draw_mask(width, draw_fn))
        core = np.maximum(core, draw_mask(max(2, width * 0.22), draw_fn))
    b8 = Image.fromarray((body * 255).astype(np.uint8))
    glow = (np.asarray(b8.filter(ImageFilter.GaussianBlur(16)), np.float32) / 255 * 1.5
            + np.asarray(b8.filter(ImageFilter.GaussianBlur(5)), np.float32) / 255 * 0.8)
    glow = np.clip(glow, 0, 1) * 0.75
    # Layers, bottom to top: glow, gold body, pale core ("over" with straight alpha).
    rgb = np.zeros((h, w, 3), np.float32)
    a = np.zeros((h, w), np.float32)
    for colour, alpha in ((GLOW, glow), (GOLD, body), (CORE, core * 0.9)):
        c = np.array(colour, np.float32) / 255
        out_a = alpha + a * (1 - alpha)
        safe = np.where(out_a > 1e-6, out_a, 1)
        rgb = (c * alpha[..., None] + rgb * (a * (1 - alpha))[..., None]) / safe[..., None]
        a = out_a
    return np.concatenate([rgb, a[..., None]], axis=-1)


def save(name, rgba, folder=OUT):
    img = Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8))
    img.save(os.path.join(folder, name))
    return img


def preview(name, img):
    bg = Image.new("RGBA", img.size, (31, 92, 52, 255))  # roughly the cloth
    Image.alpha_composite(bg, img).convert("RGB").save(os.path.join(RENDERS, name))


def golden_spiral():
    steps = golden_steps()
    pts = spiral_points(steps)

    def rects(d, width):
        s = SS
        d.rectangle([X0 * s, Y0 * s, (X0 + RECT_W) * s, (Y0 + RECT_H) * s], outline=255,
                    width=int(width))
        for (x, y, side), _, _, _ in steps:
            if side < MIN_SQUARE:
                break
            d.rectangle([x * s, y * s, (x + side) * s, (y + side) * s], outline=255, width=int(width))

    def spiral(d, width):
        s = SS
        d.line([(x * s, y * s) for x, y in pts], fill=255, width=int(width), joint="curve")
        # Round caps at both ends.
        for x, y in (pts[0], pts[-1]):
            r = width / 2
            d.ellipse([x * s - r, y * s - r, x * s + r, y * s + r], fill=255)

    full = neon([(rects, RECT_LINE), (spiral, SPIRAL_LINE)], (W, H))
    only = neon([(spiral, SPIRAL_LINE)], (W, H))
    preview("golden_spiral.png", save("golden_spiral.png", full))
    preview("golden_spiral_only.png", save("golden_spiral_only.png", only))
    # The eye of the spiral (where the arcs converge), for the doc: the last step's square.
    (x, y, side), _, _, _ = steps[-1]
    print("golden spiral: rectangle", (round(X0, 1), round(Y0, 1), RECT_W, round(RECT_H, 1)),
          "eye near", (round(x, 1), round(y, 1)), "start", tuple(round(v, 1) for v in pts[0]))


def spin_blur(size=512):
    c = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(c, -c)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)  # counter-clockwise
    rng = np.random.default_rng(7)
    a = np.zeros_like(r)
    # Streaks in three-fold symmetry (it reads as a spinning disc, not noise), each a comet:
    # bright at its head, fading back along the arc (the disc turns counter-clockwise).
    for _ in range(9):
        rad = rng.uniform(0.5, 0.92)
        width = rng.uniform(0.012, 0.03)
        length = rng.uniform(0.9, 2.2)  # radians
        head = rng.uniform(0, 2 * math.pi)
        strength = rng.uniform(0.55, 1.0)
        radial = np.exp(-((r - rad) / width) ** 2)
        for k in range(3):
            h0 = head + k * 2 * math.pi / 3
            back = np.mod(h0 - th, 2 * math.pi)  # angle behind the head
            along = np.clip(1 - back / length, 0, 1) ** 1.6
            along *= np.clip(back / 0.12, 0, 1)  # a soft head, not a cut
            a = np.maximum(a, radial * along * strength)
    # A faint even blur band under the streaks, and a soft inner rim where the ball sits.
    band = np.exp(-((r - 0.72) / 0.2) ** 2) * 0.18
    a = np.clip(a + band, 0, 1) * np.clip((r - 0.42) / 0.08, 0, 1) * np.clip((1 - r) / 0.05, 0, 1)
    img = np.ones((size, size, 4), np.float32)
    img[..., 3] = a
    out = save("spin_blur.png", img)
    preview("spin_blur.png", out)


def spin_arrows(size=256):
    s = SS
    big = Image.new("L", (size * s, size * s), 0)
    d = ImageDraw.Draw(big)
    cx = cy = size * s / 2
    R = 0.33 * size * s
    width = 0.11 * size * s
    for k in range(2):
        # Each arrow: an arc of 120 degrees (image angles, clockwise from +x), a head at the
        # end pointing on round the circle (counter-clockwise on screen: decreasing angle).
        start = 200 + 180 * k
        end = start - 125
        d.arc([cx - R, cy - R, cx + R, cy + R], start=end + 8, end=start, fill=255, width=int(width))
        # The tail end rounded.
        ta = math.radians(start)
        tx, ty = cx + (R - width / 2) * math.cos(ta), cy + (R - width / 2) * math.sin(ta)
        d.ellipse([tx - width / 2, ty - width / 2, tx + width / 2, ty + width / 2], fill=255)
        # The head: a triangle at `end`, its point further round (counter-clockwise).
        ha = math.radians(end + 10)
        mid = (cx + (R - width / 2) * math.cos(ha), cy + (R - width / 2) * math.sin(ha))
        radial = (math.cos(ha), math.sin(ha))
        tangent = (math.sin(ha), -math.cos(ha))  # toward decreasing image angle
        hw, hl = width * 1.15, width * 1.5
        tip = (mid[0] + tangent[0] * hl, mid[1] + tangent[1] * hl)
        p1 = (mid[0] + radial[0] * hw, mid[1] + radial[1] * hw)
        p2 = (mid[0] - radial[0] * hw, mid[1] - radial[1] * hw)
        d.polygon([p1, tip, p2], fill=255)
    a = np.asarray(big.resize((size, size), Image.LANCZOS), np.float32) / 255
    img = np.ones((size, size, 4), np.float32)
    img[..., 3] = a
    out = save("spin_arrows.png", img)
    preview("spin_arrows.png", out)


if __name__ == "__main__":
    golden_spiral()
    spin_blur()
    spin_arrows()
