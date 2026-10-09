#!/usr/bin/env python3
"""Tutorial v2: top-down drawings of the chosen layout for the plan page, from
draw_layout.luau's JSON: the break (where the balls start and stop, the paths of the two that
drop), the turn-2 lesson shot (every ball's path) and the Fire Shot setup it leaves.

    python3 tools/tutorial_v2/draw_layout.py layout.json <outDir>
"""
import json
import os
import sys

COLORS = {
    0: "#f4f1e8", 1: "#f2c318", 2: "#1f4fbf", 3: "#d8262b", 4: "#5b2a86", 5: "#f07d1a",
    6: "#1e8a43", 7: "#7a1f1f", 8: "#111111",
}
for i in range(9, 16):
    COLORS[i] = COLORS[i - 8]

S = 9.0  # pixels per inch
PAD = 40


def svg_open(d, title):
    hl, hw = d["table"]["halfLength"], d["table"]["halfWidth"]
    w, h = (2 * hl) * S + 2 * PAD, (2 * hw) * S + 2 * PAD + 30
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.0f} {h:.0f}" width="{w:.0f}" height="{h:.0f}" font-family="Fredoka, Arial, sans-serif">']
    out.append(f'<rect x="0" y="0" width="{w:.0f}" height="{h:.0f}" fill="#5a3a22" rx="22"/>')
    out.append(f'<rect x="{PAD - 14}" y="{PAD - 14}" width="{2 * hl * S + 28:.0f}" height="{2 * hw * S + 28:.0f}" fill="#3b2414" rx="16"/>')
    out.append(f'<rect x="{PAD}" y="{PAD}" width="{2 * hl * S:.0f}" height="{2 * hw * S:.0f}" fill="#1d8fd1"/>')
    for p in d["pockets"]:
        x, y = to(d, p["mx"], p["my"])
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{2.6 * S:.1f}" fill="#0c0c0c"/>')
        lx, ly = to(d, p["x"], p["y"])
        out.append(f'<text x="{lx:.1f}" y="{ly + (14 if p["y"] < 0 else -6):.1f}" fill="#f5e6c8" font-size="13" text-anchor="middle">P{p["id"]}</text>')
    hx, _ = to(d, -25, 0)
    out.append(f'<line x1="{hx:.1f}" y1="{PAD}" x2="{hx:.1f}" y2="{PAD + 2 * hw * S:.1f}" stroke="#ffffff" stroke-opacity="0.25" stroke-dasharray="6 6"/>')
    out.append(f'<text x="{w / 2:.0f}" y="{h - 12:.0f}" fill="#fff4dc" font-size="18" text-anchor="middle">{title}</text>')
    return out


def to(d, x, y):
    hl, hw = d["table"]["halfLength"], d["table"]["halfWidth"]
    return PAD + (x + hl) * S, PAD + (hw - y) * S


def ball(d, out, b, ghost=False, ring=None):
    bid, x, y = b
    px, py = to(d, x, y)
    r = d["table"]["radius"] * S
    if ghost:
        out.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{r:.1f}" fill="none" stroke="#ffffff" stroke-width="2" stroke-dasharray="4 3"/>')
        return
    out.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{r:.1f}" fill="{COLORS[bid]}" stroke="#000" stroke-width="1.2"/>')
    if bid >= 9:
        out.append(f'<rect x="{px - r:.1f}" y="{py - r * 0.38:.1f}" width="{2 * r:.1f}" height="{r * 0.76:.1f}" fill="#f4f1e8" opacity="0.9"/>')
        out.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{r:.1f}" fill="none" stroke="#000" stroke-width="1.2"/>')
    if bid != 0:
        out.append(f'<text x="{px:.1f}" y="{py + 4:.1f}" fill="{"#000" if bid in (1, 9) else "#fff"}" font-size="10" font-weight="bold" text-anchor="middle">{bid}</text>')
    if ring:
        out.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{r + 5:.1f}" fill="none" stroke="{ring}" stroke-width="3"/>')


def path(d, out, pts, color, width=2.5, dash=None, opacity=0.9):
    if len(pts) < 2:
        return
    s = " ".join(f"{to(d, x, y)[0]:.1f},{to(d, x, y)[1]:.1f}" for x, y in pts)
    extra = f' stroke-dasharray="{dash}"' if dash else ""
    out.append(f'<polyline points="{s}" fill="none" stroke="{color}" stroke-width="{width}" stroke-opacity="{opacity}" stroke-linecap="round"{extra}/>')


def line(d, out, a, b, color, width=2, dash=None):
    (x1, y1), (x2, y2) = to(d, *a), to(d, *b)
    extra = f' stroke-dasharray="{dash}"' if dash else ""
    out.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{color}" stroke-width="{width}"{extra}/>')


def mouth(d, pid):
    for p in d["pockets"]:
        if p["id"] == pid:
            return p["mx"], p["my"]


def draw_break(d):
    br = d["breakShot"]
    out = svg_open(d, "1. The break: 2 solids drop (paths drawn), dashed rings are the rack")
    dropped = {x["ball"] for x in br["drops"]}
    for bid in sorted(dropped):
        path(d, out, br["paths"].get(str(bid), []), COLORS[bid], 3)
    path(d, out, br["paths"].get("0", []), "#ffffff", 2, "5 4", 0.7)
    for b in br["rack"]:
        if b[0] != 0:
            ball(d, out, b, ghost=True)
    for b in br["after"]:
        ball(d, out, b, ring="#ffd64a" if b[0] == 8 else None)
    cx, cy = to(d, *br["cue"])
    out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{d["table"]["radius"] * S:.1f}" fill="none" stroke="#fff" stroke-width="2"/>')
    out.append(f'<text x="{cx:.1f}" y="{cy - 16:.1f}" fill="#fff" font-size="12" text-anchor="middle">start</text>')
    out.append("</svg>")
    return "\n".join(out)


def draw_turn2(d):
    t = d["turn2"]
    out = svg_open(d, "2. Turn 2, played perfectly: ball 3 into the side, ball 5 follows (x2)")
    cue = [b for b in t["before"] if b[0] == 0][0]
    line(d, out, (cue[1], cue[2]), (t["pot"]["ghostX"], t["pot"]["ghostY"]), "#ffffff", 2, "6 4")
    for bid, pts in t["paths"].items():
        bid = int(bid)
        if len(pts) > 1:
            path(d, out, pts, "#ffffff" if bid == 0 else COLORS[bid], 3 if bid in (0, t["pot"]["ball"]) else 2.2)
    for b in t["before"]:
        ball(d, out, b, ring="#ffd64a" if b[0] == t["pot"]["ball"] else None)
    ball(d, out, (0, t["pot"]["ghostX"], t["pot"]["ghostY"]), ghost=True)
    out.append("</svg>")
    return "\n".join(out)


def draw_fire(d):
    t = d["turn2"]
    f = d["fire"]
    out = svg_open(d, "3. The Fire Shot it leaves: ball 1 far from its pocket (orange line)")
    cue = [b for b in t["after"] if b[0] == 0][0]
    if f:
        line(d, out, (cue[1], cue[2]), (f["ghostX"], f["ghostY"]), "#ff8a1f", 4)
        ob = [b for b in t["after"] if b[0] == f["ball"]][0]
        line(d, out, (ob[1], ob[2]), mouth(d, f["pocket"]), "#ff8a1f", 4, "10 6")
    for b in t["after"]:
        ball(d, out, b, ring="#ff8a1f" if f and b[0] == f["ball"] else None)
    if f:
        ball(d, out, (0, f["ghostX"], f["ghostY"]), ghost=True)
    out.append("</svg>")
    return "\n".join(out)


def main():
    d = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for name, fn in (("layout_break.svg", draw_break), ("layout_turn2.svg", draw_turn2), ("layout_fire.svg", draw_fire)):
        open(os.path.join(out, name), "w").write(fn(d))
        print("wrote", name)


if __name__ == "__main__":
    main()
