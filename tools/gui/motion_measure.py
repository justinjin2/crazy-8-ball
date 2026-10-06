"""Measure how smoothly GUI pieces move in a screen recording (the lively GUI's gate 1).

Roblox draws GUI positions in whole pixels, so a slow move can step: still, still, jump. This
reads every frame of a recording, tracks each region and scores how evenly it moves.

Region kinds:
- "shift": a scrolling pattern; per-frame (dx, dy) by phase correlation with a sub-pixel
  peak. A smooth scroll moves the same small amount every frame.
- "centroid": a moving bright mark (the ball's white disc); its brightness-weighted centre.
- "size": a breathing bright mark; the square root of its bright area (its size).

Score ("jitter"): the root-mean-square difference between each frame's step and the average
step of the 9 frames round it, in physical pixels. A smooth move scores near 0; a move in
whole pixels at under a pixel a frame scores about 0.4 to 0.5 (steps of 0 and 1).

Run:
  tools/gui/.venv/bin/python tools/gui/motion_measure.py VIDEO REGIONS.json OUT_DIR
REGIONS.json: [{"name": "a", "kind": "shift", "box": [x, y, w, h]}, ...] in video pixels.
Writes OUT_DIR/measure.json and OUT_DIR/measure.png (one trace per region).
"""

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


def frames(video: str):
    """Every frame (no resampling) as a grey float array, with its time."""
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries",
         "stream=width,height", "-of", "csv=p=0", video],
        capture_output=True, text=True, check=True,
    ).stdout.strip().split(",")
    w, h = int(probe[0]), int(probe[1])
    times = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "frame=pts_time",
         "-of", "csv=p=0", video],
        capture_output=True, text=True, check=True,
    ).stdout.split()
    proc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", video, "-fps_mode", "passthrough", "-f", "rawvideo",
         "-pix_fmt", "gray", "-"],
        stdout=subprocess.PIPE,
    )
    size = w * h
    index = 0
    while True:
        data = proc.stdout.read(size)
        if len(data) < size:
            break
        t = float(times[index].strip(",")) if index < len(times) else index / 60
        yield t, np.frombuffer(data, np.uint8).reshape(h, w).astype(np.float32)
        index += 1


def phase_shift(a: np.ndarray, b: np.ndarray):
    """How far b is moved from a (dx, dy), with a parabolic sub-pixel peak."""
    window = np.outer(np.hanning(a.shape[0]), np.hanning(a.shape[1]))
    fa = np.fft.fft2((a - a.mean()) * window)
    fb = np.fft.fft2((b - b.mean()) * window)
    cross = fa * np.conj(fb)
    cross /= np.abs(cross) + 1e-9
    r = np.fft.ifft2(cross).real
    py, px = np.unravel_index(np.argmax(r), r.shape)

    def sub(c_m, c_0, c_p):
        d = c_m - 2 * c_0 + c_p
        return 0.0 if abs(d) < 1e-12 else 0.5 * (c_m - c_p) / d

    hy, hx = r.shape
    dy = py + sub(r[(py - 1) % hy, px], r[py, px], r[(py + 1) % hy, px])
    dx = px + sub(r[py, (px - 1) % hx], r[py, px], r[py, (px + 1) % hx])
    dy = dy - hy if dy > hy / 2 else dy
    dx = dx - hx if dx > hx / 2 else dx
    return -dx, -dy


def bright(region: np.ndarray):
    mask = np.clip((region - 150) / 80, 0, 1)
    return mask


def jitter(steps: np.ndarray) -> float:
    if len(steps) < 12:
        return float("nan")
    k = 9
    pad = np.pad(steps, k // 2, mode="edge")
    local = np.convolve(pad, np.ones(k) / k, mode="valid")
    return float(np.sqrt(np.mean((steps - local) ** 2)))


def main():
    video, regions_path, out = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    regions = json.loads(Path(regions_path).read_text())
    series = {r["name"]: [] for r in regions}
    stamps = {r["name"]: [] for r in regions}
    previous = {}
    previous_t = {}
    times = []
    for t, frame in frames(video):
        times.append(t)
        for r in regions:
            x, y, w, h = r["box"]
            crop = frame[y : y + h, x : x + w]
            name = r["name"]
            if r["kind"] == "shift":
                if name in previous:
                    dx, dy = phase_shift(previous[name], crop)
                    series[name].append((dx, dy))
                    stamps[name].append(t - previous_t[name])
                previous[name] = crop
                previous_t[name] = t
            elif r["kind"] == "centroid":
                m = bright(crop)
                total = m.sum()
                if total > 0:
                    ys, xs = np.mgrid[0:h, 0:w]
                    series[name].append(((xs * m).sum() / total, (ys * m).sum() / total))
                else:
                    series[name].append((np.nan, np.nan))
                stamps[name].append(t)
            elif r["kind"] == "size":
                series[name].append((float(np.sqrt(bright(crop).sum())), 0.0))
                stamps[name].append(t)
    result = {"frames": len(times), "seconds": times[-1] - times[0] if times else 0, "regions": {}}
    for r in regions:
        name = r["name"]
        values = np.array(series[name], dtype=float)
        when = np.array(stamps[name], dtype=float)
        if r["kind"] == "shift":
            steps = values[:, 0] + values[:, 1]  # 45 degrees: both axes move alike
            gaps = when
        elif r["kind"] == "centroid":
            steps = np.diff(values[:, 1])
            gaps = np.diff(when)
        else:
            steps = np.diff(values[:, 0])
            gaps = np.diff(when)
        # Frames do not arrive exactly 1/60 s apart: scale each step to one 60 fps frame.
        gaps = np.where(gaps > 1e-4, gaps, 1 / 60)
        steps = steps / (gaps * 60)
        steps = steps[np.isfinite(steps)]
        zeros = float(np.mean(np.abs(steps) < 0.05)) if len(steps) else float("nan")
        result["regions"][name] = {
            "kind": r["kind"],
            "jitter_px": round(jitter(steps), 3),
            "mean_step_px": round(float(np.mean(np.abs(steps))), 3) if len(steps) else None,
            "still_frames": round(zeros, 3),
            "steps": [round(float(s), 3) for s in steps[:240]],
        }
    (out / "measure.json").write_text(json.dumps(result, indent=1))

    # One trace per region: each frame's step, so even motion is a smooth line.
    rows = len(regions)
    width, row_h = 1200, 120
    chart = Image.new("RGB", (width, rows * row_h + 10), (250, 250, 252))
    draw = ImageDraw.Draw(chart)
    for i, r in enumerate(regions):
        info = result["regions"][r["name"]]
        steps = info["steps"][:200]
        top = i * row_h + 10
        draw.text((8, top), f'{r["name"]}  jitter {info["jitter_px"]} px  still {info["still_frames"]}', fill=(20, 20, 40))
        if not steps:
            continue
        lo, hi = min(steps + [0]), max(steps + [0.1])
        span = max(hi - lo, 1e-3)
        mid = top + 20
        plot_h = row_h - 30
        points = [
            (10 + j * (width - 20) / max(1, len(steps) - 1), mid + plot_h - (s - lo) / span * plot_h)
            for j, s in enumerate(steps)
        ]
        zero_y = mid + plot_h - (0 - lo) / span * plot_h
        draw.line([(10, zero_y), (width - 10, zero_y)], fill=(200, 200, 210))
        draw.line(points, fill=(40, 90, 200), width=2)
        for p in points:
            draw.ellipse((p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2), fill=(40, 90, 200))
    chart.save(out / "measure.png")
    for name, info in result["regions"].items():
        print(f'{name:22s} jitter {info["jitter_px"]:6.3f}  mean step {info["mean_step_px"]}  still {info["still_frames"]}')


if __name__ == "__main__":
    main()
