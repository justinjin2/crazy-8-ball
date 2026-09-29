# Brief: make every cue skin (61 new skins as renders and VFX clips, not imported yet)

Written 2026-09-29 with the designer, after an interview and an approved plan. **The designer
is awake and watching this run; it is not overnight.** Work through the Progress list at the
bottom, which is the source of truth for where you are.

**How to behave:**
- **Keep moving.** Make reasonable calls yourself from the plan, the designer's past decisions
  (`docs/DECISIONS.md`) and the style, and log each call in `docs/DECISIONS.md` tagged
  `(assumption)`.
- **Ask the designer** only when you truly need them. To ask and wait, add a line starting
  `WAITING FOR DESIGNER: <question>` at the very top of Notes, ask in chat, then stop. The
  Stop hook (`tools/overnight/cue_skins.json`) lets you stop only while that line is there;
  otherwise it sends you back to work while Progress boxes are unticked. Delete the line as
  soon as the designer answers. Ask for:
  - access to something (a key, a login, the Blender window)
  - a missing concept image
  - a design choice the plan doesn't answer and a wrong guess would waste real work
  - the pilot check in step 2
  - the spend limit in section 1

  **After the pilot there are no approval stops.** Make every skin, start to finish, in the
  section 8 order. The designer reviews and fixes everything themselves at the end, so don't
  wait for approvals, and keep the review file current as you go.
- **Never trade quality for progress.** If a skin doesn't match its concept or looks cheap,
  keep iterating. If a problem would make a whole tier worse (a broken tool, a missing input),
  stop and ask; don't push on with worse output. Moving on is only for skipping over
  something that is blocked, never over something that is bad.

Goal: all **61 new skins** from the approved plan (Classic is already built) built on the
shared cue mesh, with:
- their textures and glow
- their VFX: aura, moving material, ball trail and pocket finisher, per the tier rules
- **renders, a short VFX clip per skin, tier contact sheets and a review checklist** for the
  designer

**Nothing is imported into Roblox or Studio in this run.** A later session imports the skins
the designer approves, so every VFX must be built from pieces Roblox really has (section 5).

---

## 1. Rules for this run

**Read first:**
- `CLAUDE.md`
- `assets/cue/Readme.md` (the mesh, the paint kit and `CueTextures.py`)
- `assets/cue/template/CHATGPT.md`
- `docs/prompts/CUE_MESH_REPORT.md`
- `docs/STUDIO_NOTES.md`: "SurfaceAppearance facts" and the RenderFidelity note
- The effects section of `src/shared/Config.luau` (`Config.Effects`, how trails and pocket
  bursts are data today), read only
- `assets/cue/concepts/plan.json`: **the approved plan**, 62 cues with id, name, tier,
  palette, look and VFX. It is the design source of truth. Change a design only if the
  designer says so.
- `docs/prompts/CUE_SKINS_CHATGPT.md` (how the concept sheets were asked for, so you know
  their layout)

**Another run is working at the same time on the same Mac:** the abilities run
(`docs/prompts/ABILITIES_PROMPT.md`) in `~/Desktop/8ball`. It uses the Blender window through
the Blender MCP, Roblox Studio and Rojo. So:
- **Work only in the worktree `~/Desktop/8ball-skins`, on branch `cue-skins`** (made from
  `cue-mesh`; it already exists).
  - Never read from, write to, build in, commit in, or switch branches in `~/Desktop/8ball`
    or any other worktree.
  - Commit each finished skin or batch with `git add <paths>` (never `-A` or `.`), and push
    (`git push -u origin cue-skins` the first time).
  - Never commit to or push any other branch. Never force-push, rebase, `git reset --hard`,
    or delete branches.
- **Headless Blender only:** your own background processes,
  `/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python ...`.
  **Never call the Blender MCP**: it drives the one open Blender window, and that belongs to
  the abilities run.
- **Never use the Roblox Studio MCP, never run Rojo, never upload to Roblox.**
- **Don't touch game code or shared docs** (`src/`, `tests/`, `docs/GDD.md`,
  `docs/STATUS.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md`, `docs/UI_STYLE.md`). The
  abilities run edits those, and the import session will change the catalog. Put anything
  those files will need in your report as "for the import session". You may edit
  `assets/cue/`, `tools/` (new files only), `docs/prompts/CUE_SKINS_*` and
  `docs/DECISIONS.md`.
- **Share the machine politely:** run only one heavy render or bake at a time. Use EEVEE (or
  Cycles at modest samples) for previews, and keep each clip render reasonable (well under
  about 10 minutes).

**Asset generators and downloads** (the same permission as the abilities run: pre-approved,
the designer doesn't mind the credits):
- **OpenAI images (the main texture painter).**
  - The key is in the macOS Keychain under service `OPENAI_API_KEY`. Check that it exists
    with `security find-generic-password -s OPENAI_API_KEY >/dev/null 2>&1 && echo True || echo False`.
    **Never print, echo, log or write the key.** If it's missing or the API says the
    organisation needs verifying, ask the designer.
  - Write `tools/openai_image.py` (Python standard library only, key read with
    `security find-generic-password -s OPENAI_API_KEY -w`). Use the image **edits** endpoint
    with reference images, and generation when there are none.
  - Pick the newest `gpt-image` model the key can use (list `/v1/models`), and record which
    one.
  - Log every call (model, size, quality, the usage returned, an estimated cost, the output
    path) to `assets/cue/concepts/openai_log.jsonl`.
  - **Spend:** post a one-line spend note in chat at every $25 of estimated spend, and keep
    going. Stop and ask before the total estimate would pass **$150**.
- **The AI 3D generators (Rodin, Hunyuan3D, Tripo) only work through the Blender MCP**, which
  you must not use. Build every 3D piece (only the three Mythics and the Secret have one) with
  scripted modelling. If a piece would clearly be better generated (the dragon head, for
  example), finish a good scripted version, add it to "3D parts to generate" in the report,
  mention it once in chat, and carry on. **Don't wait** for an answer.
- Poly Haven textures and HDRIs downloaded directly by script are fine. Use CC0 only, and
  credit everything in `assets/cue/CREDITS.md`.

---

## 2. Inputs

- **Concept sheets:** `assets/cue/concepts/<code>.png` (C1-C2, U1-U3, R1-R3, E1-E3, L1-L7,
  M1-M3, S1, X1, K1-K2, Q1; `C1a`/`C1b` if the designer split one). `CUE_SKINS_CHATGPT.md`
  says which cues are on each sheet and how the sheet is laid out.
  - The designer makes them in ChatGPT and may still be making the later ones when you
    start.
  - When you reach a sheet that doesn't exist, **ask the designer for it** (name the file and
    the cues), and meanwhile carry on with any skin whose sheet does exist.
- **Crop the references:** for each cue, cut its row and its close-ups and VFX panels into
  `assets/cue/concepts/cues/<id>/` (`full.png`, `closeup.png`, `vfx.png`, and more as the
  sheet has them). A skin is judged against these crops.
- If a concept disagrees with `plan.json`, follow the concept for the look (the designer
  picked it) and `plan.json` for the tier rules and VFX list, and note the difference.
- **The cue's shape never changes.** Only Mythics and the Secret add a custom piece, attached
  to the cue.

---

## 3. The tier rules (from the designer; they override anything in a concept)

| Tier | Surface | VFX |
|---|---|---|
| Common (7 new) | Real cues after famous cue makers' looks, no logos or maker names | **None.** The shared white wisp ball trail |
| Uncommon (9) | Bold colours and patterns | **One glowing ring** (emissive); the wisp trail tinted to match |
| Rare (10) | A strong theme | **Every Rare has its own aura on the cue** (in hand and on the back); wisp trail tinted |
| Epic (9) | A theme plus a **moving material** | Aura; a trail or pocket burst only where `plan.json` lists one |
| Legendary (7) | **The base cue, no custom 3D piece**: a richer surface and a moving material | An aura clearly stronger than any Epic's, and **every Legendary has its own ball trail and pocket finisher** |
| Mythic (3) | The first tier with a custom 3D piece, which moves | Everything at full strength |
| Secret (1) | Eclipse, one of a kind | Beyond Mythic |
| Starter, VIP, 10 rank, 3 Unique | As in `plan.json` | As in `plan.json`. The rank cues share one trophy design and climb in metal and VFX |

**Content rules:** all ages. Hellfire and skulls stay cartoon, with no blood or gore (Blood
Moon is red mist). No crosses or deity symbols (Seraph is just wings of light and a halo). No
brand names or logos anywhere, and never the name "Ebony". No text on any cue.

---

## 4. Textures (per skin)

Use and extend the existing tools; don't start a parallel pipeline.
- `assets/cue/CueTextures.py -- --skin assets/cue/skins/<id>.json` turns a skin file into the
  maps: color, normal, roughness, metalness, and emissive when it glows.
- The five paint-kit panels are in `assets/cue/template/`.

**Choose the painter per skin, whichever gives the best result:**
- **Procedural in Blender, like Classic:** wood grain, carbon weave, stripes, classic points,
  metal. It's usually best for Commons, rank metals and anything geometric.
- **OpenAI panels:** paint each `<panel>_input.png` from the concept crops. Organic art (vines,
  flames, scales, dragons, galaxies) usually needs this.
- **A mix:** for example a procedural shaft with painted forearm and butt panels.

**For OpenAI panels:**
- Send the panel's `_input.png` as the layout image, the concept crops as the design images,
  and the rules from `template/CHATGPT.md`: exact layout and size, flat unrolled texture, no
  lighting or shading, top and bottom edges join, the skin's palette, no text.
- Check every panel for drift before using it: size, zone lines kept, no baked light, no
  text, no new colours, and seams that tile. Re-ask, or fix it in Python (seam blending,
  mirroring a half, palette snapping), until it's clean.
- Keep the chosen panels in `assets/cue/skins/<id>/`.

**The skin file:** write `assets/cue/skins/<id>.json`. Add a `vfx` block (section 5) and a
`moving` block where the skin has one. Extend `CueTextures.py` for whatever a skin needs:
- emissive masks for glow lines and the Uncommon ring
- a near-white base with a strong metal key where a skin will be tinted at runtime (Chroma's
  rainbow)
- the frames for a moving material (section 5)

**Match the concept:** compare the skin's render (6.1) side by side with its concept crops.
Iterate (up to about 4 rounds on Common to Epic; Legendary and up follow section 8's effort
rules) until the colours, the pattern, the placement on the cue and the finish match. Then look at it
at game distance too: the cue is thin, so strong, clear shapes beat fine detail.

---

## 5. VFX (built only from what Roblox has, so the import is mechanical)

Every effect is described in `skins/<id>.json` under `vfx`, using Roblox's own terms, and
previewed in Blender to look the same.

**Aura:**
- One to three `ParticleEmitter`s on `Attachment`s placed along the cue in studs (the tip is
  0, the butt is 7; the handle is where most of it lives).
- For each one, give: Texture (your sprite file), Rate, Lifetime, Speed, SpreadAngle,
  Acceleration, Drag, Size/Transparency/Color sequences, LightEmission, LightInfluence,
  Rotation/RotSpeed, LockedToPart, ZOffset, Orientation, and a FlipbookLayout (2x2, 4x4 or
  8x8, 1024 px sheets with padding between frames) where it animates.
- **Budget: at most about 20 particles a second per cue on Rare, 35 on Epic and 60 on
  Legendary and up**, because 30 players carry cues on their backs. Say what the back version
  should drop to (`BackRateScale`).

**Glow:** the emissive map plus `EmissiveStrength` and `EmissiveTint`. Roblox scripts may
pulse these at runtime, and the SurfaceAppearance `Color` tint too (Chroma's rainbow cycle).

**Moving material (Epic and up):** SurfaceAppearance maps can't change at runtime, so build it
from things that can:
- `Beam`s wrapped along or around the cue with `TextureSpeed` (flowing lava, streaming code,
  drifting stars), with their width, curve, segments and texture
- pulsing emissive or tint
- particles
- for Legendary and up only, a small set (at most 4) of pre-built SurfaceAppearance frames
  swapped by cloning

Say which one, with every number.

**Ball trail (Epic where listed; every Legendary and up):**
- A `Trail` spec (Lifetime, WidthScale, Color and Transparency sequences, LightEmission,
  TextureMode, texture), plus optional small emitters on the ball.
- Map it onto today's data model too (`Config.Effects` styles: Trail.Color(s), Trail.Core),
  so the import can drop it in.

**Pocket finisher (Epic where listed; every Legendary and up):** the burst's emitters, any
flash, ring or shockwave (textures and timing), and total duration (at most about 1.5 s).
Map it onto `Config.Effects` Pocket keys where they fit.

**Textures:** every sprite, flipbook, trail and beam texture goes in `assets/cue/vfx/<id>/`,
made in Blender (render to sheet) or by script, with alpha, sized by powers of two, and
reused across skins where sensible (keep a shared library in `assets/cue/vfx/_shared/`).

**Preview honestly:** in Blender, build each effect from the same pieces (camera-facing
sprite particles with those textures and curves, ribbon trails, beams with scrolling UVs) so
the clip shows what Roblox will show, not something Roblox can't do. Where Blender's look
differs from Roblox's (bloom, for example), keep it modest and say so.

---

## 6. What the designer reviews

### 6.1 Per skin (`assets/cue/renders/skins/<id>/`)

- **`sheet.png`:**
  - the full cue side-on
  - close-ups of the joint, forearm and butt
  - a 3/4 view
  - the aura view
  - the concept crop beside the render, labelled, for comparison
- **`clip.mp4`**, 1280x720, 30 fps, about 6 to 10 s, on a dark Roblox-like scene:
  - a slow turn of the cue with its aura and moving material
  - the cue on the back of a simple blocky Roblox-style avatar (diagonal, tip over the left
    shoulder, as in the game)
  - the cue in a shooting pose striking a cue ball, with the ball trail if it has one
  - a ball dropping into a corner pocket with the finisher if it has one

  Use the real table (`assets/table/`) and ball (`assets/balls/`). Common skins get a short
  turntable only.

### 6.2 Per tier and overall

- `assets/cue/renders/tiers/<tier>.png`: every skin of the tier side by side, the same way
  up, plus a small aura row, so the designer can judge balance at a glance.
- **`docs/prompts/CUE_SKINS_REVIEW.md`**: one row per skin, with id, name, tier, the files to
  look at, what was built (painter, VFX pieces, particle rate), anything that differs from the
  concept, and a **Designer** column left blank for "OK" or "fix: ...". When the designer
  writes fixes, do them next, before new skins, then clear the note to "fixed (date)".

`renders/` stays git-ignored, except the tier sheets. Commit those (resized under 2 MB each).

---

## 7. Git and file sizes

- **Commit:** skin files, the chosen panels, VFX textures, `vfx/_shared/`, the concept crops,
  the scripts, the tier sheets, the review file and the logs.
- **Don't commit:** the generated maps (`CueTextures.py` rebuilds them from the skin files) or
  per-skin renders and clips. Add ignore rules for them.
- Save panels and VFX textures as optimised PNG (or high-quality WebP if a PNG is over 1.5
  MB).
- If what you've added to git passes about 300 MB, stop and ask the designer about Git LFS.

---

## 8. Order and time

1. Tier by tier: Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret, then Starter/VIP,
   the rank cues, and last the Unique cues.
2. Within a tier, go concept sheet by concept sheet.
3. The Unique and rank cues come last, but get the same care as their tier. The Founder's
   Cue and Reyes Cue get Legendary-level effort.

### 8.1 Effort by tier

**Legendary and up gets a big step up in attention, detail and effort.** Those cues are the
game's crown jewels, the ones players chase, trade and show off, and their perceived value is
the whole point. Common to Epic should be clean, correct and consistent. Legendary, Mythic and
Secret must look like the best items in a top Roblox game (MM2 Chromas, Rivals Mythicals).

For every Legendary, Mythic and the Secret:
- **Surface:**
  - Detail that holds up in the Index close-up: crisp painted art, a real normal map (grain,
    engraving, scales, filigree) and layered emissive (a core glow plus accents).
  - Extra rounds against the concept.
  - The moving material polished until it reads clearly at game distance.
- **Aura:**
  - Layered from 2 to 3 emitters (a soft core glow, the main particles, small sparkle or
    accent particles), with at least one flipbook or sprite made for that skin, not only the
    shared library.
  - Colour and size ramps and easing tuned so it feels alive, not noisy.
  - Still within the particle budget.
- **Ball trail:** a layered Trail (outer ribbon, bright core and small particles) that fits
  the theme.
- **Pocket finisher:** staged over about 1 to 1.5 s: a quick flash, the main burst, then
  lingering sparkles or smoke. It should feel like a payoff.
- **Mythic and Secret pieces:** clean scripted modelling, bevelled edges, real materials, and
  motion (the claw flexing, the tails swaying, the moon orbiting).
- **Check at three distances:** the Index close-up, in hand at the table, and on a back
  across the room. The cue must look premium at all three, and clearly better than any Epic.
- **The clip:** at least two camera angles for the aura, and the trail and the finisher shown
  close.

### 8.2 Time caps (so no one design eats the day)

Rough wall-clock per skin, renders included:

| Tier | Time |
|---|---|
| Common | about 20-30 min |
| Uncommon | about 30 min |
| Rare | about 45 min |
| Epic | about 1 h |
| Legendary | about 1.5-2 h |
| Mythic and Secret | about 2-3 h, **hard cap 3 h** |

If a skin reaches its cap:
- stop polishing and keep the best version
- write what's still missing in its review-file notes
- move on

The designer will refine them afterwards. Never spend much longer than the cap on one
design.

---

## Progress

Tick each box when it's done and committed. A blocked step becomes `- [x] BLOCKED: <why>`,
and you ask the designer about it.

- [x] 0. Setup: in `~/Desktop/8ball-skins` (branch `cue-skins`), commit this brief,
  `CUE_SKINS_CHATGPT.md`, `concepts/plan.json`, `concepts/_attach/`, `tools/overnight/cue_skins.json`,
  `tools/overnight/skins_keep_going.sh`, the concept sheets
  already there, and the designer's `docs/ECONOMY.md` and `docs/DECISIONS.md` edits (the
  Starter Cue trades). Docs read. Blender
  runs headless. OpenAI key checked (True/False only) and `tools/openai_image.py` working (one
  test panel). Concept sheets found listed in Notes. Plan in Notes.
- [x] 1. Tooling: `CueTextures.py` extended (emissive, tint-ready bases, moving-material
  frames); `assets/cue/CueVfx.py` (sprite and flipbook maker, the Blender particle, trail,
  beam and pocket preview from a skin's `vfx` block); `assets/cue/CuePreview.py` (the sheet,
  the clip with the avatar, table and ball, and the tier sheets); the review file started.
- [x] 2. **Pilot, then ask the designer (the only approval stop):** one Common (Midnight),
  one Rare (Honeycomb) and one Epic (Void) finished end to end with sheets and clips. Show the
  designer the three sheets and clips, and wait for their OK or changes before the rest. The
  whole look of the set is decided here. After this, make everything else without stopping
  for approval.
- [x] 3. Commons (6 more): C1, C2.
- [x] 4. Uncommons (9): U1-U3, glowing rings.
- [ ] 5. Rares (9 more): R1-R3, every one with its own aura.
- [ ] 6. Epics (8 more): E1-E3, moving materials, with trails and pockets where listed.
- [ ] 7. Legendaries (7): L1-L7, base cue, every one with a trail and a pocket finisher, at
  section 8.1's Legendary effort within section 8.2's caps.
- [ ] 8. Mythics (3): M1-M3, with the custom pieces (list any piece to generate as
  section 1 says, without waiting), at section 8.1's effort.
- [ ] 9. Secret: Eclipse (S1).
- [ ] 10. Starter and VIP (X1).
- [ ] 11. Rank cues (10): K1-K2, one shared trophy design.
- [ ] 12. Unique cues (3): Q1.
- [ ] 13. Tier sheets complete, every designer "fix:" note done, and the review file
  current.
- [ ] 14. The report `docs/prompts/CUE_SKINS_REPORT.md`, written for a beginner:
  - what to look at first
  - every skin's status
  - OpenAI spend and the model used
  - 3D parts to generate
  - particle budgets
  - **for the import session:** the catalog changes (replacing the 30 placeholder case cues
    with these), the Starter Cue becoming tradable (Catalog `Tradable`, and the "no Exclusive
    cue trades" test gets a Starter exception; designer 2026-09-29), Config.Effects rows, what `CueStickBuilder` needs for several mesh skins,
    auras and moving materials, the upload list, and the doc updates for GDD, ECONOMY and
    STATUS
  - known issues

  Branch pushed.

## Notes

- **2026-09-29, setup.** Worktree `~/Desktop/8ball-skins`, branch `cue-skins`, pushed. Blender
  5.2.2 LTS runs headless (EEVEE ~0.4 s a 720p frame; its built-in FFMPEG writes the clips, the
  Mac has no ffmpeg). OpenAI key: True. `tools/openai_image.py` works; model
  **gpt-image-2.5-sunburst** (the newest on the key: gpt-image-2.5-flare/-sunburst, dated
  2026-09-08; Sunburst holds precise edits). One test panel (Honeycomb forearm, 1536x512 edit):
  about $0.03.
- **Concept sheets found (25 of 26):** C1, C2, U1, U2, U3, R1, R2, R3, E1, E2, E3, L1-L7, M1, M2,
  M3, S1, X1, K1, K2. **Missing: Q1** (Founder's Cue, Beta Cue, Grand Opening): asked for when
  the run reaches it.
- **Plan.**
  1. Painters write the five panels per skin (plus optional same-size greyscale companions:
     `<panel>_height`, `_rough`, `_metal`, `_glow`): `assets/cue/CuePaint.py` (Mac Python,
     numpy + Pillow) holds the procedural painters and the OpenAI panel runner with drift checks
     (exact size, seam blend, palette snap). `CueTextures.py` maps every channel onto the atlas.
  2. `assets/cue/CueVfx.py`: the sprite/flipbook maker (numpy, plus OpenAI transparent sprites
     for illustrated ones), and a Blender preview built from Roblox's own pieces: a
     deterministic ParticleEmitter simulator (Rate, Lifetime, Speed, SpreadAngle, Acceleration,
     Drag, sequences, LightEmission as additive blend, Rotation/RotSpeed, LockedToPart, ZOffset,
     flipbooks), Trails (camera-facing ribbons with Lifetime/WidthScale/sequences), Beams
     (FaceCamera ribbons with ZOffset and scrolling TextureSpeed) and the pocket burst exactly as
     `Effects.pocketBurst` builds it today plus extra layers.
  3. `assets/cue/CuePreview.py`: in Blender, the stills and the clip (EEVEE, a dark Roblox-like
     scene, a blocky avatar, the real table and ball); in plain Python, the labelled sheet and the
     tier sheets. `tools/cue_skin.py <id>` runs the whole chain for one skin.
- **2026-09-29, tooling done.** `CuePaint.py` (painters + OpenAI runner with zone snapping, seam
  and palette fixes), `CueTextures.py` (companion maps, greyscale emissive mask, `--no-render`),
  `CueVfx.py` (sprites; ParticleEmitter/Trail/Beam simulators; the pocket burst ported from
  `Effects.pocketBurst`), `CuePreview.py` (EEVEE stills and clip, PIL sheets and tier sheets),
  `tools/cue_skin.py` (the chain). A skin takes about 10 s to paint and map, 5 s for stills and
  about 1 minute for its clip. Moving-material frames (Legendary+) come with the first Legendary.
- **Pilot built:** Midnight (procedural), Honeycomb (procedural + an OpenAI bee flipbook), Void
  (OpenAI forearm and butt + procedural shaft; spinning-swirl moving material). Spend so far
  about $0.14.
- **Pilot round 1 feedback (designer):** not enough aura on the Rare and the Epic; make it more
  prominent and round the entire cue, tip to butt, for every Rare and up, using emissive glow too.
  Done: a halo Beam round the whole outline (Rare+), a streaming energy Beam (Epic+), emitters
  spanning the whole cue, stronger pulsing emissive. Logged in DECISIONS.
- **2026-09-29, pilot approved (round 2).** Designer: "looks a lot better now yes, continue".
  Direction for the rest of the run: Roblox has emissive masks, so **no compromise on surface
  detail, as close to the concept images as possible**; and **auras must not all be the same
  halo**: each rarer cue gets its own kind of effect (flame, energy, lightning, orbiting
  pieces, and so on) from whatever Roblox tools fit; ask the designer if an outside tool is
  needed.
- **2026-09-29, Commons.** New shared painters for concept-matching detail: `worley` (cellular
  noise) behind a real pebbled leather, a 2/2 twill carbon weave with anisotropic tows, a
  birdseye with eyes and blotches, a patchy curly figure, `fleck_wrap`, `inlay_points` with
  layered veneers, `inlay_lozenge`, `inlay_diamond` (pearl, faceted gem, metal), `teardrop`,
  `ring_lines`, `ivory`. Inlays face a camera 45 degrees off the top (one point faces you in
  the sheets and on the back). Midnight re-rendered with the new leather.

