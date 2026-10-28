# Halloween lane W4, Cues B: the Witch's Broom, the Black Cat Cue and the Spider Cue

**Written 2026-10-28 by the coordinator from `docs/halloween/PLAN.md`.** Lane `hw-cues-b` (W4):
folder `~/Desktop/8ball-hw-cues-b`, branch `hw-cues-b` (cut from `halloween`), Rojo **34885**,
Studio window `place/lane-hw-cues-b.rbxl` (and only that one), model **Fable 5.1, effort
xhigh**. The shared contract is [`docs/halloween/PLAN.md`](../halloween/PLAN.md); it wins over
this brief wherever they differ. Your lane file: `docs/halloween/lanes/hw-cues-b.md`. Your
partner lane: Cues A (`docs/prompts/HW_CUES_A_PROMPT.md`), which builds the tools and the
runtime your three cues run on.

Start: the coordinator launches it with `tools/halloween/lanes.sh launch`. The launch line and
any restart line are the command printed by `tools/halloween/lanes.sh command hw-cues-b`
(never write your own flags: that command carries the Stop hook, the model, the effort,
`caffeinate` and the start prompt, and clears the stop counter). In a worktree `.git` is a
file, so the marker files live in the real git directory (`git rev-parse --absolute-git-dir`).

**Attended until 11:00, then on your own.** The Progress list at the end is the source of
truth; the Stop hook (`tools/overnight/hw_cues_b.json` → `keep_going.sh`, attended, max 400)
sends you back to work while any `- [ ]` line remains. Until **11:00 EDT** Justin answers fast:
when you truly need him (the rules below force a visible change from an approved concept, or
access you cannot get), run `touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"`
(NOT `.git/overnight-waiting`: here `.git` is a file and that fails), ask ONE clear question with a picture (absolute path), and stop. After 11:00
he may sleep until about 16:30: never make the marker; decide the way he would (PLAN §2 and
§3, the approved concept, `docs/UI_STYLE.md`, simple for kids), log it under Assumptions in
your lane file, and keep going. Never stop between steps otherwise.

**Hard rules** (the session skips permission prompts, so these are the only guard rails):
times are EDT; lanes stop building at **16:00**, nothing lands after **17:00**. Never publish.
Never touch the Team Create place ("Crazy 8 Ball") or another lane's Studio window, Rojo port or
folder. Blender **headless only** (`/Applications/Blender.app/Contents/MacOS/Blender -b ...`):
the live Blender MCP is shared by every terminal. Commit only on `hw-cues-b`, push only
`hw-cues-b`; never push `halloween`/`main`/`release`, never force-push, never merge another
lane's branch (only `halloween`). Uploads: images and meshes to group **675425213** without
asking (PLAN §2), dry-run first; **no audio uploads** (Roblox library sounds only); never
print, echo or write an API key. **No runtime code**: you edit nothing under `src/` except what
`tools/cue_skins_data.py` generates (2.10); a code change you need is a Request to Cues A.

## 0. Read first

In this order, all of each:

1. `docs/halloween/PLAN.md` (the contract), `docs/halloween/REQUIREMENTS.md` (rows R2.x and §9),
   `CLAUDE.md`, `docs/parallel/README.md` (its rules apply with PLAN §4's lanes and ports and
   branch `halloween` instead of `release`; you touch no save), your lane file.
2. Cues A's brief `docs/prompts/HW_CUES_A_PROMPT.md` §2.1-2.6 and §3 (the catalog rows, the
   data tool keys, the ONLY filter, the body path, the `Aim` key, the thumbnails, the modelling
   rules, its drops and the hand-off it expects from you), and Cues A's lane file
   (`~/Desktop/8ball-hw-cues-a/docs/halloween/lanes/hw-cues-a.md`, read from disk: its Status
   says when each drop is `READY`; re-read it at every Progress step).
3. `docs/CUE_VFX_TECHNIQUES.md` whole: the depth rule (§1), the pipeline table (§2), pieces and
   their motions/visuals (§4), the aura recipe in layer order (§5), trails (§7), finishers (§8),
   Lower effects (§9), pitfalls (§10), the checklist (§11). Then
   `docs/prompts/UNIQUE_CUES_PROMPT.md` (how the last top cues were built and judged).
4. The agent report `~/Desktop/8ball-refs/halloween/research/agents/code-cues.md`: the body
   design, the modelling rules, the five cues, the risks.
5. Read-only code you write data for (spot-checked 2026-10-28 on `halloween` @ 12ee4888):
   - `assets/cue/CuePieces.py`: the `Kit` (`material`, `joint(name, pivot, parent, motion,
     aura, visual, low)` at 455, `add`, `path`, skinned `bones`), `export` (789; it writes only
     the joint keys Parent, Pivot, Motion, Aura, Visual, Low), `export_skin` (906), `attach`
     (1020), `SPRITES`/`render_sprite`/`sheet_sprite` (1187-1292), `main` (1310). The builder
     modules register through imports at 1117-1121 and 1198-1201, where Cues A's drop 2 adds a
     guarded `import CuePiecesHalloween_B`. You never edit `CuePieces.py`.
   - `assets/cue/CuePiecesUnique.py` (beta, firework: the pattern of a builder file and its
     helpers `_radius`, `_lathe`, `_torus`, `_box`), `CuePiecesMythic.py` (`kitsune_scripted`:
     a skinned running creature on bones; the `fox_spirit` sprite at 1123),
     `CuePiecesPocket.py` (pocket creatures in the `pocket` frame).
   - `tools/cue_skins_data.py` (what reaches the game: `skin_row` 172, the pocket allow-list
     200, `piece_row` 212, `"draft": true` 238), `tools/cue_pieces_glb.py`,
     `tools/vfx_sprites.py` (the shared v2 sprites in `assets/cue/vfx/v2/`), `tools/cue_skin.py`
     (`--thumb`), `assets/cue/CuePreview.py` (`--thumb` 642), `tools/roblox_upload.py`,
     `tools/manifest_image_ids.py`, `tools/build_cue_templates.luau`, `tools/vfx_lab.luau`,
     and `docs/STUDIO_NOTES.md` "Uploading assets with Open Cloud" (141).
   - Runtime: `src/client/CuePiece.luau` (joints, Aura and Low flags), `CueSkinLook.luau`
     (AuraOff hides the piece 1008-1018; the piece copies the mesh's camera fade 1166-1170; the
     quiet share 1208-1225), `CueVfx.luau` (emitter keys: `Orientation` 179,
     `FlipbookLayout/Mode/Framerate` 188), `Effects.luau` (`skinFinisher` 796: Layers, Rings,
     Flash, Piece with Rise/Scale/Spin/Transparency curves, Sound),
     `src/shared/CueSkins/Motion.luau` (Hinge, Sway, Spin, Bob, Path, Glitch).
   - Numbers: `Config.Cue.CameraFadeStuds` 1.5 (Config.luau:537), `RaisedFxOffDegrees`,
     `Config.Cue.Back` (582: tilt 36°, crosses the back attachment 4.3 studs from the tip, butt
     toward the right hip, at least 0.8 above the floor), the grip numbers (1461-1477:
     `GripFromButtFraction` 0.15, `GripButtEndStuds` 0.25, `GripMinFromTipFraction` 0.35;
     `MaxGripSlideStuds` 1.5 at 1323), `Config.CueSkins.Quiet` (6227: Mythic and Secret 0.25).
6. Skin and piece examples: `assets/cue/skins/kitsune.json` (Mythic: piece, pocket creature,
   flipbook spirit, `Aura.Highlight`), `eclipse.json` (the Secret bar: 14 aura layers, 98/s,
   `Aura.Outline`, `Aura.Lights`), `beta.json` and `firework.json` (the Unique bar, the
   `Aura.Sound` format), `assets/cue/pieces/kitsune/piece.json` (skinned parts with Bones,
   SurfaceAppearance with EmissiveMask, ForceField shells, joints with Motion, Aura flags,
   Paths).
7. **The approved concepts** in `~/Desktop/8ball-refs/halloween/mocks/v2/`. Open each before you
   model it and again at every check:
   - `C3b_broom.png` (Witch's Broom, rev 2, approved): a violet faceted crystal tip held by two
     silver spiral bands; a crooked, wavy natural branch for the handle, brown bark with a big
     knot hole about a third along and a few twig stubs; purple and emerald magic ribbons
     spiralling round it with gold four-point stars, crescent moons and small bats; at the far
     end a thick purple binding with a silver square buckle carrying a gold crescent, golden
     straw bristles flaring wide with straw leaves flying off, and a purple witch-hat charm
     (gold buckle band) hanging from the binding on a short silver chain. Panels: HAT CHARM,
     TRAIL (ribbons, stars, bats, straw over the handle), FINISHER (a purple portal ring
     swirling over the pocket, a column of sparkles and crescents, a full moon with a witch on
     a broom crossing it, bats).
   - `C2c_black_cat.png` (Black Cat, rev 3, approved): a glossy black cue with gold ring pairs
     along it, a black knurled forearm with three gold claw slashes, triple gold rings at the
     collar, a small gold claw curve at the tip end, and a furry black tail curling out of the
     butt; black smoke round the cue with gold-edged wisps and embers, and plain black cat
     silhouettes running along above it toward the tip. TRAIL: a pack of black cat silhouettes
     running behind the cue ball, thin gold rim light. FINISHER: a big black cat silhouette
     leaping out of the pocket through a gold ring, black smoke shards, gold sparks. Its words:
     "Shadows follow. Always." Tough, not cute.
   - `C1b_spider.png` (Spider, rev 2, approved): a black chrome segmented shaft with
     silver-edged chevrons, a dark spear tip, eight huge curved blades fanning back past the
     butt like Hela's crown with silver edges and silk webs between them, a crimson hourglass;
     black smoke with silver silk strands and sparkles. TRAIL: silver silk strands and smoke
     behind the ball. FINISHER: a radial silver web fanning up out of the pocket through smoke.
   - Rejected, never go back there: `C2_black_cat.png` (cute, pink, paw prints, hearts, a cat
     face on the butt), `C2b_black_cat.png` (a sculpted cat head on the butt and glowing yellow
     eyes in the smoke), `C1_spider.png`, `C3_broom.png` (earlier revisions).
8. The bar in the game, before you model anything: in your Studio, `tools/vfx_lab.luau` with
   `IDS = { "EclipseCue", "BetaCue", "FireworkCue", "KitsuneCue" }` (Firework is the Grand
   Opening cue's catalog id). Everything you ship must beat these.

## 1. Goal

You own these requirement rows (REQUIREMENTS.md; PLAN §3 settles them):

- **R2.5** Witch's Broom (`WitchBroomCue`, effects level **Secret**, track 7,000): a unique model
  that need not follow cue conventions but holds right in the hands; the hat charm sways.
- **R2.3** Black Cat (`BlackCatCue`, **Mythic**, track 2,000) **as revised to rev 3**: no head,
  no face, a swaying tail at the butt, faceless silhouettes, thin gold rim light, black smoke,
  tough not cute, no pink. (The row's older "cute, appealing to girls, not another black cue"
  was replaced by Justin's rev-3 approval.)
- **R2.4** Spider (`SpiderCue`, **Mythic**, the 3 h 01 m active-play cue): Hela-crown blades,
  black smoke with silver silk, webs, one small crimson hourglass; **not creepy for people with
  arachnophobia**: no spider bodies, legs or crawling creatures anywhere (blades, webs, silk
  and the hourglass only). The blades never block the shooter's view.
- **R2.8** the rarity ladder: the Broom is the biggest flex of all five cues; Cat and Spider
  sit clearly above Jack-o'-Lantern (Legendary) and below the Broom.
- **R2.9** for these three: unique model and tip, aura, trail, pocket finisher, animated
  parts, flipbook VFX, card art, Index entry; better than Eclipse, Beta and Grand Opening.
- **R2.10** build to the approved concepts above.
- Shared (you give the look; others own the rest): R2.6 and R2.7 (core's timer and track),
  R1.3 (Cues A's rows: Exclusive, one copy, never tradable or sold), R0.5/R0.6 (every device,
  smooth on a low-end phone).

**Done, in player terms.** A player who earns any of the three sees a cue unlike anything else
in the game, in their hands, on their back and on other players: the Broom is a real crooked
branch with a glowing crystal tip, straw bristles and a swinging hat charm wrapped in purple and
green magic; the Black Cat is sleek black and gold with a living tail and shadow cats running in
its smoke; the Spider wears a crown of huge silver-edged blades laced with silk. Each leaves its
own trail and plays its own pocket show (a portal and a witch over the moon; a cat leaping out
of the pocket; a web bursting open). While aiming, nothing blocks the shot on a phone, an iPad,
a PC or a TV. The cards in My Cues, the Index and the event track show each cue at its best.
Nothing stutters on a phone, and Lower effects still shows which cue it is.

**Time plan** (adjust, but say so in Status). Cues A's drops: 1 (rows) merged 08:15-08:30,
2 (data tool keys, ONLY filter, the guarded import of your file) about 08:45, 3 (the body path,
`Aim`, own-distance fade) about 10:00, body thumbnails by 12:00. The coordinator merges into
`halloween` on Request from 08:45 (drop 2 about 08:45, drop 3 about 10:00-10:20), so
`git fetch && git merge halloween` picks each drop up soon after.
07:30-08:15 read, set up, first push (P1-P2) · 08:15-09:00 Broom body in Blender (P3, gate-1
shots) · about 09:00 drops 1 and 2 into your branch (P4) · 09:00-09:40 Cat body (P5) ·
09:40-10:15 Spider body (P6) · 10:15-10:50 all three in your Studio through drop 3 (P7) ·
10:50-11:00 gate 2 (P8) · 11:00-12:45 Broom effects (P9-P11) · 12:45-14:15 Cat effects
(P12-P14) · 14:15-15:30 Spider effects (P15-P17) · 15:30-16:00 overhangs, then cards, lineup,
final merge (P18-P22). The overhang choice (P18) comes before any card, because a card shows
the cue's final shape: render each card (P19) once its cue's effects and overhang variant are
final and Cues A's thumbnail support is in.

## 2. Design

### 2.1 What is yours

Content only, for `BlackCatCue`, `SpiderCue`, `WitchBroomCue` (PLAN §4; the names follow Cues
A's §3.4: the body piece is named like the skin, aura decor `<sid>_aura`, finisher
`<sid>_pocket`):

| Thing | Where |
|---|---|
| Builders (bodies, aura pieces, pocket pieces, silhouette rigs) | `assets/cue/CuePiecesHalloween_B.py` (new, yours) |
| Pieces | `assets/cue/pieces/{witch_broom, witch_broom_aura, witch_broom_pocket, black_cat, black_cat_pocket, black_cat_aura (stretch), spider, spider_pocket}/` |
| Skins | `assets/cue/skins/{witch_broom, black_cat, spider}.json` |
| Sprites, flipbooks | `assets/cue/vfx/{witch_broom, black_cat, spider}/`, drawn by `tools/hw_sprites_b.py` (new, yours) |
| Cards | `assets/cue/thumbs/{witch_broom, black_cat, spider}.png` |
| Test | `tests/halloween_cues_b_test.luau` (new, yours) |
| Upload rows | your rows in `tools/upload_manifest.json` (you upload your own; 2.10) |
| Generated data | `src/shared/CueSkins/{Skins,Pieces}/*`, `Index.luau`, `Textures.luau`: written only by `python3 tools/cue_skins_data.py`, never by hand |

Not yours (Requests): the body path in `CueStickBuilder`, `CueSkinLook`, `CuePiece`,
`CueAssets`; `tools/cue_skins_data.py`, `tools/build_cue_templates.luau`,
`assets/cue/CuePreview.py`, `assets/cue/CuePieces.py`; the Catalog rows and Strings names (all
Cues A); `tools/vfx_sprites.py` (shared: you only use its sprites); any Config block.

### 2.2 The body rules (the same numbers as Cues A's §2.6; your builder enforces them)

A **body** is a piece that replaces the hidden shared cue mesh (Cues A's path: the skin's
`body` names a piece; the mesh goes Transparency 1; a missing body falls back to a visible
Classic cue with your aura). Hands, clearance and rails still use the `CueShape` envelope (tip
0.09 studs across, butt 0.36, length 7), so the body must fit it where it matters. Blender cue
frame: X the side, Y from 0 at the tip to -7 at the butt, Z up. **+Z is up in the hands and
away from the body on a back.**

- **Tip:** ends exactly at Y = 0 (nothing at Y > 0); at most 0.12 studs across for the first
  0.3 studs (the ball's radius is 0.18).
- **Bridge hand zone 0.3-2.1 studs from the tip, grip hand zone 4.4-6.75** (rest grip 5.95; a
  long wind-up slides the cue up to 1.5 studs back through the hand; never within 0.25 of the
  butt): centreline within ±0.02 of the axis, radius within ±0.02 of the envelope. Bark, knurl
  and fur come from maps there, not geometry.
- **Width:** at most envelope +0.08 sideways and downward anywhere up to 6.75 studs (rails,
  balls and cloth sit below and beside the cue). Upward (+Z) between 2.1 and 4.4 you may stand
  out up to 0.25 (twig stubs, rings, the claw). From 6.75 to the butt (binding, collar, cap)
  up to envelope +0.2. Nothing on -Z that would sink into the torso on a back.
- **Past the butt (Y < -7):** at most **0.3 studs** for any part that does not fade in the aim
  view. Longer parts (the Broom's bristles, the Cat's tail, the Spider's blades) sit on a joint
  with `"Aim": "fade"` (2.3), capped at **1.5** (`Config.CueSkins.Bodies.MaxOverhangStuds`; on
  a back the butt points at the right hip, 36° from upright, at least 0.8 above the floor, so a
  longer overhang reaches the legs or the floor of a small avatar). Build each overhang twice:
  a **compact variant** (≤0.3 past the butt) and a **long variant**. The compact one ships
  until you have seen the fade work in your own aim camera (P18).
- **Budget per cue** (hard limits; Cues A's data tool stops the run over them, and
  `--allow-over-budget` is for work in progress only, never a committed run): body ≤8
  MeshParts and ≤10,000 triangles; aura piece ≤10,000; pocket piece ≤20,000 (Cues A's §2.2
  numbers; if its tool stops a piece that is under them, for example on an older "6,000 a body,
  10,000 a pocket" line, that is a tool bug: a Request to Cues A, never a smaller piece and never
  `--allow-over-budget` in a commit). Eight parts is
  tight, because the kit makes one MeshPart per joint and per material: give each body **one
  512 px atlas** (colour + normal, an EmissiveMask for glowing inlays, alpha where needed)
  shared by its parts, and make anything that bends or moves in several places **one skinned
  MeshPart on several bones** (the FoxMask pattern: the tail, the charm's chain, the crown's
  eight blades). Log each map as an Assumption with the lab shot that proves it. Flipbook
  sheets 1024×1024 (Grid4x4: 16 frames of 256 px; Grid8x8 only for small sprites).
- Body joints never take `aura=True` or `low='hide'` (the body is the stick; it follows the
  stick's visibility, not the aura's). Aura-only decoration goes in the skin's `piece`
  (`<sid>_aura`: it hides with the aura and may take `low='hide'`).
- **Motion** (Mythic and Secret): at least three movements at three periods (about 1.6 / 2.6 /
  4 s, TECHNIQUES §6) across body and aura piece.
- `check_envelope` in your builder file samples the exported vertices every 0.1 stud against
  `cc.Envelope(cc.load_shape()[0])` and these numbers and fails the Blender run (exit code 1)
  naming the part and the distance. Cues A's `tests/cue_body_test.luau` checks parts, tip and
  overhang again in Lune.

### 2.3 The aim-fade key and the camera fade (Cues A's drop 3)

Cues A adopted this lane's proposal (its §2.4): a joint with `"Aim": "fade"` (and its children)
eases to clear over `Bodies.AimFadeSeconds` (0.25) on the stick owner's **own screen** while
their stick is drawn for a shot (AuraQuiet on their turn, AuraOff when raised), and back after
the shot; everyone else sees it whole. Every body part also fades by its **own** distance to the
camera (`Config.Cue.CameraFadeStuds`), so nothing pokes into the lens. Put `Aim` on the root
joint of each overhang (the bristles, the tail, the crown), so one joint takes the whole shape.

The exporter does not write unknown joint keys, so your entry point (2.9) adds `Aim` to
`piece.json` after the export; `cue_skins_data.py` copies joint rows whole, so the key reaches
the game without a tool change. Never ship a long variant before drop 3 is merged into your
branch and you have watched the fade in your aim camera at phone and PC sizes.

### 2.4 Witch's Broom (Secret; first, the grand prize)

- **Body `witch_broom`** (≤8 parts, one atlas): the crystal tip (Glass violet `#A86BFF` with a
  Neon inner core `#D9B8FF`, about 0.10 across, 0-0.3 studs, faceted, a Glow pulse 0.2-0.7 over
  2.4 s) and two silver spiral bands as flush inlays at 0.3-0.6; the handle 0.3-6.75 as one bark
  mesh (bark colour + normal baked headless into the atlas): straight in both hand zones,
  crooked between them (waves up to ±0.06 off-axis between 2.1 and 4.4), the knot hole at about
  2.6, three twig stubs pointing up (+Z, 0.12-0.25 long) between 2.3 and 4.2; the binding at
  6.75-7.0 (purple `#5B2A86` wraps, a silver buckle with a gold crescent as an emissive inlay);
  the straw bristles as layered straw cards with alpha (straw `#D9A441`, darker strands
  `#A8742A`), most of the volume up and to the sides (+Z, ±X): compact 7.0-7.3 flaring to 0.5
  across, long (Aim) to 8.2 flaring to 0.75; the **hat charm** as one skinned part (two chain
  links and the hat on a 3-bone Sway chain) hung from the buckle on the +X side, tilted a little
  down, swinging 15-20° over about 1.8 s, the hat purple `#4B2270` with a gold band; it never
  enters the torso on a back.
- **Aura piece `witch_broom_aura`:** two magic ribbons, purple `#9B4DFF` and emerald `#2EE6A0`,
  spiralling round the whole handle in opposite senses (the `firework` builder is the pattern:
  flat Neon helices 0.16 off the surface, a turn every 1.8 studs, Spin ±45°/s), each with a
  Glow wave; `low='hide'` on the outer ribbon only.
- **Aura (skin JSON),** inside out per TECHNIQUES §5: a deep violet haze body (smoke_8x8,
  LightEmission 0-0.3, readable on the bright floor and under Night), emerald wisps
  (wisp_8x8), gold four-point star glints (flare, glint), crescent-moon and straw-leaf flecks
  (your sprites), small **bats** (your 4x4 flap flipbook, front view, so drifting reads right
  from every side; black with a violet rim) drifting up and away a few at a time, a sparkle
  trickle from the hat, a violet PointLight at the crystal and an emerald one at the binding
  (lights ≤3), `Aura.Outline` violet `#A35CFF` (Secret gets the moving gradient outline from
  `Pop.level` on its own). Budget ≤170 particles/s before BackRateScale.
- **Trail:** `Style.Trail` violet → emerald with a white-violet core (Lifetime 1.4, width 0.6);
  trail emitters on the ball: stars, crescents, straw leaves, a few bats.
- **Pocket finisher (about 2.2 s):** a violet flash; `witch_broom_pocket` (≤20K): two Neon portal
  rings (violet, emerald) turning in opposite senses, rising and widening over the pocket
  (Rise/Scale/Spin curves), a `swirl_8x8` violet-emerald layer lying flat in them; a rising
  column of sparkles and crescents; then the **witch over the moon**: one big OneShot 4x4
  flipbook (about 4.5 studs, 3 studs over the pocket) where a pale full moon fades in, a black
  witch-on-broom silhouette crosses it with bats, and it fades; a gold star burst; a violet
  ring decal. Sound: a magic shimmer or whoosh from the Roblox library (2.8).

### 2.5 Black Cat (Mythic; second)

- **Body `black_cat`** (≤8 parts, one atlas): a glossy black shaft (`#0B0B0D`, a little
  Reflectance) with the tip end a small gold claw curve as an emissive inlay inside the tip
  limits (nothing protrudes); gold ring pairs (`#E2B04A`) at about 3.3 (joint), 4.3 and
  6.6-6.75 (the triple collar), flush within the width rules; the forearm 3.6-4.4 with three
  gold claw slashes as emissive inlays (`#FFC85A`, a slow Glow breath 0.1-0.5 over 3 s); the
  wrap 4.4-6.6 a black knurl (normal map); the butt cap 6.75-7.0 black with a gold ring.
- **The tail** (part of the body, so it stays when the aura is off): one skinned fur part on
  4-5 bones from the butt cap, on a Sway chain (travelling down the tail, about 2.4 s, 8-14°
  per joint, plus a slower Hinge so it never loops visibly); black with a fur-strand normal and
  a slightly larger skinned **gold ForceField shell** (`#E8B04A`, the Kitsune mask's shell
  trick) for the thin gold rim light. Compact: leaves the cap straight back and curls up (+Z)
  within 0.3 past the butt. Long (Aim): up to 0.8 past the butt and 0.9 up, the concept's
  C-curve. Lean and strong, not fluffy.
- **No head, no face, no eyes anywhere (not even glowing eyes in the smoke), no pink, no paw
  prints or hearts.** Silhouettes are athletic (long legs, a low panther run), not chibi.
- **Aura:** black smoke body (smoke_8x8 tinted `#0A0A0C` → `#1A1408`, LightEmission 0, so it
  reads as smoke on the bright floor) with gold-edged wisps (wisp_8x8 tinted gold, additive,
  thin), gold embers; the **shadow cats**: your 4x4 run-cycle flipbook (black fill, thin gold
  rim) on 1-2 emitters along the shaft, `Orientation` FacingCamera, **running in place**
  (LockedToPart, speed near 0, a little upward drift), rising out of the smoke and dissolving
  (transparency curve), 2-4 alive at once, about 0.6-0.9 studs tall; a warm gold PointLight at
  the collar (lights ≤2); `Aura.Outline` gold `#E8B04A`. Budget ≤120 particles/s. Stretch,
  only if ahead: 2 three-dimensional runner cats (flat extruded silhouettes with a gold
  ForceField rim, legs on Hinge joints, riding a Path along the cue like Kitsune's RunningFox)
  in `black_cat_aura`.
- **Trail:** a dark ribbon with a gold core (`Style.Trail`, Lifetime 1.2, width 0.5) with the run
  flipbook dropped along the ball's path, each cat running in place where it was dropped (the
  pack of the concept, and the moonwalk rule, 2.7), black smoke puffs and gold sparks. Keep the
  smoke thin and short-lived: the 8 ball is black and the 2v2 cloth is charcoal.
- **Pocket finisher (about 1.6 s):** a gold flash and a gold ring decal; a black smoke burst with
  dark shards; the **leap**: a OneShot 4x4 flipbook of one big cat silhouette (about 3.5 studs)
  leaping up and out of the pocket with its gold rim, the frames moving it within the cell (no
  direction problem); gold sparks falling. `black_cat_pocket` (a 3D leaping silhouette) only if
  the flipbook leap looks flat in the lab. Sound: a low growl or hiss from the Roblox library,
  nothing cute.

### 2.6 Spider (Mythic; third)

- **Body `spider`** (≤8 parts, one atlas): a black chrome shaft (Foil `#101014`) in segments
  with silver-edged chevrons (emissive `#C9CED8` inlays or flush ridges); a faceted spear
  ferrule inside the tip limits (0-0.3, ≤0.12 across, silver edges; no barbs in the bridge
  zone); the crown collar on the butt cap at 6.75-7.0 (past the grip hand) with **one** small
  crimson hourglass (Neon `#C0142C`, ≤0.1 tall, on +Z) and a silver ring.
- **The crown:** eight blades rooted at the collar's back edge (about 6.9-7.0), fanning over the
  top and the sides (from +Z round to about ±100°, none pointing down into a back), sweeping
  back past the butt and curving outward like Hela's crown; black with silver emissive edges
  and silk webs between neighbouring blades as part-transparent membranes (web alpha, silver
  `#DDE3F0`). One skinned part with a bone per blade: each blade breathes on its own Hinge
  (2-4°, 3-4 s, phases spread) and the edges Glow. `Aim` on the crown's root joint, so all
  eight fade together. Compact: the blades curl tight round the cap within 0.3 past the butt
  (a closed crown). Long: the longest reaches 1.5 past the butt.
- **Aura:** black smoke body (dark, LightEmission 0); silver silk: 4-6 Beams between blade tips
  and along the shaft with a silk-strand texture (LightEmission 1, slow TextureSpeed); web
  flecks (your radial web sprite, small, turning slowly); silver glints; a faint crimson glint
  at the hourglass every few seconds; a cool white PointLight (lights ≤2); `Aura.Outline`
  silver `#D8DCE6`. Budget ≤120 particles/s. No spiders, no legs, nothing crawling.
- **Trail:** a silver silk ribbon (`Style.Trail` silver core, Lifetime 1.2, width 0.5) with web
  strand streaks, silk flecks and thin smoke. The Cat's ball-readability rule applies.
- **Pocket finisher (about 1.6 s):** a white flash; `spider_pocket` (≤20K): a radial web (Neon
  silver spokes and spiral) rising out of the pocket, opening and tilting toward the camera
  (Rise/Scale/Spin), a web ring decal expanding on the cloth, a black smoke burst, silver
  sparks and one crimson glint. Sound: a sharp silk snap or whoosh from the Roblox library.

### 2.7 Sprites and flipbooks

- Reuse the shared v2 sprites (`smoke_8x8`, `wisp_8x8`, `swirl_8x8`, `flare`, `glint`, `dust`,
  `orb`, `ring`, `streak`) tinted by each row's Color; draw only what is new in
  `tools/hw_sprites_b.py` (procedural Pillow, deterministic): crescent, straw leaf, radial web,
  silk strand, web ring decal, a portal swirl only if `swirl_8x8` reads wrong.
- Silhouette flipbooks (cat run 16 frames Loop, cat leap 16 frames OneShot, bat flap 16 frames
  Loop, witch over the moon 16 frames OneShot): pose a simple jointed silhouette rig in Blender
  headless (metaball or sweep body, capsule legs, a pose function per frame), render it
  orthographic, black on transparent; then `tools/hw_sprites_b.py` adds the rim from the alpha
  edge (the alpha minus its erosion, gold `#E8B04A` for cats, violet for bats and the witch,
  1-2 px at 256 px cells, a soft glow) and packs 4x4 at 1024 with 8 px padding (as
  `sheet_sprite` does). The moon is a Pillow disc (soft craters, pale `#F4EBD0`). OpenAI images
  through `tools/openai_image.py` are allowed for one painted element if clearly better.
- **The moonwalk rule:** a camera-facing flipbook is never mirrored, so a sprite of a cat
  running right moonwalks when seen from the other side. A flipbook creature must either not
  travel (run in place, leap within its own cell, flap symmetrically) or be a 3D silhouette.
  Check every flipbook from both sides in the lab.

### 2.8 Data shapes

Skin JSON (copy the structure of `kitsune.json`; the body keys are Cues A's §2.2; the
generator drops `Note` and `Budget`):

```jsonc
{
  "id": "witch_broom", "name": "Witch's Broom", "tier": "Secret", "catalog_id": "WitchBroomCue",
  "draft": true,                       // until the generator runs clean without --allow-missing
  "body": "witch_broom",               // the body piece
  "maps_from": "classic",              // the hidden mesh wears Classic's maps (seen only if the body is missing)
  "look": { "Shaft": [107, 74, 46], "Forearm": [107, 74, 46], "Wrap": [91, 42, 134],
            "Ring": [201, 206, 216], "Accent": [168, 107, 255], "Tip": [168, 107, 255], "Cap": [217, 164, 65] },
  "piece": "witch_broom_aura",         // aura-only decoration (hides with the aura)
  "colours": { "violet": "#9B4DFF", "emerald": "#2EE6A0", "gold": "#FFD36A", "straw": "#D9A441" },
  "vfx": {
    "Piece": { "Note": "..." }, "Moving": { "Note": "..." },
    "Aura": { "Emitters": [], "Beams": [], "Lights": [], "Outline": "#A35CFF" },
    "Style": { "Trail": {}, "Pocket": { "Colors": [], "ColorShare": 1 } },
    "Trail": { "Emitters": [] },
    "Pocket": { "Layers": [], "Rings": [], "Flash": {},
                "Piece": { "Piece": "witch_broom_pocket", "Rise": [], "Scale": [], "Spin": [], "Transparency": [] },
                "Sound": { "Asset": "rbxassetid://<library id>", "Volume": 0.4 } },
    "Budget": { "ParticlesPerSecond": 0, "Lights": 0, "Beams": 0, "BodyTriangles": 0, "PieceTriangles": 0, "PocketPieceTriangles": 0 }
  }
}
```

- Ids: skins `witch_broom`, `black_cat`, `spider`; names "Witch's Broom", "Black Cat Cue",
  "Spider Cue" (= Cues A's Strings); tiers Secret, Mythic, Mythic (they set the quiet share and
  the Index band). `look` is the flat colours of the 2D power-bar cue and the band fallback.
- Sounds: an `"rbxassetid://..."` string passes through the generator untouched. Find Roblox
  library sounds with the Studio MCP asset search, check one plays in your window
  (`IsLoaded`, `TimeLength > 0`), volume ≤0.5. Nothing fits → no sound. Never upload audio.
- Piece rows: the exporter's `piece.json` plus your `Aim` keys (2.3).
- **Leaving draft:** the generator puts every uploaded id in the row, the card
  (`thumbs/<id>.png`) included, and stops on a missing one; Cues A's `cue_mesh_test` wants a
  built event skin to have a `Body`, a non-empty `Thumb` and a `Look`. So commit a skin without
  `"draft"` only when `python3 tools/cue_skins_data.py` runs clean without `--allow-missing`.
  Until then test in your window from a local non-draft copy and an `--allow-missing` run, and
  never commit generated files from such a run (restore them, regenerate clean, then commit).

### 2.9 Your builder entry point and the pipeline

`assets/cue/CuePiecesHalloween_B.py` registers on the imported `CuePieces` module (`from
CuePieces import piece, apply_modifier`, after putting its own folder on `sys.path`) and ends
with an `if __name__ == "__main__":` entry point that runs `CuePieces.main()`, then patches
each built `piece.json` with the `Aim` keys, then runs `check_envelope`. Always build your
pieces through it (the plain `CuePieces.py -- <pid>` command does not write `Aim`). Three
traps: once Cues A's drop 2 lands, your file is loaded twice (as `__main__` and as
`CuePiecesHalloween_B` through the guarded import), so keep the `Aim` keys in a **static
module-level table** (`AIM = {"spider": ["Crown"], ...}`), never recorded at build time; the
file must import with no side effects; and the guarded import catches only `ImportError`, so a
syntax error in your file breaks Cues A's builds: `python3 -m py_compile` it before every
commit.

```bash
B=/Applications/Blender.app/Contents/MacOS/Blender
$B -b --factory-startup --python-exit-code 1 --python assets/cue/CuePiecesHalloween_B.py -- witch_broom
$B -b --factory-startup --python-exit-code 1 --python assets/cue/CuePiecesHalloween_B.py -- --silhouette cat_run
python3 tools/hw_sprites_b.py cat_run cat_leap bat_flap witch_moon crescent straw web silk
python3 tools/cue_pieces_glb.py witch_broom witch_broom_aura witch_broom_pocket
python3 tools/roblox_upload.py --list <list in your scratch dir> --group-id 675425213 --dry-run   # then without --dry-run
python3 tools/manifest_image_ids.py emit --prefix assets/cue/ > <scratch>/ids.luau   # run it in YOUR Studio, Edit mode
python3 tools/manifest_image_ids.py apply <scratch>/result.txt
python3 tools/cue_skins_data.py --also-manifest ~/Desktop/8ball-hw-cues-a/tools/upload_manifest.json
# Studio, your window, Edit mode: tools/build_cue_templates.luau with ONLY = { "WitchBroomCue", "BlackCatCue", "SpiderCue" }, ALL = false
python3 tools/cue_skin.py witch_broom --thumb     # once Cues A's CuePreview draws bodies
```

The generator needs Cues A's drop 2 (the `body`, `maps_from`, `look` keys and `--also-manifest`)
merged into your branch; the ONLY build needs drops 2 and 3. Before then, judge your models in
the headless Blender previews.

### 2.10 Uploads, merges and generated files

- **You upload your own files** (images, GLBs) into `tools/upload_manifest.json` (keyed by
  absolute path, sorted). The script reads the key from the Keychain; never print it. If your
  key or window fails, Cues A is your backup: add `UPLOAD for A (<HH:MM>): <paths under
  assets/cue/, space separated>` to your Requests; A answers within 30 minutes with
  `UPLOADED for B (<HH:MM>): <path> = <id>, ...` in its Status, and you generate with
  `--also-manifest` (always pass it; it is harmless). A changed file: delete its manifest row
  with a one-line Python edit and upload again; never type ids by hand.
- **Manifest conflicts** (Cues A's rows sit next to yours): union both sides, never drop a row:
  read `git show :2:tools/upload_manifest.json` and `:3:` into your scratch folder, merge the
  dicts in Python (an `"ok"` row wins), write it back with `indent=2, sort_keys=True`, check it
  parses, `git add` it.
- **Generated files** (`src/shared/CueSkins/*`): on a conflict take either side, rerun the
  generator, check `git diff --stat src/shared/CueSkins` shows only Halloween skins and
  `Index.luau`, commit.
- **The coordinator merges by the same two rules** (its §2.2): a manifest conflict takes the
  union (an `"ok"` row wins, keys sorted; core's tile icon and GUI's chip icon rows sit there
  too), a `CueSkins` conflict is settled by re-running `python3 tools/cue_skins_data.py`. So
  keep your manifest rows well-formed (one per file, absolute-path keys) and never hand-edit a
  generated file. Both files are listed under Shared-file changes in your lane file.
- Never commit `assets/cue/renders/`, `_frames_*` folders, logs or checkpoint renders.

### 2.11 Switches, numbers, analytics

- **No Config block of yours.** Your off switch is data: `"draft": true` keeps a skin and its
  pieces out of the game (Cues A's `Catalog.ready` then hides the cue and its stand-in draws as
  Classic; core grants a track or active-play cue only once `Catalog.ready` is true and holds
  the grant until then, so leaving draft is what releases it); a dropped layer is a removed row. Cues A owns `Config.CueSkins.Bodies` (`Enabled`,
  `Outline`, `MaxParts` 8, `MaxOverhangStuds` 1.5, `AimFadeSeconds` 0.25, `PastButtStuds` 0.3,
  `TipSlackStuds` 0.01).
- PLAN numbers that bind you: the ids; effects levels Cat Mythic, Spider Mythic, Broom Secret;
  group Exclusive (Cues A); track 2,000 (Cat) and 7,000 (Broom), the Spider at 10,860 s of
  active play (core); the cloths you must stay readable on under Night: 1v1 orchid purple
  (185,90,230), 2v2 charcoal (90,94,102) with orange glow, 3v3 toxic green (110,220,40);
  go-live 19:00; builds stop 16:00.
- Your own numbers (log them as Assumptions): the budgets in 2.2 and 2.4-2.6; trail Lifetime
  1.2 (Mythic) / 1.4 (Secret); finisher 1.6 s (Mythic) / 2.2 s (Secret).
- **Analytics:** none of yours (no runtime code). Cues A logs `HalloweenCueEquipped` for all
  five cues; core logs the grants (R2.7's 100+ Broom owners).

### 2.12 Edge cases to check for every cue

Raised over a rail (body stays; aura and `Aim` overhangs gone on your own screen) · your own
turn (the aura eases to 0.25; overhangs gone for you only) · Lower effects (identity holds:
body, core aura, trail core, finisher flash) · on a back walking, sitting on a lounger, small
R15, tall R15, R6 · in other players' hands at another table · the camera close to the butt ·
the YOU GOT scene (PullKit) · the Cue Preview stage once GUI's lane is merged · the first load
of the cue (never grey, the pocket creature present on the first pocket) · two Halloween cues
at one table · all three cloths under Day and Night, every ball readable through trail and
finisher (the 8 ball under a black trail on charcoal) · Highlights cap (`MaxShown` 14) · every
flipbook from both sides (the moonwalk rule).

## 3. Interfaces

**You deliver first.** PLAN §5 lists nothing from Cues B, and Cues A has already adopted this
lane's `Aim` key, own-distance fade, budgets and naming (its §2.4-2.6, §3.4). Push by
**08:15**, small, tests green:

1. Your lane file's **Requests**: to Cues A, a confirmation line ("Cues B builds to your §2.2
   keys `body`/`maps_from`/`look`, §2.4 `"Aim": "fade"` and own-distance fade, §2.6 names and
   budgets; tell me in your Status if any name changes"), and `CuePreview.py --thumb` drawing
   bodies with their `Aim` overhangs (long variant) by 12:00. To the coordinator: "merge Cues A's
   drop 3 into `halloween` as soon as it is READY (about 10:00): Cues B needs it for gate 2".
2. Three skin stubs with `"draft": true` (ids, names, tiers, catalog ids, `look`, colours):
   they reach nothing in the game.
3. `assets/cue/CuePiecesHalloween_B.py` with the entry point, the `AIM` table, `check_envelope`
   and a Broom blockout body that passes it (built, `preview.png`); the Lune test (it skips
   drafts). This file must exist and compile before Cues A's drop 2 imports it.

**You consume** (never a stub; until each lands you work on what does not need it):

| From | What | Until it lands |
|---|---|---|
| Cues A drop 1 (08:15-08:30) | rows `BlackCatCue`, `SpiderCue`, `WitchBroomCue` (Exclusive; Effect Mythic, Mythic, Secret; stand-in Classic; hidden until ready) and Strings names | skins stay draft |
| Cues A drop 2 (about 08:45) | data tool keys, `--also-manifest`, budget stop, ONLY filter, the guarded import of your file | model in Blender, run your entry point directly; no generated rows |
| Cues A drop 3 (about 10:00) | the body path, `Aim`, own-distance fade, `Config.CueSkins.Bodies` | headless previews only; to see a shape in the hands earlier, set the skin's `piece` to the body on the shared mesh in your window (local only, never commit); not in `halloween` by **12:00** → the coordinator decides (Cues A's `BLOCKER` rule): Cat and Spider as pieces on the shared mesh, the Broom waits |
| Cues A (by 12:00) | `CuePreview.py` bodies in thumbnails | skins stay draft; at 15:00 without it, a Request to the coordinator |
| Map | `Lighting.Night` | judge under Day and Sunset; under Night once merged |
| GUI | `CuePreview.luau` stage | the lab and a solo match |

**Handing a finished cue to the coordinator** (finished cues reach them through Cues A's
pipeline and your Requests; `hw-cues-b` merges last). When a cue's last step is pushed, write
one Request: `READY <CatalogId> @ <sha>`, its skin id, piece ids, manifest paths, and "the
Team Create template build includes it (Cues A's Request 3: ONLY with all five ids, ALL =
false)". Nothing of yours is built by hand in your window: every part is data, so the merge
plus the builder reproduces it.

## 4. Checks

After every Progress step: `python3 -m py_compile` on your Python files, `tools/lint.sh`,
`tools/test.sh`, the check in your Studio, commit (one step per commit, the attribution line),
`git push -u origin hw-cues-b`, tick the line, one dated Status line in your lane file.

- **Lune test** `tests/halloween_cues_b_test.luau` (Cues A's `cue_body_test` already checks
  body parts, tip and overhang; yours adds), for each of the three ids that has a skin row (a
  draft has none and is skipped): Tier Secret/Mythic/Mythic; the pocket piece exists; aura
  particles per second ≤ the tier budget (120 Mythic, 170 Secret) and lights ≤2 Mythic, ≤3
  Secret; every `Sound.Asset` an `rbxassetid://` string; `Thumb` a non-empty `rbxassetid://`
  string. At P20, make it require all three rows.
- **Blender:** `check_envelope` passes for every body; `preview.png` beside the concept.
- **Studio, your window only** (`list_roblox_studios`, pick the one named
  `lane-hw-cues-b.rbxl`; Rojo on 34885): the ONLY build, console clean (no CueSkinLook,
  CuePiece or CueAssets warnings); `tools/vfx_lab.luau` with `IDS = { "WitchBroomCue",
  "BlackCatCue", "SpiderCue", "EclipseCue", "BetaCue", "FireworkCue" }` from the back, stand and
  front views, each also from the other side, on the bright floor and under Night; a solo or PC
  match (`/givecue` through `DevCommandsQA`, equip from My Cues): the tip on the ball, both
  hands clear of the decor (a long wind-up, a steep shot), the aim view, the cue raised over a
  rail, the trail over each cloth, the pocket finisher and a scratch; Lower effects on and off.
  Give new emitters a couple of seconds before a capture.
- **Four device sizes** via `tools/halloween/studio_size.sh lane-hw-cues-b.rbxl <w> <h>`, then
  read `workspace.CurrentCamera.ViewportSize` through MCP until it is phone 844×390, iPad
  1024×768, PC 1920×1080, and TV 1920×1080 with `PlayerScripts.GuiQA:Invoke("padMode", true)`:
  the aim view with each cue (nothing over the cue ball, the aim line or the object ball) and
  the cards in My Cues, the Index and the event track (once core's menu is merged). If the
  resize helper fails (macOS permission), say so in the lane file; the coordinator sweeps.
- **Fresh-player run:** you touch no join, tutorial, save, purchase or popup code, so none is
  required; do one rejoin with each cue equipped to see it load (no grey cue, the finisher
  creature on the first pocket).
- **Screenshots** to `~/Desktop/8ball-refs/halloween/shots/hw-cues-b/` (gate shots in `gate1/`
  and `gate2/`), one line per image in the lane file.

## 5. Cut order

Cut from the top when the time plan slips by more than 30 minutes. A cut is switched off or
removed, never left half-visible, and listed in the lane file with the reason:

1. The Cat's 3D runner cats (stretch; the flipbook shadow cats stay).
2. Sounds (no sound beats a wrong one).
3. Extra aura flecks: the Broom's straw leaves and crescents, the Spider's web flecks (the
   haze, wisps, stars, bats and silk beams stay).
4. The Spider's `spider_pocket` web piece (the finisher becomes the web ring decal, a web
   flipbook burst, smoke and sparks).
5. Long overhangs (bristles, tail, blades): the compact variants ship (automatic if drop 3 is
   not merged and seen working in your aim camera by 14:00).
6. The Broom's witch-over-the-moon flipbook (the portal, column and star burst stay).

Never cut: a body, the core aura (body layer, lights, outline), a trail with a core, a finisher
with a flash and a ring, the card, the Lower-effects variant. If the Spider cannot reach that
floor by **15:00**, write a Request to the coordinator at once (Cues A may take its effects).

## 6. Gates

- **09:00 (gate 1; the gate itself is Candy Corn and Jack, yours is a progress look):** the
  Broom body's `preview.png` and three headless renders (three-quarter, a hand-zone close-up,
  the hat charm and bristles) next to `C3b_broom.png`, in `shots/hw-cues-b/gate1/`; one line
  each in the lane file.
- **11:00 (gate 2, PLAN §8 "Broom/Cat/Spider bodies"):** all three bodies in your Studio through
  drop 3: on a stand and on a back in the lab beside Eclipse, in the hands at a table, and the
  aim view at phone size with the overhangs faded (or the compact variants), each next to its
  concept; in `shots/hw-cues-b/gate2/` with one line each. If drop 3 is late, the headless
  renders of all three plus whatever runs in your window, labelled. Ask nothing at 11:00
  unless a body must differ visibly from its concept.

## Progress

- [x] 1. First push by 08:15: lane file Requests (section 3), three draft skin stubs,
  `CuePiecesHalloween_B.py` (entry point, `AIM` table, `check_envelope`, a Broom blockout body
  that passes), `tests/halloween_cues_b_test.luau` (skips drafts); compile, lint and tests
  green, pushed, Status line.
- [x] 2. Lane ready: worktree on `hw-cues-b`, Rojo 34885 into `lane-hw-cues-b.rbxl`, the window
  found by name, the lab showing Eclipse, Beta and Firework.
- [x] 3. Witch's Broom body: crystal tip, crooked bark handle straight in both hand zones, knot,
  twig stubs, binding and buckle, straw bristles (compact and long, `Aim`), skinned hat charm on
  a Sway chain, one atlas; `check_envelope` passes; uploaded; preview and gate-1 renders beside
  `C3b_broom.png`.
- [x] 4. Drops 1 and 2 in your branch: `git fetch && git merge halloween` once the coordinator
  has merged drop 1 (the three rows present) and drop 2 (generator keys, `--also-manifest`, the
  ONLY filter, the guarded import of your file); one plain `CuePieces.py -- <pid>` headless build
  of an existing piece still runs with your file imported (no side effects, `py_compile` clean).
  If drop 2 is not in `halloween` yet, merge what is there, say so in Status and tick: P7 merges
  it with drop 3.
- [x] 5. Black Cat body: black shaft, gold rings, claw inlays, knurled wrap, gold claw tip
  inlay, the skinned swaying tail with its gold ForceField shell (compact and long, `Aim`), one
  atlas; `check_envelope` passes; uploaded; preview beside `C2c_black_cat.png`.
- [x] 6. Spider body: segmented chrome shaft, spear ferrule, one crimson hourglass, the skinned
  eight-blade crown with silk webs and breathing blades (compact and long, `Aim` on the crown
  root), one atlas; `check_envelope` passes; uploaded; preview beside `C1b_spider.png`.
- [x] 7. Bodies in the game: drops 2 and 3 merged, rows generated, the ONLY build of the three in
  your window; each checked in the hands (long wind-up, steep shot), on a back (small R15, tall
  R15, R6, walking and sitting), raised over a rail, and in the aim view at phone and PC sizes.
- [x] 8. Gate 2 at 11:00: the three bodies on a stand, a back, in the hands and in the aim view
  beside Eclipse and their concepts; shots in `gate2/`, lines in the lane file.
- [x] 9. Broom sprites: bat flap 4x4, crescent, straw leaf, witch over the moon 4x4, a portal
  swirl if needed; drawn by `tools/hw_sprites_b.py`, checked from both sides, uploaded, image
  ids applied.
- [x] 10. Broom aura: `witch_broom_aura` ribbons, haze, wisps, stars, bats, flecks, charm sparkle,
  crystal and binding lights, violet outline; ≤170/s; Lower effects; judged on the bright floor
  and under Night beside Eclipse.
- [x] 11. Broom trail and finisher: violet-emerald trail with stars, crescents, straw and bats;
  portal rings, sparkle column, witch over the moon, star burst, ring, library sound; checked in
  a solo match on all three cloths.
- [x] 12. Black Cat sprites: run-in-place 4x4 and leap 4x4 (black, thin gold rim), checked from
  both sides; uploaded, ids applied.
- [x] 13. Black Cat aura: black smoke, gold-edged wisps, embers, shadow cats, collar light, gold
  outline; ≤120/s; Lower effects; Day and Night.
- [x] 14. Black Cat trail and finisher: gold-cored dark trail with the pack, smoke and sparks;
  the leap out of the pocket with smoke, shards, gold ring and sparks, library sound; every ball
  readable on charcoal; solo match.
- [x] 15. Spider sprites: radial web, silk strand, web ring decal; uploaded, ids applied.
- [x] 16. Spider aura: black smoke, silk beams between blade tips and along the shaft, web
  flecks, glints, the hourglass glint, silver outline; ≤120/s; Lower effects; Day and Night; no
  creature anywhere.
- [x] 17. Spider trail and finisher: silk trail with strands and flecks; `spider_pocket` web
  rising and opening, web ring, smoke, sparks, crimson glint, library sound; solo match.
- [x] 18. Long overhangs decided, before any card: the aim fade watched in your aim camera at
  phone and PC sizes → long variants on (rebuilt, uploaded, re-checked on a back); otherwise
  the compact ones ship and the cut is logged.
- [x] 19. Cards: the three thumbnails with their auras and the overhang variant P18 chose,
  through `tools/cue_skin.py <id> --thumb` (Cues A's body support), uploaded, ids applied, all
  three skins out of draft (2.8); checked in My Cues, the Index and the event track at phone and
  PC sizes; a `READY` Request per cue to the coordinator (section 3).
- [x] 20. Final lineup and devices: all three beside Eclipse, Beta and Firework in the lab (Day
  and Night), the aim view at the four sizes, a rejoin with each cue equipped; the Lune test
  requires all three rows; compile, lint and tests green.
- [x] 21. Lane file Status final + all screenshots.
- [ ] 22. Merge halloween, re-test, push.

## Notes
