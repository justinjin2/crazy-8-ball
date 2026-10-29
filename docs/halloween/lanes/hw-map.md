# Lane hw-map (W5): Map + Pumpkin King

Folder `~/Desktop/8ball-hw-map`, branch `hw-map`, Rojo 34886, Studio `place/lane-hw-map.rbxl`,
Opus 5.5 · xhigh. Brief: `docs/prompts/HW_MAP_PROMPT.md`. Contract: `docs/halloween/PLAN.md`.

Launch and restart: the command printed by `tools/halloween/lanes.sh command hw-map` (never your
own flags). Waiting for Justin (before 11:00 only):
`touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"` (not `.git/overnight-waiting`).

## Owns

From PLAN §4 (everything else is read-only to this lane; ask through Requests):

- `Config.HalloweenMap`: the Night preset settings, skybox ids, table looks by mode, the decor
  kit, the props replace-list and placements, candy-drop spawning, the King's look, throne,
  difficulty and MaxAtOnce.
- `Config.Lighting.Night` (the preset itself, same keys as Day) and the event lighting helpers in
  `src/shared/LightCycle.luau` (`LightCycle.event`, `mixStates`) and `src/client/DayCycle.luau`.
- `TableBuilder.addDecor` (`src/shared/TableBuilder.luau`).
- Event props, as `.rbxm` under `src/server/HalloweenMap/Assets/` or built by code; their Blender
  scripts and exports under `assets/halloween/map/`; the `night` light of `assets/map/gen_sky.py`.
- The King's body, head, crown, cape, throne and prompt (`src/server/HalloweenMap/KingLook.luau`,
  `src/client/HalloweenMap/`).
- `src/server/HalloweenMap/BossService.luau`, `EventMap.luau`, `CandyDrop.luau` (a copy of
  MoneyRain), `src/shared/HalloweenMap/Rules.luau`, `tests/halloween_map_test.luau`,
  `tools/halloween/hw_map_cloth_check.py`, `tools/upload_manifest_hw_map.json`.
- The BotService boss hooks (`src/server/Bots/BotService.luau` spawn/seatInfo/attributesOf/
  playBoss/BotsQA "boss", `src/server/Bots/Body.luau` animations and dress arguments,
  `src/client/People.luau` portrait icon).
- `Strings.HalloweenMap`; the Net remotes `HalloweenMapFx` and `KingChallenge`.

## Interfaces

- Switch keys core's quest fallbacks read (always booleans, false until verified):
  `Config.HalloweenMap.Enabled` (master), `Config.HalloweenMap.Boss.Enabled`,
  `Config.HalloweenMap.Candy.Enabled`; core uses `HM.Enabled and HM.Boss.Enabled` and
  `HM.Enabled and HM.Candy.Enabled`.
- No hour-cap key here: the pickup cap lives only in `Config.Halloween.Pickup.HourCap` (core),
  enforced by `CandyService.pickup(player) -> (ok, reason: "Cap" | "NotLive" | "NotLoaded" | nil)`;
  the bag-full note shows only for `"Cap"`.
- Consumed from core: `Config.Halloween.CandyIcon`, `CandyService.bossCooldown(player) -> number`
  (unix seconds, 0 if none), `bossWon`, `isLive`, `Event.state(Clock.now())`, player attribute `HwOn`.
- Attributes: `PumpkinKingReadyAt` on players (unix seconds his cooldown ends, from core's
  `bossCooldown`/`bossWon`; `Config.HalloweenMap.Boss.ReadyAttribute`); on workspace
  `HalloweenMapState` (string: "Before" | "Countdown" | "Live" | "Ended") and `HalloweenMapFlipAt`
  (server time of the last change) (`Config.HalloweenMap.StateAttribute`/`FlipAtAttribute`);
  Studio-only force: workspace `HalloweenMapForce` (a state name).
- Net: `HalloweenMapFx` (server -> clients: `{ kind = "Burst" | "Pickup" | "BagFull", ... }`),
  `KingChallenge` (client -> server, no arguments).
- `Config.HalloweenMap.Props.Budget.Lights = 6` (throne 2 + the throne King's aura 1 + 3 table Kings).

## Status
- 04:40 hw-map: **KING SIGN OVERLAP FIXED** (hw-gui QA @6d6fce11: from ~75 studs the name
  "Pumpkin King" covered "JACK-O'-LANTERN CUE"). Commit 3ce60b7c. The sign is now anchored by its
  bottom edge (SizeOffset 0, 0.5) on the KingName's centre (3.4 studs), with a clear strip of the
  name's half height plus `Config.HalloweenMap.KingSign.GapPx` (8 px) under the card. Both are in
  pixels, so the gap never closes (`AboveHeadStuds` is gone). Studio: clear at 15, 30, 75, 88 (the
  name's own MaxDistance of 90) and 135 studs (sign alone). Console clean. Shots:
  `~/Desktop/8ball-refs/halloween/shots/hw-map/king_drop_sign/fix_*.jpg`.
- 04:08 hw-map: **KING DROP SIGN built** (Justin approved the mock, plus: hidden for an owner).
  - `src/client/HalloweenMap/KingDropSign.luau` (started by MapClient with the Boss on): one
    BillboardGui on the King's stage figure (tag PumpkinKing, ThroneKing) above his name: the
    drop cue's card art (Config.UI.Halloween.Art) on a purple tile, "BEAT ME!", "5% CHANCE" and
    "JACK-O'-LANTERN CUE" (Strings.HalloweenMap.KingDrop*, the cue's name from Strings.Items.Cues).
    It goes with his figure when he leaves. Sized in studs plus a px floor; one looped tween
    on the art tile (none with Reduce Motion, paused while hidden); nothing per frame.
  - Shown only while `Rules.kingDrop()` reads Config.Halloween.KingDrop on (hw-core's; a missing
    or malformed row hides it, tested), and hidden while the player owns the cue, rechecked on
    every Items snapshot.
  - Config.HalloweenMap.KingSign (every number), `Rules.chanceText` ("5%", "2.5%"), a Lune test.
  - Studio (lane window, King's visit forced, a temporary uncommitted KingDrop row): the sign over
    him as mocked, then `/givecue JackOLanternCue` hid it at once. Console: Studio's usual lines.
    Shots: `~/Desktop/8ball-refs/halloween/shots/hw-map/king_drop_sign/` (mock_v1, wired_visit,
    wired_owned_hidden).
- 21:29 hw-map: **PITCHFORK CUE APPROVED** (Justin 21:28: "yes pitchfork is thin enough", via the
  coordinator). Merged: card aed00b8d, core's Art id f0257a2c, decision 73d60f6e. Team Create's
  template is built from 0136f90b's ids. HELD: no more Pitchfork changes unless Justin asks.
- 21:12 hw-map: **PITCHFORK CARD popped for the dark track tile** (core: at about 62x50 px the slim fork read as
  a thin red line on the purple). The round halo (`tools/thumb_pop.py`, the Sword's) sat in the
  middle and missed the fork in the corner, so the tool gained an opt-in `--rim`: a soft light
  that hugs the cue's silhouette, under it. The Pitchfork's card is re-rendered at
  `thumb_margin` 2.4 (room for the rim) and run through
  `python3 tools/thumb_pop.py pitchfork --rim 9 --rim-color FFDDBE --rim-alpha 0.85 --halo-alpha 0 --glow 1.25 --lift 0.9 --zoom 1.0`.
  Re-run it after any re-render. New card id 139633646140924, sent to core. The Sword's pop
  output is byte-identical with `--rim` at its default 0.
- 21:04 hw-map: **PITCHFORK CUE slimmed** (Justin via the coordinator 20:58: "make pitchfork skinnier
  all around including the horns and the width of the cue, it's too wide").
  - SHAFT: the whole lathe at 0.82 of the shared cue's envelope (it was ON the envelope: 0.36
    across at the butt, now 0.295), under a new named `Slim` exception to the hand rule, so the
    hands rest at most 0.032 off the grip and 0.014 off the bridge. Raised bands at 0.6 of their
    rise, the ferrule ring +0.008. Body bounding box 0.38 across (was 0.50).
  - HORNS: smaller and slimmer (reach 0.15, was 0.21; base radius 0.037, was 0.06).
  - FORK: the span is kept (2.08 across the barbs, 1.04 off the axis). Prongs 0.12 x 0.14 (were
    0.19 x 0.23); arrowheads 1.15x wide (were 1.45x) and 0.7 of that thick, so flat blades; the
    yoke at 0.75. Outer prongs spread to 0.80 (were 0.74) to hold the span. Tip flames moved to
    the new points (Side +-0.693, Up +-0.40).
  - TAIL: tube 0.04 (was 0.052), still visible from the stand and the back; tip arrowhead 0.75x.
  - Gloss and gold work unchanged (same atlas and roughness map: their ids did not change).
    3 parts / 9,440 tris; `check_body` passes. New GLB 136051344252950, new card 108749630308384.
  - LAB, same cameras as the 20:40 pass: stand Night (full and fork), back carry 7 Day and 15
    Night, hand at aim (solo game, clear). Console: only Studio's usual lines. The hands' gap
    was checked by numbers, not a close-up (the match camera overrides the capture camera).
    Before/after: `~/Desktop/8ball-refs/halloween/shots/hw-map/pitchfork/pitchfork_before_after.jpg`
    (and `blender_before_after.jpg`); R2 side-by-side: `pitchfork_vs_R2.jpg`; the 20:40 pass in `v2/`.
- 20:40 hw-map: **PITCHFORK CUE refined** (coordinator 20:4x: detail and polish before Justin sees it).
  - FORK about 20% bigger: prong centres 0.74 off the axis (were 0.62), prongs 0.19 x 0.23 with
    a rounded-square (superellipse) section so their edges catch light, arrowheads 1.45x (were
    1.2x) and longer. 2.08 across the barbs (was 1.74), 1.04 off the axis (Aim cap 1.1), still
    1.48 past the butt. The gold yoke is bevelled: two rims and a groove, then the dome.
  - GLOSS, painted in the atlas: a sheen, a near-white streak with a thinner one each side, and a
    rim light underneath. The gold and black bands are bevelled (a dark edge, then a bright line
    just inside), with dark-red hairlines at the band edges. The tail's shadow is painted on the
    shaft round the coil. The swatches have rim lights (a red rim on the black horns). A 64x256
    roughness map (red 0.22, black 0.26, gold 0.34): in an Edit A/B the sun draws a crisper white
    line with it (`roughness_ab_edit.jpg`). No Reflectance.
  - TAIL: tube 0.052 (was 0.036), riding higher on top; the coil ends at 3.62 and the tip lifts
    0.035 to a 0.9x arrowhead laid nearly flat (the up rule's 45-degree cone: tipped more, its
    lower barb reads as "sideways"). 3 parts / 9,440 tris; `check_body` passes, hand zones flush.
    The tip flames moved to the new points.
  - LAB (lane window, Play): stand Night (fork close and full), back carry 7 studs Day and 15
    Night, hand at aim in a solo game (clear: the fork fades, shaft glossy), finisher Day.
    Console: only Studio's DataStore/MemoryStore lines and an avatar asset "being generated"
    (114949053813201, not in src, the manifest or the place). Shots and the R2 side-by-side:
    `~/Desktop/8ball-refs/halloween/shots/hw-map/pitchfork/pitchfork_vs_R2.jpg` (first build's in `v1/`).
  - CARD re-rendered (`thumb_margin` 2.2: the bigger fork met the edge at 1.75): new image id
    109608018268838 (was 121098110131668). I sent it only to the coordinator, not to core; core
    took it from the merged skin's Thumb and pointed `Art.PitchforkCue` at it (hw-core a45d8c6e).
- 20:22 hw-map: **PITCHFORK CUE built and labbed** (coordinator 19:40, concept R2; never "devil").
  `assets/cue/CuePiecesHalloween_Pitchfork.py`, `skins/pitchfork.json`, `pieces/pitchfork`,
  `vfx/pitchfork`, `thumbs/pitchfork.png`. Core's rows merged (Legendary, track 500); core set
  `Art.PitchforkCue` to my card id 121098110131668 (hw-core 8317597d).
  - BODY: 3 parts / 8,442 tris on one painted 256x1024 atlas (a 512 atlas's pixels): candy-apple
    red with a painted gloss, cream tip, gold ferrule; the horn collar (gold, black, gold) with two
    broad curved black horns; a red tail coiling 1.75 loose turns from under the collar to 3.8,
    its arrowhead tip lifting off the top on a swaying joint; a gold-black-gold band at 4.2-4.4;
    a painted black band on the grip; a black butt cap with a gold ring; past the butt on an
    Aim-fade joint the pitchfork: a gold yoke, three thick red prongs (0.16 x 0.19), the outer
    ones in a round U, R2's barbed arrowheads with rounded points. 1.48 past the butt, 1.74
    across the barbs (prong centres 1.24 apart), 0.87 off the axis (AimRadius 1.1: no exception
    needed). `check_body` passes; hand zones flush.
  - VFX, all opaque painted (`vfx/pitchfork/flame_4x4.png`: red, dark-red rim, warmer core,
    orange only on each tongue's top third): flames rising off the three arrowhead points and a
    few sparks (aura 29/s); the trail is a row of those flames plus sparks, no ribbon (79/s while
    the ball moves); the finisher is a red flash and rings, a column of flame, a ring of flame,
    gold sparkles and sparks, and a library fire whoosh (Pro Sound Effects "Fire Whoosh 13").
  - LAB at (-80, 0, 68), Night and Day: stand, back carry at 7 and 15 studs (reads as a
    pitchfork at 15), hand at aim in a solo game (the fork and its flames clear for the owner),
    the finisher at table 4's side pocket, the trail on a moving test ball. Console clean.
- 19:50 hw-map: **BONE CUE PARKED, PITCHFORK CUE started** (coordinator 19:40: Justin picked the
  Pitchfork for the 500 slot). The Bone WIP is committed as parked (5450b579), origin/halloween
  is merged with halloween's side for every Track, Catalog, Strings and Art row (10d228f9), and
  the Bone is off the track: a draft skin, no generated rows (3e785650). Nothing of the Bone
  goes live. The opt-in `Smooth` part key in `cue_pieces_glb.py` is approved (856430e4).
  Lint clean, 1,477 tests pass. Next: the Pitchfork builder (`CuePiecesHalloween_Pitchfork.py`).
- 19:27 hw-map: **BONE CUE rework per the 19:05 review**, and the flame colour made one switch
  (coordinator 19:2x: the Bone is a candidate for the 500 slot, Ghost out; green C7 or red R3).
  Captures (Blender, the lab's views): `shots/hw-map/bone/blender2_skull.png`,
  `blender2_body.png`, `blender2_pocket.png`.
  - SKULL: the Meshy skull is gone. It is now a clean cartoon skull modelled from a distance
    function and meshed by OpenVDB in headless Blender: a smooth round cranium, big round
    sockets with Neon eyes, a small nose hole, a wide grin with 13 chunky teeth. Painted by a
    bake from the fine mesh: zone colours plus ambient occlusion in one warm-ivory map. The face
    looks three ways at once (up/out for the back view, -X for the stand side, a little past
    the butt as in C7) and the crown leans to the tip, so the cue enters the back of the head
    (C7 and R3). Body: 3 parts / 8,006 tris, `check_body` passes, reaches 1.14 past the butt.
  - SPINE: four knobby cartoon bones between the hands (wide two-lobed knuckles, a waist), a
    bronze ring between the middle two and at both ends; the tall spines dropped. The grip is
    two long smooth bones with a flush ring (the hand rule allows only +-0.02). Painted
    occlusion in the hollows, hairline cracks, a bronze collar under the skull.
  - FINISHER: the same skull split at the grin (a real jaw part on a chattering hinge), six
    3D bones and two mini skulls; Lower effects hides three bones and the minis.
    13 parts / 9,200 tris.
  - PALETTE: `PALETTE = 'green' | 'red'` in `CuePiecesHalloween_Bone.py`. The build writes
    every flame, spark, smoke, light, ring, trail and outline colour into `skins/bone.json`
    (red = R3's swatches); the eyes follow it.
  - Lab uploads only (no card, nothing final): new maps and meshes uploaded, ids filled, data
    tool clean. The Meshy model and its maps were deleted (unused); their manifest rows were
    dropped. Next: the lab in Night and Day (stand, back, hand at aim) side by side with C7.
- 19:06 hw-map: **BONE CUE in progress** (coordinator 18:45/18:50/19:08). Concept
  `mocks/v2/C7_bone.png` approved (no ghosts). Built in my own files
  (`assets/cue/CuePiecesHalloween_Bone.py`, `skins/bone.json`, `pieces/bone*`, `vfx/bone/`):
  a Meshy skull (`models/bone_skull`, 35 credits) on the butt, real 3D vertebrae between the
  hands, the grip carved flush, a neck vertebra, Neon green eyes; body 4 parts / 8,692 tris,
  passes `check_body`; the pocket piece is the skull (skinned chattering jaw) with six 3D bones
  and two mini skulls whirling round it (9 parts / 11,496 tris). Uploaded to the group,
  image ids filled, `cue_skins_data.py bone` clean. Slot swap done locally (Catalog, track
  2,000, Strings, Art, four tests, BlackCatCue rows/files/builder block/sprites out, as Cues A
  asked), not committed yet. Lab (Night light, `shots/hw-map/bone/`): first pass read pale
  lavender (cream + 0.06 reflectance under the violet Night; maps also loaded late) and the
  skull's inner edges inked green: fixed (tan ivory, no reflectance, skull Outline off, skull
  turned face-up as on M3), re-lab next. Flat bone/skull cards removed (19:08 rule).
- 18:40 hw-map: **READY night sky @9e8cbcf5: NIGHT SKY AND MOON** (coordinator 18:45, Justin's
  verdict: night "too dull", the moon "looks like a sun"). Shots in `~/Desktop/8ball-refs/halloween/shots/hw-map/night2/`:
  `before_lobby_moon.jpg` vs `after_lobby_moon.jpg` (same lobby camera), `after_moon_view.jpg`
  (the moon over the tables), `after_moon_view_hud.jpg` (HUD on the new sky).
  - The "sun" was the painting, not Roblox: the old night faces had a cream disc inside three
    big pale glow lobes (one 60% white over a wide cone), which is what bloomed behind the
    avatar. Roblox's own sun/moon are off (SunAngularSize/MoonAngularSize 0, Glare 0) and
    Bloom's threshold 2.6 does not reach the sky.
  - New night faces (gen_sky.py, headless Blender, uploaded to the group, image ids in
    `Config.Lighting.Night.Sky`): a deep indigo zenith to a magenta-violet horizon, deeper sea
    and violet clouds, and the moon is now a real full-moon crater photo
    (`assets/map/textures/moon_disc.png`, made with openai_image.py, cut to a disc) projected
    onto the sky at 6 degrees radius (was 3.6), cool grey, only a faint violet halo.
  - Kept painted, not `Sky.MoonTextureId` (Roblox's moon sits opposite the sun, and the Night
    holds Sunset's sun; it draws additively so the dark seas go see-through) and not a far
    billboard (cut by low graphics levels' draw distance; costs instances).
  - Light: Exposure 0.45 to 0.3 (0.45 washed the sky to lilac), Brightness 3 to 4.4 and a light
    violet OutdoorAmbient #BCA2F6 to keep the floor bright, Atmosphere #9A5CFF/#4A1A90,
    ColorCorrection Saturation 0.05 to 0.25, Tint #EADCFF. Bloom stays Sunset's (test).
  - Measured, same camera (floor L*, three patches): Day 92.6, old Night 82.5 (0.90), new
    Night 78.0 (0.84) with floor saturation 0.29 (old 0.17, Day 0.13). Tables and players read
    clearly; the HUD reads on the deeper sky. `HalloweenMap.Night.MinBrightnessShare` 0.9 to 0.8
    (Assumptions).
  - Switches: forcing Before brings back Day's sky (Bk 136510513323451) and light, forcing Live
    brings the new Night back; every Night value in Studio matches Config; both consoles clean.
    Lint OK, 1,472 tests.
  - Next: the Bone cue. Concept card `mocks/v2/C7_bone.png` posted; asked Cues A (owns
    black_cat) and Cues B (pipeline) for the swap and the recipe; skull reference for Meshy made.
- 18:07 hw-map: **ROBUSTNESS PASS** (coordinator 17:52), on halloween @cb89ebcc (merged 77026883).
  Three read-only reviews (the King server; candy and the client; props, Night and switches),
  every finding checked against the code; my own Studio checks below. Ten fixes, one commit
  each, no look changes:
  - 21c40032 the Throne switch off now stops the timed King's visits (Timed put the stage up
    anyway). Lune test; Studio: no throne in a visit window.
  - 50a47a53 CandyDrop's 1 s / 0.2 s loops and the King's 1 s visit loop warn once per failure.
  - c8b1b6d5 `Rules.kingVisits()` covers master, Boss and Throne; core's timer line uses it
    (core's f2883db2 plus its robustness READY), so a King kill switch also hides "PUMPKIN KING
    IN 14:22" and the guide. Lune test.
  - 0cb6e4b0 a King whose table moved on before he saw the result (Surrender + Decline + one
    more action in one burst, or a surrender and a disconnect) counted toward MaxAtOnce forever:
    three of them made the King unplayable on that server. Reproduced in Studio; fixed
    (`Rules.kingsPlaying`, a 10 s grace); Studio: after 3 such bursts a 4th challenge is still
    seated. Lune test.
  - 0e8543a0 matches being seated (his body still building) count toward MaxAtOnce: presses at
    the same moment could start more than 3. Lune test.
  - 4f5031fe a seat takes its visit before the body build: a visit ending in that wait credited
    the win to the next visit (an extra pay at the event's last visit).
  - 22113f90 any timed win sets PumpkinKingBeat (repeat or other-server wins kept jumping the line;
    pay was already once a visit by core's KingVisit).
  - fb003e07 CandyDrop's leave report clears Funnel's per-player log (it held the Player for the
    server's life when Funnel's leave handler ran first).
  - 79640487 the King banner and chat line only for HwOn players (not in the tutorial).
  - 510f3e37 Main starts MapClient only if it is there (no endless WaitForChild).
  Checked with nothing found: KingChallenge spam (throttle first, no arguments, every gate on
  the server), the line on leave and at his exit, pay once per visit (`ended`, the bot's
  endedEpoch, core's KingVisit), no client pickup remote (the server picks up by distance; one
  candy a tick; the hour cap bounds any exploit), payloads type-checked on the client, the
  prompt rebuilt once per throne, no per-frame server work, every part's on/off in pcall.
  Studio, my window: each switch false, one at a time (Night, Tables, Decor, Props, Throne,
  Boss, Candy, the master, Mode "Throne"): the old behaviour each time (Night off and master
  off: the plain Day sky under /day; Throne mode: the throne at the piano and a 1.0x table King),
  both consoles clean; all set back. Clock edges: Countdown -> Live at 19:00 (everything comes
  up, the Night sky; right after an Ended flap too); the event ending (Nov 3 19:00 EST) during a
  King match from the last :45 visit: looks, decor, props, candy and throne gone, the match
  finished normally, the bot left, the sky restored, clean. His exit with a line and mid-match
  was checked at 13:00. Saves: nothing of mine (KingVisit is core's SaveSchema field).
  Left as they are (cosmetic, or a look change; the designer's call): a server whose meshes take
  over 15 s keeps fallback props and decor for its life; the arrival and paid bursts throw 50
  candies on phones too (only Lower effects halves them); the King's Puff has no distance gate
  (1 part); 21 planter boxes cast shadows (the old beds did not); a winner who rejoins in the
  same visit is ordered as unpaid until he wins again (core still pays once). Lint OK,
  1,472 tests. **READY @510f3e37** (the lane file on top).
- 13:19 coordinator: `halloween` @d0b1d604 adds map 656825bf + ee17dc24 (**Boss.Mode "Timed" is ON**: the King visits the roof's middle at UTC :15 and :45 for 12 min) + 092ab2c9 (result-card pumpkin portrait) + 4ebc50cb (winners last in his line), core fa17a763 (visit reward +150 Candy / +$2,500 / +100 XP once a visit, KingVisit save mark, the King timer pill) and cues-a 95325e31 (the Jack's own signature, no ribbons). Reward fairness checked: kept. Lint OK, 1,468 tests, Team Create: :15 arrival, challenge seated, Jack lab, console clean. Merge `origin/halloween` before your next READY.
- 13:16 hw-map: **READY @4ebc50cb** (the coordinator's fairness fix, due 14:30): in Timed, a
  player who already won this visit (PumpkinKingBeat == the visit) waits behind everyone in his
  line who hasn't (`Rules.linePlace`, `lineJoin`), and is seated only while nobody in the line
  has yet to win (`Rules.lineNext`); joining, a winner hears "You beat him this visit! Others go
  first." (new `GlobalQueue.Failed.KingLinedBeaten`, 41 characters). An empty line still seats
  a winner at once (repeat wins count for the quests on a quiet server). Throne mode never
  reaches it. Lune test for the order (unpaid first in order, winners after, a busy unpaid
  player still blocks winners). Studio: as a winner with eight tables taken: #1 in line with
  the new notice (`timed/09`); a freed table seated me within a second. Lint OK, 1,467 tests.
  Gap: PumpkinKingBeat lives on the server only, so a winner who rejoins in the same visit is
  ordered as unpaid (core still pays once; a `CandyService.bossVisit(player)` read would close
  it). Seen, not mine: `rbxassetid://12661708250 ... not approved` once, not in the repo (the
  tutorial bot's borrowed avatar, most likely).
- 13:02 hw-map: **READY @092ab2c9** (the coordinator's go): the King's result card shows his
  pumpkin portrait, not the PC robot. `Ranking.teamList` carries the seat's bot icon (nil for
  every other bot) and `ResultScreen` shows it first. Studio: /king, Surrender, the card shows
  rbxassetid://85794616941921 (`timed/08`). Lint OK, 1,466 tests. ee17dc24 (Mode = "Timed")
  stays held for core's per-visit reward (a775fd51, 52c1f23c on hw-core; interface confirmed:
  BossService always passes a visitStart in Timed).
- 12:54 hw-map: **READY @6e02fb32**: the timed Pumpkin King (12:40 job). 656825bf builds it
  behind `Boss.Mode`; ee17dc24 flips Mode to "Timed" (one line: back to "Throne" brings the
  old throne back, checked); halloween @e9b90417 merged in (clean). Lint OK, 1,466 tests.
  Studio (lane window, shots in `timed/`): he arrives at :15:00 (`01` from the spawn: his name
  and banners over the middle; `02` the stage between tables 6 and 7, King 1.5x, the prompt);
  with eight 1v1 tables taken by bots a challenge joins his line (`03` "You're #1 in the King's
  line", notice "You're in the King's line. Stay close!"); freeing a table seated me from the
  line within a second (table 7); the King at the table is 1.5x, feet on the floor (lowest part
  -0.19), and the shooter's view is clear (`04`); a loss (Surrender) retries at once; the
  "You beat him! Next visit :45" line (attribute set by hand: `05`); at :27:00 he leaves (`06`:
  throne gone, piano stays, line cleared with "The King has left. Back at :15 and :45!", banner
  "The Pumpkin King has left. He returns at :45!"); :45:00 arrival puff and burst (`07`).
  KingSpawn (:15, :45), KingChallenge (Lined, Seated) and PumpkinKing (Challenge, Lost) logged.
  Console clean (Studio store lines, the known 203785492, cues-a's CuePieces note). Not
  checked: a paid win (my branch's CandyService.bossWon ignores the visit and still starts the
  old cooldown; core's bossWon(player, visitStart) and bossCooldown 0 in Timed make it right).
  The result card's robot King: fixed in 092ab2c9.
- 12:37 coordinator: `halloween` @7be001ed adds map 88e9cceb (throne builds once; Studio: 1 throne, 1 King) + 623d0051 (timed King schedule, Mode Throne), core 1361de6d (ActiveGate, pacing), sys 57bc2b91 (50 badges, v2 icons), cues-a 66af67b0 (painted Jack, Candy rework) + fec0cb91 (deterministic generator; a main-checkout regen is now clean), cues-b 0e3569b6 (Broom redo). Lint OK, 1,465 tests, Team Create play console clean. JUSTIN (12:35): the Pumpkin King becomes a timed visitor (UTC :15 and :45, 12 min, middle of the map, 1.5x size, a top timer, the King's line when tables are full, one paid win a visit: +150 Candy, +$2,500, +100 XP). Map and core build it by 15:00; Throne mode stays the fallback. Run `git fetch && git merge origin/halloween` before your next READY.
- 12:24 hw-map: **READY @88e9cceb**: the 12:16 BLOCKER fixed (c1e75749), halloween @5dae747d
  merged in (clean), lint OK, 1,462 tests. Cause as the review found: EventMap's first Live pass
  waited on the meshes in the props, BossService's addPart turned the throne on on Bootstrap's
  thread, and the resuming pass reached the new part too; both passed `built == nil`. Fix:
  `HalloweenMap.Once` (a build runs once however many ask; the second waits for it) for the
  throne and the props; an off during the wait wins over the waiting on; `turnOn` walks the
  parts as they were and `addPart` turns a late part on in its own thread (Bootstrap no longer
  waits on the meshes). Test: two ons at once build once (two without the guard), plus retry
  and error cases. Studio: three Plays into Live, one throne and one King each; a forced Ended
  left none, the piano and the props back; Live again one; on the merged tree once more one,
  console clean.
- 12:15 coordinator: `halloween` @5dae747d adds map 7fd462cc + 39815514 (night rooftop, King, drops, /king), core d7120fac (the 11:30 review fixed, the Rush chip names what runs) and gui c9f01ea6 (the boost lines restyle, VIP perks in the Soft step). The contract test is now STRICT. Lint OK, 1,460 tests, Team Create play console clean (shots/coordinator/merge_5dae747d_boost_lines.jpg). Known blocker sent to map: the throne builds twice on a server that starts during Live. Run `git fetch && git merge origin/halloween` before your next READY.
- 12:03 hw-map: **READY @39815514** (step 21): halloween @02e046e1 merged in (clean), lint OK,
  1,459 tests, Studio boot on the merged tree: Live, 16 tables with the look, 44 decor pieces,
  51 props, the throne; console clean but for the Studio store lines, the known 203785492 ones
  and `1621084` (the tutorial bot's random avatar, not in src). New since READY 7fd462cc:
  aaaffdbe and 9af68c6a (King notices fit the card, a test), 10489ad6 (`LocalSearch.isPromised`),
  b86b9142 (the designer's `/king [tier]`), lane-file updates. All 21 steps ticked.
- 11:59 hw-map: **Status final** (step 20). Everything below is on (`Config.HalloweenMap`, all
  eight switches true), follows core's Event.state and was checked in my Studio window:
  - **Night**: while Live the event light takes Day's slot of the cycle (Countdown preloads the
    sky, a flip fades over FlipSeconds, a mid-event join sees it at once); after Live, Config's
    own light. Roof brightness L* 0.91 of Day's.
  - **Tables**: orchid 1v1 (185,90,230), charcoal 2v2 (90,94,102), toxic green 3v3 (88,176,32)
    on black frames; rendered ΔE 24.6 / 28.4 / 19.9 (all ≥ 17); decor kits Orchid, Pumpkin,
    Toxic inside the body footprint; arenas get the look and the kit; all restored after.
  - **Props**: dead trees in the palms' pots, spooky planters, 6 strands, 4 cobwebs, 2 pumpkin
    clusters; 18 palms, 12 fern planters and 9 beds put away and back. Budget: 47,786 of 60,000
    triangles, 112 of 130 MeshParts, 3 of 6 lights.
  - **The Pumpkin King**: the throne at the piano spot, his own look and portrait, the prompt
    (hold E, tap, X; "Ready in m:ss" on cooldown), real King matches by tier (won, lost, left
    logged; a win pays core's Candy and starts the cooldown), the +50 CANDY burst, the
    designer's `/king [tier]`; he skips tables a local search promised.
  - **Candy**: pieces near eligible players (HwOn, the lobby), +1 on pickup to core's
    CandyService (its hour cap), animated within 160 studs (60 on Lower effects).
  - Checked on: PC in my window; the fresh-player run (tutorial, Skip, first match, the prompt
    after). Phone, iPad, TV and the pad: nothing I add depends on the screen size (step 18), so
    the four-size screenshots and the X glyph are the coordinator's sweep.
  - Shared files: the list under Shared-file changes (all landed lines with their commits).
  - Needs: Justin's gate 2 throne answer (staying at the piano spot until then, see
    Assumptions); the coordinator's device sweep. Not mine, seen while testing: `RequestLeave`
    has no server handler (cleanup list); the King's Jack-o'-Lantern Cue body piece is not in
    my window's CuePieces (cues-a's asset; drawn with the shared mesh here).
- 11:54 hw-map: step 19 done (fresh-player run, Studio, a new save each Play). Core's BootLive
  puts the clock at Live + 60 s: the join shows the Night sky, orchid tables, dead trees and
  strands (fresh `01`). In the tutorial `HwOn` is false: the King prompt exists but is off (no
  prompt UI is even made) and no candy spawns near the player. The first match is on table 2,
  orchid, balls readable (fresh `02`). Skip mid-match: `HwOn` turns true, the prompt stays off
  while seated; after the match (Surrender) it is on within 3 s and shows at the throne (fresh
  `03`, behind the result card until Continue). Console clean (Studio store lines and the known
  203785492 ones). Notes for the sweep: (a) the MCP resets CameraType after every execute_luau,
  which undid the game's own camera return after the match, and a prompt only shows in view:
  a test artifact; (b) `RequestLeave` (Hub.requestLeave) has no server handler: a dead remote,
  not mine, for the cleanup list; (c) one earlier run's Play stopped by itself about 20 s after
  its tutorial match ended on its own after Skip (HwMatch, HwCandy 77, a Mystery block; no error,
  no kick line). The same path ran clean once more; not reproduced.
- 11:54 hw-map: step 18 done as far as one window allows (aaaffdbe notices, 9af68c6a test).
  Nothing I add depends on the screen size: the prompt is Roblox's default (fixed px; tap works,
  ClickablePrompt), the queue card is a fixed 320 px with no UIScale, the +1/+50 billboards are
  sized in studs, the portrait is a square image in the gui lane's MatchHUD slot. Measured in
  Studio (TextService, FredokaOne 18 px, 300 px of text room): KingBusy 295, KingNoTable 311
  (about 17 px), KingCooldown 267, KingNotNow 286; the new test holds them to 43 characters.
  devices/ `01`-`04` as above, `05` the +1 and +50 CANDY billboards (the board clips the +50 only
  because the shot copy has AlwaysOnTop off). Left to the coordinator's sweep: the four-size
  screenshots (the resize helper is blocked) and the pad's X glyph (Roblox's prompt follows the
  real last input; GetImageForKeyCode(ButtonX) resolves to DefaultController/ButtonX@2x.png;
  GuiQA "pad" drives only our PadMode).
- 11:49 coordinator: `halloween` @64085ab2 adds core de236025 (the NEW CUE! card and end screen count in Progression.quiet) and cues-b a431419b (Witch Broom, Black Cat and Spider out of draft). cue_skins_data.py clean on halloween (66 skins, 28 pieces). Lint OK, 1,441 tests, Team Create play console clean. Map's READY 7fd462cc is next. Run `git fetch && git merge origin/halloween` before your next READY.
- 11:45 hw-map: **READY @7fd462cc** for merge pass 1: steps 1-17 (5 now too; all Studio-checked), with
  halloween @070893de merged in (clean, no conflicts). Lint OK, 1,453 tests. Step 18 (devices)
  is partly done and left for later as asked; 19-21 follow.
- 11:45 hw-map: step 5 done (7fd462cc): the CONTRACT CHANGE in one commit: the 3v3 cloth is
  (88,176,32) in Config, `tests/config_test.luau`, `tests/halloween_contract_test.luau:252` and
  `tools/halloween/hw_map_cloth_check.py` (`--raw`: 3v3's nearest ball 31.6; rendered under Night
  19.9, gate1 `12`). Studio after the merge: Tables 15 and 16 wear (88,176,32) with the Toxic
  kit while Live (gate1 `13-3v3-88-176-32-merged`), console clean (only the Studio store lines
  and the known 203785492 ContentId ones). Brief §2.4 and its Config block updated to match.
- 11:45 hw-map: step 18 so far (not ticked). aaaffdbe shortens the four King notices, so each
  fits the queue card on one line (it is min(StatusWidth 320, screen - 20) px, so the same on
  a phone). Shots at my window's size (devices/): `01` the prompt's "Ready in 11:11", `02`
  "Challenge the Pumpkin King", `03` the KingNoTable notice, `04` the King's pumpkin portrait in
  the match bar. Notes: the MCP capture leaves out AlwaysOnTop billboards (STUDIO_NOTES), so
  the prompt shots set the prompt's AlwaysOnTop off on the client; the +1/+50 billboards are
  sized in studs (TextScaled), so no screen size changes them. Left: the four sizes by Root-frame
  emulation (the resize helper is blocked: the Studio windows are on another Space), and the pad:
  the prompt is Roblox's default UI with GamepadKeyCode ButtonX, which follows the real last
  input, not GuiQA "pad" (PadMode is our UI's flag only), so the X glyph needs a real controller
  or the coordinator's sweep.
- 11:41 coordinator: **CONTRACT CHANGE: go with (88,176,32)** (the same hue at 80% lightness, ΔE 19.9, the brief's §2.4 rule). PLAN §2 Tables updated (halloween @ the PLAN commit after 8a104005). In ONE commit change Config, your tests, the cloth tool **and** `tests/halloween_contract_test.luau` line 252 (`rgb(by[3].Cloth, 88, 176, 32)`), so `halloween` stays green when it merges. Include it in your READY for the 12:00 pass.
- 11:42 coordinator: merge pass 1 is at 12:00. Post a `READY @<sha>` line (pushed, with halloween @537270fd merged in) for your Studio-checked steps through 17, and I'll merge it then. Leave the device step (18) for later; real window resizing is still blocked (the Studio windows are on another Space), so use Root-frame emulation like core and cues-a did.
- 11:36 coordinator: `halloween` @537270fd has cues-a 83e876db (drop 3 body path, CuePreview bodies, Candy Corn + Jack-o'-Lantern, Upright, analytics, Aim-fade fix), core 3c4b87aa (event menu, tile, quests, Spider, packs, art), sys c5b6b607 and gui 3438ea94 (review fixes). Lint OK, 1,436 tests, Team Create play console clean (only the known 203785492 ContentId lines), tile + 2x chip + pill +120% seen. Review of this merge is running; findings come back as Requests. Run `git fetch && git merge origin/halloween` before your next READY. Main.client still has 12 top-level locals to spare.

- 11:32 hw-map: step 17 done (f61bb19a). All eight `Config.HalloweenMap` switches are true
  (the map still follows core's Event.state: nothing before the event, all gone after). Each
  checked in Studio, Live, with only it off: master (no state attribute, the normal cycle, nothing
  up, no prompt), Night (the normal cycle's sky and exposure; all else on), Tables (today's
  cloth; the kits still on), Decor (looks, no kits), Props (the 41 palms and planters stay),
  Throne (the piano stays; no prompt), Boss (no throne either), Candy (none in a 45 s walk).
  Found: the King's prompt lives on the throne, so Throne off with Boss on would leave core's
  King quest unfinishable; a test now holds Boss on only with Throne on, and the switches say
  "switch both off together". Now: devices (18).
- 11:24 hw-map: step 16 done. **Counts** (step 14's, Studio): 47,786 triangles of 60,000, 112
  MeshParts of 130, 16 unique meshes (OVERRULED), 3 lights of 6; every event MeshPart is
  RenderFidelity Automatic (Roblox's own LOD on weak devices), touches nothing, is never
  queried and casts no shadow (103 checked). **Client, on vs off** (Play, one camera over the
  lobby, 4 s each): draw calls 445 / 504 Live vs 483 Before, scene triangles 439.5k / 491.6k vs
  467.6k: the day cycle's light moves them more than the event does; graphics mesh memory 4.2
  MB both ways; +470 instances. Frame time could not be told apart here: the lane window renders
  in the background, throttled to 15 fps both ways (RenderCPU/GPUFrameTime read 0 in Studio).
  **Low quality:** the burst, candy sparkles and the King's aura already halve or go; new
  (aa8c2804): the per-frame candy float only within `AnimateStudsLow` 60 studs with Lower
  effects (160 otherwise; it was a hardcoded 160), checked in Studio through SettingsState.
  **Server:** heartbeat time 0.098 / 0.094 ms Live vs 0.108 ms Before (one player); the map's
  loops are the 1 s state poll, the 1 s King and candy spawn ticks, and the 0.2 s pickup check
  (at most 40 candies x players, distance only); nothing per frame. Now: switches (17).
- 11:20 hw-map: step 15 done (the full flip test, Studio, switches on in the working tree only).
  Lobby, one Play session, server parts and the client's light read at each state: Before (no
  look, kit, prop, throne; the 41 Models and the piano in the map; client Day sky, exposure
  -0.05) -> Countdown (the same; the six Night faces fetched) -> Live (16 looks, 16 kits, 51
  props, the throne, 39 Models hidden; client Night sky, exposure 0.45, sun at 7.4; the King's
  prompt on once `HwOn` is set) -> Ended (all back as Before) -> Live (all on again) -> force
  cleared (core's clock keeps it Live). Boot during Live: every Play start (FlipAt 0, no fade).
  Arena (`StudioArena` 1): boots Live, its one table orchid (185,90,230) with the Orchid kit, no
  props, hides, throne, prompt or candy, client Night; Ended gives back the Blue look's cloth and
  takes the kit; Live again re-dresses it. Console clean of map lines in both (the only new line,
  asset 1668310 "not approved", is not ours: an avatar asset). Now: performance (16).
- 11:17 hw-map: step 14 done (68dbca8e meshes, ebfbe1f7 MapProps, d8d0f166 budget). While Live
  the lobby hides its 18 palms, 12 fern planters and 9 planter beds (found in the window:
  `Palm_N` x18 Models, `FernPlanter_N` x12, `PlanterBed_N` x11 of which 42 and 48 are the
  portals'; their pots `PalmPlanter_N` and collision twins stay; the piano is the throne's own
  hide). Each palm's pot grows a dead tree (scaled to the palm, leaning inward, its lanterns
  glowing); each planter becomes a dark box in its pot's place with a dressing on top (beds: two
  tombstones, two dead bushes, three jack-o'-lanterns; pots: a bush and a jack-o'-lantern); six
  strings of lights (orange, purple) hang under the pergola's front and middle beams, cobwebs in
  its four front corners, pumpkin clusters at the throne's two lanterns. Flip test: Live 51
  props and 39 hidden; Ended and Before put all 41 Models and the piano back; Live again the
  same. **Budget** (counted in Studio, Live, lobby at rest): 47,786 triangles of 60,000, 112
  MeshParts of 130, 16 unique meshes (OVERRULED below), 3 lights of 6 (throne 2, aura 1);
  first count was 159 MeshParts, fixed by merging each table's pairs into one mesh and the
  throne's small pumpkins into the one-piece mesh. Worst case on top: 40 candies (9,760 tris,
  40 MeshParts) and 3 table Kings (2,520, 9) while they last. Shots: `shots/hw-map/props/01-03`,
  `decor/04`. Now: the flip test with an arena (15).
- 11:00 hw-map: step 13 done (28fd816f meshes, fa43df20 kits). Every table wears its mode's
  kit while Live, arenas too, and loses it at the end: Orchid 1v1 (purple underglow, two glowing
  bats on the long aprons; 3 parts, 196 tris), Pumpkin 2v2 (orange underglow, trim ring under
  the rail line, bats, four small jack-o'-lanterns by the legs; 8 parts, 956 tris), Toxic 3v3
  (green underglow, trim, bats, cobwebs in two opposite corners; 6 parts, 676 tris). Studio: all
  16 tables built (74 parts), every piece passed `Rules.decorInside` (no warnings), a forced
  Ended removed every kit and look, Live again put the same 74 back, Live twice changed nothing.
  New meshes in the props GLB (re-uploaded, Model 113325392217599): PumpkinSmall (182 tris, one
  piece) and Trim. Shots: `shots/hw-map/decor/01-03`. Now: props and hides (14).
- 10:55 hw-map: step 11 done. Candy walk test (5 min, the player walked by Humanoid:MoveTo, core
  live): 4 candies spawned near the moving player, all 4 picked up by walking over them, core's
  save PickCount 4 and Earned +4 (+1 each); none while idle. About one per 30 s of eligible
  lobby time, as the brief sets (a lobby-only player reaches core's 40/hour cap; ~25/hour for a
  typical player). The lobby candy is the event mesh (`shots/hw-map/candy-lobby.jpg`).
- 10:45 hw-map: merged halloween @f32c3d1b (core's CandyService, sys's badges; lint OK, 1418
  tests). With core live in Studio (BootLive) the King's whole chain works: prompt, match, a
  staged real win -> `Won`, core's save Earned 50, KingPaid 1, KingWins 1, cooldown 15:00 on
  `PumpkinKingReadyAt` and the prompt's "Ready in 14:30". Fixes found by testing: a win never
  paid (a38b71e1), the King sat backwards (8df3864c), see-through pumpkin eyes and a floating
  crown (c88e894c), core's clock for the cooldown (a5b303ba). New: candy meshes in the lobby
  and the burst (6925d850), the King's portrait and Vampire idle (4bf19ec7). Steps 3, 4, 6-10, 12
  ticked; 5 waits on the CONTRACT CHANGE (3v3 tint). Still stand-ins in Studio: `HwOn` set by
  hand (core's client state not built yet). Now: the candy walk test, then decor kits (13).
- 09:50 hw-map: pushed ea730d46. Merged halloween @403da7da (lint OK, 1382 tests). Done since
  08:50: Rules + tests (step 2), the Night sky uploaded (6 faces), Night/LightCycle.event/
  DayCycle crossfade, EventMap and the table looks, the King end to end in code (BotService
  hooks, KingLook, BossService, taunts, reward), CandyDrop + MapFx, the event meshes (one GLB,
  Model 137550009666802; King head, crown, throne from them), the coordinator's two requests
  (Main `do...end`, Night in map_config_test). Step 9 done: difficulty table under Assumptions,
  top three rows stepped down to a Grandmaster King (OVERRULED line). **Blocked on Studio:** the
  lane window's Rojo plugin dropped again ("Disconnected from an error: WebSocket error: 400"),
  so steps 3-5, 7-8 and the gate 1 shots wait for a Connect.
- 09:22 coordinator: halloween @403da7da has cues-a drop 2 (skin keys, --also-manifest, budget stop, the builder ONLY filter, Aim joint; Firework row unchanged but a comment); lint OK, 1370 tests, Studio synced. Run `git fetch && git merge origin/halloween`. Cues B: you can generate rows now.
- 09:12 coordinator: halloween @792bbb35 has every lane's interfaces (sys 1c9f99b7, core 1c9945a0, cues-a drop 1 1039f19b, gui b2c51102, map 6d45e218); lint OK, 1370 tests, Studio boot clean. Run `git fetch && git merge origin/halloween` now. Gate 1 is at 10:00: shots + one caption line each in your Gate shots by 09:55.
- 09:12 coordinator REQUESTS: (1) wrap your Main.client block in `do ... end` (it adds 2 top-level locals; Main is near Luau's 200 limit; see the 09:05 line). (2) add "Night" to the lighting-state loop in tests/map_config_test.luau:167 so a typo'd Night sky id fails a test. Your ROJO RECONNECT: done 08:55 (Justin reconnected; Studio pid 17672 on 34886).
- 09:05 coordinator REQUEST (all lanes, blocks a merge): `src/client/Main.client.luau` is 12-14 top-level locals from Luau's 200-local limit; past it the client fails to compile in Studio and live and lint/tests stay green. Put every Main.client addition inside `do ... end` (zero new top-level locals), e.g. `do local ok, err = pcall(...) ... end`. New test `tests/client_compiles_test.luau` (on halloween @HEAD) compiles every src script and fails if Main.client has fewer than 8 locals left; run it before you push.
- 08:50 interfaces pushed (step 1, 0b5ef756): `Config.HalloweenMap` (every
  switch false; `Enabled`, `Boss.Enabled`, `Candy.Enabled`; no hour-cap key), `Config.Lighting.Night`
  (first values, Day's keys), `Strings.HalloweenMap` + 4 `GlobalQueue.Failed` keys, Net
  `HalloweenMapFx`/`KingChallenge`, Bootstrap + Main blocks (pcall-guarded) and the four modules,
  each returning at once while its switch is off. Late against 08:15 (lane started 08:43).

- 09:16 code pushed, all switches off, **Studio unchecked (no Rojo in the lane window)**:
  355ce0a8 Rules + Lune tests (step 2 done); ccb73403 Night (LightCycle.event, mixStates,
  DayCycle crossfade), EventMap switch + table looks by mode, the night sky rendered headless and
  uploaded (6 faces, ids in `Config.Lighting.Night.Sky`, `tools/upload_manifest_hw_map.json`),
  `tools/halloween/hw_map_cloth_check.py` (raw: orchid 23.2, charcoal 20.4, toxic 29.4);
  0498b301 BotService boss hooks, KingLook (code-built placeholder King and throne), BossService,
  CandyDrop, MapClient prompt + MapFx. bot_duel for the 10 TierFor rows running in the background.
  Night sky preview: `~/Desktop/8ball-refs/halloween/shots/hw-map/gate1/night-sky-cross.png`.
- 08:50 coordinator: lanes started 08:43 (73 min behind the plan). New times: interface commits as soon as they pass (target 09:30, merged by 09:45); gate 1 at 10:00 (shots + captions by 09:55); gate 2 at 11:15 with whatever is ready (Justin sleeps after it); merges on request all day; 16:00 done/cut and the 17:00 freeze stay for now (re-timed at 13:00 if needed). Rojo: a watchdog restarts any crashed server by itself (log ~/Desktop/8ball-refs/halloween/shots/coordinator/rojo-watchdog.log; Rojo 7.7 can panic on an editor temp file); if MCP shows your window no longer syncs (append a comment, read it back), write `ROJO RECONNECT` in your Requests and keep working on files. Resize helper: not yet (Studio windows were full screen; Justin is un-fullscreening them); use your layout tests until the outer sizes are posted here.
- 09:55 coordinator: `halloween` @82ab885c (+ docs f8566968) has core interface 2 (7f01d27b: Halloween save field, CandyService, /hw; switches off), sys 4cdf5620 (roam off, badges off) and gui f2562efb (boost pill ON, friend boost ON, Cue Preview core off). Lint OK, 1,404 tests, Studio play console clean, pill shows +120%. Run `git fetch && git merge origin/halloween` before your next READY. Main.client still has 12 top-level locals to spare: hooks stay inside `do ... end`.
- 09:56 coordinator: your Rojo server on 34886 is up (pid 20013, since the 08:47 watchdog restart); only the plugin dropped. Asked Justin to click Connect in lane-hw-map (terminal + notification). Until then keep going on headless work (props, decor kits, Rules tests) and queue the Studio steps. Your ea730d46 (Grandmaster King rows) is noted; I merge map once steps 3-5 are Studio-checked.

## Shared-file changes

Landed (only my own blocks unless said):
- `tools/cue_pieces_glb.py`: my opt-in `"Smooth"` part key (856430e4) is superseded by cues-b's
  identical one (the coordinator, 20:0x); hw-map took halloween's file whole (22ddeeaf), no diff left.
- `assets/cue/CuePreview.py`: two opt-in skin keys for the card picture, `thumb_margin` (studs of
  frame) and `thumb_shift` (studs toward the tip); absent = the house framing, so every other card
  renders as before (the Pitchfork's fork, thickened 1.45x with the rest, met the corner).
- `assets/cue/CuePieces.py`: a guarded `import CuePiecesHalloween_Pitchfork` beside the Bone's.
- `tools/thumb_pop.py` (cues-a's): opt-in `--rim`, `--rim-color`, `--rim-alpha`, a silhouette glow under the
  cue. With the default `--rim 0` the output is unchanged (checked byte for byte on the Sword).
- `assets/cue/CuePiecesHalloween_A.py`: a named `Slim` body exception (a factor under 1): the hand
  rule holds against that share of the envelope. Only the Pitchfork sets it (0.82); other bodies
  are unchanged.
- `tools/build_cue_templates.luau`: `dress()` applies a piece part's `RoughnessMap` when its row
  says `UseRoughness = true` (the Pitchfork's lacquer). Opt-in because Infernal's skull already
  carries Meshy roughness and metalness maps this never applied; its look stays put.
- `Config.luau`: `Config.Lighting.Night` (after Sunset), `Config.HalloweenMap` (after Lighting) — 0b5ef756, ccb73403, 0498b301.
- `Strings.luau`: `Strings.HalloweenMap` (after `Arena`); 5 keys in `GlobalQueue.Failed` (`KingBusy`,
  `KingNoTable`, `KingCooldown`, `KingNotNow`, `CandyBagFull`: the bag-full note reuses the queue
  notice) — 0b5ef756, 0498b301.
- `Net.luau`: `HalloweenMapFx`, `KingChallenge` at the end of REMOTES — 0b5ef756.
- `Bootstrap.server.luau`: one block after MoneyRain — 0b5ef756.
- `Main.client.luau`: one guarded block after `DayCycle.new()` (MapClient.start(dayCycle, hub)) — 0b5ef756, 0498b301.
- `tests/config_test.luau`, `tests/light_cycle_test.luau`: my own tests — 0b5ef756, ccb73403.
- Existing lines changed: `LightCycle.luau` (two new functions only), `DayCycle.luau` (the
  lighting source: `setLighting`, `self.lighting` instead of `L` in update, a crossfade),
  `Bots/BotService.luau` (spawn takes description/icon/animations/dress, seatInfo/attributesOf
  carry icon, `playBoss`, BotsQA "boss"), `Bots/Body.luau` (build takes animations, dress),
  `People.luau` (portrait: bot.icon / BotIcon first) — ccb73403, 0498b301.
- `TableBuilder.luau`: `addDecor` and its helpers (new functions only) — fa43df20.
- `Main.client.luau`: the MapClient block moved inside `do ... end` (coordinator) — 4c0e3895.
- `Config.luau`: the 3v3 cloth (88,176,32) — 7fd462cc; `Config.Debug.Commands.King = "/king"`
  after core's `Halloween` line — b86b9142.
- `tests/halloween_contract_test.luau:252`: the 3v3 tint, as the coordinator asked — 7fd462cc.
- `Strings.luau`: the four King notices shortened to fit the queue card — aaaffdbe;
  `KingDevStarted`, `KingDevFailed` in `Strings.HalloweenMap` — b86b9142.
- `DevCommands.luau`: the designer-only `/king [tier]` block after core's `/hw` — b86b9142.
- `LocalSearch.luau`: `isPromised(t)`, read-only (one new function) — 10489ad6.
- The timed King — 656825bf (Mode flip ee17dc24): `Config.luau` (my `Boss.Timed` lines,
  `LineAttribute`, `BeatAttribute`); `Strings.luau` (4 `GlobalQueue.Failed` keys `KingLined`,
  `KingLineLeft`, `KingLeft`, `KingAway`; `HalloweenMap.LinePlace`, `Beaten`; `Banner.KingArrived`,
  `KingLeft`); `Banner.luau` (no lane's file: one `kind == "King"` branch at the end of
  onBanner).
- `Strings.luau`: `GlobalQueue.Failed.KingLinedBeaten` — 4ebc50cb.
- `Ranking.luau` (`teamList`: one `icon` field) and `ResultScreen.luau` (makePlayer: `player.icon`
  first): the King's result-card portrait, on the coordinator's go — 092ab2c9.

Shared files (PLAN §7 plus `HubCorners.luau`, `Net.luau`, `DevCommands.luau`,
`tests/save_schema_test.luau`, `tests/config_test.luau`): only your own block or line; the
coordinator resolves overlaps. Planned (add the commit sha when each lands):

- `src/shared/Config.luau`: the `Config.HalloweenMap` block (after `Config.Lighting`) and
  `Config.Lighting.Night` (after Sunset).
- `src/shared/Strings.luau`: `Strings.HalloweenMap`; four `Strings.GlobalQueue.Failed` keys
  (`KingBusy`, `KingNoTable`, `KingCooldown`, `KingNotNow`).
- `src/shared/Net.luau`: `HalloweenMapFx` and `KingChallenge` (core and GUI add their own lines).
- `src/server/Bootstrap.server.luau`: one block after MoneyRain (EventMap, BossService, CandyDrop).
- `src/client/Main.client.luau`: one line starting MapClient.
- `src/server/DevCommands.luau`: the designer-only `/king` block (core's `/hw` block is separate).
- `tests/config_test.luau`: your own `Config.HalloweenMap` block (core and sys add theirs).
- Outside your folders (§2.1 of the brief): `LightCycle.luau`, `DayCycle.luau`, `TableBuilder.luau`
  (`addDecor`), `Bots/BotService.luau`, `Bots/Body.luau`, `People.luau`, `LocalSearch.luau`
  (`isPromised`).

## Requests

- RESOLVED 11:41 (coordinator: go with (88,176,32); done as the step 5 commit). **CONTRACT CHANGE** (10:05, updated 10:50; coordinator): the 3v3 toxic green (110,220,40)
  renders (167,243,23) at the table and sits **ΔE 16.5** from the yellow balls (1 and 9) under
  Night and Sunset alike (they read the same up close), under PLAN's 17. The brief's rule (§2.4:
  "shift that tint's lightness within its hue and re-measure") gives **(88,176,32)**: the same
  hue at 80% lightness, renders (139,219,32), **ΔE 19.9** (gate1 `12`). Recommended: it keeps
  PLAN's lime. (A greener (70,210,55) reads 23.9 but moves the hue; gate1 `08`.) It needs PLAN
  §2 Tables and `tests/halloween_contract_test.luau:214` (yours) changed: say go and I change
  Config, my tests and the cloth tool in one commit, or change the contract line yourself and I
  follow.
- RESOLVED 10:00 (Justin reconnected). **ROJO CONNECT AGAIN** (09:50): the `lane-hw-map.rbxl` window's plugin shows `[Rojo-Warn]
  Disconnected from an error: WebSocket error: 400` and has none of this branch's code. Rojo on
  34886 is up (pid 20013 since 08:47). Please click Connect to `localhost:34886` once more
  (and Accept if it asks to confirm the changes).
- RESOLVED 09:00. **ROJO RECONNECT** (08:53): the `lane-hw-map.rbxl` window has none of this branch's code (no
  `ServerScriptService.Server.HalloweenMap`, no `Config.HalloweenMap`), so its Rojo plugin is not
  on 34886 (maybe auto-connected to 34872). Please Connect it to `localhost:34886` (Rojo on
  34886 is up). Working on files meanwhile.

- Core: this lane reads `Config.Halloween.CandyIcon` and `CandyService.bossCooldown(player) ->
  number` (unix seconds, 0 if none), `bossWon`, `pickup`, `isLive`, `Event.state(Clock.now())`
  and the player attribute `HwOn`. Say if any is missing after the 08:30 merge.
- Core: please confirm the quest fallbacks read `HM.Enabled and HM.Boss.Enabled` and
  `HM.Enabled and HM.Candy.Enabled` (`HM = Config.HalloweenMap`, shipped in step 1, all false
  now), and that `pickup` returns `(ok, reason)` with `"Cap"` for the hour cap.
- hw-sys: noted your Request: the King's prompt refuses a player in a match and CandyDrop skips
  players in a match (`Tables.tableOf(p) ~= nil`); BossService calls
  `Badges.grant(p, "PumpkinSlayer", "Boss")` (guarded require + pcall).
- Coordinator: please include the step-1 interface commit in the interface merge.

## Assumptions

- King drop sign, decided here (2026-10-29): built on the client (not with the server's
  throne), because hiding it for an owner is per player; it hangs on the figure KingLook
  already tags, so leaving needs no extra code. Sized in studs plus a px floor (7 x 2.6 studs
  + 110 x 40 px): the cue line is about 14 px on a phone at 28 studs, and it grows as you walk up.
- Pitchfork Cue, decided here (2026-10-28):
  - The fork's prongs spread along (cos 150, 0, sin 150) in the cue's Blender frame. The card's
    camera looks from +X and the top, a back's from the top toward the tip, the stand's from
    -X: the card sees it face-on, a back about 90%, the stand 50%. At 30 degrees (the plan) the
    card saw it edge-on.
  - "Err bigger": spread 0.62 and arrowheads 1.2x after the first back-carry capture read slim.
    It reads as a pitchfork at 15 studs; bigger pushes the lower prong further into the legs on
    a back (its -Z reach is already about 0.43), so I stopped there.
  - "No ribbons" for the trail: `Style.Trail` stays on but draws nothing (fully clear, 0.02 wide,
    0.05 s). `Effects.attachTrail` attaches a skin's TrailEmitters only when the trail is on, and
    a data-only clear ribbon keeps the shared runtime untouched. A cleaner code fix (emitters
    without a ribbon) is core's call.
  - No pocket piece: R2's finisher is flame and sparkles, and the opaque painted particles read
    on the bright table. A 3D flame mesh can be added later if wanted.
  - Horns at 30 degrees off the top: the up rule's +0.25 is a 45-degree cone and a horn's flank
    reaches about 13 degrees more.
  - Refinement (coordinator 20:4x): the fork went from 0.87 to 1.04 off the axis, which uses most
    of the Aim cap's 1.1 and pushes the lower prong further into the legs on a back. The
    coordinator asked for it; it still reads cleanly at 7 and 15 studs.
  - Painted streaks are wide (main sigma 0.035 of the way round, sides 0.022): a hairline streak
    vanished on the floor at 7 studs.
  - Slim (Justin 20:58): 0.82 rather than the envelope with flatter bands. The shaft already
    sat on the shared envelope, and he asked for "the width of the cue". 0.82 reads as a slim
    pool cue and keeps the hands' gap to about a tenth of a hand's thickness. The fork keeps
    its span; only its parts got slimmer.
  - The tail tip's arrowhead stays nearly flat (face tipped 0.2 toward the stand side). The up
    cone leaves no room to show it face-on from the side, so from the stand it reads as a
    hooked tip and from above (back carry) as an arrowhead.

- Cue labs, 2026-10-28: the lab spot moved to (-80, 0, 68). At (-40, 0, 70) the SoloPortal's
  cyan PointLight (range 14, brightness 2) tints every cue mint (cues-a and cues-b told). Body
  cues carry no large coloured PointLight of their own: by day it dyes the body (the Bone read lime).
- Which way a body piece faces, measured on the lab: on the stand Blender -X faces the camera
  and Z is up; on a back carry Blender +Z faces the camera behind and -X and past-the-butt point
  at the floor. A butt piece is posed between the two (the Pitchfork's fork is tilted 30 degrees
  from X toward +Z).

- Night readability, 2026-10-28: Justin's richer night is a touch darker, so the floor rule is
  0.8 of Day's (was 0.9; measured 0.84). The moon stays painted into the skybox (works at every
  graphics level, no instances); it is about 150 px across at 1080p, enough for its seas and
  rays, limited by the 1024 px face.

- The throne stays at the piano spot (gate 2 option (c)) until Justin answers the gate 2 question
  (`gate2/05`): from the spawn it reads as a glow between the two lobby boards, and the prompt
  and the glow lead players there. Option (a) is a two-line change (`Throne.Pivot` z about -66
  and `PromptAt` with it), to be checked in Studio against the boards and the last table row.

- The timed King (12:40 job), decided here: his stage reuses the whole approved throne (same
  96 parts, 3 lights, no new meshes) at `Boss.Timed.Pivot` (0,0,4), the open cross between
  tables 6/7 and 10/11, front to the spawn; only the King on it is 1.5x. His line is per server
  and first come first served; someone in another match keeps their place but is skipped until
  free; 40 studs (`LineStuds`) from his prompt drops a place. `MaxAtOnce` stays 3 in Timed (not
  4: no perf numbers yet). KingSpawn is logged once per HwOn player present when he arrives
  (a = ":15"/":45"); KingChallenge a = Seated/Lined/NoTable; KingWin value = Candy paid, b =
  Paid/Free. The designer's `/king` still works while he is away.

- OVERRULED (Justin: yes, 12:16 via the coordinator): the top three TierFor rows play a Grandmaster King, not Reyes (PLAN: two ranks
  above, at most Reyes). Measured: a Reyes King left the model player 11.5% (Master), 13.5%
  (Grandmaster) and 14.0% (Reyes), all under the brief's 20% floor; stepped down one tier they
  read 26.5% / 33.0% / 36.0%, inside 25-45%. The Reyes row's King is now one tier below the
  player (the only row so).

- `TableBuilder.addDecor(model, kit?)` reads the table's frame from the model's pivot (the
  placement's own, set by `buildFromModel`), so it takes no `p`: EventMap finds tables by model,
  and an arena's table is placed the same way.
- The trim is one mesh ring (Assets `Trim`, the body footprint's size, 32 tris), not strips: four
  strips put the 2v2 kit at 11 parts, and a solid plate would show inside the pocket cups.
- The bats glow Neon in the kit's colour: the brief's black bat vanishes on the black-frame
  apron. They sit 0.022 studs proud of the apron (the footprint leaves 0.024).
- The underglow stays inside the footprint, as the brief rules: at Transparency 0.45 it reads as
  a pool of light under the table (a solid Neon plate read as a yellow slab). The 2v2 kit's
  orange is (255, 90, 10): Neon draws (255, 122, 26) nearly yellow.
- The decor goes on arena tables too (part of the table's look, like the cloth tint).

- OVERRULED (Justin: yes, 12:16 via the coordinator): `Props.Budget.UniqueMeshes` is 16, not the brief's 8. The event's 16 meshes hold
  6,900 triangles in all on one palette texture (one upload); getting to 8 would merge props
  whose places are data (trees, strings of lights, dressings) into fixed meshes. The draw cost
  the cap guards is met by the MeshParts count (112 of 130) and the shared texture.
- Spooky planters: the brief's "dark box" is a Slate Part the size and place of the hidden
  planter's pot (`__Opaque` part), shadow on, no collision (the collision twin stays); the fern
  dressing is drawn 1.39x on the 4.16 pots so it fills the top instead of sitting small.
- String lights hang only on the pergola (front and middle beams, 6 strands); none on the
  railing (it is 400 studs round; cut-order 2 anyway). Pumpkin clusters only at the throne's two
  lanterns: the spawn's tall lanterns stand at the spawn (the brief keeps the spawn clear) and
  the side lanterns sit by beds that now carry pumpkins.

### King difficulty (bot_duel, 200 games a row, `--no-write`, 2026-10-28)

| Player | King | Player wins | Note |
|---|---|---|---|
| Bronze | Gold | 44.5% | |
| Silver | Platinum | 39.5% | |
| Gold | Diamond | 33.5% | |
| Platinum | Expert | 39.5% | |
| Diamond | Veteran | 36.0% | |
| Expert | Master | 26.0% | |
| Veteran | Grandmaster | 27.5% | |
| Master | Grandmaster | 26.5% | Reyes King: 11.5% |
| Grandmaster | Grandmaster | 33.0% | Reyes King: 13.5% |
| Reyes | Grandmaster | 36.0% | Reyes King: 14.0% |

## Gate shots

Gate 1 (`~/Desktop/8ball-refs/halloween/shots/hw-map/gate1/`, Play captures, lane window):

- `01-night-spawn.jpg`: Live (Studio force), from the spawn: the Night light (purple sky,
  violet haze-free light), the 1v1 tables orchid on black frames, the throne at the aisle's end.
- `02-day-spawn.jpg`: the same camera after forcing Before: Day, blue cloths and wood frames,
  the piano back (the off path restores everything).
- `03-three-looks-night.jpg`: the table looks under Night (Live): 2v2 charcoal (left, front
  and back), 1v1 orchid (front right), 3v3 toxic green (back right), all on the black frame.
  Server check: all 16 tables carry `HalloweenLook`, cloth tints exactly 185,90,230 / 90,94,102
  / 110,220,40; forcing Before clears them and restores Blue. Note for gate 2: the lobby boards
  stand in front of the throne, which half-hides it from the spawn.
- ΔE (CIEDE2000, closest ball), raw tints: 1v1 23.2 (ball 4), 2v2 20.4 (ball 2), 3v3 29.4
  (cue ball).
- Rendered ΔE (`05`-`10`: the 16 balls in a 4x4 grid on a table of each mode, a fixed camera
  2.4 studs over the cloth, cloth and ball centres sampled with hw_map_cloth_check's medians):
  Night 1v1 **24.6** (ball 12), 2v2 **28.4** (ball 2), 3v3 **16.5 (ball 9 yellow), UNDER 17**.
  Sunset reads the same to the unit up close (the table lamps light the cloth and balls; `11`
  shows the Sunset hold took). The 3v3 tint (70,210,55) renders (95,240,47): **23.9** under both
  (`08`, `09`). See Requests: CONTRACT CHANGE.
- Brightness after tuning (`04-night-spawn-tuned.jpg` vs `02`, exposure 0.45, shade #B8A8D8):
  L* floor **0.91**, lobby band **0.93**, whole frame 0.89 (the purple sky is darker than the
  blue one by design). The roof meets the 0.9 target.
- Brightness, Night vs Day, same camera (01 vs 02): perceived lightness L* 0.81 whole frame,
  0.84 floor, 0.83 lobby band; linear luminance 0.66. **Under the 0.9 target**: step 4 tunes
  Night up (Brightness/Exposure, the purple kept).
- `night-sky-cross.png`: the Night sky's six faces (gen_sky night: moon, stars, violet
  gradient), uploaded as the six ids in `Config.Lighting.Night.Sky`.
- `12-dE-3v3-88-176-32.jpg`: the 3v3 cloth at (88,176,32), the CONTRACT CHANGE tint (the same
  hue at 80% lightness): renders (139,219,32), **19.9** from the yellow balls under Night.
- `13-3v3-88-176-32-merged.jpg`: Table 15 with that tint and the Toxic kit while Live, after
  merging halloween @070893de (7fd462cc).


Gate 2 (`~/Desktop/8ball-refs/halloween/shots/hw-map/gate2/`, Play captures, lane window, Live forced):

- `01-throne-night.jpg`: the throne at the piano spot (0, 2, -86) from its carpet: the carved
  pumpkin back (the event mesh), the crown over it, purple banners, steps, candles, four small
  carved pumpkins (meshes). The piano and its bench hidden; 98 parts, 28 meshes, 3 lights.
- `02-king-close.jpg`: the King on his throne, the real head (carved pumpkin mesh, tilted gold
  crown with purple gems), black suit, orange vest, seated, the cue as a sceptre.
  `00-king-backwards-before-fix.jpg`: he first sat facing the pumpkin (fixed, 8df3864c).
  Note: his orange head sits on the orange pumpkin back, so he reads less than he could.
- `03-king-match.jpg`: a King match at table 11 from the prompt (the real path: tutorial
  skipped, HwOn set by hand as core's server is not merged yet): Gold King vs an Unranked
  player, JackOLanternCue, Pc kind. The loss (he ran the table) logged Lost, no cooldown, and a
  second challenge right after worked (lose = retry at once).
- A staged win (PoolMatchQA finalEight, a real shot) found a bug: every win logged "Left" and
  paid nothing (the table lets the player go before the bot sees the result). Fixed
  (a38b71e1, `Rules.kingOutcome` + test); now "Won", and the reward runs to core's
  CandyService (missing here: "a King win grants nothing" warning until core merges).
- `04-candy-burst.jpg`: the candy explosion over table 11 (the real Burst remote): the event's
  wrapped candy meshes flung up, an orange pop, sparkles; "+50 CANDY" riser checked in the
  client (not in this frame: the candies were frozen 0.3 s in for the shot).
- `05-throne-from-spawn.jpg`: **gate 2 question**: from the spawn the throne is only a glow
  between the two lobby boards (Top players / Top countries) that stand in the aisle in front
  of the piano spot. Options: (a) move the throne forward of the boards (z about -66, still on
  the aisle's axis; mine, one Config line); (b) part the boards while Live (LobbyBoards, not
  mine); (c) leave it (the prompt and the glow lead players there). I suggest (a).
- Difficulty table: under Assumptions (all ten rows measured; the top three play a
  Grandmaster King).
- The PC-kind King pays a Pc match's money for balls (the staged win: +$66 for one ball), as
  PLAN chose ("Pc" so no farming). His portrait was the PC robot here; it is now his own
  (`Config.HalloweenMap.King.Icon`, devices `04`).

Decor kits (`decor/`, step 13, Live forced):

- `01-pumpkin-2v2.jpg`: the Pumpkin kit on a 2v2 table: orange underglow, the trim ring, bats,
  the small jack-o'-lanterns by the legs.
- `02-toxic-3v3-cobweb.jpg`: a low view of a 3v3 table's corner (Toxic kit): the green trim
  ring and underglow, the cobweb at a leg.
- `03-orchid-1v1.jpg`: the Orchid kit on a 1v1 table: purple underglow and the two bats.
- `04-pumpkin-2v2-merged.jpg`: the 2v2 kit after merging each table's pairs into one mesh (the
  MeshParts fix, 159 -> 112).

Props (`props/`, step 14, Live forced):

- `01-pergola-strands-webs-clusters.jpg`: the pergola's strings of lights (orange, purple), the
  cobwebs in its front corners, the pumpkin clusters at the throne's lanterns.
- `02-corner-trees-planters.jpg`: dead trees in the palms' pots and the dark planter boxes with
  their dressings.
- `03-fern-planter-from-spawn-side.jpg`: a fern planter's spooky twin (the dressing at 1.39x).

Candy (step 11): `candy-lobby.jpg`: a lobby candy, the event's wrapped candy mesh.

Devices (`devices/`, step 18, my window's size, 1523x814 viewport; captures at 1920 wide):

- `01_prompt_ready_in.jpg`: the King's prompt on cooldown, "Ready in 11:11", key E.
- `02_prompt_challenge.jpg`: the prompt when ready, "Challenge the Pumpkin King".
- `03_notice_king_no_table.jpg`: the KingNoTable notice on the queue card, one line.
- `04_king_match_portrait.jpg`: a King match: his pumpkin-and-crown portrait in the match bar.
- `05_billboards_plus1_plus50.jpg`: the +1 pickup and the +50 CANDY burst risers, the candy
  burst on the floor.

Fresh player (`fresh/`, step 19, a new save, core's BootLive):

- `01-join-tutorial-night.jpg`: the join: Night sky, orchid tables, dead trees, strands; the
  tutorial's "Join a table!" arrow; no prompt, no candy.
- `02-tutorial-first-match-orchid.jpg`: the tutorial's first match on table 2, orchid, balls
  readable.
- `03-prompt-after-tutorial-result-card.jpg`: after Skip and the match, the King's prompt at the
  throne (behind the result card until Continue).
