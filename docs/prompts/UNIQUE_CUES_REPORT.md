# Unique cues: the report

The Unique cues lane (brief `UNIQUE_CUES_PROMPT.md`, branch `lane-unique`, worktree
`~/Desktop/8ball-unique`, Studio copy `lane-unique.rbxl`), 2026-10-04. **Both cues are
complete and passed all three gates.** The techniques are written up in
`docs/CUE_VFX_TECHNIQUES.md`; the integrator's steps are in the brief's Handoff section.

## What was built

**The Beta Cue** (Limited, Unique tier, above Secret): a see-through blueprint hologram.
Painted blueprint linework on a part-transparent electric-blue body with magenta rings and a
white, holographic tip; a hexagon wireframe lattice that turns and glitches; section rings
that breathe; a scan line sweeping tip to butt; eight floating blueprint panels that pop in,
type gibberish glyphs and dissolve on their own life cycles; two scrolling wireframe beams;
blue haze, data motes, glints and glyph flecks; three data-stream orbiters; a faint hologram
hum. Trail: a wide blue-to-magenta light stream with a white core, rings peeling off, shards
and glyphs. Pocket: a wireframe funnel rises turning out of the pocket, rings lighting, a
column of blue light, digital shards, a flare, motes.

**The Grand Opening Cue** (Limited, Unique tier): navy lacquer with gold inlays, painted
fireworks and stars that glow, a quilted wrap and gold collars; two 3D gold ribbon helices
turning like a screw with sparkle heads riding them; mini fireworks popping in five colours
with a big burst every few seconds; gold glitter, star glints, crackle sparks falling,
sparkler lights; a faint crackle. Trail: a gold sparkler streamer with a white-gold core,
falling sparks and coloured starlets. Pocket: a four-shot spark fountain, then five staggered
firework bursts in gold, pink, cyan, purple and blue, glitter raining, with a fireworks sound.

Both have Lower-effects variants (Beta's far panels hide; rates drop to a third), quiet to a
quarter in the shooter's hands, their own outline colours, no-aura card pictures and Index
cards in the Unique row.

## New generic capabilities (any cue can use them)

`saw` and `life` wave shapes; the `Glitch` motion; joint visuals `Fade`, `Blink`, `Glow` and
`Type` (3D typing panels); joint `Low = "hide"`; `Aura.Sound` and `Pocket.Sound`; pocket
piece `Outline`, `ShellFade`, `EmissiveScale`; sound paths in skin data; alpha in the paint
kit for see-through surfaces. All listed with files in `docs/parallel/unique.md`, "Changes to
shared files".

## Screenshots

`assets/cue/concepts/unique/`: the approved boards (`beta-board.png`,
`grand_opening-board.png`), the Studio looks (`beta-studio-*.jpg`,
`grand-opening-studio-*.jpg`: stand, close, back, panel, low, trail, pocket, fireworks), the
Index cards (`beta-index.jpg`, `grand-opening-index.jpg`) and the gate-3 lineup
(`lineup-six-high.jpg`, `lineup-beta-grand-opening-eclipse.jpg`,
`lineup-apex-kitsune-dragon.jpg`).

## What was checked

- `tools/lint.sh` and `tools/test.sh` (984 tests) green at every step; new tests for the
  motion kinds and the built-mesh list.
- In the lane window: templates and pieces rebuilt with the builder; the lab beside Eclipse,
  Apex, Kitsune and the Celestial Dragon from three angles; a solo fixture match for the hands
  (quieting), the trail over the felt, the pocket finisher and both sounds; Lower effects; the
  Index tab. Console clean.
- Not checked: phone and gamepad emulation (no controls were added; the looks are
  input-independent), and a live two-player match (the fixture was solo).

## Spend

OpenAI images: eight panel paints (four a cue) at about $0.04 each, about $0.30 in total
(`assets/cue/concepts/openai_log.jsonl`, tags `beta:*` and `grand_opening:*`). Meshy: none
(every piece was built in Blender from the kit). Roblox uploads: free (group assets).

## Designer decisions along the way

In the brief's Decisions: built on the 0.36 cue; the three sounds from the designer's
Downloads; own outline colours; the holographic then white tip; brighter fireworks; both pass
at gate 3; the techniques doc wanted, and the same bar to be applied back to the rarer
existing cues (Eclipse first).
