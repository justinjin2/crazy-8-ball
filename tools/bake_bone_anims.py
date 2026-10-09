#!/usr/bin/env python3
"""Bakes a rigged model's Blender animations (per-frame bone matrices, JSON) into a Luau data
module the client plays with src/client/BoneAnim.luau. Standard library only.

    python3 tools/bake_bone_anims.py tiger    # assets/abilities/GuangdongTiger/tiger_v2_anims.json

(The Verity monster's job went with it in the designer's second round, 2026-10-08: Verity is
an evil ball now, hinged pieces with no bones. Its clips stay in assets/abilities/Verity.)

For every kept action, frame and bone it writes the skinning delta S = P * R^-1 (P the posed
armature-space matrix, R the rest one), mapped into the uploaded model's space: Roblox's glTF
import turns Blender (x, y, z) into (-x, z, y) (STUDIO_NOTES "The cue skins import": the
half turn about Y), so the rotation is M S M^T and the translation M t. Each is stored as a
quaternion (x, y, z, w) and a translation, rounded, 7 numbers. Every bone's mapped rest
position goes in too, which fits the armature space to the loaded model at runtime (its
scale, and where its origin sits).
"""

import json
import math
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# What each model keeps: the action, its first and last frame (inclusive; None = all).
JOBS = {
    "tiger": {
        "source": "assets/abilities/GuangdongTiger/tiger_v2_anims.json",
        "out": "src/client/TigerAnims.luau",
        "title": "the Guangdong Tiger",
        "actions": [
            ("Run", None, None),
            ("Pounce", None, None),
            ("Swipe", None, None),
            ("Roar", None, None),
            ("Idle", None, None),
        ],
    },
}

M = [[-1, 0, 0], [0, 0, 1], [0, 1, 0]]


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def transpose(a):
    return [[a[j][i] for j in range(3)] for i in range(3)]


def apply(a, v):
    return [sum(a[i][k] * v[k] for k in range(3)) for i in range(3)]


def parse(m, layout):
    """12 numbers to (3x3 rotation, translation)."""
    if layout == "rows3_then_t":  # r00 r01 r02 r10 r11 r12 r20 r21 r22 tx ty tz
        rot = [m[0:3], m[3:6], m[6:9]]
        t = m[9:12]
    else:  # "rows3x4": r00 r01 r02 tx r10 r11 r12 ty r20 r21 r22 tz
        rot = [m[0:3], m[4:7], m[8:11]]
        t = [m[3], m[7], m[11]]
    return [list(r) for r in rot], list(t)


def orthonormal(r):
    """Gram-Schmidt the columns (the JSON is rounded to 4 decimals)."""
    cols = [[r[0][j], r[1][j], r[2][j]] for j in range(3)]
    out = []
    for c in cols:
        for o in out:
            d = sum(c[i] * o[i] for i in range(3))
            c = [c[i] - d * o[i] for i in range(3)]
        n = math.sqrt(sum(x * x for x in c)) or 1.0
        out.append([x / n for x in c])
    return [[out[j][i] for j in range(3)] for i in range(3)]


def quat(r):
    """Rotation matrix to a unit quaternion (x, y, z, w)."""
    tr = r[0][0] + r[1][1] + r[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        w = 0.25 * s
        x = (r[2][1] - r[1][2]) / s
        y = (r[0][2] - r[2][0]) / s
        z = (r[1][0] - r[0][1]) / s
    elif r[0][0] > r[1][1] and r[0][0] > r[2][2]:
        s = math.sqrt(1.0 + r[0][0] - r[1][1] - r[2][2]) * 2
        w = (r[2][1] - r[1][2]) / s
        x = 0.25 * s
        y = (r[0][1] + r[1][0]) / s
        z = (r[0][2] + r[2][0]) / s
    elif r[1][1] > r[2][2]:
        s = math.sqrt(1.0 + r[1][1] - r[0][0] - r[2][2]) * 2
        w = (r[0][2] - r[2][0]) / s
        x = (r[0][1] + r[1][0]) / s
        y = 0.25 * s
        z = (r[1][2] + r[2][1]) / s
    else:
        s = math.sqrt(1.0 + r[2][2] - r[0][0] - r[1][1]) * 2
        w = (r[1][0] - r[0][1]) / s
        x = (r[0][2] + r[2][0]) / s
        y = (r[1][2] + r[2][1]) / s
        z = 0.25 * s
    n = math.sqrt(x * x + y * y + z * z + w * w)
    q = [x / n, y / n, z / n, w / n]
    if q[3] < 0:  # one hemisphere, so neighbouring frames interpolate the short way
        q = [-c for c in q]
    return q


def delta(posed, rest):
    """S = P * R^-1 as (rotation, translation)."""
    pr, pt = posed
    rr, rt = rest
    rinv = transpose(rr)
    srot = matmul(pr, rinv)
    st = [pt[i] - apply(srot, rt)[i] for i in range(3)]
    return srot, st


def mapped(rot, t):
    return matmul(matmul(M, rot), transpose(M)), apply(M, t)


def fmt(x):
    s = "%.4f" % x
    s = s.rstrip("0").rstrip(".") if "." in s else s
    return "0" if s in ("-0", "") else s


def load(job):
    data = json.load(open(os.path.join(ROOT, job["source"])))
    bones, order, rests, actions = {}, [], {}, {}
    if isinstance(data["bones"], list):  # Verity: a list, actions a list with tracks
        layout = "rows3_then_t"
        for b in data["bones"]:
            order.append(b["name"])
            bones[b["name"]] = b["parent"]
            rests[b["name"]] = parse(b["rest"], layout)
        for a in data["actions"]:
            actions[a["name"]] = {
                "fps": a["fps"],
                "loop": a["loop"],
                "frames": a["frames"],
                "tracks": {k: [parse(m, layout) for m in v] for k, v in a["tracks"].items()},
            }
    else:  # the tiger: a dict of bones, boneOrder, actions with poses
        layout = "rows3x4"
        order = list(data["boneOrder"])
        for name in order:
            b = data["bones"][name]
            bones[name] = b["parent"]
            rests[name] = parse(b["rest"], layout)
        for name, a in data["actions"].items():
            actions[name] = {
                "fps": a["fps"],
                "loop": a["loop"],
                "frames": a["frames"],
                "tracks": {k: [parse(m, layout) for m in v] for k, v in a["poses"].items()},
            }
    return order, bones, rests, actions


def bake(key):
    job = JOBS[key]
    order, parents, rests, actions = load(job)
    root = next(n for n in order if parents[n] is None)
    rr = rests[root]
    root_rest = apply(M, rr[1])
    lines = [
        "--!strict",
        "-- Baked bone animations for %s (generated by tools/bake_bone_anims.py %s from" % (job["title"], key),
        "-- %s; do not edit by hand)." % job["source"],
        "-- Played by src/client/BoneAnim.luau: per action, per bone, a string of 7 numbers a frame",
        "-- (a quaternion x, y, z, w, then a translation): the skinning delta posed * rest^-1 in the",
        "-- uploaded model's space (Blender (x, y, z) -> (-x, z, y)). Strings keep StyLua off them.",
        "return {",
        "\tRoot = %s," % json.dumps(root),
        "\tRootRest = { %s }," % ", ".join(fmt(v) for v in root_rest),
        "\tBones = { %s }," % ", ".join(json.dumps(n) for n in order),
        "\tRest = {",
    ]
    for n in order:
        lines.append("\t\t[%s] = { %s }," % (json.dumps(n), ", ".join(fmt(v) for v in apply(M, rests[n][1]))))
    lines.append("\t},")
    lines.append("\tParents = {")
    for n in order:
        if parents[n] is not None:
            lines.append("\t\t[%s] = %s," % (json.dumps(n), json.dumps(parents[n])))
    lines.append("\t},")
    lines.append("\tActions = {")
    for name, first, last in job["actions"]:
        a = actions[name]
        lo = 0 if first is None else first
        hi = a["frames"] - 1 if last is None else min(last, a["frames"] - 1)
        frames = hi - lo + 1
        lines.append("\t\t%s = {" % name)
        lines.append("\t\t\tFps = %d," % a["fps"])
        lines.append("\t\t\tFrames = %d," % frames)
        lines.append("\t\t\tLoop = %s," % ("true" if a["loop"] and first is None and last is None else "false"))
        lines.append("\t\t\tTracks = {")
        for bone in order:
            track = a["tracks"].get(bone)
            if track is None:
                continue
            nums = []
            for f in range(lo, hi + 1):
                pr, pt = track[f]
                srot, st = delta((orthonormal(pr), pt), (orthonormal(rests[bone][0]), rests[bone][1]))
                mr, mt = mapped(srot, st)
                q = quat(mr)
                nums.extend(q + mt)
            lines.append("\t\t\t\t[%s] = \"%s\"," % (json.dumps(bone), ",".join(fmt(v) for v in nums)))
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append("}")
    out = os.path.join(ROOT, job["out"])
    with open(out, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    stylua = shutil.which("stylua") or os.path.expanduser("~/.aftman/bin/stylua")
    if os.path.exists(stylua):
        subprocess.run([stylua, out], cwd=ROOT, check=True)
    print("wrote", job["out"], "%.0f KB" % (os.path.getsize(out) / 1024))


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in JOBS:
        sys.exit("usage: tools/bake_bone_anims.py " + "|".join(JOBS))
    bake(sys.argv[1])
