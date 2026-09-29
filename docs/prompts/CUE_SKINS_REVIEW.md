# Cue skins: the review checklist

One row per skin. Look at the **sheet** first (the render beside its concept, labelled), then the
**clip**. Write `OK` or `fix: ...` in the **Designer** column; fixes are done before any new skin,
then the note becomes `fixed (date)`.

Files are under `assets/cue/renders/` (not in git; rebuild any of them with
`python3 tools/cue_skin.py <id>`): `skins/<id>/sheet.png`, `skins/<id>/clip.mp4`, and the tier
contact sheets `tiers/<tier>.png`.

Painters: **proc** = drawn by script (`assets/cue/CuePaint.py`), **AI** = painted by OpenAI from
the concept crops, **mix** = both. Particle rates are per cue (in hand); the back version runs at
`BackRateScale` of it.

| Id | Name | Tier | Files | Built (painter, VFX pieces, particles/s) | Differs from the concept | Designer |
|---|---|---|---|---|---|---|
| midnight | Midnight | Common | skins/midnight/sheet.png, clip.mp4 | proc: gloss black with metal flake, a brushed silver-grey stripe tapering to a point along the top of the forearm with chrome pinstripe edges, chrome collar, ring and butt-cap band, pebbled black leather wrap. VFX: none (the white wisp). | The stripe is on the top of the cue (what you see in the hand and on the back), not the side the concept shows; it is silver-grey (as the concept) rather than the plan's matte #6B6E73. The sleeve is the mesh's (shorter than the concept's). | |
| honeycomb | Honeycomb | Rare | skins/honeycomb/sheet.png, clip.mp4 | proc: 7-round hexagon comb (glowing gold walls, glossy amber-brown cells) on the forearm and sleeve, honey pooling on top and running down, chocolate grip with 3 amber spiral stripes, gold rings, deep amber curly-maple shaft with glowing veins. Aura (redone after the pilot): an amber halo Beam round the whole cue, tip to butt, breathing; flipbook cartoon bees (OpenAI sprite) all along it; falling honey drops; warm glow puffs and gold glints the whole length: 18/s (back 9) plus 1 Beam. Emissive 1.2-1.9, pulsing. Trail: wisp tinted amber. | Bees drift in slow arcs (particles fly straight), not loops. The honey drips are a painted surface, the falling drops are particles. | |
| void | Void | Epic | skins/void/sheet.png, clip.mp4 | mix: AI forearm (violet black-hole swirl) and butt (black snakeskin grip with violet cracks, black-hole sleeve), procedural gloss-black star-dust shaft, silver collar, silver ring with two violet lines, violet event-horizon ring on the end face. Moving: spinning swirl and accretion-ring sprites over the painted ones (ZOffset 0.25). Aura (redone after the pilot): a violet halo Beam round the whole cue and a second Beam of violet energy strands streaming toward the black hole at the butt; violet motes, dark-matter smoke and black rock shards pulled in all along the cue (Inward cylinders); violet haze: 31.4/s (back 15.7) plus 2 Beams. Emissive 1.3-2.1, pulsing. Trail: smoky textured ribbon lilac to near black with a lilac core, plus smoke puffs from the ball (22/s while rolling). Pocket: default gust. | The concept's violet rim glow is the halo Beam. The grip's scales are finer than the concept's. | |
