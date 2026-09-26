"""Measure the rooftop map palette from the concept art.

Run from the repo root:

    python3 assets/map/measure_palette.py

Writes assets/map/Palette.json (committed) and
assets/map/checkpoints/palette_sheet.png (git-ignored, for eyeballing every crop).

Method
------
* Each REGIONS row names one material, the reference image it is read from, a crop box
  (left, top, right, bottom in that image's own pixels, right/bottom exclusive, the same
  convention as PIL's Image.crop), k (number of clusters) and two rules: which cluster is
  reported as the colour ("pick") and which as the darker companion ("shade").
* The crop's pixels are converted from sRGB to CIELAB (D65) and clustered with k-means in
  Lab, so clusters split along perceived differences (lit face vs shadow vs JPEG edge)
  rather than raw RGB distance. k-means++ seeding uses numpy.random.default_rng(SEED);
  Lloyd iterations run to convergence. Same input, same output, byte for byte.
* A cluster's reported colour is the mean sRGB of its member pixels (what the painter's
  pixels average to), rounded to the nearest integer.
* Clusters are listed by share, largest first (ties broken by lightness).
* Sources: panels/day.jpg and panels/sunset.jpg are pixel-identical to the two halves of
  01-concept-sheet.jpg's top row (checked: mean abs difference 0.02), so the panel files are
  used; the other panels are re-encoded crops of the sheet at small offsets.

Palette.json, one entry per region (keys sorted, stable bytes):
  hex       the chosen cluster's mean colour        shade     a darker companion or null
  source    always "image" (measured, not invented)  image     the reference file
  box       the crop                                 k, pick   the clustering settings
  clusters  [[hex, share], ...] biggest first        note      what the crop shows

Pick rules (how the reported cluster is chosen)
------------------------------------------------
The default aim is the lit base colour: the largest cluster that is not a highlight, a
shadow or an edge. Crops are cut from one material wherever the art allows, so "largest"
is right most of the time; the other rules exist for subjects the art never shows clean.

  largest        the biggest cluster. Used when the crop is one clean material.
  largest_mid    the biggest cluster that is neither the lightest nor the darkest one
                 (k >= 3): drops the specular highlight and the shadow/edge clusters even
                 when they are big (thin palm trunk against sky, flame core and rim).
  lightest       the lightest cluster with share >= MIN_SHARE: the sunlit face of something
                 mostly seen in shade (column, parapet, cloud at sunset, sun disk).
  darkest        the darkest cluster with share >= MIN_SHARE: grout lines.
  warm           the cluster with the highest b* (yellowness), share >= MIN_SHARE: lit
                 windows among dark facade.
  hue:LO:HI      the biggest cluster whose Lab hue angle lies in [LO, HI] degrees (wraps
                 past 360) with chroma >= HUE_MIN_CHROMA. For subjects that cannot be
                 cropped without sky or leaves behind them: sky is ~260-290 deg, foliage
                 ~100-150 deg, magenta ~340-20 deg, the blue fire ring ~230 deg.
  lit_hue:LO:HI  the lightest cluster (share >= MIN_SHARE) in that hue range. Used for
                 leaf clumps: most of a clump is self-shadow, so the biggest green cluster is
                 shadow; the leaf colour is the lit cluster and the self-shadow becomes the
                 shade.

  vivid:HLO:HHI:LLO:LHI
                 not a cluster: the mean of the most saturated 15% of the crop's pixels
                 whose Lab hue lies in [HLO, HHI] and L* in [LLO, LHI]. For small painted
                 subjects (leaves, flowers) whose clusters average the JPEG blur with shadow
                 and sky into olive or maroon: the painter's clean colour at that lightness.

Shade rules (the darker companion, for gradients and AO)
--------------------------------------------------------
  darker         the next step down: of the clusters at least SHADE_MIN_DL darker (L*)
                 than the pick with share >= MIN_SHARE, the one nearest in L*. Null if none.
  darker_hue     the same, restricted to clusters within SHADE_MAX_DH degrees of the pick's
                 hue, so a leaf's shade is darker leaf and not the brown shadow behind it.
  darker_big     the biggest of those darker clusters, when the next step down is only an
                 edge blend (a lit side face whose real shade is the big shadowed face).
  none           no shade (emissive colours, or the only darker cluster is another object).
"""

from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_JSON = os.path.join(ROOT, "assets/map/Palette.json")
OUT_SHEET = os.path.join(ROOT, "assets/map/checkpoints/palette_sheet.png")

SEED = 8  # k-means++ seed, fixed so re-runs are identical
MIN_SHARE = 0.05  # clusters smaller than this are ignored by lightest/darkest/warm/shade
SHADE_MIN_DL = 4.0  # a shade must be at least this many L* units darker than the pick
HUE_MIN_CHROMA = 12.0  # hue rules only consider clusters at least this saturated
SHADE_MAX_DH = 40.0  # darker_hue: the shade's Lab hue must be within this many degrees

REF = "assets/map/reference/"
D = REF + "02-day-view.jpg"  # rooftop at near-player height: authority for rooftop colours
A = REF + "03-detail-assets.jpg"  # prop close-ups: authority for props (dusk lighting)
PD = REF + "panels/day.jpg"  # whole rooftop, day (identical pixels to 01 top-left)
PS = REF + "panels/sunset.jpg"  # whole rooftop, sunset (identical pixels to 01 top-right)
TD = REF + "panels/top-down.jpg"  # top-down (01 rows 380-808, re-encoded)
OC = REF + "panels/ocean-side.jpg"
CS = REF + "panels/city-side.jpg"

# name, image, (left, top, right, bottom), k, pick, shade, note
# Every box was checked by eye on the contact sheet (crop, context and swatches).
REGIONS = [
    # --- Rooftop (02 is the authority; panels where 02 has no clean view) -----------------
    ("floor", D, (725, 445, 770, 468), 3, "largest", "darker",
     "sunlit tile right of the front-right planter, clear of table glow; reads warm pink-white"),
    ("floor_shade", D, (575, 497, 640, 518), 3, "largest", "darker",
     "tile inside a planter's cast shadow: the painter's cool blue-lavender shade"),
    ("floor_panel_day", PD, (258, 244, 272, 256), 2, "largest", "none",
     "open floor between tables in the day overview, for comparison with 02"),
    ("floor_topdown", TD, (340, 222, 356, 236), 2, "largest", "none",
     "plain tile in the top-down (warm evening light); pair with floor_accent"),
    ("floor_accent", TD, (323, 229, 334, 240), 2, "largest", "none",
     "darker accent tile of the checker pattern, same light as floor_topdown (-12 L*)"),
    ("grout", D, (645, 528, 668, 552), 3, "darkest", "none",
     "sunlit tiles across a 1-2 px grout line; approximate (line is blurred by JPEG)"),
    ("step", PD, (282, 166, 305, 186), 3, "largest", "darker",
     "left lounge steps: lit treads, the shade is the riser"),
    ("step_entrance", TD, (365, 398, 435, 420), 3, "largest", "darker",
     "entrance stair from above (warm evening light): treads and risers"),
    ("parapet", PD, (712, 312, 752, 345), 3, "lightest", "darker",
     "front-right low wall: lit top edge; the shade is the wall face in shadow"),
    ("railing_frame", D, (49, 380, 53, 432), 2, "largest", "none",
     "railing post on the city side; posts and top rail read near-black"),
    ("railing_glass", PD, (622, 222, 634, 236), 3, "largest", "none",
     "sea seen through one glass panel, ocean side; glass is near-clear with a cyan cast"),
    ("column", D, (266, 152, 296, 178), 3, "lightest", "darker",
     "front-left pergola column: sunlit cream edge; the shade is its mauve front face"),
    ("pergola_beam", D, (340, 91, 520, 106), 3, "largest", "none",
     "front fascia of the pergola roof: the cream material in shade (lit value ~ column)"),
    ("led_strip", D, (380, 113, 520, 117), 3, "lightest", "none",
     "warm LED line under the pergola fascia (2-3 px tall, so the lightest cluster)"),
    ("pergola_soffit", D, (340, 120, 520, 134), 3, "largest", "darker",
     "underside of the pergola roof, warmed by its LED strip"),
    ("pergola_slat", A, (805, 104, 845, 114), 3, "largest", "darker_hue",
     "wood beam of the pergola close-up (03 draws a wood pergola, 02 a solid cream roof)"),
    ("pergola_post_wood", A, (763, 128, 772, 185), 3, "largest_mid", "darker",
     "wood post of the pergola close-up; lightest cluster is lamp glow"),
    ("vine_leaf", D, (262, 78, 290, 100), 4, "lit_hue:80:170", "darker_hue",
     "vines over the front-left pergola corner, sky behind"),
    ("flower_pink", D, (690, 125, 715, 165), 4, "hue:300:30", "darker_hue",
     "bougainvillea on the front-right pergola column"),
    ("under_table_glow", D, (878, 518, 925, 545), 3, "largest_mid", "darker",
     "orange glow on the floor at the base of the front-right table; lightest is the hot rim"),
    # --- Props (03 is the authority, lit by warm lamps at dusk; 02 variants for daylight) ---
    ("planter", A, (1306, 210, 1321, 268), 3, "largest", "darker",
     "square planter, lit side face (warm lamp light on off-white concrete)"),
    ("planter_shade", A, (1200, 215, 1295, 265), 3, "largest", "none",
     "same planter, front face in shadow"),
    ("planter_day", D, (658, 420, 712, 455), 3, "lightest", "darker_big",
     "02 planter: lit side face; the shade is its front face in shadow"),
    ("couch", A, (300, 168, 350, 190), 3, "largest", "darker",
     "sectional seat top, warm grey fabric under lamp light"),
    ("couch_day", D, (995, 338, 1040, 350), 3, "largest", "darker",
     "02 ocean-side sofa seat in daylight"),
    ("cushion_blue", A, (338, 135, 355, 152), 3, "largest", "darker", "deep blue cushion"),
    ("cushion_teal", A, (396, 138, 414, 150), 3, "largest", "darker",
     "the 'light blue' cushion: a low-chroma blue-grey that reads blue beside the ochre"),
    ("cushion_orange", A, (366, 134, 380, 150), 3, "largest", "darker", "ochre cushion"),
    ("cushion_white", D, (1026, 309, 1046, 327), 3, "lightest", "darker",
     "cream cushion on the 02 ocean-side sofa: lit top; shade is its shaded front"),
    ("coffee_table", A, (375, 212, 400, 236), 3, "largest", "darker",
     "round coffee table: top; the shade is the dark apron"),
    ("firepit_stone", A, (575, 215, 700, 240), 3, "largest", "darker",
     "fire pit drum, vertical brown stone panels"),
    ("firepit_top", A, (560, 195, 610, 208), 3, "largest", "darker", "fire pit cap"),
    ("firepit_ring", A, (583, 181, 598, 191), 3, "hue:200:300", "none",
     "blue glass ring round the burner (crop also holds cap and flame)"),
    ("fire", A, (620, 150, 648, 188), 3, "largest_mid", "darker",
     "flame body; lightest cluster is the white core"),
    ("lantern_glass", D, (497, 512, 512, 560), 3, "largest", "none",
     "floor lantern panel by the front-centre planter, day"),
    ("lantern_glass_detail", A, (1402, 115, 1424, 230), 3, "largest", "none",
     "floor lantern panel in the close-up"),
    ("lantern_frame", A, (1391, 110, 1397, 235), 3, "largest", "none",
     "lantern corner post in the close-up: dark bronze (lighter clusters are glow spill)"),
    ("globe_light", A, (786, 135, 798, 149), 3, "largest", "none",
     "hanging globe in the pergola close-up"),
    ("umbrella_canvas", A, (1045, 85, 1105, 105), 3, "largest", "darker_hue",
     "umbrella canopy in the close-up (warm light)"),
    ("umbrella_canvas_day", D, (790, 176, 850, 187), 3, "largest", "darker",
     "umbrella canopy on the 02 ocean-side terrace; shade is its underside"),
    ("umbrella_pole", A, (1057, 125, 1061, 220), 2, "largest", "darker", "umbrella pole, wood"),
    ("lounger", A, (1023, 190, 1050, 212), 3, "largest", "darker", "sun lounger back"),
    ("piano_black", D, (570, 200, 600, 215), 3, "largest", "none",
     "grand piano body; the second cluster is a navy sheen"),
    ("foliage_light", D, (80, 515, 105, 535), 3, "hue:80:170", "none",
     "sunlit broad leaf in the 02 foreground"),
    ("foliage_dark", D, (30, 560, 60, 590), 3, "hue:80:170", "none",
     "shaded leaves in the 02 foreground"),
    ("fern", D, (405, 380, 445, 415), 3, "lit_hue:80:170", "darker_hue",
     "fern in the front-centre planter: lit fronds; shade is the inner fronds"),
    ("palm_frond", D, (760, 55, 795, 100), 4, "lit_hue:80:170", "darker_hue",
     "palm fronds right of the pergola, sky behind"),
    # The painter's clean greens and pink (vivid rule): the k-means picks above average the
    # JPEG blur of small leaves with shadow and sky into olive. These three stops are what the
    # foliage atlas paints with (Spec section 2).
    ("leaf_lit", D, (395, 350, 470, 420), 5, "vivid:90:140:50:80", "none",
     "front-centre fern, 02: the most saturated sunlit fronds"),
    ("leaf_mid", D, (395, 350, 470, 420), 5, "vivid:95:145:30:50", "none",
     "front-centre fern, 02: the most saturated mid-tone fronds"),
    ("leaf_dark", D, (395, 350, 470, 420), 5, "vivid:100:150:10:30", "none",
     "front-centre fern, 02: the most saturated deep fronds"),
    ("palm_lit", D, (740, 40, 800, 110), 5, "vivid:90:140:50:80", "none",
     "palm crown right of the pergola, 02: sunlit fronds"),
    ("palm_mid", D, (740, 40, 800, 110), 5, "vivid:95:145:30:50", "none",
     "palm crown right of the pergola, 02: mid-tone fronds"),
    ("flower_vivid", D, (682, 80, 720, 150), 5, "vivid:330:20:30:65", "none",
     "bougainvillea on the front-right pergola column, 02: the clean magenta"),
    ("palm_trunk", D, (748, 122, 754, 165), 3, "largest_mid", "darker",
     "palm trunk: lit side; shade is the dark side (lightest cluster is sky)"),
    # --- Backdrop, day --------------------------------------------------------------------
    ("sky_top_day", D, (480, 8, 580, 28), 3, "largest", "none", "upper sky"),
    ("sky_horizon_day", OC, (440, 40, 540, 52), 3, "largest", "none",
     "pale sky just above the far islands"),
    ("cloud_day", D, (1095, 28, 1150, 50), 3, "largest", "darker",
     "cumulus: lit white; shade is its blue underside"),
    ("water_near", OC, (190, 135, 250, 160), 3, "largest", "darker_hue",
     "turquoise shallows round the islands"),
    ("water_far", D, (925, 160, 975, 192), 3, "largest", "none",
     "open sea off the ocean-side railing, 02"),
    ("sand", OC, (20, 118, 60, 130), 3, "largest", "none", "beach"),
    ("island_green", OC, (52, 84, 68, 98), 3, "largest", "darker_hue",
     "jungle on a near island (the art paints it sage green)"),
    ("island_far", D, (1138, 128, 1162, 148), 3, "largest", "darker",
     "02 nearest steep island: haze turns the green teal"),
    ("island_rock", OC, (36, 134, 50, 154), 3, "largest", "darker",
     "big shore rock: mauve grey"),
    ("mountain_far", D, (1025, 113, 1060, 128), 3, "largest", "none",
     "hazy far mountain, painted just darker than the sky"),
    ("city_glass_day", D, (55, 110, 70, 190), 3, "largest", "none", "tower glass"),
    ("city_facade_day", D, (120, 235, 135, 295), 3, "largest", "darker",
     "light warm-grey facade; the shade is its window grid"),
    ("city_far_day", CS, (500, 60, 560, 75), 3, "largest", "none",
     "hazy far city at the horizon"),
    # --- Sunset (panels/sunset.jpg = 01 top-right, same pixels) ---------------------------
    ("sky_top_sunset", PS, (190, 2, 300, 12), 3, "largest", "none", "violet upper sky"),
    ("sky_mid_sunset", PS, (85, 62, 125, 85), 3, "largest", "none", "magenta band"),
    ("sky_horizon_sunset", PS, (640, 82, 700, 94), 3, "largest", "none",
     "orange band right of the sun"),
    ("cloud_sunset", PS, (245, 26, 268, 38), 3, "lightest", "darker",
     "lit salmon cloud edge; shade is the magenta body"),
    ("sun", PS, (604, 82, 620, 96), 3, "lightest", "none", "sun disk"),
    ("water_sunset_glow", PS, (602, 140, 622, 190), 3, "largest", "darker",
     "sun reflection column on the sea"),
    ("water_sunset", PS, (660, 160, 700, 185), 3, "largest", "darker",
     "sea away from the reflection"),
    ("city_glass_sunset", PS, (50, 70, 70, 140), 3, "largest", "none", "tower glass at dusk"),
    ("city_lit_window", PS, (22, 115, 32, 135), 3, "warm", "none",
     "warm-lit windows of a tower top; windows are 1-2 px, so approximate"),
    ("mountain_sunset", PS, (672, 115, 732, 135), 3, "largest", "none", "island silhouette"),
    ("floor_sunset", PS, (236, 248, 262, 262), 3, "largest", "none",
     "rooftop floor between the front tables"),
    ("lantern_glass_sunset", PS, (420, 315, 428, 345), 3, "largest", "none",
     "floor lantern panel at the entrance"),
    # --- The near world below the roof (Stage 4): the city panel and the day panel's beach ---
    ("road_day", CS, (383, 165, 392, 195), 3, "largest", "none",
     "the street running down the middle of the city panel: the art paints it warm mauve-grey"),
    ("facade_terracotta_day", CS, (22, 108, 38, 160), 3, "lightest", "darker",
     "salmon-terracotta block at the far left; the shade is its window grid"),
    ("facade_white_day", CS, (475, 85, 498, 140), 3, "lightest", "darker",
     "the lit face of the cream-white tower right of centre; the shade is its windows"),
    ("lawn_day", CS, (180, 138, 245, 175), 3, "vivid:100:150:35:75", "none",
     "the city panel's park and street greenery, lower left of the river: the saturated leaves"),
    ("boat_hull_day", PD, (727, 185, 740, 190), 3, "lightest", "none",
     "white yacht off the beach below the ocean side"),
    ("shallows_day", PD, (700, 228, 725, 240), 3, "largest", "none",
     "turquoise water just off the beach below the ocean side"),
]


# --- colour maths -------------------------------------------------------------------------

_M_RGB_TO_XYZ = np.array(
    [
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041],
    ]
)
_WHITE_D65 = np.array([0.95047, 1.0, 1.08883])


def srgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """rgb: (n, 3) floats in 0..255 -> (n, 3) CIELAB (D65)."""
    c = rgb / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    # explicit sums rather than matmul: numpy 2 + Accelerate on macOS raises spurious
    # floating-point warnings from matmul on some inputs
    xyz = np.stack([(lin * _M_RGB_TO_XYZ[i]).sum(1) for i in range(3)], axis=1) / _WHITE_D65
    eps = 216 / 24389
    kappa = 24389 / 27
    f = np.where(xyz > eps, np.cbrt(xyz), (kappa * xyz + 16) / 116)
    lab = np.empty_like(f)
    lab[:, 0] = 116 * f[:, 1] - 16
    lab[:, 1] = 500 * (f[:, 0] - f[:, 1])
    lab[:, 2] = 200 * (f[:, 1] - f[:, 2])
    return lab


def kmeans(x: np.ndarray, k: int, seed: int, iters: int = 200) -> np.ndarray:
    """Deterministic k-means with k-means++ seeding. Returns labels (n,)."""
    n = x.shape[0]
    k = min(k, n)
    rng = np.random.default_rng(seed)
    centres = np.empty((k, x.shape[1]))
    centres[0] = x[rng.integers(n)]
    d2 = ((x - centres[0]) ** 2).sum(1)
    for i in range(1, k):
        total = d2.sum()
        if total <= 0:
            idx = int(rng.integers(n))
        else:
            idx = int(rng.choice(n, p=d2 / total))
        centres[i] = x[idx]
        d2 = np.minimum(d2, ((x - centres[i]) ** 2).sum(1))
    labels = np.full(n, -1)
    for _ in range(iters):
        dist = ((x[:, None, :] - centres[None, :, :]) ** 2).sum(2)
        new = dist.argmin(1)
        if np.array_equal(new, labels):
            break
        labels = new
        for j in range(k):
            members = x[labels == j]
            if len(members):
                centres[j] = members.mean(0)
            else:  # re-seed an empty cluster at the worst-fit point
                far = int(dist.min(1).argmax())
                centres[j] = x[far]
    return labels


def to_hex(rgb) -> str:
    r, g, b = (int(round(float(v))) for v in rgb)
    return "#{:02X}{:02X}{:02X}".format(r, g, b)


# --- per-region measurement ---------------------------------------------------------------


def measure(img: Image.Image, box, k: int):
    px = np.asarray(img.crop(box), dtype=np.float64).reshape(-1, 3)
    lab = srgb_to_lab(px)
    labels = kmeans(lab, k, SEED)
    clusters = []
    for j in range(labels.max() + 1):
        m = labels == j
        if not m.any():
            continue
        rgb = px[m].mean(0)
        clab = lab[m].mean(0)
        clusters.append(
            {
                "rgb": rgb,
                "hex": to_hex(rgb),
                "share": float(m.mean()),
                "L": float(clab[0]),
                "a": float(clab[1]),
                "b": float(clab[2]),
                "C": float(np.hypot(clab[1], clab[2])),
                "h": float(np.degrees(np.arctan2(clab[2], clab[1])) % 360.0),
            }
        )
    clusters.sort(key=lambda c: (-round(c["share"], 6), -c["L"]))
    return clusters


def _hue_in(h: float, lo: float, hi: float) -> bool:
    return lo <= h <= hi if lo <= hi else (h >= lo or h <= hi)


def _hue_gap(a: float, b: float) -> float:
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


def vivid(img: Image.Image, box, rule: str, top: float = 0.15):
    _, hlo, hhi, llo, lhi = rule.split(":")
    px = np.asarray(img.crop(box), dtype=np.float64).reshape(-1, 3)
    lab = srgb_to_lab(px)
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    hue = np.degrees(np.arctan2(lab[:, 2], lab[:, 1])) % 360.0
    lo, hi = float(hlo), float(hhi)
    in_hue = (hue >= lo) & (hue <= hi) if lo <= hi else (hue >= lo) | (hue <= hi)
    m = in_hue & (lab[:, 0] >= float(llo)) & (lab[:, 0] <= float(lhi))
    if not m.any():
        raise SystemExit(f"no pixels for {rule}")
    cut = np.quantile(chroma[m], 1.0 - top)
    sel = m & (chroma >= cut)
    rgb = px[sel].mean(0)
    clab = lab[sel].mean(0)
    return {
        "rgb": rgb,
        "hex": to_hex(rgb),
        "share": float(sel.mean()),
        "L": float(clab[0]),
        "a": float(clab[1]),
        "b": float(clab[2]),
        "C": float(np.hypot(clab[1], clab[2])),
        "h": float(np.degrees(np.arctan2(clab[2], clab[1])) % 360.0),
    }


def choose(clusters, rule: str):
    big = [c for c in clusters if c["share"] >= MIN_SHARE] or clusters
    if rule == "largest":
        return clusters[0]
    if rule == "largest_mid":
        if len(clusters) < 3:
            return clusters[0]
        by_l = sorted(clusters, key=lambda c: c["L"])
        mids = [c for c in clusters if c is not by_l[0] and c is not by_l[-1]]
        return mids[0]
    if rule == "lightest":
        return max(big, key=lambda c: c["L"])
    if rule == "darkest":
        return min(big, key=lambda c: c["L"])
    if rule == "warm":
        return max(big, key=lambda c: c["b"])
    if rule.startswith("lit_hue:"):
        _, lo, hi = rule.split(":")
        hits = [
            c
            for c in big
            if c["C"] >= HUE_MIN_CHROMA and _hue_in(c["h"], float(lo), float(hi))
        ]
        if not hits:
            raise SystemExit(f"no cluster in hue range {rule}")
        return max(hits, key=lambda c: c["L"])
    if rule.startswith("hue:"):
        _, lo, hi = rule.split(":")
        hits = [
            c
            for c in clusters
            if c["C"] >= HUE_MIN_CHROMA and _hue_in(c["h"], float(lo), float(hi))
        ]
        if not hits:
            raise SystemExit(f"no cluster in hue range {rule}")
        return hits[0]
    raise SystemExit(f"unknown pick rule {rule}")


def choose_shade(clusters, pick, rule: str):
    if rule == "none":
        return None
    darker = [
        c
        for c in clusters
        if c is not pick and c["share"] >= MIN_SHARE and c["L"] <= pick["L"] - SHADE_MIN_DL
    ]
    if rule == "darker_hue":
        darker = [c for c in darker if _hue_gap(c["h"], pick["h"]) <= SHADE_MAX_DH]
    elif rule not in ("darker", "darker_big"):
        raise SystemExit(f"unknown shade rule {rule}")
    if not darker:
        return None
    if rule == "darker_big":
        return darker[0]  # clusters are sorted by share, biggest first
    return max(darker, key=lambda c: (c["L"], c["share"]))  # the next step down


# --- contact sheet ------------------------------------------------------------------------


def load_font(size: int):
    for path in (
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def fit(im: Image.Image, w: int, h: int, resample) -> Image.Image:
    s = min(w / im.width, h / im.height)
    return im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), resample)


def sheet_cell(name, image_path, img, box, clusters, pick, shade, note, fonts):
    f_big, f_small = fonts
    cw, ch = 900, 190
    cell = Image.new("RGB", (cw, ch), (28, 30, 36))
    d = ImageDraw.Draw(cell)
    d.text((8, 4), name, fill=(255, 255, 255), font=f_big)
    d.text((8, 28), f"{os.path.basename(image_path)} {list(box)}", fill=(170, 175, 190), font=f_small)
    d.text((8, 172), note[:110], fill=(150, 155, 170), font=f_small)
    # context: the crop box drawn on its surroundings
    l, t, r, b = box
    pad = max(r - l, b - t, 24)
    cl, ct = max(0, l - pad), max(0, t - pad)
    cr, cb = min(img.width, r + pad), min(img.height, b + pad)
    ctx = img.crop((cl, ct, cr, cb)).copy()
    ImageDraw.Draw(ctx).rectangle((l - cl - 1, t - ct - 1, r - cl, b - ct), outline=(255, 0, 255))
    ctx = fit(ctx, 150, 120, Image.LANCZOS)
    cell.paste(ctx, (8, 46))
    # the crop itself, enlarged with nearest-neighbour so pixels stay honest
    crop = fit(img.crop(box), 150, 120, Image.NEAREST)
    cell.paste(crop, (166, 46))
    # swatches
    x = 330
    for c in clusters:
        d.rectangle((x, 50, x + 64, 114), fill=tuple(int(round(v)) for v in c["rgb"]))
        if c is pick:
            d.rectangle((x - 3, 47, x + 67, 117), outline=(255, 255, 255), width=3)
            d.text((x, 34), "PICK", fill=(255, 255, 255), font=f_small)
        elif c is shade:
            d.rectangle((x - 3, 47, x + 67, 117), outline=(140, 140, 140), width=2)
            d.text((x, 34), "shade", fill=(200, 200, 200), font=f_small)
        d.text((x, 120), c["hex"], fill=(220, 220, 220), font=f_small)
        d.text((x, 136), f"{c['share'] * 100:.0f}%  L{c['L']:.0f}", fill=(170, 170, 170), font=f_small)
        x += 76
    # chosen colour, large
    d.rectangle((cw - 120, 46, cw - 12, 130), fill=tuple(int(round(v)) for v in pick["rgb"]))
    d.text((cw - 120, 136), pick["hex"], fill=(255, 255, 255), font=f_big)
    return cell


def dump_palette(palette: dict) -> str:
    """Sorted keys, one field per line, lists kept inline: stable and easy to diff."""
    lines = ["{"]
    names = sorted(palette)
    for i, name in enumerate(names):
        entry = palette[name]
        lines.append(f"  {json.dumps(name)}: {{")
        fields = sorted(entry)
        for j, key in enumerate(fields):
            comma = "," if j < len(fields) - 1 else ""
            lines.append(f"    {json.dumps(key)}: {json.dumps(entry[key])}{comma}")
        lines.append("  }" + ("," if i < len(names) - 1 else ""))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> int:
    names = [r[0] for r in REGIONS]
    if len(set(names)) != len(names):
        raise SystemExit("duplicate region names")
    cache: dict[str, Image.Image] = {}
    palette = {}
    cells = []
    fonts = (load_font(18), load_font(12))
    for name, path, box, k, pick_rule, shade_rule, note in REGIONS:
        if path not in cache:
            cache[path] = Image.open(os.path.join(ROOT, path)).convert("RGB")
        img = cache[path]
        l, t, r, b = box
        if not (0 <= l < r <= img.width and 0 <= t < b <= img.height):
            raise SystemExit(f"{name}: box {box} outside {path} {img.size}")
        clusters = measure(img, box, k)
        pick = vivid(img, box, pick_rule) if pick_rule.startswith("vivid:") else choose(clusters, pick_rule)
        shade = choose_shade(clusters, pick, shade_rule)
        palette[name] = {
            "box": list(box),
            "clusters": [[c["hex"], round(c["share"], 3)] for c in clusters],
            "hex": pick["hex"],
            "image": path,
            "k": k,
            "note": note,
            "pick": pick_rule,
            "shade": shade["hex"] if shade else None,
            "source": "image",
        }
        cells.append(sheet_cell(name, path, img, box, clusters, pick, shade, note, fonts))

    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(dump_palette(palette))

    cols = 2
    rows = (len(cells) + cols - 1) // cols
    cw, ch = cells[0].size
    sheet = Image.new("RGB", (cw * cols + 8 * (cols + 1), ch * rows + 8 * (rows + 1)), (12, 12, 16))
    for i, cell in enumerate(cells):
        cx, cy = i % cols, i // cols
        sheet.paste(cell, (8 + cx * (cw + 8), 8 + cy * (ch + 8)))
    os.makedirs(os.path.dirname(OUT_SHEET), exist_ok=True)
    sheet.save(OUT_SHEET)
    print(f"{len(palette)} regions -> {os.path.relpath(OUT_JSON, ROOT)}, {os.path.relpath(OUT_SHEET, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
