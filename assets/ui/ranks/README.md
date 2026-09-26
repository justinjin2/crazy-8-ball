# Rank badges

Made by `tools/gen_rank_badges.py`. To change a badge, change the generator and run
`python3 tools/gen_rank_badges.py`; never edit the PNGs or SVGs by hand.

**Not in the game yet** (designer, 2026-09-26): not uploaded to Roblox and not in Config, so this
work does not overlap the map work in Studio. Design notes: `docs/UI_STYLE.md` sections 6 and 7.

## Files

| File | What it is |
|---|---|
| `unranked.png` | plain grey badge; no pips, no shine |
| `bronze_1.png` to `diamond_5.png` | 1 to 5 stars (bronze, silver, gold, platinum, diamond) |
| `expert_1.png` to `grandmaster_5.png` | 1 to 5 gems and a crown (expert, veteran, master, grandmaster) |
| `reyes.png` | one badge: black and gold, the biggest crown, no pips |
| `shine/<same name>.png` | the badge's shape in white, which the light sweep is clipped to |
| `sparkle.png` | the white twinkle for Expert and up (128 px) |
| `*.svg` | the drawings the PNGs are rendered from |
| `preview.html` | every badge with its animation (see below) |

The number is the division: `_1` is I (the bottom), `_5` is V (the top). Badges are 512 px
(Roblox shows images up to 1024 px, so they stay sharp). Going in the game means 95 uploads:
47 badges, 47 shine masks and the sparkle.

**Same layout on every badge.** The 8 ball's centre is at 50% across and 58% down, and the
shield, ring and ball are the same size on every badge; crowns rise above and pips sit in an
arc under the ball. So one ImageLabel can switch from any badge to any other (for a rank-up
animation) without anything jumping.

## The shine (starting values, for Config when the badges go in)

| Tiers | Light sweep | Sparkles | Extra |
|---|---|---|---|
| Unranked | none | none | |
| Bronze to Diamond | every 4 s, 0.9 s across | none | |
| Expert to Grandmaster | every 3 s, 0.8 s across | 3, one after another (1.6 s cycle) | |
| Reyes | every 2.2 s, 0.7 s across | 5 (1.4 s cycle) | gold rays turning once every 14 s |

How to build it in Roblox (the same band as `UIAnim.shine`):
1. The badge is an ImageLabel.
2. On top of it, the same size, an ImageLabel showing `shine/<name>.png` in white, with a
   UIGradient: Rotation 20, transparency 1 everywhere except a narrow band (0.35 in the middle,
   as in `UIAnim.shine`). Tweening the gradient's Offset from (-1, 0) to (1, 0) moves the band
   across; because the mask is the badge's shape, only the badge lights up. Wait, repeat.
3. Sparkles (Expert and up): small ImageLabels with `sparkle.png` that grow from nothing and
   shrink back while turning, at bright spots such as crown tips, wing tips and shield corners.
4. Reyes: `assets/ui/art/rays.png` behind the badge, tinted gold (#FFC928), about 55%
   transparent, turning slowly.
5. Every loop stops when its screen closes (UI_STYLE section 7). Many badges on one screen (a
   leaderboard) can share one clock.

## Preview

`preview.html` draws every badge with the shine above, the way the game will. Chrome needs the
folder served over http to show it:

```bash
python3 -m http.server 8765 --directory assets/ui
```

then open http://localhost:8765/ranks/preview.html (tick "dark background" to see the
sparkles and Reyes' rays best).
