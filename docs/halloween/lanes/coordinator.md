# Lane coordinator (W1)

Folder `~/Desktop/8ball`, branch `halloween`, Rojo 34872, Studio = the Team Create place
("Crazy 8 Ball"), Opus 5.5 with ultracode. Brief: `docs/prompts/HW_COORDINATOR_PROMPT.md`.
Contract: `docs/halloween/PLAN.md`.

## Owns

From PLAN §4 (lanes ask for these through their own lane file's Requests):

- The `halloween` branch: every merge, push and revert. Lanes never push to it. Merges on
  request from 08:45 (Cues A drop 2 at about 08:45, drop 3 and the GUI pill at about
  10:00-10:20), not only at the timed passes.
- Resolving overlaps in the shared files (PLAN §7, brief §2.2 step 4): each lane adds its own
  block or line and lists it in its lane file; you keep every lane's whole. `HubCorners`
  `padStops`: core's event tile first, GUI's pill right after Plus. `tools/upload_manifest.json`:
  the union (an `"ok"` row wins, keys sorted). `src/shared/CueSkins/*`: rerun
  `python3 tools/cue_skins_data.py`.
- `docs/STATUS.md`, `docs/DECISIONS.md`, `docs/ROADMAP.md`, `docs/archive/STATUS_HISTORY.md`,
  the Status column of `docs/halloween/REQUIREMENTS.md`, `docs/halloween/RELEASE.md` (new), this
  file and `docs/prompts/HW_COORDINATOR_PROMPT.md`.
- `tests/halloween_contract_test.luau` (new: the PLAN numbers every lane must keep).
- `tools/halloween/studio_size.sh`, `tools/halloween/device.sh` and `tools/halloween/store_page.py`
  (new), and `tools/overnight/hw_*.json`.
- The Team Create place and its Edit-mode content: the cue templates and pieces of the 5 new
  ids only (`ReplicatedStorage.CueSkins` / `CuePieces`, built with the ONLY filter),
  `ServerStorage.EventProps`, table looks, props and anything a lane's Requests spell out;
  `place/8ball.rbxl`.
- Device sweeps of the merged build (phone 844x390, iPad 1024x768, PC 1920x1080, TV 1920x1080 with
  GuiQA "pad", and Studio's Device menu presets).
- The store page: the Experience Event "Haunted Rooftop", the title prefix, the Halloween icon and
  the countdown icons, the thumbnail.
- The gate pages, the release checklist, the 19:00 watch.
- `~/Desktop/8ball-refs/halloween/shots/coordinator/`.

## Status

- 09:12 interface merge pushed: halloween @808ed389 (+ ticks @792bbb35) = sys 1c9f99b7, core 1c9945a0, cues-a
  1039f19b, gui b2c51102 (NOT b3bb0288 "Friend boost on": live pay, own review later), map 6d45e218. Reviews: 2
  workflows (5 lanes), 0 critical; minor findings sent as Requests. lint OK, 1370 passed / 0 failed, Studio
  Team Create: Rojo synced (Config 984285 bytes both sides), Play solo clean (only the old 203785492 warning).
- 09:05 new tests/client_compiles_test.luau (14e2d157): every src script compiles; Main.client must keep 8
  top-level locals of headroom (it had 14; map's block takes 2). Every lane told to wrap Main hooks in do...end.
- 08:58-09:02 store: originals recorded (store/original.json: "[EMOTES] CRAZY 8 Ball", icon 123614794049673 TN3);
  icons 5H-1H, LIVE, plain from M6 (512, corners square), uploaded with a copy of today's icon: all 8 APPROVED
  (store/icons.json). tools/halloween/store_page.py (dry-run default, log store/log.txt), selftest OK.
  Contract test tests/halloween_contract_test.luau (da021510): skips per lane until merged.
- 08:52 coordinator (CLI, started 08:44): baseline `halloween` @b16b5544, lint OK, tests 1345 passed / 0 failed.
  Hand-over verified: briefs, lane files, hooks committed and pushed (origin/halloween = local), six worktrees at
  b16b5544 with brief + lane file + hook, six lane Studio windows + the Team Create window in `list_roblox_studios`,
  Rojo 34872 serving `halloween` with live sync proven (probe comment read back in Studio, then reverted). Lanes
  started 08:43 (73 min late): new times posted in every lane file (gate 1 10:00, gate 2 11:15).
- 08:47 hw-map's Rojo had panicked at 08:44 on a Claude temp file (`Config.luau.tmp.<pid>`, change_processor.rs:172);
  could not reproduce with plain tmp+rename writes. Started `tools/halloween/rojo_watchdog.sh` (restarts any of the
  7 servers within 10 s, log `shots/coordinator/rojo-watchdog.log`); map restarted 08:47, Justin asked to Connect.
- 08:50 resize helper: System Events reads Terminal windows (Accessibility OK) and CoreGraphics reads Studio titles
  (Screen Recording OK), but all 7 Studio windows are full screen in their own Spaces, so AX sees 0 windows; Justin
  asked to exit full screen. cliclick installed (/opt/homebrew/bin/cliclick).
- 07:50 desktop session (hand-over): the briefs, lane files and hooks committed and pushed on
  `halloween`, the six worktrees fast-forwarded to it, the six lane Studio windows opened.
  Verify it at the 07:30 Progress line; do not redo it.
- 09:21 Gate 1 page published (private): "Halloween Gates" https://claude.ai/artifact/R2zt2CDfJeU5wuJp7VvMXA (slug c2a2bdc0-a441-4a0c-8479-0585a4bd07ad, v 1793193675-635a); builder `~/Desktop/8ball-refs/halloween/shots/coordinator/gate/build.py gate1|gate2`. Five asks to Justin: icons, event text, title, store schedule yes, gui's +0% pill.
- 09:55 Merged core interface 2 (7f01d27b), sys 4cdf5620, gui f2562efb -> 82ab885c; review workflow wf_209d4f07-82b (9 agents): 18 confirmed findings, none blocking with switches as they are; posted to each lane (core 6, sys 5, gui 5). Hand-resolved additive conflicts: SaveSchema/save_schema_test (core vs sys Badges), Ranking requires. Lint OK, 1,404 tests, Studio play clean (pill +120%). Pushed before the Studio check (order slip; check passed). Release checklist must carry: gui's Soft-step VIP confirmation fix; core's EventButton boot error and pad blur before Halloween.Enabled tiles show at 19:00.
- 11:36 Merged cues-a 83e876db (drop 3 37573b2c through ed8b7ca3: cue bodies, Bodies.Enabled, Candy Corn + Jack-o'-Lantern out of draft, Upright, analytics, Aim-fade), core 3c4b87aa (READY 10:16: menu, tile, quests, Spider, packs, art, funnel), sys c5b6b607 (FINAL fe78db7a) and gui 3438ea94 (FINAL 1dc99f84) -> `halloween` @537270fd, pushed. Only conflict: tools/upload_manifest.json (union, 984 rows, sort_keys). Lint OK, Main.client headroom 12, 1,436 tests, Team Create play console clean (only the old 203785492 lines), tile + Rush chip + pill +120% seen (shots/coordinator/merge_537270fd_lobby.jpg). Review workflow wf_055b7a55-6ba runs after the push (see Assumptions). Lanes told (Status line in all six; cues-b by message).
- 11:39 Gate 2 page published on the same artifact (v 1793201977-1533): 127 lane shots, the six gate-1 asks still open + a 7th (keep the lanes' four OVERRULED calls?). Justin back at 11:33.
- Late: the coordinator stopped at 09:51 for Justin's gate-1 answers and sat idle until 11:30, so drop 3 (MERGE NOW 09:45) went in 1 h 50 min late and cues-b waited on it. From now on a stop for Justin keeps a background watch on lane READY lines.
- 11:49 Merged core de236025 (Progression.quiet counts the NEW CUE! card and end screen) + cues-b a431419b (Broom, Cat, Spider out of draft) -> @64085ab2, pushed; cue_skins_data.py clean (66 skins, 28 pieces); 1,441 tests; Team Create play clean.
- 11:50 Justin's answers (gate 1/2), in his words in the transcript:
  1. Icons OK: set them automatically each hour (5H at 14:00 ... LIVE at 19:00), LIVE for a day, then the plain icon (19:00 Oct 29).
  2. The event already exists (his own "??? HALLOWEEN UPDATE", id 3257813357457179184): fix only the times (it said 17:00 EDT to Nov 1 18:00).
  3. Title: no countdown title. At release he adds the pumpkin emoji by hand, nothing else.
  4. Store schedule yes, minus 2 and 3.
  5. The zero-boost pill a bit dimmer, plus a restyle: no background, green "Money Boost: +XX%", orange "Candy Boost: +XX%" -> hw-gui.
  6. Badges: fine that they're made. He dislikes the icons and some names -> hw-sys asks him directly.
  Plus: the five cues "look terrible ... nothing like Beta Cue, Firework Cue": redo or improve -> both cue lanes, last READY 16:00.
- 11:55 Icon route test passed (identical copy 108723548670554 set and confirmed by GET, original 123614794049673 back). Event times PATCHed: 2026-10-28T23:00Z to 2026-11-04T00:00Z (200, title and text unchanged; tools/halloween/store_page.py event-times). icon-schedule --go running under caffeinate (pid in store/icon-schedule.out, log store/log.txt), last step plain at 1793314800.
- 11:55 Review wf_055b7a55-6ba (8 agents) of the 11:36 merge: no blocker. cues-a 1 should-fix (ghost body on a Lower-effects toggle) + 1 minor; core 6 minor; sys 1 minor; gui: the four 09:55 items were never fixed (my 11:36 merge message said they were; corrected here) -> sent back. All as Status lines in the lane files.
- 11:55 Map CONTRACT CHANGE approved (3v3 cloth (88,176,32), PLAN updated); map READY 7fd462cc in trial merge (tests + review running).
- 12:16 Map review (agent): the throne built twice on a server starting during Live (confirmed in Studio: 2 thrones, 2 Kings) -> map fixed it in 88e9cceb (HalloweenMap.Once); Studio after the merge: 1 and 1. Finding 2 (LocalSearch.isPromised missing) was fixed in 39815514.
- 12:30 Justin, the King (option 2, his words in the transcript): a timed visitor in the open middle, 10-15 min, rewarded well (money/Candy/XP), 1.5x size, a solution for full tables. Design sent to map + core: UTC :15 and :45 for 12 min, server-synced (Rules.kingWindow), a top timer in core's Countdown pill, the King's line when no 1v1 table is free (no private servers), one paid win a visit: +150 Candy, +$2,500, +100 XP (Ranking.addXp), behind Boss.Mode ("Throne" fallback = move forward of the boards). READY target 15:00.
- 12:31 Justin: Q7 all yes (pickup quests 15/30/50 with a pacing check; play-time counts match and lobby: core says it already did; ActiveGate now needs the day's first real match). Badges: sys applied his names, 2 badges off, v2 icons uploaded (moderation).
- 12:37 Merged + pushed through @7be001ed: map 88e9cceb + 623d0051, core 1361de6d, sys 57bc2b91, cues-a 66af67b0 + fec0cb91, cues-b 0e3569b6. Caught: cue_skins_data.py in the main checkout rewrote shipped Looks (Beta, Kitsune, Dragon); discarded, cues-a made it deterministic (fec0cb91), regen now clean.
- 12:38 Team Create, Edit: build_cue_templates with ONLY = CandyCornCue, JackOLanternCue, WitchBroomCue on @c55860a6: 3 skins rebuilt, 61 other templates untouched; 8 pieces (candy_corn 4, candy_corn_aura 6, jack_o_lantern 6, jack_o_lantern_aura 11, jack_o_lantern_pocket 4, witch_broom 6, witch_broom_aura 19, witch_broom_pocket 13), no problems, 19 other pieces untouched. Re-run for all five after the Cat/Spider reworks.
- 12:52 Justin (his words in the transcript): (1) double-check that the King reward is fair to the economy and progression (wf_bb7a015a-674 running); (2) the five cues look alike and reuse the ribbon VFX: no ribbons, a unique hand-made effect per cue (sent to cues-a: Jack, Candy Corn, and now the Black Cat; READY 16:00); (3) the Broom's bristles are far too small: remake the Broom as its own model, not the cue mesh (Blender, generate_3d, ChatGPT images allowed; sent to cues-b with the Spider; Spider 16:00, Broom 16:30); (4) Studio is set to All Desktops. Team Create is still fullscreen, so device resizing waits for Ctrl+Cmd+F.
- 12:57 10:30 Requests pass 1: no lane asked for an Edit-mode build (map builds the throne, decor, props and table looks in code; `git grep EventProps` in the lane files: none). The only place work is the cue templates (12:38, again after the reworks). Nothing built, so there is no fingerprint to compare.
- 12:58 Merged map 656825bf alone (c1bc88e1): the timed King behind `Boss.Mode`, Mode still "Throne". **Held: ee17dc24** (Mode = "Timed") until core's `CandyService.bossWon(player, visitStart)` with no cooldown in Timed lands; with the flip but without core's change he pays once and then refuses with KingCooldown (map's 12:54 note). Map also saw the result card show the King as the PC robot portrait (the match bar shows the pumpkin): sent to core/gui.
- 13:09 King reward fairness (wf_bb7a015a-674: economy, Candy pacing, skeptic; all "fair"): KEEP +150 Candy, +$2,500, +100 XP once a visit. King tries replace real matches, so an hour of chasing pays about what normal play pays (money -8% to +7.5%, XP -11% to +1.5% Bronze to Expert, Candy +1% to +23%); at most 2 paid wins an hour, KingVisit saved so a server hop pays 0; trading off, so alts pass nothing; about 1-3% of daily money sources gross, about 0 net. No XP fade and no daily cap (watch HwKing for >10 paid wins a day). Two follow-ups asked: map, a player who already won this visit goes behind every unpaid player in the line; core, the paid-win toast names all three rewards, and King matches count for the Matches and Balls quests (`Config.Halloween.Boss.CountsForQuests`). Day-1 reads: KingWin vs KingChallenge by tier (the win shares are bot vs bot), King match length, the line length.
- 13:16 Merged + pushed through @e1c9ca26: map 092ab2c9 (cherry-pick 23e289f4, the King's pumpkin portrait on the result card), core fa17a763 (the visit reward, KingVisit save mark with old-save test, the King timer pill), map ee17dc24 (**Boss.Mode "Timed" is on**), cues-a 95325e31 (the Jack's signature, no ribbons). cue_skins_data.py clean (66 skins, 30 pieces). Lint OK, 1,467 tests. Team Create Edit: build_cue_templates ONLY = JackOLanternCue: 1 skin rebuilt, 63 untouched; 3 pieces rebuilt, 24 untouched; fingerprint diff only jack_o_lantern_aura. Play: HwTimeOffset moved to :15 -> throne in the middle at (0,8.2,3.4), the pill "PUMPKIN KING IS HERE! 11:30", KingSpawn funnel event; the Jack in the lab (back + stand) loads; console clean (the known 203785492 and Badges lines; core's 1593733/81504106 lines did not appear). Shots: merge_c1bc88e1_throne.jpg, merge_e1c9ca26_timed_king.jpg, merge_e1c9ca26_jack_lab.jpg.
- 13:18 Merged + pushed @4cde411a: map 4ebc50cb (this visit's winners wait behind every unpaid player in the King's line, Timed only; rejoin gap noted by map: PumpkinKingBeat is a server attribute, so a winner who rejoins is ordered as unpaid; core still pays once, left as is). Lint OK, 1,468 tests. Team Create Play: :15, KingChallenge from 6 studs -> Seated (Bronze>Gold), the pumpkin portrait in the match bar, console clean. Shot merge_4cde411a_king_match.jpg.
- 13:23 Merged + pushed @7a4119a7: cues-a 5be5b0a9 (the Candy Corn's signature, no ribbons: kernel fountain off the tip, hopping kernels, sugar crystals, the wrapper popping). cue_skins_data.py clean, lint OK, 1,468 tests. Team Create Edit: ONLY = CandyCornCue: 1 skin rebuilt, 63 untouched; 2 pieces rebuilt, 25 untouched; fingerprint diff only candy_corn_aura. Play lab (Candy + Jack, back and stand) loads, console clean. Shot merge_7a4119a7_candy_lab.jpg. My read, sent to cues-a: in stills both reworked cues now read far quieter than the Firework; the signature effects need more size and brightness to read at a glance (no ribbons back). Justin to judge.
- 13:29 Merged + pushed @ff30c0c0: core 3bd371c0 (the paid win's gold line "Pumpkin King beaten! +150 Candy +$2,500 +100 XP", the repeat line) + da3b5b25 (King matches count for the Matches and Balls quests, `Config.Halloween.Boss.CountsForQuests`). Lint OK, 1,469 tests. Also RELEASE.md (c6306d32) and the PLAN King row (3a2d2827) now describe the timed King. Team Create Play, a real paid win (:15, KingChallenge, the King's bot surrenders through PoolMatchQA): Money 8,100 -> 10,600, Candy 0 -> 150, RankXp 100 -> 200; HwKing Paid, KingWin Paid, HwCandy Boss, PumpkinSlayer badge, funnel 3_FirstCandy and 4_Cue150; the result card shows the pumpkin portrait; console clean. The 4 s gold line had faded before the capture while the card still reads "No XP" / Total $0: asked core to keep the line up while the card is open. Shot merge_ff30c0c0_king_paid.jpg. Fresh-player run on this build delegated to hw-gui (mock save; Team Create's Studio save is Justin's and is not wiped).
- 13:34 Merged + pushed @bcb0e2db: cues-b a18478af (the Witch's Broom remake: a real broom body, 5 parts / 9,144 tris, bristle head 3.3x; aura without ribbons: moons, stars, bats, spell sigils, potion smoke; and the Spider without ribbons: self-spinning web wheels, silk droplines with dew). Held their 568de991 first: it carried the superseded WIP Cat (eb95993d); cues-b made the branch cat-neutral (a18478af) and the merge's game data touches only witch_broom* and spider* (cue_skins_data.py clean, 66 skins / 31 pieces). Lint OK, 1,469 tests. Team Create Edit: ONLY = WitchBroomCue, SpiderCue: 2 skins rebuilt, 63 untouched; 6 pieces rebuilt (spider, spider_aura, spider_pocket new to the place; witch_broom + witch_broom_aura replaced; witch_broom_pocket identical), 24 untouched; fingerprint diff only those. Play lab: both load (back + stand), console clean. Shot merge_bcb0e2db_broom_lab.jpg. Then @663de787: cues-b 7bae1ea4 (the straw part `Outline = false`, ignored until Cues A's runtime key; cue + halloween tests 170 passed). Justin's verdict on the Broom still open.
- 13:40 Merged + pushed: core d1f8dbd8 (the King's reward line stays while the result card is open; 8 s without one; 90 s cap). Lint OK, 1,469 tests. Team Create Play, a second visit's paid win (:45): the gold line "Pumpkin King beaten! +150 Candy +$2,500 +100 XP" over the open card at 10 s; Money +5,000 = the King's 2,500 + the track's 300-Candy step (HwTrack 300 Money), Candy +150, XP +100; console clean. Core's "JackOLanternCue's body piece jack_o_lantern is not in ReplicatedStorage.CuePieces" line (CueStickBuilder.luau:227, the King's bot cue is the Jack) comes from its lane place, which lacks the Jack's Edit-mode template; Team Create has it. Shot merge_king_line_over_card.jpg.
- 13:43 Merged + pushed: cues-b 76cdfa8e (the Spider's webs and silk read on the bright floor; new spider_aura 112575234442239). cue_skins_data.py clean, lint OK, 1,469 tests. Team Create Edit: ONLY = SpiderCue: 1 skin rebuilt, 64 untouched; 3 pieces rebuilt, 27 untouched; fingerprint diff only spider_aura. Play lab loads, console clean. Shot merge_spider_readability_lab.jpg.
- 13:43 13:00 fresh-player run (delegated to hw-gui, mock save, halloween @1908738e; shots `shots/hw-gui/fresh1319/` 01-11): tutorial shows no Halloween button, popups, badge toasts or King pill; after Skip the boost lines, the Rush chip, the HALLOWEEN tile and the King pill ("IN 13:17", "IS HERE! 11:20" at :15); first match WINNER, 143 Candy saved; popups BRONZE!, Daily Rewards, Invite, lobby; no game-code error or warning. **Bug (core):** the first match's "+143" Candy chip is hidden by HudFocus when Daily Rewards opens 0.4 s after it pops, so a new player never sees their first Candy; sent to core. Phone pass only partly emulated (the lobby HUD has no Root frame); the real device sweep still waits for the Team Create window to leave fullscreen.
- 13:55 Merged + pushed: core 2485ee30 (a match's Candy chip makes CandyToast.busy() true for its 2.05 s flight, so Progression.quiet holds Daily/Invite until the first Candy lands; core proved it on fresh saves). Lint OK, 1,469 tests. Team Create Play boot: HalloweenToast present, the new module synced, console clean.
- 14:00 Store: the 5H icon 82872198740147 set by the schedule job, confirmed by GET, thumbnail Completed (log.txt 14:00:00-14:00:26). Progress 14:00 ticked (no countdown title: Justin adds the pumpkin by hand at 19:00).
- 14:06 Merged + pushed: cues-a b5633adc (the Black Cat's signature, no ribbons: the tail flicks, three shadow cats race the shaft, gold claw swipes, embers, the collar light) + 4d759889 (CuePiece: a part row with Outline = false goes under a sibling Model the Highlights skip; its parts stay in the rigid list, so fades and hiding still reach them; the Broom's straws lose the violet fringe) + bea11fbb (a skinned rig's invisible root shrunk to a dot, no gold box round the Cat). cue_skins_data.py clean (66 skins, 32 pieces), lint OK, 1,469 tests. Team Create Edit: ONLY = BlackCatCue: 1 skin + black_cat + black_cat_aura built (new to the place), 65 templates and 30 pieces untouched, fingerprint diff only those. Play lab: the Cat and the Broom load, the straws without the fringe, console clean. Shot merge_8fdbdd3e_cat_broom_lab.jpg. **All five Halloween cues are now merged and built in Team Create.**
- 14:07 Team Create Play, a real solo match with the Witch's Broom (/givecue, EquipCue, QueuePad_03, /solo, the break through PoolMatchQA): the gnarled handle in hand on the aim line (the head fades for the aiming owner), the whole broom in the PULL bar, the break's trail (white streak, moon, bat), the avatar holding the broom with its bristles; HalloweenCueEquipped, Cues5 and BroomRider badges (would award), console clean. Shots match_broom_aim.jpg, match_broom_break.jpg. Progress 14:30 ticked (merge pass 2 + ONLY builds for all five + lab + a match).
- 17:52 Justin (17:45, back): the release can go out any time tonight, not tied to 19:00; drop the store icon's STARTS IN badge; focus on robustness. Done: the countdown job stopped, the plain icon set and confirmed (121071839544374). Robustness pass sent to all six lanes (READY by 19:15) plus two independent read-only reviews (server core files, client core files). Checked here: the fresh-player run PASS (hw-gui 17:48 on 16784c7c); Team Create Edit has no test objects or attributes, all five skins and 13 pieces; Rojo byte-exact at the tip; Play: Live, console clean, Halloween adds no particles (pad sparks and back cues are the old load), HalloweenMenu 1,126 instances. Docs cc887cc4, ce76959b.
- 18:04 Merged + pushed @c2e5fcdb: cues-b e4032dc0 (robustness: the Spider's droplines clear of the cloth; cost, Lower effects, pocket cleanup, ids all checked). cue_skins_data.py no-op, lint OK, 1,469 tests. Team Create template build ONLY = SpiderCue waits for Justin's playtest (Rojo 34872 not connected: Justin reconnects). Server review (independent, read-only): nothing critical; joins, matches, saves, receipts and every switch-off clean; 4 low/medium findings checked against the code and sent: core (the 5 s hwActive commit wakes Tutorial/LuckyBlock listeners; bought Candy converts as earned money; Candy after Converted; Bootstrap pcall hardening as a Request), map (CandyDrop's report re-creates Funnel's log after leave). Pre-publish baselines in RELEASE §7; error baseline V1615 in analytics/watch.
- 18:27 All six robustness passes merged (map 0a8c9f4c, sys 7e554d60, gui ad26e517, cues-a 9260eb32, core 866cdec0 with a CandyToast conflict resolved keeping both, Bootstrap CandyService guard d0327035); lint OK, 1,477 tests, pushed. Client review: the Halloween HUD setups and HubCorners requires unguarded (fixed by core and gui), the body-cue fallback (cues-a), the King banner in the tutorial and Main's MapClient wait (map). Justin ~18:20 after trying the cues: models before the release; redo Spider and Cat entirely, Candy Corn's tip and kernel fountain wrong, Broom sigils satanic, the night sky dull and the moon a sun. My calls (to confirm): Phantom replaces Candy Corn (cues-a), Bone replaces Black Cat (map), from his M3 board; concept card first, side-by-side before READY. cues-b: Broom sigils then the Spider to C1. map: night sky + crater moon first.

## Shared-file changes

None yet. Only if Cues A has no ONLY filter by 14:30: that one small commit to
`tools/build_cue_templates.luau`, listed here.

## Requests

**Justin at 16:30** (what only he can do; updated 12:58):
1. Now, when free: Ctrl+Cmd+F on the "[EMOTES] CRAZY 8 Ball" Studio window (leave full screen) for the device sweep.
2. Look at and approve the reworked cues (Jack, Candy Corn, Black Cat, Spider) and the new Broom model as their side-by-sides arrive (paths in chat).
3. The King's reward: the fairness numbers in chat (approve or change).
4. 17:00: File > Save to File As `place/8ball.rbxl` in Team Create if System Events cannot reach the menu (fullscreen blocks it).
5. Publish the test place build I hand over (optional), then at 18:30 walk RELEASE.md §1 with me, File > Publish to Roblox, restart servers "outdated only".
6. 19:00: rename the game with the pumpkin; post the Discord text (RELEASE.md §8).

**My calls until then** (logged under Assumptions as made): merge order and the Timed flip only with core's reward; cut anything unfinished at 16:00 by its switch; the cue template build in Team Create with ONLY; the store icons by the schedule job.

## Assumptions

- 11:36 Merged and pushed cues-a/core/sys/gui once lint, tests and the Studio check passed, before the review workflow returned. Cues-b had been blocked on drop 3 since 09:45, every new feature sits behind a Config switch, and nothing publishes before Justin's 18:30 walk-through. Review findings go to the owning lane as Requests, and any blocker is fixed and merged before the 17:00 freeze.

## Gate shots
