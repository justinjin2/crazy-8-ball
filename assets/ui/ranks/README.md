# Rank badges

Made by `tools/gen_rank_badges.py`. To change a badge, change the generator and run
`python3 tools/gen_rank_badges.py`; never edit the PNGs or SVGs by hand.

**In the game** since 2026-09-27: all 95 images uploaded, ids in `Config.UI.Ranks` (keyed by
file name), shown by `src/client/RankBadge.luau`. Design notes: `docs/UI_STYLE.md` sections 6
and 7.

## Files

| File | What it is |
|---|---|
| `unranked.png` | plain grey badge; no pips, no shine |
| `bronze_1.png` to `diamond_5.png` | 1 to 5 stars (bronze, silver, gold, platinum, diamond) |
| `expert_1.png` to `grandmaster_5.png` | 1 to 5 gems and a crown (expert, veteran, master, grandmaster in black and gold) |
| `reyes.png` | one badge: rainbow, the biggest crown, no pips |
| `shine/<same name>.png` | the badge's shape in white, which the light sweep is clipped to |
| `sparkle.png` | the white twinkle for Expert and up (128 px) |
| `*.svg` | the drawings the PNGs are rendered from |
| `preview.html` | every badge with its animation (see below) |

The number is the division: `_1` is I (the bottom), `_5` is V (the top). Badges are 512 px
(Roblox shows images up to 1024 px, so they stay sharp). Going in the game means 95 uploads:
47 badges, 47 shine masks and the sparkle.

**Each tier is its own badge** after the designer's reference sheet, but the 8 ball and its
ring are the same size in the same place on every one (50% across, 54% down); crowns rise
above and pips sit in an arc under the ball. So one ImageLabel can switch from any badge to
any other (for a rank-up animation) without the ball jumping.

## The shine (in the game: `Config.UI.Ranks.Shine`)

Mostly sparkles, with a faint light sweep now and then (designer, 2026-09-27: the first
version shimmered too much).

| Tiers | Light sweep | Sparkles | Extra |
|---|---|---|---|
| Unranked | none | none | |
| Bronze to Diamond | every 9 s, faint | 2 (2.6 s cycle) | |
| Expert to Grandmaster | every 8 s, faint | 3 (2.0 s cycle) | |
| Reyes | every 7 s, faint | 5 (1.5 s cycle) | gold rays turning once every 14 s |

A badge that reacts to the mouse bursts sparkles when hovered and pressed.

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

Or, without a browser: `python3 tools/gen_rank_badges.py --gif shine.gif` writes a looping
GIF of every badge shining (and `--sheet sheet.png` a still contact sheet). Keep those out of
the repo; they are for reviewing.
