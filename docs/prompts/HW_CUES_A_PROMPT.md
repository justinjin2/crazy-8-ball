# Halloween lane W3, Cues A: the custom-model path, Candy Corn and Jack-o'-Lantern

**Written 2026-10-28 07:20 EDT by the coordinator, from `docs/halloween/PLAN.md` and the
`code-cues` agent report (its file:line claims checked against `halloween` @ 12ee4888).**
Lane `hw-cues-a`: folder `~/Desktop/8ball-hw-cues-a`, branch `hw-cues-a` (cut from
`halloween`), Rojo **34884**, Studio window `place/lane-hw-cues-a.rbxl` (and only that one),
**Fable 5.1 at xhigh**. The shared contract is [PLAN.md](../halloween/PLAN.md): it wins over
this brief; log any clash in your lane file. Lane file: `docs/halloween/lanes/hw-cues-a.md`.
Requirements: `docs/halloween/REQUIREMENTS.md`.

**Start and restart:** the coordinator launches this lane with `tools/halloween/lanes.sh
launch`. The launch line, and any restart of this lane, is exactly the command
`tools/halloween/lanes.sh command hw-cues-a` prints (it carries the hook settings, the model and
the effort); never write your own flags.

**Attended until 11:00.** The Progress list at the end is the source of truth; the Stop hook
(`tools/overnight/hw_cues_a.json`) sends you back to work while any `- [ ]` remains. Until
11:00 Justin answers fast: when you truly need him (a look only he can judge, access you can't
get, a click only he can make), run `touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"`
(in this worktree `.git` is a file, so `touch .git/overnight-waiting` fails), ask ONE short
question with the picture's path, and stop; the hook lets that one stop through. **After 11:00
never stop to ask:** he may be asleep until about 16:30. Decide the way he would (PLAN §2, the
approved concepts, the past cue decisions in `docs/prompts/UNIQUE_CUES_PROMPT.md`, simple and
readable for kids), log it under Assumptions in the lane file, keep going. A truly blocked step
is ticked `- [x] BLOCKED: <why>` and you move on.

**Rules for today.** Times are EDT. Lanes finish by **16:00** (every line ticked: done, CUT or
BLOCKED); **17:00** freeze; Justin publishes about 18:30; live 19:00. Never publish. Never touch
the Team Create place ("Crazy 8 Ball") or another lane's Studio window; Rojo only on 34884.
Blender **headless only** (`/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup
--python-exit-code 1 --python ...`); the live Blender MCP is shared, never use it. Images and
meshes go to group 675425213 **without asking** (`tools/roblox_upload.py`, key in the Keychain,
never print it, dry-run first); **no audio uploads**, Roblox library sounds only; no other
spending. Small verified steps: `tools/lint.sh`, `tools/test.sh`, a Studio check in your window,
commit on `hw-cues-a` with the attribution line, `git push -u origin hw-cues-a`, tick the line,
a dated line in the lane file's Status. Never edit `docs/STATUS.md`, `ROADMAP.md` or
`DECISIONS.md`; your decisions go in the lane file. You may use subagents for independent jobs
(a Blender modelling pass while you write the runtime path), but only you drive your Studio
window, and you own the result.

## 0. Read first

In this order, fully: `docs/halloween/PLAN.md`, `docs/halloween/REQUIREMENTS.md`, `CLAUDE.md`,
`docs/parallel/README.md` (its rules apply with PLAN §4's lanes and ports and branch
`halloween` instead of `release`), this brief, your lane file, `docs/CUE_VFX_TECHNIQUES.md`
(the craft: the depth rule, the aura recipe and budgets, trails, finishers, Lower effects,
pitfalls), `docs/prompts/UNIQUE_CUES_PROMPT.md` (how the last top cues were built; its Handoff
section is the pipeline in practice), the `assets/cue/CuePieces.py` docstring (the piece
format and joint kinds), `assets/cue/CuePiecesUnique.py` (a builder file), and in
`docs/STUDIO_NOTES.md` the sections "Uploading assets with Open Cloud", "Images come back as a
Decal ID" and the pad-mode note ("Without a pad").

**The approved concepts (Justin, rev 1; build to them, `.jpg` twins are the same pictures):**

- `/Users/justinjin/Desktop/8ball-refs/halloween/mocks/v2/C5_candy_corn.png`: a glossy candy
  cue on a dark purple board. Tip: a candy-corn kernel (white point, orange, yellow) behind an
  orange collar. Shaft: pearly cream-white, glossy, faint sugar sparkle. Joint: a white/orange
  candy-stripe twist wrap between orange and white rings. Forearm: orange with sugar glitter.
  Handle: yellow glitter. Butt: a rounded bulb in candy-corn bands (yellow end, orange, white),
  wider than the cue. Aura: little 3D-looking candy corns floating round the cue, orange,
  yellow and white sugar dots, one thin gold swirl line winding along it. Panels: CANDY (the
  bulb close-up), TRAIL (gold sparkle swirl with a kernel and dots), FINISHER (kernels, short
  orange/yellow/white sprinkle rods and a gold spark fountain bursting from the pocket). Copy
  the colours, the kernel tip, the striped wrap, the bulb, the floating kernels; ignore the
  title lettering and the blue cloth.
- `/Users/justinjin/Desktop/8ball-refs/halloween/mocks/v2/C4_jack.png`: an orange cue with
  shallow lengthwise pumpkin-rind ribs, a green vine with leaves spiralling along it, dark
  brown wooden collars with glowing orange slits at the joint, a dark green stem-like tip with a
  brown ring, and at the butt a carved jack-o'-lantern (ribbed, glowing triangle eyes and a
  jagged grin) with a curly green stem out of the end. Aura: orange flames licking along the
  cue, small glowing jack-o'-lantern faces floating round it, embers. TRAIL: flames with mini
  jack-o'-lanterns. FINISHER: a flaming jack-o'-lantern face rising out of the pocket in fire,
  mini jacks round it. Justin's own rule (R2.2): **no candy corn on it**, and the finisher is a
  **laughing** jack-o'-lantern. Ignore "EPIC / LEGENDARY" on the board: its level is Legendary.
- The painted-VFX quality bar (layered, crisp, real shapes, depth):
  `/Users/justinjin/Desktop/8ball-refs/cue-vfx/01-fire-slash-arc-painted-anime-vfx.webp`
  (useful for Jack's flames).

**The agent report:** `~/Desktop/8ball-refs/halloween/research/agents/code-cues.md` (its "Body
piece" design is section 2 below). Two corrections from the check: the outline Highlight and
the ink ribbons live in `CueSkinLook.luau` (403, 430, 438, 472), not in CueStickBuilder; and
the grip hand sits anywhere about **4.4 to 6.75 studs from the tip** (`Config.luau:1471`
GripFromButtFraction 0.15 puts it at 5.95; the cue slides back through it up to
MaxGripSlideStuds 1.5 at :1323; never within GripButtEndStuds 0.25 of the butt at :1472), a
little wider than the report's 5 to 6.8.

**Code to know (lines on `halloween` @ 12ee4888):**

- `src/shared/CueStickBuilder.luau`: `known` 77, `meshTemplates` 103 (templates are found once,
  catalog ids only), `applyVisibility` 166, `paintStick` 190 (no template → bands), `build` 318,
  `frame` 429 (the only placement maths; pivot = tip, the stick runs along local +Z).
- `src/client/CueSkinLook.luau`: `attach` 175, `clear` 279, `refresh` 326 (keys off the stick's
  `Mesh` attribute; `self.piece = CuePiece.new(row.Piece, mesh, folder)` 357), CueOutline
  Highlights 403/430 (adornee = the stick), `buildInk` 438/472, `applyVisible` 951 (AuraOff
  hides every effect AND the piece at 1014-1015), `step` 1027 (the piece copies
  `mesh.LocalTransparencyModifier` at 1166-1169), `quietTarget` 1216, `destroy` 1248.
- `src/client/CuePiece.luau`: `new` 221 (returns nil when the row or the template is missing),
  aura/low joints 234-235, `setModifier`, `setFade` 546. `src/shared/CueSkins/Motion.luau`:
  `rig` reads joint flags at 303-304 (`Aura`, `Low`); Hinge and Sway at 352.
- `src/client/CueAssets.luau`: `addPiece` 324, the row's piece warmed at 398, `holdShots` 586,
  `holdLooks`. `src/shared/CueSkins/Pop.luau:227` `Pop.level` (the catalog Effect sets the
  ladder level; Legendary and up get the moving gradient outline).
- `src/client/Effects.luau`: `styleOfCue` 121, `pocketBurst` 577, the pocket sound 773
  (`Config.Effects.Finisher.Sound`), `skinFinisher` 796.
- `src/shared/Progression/Catalog.luau`: `skinLook` 68, `rankCue` 95, `specialCue` 113, the
  Exclusive and Unique rows 219-240, Exclusive's sort place 253-260, `Catalog.style` 354.
  `src/shared/Strings.luau` cue names at `Strings.Progress.Cues` (Beta at 668).
- Every drawn cue goes through `CueSkinLook.attach`: your own (`Main.client.luau:134`), others'
  (`Hub.luau:83`), backs (`BackCue.luau:90`, placed by `tipInTorso` 124/181), the YOU GOT scene
  (`PullKit.luau:711`), and the GUI lane's new Cue Preview. Camera fade: `Camera.luau:873`.
  Cards: `CueThumb.luau:110-140` and `PowerCue.luau:131` show the skin's `Thumb`.
- Tools: `tools/cue_skins_data.py` (`asset_id` 40, `resolve` 69, `skin_row` 172, `piece_row`
  212, `main` 233), `tools/build_cue_templates.luau` (skins loop 86-121, `pieceIds` 170-181),
  `assets/cue/CuePreview.py` (piece attach 202-210, `--thumb` 642-720, outline pass 684),
  `assets/cue/CuePieces.py` (builder imports 1117-1120 and 1198-1200), `tools/cue_pieces_glb.py`,
  `tools/cue_skin.py` (`--thumb`), `tools/manifest_image_ids.py` (emit/apply), `tools/vfx_lab.luau`.
- Patterns to copy: `assets/cue/pieces/infernal_pocket/piece.json` (a Skull joint with a Jaw
  child on a snapping Hinge: the laughing jaw) and `assets/cue/skins/infernal.json` (a
  Legendary's pocket timeline with a rising piece); `assets/cue/skins/firework.json`
  (`Pocket.Sound`); an Epic with only a pocket timeline, e.g. `assets/cue/skins/blood_moon.json`.
  Shared sprites in `assets/cue/vfx/_shared/` (`fire_8x8`, `energy_flame_8x8`, `smoke_8x8`,
  `spark`, `sparkles_main`, `star4`, `glow_soft`, `ring`, `wisp_strip`).
- Tests: `tests/catalog_test.luau:60-67` (counts 2 Exclusive), `tests/cue_mesh_test.luau:9-31`
  (every non-Unique cue has a skin), `tests/cue_looks_test.luau:101`.
- Studio fixtures (Play, server side): `ServerStorage.DevCommandsQA:Invoke(userId, "/givecue
  CandyCornCue")`, `ServerStorage.PoolMatchQA` (match fixtures); client:
  `PlayerScripts.GuiQA:Invoke("padMode", true)`.

## 1. Goal

**Rows this lane owns:** R2.1 (Candy Corn), R2.2 (Jack-o'-Lantern), R2.8 (the rarity ladder:
the `Effect` levels of all five in the Catalog, and its first two rungs), R2.9 for its two cues
plus the "unique model" part for all five (the body path makes it possible; R2.5's "doesn't
have to follow cue conventions" depends on it), R2.10 (build only the approved concepts),
R1.3 with core (the rows: never sold, traded or returning), and R0.6 for the cue runtime (no
critical bug: the path fails safe).

**Done, in player terms:**

- Five new cues exist from the first merge (valid ids and names everywhere), and none shows in
  the Index or anywhere else until it is built, so nothing half-made is ever on screen.
- A cue can be its own model. The cue in your hands, on your back, in other players' hands, in
  the YOU GOT scene, in the Cue Preview and on its card all show the custom body, never the
  standard stick under it. If a body is missing, the player sees a normal Classic cue, never an
  error or an empty hand.
- **Candy Corn Cue** (track 150, Epic level): a white, orange and yellow candy cue with a kernel
  tip, a turning candy-stripe wrap and a candy-corn bulb; little candy corns float round it with
  sugar sparkles; a gold sparkle trail drops tumbling kernels; the pocket bursts with kernels,
  sprinkles and gold sparks. Clearly nicer than every Epic today (Void, Blood Moon, Toxic,
  Magma, Prism, Aurora, Disco, Hacked, Shooting Star), clearly smaller than Jack.
- **Jack-o'-Lantern Cue** (track 500, Legendary level): an orange ribbed cue wrapped in a
  swaying green vine, a carved pumpkin at the butt whose face flickers like a candle, flame
  wisps, embers and floating mini jack-o'-lanterns; a flame trail; at the pocket a
  jack-o'-lantern rises in fire and laughs, jaw moving, with a laugh sound. Beats every
  Legendary today (Infernal, Phoenix, Kraken, Seraph, Clockwork, Chroma, Thunderstrike), and
  stays below the Mythics and the Broom.
- Both: the tip reads on the ball while aiming, the balls stay readable through the trail and
  finisher, Lower effects keeps each identity, and they look right in the bright day lobby and
  under the event's Night lighting, on phone, iPad, PC and TV.

## 2. Design

### 2.1 Catalog rows and names (interface drop 1)

In `Catalog.luau`, next to `specialCue` (113), a constructor, and a block after the Unique rows:

```lua
-- The Halloween 2026 event cues (designer, 2026-10-28; docs/halloween/PLAN.md §3): group
-- Exclusive, one copy each, never traded or sold, never coming back. Effect is the visual
-- ladder level (Pop.level). Until its skin is built a cue is hidden (Catalog.ready) and drawn
-- as Classic (StandIn).
local function eventCue(id: string, effect: string): Cue
	local cue = specialCue(id, "Exclusive", effect, skinLook(Catalog.Default))
	cue.Event = "Halloween2026"
	cue.StandIn = Catalog.Default
	return cue
end
	...
	eventCue("CandyCornCue", "Epic"), -- track 150
	eventCue("JackOLanternCue", "Legendary"), -- track 500
	eventCue("BlackCatCue", "Mythic"), -- track 2,000
	eventCue("SpiderCue", "Mythic"), -- 3 h 01 m of active event play
	eventCue("WitchBroomCue", "Secret"), -- track 7,000
```

`specialCue` already takes `SkinIndex[id].Look` once the skin exists. Add `Event: string?` and
`StandIn: string?` to the `Cue` type. Pure helpers, Lune-tested:

- `Catalog.ready(id): boolean`: a catalog cue that is not an event cue, or whose skin is in the
  Index (`SkinIndex[id] ~= nil`; a skin JSON with `"draft": true` is not in it). **This contract
  stays fixed** (name, signature, meaning) from drop 1 to the end: core grants a track cue only
  when `Catalog.ready(id)` is true, holds the grant otherwise and retries it on load and on
  every tick. So taking a skin out of draft is what hands the cue to earners: do it only when
  the cue is complete (the leaving-draft rule in 2.2).
- `Catalog.ofRarity` skips event cues that are not ready, so the Index row, its totals and
  every per-rarity list never show an unbuilt cue. `Catalog.list`/`get`/`exists` keep all five
  (saves, dev commands, trading checks stay valid).
- `Catalog.drawAs(id, has: (string) -> boolean): string?`: the template the stick wears: its own
  when `has(id)`, else its `StandIn`'s when `has(StandIn)`, else nil (bands). `paintStick` (190)
  calls it with `meshTemplates()` instead of `meshTemplates()[id]` (set `meshSkin` to the
  template actually worn).

Names in `Strings.Progress.Cues`: `CandyCornCue = "Candy Corn Cue"`, `JackOLanternCue =
"Jack-o'-Lantern Cue"`, `BlackCatCue = "Black Cat Cue"`, `SpiderCue = "Spider Cue"`,
`WitchBroomCue = "Witch's Broom"`. Never reuse `CandyCue` (the Candy Cane invite cue) or
`PhantomCue`. They sit in the Index's existing Exclusive row (no new row, no layout change);
each pays the existing Exclusive find money (`Config.Index.FindMoney.Exclusive`, $1,000) the
first time it is owned: an existing rule, not a new number (log it under Assumptions).

### 2.2 The data tool (`tools/cue_skins_data.py`, drop 2)

New skin JSON keys, all passed through to the rows (pitfall: a key not added to the filters
silently never reaches the game):

- `"body": "<piece id>"` → `row.Body` and `Index[id].Body`; the body's piece is added to `used`
  so its piece row is written.
- `"maps_from": "classic"` → the row's `Maps` come from `textures/classic_*.png` (already
  uploaded) instead of the skin's own; the body hides the mesh, so these show only if the body
  is missing.
- `"look": {"Shaft": [r,g,b], "Forearm": ..., "Wrap": ..., "Ring": ..., "Accent": ..., "Tip"?,
  "Cap"?}` → `row.Look` as given (sampling would read Classic's map).
- `--also-manifest <path>` (repeatable): extra manifests read after the repo's own, read-only,
  so Cues B can generate rows with ids you uploaded before the branches merge.
- A piece over the hard budget (a body over 8 parts or 10,000 triangles, an aura piece over
  10,000, a pocket piece over 20,000, from piece.json `Triangles`; the same limits as Cues B's
  brief) stops the run with the numbers; `--allow-over-budget` exists for work in progress
  only, never for a committed run.
- **Leaving draft** (the same rule as Cues B's brief 2.8): a skin stays `"draft": true` until
  its body, aura, trail, finisher and card are done, because leaving draft makes
  `Catalog.ready` true and core then grants it. `cue_mesh_test` wants a built event skin to have
  a `Body`, a non-empty `Thumb` and a `Look`, so commit a skin without `"draft"` only when
  `python3 tools/cue_skins_data.py` runs clean without `--allow-missing`. Until then test in your
  window from a local non-draft copy and an `--allow-missing` run, and never commit generated
  files from such a run (restore them, regenerate clean, then commit).

Regenerating must not change any shipped row: after a run, `git diff --stat src/shared/CueSkins`
shows only the Halloween files and `Index.luau`.

### 2.3 The template builder ONLY filter (`tools/build_cue_templates.luau`, drop 2)

Today a run destroys and rebuilds all 60 templates and every piece (one failed `LoadAsset`
would break a shipped cue on the live place). Add at the top:

```lua
local ONLY = nil -- e.g. { "CandyCornCue", "JackOLanternCue" }: rebuild only these skins'
-- templates and the pieces they use (Piece, Carrier, Body, Pocket.Piece); nothing else is touched
local ALL = false -- true: the old full rebuild (never on the live place)
```

With `ONLY` nil and `ALL` false it refuses with a clear message. Add `row.Body` to `pieceIds`.
The report line says "only: N skins, M pieces rebuilt; K other templates untouched". Prove it in
your window: keep references to every other template and piece before the run and assert they
are the same instances after it.

### 2.4 The runtime body path (drop 3, behind `Config.CueSkins.Bodies.Enabled`)

- **One pure decision** in `src/shared/CueSkins/init.luau`, Lune-tested:
  `CueSkins.bodyOf(id, hasPiece: (string) -> boolean, enabled: boolean): string?` → the body
  piece to draw, or nil (no `Body` in the Index row, the switch off, or the piece template
  missing from `ReplicatedStorage.CuePieces`). Nothing else decides.
- **CueStickBuilder** (`applyVisibility` 166, `paintStick` 190): when `bodyOf` gives a body, the
  mesh slot stays (it is the body's root and the camera-fade source) with `Transparency = 1`
  always and `CastShadow = false`; the `Mesh` attribute stays true (the look keys off it); set
  a `Body` attribute naming the piece.
- **CueSkinLook:**
  - `refresh` (326): `self.body = CuePiece.new(body, mesh, folder)`, separate from `self.piece`
    (which stays the aura-only decoration a skin may still have).
  - `applyVisible` (951): `self.body:setModifier(if visible then 0 else 1)`: the body follows
    the stick's visibility, **never AuraOff** (the cue raised over a rail; today the piece
    vanishes there, 1014).
  - `step` (~1166): `self.body:step(t)` and, while visible, the camera fade below.
  - Outline: the `CueOutline` Highlight's adornee (403/430) is `self.body.model` (a Highlight on
    a Transparency-1 mesh draws nothing); obey `Config.CueSkins.Bodies.Outline`. Skip
    `buildInk` (438) for body cues (it traces a straight stick). `PieceHighlight` (410) stays on
    `self.piece`.
  - `clear` (279) and `destroy` (1248) destroy the body.
  - Body joints never take the aura flag, `Low = "hide"` or the quiet share (a test enforces it).
  - Camera fade: each body part fades by the larger of the mesh's modifier and **its own**
    distance to the camera (the `Camera.fadeNear` formula, `Config.Cue.CameraFadeStuds`, applied
    inside CuePiece so one writer owns the parts' modifier), so a long part never pokes into the
    lens. This is Cues B's request in its brief (2.3).
- **The aim-fade joint key, `"Aim": "fade"`** (Cues B's proposed name, kept so both briefs
  agree; `Motion.rig` 303 reads `Aim` like `Aura`/`Low`; CuePiece applies it per joint and to
  its children): on the stick owner's **own screen**, while that stick is drawn for a shot
  (`AuraQuiet` on their turn, or `AuraOff` when raised, which Main sets on your own stick only,
  `Main.client.luau:1725`), the joint eases to clear over `Bodies.AimFadeSeconds` and back after
  the shot; everyone else sees it whole (pass `own = true` from `Main.client.luau:134`, one line
  listed in Shared-file changes). The Broom's bristles, the Cat's tail and the Spider's blades
  use it to reach past the butt; any cue may use it, on a body or a piece.
- **CueAssets** (398): `addPiece(w, row.Body, seen)`, so the body is warm before a stick swaps.
- **Free everywhere:** your stick, others', backs, the YOU GOT scene and the Cue Preview all go
  through `attach`, so they need no extra code. `Pop.level` gives Jack the moving gradient
  outline and Candy Corn the solid one.
- **Fail-safe:** body piece missing in the place → the stick shows the mesh in Classic's maps
  with the skin's aura; one `warn` per id per session. `Bodies.Enabled = false` does the same
  for every body cue.

### 2.5 Thumbnails with the body (`assets/cue/CuePreview.py`, by 12:00)

When the skin has `body`: attach it like the piece (202-210, `CuePieces.attach`), hide the base
cue mesh from every render pass, include the body in `reach`, thicken only the body by
`THUMB_THICKEN` (1.45) across (X and Z), and render the body, not the bare stick, in the
outline pass (684). The body support lands by 12:00 in its own commit, because Cues B needs it
for its cards. Your own two cards come later, after Jack's trail and finisher (Progress 12), so
the aura frozen into each card is the final one: `python3 tools/cue_skin.py <sid> --thumb` (the
aura frozen in, the 2026-10-07 decision). The thumbnail feeds the Index, My Cues, the power-bar
cue and core's track cards, so it must read at phone card size.

### 2.6 Modelling rules (every body; the same numbers as Cues B's brief 2.2)

- Names: the body piece is named like the skin (`candy_corn`, `jack_o_lantern`), aura-only decor
  `<sid>_aura`, the finisher `<sid>_pocket` (Cues B uses the same scheme).
- Builders in `assets/cue/CuePiecesHalloween_A.py` (`@piece` from `CuePieces`), Blender cue
  frame: X the side, Y from 0 at the tip to −7 at the butt, Z up. Build with
  `Blender -b --factory-startup --python-exit-code 1 --python assets/cue/CuePieces.py -- <pid>`
  (`--no-preview` once settled), then `python3 tools/cue_pieces_glb.py <pid>`. Add a small
  envelope assert in the builder (sample the radius every 0.1 stud against
  `cc.Envelope(cc.load_shape()[0])`) so a bad body never exports.
- **Tip:** ends exactly at the pivot (Y = 0); at most 0.12 studs across for the first 0.3 studs
  (the ball's radius is 0.18), so the tip still reads on the ball.
- **Envelope** (`Shape.json`, `CueShape.radiusAt`): radius 0.045 at the tip, 0.36 across at the
  butt. In the hand zones (bridge 0.3 to 2.1 studs from the tip, grip 4.4 to 6.75) the
  centreline stays within ±0.02 of the axis and the radius within ±0.02 of the envelope.
  Anywhere up to 6.75: at most envelope +0.08 sideways and downward (the rail clearance uses
  the envelope, not the body); upward (+Z) between 2.1 and 4.4 up to 0.25 (leaves, rings);
  from 6.75 to the butt up to envelope +0.2 (the bulb, the pumpkin). Nothing on −Z that would
  sink into the torso on a back. Check the grip hand at the butt shapes in Studio (long
  wind-up, steep shot).
- **Past the butt:** at most 0.3 studs for any part that does not fade in the aim view. A joint
  with `"Aim": "fade"` may reach further, capped at `Bodies.MaxOverhangStuds` (1.5).
- **Decorations on +Z:** up in the hands, away from the body on the back.
- **Budget:** your two bodies aim for at most 6 MeshParts and 6,000 triangles each (Epic and
  Legendary; the hard limit is 8 and 10,000), Material + Color or Neon, no texture maps unless
  the lab proves one needed (then one set, 512 px at most); Jack's pocket piece at most 8 parts
  and 10,000 triangles. Per cue: 2 model uploads, 1 thumbnail, its sprites.
- **Motion:** body joints only animate decor (leaves, charms, stripes, faces); at least two
  movements at two periods for Epic, three at three periods (about 1.6 / 2.6 / 4 s) for
  Legendary and up (TECHNIQUES §6).

### 2.7 Candy Corn Cue (skin `candy_corn`, `CandyCornCue`, Epic, track 150)

- **Body `candy_corn`:** kernel tip cap (white point, orange, yellow) ending in a thin
  orange collar near 0.3; glossy cream-white shaft (`#FFF4E2`, SmoothPlastic, a little
  Reflectance) to the joint at 3.5; the joint's white/orange barber-pole twist wrap as its own
  part between two orange rings; orange forearm (`#FF7A12`) 3.6 to 5; yellow handle (`#FFD21E`)
  5 to the bulb, flush in the grip zone; the candy-corn bulb (yellow end, orange, white bands)
  swelling only past 6.5. Sugar glitter from sparkle glints in the aura; a small glitter map
  only if the lab shows it reads better (cut first).
- **Motion (Epic, 2+):** the stripe wrap turns slowly (Spin, about 4 s); three small 3D kernels
  orbit the joint on +Z (Spin, about 2.6 s); the kernel tip's glow pulses (Glow, about 1.6 s).
- **Aura (Epic: about 60 to 90 particles/s, 1 light, at most 1 beam, at most 1 orbiter):** a
  dim warm body haze (dark behind light), floating candy corns (a kernel sprite sheet rendered
  headless from the Blender kernel at several angles, on a Volume host along the cue, slow),
  sugar sparkles (white-hot → orange → yellow), one thin gold swirl (an Orbiter riding round
  the shaft), one warm PointLight (about 0.45, range 7). Quiet share Epic 0.5.
- **Trail (smaller than Jack's):** a gold sparkle core (`sparkles_main` or a sparkle strip in
  Wrap, gold → orange) with a thin white core; ball-riding emitters shedding tumbling kernels
  with gravity and orange, yellow and white sugar dots.
- **Finisher (about 1.0 to 1.2 s, no pocket piece: Epic):** a flash and an orange ring on the
  cloth, a gold spark fountain, 10 to 14 kernels tumbling up and falling, sprinkle rods in the
  three colours, a short glitter fall; nothing opaque low over the cloth for more than 0.3 s.
  An optional soft library "pop" sound, quiet; none if nothing fits.
- **Card:** the thumbnail with the body and its frozen aura.

### 2.8 Jack-o'-Lantern Cue (skin `jack_o_lantern`, `JackOLanternCue`, Legendary, track 500)

- **Body `jack_o_lantern`:** a dark green stem-like tip cap (`#2F5A2A`) with a brown ring;
  glossy pumpkin-orange shaft (`#FF7A1C`) with 8 shallow lengthwise ribs (grooves inward, so it
  stays in the envelope); the vine (`#3E8E3A`) spiralling along the cue: a flush raised strand
  (within ±0.02) in the hand zones, standing out (up to 0.04) between them with 4 to 6 leaves
  on +Z as their own part; dark wood collars (`#5A3A22`) at the joint with Neon orange slits
  (`#FF9A2E`); at the butt a ribbed carved pumpkin from about 6.5 to the end (plus at most 0.3
  past), its face on +Z: triangle eyes and a jagged grin as a Neon inner glow (`#FFC34D`), a
  warm PointLight inside, the curly green stem inside the past-butt limit.
- **Motion (Legendary, 3+):** leaves Sway (about 2.6 s); the face flickers like a candle (Glow
  plus an occasional Blink, irregular, about 1.3 s with a 0.37 s flutter); the slits' glow
  pulses (about 4 s). Polish only if time: the butt pumpkin chuckles (a small jaw part snaps
  three times every 8 s).
- **Aura (Legendary: about 110 to 150 particles/s, 2 to 3 lights, 1 to 2 beams, 2 orbiters),
  inside to outside:** a dark smoke body (`smoke_8x8`, deep brown/plum, LightEmission 0), flame
  wisps licking up along the cue (`energy_flame_8x8` or `fire_8x8` OneShot on a Volume host,
  white-hot → orange → red), embers rising, floating mini jack-o'-lanterns (a 4x4 flickering
  face sheet rendered headless from your pumpkin with `CuePieces.SPRITES`/`render_sprite`, or
  painted with `tools/openai_image.py`; small, slow, `LockedToPart = false` so they drift off),
  two Orbiters with flame heads, 2 to 3 flickering orange PointLights (0.45 to 0.7, range 7 to
  8). Under the Night lighting the lights matter most; never flood the floor white.
- **Trail:** a flame ribbon (gold → orange → red, Wrap) with a white-hot core, embers shed with
  gravity, a few mini jack flecks.
- **Finisher (about 1.6 to 1.8 s, pocket piece `jack_o_lantern_pocket`, Infernal's pattern):** a
  dark ring and a flash, a fire column (`fire_8x8`), the jack-o'-lantern rising out of the pocket
  (about Rise −2.4 → 0.5 → 1.1, Scale 0.75 → 1.05) wrapped in flame, its jaw on a Hinge child
  joint **laughing** (a snapping chatter of about 0.25 to 0.3 s through the middle second; the
  head wobbles slowly, Hinge about 4°, 1.6 s), the face flaring; a seed-and-ember burst; 3 to 5
  mini jacks popping out; it dissolves upward. The pocket piece: a ribbed shell with the face
  cut out, a Neon glow core showing through, the lower grin as the jaw part.
- **Laugh:** `Pocket.Sound` with a Roblox **library** laugh (an evil or pumpkin cackle, 1 to 2 s),
  Volume about 0.6, roll-off 8 to 60 studs. Find it with the Studio MCP asset search, audio
  published by Roblox first; prove it plays in a Play session in your window (`TimeLength > 0`,
  no load error in the console); write it as `"rbxassetid://<id>"` (the data tool passes such
  strings through). No usable sound → a silent finisher (cut line), never an upload.

### 2.9 Config (a block of its own after `Config.CueSkins`)

```lua
-- Halloween 2026 (lane hw-cues-a, 2026-10-28): cues drawn by their own model. A skin's Body
-- (a ReplicatedStorage.CuePieces template) replaces the shared cue mesh, which is hidden; the
-- body follows the stick's visibility and camera fade (never AuraOff, Lower effects or the
-- quiet share), wears the outline and skips the ink ribbons. A missing body template draws
-- the shared mesh in the skin's maps (Classic's) instead.
Config.CueSkins.Bodies = {
	Enabled = true, -- false: every body cue draws the shared mesh (switch; true only once verified)
	Outline = true, -- false: body cues wear no outline Highlight (cut switch)
	MaxParts = 8, -- a body's MeshParts, hard limit (tests/cue_body_test.luau; A's own aim at 6)
	MaxOverhangStuds = 1.5, -- an Aim-fade joint's reach past the butt, cap (tests)
	AimFadeSeconds = 0.25, -- an Aim-fade joint eases to clear and back over this (tune)
	PastButtStuds = 0.3, -- how far a body may reach past the butt (tests)
	TipSlackStuds = 0.01, -- a body must reach this close to the pivot (tests)
}
```

The hard triangle stop lives in the data tool, which reads piece.json: 10,000 a body, 10,000
an aura piece, 20,000 a pocket piece (2.2; the same limits as Cues B's brief 2.2, so the tool
never refuses B's pocket pieces). Your own aim of 6,000 a body and 10,000 for Jack's pocket
piece (2.6) is a modelling target, not a tool limit. No other new numbers: the track
thresholds and Candy belong to core.

### 2.10 Analytics

`Funnel.event(player, "HalloweenCueEquipped", 1, cueId)` in `Items.luau` `HANDLERS.EquipCue`
(282) when `Catalog.get(cueId).Event == "Halloween2026"` (field values: the five ids). It
measures how many earners actually wear each cue (core logs the grants). Verify the line in
Funnel's Studio log.

### 2.11 Edge cases

- Raised over a rail (AuraOff): the body stays, the aura goes. Camera close while aiming: the
  body fades with the mesh. Cue swap to the next shooter: no frame of the previous body
  (`applyVisible`'s `current` check, 954; `CueAssets.holdLooks` warms the next).
- Back: the pumpkin and the bulb must not sink into the legs while walking or sitting; check a
  default R15 and a tall avatar. Others' sticks and spectators (`Hub`) show the body.
- Lower effects: the body intact, the aura thins with Quality, the finisher keeps its flash and
  piece. Quiet in the shooter's hands: aura only.
- Body template missing, or `Bodies.Enabled = false`: the fail-safe above. An event cue not
  ready: hidden from the Index; core holds its grant until it is ready; if owned anyway (a dev
  `/givecue`) it draws as Classic (StandIn).
- An old server meets a new id: it resets the equipped cue to Classic (`SaveSchema.luau:1316`),
  inventory kept, so the coordinator restarts outdated servers at publish.
- Highlights stay under `MaxShown` 14 (one outline per body cue). The pocket piece is cloned
  per finisher and destroyed after it.
- Never `if cueId == ...` in runtime code: every new behaviour is a data kind any cue can use.

## 3. Interfaces

### 3.1 Drop 1, by 08:15 (PLAN §5: ids valid from the first merge)

The five Catalog rows with `eventCue`, `Catalog.ready`, the `ofRarity` hiding, `Catalog.drawAs`
and its call in `paintStick`, the five Strings names, the test updates (`catalog_test` counts:
`list()` has 7 Exclusive, `ofRarity("Exclusive")` 2 plus the ready ones; `cue_mesh_test`: an
event cue may be unbuilt, a built one has a `Body`, a non-empty `Thumb` and a `Look`). Lint and tests green; a quick check in your window (give and equip `CandyCornCue`: a
Classic stick, the Index unchanged, console clean); push; in the lane file Status
`READY drop 1 @ <sha>` and in Requests `MERGE drop 1`.

### 3.2 Drop 2, by 08:45: tooling

The data tool keys (2.2), the builder filter (2.3), and in `assets/cue/CuePieces.py` guarded
imports of both Halloween builder files at 1117-1120 and 1198-1200
(`try: import CuePiecesHalloween_A ... except ImportError: pass`, the same for `_B`), so neither
cue lane edits `CuePieces.py` again; a valid `CuePiecesHalloween_A.py`. Request `MERGE drop 2`
(tooling only, no runtime change). Cues B generates rows only after it has this.

### 3.3 Drop 3, by 10:00: the body path

2.4 complete, its tests, the path checks of §4.3 passed with both of your bodies (the ONLY
build, hands, raised over a rail, camera fade, the back, the next shooter's swap, Lower effects
keeping the body, console clean; from a local non-draft copy, 2.2; the rest of §4.3 runs as
each cue completes), `Bodies.Enabled = true`. Request `MERGE NOW drop 3: Cues B needs it for
gate 2 at 11:00` (the coordinator merges it about 10:00-10:20). CuePreview.py's body
thumbnails (2.5) follow by 12:00 in their own commit with `MERGE CuePreview bodies`.

### 3.4 The hand-off format for Cues B (Cues B reads this section)

- **Names:** skin ids `black_cat`, `spider`, `witch_broom`; catalog ids `BlackCatCue`,
  `SpiderCue`, `WitchBroomCue`; pieces `<sid>` (the body), `<sid>_pocket` (the finisher
  piece), optionally `<sid>_aura` (aura-only decor that hides with the aura).
- **B's files** (in `~/Desktop/8ball-hw-cues-b`): builders in
  `assets/cue/CuePiecesHalloween_B.py`; `assets/cue/pieces/<pid>/piece.json`,
  `<pid>_parts.glb`, `preview.png` (plus a skinned part's own GLB); `assets/cue/skins/<sid>.json`
  with `catalog_id`, `name` (= the Strings name), `tier` (Mythic, Mythic, Secret), `body`,
  `"maps_from": "classic"`, `look`, optional `piece`, `vfx` (Aura, Style, Trail, Pocket with a
  library `Pocket.Sound`), and `"draft": true` until B's own gate passes; sprites in
  `assets/cue/vfx/<sid>/`; the card in `assets/cue/thumbs/<sid>.png`. The modelling rules of 2.6
  and the `"Aim": "fade"` joint key of 2.4 apply.
- **Uploads:** Cues B uploads its own files into `tools/upload_manifest.json` (its brief 2.10,
  "Uploads, merges and generated files"). The manifest is a shared file (PLAN §7): Cues A, Cues
  B, core (the tile icon) and the GUI lane (the chip icon) all add rows through the default
  `--manifest`. On any merge conflict there, yours included, take the union the way B's 2.10
  says (`git show :2:` and `:3:` into your scratch folder, merge the dicts in Python, an `"ok"`
  row wins, never a row dropped, write it back with `indent=2, sort_keys=True`, check it parses,
  `git add`); on a conflict in the generated `src/shared/CueSkins/*`, take either side and
  re-run `python3 tools/cue_skins_data.py`, never fix it by hand. You are
  its backup uploader: when B adds `UPLOAD for A (<HH:MM>): <paths under assets/cue/>` to its
  lane file Requests (its key or window failed), answer within 30 minutes. Read
  `~/Desktop/8ball-hw-cues-b/docs/halloween/lanes/hw-cues-b.md` from disk at every Progress step
  and at least every 30 minutes; dry-run, then `python3 tools/roblox_upload.py --list <a list
  of B's absolute paths> --group-id 675425213` in your worktree (the manifest keys are B's
  absolute paths; `asset_id` matches by the path inside `assets/cue`), resolve image ids with
  `tools/manifest_image_ids.py emit` → your window (Edit) → `apply`, commit and push the
  manifest ("Uploads for Cues B: ..."), and write in your Status `UPLOADED for B (<HH:MM>):
  <path> = <id>, ...`; B then generates with `--also-manifest
  ~/Desktop/8ball-hw-cues-a/tools/upload_manifest.json`. A changed file: delete its manifest
  entry with a one-line Python edit, then upload again; never type ids by hand.
- **Rows and templates on B's side:** B runs `python3 tools/cue_skins_data.py` and, once
  drops 2 and 3 are in `halloween` and merged into its branch, builds its own templates in its
  own window with
  `ONLY = { "<its ids>" }` (a tool run, not a code edit). Before that, B checks its models in
  headless Blender previews.
- **Your side:** after each coordinator merge that brings B's rows into `halloween`, merge it
  and build all five in your window (`ONLY` = the five ids) to test the path on B's shapes (the
  Broom's crooked handle in the hands, the Spider's blades with `Aim` and the camera fade,
  the Cat's tail on the back). A path bug is yours to fix; B asks for code changes through its
  Requests and you answer in your Status.

### 3.5 What you consume (guarded)

- **Cues B's files:** none needed for your cues; their ids are valid and hidden until ready, so
  a late or cut B cue never breaks anything.
- **Map's Night lighting** (`Lighting.Night`): check both cues under it once it is in
  `halloween`; until then check day and Sunset and say so.
- **Core** consumes `Catalog.ready` (the fixed contract of 2.1: it grants a track cue only when
  `ready` is true, holds it otherwise and retries on load and every tick) and the cards; the
  **GUI lane's** Cue Preview consumes the path through `CueSkinLook.attach` and
  `Effects.styleOfCue`. You consume nothing from them.

### 3.6 Requests to the coordinator (write each in the lane file when it is due)

1. Merge on request (the coordinator merges on request from 08:45): drop 1 in the 08:15-08:30
   interface merge, drop 2 about 08:45, drop 3 about 10:00-10:20, the CuePreview.py body
   support by 12:00, then each cue as it leaves draft.
2. After merging both cue lanes: run `python3 tools/cue_skins_data.py` in the `halloween`
   checkout and commit. Merge rules for the two generated/shared files: on a
   `tools/upload_manifest.json` conflict take the union (an `"ok"` row wins, keys sorted,
   `indent=2, sort_keys=True`; never drop a row; Cues B's brief 2.10 has the steps); on a
   `src/shared/CueSkins/*` conflict re-run `python3 tools/cue_skins_data.py`, never fix it by
   hand.
3. In the Team Create place, Edit mode, once all five are final: `tools/build_cue_templates.luau`
   with `ONLY = { "CandyCornCue", "JackOLanternCue", "BlackCatCue", "SpiderCue",
   "WitchBroomCue" }` and `ALL = false`; expect "5 skins, N pieces rebuilt, 60 other templates
   untouched"; then the lab check. Without this run the five show as Classic sticks with auras.
4. Publish with "restart outdated servers" (the old-server reset above).

## 4. Checks

**4.1 Lune tests** (`tools/test.sh`):

- `tests/catalog_test.luau`: the new counts; every event row has Group and Rarity "Exclusive",
  `Tradable` and `Sellable` false, `Event = "Halloween2026"`, `StandIn = "Classic"` and the
  Effect of PLAN §3 (Epic, Legendary, Mythic, Mythic, Secret); `ready`, the `ofRarity` hiding
  and `drawAs` (own, stand-in, none).
- `tests/cue_mesh_test.luau`: event cues may be unbuilt; a built event skin has `Body`, a
  non-empty `Thumb` and a `Look`.
- New `tests/cue_body_test.luau`: every Index `Body` has a piece row with Frame "cue" and at
  most `Bodies.MaxParts` parts; no body joint is `Aura` or `Low = "hide"`; a part reaches the
  tip (front within `TipSlackStuds` of the pivot) and no part ends more than `PastButtStuds`
  past the butt (in the mesh frame Z = 3.5 − AtStuds), `Aim` joints excepted up to
  `MaxOverhangStuds`;
  `CueSkins.bodyOf` (no body, switch off, template missing, present); `Motion.rig` keeps
  `Aim`.
- The data tool: the budget stop works; a plain regenerate leaves shipped rows unchanged.

**4.2 Lint:** `tools/lint.sh` green; `tools/format.sh` only on files you changed.

**4.3 Studio, your window only** (list the studios, pick `lane-hw-cues-a.rbxl` by name every
session; Rojo 34884 connected; at the start note the template and piece counts in Edit mode):

- Edit: the ONLY build report, other templates untouched.
- Play, `tools/vfx_lab.luau` with `IDS = { "CandyCornCue", "JackOLanternCue", "EclipseCue",
  "BetaCue", "FireworkCue", "InfernalCue", "BloodMoonCue" }` (the bar and both rungs below):
  back, stand and front captures; give emitters a couple of seconds.
- In a solo or PC match (`/givecue` through `DevCommandsQA`, equip from My Cues): the tip on the
  ball, the bridge and grip hands outside the decor (long wind-up, a steep shot), the cue raised
  over a rail (body stays, aura off), the camera close (fade), the trail over the felt, the
  pocket finisher and a scratch, the next shooter's swap; walk with it on your back; the YOU GOT
  scene; Lower effects on; the Index card and detail; the power-bar cue. Others' view: the
  lab's back avatar, plus a Hub-drawn stick if you can set one up (say if not).
- Console clean (no CueSkinLook, CuePiece or CueAssets warnings). After Map's Night lands,
  repeat the lab under Night.

**4.4 Devices:** `tools/halloween/studio_size.sh lane-hw-cues-a.rbxl <w> <h>`, then read
`workspace.CurrentCamera.ViewportSize` through MCP and adjust until it is 844×390 (phone),
1024×768 (iPad), 1920×1080 (PC), and 1920×1080 with `GuiQA:Invoke("padMode", true)` (TV).
Screens: the Index Exclusive row and detail with the new cards, My Cues detail, the power-bar
cue in a match, the YOU GOT scene. If the helper fails (macOS permission), say so in the lane
file and rely on the coordinator's sweep.

**4.5 Fresh-player run** (the Catalog rows touch inventory, the Index and save checks): join,
tutorial or skip, first match, the popups, console clean; after drop 1 and on the final build.

**4.6 Screenshots** to `~/Desktop/8ball-refs/halloween/shots/hw-cues-a/` named
`NN-<what>.png` (`07-jack-back-night.png`); gate shots in `gate1/` and `gate2/`.

## 5. Cut order (first to go; a cut is switched off or removed, never half-visible)

1. Jack's chuckling butt pumpkin (polish).
2. Building B's cues in your window (B tests in its own; note it).
3. Candy Corn's glitter map (the sparkle glints carry it).
4. The aura in the card art (`--noaura`) if it reads badly at phone size.
5. The analytics event.
6. Jack's laugh sound (a silent finisher) if no library sound loads reliably.
7. Jack's moving jaw (the pumpkin rises and flares with a closed grin; the joint's motion
   removed, never a frozen half-open jaw).
8. Body outlines (`Bodies.Outline = false`) if the Highlight misbehaves on bodies.

Never cut: drop 1, the body path (it fails safe), both bodies, the cards, Candy Corn complete,
B's uploads. If the path fails its Studio checks by 12:00, tell the coordinator at once in
Requests (`BLOCKER`): the event cues cannot ship as Classic sticks.

## 6. Gates (shots in `gate1/` or `gate2/`, one line per image in the lane file's Gate shots)

- **09:00:** both bodies as headless Blender previews beside the concept (side and three
  quarter); the drop 1 and drop 2 shas. The uploads and skin JSONs come after this gate, so no
  in-window shots are due here (for this lane, PLAN §8's "Candy Corn + Jack in Studio" is met by
  the headless previews).
- **11:00:** Candy Corn complete (lab back/stand/front beside Eclipse, Beta, Firework and Blood
  Moon; in the hands; the trail; the finisher); Jack's body through the path in the hands and
  on the back (its aura, trail and finisher come after this gate); the path proofs (raised over
  a rail, camera fade, walking with it on the back); one of B's bodies through the path in your
  window if its rows are in `halloween`.

Justin's changes at a gate go straight into the work and into the lane file's Status.

## Progress

- [x] 1. Drop 1 (by 08:15): after section 0 and a look at your window (templates and pieces
  counted), the five Catalog rows (`eventCue`, Effects, `StandIn`, `Event`, `Catalog.ready`, the
  `ofRarity` hiding, `drawAs` in `paintStick`), the five Strings names, tests; lint, tests, a
  Studio check and a fresh-player run; push; `READY drop 1` and `MERGE drop 1` in the lane file.
- [x] 2. Drop 2 (by 08:45): the data tool keys and `--also-manifest` and budget stop, the builder
  `ONLY`/`ALL` filter with `row.Body`, the guarded Halloween imports in `CuePieces.py`, a valid
  `CuePiecesHalloween_A.py`; the ONLY run proven in your window; push; `MERGE drop 2` (the
  coordinator merges it about 08:45).
- [x] 3. Candy Corn and Jack bodies modelled in `CuePiecesHalloween_A.py` with the envelope
  assert, GLBs, headless previews beside the concepts (side and three quarter). No uploads yet.
- [x] 4. Gate 1 shots and lines (09:00): the headless previews, the drop 1 and drop 2 shas.
- [x] 5. After gate 1 (Justin's gate 1 changes in first): both bodies uploaded (dry-run first),
  image ids resolved, skin JSONs (`"draft": true`) with `body`, `maps_from`, `look`.
- [x] 6. Drop 3 (by 10:00): `CueSkins.bodyOf`, the CueStickBuilder hide, the CueSkinLook body
  (visibility, own-distance fade, outline, no ink, clear/destroy), the `Aim` joint key (Cues
  B's request), CueAssets warm, `cue_body_test`; the §4.3 path checks with both bodies (3.3,
  from a local non-draft copy); `Bodies.Enabled = true`; push; `MERGE NOW drop 3`.
- [x] 7. Candy Corn complete: motion, aura and its kernel sprites, trail, finisher (it stays
  draft until its card, line 12); lab beside Eclipse, Beta, Firework and Blood Moon; a match
  (hands, trail, pocket).
- [x] 8. Gate 2 shots and lines (11:00).
- [x] 9. Body support in `CuePreview.py --thumb` (2.5) by 12:00, its own commit, pushed;
  `MERGE CuePreview bodies` in Requests and a Status line for Cues B (it needs this for its
  cards).
- [x] 10. Jack: aura (smoke, flames, embers, mini jacks, orbiters, lights), face flicker, leaves
  sway, slit pulse; lab and hands.
- [x] 11. Jack: trail and finisher (`jack_o_lantern_pocket` with the laughing jaw, fire column,
  seeds and embers, mini jacks), the library laugh proven to load; checked in a match.
- [x] 12. Both cards rendered with the body and their final aura (`cue_skin.py <sid> --thumb`)
  and uploaded; both skins out of draft (2.2: the generator runs clean without
  `--allow-missing`; this is what lets core grant them); checked in the Index, My Cues and the
  power bar; push; a merge Request per cue. If line 11 is not done by 14:00, do Candy Corn's
  card and take it out of draft alone first, so it ships.
- [ ] 13. Every Cues B request answered within 30 minutes (backup uploads, path fixes), in your
  Status (the last by 15:00).
- [ ] 14. Integration: after B's rows reach `halloween`, merge it (manifest and CueSkins
  conflicts by the 3.4 rules), build all five with ONLY in your window, check the path on the
  Broom, Spider and Cat (hands, back, fade, `Aim`); fix or answer each problem.
- [x] 15. Lower effects, quiet in the hands and the Night lighting for both cues; their cost
  (parts, emitters, particles a second, lights) beside Eclipse's in the lane file.
- [x] 16. Analytics: `HalloweenCueEquipped` in `Items.luau`, seen in the Studio log.
- [x] 17. Devices: Index row and detail, My Cues, power bar and YOU GOT at phone, iPad, PC and
  TV (pad), shots. BLOCKED for phone and iPad: the window resize helper sees no Studio window from this shell (PC and TV done, lane file 10:50).
- [ ] 18. Fresh-player run on the final build, console clean.
- [ ] 19. R2.1, R2.2, R2.8 and R2.9 checked row by row against the shots; coordinator Requests
  3.6 written in full (merges, the manifest/CueSkins merge rules and regenerate, the Team
  Create ONLY build, the publish note).
- [ ] 20. Lane file Status final + all screenshots.
- [ ] 21. Merge `halloween` (the 3.4 conflict rules), re-test, push.

## Notes
