# Halloween 2026, W1: the coordinator

**Written 2026-10-28 07:15 EDT by the designer (Justin) with Claude.** Lane `coordinator`
(window W1): folder `~/Desktop/8ball`, branch `halloween`, Rojo **34872**, Studio window = **the
Team Create place** ("Crazy 8 Ball"; you are the only terminal that ever touches it), **Opus 5.5
with ultracode on** (xhigh plus multi-agent review workflows). The shared contract is
[`docs/halloween/PLAN.md`](../halloween/PLAN.md) (plan page
https://claude.ai/artifact/9f2FRDkuHesqL2JfWmnFfg); the requirements are
`docs/halloween/REQUIREMENTS.md`; your lane file is `docs/halloween/lanes/coordinator.md`.
Times are EDT. Lanes stop building at 16:00, the freeze is 17:00, Justin playtests 17:00-18:30,
publishes about 18:30, and the event goes live by itself at 19:00.

You are the desktop conversation that planned this build, forked into the CLI. Justin starts you
with the command `tools/halloween/lanes.sh command coordinator` prints (copy it from there; never
write your own flags). A resume does not keep `--settings` or the permission flag, so any restart
of yours is that same printed command again: it forks the planning conversation once more, and
you pick up at the first unticked Progress line and your lane file's Status.

Then he types: "Read docs/prompts/HW_COORDINATOR_PROMPT.md and start at the first unticked
Progress line." `tools/halloween/lanes.sh status` shows every lane's folder, branch, last
commit and Rojo.

**Attended until 11:00.** The Progress list at the end is the source of truth; the Stop hook
(`tools/overnight/hw_coordinator.json`) sends you back to work while any `- [ ]` line remains.
Until 11:00 Justin answers fast: when you truly need him (an approval below, a click only he can
make, access you cannot get), run `touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"`,
ask one clear question with a
picture, and stop; the hook lets that one stop through. **After 11:00 he may be asleep until
about 16:30**, whatever the hook's message says: decide the way he would (PLAN §2, past
decisions, `docs/UI_STYLE.md`, simple for kids), log it under Assumptions in your lane file, and
keep going. What only he can do goes on a "Justin at 16:30" list in your lane file's Requests.

**Waiting.** Many lines are tied to a clock time or to a lane's push. Never end a turn just to
wait: the hook sends you straight back and every bounce counts toward `OVERNIGHT_MAX=400`.
Wait inside the turn (the Monitor tool with an until-loop on the clock or on
`git ls-remote origin 'refs/heads/hw-*'` changing, at most about 15 minutes per wait, or a
`run_in_background` sleep you are woken from), and between waits do the standing duties in §2.1.
Lines may be ticked out of order when their time has come and an earlier one is blocked.

**Hard rules (nothing else stops a bad command in this mode):**
- **Never publish**, not the real game (place 107430170196919) and not the test place
  (75362358216917). Justin publishes. Never push `main`, `gui-v4` or `release`, never
  force-push, never merge `claude/rewards-0a7d6e` ("Match prize" stays out, PLAN §1).
- **Create nothing a lane owns** (PLAN §4). A bug in a lane's area goes back as a dated Request
  in that lane's file; the one exception is in §3 (the template ONLY filter at 14:00).
- **In a lane's worktree you write exactly one kind of thing:** a dated line directly under the
  `## Status` heading of its lane file. Never commit there, never run its Rojo, never drive its
  Studio window. The briefs, lane files and hooks reached the six worktrees through a
  fast-forward the desktop session ran at about 07:50 (it also opened the six lane Studio
  windows); you only verify that. The one exception: if a worktree still lacks its brief, lane
  file or hook, you may run `git -C ~/Desktop/8ball-hw-<x> merge --ff-only halloween` while it
  has no commits of its own and no `claude` runs in it; otherwise a dated Status line asks the
  lane to `git fetch && git merge halloween` itself.
- **Scripts are files** (CLAUDE.md). Never create or edit a script through the Studio MCP.
  Running an Edit-mode builder in the command bar (`execute_luau`), as the repo's tools say to,
  is allowed.
- **The Team Create place holds unfinished `halloween` code from the first merge (08:30)**, so
  Justin must not publish from it before the 18:30 release (say so in the 07:30 message).
- **Store-page changes are public.** The Experience Event, the title, the icon and the
  thumbnail change only after Justin's yes at gate 1 for the exact texts, images and schedule
  you showed him; anything not shown asks again.
- **Keys** live in the Keychain (`ROBLOX_API_KEY` = the group key: uploads, products, passes,
  the icon; `ROBLOX_USER_KEY` = Painicane's user key: badges, title, Experience Event,
  thumbnails; `ROBLOX_ANALYTICS_KEY`, `ROBLOX_PUBLISH_KEY`, `OPENAI_API_KEY`).
  `python3 tools/halloween/key_scopes.py` lists both keys' scopes and what is missing. Never print, echo, log or write one; check one exists as True/False only.
- **Uploads:** images, meshes, the skybox and badge icons go to group 675425213 without asking
  (dry-run first). No audio uploads. No spending except the badges Justin approved.
- **Blender only headless** (`/Applications/Blender.app/Contents/MacOS/Blender -b -P ...`); the
  live Blender MCP is shared by every terminal, never use it.
- **cliclick moves the real mouse.** Before 11:00, tell Justin before a sweep ("the mouse will
  move by itself for ~2 minutes"). Before every click, check that the frontmost window's title
  is the Team Create place; capture only that window.
- Commits: small, one thing each, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## 0. Read first

In this order: `CLAUDE.md`; `docs/parallel/README.md` (its rules apply, with PLAN §4's lanes,
ports and branch `halloween` in place of `release`); `docs/halloween/PLAN.md`, `REQUIREMENTS.md`,
`BADGES.md`; every lane brief `docs/prompts/HW_*_PROMPT.md` (Core, Cues A, Cues B, Map, Sys, GUI:
their Interfaces, Checks, Cut order, Gates and Progress lists are what you hold them to) and
every lane file `docs/halloween/lanes/*.md`; `docs/STATUS.md`; `docs/STUDIO_NOTES.md` (Open Cloud
uploads, products, the test-place recipe and its 409 note at about lines 159-170);
`.claude/skills/lively-gui/SKILL.md` and `verification.md` (what a passing GUI looks like);
`tools/overnight/keep_going.sh`; `tools/halloween/studio_size.sh`; `tools/lanes.sh`;
`tools/build_cue_templates.luau`; `tools/roblox_upload.py`; `tools/openai_image.py`;
`~/Desktop/8ball-refs/analytics/2026-10-25/aq.py` and `~/Desktop/8ball-refs/halloween/analytics/q.json`.

Agent reports in `~/Desktop/8ball-refs/halloween/research/agents/`: **in full**
`research-boosts-hype.md` part B (B1 Experience Events and their API, B2 icon and thumbnail
routes and moderation, B3 countdown icons, B4 title through the places PATCH and its 409, B5
server restarts) and `claude-cli.md` (resume, effort, ultracode, `--settings`, Stop hook caps).
**Skim** `code-cues.md` (template build risk, old servers, the body path), `code-bot-map.md`
(Edit-mode builds: EventProps, TableLooks, props, the throne spot), `code-hud-boosts.md` (§3
device detection, the free-width table), `code-roam.md`, `code-badges.md`, `research-badges.md`,
`economy-candy.md` (the numbers you compare live data with; its StartsAt/EndsAt and its Oct 31
window are older than PLAN: PLAN wins).

Pictures (open them; you judge merges and gate shots against them):
- `~/Desktop/8ball-refs/halloween/refs/01-live-icon.png`: the live icon today (`refs/icon.json`:
  state Completed, version TN3). The base of every icon you make.
- `~/Desktop/8ball-refs/halloween/mocks/M6_icon.png` (prompt `prompts/M6_icon.txt`): the
  approved Halloween icon direction: same composition, purple night sky, full moon, dead trees,
  witch hat on the bacon hair, jack-o'-lantern on the rail, 8-ball brightest, no text.
- `~/Desktop/8ball-refs/halloween/refs/04-live-thumb-winner.png`: the winning thumbnail (0.85%
  QPTR on Oct 26): a raw gameplay screenshot with the HUD on. Game-faithful beats posters.
  `mocks/M7_thumb.png` is only the direction for the Halloween one.
- The five approved cues, `~/Desktop/8ball-refs/halloween/mocks/v2/`: `C5_candy_corn.png`,
  `C4_jack.png`, `C2c_black_cat.png` (no head, a tail only, faceless silhouettes, gold rim,
  tough, no pink), `C1b_spider.png` (huge blades past the butt that fold or fade near the
  camera), `C3b_broom.png` (crooked branch, violet crystal tip, swaying hat charm).
- `mocks/v2/MAP2_lobby.png` (night lobby), `P1_pumpkin_king.png`, `H1_boost_hud.png` (the pill),
  `PREV1_cue_preview.png`; `refs/06-gameplay-hud.jpg` (today's HUD).

## 1. Goal

**Rows you own:** R0.1 and R0.2 (released today at 19:00 in high quality, builds done 17:00 so
Justin gets 1.5 h of playtest), R0.3 (the windows keep running unblocked), R0.5 (every new screen
checked on phone, tablet, console and PC without Justin switching devices), R0.6 (the merged
build is bug-free on every device: you are the one place everything is tested together), R0.9
(nothing lost: the docs hold every decision), R1.7 (store countdown: Experience Event, icon
countdown, title), R1.9 (Halloween icon and thumbnail). R0.10 (how Candy works) is already done:
it was answered to Justin on the plan page and in chat before the start, so set its Status to
done and send nothing more about it. And the final check of every other row:
at 16:45 each REQUIREMENTS row's Status is `verified` or `cut (reason)` from the lane reports
and your own tests.

**Done, in player terms:** at 18:30 a kid scrolling Roblox sees "[🎃 7PM] Crazy 8 Ball" with a
pumpkin-night icon marked 1H, and a "Haunted Rooftop" event with Notify me on the game page. At
19:00 the night falls in every server by itself, the icon says LIVE, and every part of the
event works on a phone, a tablet, a console and a PC with no errors in the console or the error
report, while server frame rates hold. Justin got one clean build at 17:00, a short checklist,
and a list of off switches; nothing broke.

## 2. Design

### 2.1 Standing duties (all day, between the timed lines)

Every ~30 minutes: `git fetch origin`; read each lane file's Status and Requests (in its
worktree, table below); answer Requests addressed to you; pull merges whose steps say verified
(§2.2). **From 08:45 you merge on request**, not only at the timed passes: a lane's
`MERGE NOW` Request or a verified step is merged through §2.2 within about 15 minutes (expected:
Cues A drop 2 at about 08:45; drop 3 and the GUI pill at about 10:00-10:20, Cues B needs drop 3 in
its branch by 10:15-10:50). If a lane's Progress has not moved in 60 minutes, add a dated nudge
to its Status. If a lane's `claude` process is gone (`ps aux | grep 8ball-hw-<x>`), tell Justin
before 11:00; after 11:00 you may restart it yourself: a new Terminal window running the command
`tools/halloween/lanes.sh command hw-<x>` prints (never your own flags; the new session picks up
at the lane's first unticked Progress line), logged; never two sessions in one folder. Keep your lane file's
Status one dated line per event (merge, build, sweep, store change) with the sha or asset id.

| Lane | Worktree | Branch | Rojo | Lane file (in its worktree) |
|---|---|---|---|---|
| Core | `~/Desktop/8ball-hw-core` | `hw-core` | 34883 | `docs/halloween/lanes/hw-core.md` |
| Cues A | `~/Desktop/8ball-hw-cues-a` | `hw-cues-a` | 34884 | `docs/halloween/lanes/hw-cues-a.md` |
| Cues B | `~/Desktop/8ball-hw-cues-b` | `hw-cues-b` | 34885 | `docs/halloween/lanes/hw-cues-b.md` |
| Map + King | `~/Desktop/8ball-hw-map` | `hw-map` | 34886 | `docs/halloween/lanes/hw-map.md` |
| Roam + Badges | `~/Desktop/8ball-hw-sys` | `hw-sys` | 34887 | `docs/halloween/lanes/hw-sys.md` |
| Boost pill + Preview | `~/Desktop/8ball-hw-gui` | `hw-gui` | 34888 | `docs/halloween/lanes/hw-gui.md` |

If a lane file has another name, `ls docs/halloween/lanes/` in that worktree and use it.

### 2.2 Merging a lane (every time, in this order)

1. **Ready?** The lane's Status says the step is verified and the commit is pushed
   (`git log origin/hw-<x> -3`).
2. **Ownership:** `git diff --name-only halloween...origin/hw-<x>` stays inside the lane's Owns
   plus its listed Shared-file changes. A file outside both: do not merge; Request.
3. **Review:** an ultracode review workflow over `git diff halloween...origin/hw-<x>` (code
   first: `*.luau`, `*.py`; skim JSON and assets), findings verified before reporting (the
   `code-review` skill at `high` when a workflow is not available). Look hardest at: saves
   (fields only added, template + validate + MAP_KEYS, an old-save test), purchases (replay
   safe), payouts (PLAN numbers, `Settle.isReal`, kind "Pc" for the King), the server trusting
   the client, per-frame work, switches defaulting true only when verified, text outside
   `Strings`, anything visible while its switch is off, a track cue granted while
   `Catalog.ready(id)` is false (core holds it and retries on load and every tick), a second copy
   of a single-source number (friend and group boost only in `Config.Economy`, read through
   `Money.friendBoost`/`Money.boostParts`; the pickup cap only in
   `Config.Halloween.Pickup.HourCap`, enforced by `CandyService.pickup`). A critical finding (error, save risk,
   payout or purchase bug, a device crash) blocks the merge and goes to the lane; minor ones
   merge and go to the lane as Requests.
4. **Merge:** `git merge --no-ff origin/hw-<x> -m "Merge hw-<x>: <step>"`. Shared files (PLAN
   §7: `Config.luau`, `Strings.luau`, `SaveSchema.luau`, `PlayerData.luau`, `Ranking.luau`,
   `TableService.luau`, `Main.client.luau`, `Bootstrap.server.luau`, `Progression.luau`,
   `HubCorners.luau`, `Net.luau`, `DevCommands.luau`, `UltService.luau`,
   `tests/save_schema_test.luau`, `tests/config_test.luau`, `tools/upload_manifest.json`,
   generated `src/shared/CueSkins/*`): each lane adds its own block or line and lists it in its
   lane file; you resolve the overlaps. A conflict between two lanes' blocks: keep both whole.
   The known overlaps:
   - `HubCorners.luau` `padStops`: core's event tile goes first; GUI's pill goes right after Plus.
   - `UltService.luau`: only Sys edits it (it adds the `UltService.Used` signal); core
     subscribes through a guarded require, so a core diff touching UltService fails step 2.
   - `Net.luau`, `DevCommands.luau`, `tests/save_schema_test.luau`, `tests/config_test.luau`:
     one block or line per lane, keep every lane's (core's `/hw ...` block with `/hw kingwin`,
     never `/hw king`, next to Map's `/king`).
   - `tools/upload_manifest.json` (rows from Cues A, Cues B, core and GUI): take the union, never
     drop a row: `git show :2:tools/upload_manifest.json` and `:3:` into your scratchpad, merge
     the dicts in Python (an `"ok"` row wins over any other status for the same path), write it
     back with `indent=2, sort_keys=True`, check it parses, `git add` it. Resolve this before the
     generated files.
   - `src/shared/CueSkins/*` (generated by both cue lanes): take either side, rerun
     `python3 tools/cue_skins_data.py`, check `git diff --stat src/shared/CueSkins` shows only
     Halloween skins, pieces, `Index.luau` and `Textures.luau`, `git add` them. If the generator
     fails, `git merge --abort` and send the error to Cues A.
   Any conflict inside one lane's logic: `git merge --abort` and ask that lane to merge
   `halloween` first. Merge order when several are ready: sys's interface commit, core, cues-a,
   gui, map, then the rest of sys, cues-b.
5. **Tests:** `tools/lint.sh` and `tools/test.sh` green, test count never below the last pass
   (record it).
6. **Studio, the Team Create window only:** Rojo 34872 synced (a value from the merge visible
   through MCP), Play solo, console clean, the lane's own check path from its lane file, stop
   play. Several lanes merged in one pass may share one Studio check; if it fails, revert the
   last merge first.
7. **Push** `git push origin halloween`, then a dated line at the top of every lane file's
   Status: `- HH:MM coordinator: halloween @<sha> has <what>; run git fetch && git merge halloween`.
8. **Broke something after the push:** `git revert -m 1 <merge sha>` (never reset a pushed
   branch), push, tell the lane and everyone.

### 2.3 Building in the real place (lanes' Requests)

Edit mode only (stop play first; `MapBuilder.prepareProps` refuses to run in play,
`src/shared/MapBuilder.luau:518-521`; `TableBuilder.prepareImport` is at
`src/shared/TableBuilder.luau:452`). Before the first build of the day, note the place's
current version (Creator Hub > Crazy 8 Ball > Places > Version History) so a bad build can be
rolled back, and save a copy to `~/Desktop/8ball-refs/halloween/backup/` if Studio's
File > Save to File As works through System Events. Prefer what travels with a branch (code, or
`.rbxm` under `src/`); build by hand only what a Request spells out exactly, and log every build
(what, where, which command) in your Status.

- **Cue templates for the 5 new ids, ONLY.** `tools/build_cue_templates.luau` today destroys and
  rebuilds every template (`:88-96`, a loop over `CueSkins.ids()`) and every piece
  (`:170-184`), so one failed `LoadAsset` would break a shipped cue on the live place
  (code-cues.md, Risks). Cues A adds an ONLY-these-ids filter (PLAN §4). Run it only with
  `ONLY = { "CandyCornCue", "JackOLanternCue", "BlackCatCue", "SpiderCue", "WitchBroomCue" }`
  (and their body, aura and pocket pieces). Before and after, print a fingerprint of
  `ReplicatedStorage.CueSkins` and `ReplicatedStorage.CuePieces` (each child's name, class,
  descendant count, MeshIds and SurfaceAppearance map ids); the diff may show only the 5 ids and
  their pieces. The console must say "only: N skins, M pieces rebuilt; K other templates
  untouched" (Cues A's report line; N = the ids in that run, K = every other template) with no
  warnings. Then the
  lab (`tools/vfx_lab.luau`, `IDS` = the 5 plus `EclipseCue`) in Play, and one match: hands,
  back, trail, pocket finisher, Lower effects. Rebuild per id as Cues A/B report each cue's
  assets uploaded and in `tools/upload_manifest.json` (expected about 12:30, 14:30, 15:45).
- **EventProps, table looks, props, the throne:** exactly what Map's Requests say (asset ids,
  sizes, positions, properties), e.g. `ServerStorage.EventProps` models or a
  `TableBuilder.prepareImport` run for a new look. Missing assets must be skipped quietly by the
  code that clones them (code-bot-map.md); check that the server boots without them too.
- **Skybox:** the ids live in Config (`Lighting.Night`, Map lane); `DayCycle` preloads the Day,
  DuskSky and Sunset faces (`src/client/DayCycle.luau:60-70`), so the Night alias needs no place
  build. Only verify in Play that the new purple sky loads with no grey faces.

### 2.4 Device sweeps

- **First (07:45), verify the resize helper** after Justin grants Terminal Accessibility and
  Screen Recording: `tools/halloween/studio_size.sh "Crazy 8 Ball" show`, then resize; in Play
  read `workspace.CurrentCamera.ViewportSize` through MCP and adjust the outer size until the
  viewport is 844x390, 1024x768 and 1920x1080. Write the outer sizes that give each viewport
  (and whether the helper works) at the top of every lane file's Status, so lanes reuse them.
- **The Device menu.** Studio's device emulator is RobloxScriptSecurity: MCP and plugins cannot
  switch it (checked 2026-10-04), so click it like a person. `brew install cliclick`; front the
  Team Create window by name (`osascript`, System Events); `screencapture -x -l <window id>` to
  see it (Retina pixels are 2x the points cliclick uses); find the Test tab's device control;
  `cliclick c:<x>,<y>`; pick a phone (landscape, about 844x390), an iPad (1024x768) and a
  console/TV preset (1920x1080); capture again to confirm; switch back to off. Record the steps
  and coordinates in your lane file and wrap them in `tools/halloween/device.sh
  phone|tablet|console|off` (yours) so later sweeps are one command.
- **Controller:** GuiQA `"pad"` (`src/client/HubPad.luau:225`) forces pad mode, but RankHud,
  UIAnim, MenuFrame and ShopParts read `GetLastInputType` directly (code-hud-boosts.md §3), so
  judge controller focus on the console preset too.
- **What a sweep covers** (each at phone, iPad, PC and TV + pad, in the Team Create window):
  the lobby at Night with the decor and the three table looks; the Halloween button and menu
  (track, quest board, Spider ring); the Rush chip and the boost pill + card; the countdown
  banner, the 19:00 start moment and the end screen (Candy to money) through Core's
  designer-only `/hw time countdown|live|rush|double|end|real` (HW_CORE_PROMPT §2.3, §2.13); the King's
  throne, prompt, a King match and the candy explosion; a pickup; the Cue Preview from My Cues
  and the Index; the five cues in hands, on a back, trail and finisher; badge pop-ups; roaming
  and the teleport back; Candy pack prompts (cancel, never buy). Proof:
  `~/Desktop/8ball-refs/halloween/shots/coordinator/devices/<HHMM>/<device>-<screen>.png`. A
  failure goes to the owning lane as a Request with the shot.
- **Fresh-player run** (CLAUDE.md) after any merge touching join, the tutorial, the first match,
  saves, purchases or lobby popups (Core, Sys badges, GUI pill, Map's prompt): join on a fresh
  save, tutorial and skip, first match, the popups. The Halloween button and popups wait until
  the tutorial is Done or Skipped; Candy counts from the first match; badges never during the
  tutorial or a lucky-block reel.

### 2.5 The store page

Tools: `tools/halloween/store_page.py` (yours) with subcommands `event`, `title`, `icon-upload`,
`icon-set`, `icon-check`, `icon-schedule` and `selftest`; it reads `ROBLOX_USER_KEY` from the
Keychain for `event` and `title` (and a thumbnail) and `ROBLOX_API_KEY` (the group key, asset
scopes on group 675425213) for the `icon-*` asset calls, dry-runs by default (prints the request without the key), and logs every real call
to `~/Desktop/8ball-refs/halloween/shots/coordinator/store/log.txt`. For the unofficial icon
route, read the community updater named in research B2 as text for its request shape; never
run downloaded code. Universe 10767330648, root place 107430170196919.

- **API key scopes (settled 07:55 in the desktop chat).** Creator Hub offers the legacy badge
  scopes only on user keys, so Justin made a user key ('badge-event-place-thumbnail', stored as
  `ROBLOX_USER_KEY`): `legacy-universe.badge` write + manage-and-spend-robux, `legacy-badge`
  manage, `universe.event` read/write, `universe.thumbnail` read/write. Its "universe-places"
  entry gave only `universe-places:write` (publishing), NOT `universe.place:write` (the title);
  run `key_scopes.py` first: if `universe.place:write` is still missing, the title changes go on
  Justin's list as clicks (Creator Hub > Configure > Basic Settings > Name) and you never use the
  publish scope. The group key `ROBLOX_API_KEY` ("8ball uploader": asset read/write on group
  675425213, asset-permissions write, developer-product and game-pass read/write on 10767330648)
  keeps uploads, products and the icon calls.
- **Experience Event** (create right after gate 1's yes, so Notify me collects RSVPs all day):
  title `Haunted Rooftop`; subtitle `5 Halloween cues · Pumpkin King · Candy`; description
  (kid-simple, nothing a cut could make untrue): "The rooftop turns haunted for 6 days! Play
  matches to collect Candy, finish the daily quests and unlock 5 Halloween cues that never come
  back. Challenge the Pumpkin King on his throne. Candy Rush: 2x Candy the first 10 minutes of
  every hour. Ends Nov 3."; start `2026-10-28T23:00:00Z` (19:00 EDT, `1793228400`); end
  `2026-11-04T00:00:00Z` (19:00 EST Nov 3, `1793750400`); place 107430170196919; public; no
  thumbnail at first (it falls back to the game's), the Halloween thumbnail added at 16:30.
  Route: `POST apis.roblox.com/virtual-events/v3/universes/10767330648/game-events`
  (EXPERIMENTAL, body fields undocumented: take them from Roblox's own OpenAPI spec in the
  creator-docs repo), then GET it back. On any 4xx: exact clicks for Justin before 11:00
  (Creator Hub > Crazy 8 Ball > Engagement > Events & Updates > Create Event, field by field, the
  times typed in Eastern time; check the end reads 7:00 PM EST on Nov 3, after the clocks
  change). Verify on the game page (Claude in Chrome, read-only): the Events section shows it
  with its countdown.
- **Title.** First `GET cloud/v2/universes/10767330648/places/107430170196919` and record the
  current `displayName` (the Nov 3 revert). Plan: 14:00 `[🎃 7PM] <name>`, 19:00
  `[🎃 HALLOWEEN] <name>`, by `PATCH ...?updateMask=displayName` (`universe.place:write`, 100 a
  minute). It returns **409 while the place is open in a Team Create session, Studio counts**:
  at 10:00 test a no-op PATCH (the same name) with your window open (expect 409), then with your
  Team Create window closed (expect 200). For each real change: sync, stop play, close your
  window, PATCH, GET to confirm, reopen the place (the Rojo plugin auto-connects a new window to
  34872; check it). Still 409 (someone else has it open): skip and put it on Justin's list
  (Creator Hub > Configure > Basic Settings > Name). The text filter once blocked "[UPDATE]": if
  a title is refused, fall back to `[HALLOWEEN] <name>` without the emoji.
- **Icons (512x512 square, edge to edge, no rounded corners: check the corner pixels; words off
  faces).** LIVE base = the Halloween edit of `01-live-icon.png` in the M6 direction (use
  `mocks/M6_icon.png` if it passes, else edit it with `tools/openai_image.py`, the live icon
  attached first). Countdown frames 5H, 4H, 3H, 2H, 1H = that icon plus a bold corner badge drawn
  with Pillow (readable at 150x150; pumpkin orange `#FF7A1A` on deep purple, white text);
  LIVE = the same with a LIVE badge; optional seventh = the plain Halloween icon with no badge,
  for after launch night (Justin's call at gate 1). Upload all of them plus one exact copy of
  the current icon (for the test) **by 10:00** as the asset type the icon route takes, then poll
  each until `moderationState` is APPROVED.
- **Icon route test (10:00), revert at once.** Record the current icon's image id (Assets GET on
  the place, or `thumbnails.roblox.com/v1/games/icons?universeIds=10767330648`). `PATCH
  /assets/v1/assets/107430170196919?updateMask=icon` with the identical copy; check the icon
  thumbnail's state is Completed and its version moved, download it, and compare it with the
  source; then PATCH back to the original id and check again. Never set an image that is not
  APPROVED: a pending icon shows a blank placeholder to 25K players a day.
- **Countdown schedule (if the test passed):** `icon-schedule` runs in the background from 13:55
  under `caffeinate` and swaps at `1793210400` 5H (14:00), `1793214000` 4H (15:00),
  `1793217600` 3H (16:00), `1793221200` 2H (17:00), `1793224800` 1H (18:00), `1793228400` LIVE
  (19:00); after each swap it checks the live icon (Completed, same picture) and on any doubt
  puts back the last good one and stops. **If the test failed:** the countdown is cut (every
  hand upload starts a new review with a blank placeholder); before 11:00 Justin chooses between
  one hand swap to the Halloween icon at about 18:30 (a 5-click guide in RELEASE.md: Creator Hub
  > Crazy 8 Ball > Places > the start place > Icon > upload) and keeping today's icon.
- **Thumbnail (16:30):** a real Studio screenshot of the built night map in the Team Create
  place, in Play with `/hw time live`: the HUD on, Painicane holding the Broom (or
  the best finished Mythic if the Broom is cut) at an orchid-purple 1v1 table, the throne behind,
  framed like `04-live-thumb-winner.png`; 1920x1080 viewport through `studio_size.sh`; three
  candidates, no added words. Justin picks one at 17:00 and adds it at 18:30 (Creator Hub, or by
  API on his yes); the same image becomes the event's thumbnail.

### 2.6 Gate pages

One private artifact, "Halloween Gates" (load the `artifact-design` skill and run the Artifact
quickstart first): a section per gate, a card per lane with its `shots/<lane>/gate1|gate2/`
images (JPG, about 1600 px wide, as supporting files) and the one-line captions from its lane
file's Gate shots, that lane's open questions, then your own card. Republish the same file for
gate 2 so the link stays. Justin answers in the terminal (or with OK/Change marks if you give
the page a db through the `artifact-capabilities` skill). Copy every answer into the lane's
Status as a dated line, and decisions into your lane file for DECISIONS.md.

### 2.7 The contract test (`tests/halloween_contract_test.luau`, yours, 08:45)

Checks every number PLAN fixes, against the names the lanes chose (read from their lane files
after the 08:30 merge): `Event.state` is Before below `1793226600`, Countdown to `1793228400`,
Live to `1793750400`, then Ended; `Event.multiplier` is 1 or 2 at every 10-minute sample of the
event and 2 exactly in UTC minutes 0-9 and inside the Oct 31 Eastern window
`1793419200`-`1793505600`, never 4; `Event.boardIndex` steps at `1793228400 + (N-1)*86400`, N
1-6; Candy 3 a ball, 10 a finished match, +25 a win; boost = E x (1 + 0.1·min(friends,4) +
0.1·group); quests 60/100/150/250; the track 50 spin, 150 `CandyCornCue`, 300 $2,500, 500
`JackOLanternCue`, 1,000 2 spins, 1,500 $5,000, 2,000 `BlackCatCue`, 3,000 3 spins, 4,500
$10,000, 5,500 5 spins, 7,000 `WitchBroomCue`; Spider at 10,860 active seconds; King +50 for
each of the first 2 wins a UTC day, 900 s cooldown, at most 3 at once, 2 spare tables, kind
"Pc", rematch "Never"; the pickup cap `Config.Halloween.Pickup.HourCap` = 40 a player a UTC
hour and no second cap key (none under `Config.HalloweenMap.Candy`); packs 500 for 49 R$ and
2,000 for 149 R$; the friend and group numbers only in `Config.Economy` (`FriendBoost` 0.1,
`FriendBoostMaxFriends` 4, the existing `GroupBoost` 0.1) with no copy under `Config.Halloween`
(no `FriendAdd`, `FriendMax`, `FriendsEnabled`, `GroupAdd`), and Candy's boost computed from
them (`Money.friendBoost`/`Money.boostParts`); `Config.Halloween.CandyIcon` is a string;
conversion $10 a Candy; cloths 1v1 (185,90,230), 2v2 (90,94,102), 3v3 (110,220,40); the five
ids exist as group "Exclusive" rows with their names in `Strings`, and none is `CandyCue` or
`PhantomCue`; every Halloween, HalloweenMap (`Enabled`, `Boss.Enabled`, `Candy.Enabled` and the
rest), Roam, Badges, BoostPill, CuePreview and `CueSkins.Bodies` `Enabled` and
`Economy.FriendBoostEnabled` is a boolean. A part whose lane has not merged
yet is skipped with a printed note; after 12:00 nothing may skip. Plus
`python3 tools/halloween/store_page.py selftest` (the right icon for every hour, never an
unapproved id).

### 2.8 Freeze, release, watch

- **16:00:** every lane is done or its open lines are ticked CUT/BLOCKED; every cut is switched
  off and the sweep proves nothing of it shows.
- **17:00 freeze:** `halloween` at the final sha, `git status` clean, pushed; the Team Create
  window synced to it, console clean; the place saved to `place/8ball.rbxl` (File > Save to File
  As through System Events, else Justin at 16:30; commit it once, CLAUDE.md). The test-place
  build: `rojo build default.project.json -o build.rbxl`, then `lune run
  ~/Desktop/8ball-refs/tutorial/merge_place.luau place/8ball.rbxl build.rbxl
  ~/Desktop/8ball-refs/halloween/build/halloween-<sha>.rbxl` (STUDIO_NOTES); open it locally to
  check it boots. Justin publishes it to Crazy 8 Test Place himself (Studio, or the Open Cloud
  command you hand him). On the test place Core's server sets `HwTimeOffset` at boot so the
  event is Live, and `/hw time` moves it (Core §2.3); check both in the built file. Only if that
  is missing: a clearly named test-only file with the start shifted to now+10 minutes, from a
  throwaway branch that is never merged.
- **`docs/halloween/RELEASE.md` (yours, 16:45):** (1) Justin's by-hand list per device: join on
  a new and an old account, the tutorial (no Halloween popups until Done or Skipped), a match
  paying Candy, the King, a pickup, the pill and its card, roaming, a pack prompt, the preview,
  each cue, Lower effects. (2) Publishing: the Team Create window, Rojo synced at the final sha,
  tree clean, File > Publish to Roblox; then Creator Hub > Configure > Server management >
  Restart Servers with **"Restart only servers with outdated versions"** and no delay longer than
  10 minutes, so every old server is gone well before 19:00 (old code resets an equipped new cue
  to Classic, `src/shared/Progression/SaveSchema.luau:1313-1330`, and pays no Candy). Servers
  restart themselves after 5-6 h anyway (`Config.ServerRestart`, `Config.luau:9089`). (3) What
  to see at 18:30 (countdown banner only) and at 19:00 (night falls, props, button, King, Candy,
  pickups, and a Rush chip at once: 19:00 EDT is UTC minute 0). (4) Every switch, what turning
  it off does, and its exact Config line, from the lane files. (5) A break: flip the switch,
  commit, push, Justin publishes with outdated-only restart; you prepare that commit on request.
  (6) Nov 3 19:00 EST: the event ends and converts by itself; revert the title and the icon to
  the recorded originals; the Experience Event ends itself. (7) Each lane's custom events and
  what to read when. (8) A Discord announcement draft (Justin posts it).
- **After 19:00, the watch:** `python3 ~/Desktop/8ball-refs/analytics/2026-10-25/aq.py <q.json>
  <out.json>` (2 threads at most, or 429s) for concurrent users, `ServerFrameRateP10` and P50 and
  server memory at the finest granularity it allows; Core's custom events (`HwCandy`, `HwMatch`,
  `HwQuest`, `HwTrack`, `HwSpider`, `HwPack`, `HwConvert`, `HwMenu`, the `Halloween` funnel)
  and the other lanes' as they arrive; the Creator Hub error report
  (Monitoring > Error report, read-only in Claude in Chrome; any new error from
  `src/server/Halloween` or another new module counts).
  Baselines: server FPS P10 in `r2.json`/`r3.json` (about 37-47 before the Oct 25 surge, 1.6 at
  its worst), DAU 24,887 and 23.1 min per DAU (Oct 26). Alarms: P10 under 20 for 30 minutes,
  any new error on more than a few percent of sessions, Candy per active hour far above the
  model's ~400 (economy-candy.md §2), a pack grant failing. Report at 19:30, 20:00 and 21:00
  (your Status, plus a short note for Justin): numbers, what they mean, which switch to flip if
  any.

### 2.9 Docs

Lanes do not edit STATUS, DECISIONS or ROADMAP; you move their content over. By 16:45:
`docs/STATUS.md` (current state only: the Halloween update pushed on `halloween` and waiting to
publish, what to check by hand; it is 218 lines today, so move finished entries to the top of
`docs/archive/STATUS_HISTORY.md` until it is near 100), `docs/DECISIONS.md` (a dated 2026-10-28
line for each PLAN §2 decision and each lane decision, assumption and OVERRULED), `docs/ROADMAP.md`
(a "Halloween 2026" section, boxes ticked for what is verified), the REQUIREMENTS Status column,
and the GDD: Sys leaves paste-ready text in its Requests for the "stay by your table" lines
(`docs/GDD.md:279-281`), its DECISIONS lines and a badges section; other lanes may do the same.

### 2.10 Edge cases

- An interface commit is red or missing at 08:30: merge the others, retry at 08:45 and 09:00;
  lanes code against guarded requires meanwhile; never a stub.
- Screen Recording asks to quit and reopen Terminal: every CLI window restarts; each lane
  restarts in its own Terminal window with the command `tools/halloween/lanes.sh command <lane>`
  prints (never your own flags; it picks up at its first unticked Progress line), and you with
  `tools/halloween/lanes.sh command coordinator`.
- Rojo 34872 dies or Studio crashes: `tools/lanes.sh rojo main` (background, log in
  `.lanes/rojo.log`), reopen the place, check the sync. A lane window found on 34872: tell that
  lane to Connect to its own port.
- Justin (or anyone) is editing in the Team Create place: no Edit-mode builds until he leaves.
- Two lanes change the same existing line: the owner in PLAN §4 wins; the other gets a Request.
- A store change looks wrong (icon state not Completed, a different picture, title refused):
  put back the last good one at once, log it, and cut that piece.
- Rush at 19:00-19:10 doubles Candy by design; not an alarm.
- Daylight time ends Nov 1: the end is 19:00 EST = 00:00 UTC Nov 4, not 23:00 UTC.

## 3. Interfaces

**Done for you, verify it:** at about 07:50 the desktop session committed and pushed
`docs/halloween/`, `tools/halloween/`, every `HW_*` brief, lane file and hook on `halloween`,
fast-forwarded the six worktrees to it, and opened the six lane Studio windows (07:30 Progress
line).

**You deliver first:**
- **07:50:** the resize-helper verdict and outer sizes in every lane file's Status.
- **08:15-08:30: the interface merge** (PLAN §5), each through §2.2: `hw-sys`
  (`Config.Multiplayer.Roam` and `Config.Badges` switched off, the `Badges` save field with its
  old-save test, the `Badges.luau` API, the `UltService.Used` signal; merge it before core's so
  its SaveSchema lines land first, HW_SYS_PROMPT §3), `hw-core`
  (`src/shared/Halloween/Event.luau`: `state`, `isLive`, `rushActive`, `rushEndsAt`,
  `multiplier`, `boardIndex`; `src/server/Halloween/CandyService.luau`: `add`, `bossWon`,
  `bossCooldown(player) -> number` (unix time, 0 if none),
  `pickup(player) -> (ok, reason: "Cap"|"NotLive"|"NotLoaded"|nil)`, `isLive`; the
  `Config.Halloween.CandyIcon` key), `hw-cues-a` (the 5 Catalog rows and `Strings` names, Classic
  fallback look, `Catalog.ready`), `hw-gui` (player attribute `FriendsHere`, pure
  `Money.boostParts(flags)`, `Money.friendBoost`, `Config.Economy.FriendBoost`,
  `FriendBoostMaxFriends`, `FriendBoostEnabled` off) and `hw-map` (HW_MAP_PROMPT §3:
  `Config.HalloweenMap` with every switch false incl. `Enabled`, `Boss.Enabled`, `Candy.Enabled`,
  `Config.Lighting.Night`, `Strings.HalloweenMap`, the remotes `HalloweenMapFx` and
  `KingChallenge`, the guarded Bootstrap and Main.client blocks, the attribute names in its lane
  file), plus any other lane's pushed interface commit. Then push and the dated "merge
  halloween" line in every lane file.
- **08:45:** the contract test on `halloween`.
- **From 08:45: merges on request** (§2.1): Cues A drop 2 at about 08:45, drop 3 and the GUI
  pill at about 10:00-10:20, then each lane as it passes its checks.

**You consume (guarded fallback in brackets):**
- **Core:** the interfaces above [late: merge the rest, retry each 15 minutes]; `Clock.now()`
  with the `HwTimeOffset` attribute (Studio and the test place only, `Config.Save.TestPlace.GameId`)
  and the `/hw time ...` command, which every lane gates on and your sweeps use [missing by
  10:00: Request; else sweep Before only and build the test-only file in §2.8]; the Candy
  product ids (`Candy500`, `Candy2000`) and every switch name [read from Config at 16:00].
- **Cues A:** the ONLY filter in `tools/build_cue_templates.luau` with its first cue commit, and
  a Request per finished cue (ids, pieces, manifest paths) [no filter by 14:00: ask once more;
  at 14:30 add the filter yourself as one small commit, tell Cues A, list it in your
  Shared-file changes; never run the unfiltered builder on the Team Create place].
- **Cues B:** finished cues reach you through Cues A's pipeline and Requests.
- **Map + King:** Requests for EventProps, table looks, props, the throne; skybox ids in Config
  [an item not spelled out exactly is not built; ask].
- **Roam + Badges:** badges created on Roblox (needs the badge scopes from the 07:30 message) and
  their ids in Config; the roam switch [badges not created by 15:00: `Config.Badges` rows stay
  inert at id 0, logged as cut].
- **Boost pill + Preview:** the pill, card and preview with their layout test results; the
  Preview ships on only if it passes your phone and console sweep [else its switch off].
- **Every lane:** gate shots in `~/Desktop/8ball-refs/halloween/shots/<lane>/gate1|gate2/` with a
  line each in its lane file's Gate shots, by 08:55 and 10:55.

## 4. Checks

- **Lune:** `tests/halloween_contract_test.luau` (§2.7) and the `store_page.py selftest`; the
  full suite (`tools/test.sh`) after every merge, count never dropping; the lanes' old-save tests
  pass on the merged build.
- **Lint:** `tools/lint.sh` before every push; `tools/format.sh` only on files you changed.
- **Studio:** only the Team Create window ("Crazy 8 Ball" in `list_roblox_studios`), Rojo only on
  34872; Play solo after every merge pass; console clean; stop play when done.
- **Devices:** the four sizes (phone 844x390, iPad 1024x768, PC 1920x1080, TV 1920x1080 with GuiQA
  "pad") through `studio_size.sh` and `ViewportSize`, plus the Device menu's phone, tablet and
  console presets through `tools/halloween/device.sh`; sweeps at 13:00 and 16:00 (§2.4).
- **Fresh-player runs** at 13:00 and on the final build at 16:00.
- **Store page:** each change confirmed by a GET or the thumbnails API, logged with its id.
- **Screenshots:** `~/Desktop/8ball-refs/halloween/shots/coordinator/` (`devices/`, `store/`,
  `thumb/`, `gate1/`, `gate2/`, `release/`).

## 5. Cut order (first to go; a cut is switched off or skipped, never half-visible)

1. The hourly icon swaps 14:00-18:00 (keep LIVE at 19:00 if the route works, else today's icon).
2. The `[🎃 7PM]` title (keep only `[🎃 HALLOWEEN]` at 19:00, or none).
3. The cliclick Device-menu presets (keep window resizing, GuiQA pad and the layout tests; Justin's
   real phone, console and PC cover touch and controller feel at 17:00).
4. The thumbnail (keep today's winner).
5. Review depth on small or asset-only diffs (a single-agent review; never skip lint, tests or
   the Studio check).

Never cut: the interface merge, merges with lint, tests and the Studio check, the contract test,
the Experience Event, the 16:00 cut enforcement, the freeze, RELEASE.md, the 19:00 watch.

## 6. Gates

- **09:00, gate 1:** the lanes' PLAN §8 items (Candy Corn and Jack in Studio, night lighting and
  table colours, the pill at phone size, roaming, the badge list and icon drafts) plus yours: the
  resize helper and Device-menu proof (phone, tablet, console shots of the Team Create window),
  the merged sha with its test count and a Studio boot shot, and the store set (LIVE icon, the
  five frames, the plain option, the event text, the title strings, the schedule table with
  times). Ask, one line each: icons OK? event text OK? title OK? **yes to the store schedule?**
  Plus every lane's open questions.
- **11:00, gate 2:** the lanes' items (Broom, Cat and Spider bodies, the King at a table, the
  quest board and track, badges created on Roblox) plus yours: the event on the game page (shot),
  the icons' moderation states and the route test result, the merge state per lane, the first
  device shots of new screens, the "Justin at 16:30" list so far, and the calls you will make
  alone until then. Ask: anything before you sleep?

## Progress

- [ ] 07:30 Setup: read §0; baseline in the lane file (`git log --oneline -5`, lint, the test count); verify the desktop session's 07:50 hand-over instead of redoing it: `docs/halloween/`, `tools/halloween/`, the 7 briefs, lane files and hooks committed on `halloween` and pushed (`git status` shows none of them untracked or changed, `git log origin/halloween -1` equals local); each of the six worktrees on its branch at or after that sha with its brief, lane file and hook present (`git worktree list`, `tools/halloween/lanes.sh status`, `ls` in each; a gap: the one exception in the hard rules); the six lane Studio windows open (`list_roblox_studios`); the Team Create window found by name, Rojo 34872 serving `halloween` and connected; the REQUIREMENTS Status column set per its 07:50 note (R0.3, R0.4, R0.5 decided; R0.10 done, answered on the plan page and in chat; the superseded parts of R2.3, R5.5 and R1.10 marked); the one start message to Justin (Accessibility + Screen Recording, the API key scopes, no publish from Team Create before 18:30, the mouse will move during sweeps).
- [ ] 07:45 Devices: `studio_size.sh` verified on the Team Create window at the 3 viewports, cliclick installed, the Device menu switched to phone, tablet, console and back with proof shots, `tools/halloween/device.sh` written; verdict and outer sizes at the top of every lane file's Status.
- [ ] 08:00 Store drafts for gate 1: LIVE icon, 5H-1H frames and the plain option (512x512, corners checked), event text, title strings; current `displayName` and the original icon id recorded (GET only).
- [ ] 08:15-08:30 Interface merge: `hw-sys` (Roam/Badges config off, Badges save field, `UltService.Used`), `hw-core` (Event, CandyService with `bossCooldown` and `pickup` returning ok, reason; `Config.Halloween.CandyIcon`), `hw-cues-a` (5 Catalog rows, `Catalog.ready`), `hw-gui` (FriendsHere, boostParts, `Config.Economy.FriendBoost*`), `hw-map` (`Config.HalloweenMap` switches off, `Lighting.Night`, Strings, remotes, guarded blocks; HW_MAP §3), each reviewed, merged, lint + tests, Studio boot check; `halloween` pushed; the dated "merge halloween" line in every lane file (late ones in the 08:45 pass).
- [ ] 08:45 `tests/halloween_contract_test.luau` and the store selftest green on `halloween`, pushed.
- [ ] 08:45 Merge cues-a drop 2 on its Request (§2.2), pushed, lanes told; from now on merge every `MERGE NOW` Request within about 15 minutes.
- [ ] 09:00 Gate 1 page published; Justin's answers in each lane file and in your lane file; his yes for the store schedule.
- [ ] 09:30 Experience Event "Haunted Rooftop" (Oct 28 19:00 EDT to Nov 3 19:00 EST) created by API or Justin's clicks and seen on the game page; all icons plus the test copy uploaded, moderation polling.
- [ ] 10:00 Icon route test (identical copy, back at once) and the title no-op PATCH (409 with the window open?); the verdict in your lane file (automatic countdown, or cut with Justin's choice); every icon APPROVED.
- [ ] 10:00-10:20 Merge cues-a drop 3 (`MERGE NOW`, Cues B needs it for gate 2) and the GUI pill if its step is verified (§2.2), pushed, lanes told.
- [ ] 10:30 Requests pass 1 in the Team Create place (EventProps, table looks, anything listed), version noted, fingerprints before and after, logged.
- [ ] 11:00 Gate 2 page (same artifact); Justin's answers passed on; the "Justin at 16:30" list and your solo calls written.
- [ ] 12:00 Merge pass 1: every lane with a verified step merged (§2.2), pushed, lanes told.
- [ ] 13:00 Device sweep 1 and a fresh-player run on the merged build; failures sent as Requests with shots.
- [ ] 14:00 Store countdown: the 5H icon (if the route passed) and the `[🎃 7PM]` title live and confirmed; the icon schedule job running and logging.
- [ ] 14:30 Merge pass 2, and the ONLY-filter template build for every finished new cue in the Team Create place, checked in the lab and a match.
- [ ] 15:30 Merge pass 3; each lane's 16:00 cut list collected; every cut switched off and seen invisible.
- [ ] 16:00 Final lane merges and the last template build; device sweep 2 (every new screen, 4 sizes, pad, the Device presets) and a fresh-player run on the final build.
- [ ] 16:30 Thumbnail candidates (night map, the Broom, HUD on); the event description fixed for any cut; the "Justin at 16:30" list handed over.
- [ ] 16:45 Docs: STATUS, DECISIONS, ROADMAP, the REQUIREMENTS statuses, `docs/halloween/RELEASE.md` (checklist, switches, custom events, Discord draft), committed and pushed.
- [ ] 17:00 Freeze: `halloween` clean and pushed at the final sha; the Team Create window synced, saved to `place/8ball.rbxl`; the test-place build ready; Justin told exactly what to publish and how.
- [ ] 17:00-18:30 Playtest support: Justin's notes fixed only as he asks (by the owning lane or you), each re-verified and merged; at 18:30 the release checklist walked with him (he publishes, outdated-only restart).
- [ ] 19:00 Go-live: the LIVE icon and the `[🎃 HALLOWEEN]` title confirmed; the event state Live seen in live data; first watch reading.
- [ ] 19:30-21:00 Watch: error report, server FPS P10/P50, memory and concurrent users through `aq.py`, Candy, King and pack events against the model; reports at 19:30, 20:00 and 21:00 with any switch to flip.
- [ ] 21:00 Lane file Status final + all screenshots (`shots/coordinator/`, the gate page final, the store log).
- [ ] 21:00 Merge halloween: every lane's last commit merged, re-test (lint, tests), push; anything past the published sha listed in STATUS as waiting to publish.

## Notes
