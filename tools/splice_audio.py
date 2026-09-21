#!/usr/bin/env python3
"""Cut raw recordings into clean one-shots ready to upload to Roblox.

Drop recordings in assets/audio/raw/ and run this. It finds every hit in a take, cuts
each one out with a little lead-in and a fade, normalises it, and writes numbered files
into assets/audio/ for you to upload through Studio's Asset Manager.

    tools/splice_audio.py                # do everything in raw/
    tools/splice_audio.py raw/clack.wav  # just one file
    tools/splice_audio.py --list         # say what would be cut, write nothing

A file named roll_loop.* is treated differently: it is a LOOP, not a series of hits, so
it is never cut up. It gets trimmed to its steadiest stretch and crossfaded end-to-start
so it loops without a seam.

WAV works with nothing installed. Other formats need ffmpeg (brew install ffmpeg).
"""

import argparse
import math
import shutil
import subprocess
import sys
import wave
from pathlib import Path

try:
    import numpy as np
except ImportError:
    sys.exit("numpy is needed: python3 -m pip install numpy")

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "assets" / "audio" / "raw"
OUT = ROOT / "assets" / "audio"

# A hit is a sudden jump in loudness. These are in seconds and in dB below the loudest
# peak of the file, so they do not care how hot the recording was made.
ONSET_WINDOW = 0.005  # loudness is measured over 5ms blocks
MIN_GAP = 0.08  # two peaks closer than this are one hit, not two
LEAD_IN = 0.008  # keep this much before the attack, or it sounds clipped off
THRESHOLD_DB = -32.0  # anything quieter than this below peak is not a hit
FLOOR_DB = -45.0  # a clip ends when it has been this quiet for TAIL_QUIET
TAIL_QUIET = 0.06
MAX_LENGTH = 1.6  # no one-shot is longer than this
FADE_OUT = 0.02
LOOP_CROSSFADE = 0.25


def read_wav(path: Path):
    """Return (mono float32 in -1..1, sample rate). Uses ffmpeg only if it has to."""
    if path.suffix.lower() != ".wav":
        if not shutil.which("ffmpeg"):
            raise RuntimeError(
                f"{path.name} is not a WAV. Install ffmpeg (brew install ffmpeg) or "
                f"export it as WAV."
            )
        tmp = path.with_suffix(".converted.wav")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(path), str(tmp)], check=True
        )
        try:
            return read_wav(tmp)
        finally:
            tmp.unlink(missing_ok=True)

    with wave.open(str(path), "rb") as w:
        rate = w.getframerate()
        channels = w.getnchannels()
        width = w.getsampwidth()
        frames = w.readframes(w.getnframes())

    dtype = {1: np.uint8, 2: np.int16, 4: np.int32}.get(width)
    if dtype is None:
        raise RuntimeError(f"{path.name}: {width * 8}-bit WAV is not supported")
    data = np.frombuffer(frames, dtype=dtype).astype(np.float32)
    if width == 1:
        data = (data - 128.0) / 128.0
    else:
        data /= float(2 ** (width * 8 - 1))
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return data, rate


def write_wav(path: Path, samples: np.ndarray, rate: int):
    clipped = np.clip(samples, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def envelope(samples: np.ndarray, rate: int):
    """Loudness per small block, in dB below the file's own peak."""
    block = max(1, int(ONSET_WINDOW * rate))
    usable = len(samples) - len(samples) % block
    if usable == 0:
        return np.zeros(0), block
    blocks = samples[:usable].reshape(-1, block)
    rms = np.sqrt((blocks**2).mean(axis=1))
    peak = rms.max()
    if peak <= 0:
        return np.full(len(rms), -120.0), block
    return 20.0 * np.log10(np.maximum(rms, 1e-9) / peak), block


def find_hits(samples: np.ndarray, rate: int):
    """Start and end sample of every hit in the take."""
    db, block = envelope(samples, rate)
    if len(db) == 0:
        return []

    loud = db > THRESHOLD_DB
    min_gap_blocks = max(1, int(MIN_GAP / ONSET_WINDOW))
    quiet_blocks = max(1, int(TAIL_QUIET / ONSET_WINDOW))
    max_blocks = int(MAX_LENGTH / ONSET_WINDOW)

    hits = []
    i = 0
    while i < len(loud):
        if not loud[i]:
            i += 1
            continue
        # An attack: the first loud block after silence. Back off a touch so the very
        # start of the transient survives.
        start_block = max(0, i - int(LEAD_IN / ONSET_WINDOW))
        # Walk forward until it has been quiet for long enough, or we hit the cap.
        j, quiet_run = i, 0
        while j < len(db) and (j - i) < max_blocks:
            quiet_run = quiet_run + 1 if db[j] < FLOOR_DB else 0
            if quiet_run >= quiet_blocks:
                break
            j += 1
        end_block = min(len(db), j + 1)
        hits.append((start_block * block, end_block * block))
        i = max(j, i + min_gap_blocks)

    # Merge anything that ended up overlapping after the lead-in was applied.
    merged = []
    for s, e in hits:
        if merged and s < merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))
    return merged


def polish(clip: np.ndarray, rate: int):
    """Normalise to just under full scale and fade the tail so it cannot click."""
    peak = np.abs(clip).max()
    if peak > 0:
        clip = clip * (0.97 / peak)
    fade = min(len(clip), int(FADE_OUT * rate))
    if fade > 1:
        clip = clip.copy()
        clip[-fade:] *= np.linspace(1.0, 0.0, fade)
    return clip


def make_loop(samples: np.ndarray, rate: int):
    """Trim a roll recording to its steadiest stretch and crossfade it into a loop.

    A loop with a seam is worse than no loop at all: you hear a click every few seconds
    and it is the only thing you hear. So the end is faded into the start, which makes
    the join continuous by construction.
    """
    db, block = envelope(samples, rate)
    if len(db) == 0:
        return samples
    # The steadiest window is the one whose loudness varies least.
    want_blocks = min(len(db), int(3.0 / ONSET_WINDOW))
    best, best_var = 0, None
    for start in range(0, max(1, len(db) - want_blocks), max(1, want_blocks // 8)):
        var = float(db[start : start + want_blocks].var())
        if best_var is None or var < best_var:
            best, best_var = start, var
    clip = samples[best * block : (best + want_blocks) * block].copy()

    fade = min(len(clip) // 3, int(LOOP_CROSSFADE * rate))
    if fade > 1:
        ramp = np.linspace(0.0, 1.0, fade)
        head, tail = clip[:fade], clip[-fade:]
        clip = clip[:-fade]
        clip[:fade] = head * ramp + tail * (1.0 - ramp)
    peak = np.abs(clip).max()
    if peak > 0:
        clip *= 0.9 / peak
    return clip


# The prefix of a raw file names the event it belongs to. Longest first, so that
# ball_clack_rattle_* is not swallowed by ball_clack_*. These match the names already in
# use for the uploaded set, so re-recording a replacement can reuse its existing name.
KNOWN_PREFIXES = (
    "ball_clack_rattle",
    "ball_hitting_edge",
    "ball_rolling",
    "ball_clack",
    "cue_strike",
    "pocket_drop",
    "roll_loop",
    "clack",
    "rail",
    "strike",
    "pocket",
    "tick",
    "roll",
)

# Which prefixes are continuous material rather than a series of hits.
ROLL_PREFIXES = ("ball_rolling", "roll_loop", "roll")


def base_name(path: Path):
    """ball_clack_rattle_take3.wav -> ball_clack_rattle."""
    stem = path.stem.lower()
    for known in KNOWN_PREFIXES:
        if stem.startswith(known):
            return known
    return stem.split("_")[0]


def process(path: Path, listing: bool):
    samples, rate = read_wav(path)
    name = base_name(path)
    seconds = len(samples) / rate

    if name in ROLL_PREFIXES:
        # Rolling material is one continuous sound, not a series of hits, so it is trimmed
        # to its steadiest stretch rather than cut up. The end-to-start crossfade is now
        # belt and braces: the game crossfades two copies at runtime, so it never reaches a
        # seam anyway (Roblox re-encodes uploads, so no uploaded file is seamless for sure).
        clip = make_loop(samples, rate)
        target = OUT / f"{name}.wav"
        print(f"{path.name}: {seconds:.2f}s roll -> {len(clip)/rate:.2f}s steady stretch")
        if not listing:
            write_wav(target, clip, rate)
            print(f"  wrote {target.relative_to(ROOT)}")
        return 1

    hits = find_hits(samples, rate)
    if not hits:
        print(f"{path.name}: {seconds:.2f}s, nothing loud enough to cut")
        return 0

    print(f"{path.name}: {seconds:.2f}s, {len(hits)} hit(s)")
    if listing:
        for n, (s, e) in enumerate(hits, 1):
            print(f"  {n:02d}  {s/rate:6.3f}s  {(e-s)/rate:.3f}s long")
        return len(hits)

    # Number from whatever is already there, so running twice adds rather than clobbers.
    existing = sorted(OUT.glob(f"{name}_*.wav"))
    start_at = 1
    for f in existing:
        tail = f.stem.rsplit("_", 1)[-1]
        if tail.isdigit():
            start_at = max(start_at, int(tail) + 1)

    for n, (s, e) in enumerate(hits):
        clip = polish(samples[s:e], rate)
        target = OUT / f"{name}_{start_at + n:02d}.wav"
        write_wav(target, clip, rate)
        print(f"  wrote {target.relative_to(ROOT)}  ({len(clip)/rate:.3f}s)")
    return len(hits)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="files to cut (default: everything in raw/)")
    ap.add_argument("--list", action="store_true", dest="listing",
                    help="say what would be cut, write nothing")
    args = ap.parse_args()

    if args.files:
        paths = [Path(f) if Path(f).is_absolute() else ROOT / f for f in args.files]
    else:
        if not RAW.is_dir():
            sys.exit(f"no {RAW.relative_to(ROOT)} folder")
        paths = sorted(p for p in RAW.iterdir()
                       if p.is_file() and not p.name.startswith("."))

    if not paths:
        print(f"Nothing in {RAW.relative_to(ROOT)}. Drop recordings in there and run again.")
        print("See assets/audio/README.md for what to record.")
        return

    OUT.mkdir(parents=True, exist_ok=True)
    total = 0
    for p in paths:
        try:
            total += process(p, args.listing)
        except Exception as exc:  # one bad file must not stop the rest
            print(f"{p.name}: {exc}")

    print()
    if args.listing:
        print(f"{total} clip(s) would be written. Drop --list to write them.")
    else:
        print(f"{total} clip(s) in {OUT.relative_to(ROOT)}.")
        print("Now upload them: Studio -> View -> Asset Manager -> Audio ->")
        print("right-click -> Add Audio (you can select them all at once).")


if __name__ == "__main__":
    main()
