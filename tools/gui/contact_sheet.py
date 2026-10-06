"""Contact sheets from a screen recording (the lively GUI's verification, SHOP_LIVELY_PROMPT 7.5).

Two kinds:
  sheet  every Nth frame of a part of the video, numbered with its time, in a grid (like the
         designer's stills 01 to 08 of another game's shop opening):
         contact_sheet.py sheet VIDEO OUT.png --box x y w h --every 2 --cols 6 --width 480
         [--start SECONDS] [--count N]
  strip  consecutive frames of one small region blown up with hard pixels, so a whole-pixel
         step (still, still, jump) is easy to see:
         contact_sheet.py strip VIDEO OUT.png --box x y w h --count 12 --zoom 4 [--start S]
Boxes are in video pixels. Frames are read as recorded (no resampling).
"""

import argparse
import subprocess

from PIL import Image, ImageDraw


def read_frames(video, box, start, count, every):
    x, y, w, h = box
    times = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "frame=pts_time",
         "-of", "csv=p=0", video],
        capture_output=True, text=True, check=True,
    ).stdout.split()
    times = [float(t.strip(",")) for t in times]
    proc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", video, "-fps_mode", "passthrough", "-vf",
         f"crop={w}:{h}:{x}:{y}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE,
    )
    size = w * h * 3
    index = 0
    taken = []
    first = None
    while len(taken) < count:
        data = proc.stdout.read(size)
        if len(data) < size:
            break
        t = times[index] if index < len(times) else index / 60
        index += 1
        if t < start:
            continue
        if first is None:
            first = index
        if (index - first) % every:
            continue
        taken.append((t, Image.frombytes("RGB", (w, h), data)))
    proc.kill()
    return taken


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["sheet", "strip"])
    ap.add_argument("video")
    ap.add_argument("out")
    ap.add_argument("--box", type=int, nargs=4, required=True)
    ap.add_argument("--start", type=float, default=0)
    ap.add_argument("--count", type=int, default=24)
    ap.add_argument("--every", type=int, default=2)
    ap.add_argument("--cols", type=int, default=6)
    ap.add_argument("--width", type=int, default=480)
    ap.add_argument("--zoom", type=int, default=4)
    a = ap.parse_args()
    if a.kind == "sheet":
        frames = read_frames(a.video, a.box, a.start, a.count, a.every)
        w = a.width
        h = int(a.box[3] * w / a.box[2])
        rows = (len(frames) + a.cols - 1) // a.cols
        out = Image.new("RGB", (a.cols * w, rows * (h + 18)), (255, 255, 255))
        d = ImageDraw.Draw(out)
        t0 = frames[0][0] if frames else 0
        for i, (t, im) in enumerate(frames):
            cx, cy = (i % a.cols) * w, (i // a.cols) * (h + 18)
            out.paste(im.resize((w, h), Image.LANCZOS), (cx, cy + 18))
            d.text((cx + 4, cy + 3), f"{(t - t0) * 1000:5.0f} ms", fill=(0, 0, 0))
    else:
        frames = read_frames(a.video, a.box, a.start, a.count, 1)
        w, h = a.box[2] * a.zoom, a.box[3] * a.zoom
        out = Image.new("RGB", (len(frames) * (w + 4), h + 18), (255, 255, 255))
        d = ImageDraw.Draw(out)
        t0 = frames[0][0] if frames else 0
        for i, (t, im) in enumerate(frames):
            out.paste(im.resize((w, h), Image.NEAREST), (i * (w + 4), 18))
            d.text((i * (w + 4) + 4, 3), f"{(t - t0) * 1000:4.0f} ms", fill=(0, 0, 0))
    out.save(a.out)
    print(a.out, out.size)


if __name__ == "__main__":
    main()
