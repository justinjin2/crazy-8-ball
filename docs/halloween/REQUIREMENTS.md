# Halloween update: every requirement (source of truth)

Written 2026-10-28 06:30 EDT from Justin's messages. Every lane brief points here.
Before you mark a lane done, check that each row it owns is met.
Status: `open` = not built, `decided` = design agreed, `built`, `verified`, `cut` (with reason).
Quotes are Justin's own words.

## 0. Ground rules for this run

| # | Requirement | Status |
|---|---|---|
| R0.1 | Release **today Oct 28**. 5 PM EDT was the target. Justin added at 06:30: "if you think this requires more time like 6-7-8pm, i dont mind pushing it a few hours back ... as long as it gets released by end of today still in high quality". | built: the event goes Live by clock at 19:00 EDT (`Config.Halloween.StartsAt` 1793228400, contract test); the publish is Justin's at the 18:30 walk-through |
| R0.2 | Build tasks finish by about **3 PM** (or 2 h before the chosen release time), so Justin gets 1-2 h to playtest before it goes public. | built: builds done 14:06 (the cue reworks Justin asked for at 11:50 and 12:52 ran that long), before the 17:00 stop; but the Mac slept 14:10-17:41, so the hand-over for Justin's 17:00-18:30 playtest started only after 17:41 and his window shrank to under an hour |
| R0.3 | Runs in the **Claude CLI in the terminal**, not the desktop app: 3 lane terminals + 1 coordinator = 4 windows (a 5th is allowed for badges if needed). Give Justin clear move instructions before starting. | verified: 7 CLI windows (coordinator + 6 lanes, §9) ran from 08:43; hand-over checked 08:52 (coordinator log) |
| R0.4 | Recommend the effort level (ultracode? max?) and when to use Opus 5.5 vs Fable 5.1 for hard or visual tasks. Usage limits don't matter ("you can use all of this week's usage"). | decided (§9) and used: coordinator Opus 5.5 ultracode, lanes Opus 5.5 xhigh, cue lanes Fable 5.1 xhigh |
| R0.5 | Test every new GUI and feature on **phone, tablet, console and PC** without Justin switching devices by hand. Find a way. | built, emulated only: Root-frame sizes (844x390, 1024x768), `hud_layout_test` and GuiQA "pad"; the real phone/iPad/TV sweep was NOT done (the Team Create window stayed fullscreen) |
| R0.6 | Feasible, optimized, bug-free on console/mobile/PC, little tweaking after, done in time. AI runs on its own after the first approval. | built: lint OK and 1,469 tests at every merge, Team Create console clean, every feature behind a Config switch, map within its budget (47,786 of 60,000 tris); no real-device check (see R0.5) |
| R0.7 | Push back when it gives better results. Interview Justin about anything unclear before implementing. | done: lanes' four OVERRULED calls kept by Justin at gate 2; coordinator flagged the reworked cues as quieter than the Firework (13:23) |
| R0.8 | Justin is awake for the next ~5 h (from 06:15) and can test short gates any time. Do as much as possible without him and ask only when his input is needed. | done: gates at 09:21 and 11:39, answers 11:50 / 12:30 / 12:52; the coordinator sat idle 09:51-11:30 waiting on gate 1 (logged) |
| R0.9 | Don't lose detail as the conversation gets long (this file, the plan page and memory hold it all). | done: this file, PLAN, the lane files, RELEASE.md and memory hold the decisions |
| R0.10 | Before starting the Halloween work, report back how Candy works: how much per Candy and per win. | done (answered in chat and on the plan page) |

## 1. Event core (from the first request plus answers)

| # | Requirement | Status |
|---|---|---|
| R1.1 | Event length **6 days, ends Tue Nov 3** (Justin: "event length is good"). If release moves later, keep the end time or shift it (to decide). | verified: `EndsAt` 1793750400 (Tue Nov 3 19:00 EST) in the contract test; the store Experience Event set to 23:00Z Oct 28 - 00:00Z Nov 4 (11:54, by API) |
| R1.2 | Halloween currency (Candy) + quests to earn the cues. Quest board ideas: pocket XX balls, win XX games. Enough fun, achievable, rewarding content for 5-6 days. | verified (Team Create 13:29 and 13:40: Candy from King wins, the 300-Candy track step paid); 24 quests on 6 day boards, CLAIM checked by core in Studio |
| R1.3 | Cues never come back after the event. | built: the five rows are Exclusive with `Event = "Halloween2026"`, granted only by the track and the Spider clock; no grants once Converted (core b29a5b16). Since the lineup of 2026-10-29: by the track and the Pumpkin King's drop (the Jack-o'-Lantern); the Spider clock is off |
| R1.4 | Leftover Candy converts to money at **$10 per Candy**, with a GUI arrow showing what it became. Auto end. | built (core): at the end quests are claimed, then all Candy becomes money at $10 each once per save; end screen with the counting arrow and COLLECT; Lune conversion tests; core's Studio `/hw time end` |
| R1.5 | **2 Robux Candy packs** ("candy packs are good"). Draft prices 49 R$ and 149 R$. | built (core 9e53700c): Candy500 3723285204 (49 R$) and Candy2000 3723285208 (149 R$) on sale only while Live, replay-safe (StoreQA); no real purchase tested |
| R1.6 | **In-game countdown starting 30 min before** release, then everything switches on at release time. | built (core): the countdown pill 18:30-19:00, then "THE HALLOWEEN EVENT HAS STARTED!" and the tile at 19:00 (core's Studio `/hw time countdown`) |
| R1.7 | **Automated update countdown on the game icon/thumbnail**, starting about 5 h before release (Justin referenced an "image #3" that did not come through). Or use a Roblox feature if one exists. Set it up when we get there. | verified: the icon schedule job set 5H at 14:00 (confirmed by GET); 4H and 3H were skipped while the Mac slept 14:10-17:41; 2H set 17:42 (confirmed); 1H 18:00, LIVE 19:00 and the plain icon 19:00 Oct 29 still to run (the Mac must stay awake) |
| R1.8 | Clear Halloween icon/button on the right side of the screen. | verified: the HALLOWEEN tile in the right-side slot (Team Create 11:36; the 13:19 fresh-player run saw it after Skip) |
| R1.9 | New game icon (an edit of the current one) + Halloween thumbnail. | built (icon only): the edited Halloween icons (countdown, LIVE, plain) approved and on the schedule; no Halloween thumbnail was made |
| R1.10 | Candy Rush boost: clear **bottom-left chip "x2 Candy" with a countdown timer**. | verified (Team Create 11:36; the 13:19 fresh-player run); superseded: the chip says "CANDY RUSH mm:ss" (no "2x"; the orange Candy Boost line shows how much) and sits above the boost lines (§9) |
| R1.11 | Track gifts between cues: Justin didn't understand Q4. Explain it simply and propose (more cues means more rewards between quests). | verified (Team Create 13:40: the 300-Candy step paid $2,500): spins and money between the cues on the 11-step track (PLAN §2) |
| R1.12 | Halloween abilities: optional idea from the first request. The plan said no new ability. | cut: no Halloween ability (the plan put the work into the cues) |

## 2. Event cues: 5 cues, all Exclusive, gold standard for future cue reworks

| # | Requirement | Status |
|---|---|---|
| R2.1 | **Candy Corn** (new 5th cue): starter of the track. Candy corn texture + candy corn aura, smaller trail and finisher. Visual tier about **Rare-Epic**, still unique in model, trail, finisher, aura and VFX. | verified (Team Create 13:23: ONLY build + lab, reworked without ribbons: kernel fountain, hopping kernels, sugar crystals, the wrapper pop); Epic effects; Justin's look still open |
| R2.2 | **Jack-o'-Lantern**: no candy corn on it. Pumpkin auras. Finisher = **laughing jack-o'-lantern**. Tier about **Epic-Legendary**. | verified (Team Create 13:16: ONLY build + lab, own signature without ribbons; the finisher is the laughing jack with the library laugh); Legendary effects; Justin's look still open |
| R2.3 | **Black Cat** (replaces Bone): cute (especially appealing to girls), detailed animated cat VFX/auras, colours clearly different from Spider (not another black cue). Tier about **Legendary-Mythic**. Unique model twist. Concept art first. | verified (Team Create 14:06: built + lab; cues-a played it in a real match 14:02): tail flicks, shadow cats, gold claw swipes, no ribbons; Mythic effects; superseded: Black Cat rev 3 (§9); from the aiming camera above the shadow cats read as dark bars |
| R2.4 | **Spider** (replaces Phantom, which already exists in the game): cool black arachnid cue with extra model extensions, not creepy for people with arachnophobia, "kinda like hela's helmet from thor". Tier about **Legendary-Mythic**. Concept art, then **Justin's approval before building**. | verified (Team Create 13:34 and 13:43: ONLY build + lab, web wheels and silk droplines, no ribbons); concept rev 2 approved before building; Justin's look still open |
| R2.5 | **Witch's Broom**: last and hardest prize, tier about **Mythic-Secret**. Unique model, doesn't have to follow cue conventions, as long as the shape roughly matches so holding looks right. Keep the little **witch-hat charm, and make it sway**. | verified (Team Create 14:07, a real solo match): a new broom model (5 parts, 9,144 tris, bristle head 3.3x), the hat charm on Sway joints; Justin's verdict on the Broom still open |
| R2.6 | Playtime cue at **3 h 01 m** ("31"), not 3 h 06 m. (Spider took Phantom's slot as the playtime cue: confirm.) | verified: the Spider is the active-play cue at 10,860 s = 3 h 01 m (`Config.Halloween.Spider.Seconds`, contract test; core walked the clock past it in Studio). **Superseded** by the designer's lineup of 2026-10-29 03:59: the Spider is a track cue at 4,500 Candy and the playtime clock is off (`Spider.Enabled = false`); active time still fills the "Play N min" quests |
| R2.7 | The **top track cue** must be hard but reachable: at least **100+ owners by the end of the event** ("generously rewarded while maintaining status and exclusivity for grinders"). Was the Broom; since the designer's lineup of 2026-10-28 evening the top cue is the **Halloween Sword** at 7,000 (the Broom moved to 2,000). The lineup of 2026-10-29 keeps it there (track cues 500 Pitchfork, 2,000 Broom, 4,500 Spider, 7,000 Sword; the Jack is the King's drop). | staged (hw-core 756e75bb): the Sword at 7,000 Candy on the track, the same step the Broom had, so the 12:25 pacing holds: 60 min a day ends 255 short, about 65 min a day or a pack reaches it (the King's +150 a visit came later and adds more); owner count only measurable at the end (funnel 7_Cue7000, was 7_Broom) |
| R2.8 | The rarity ladder follows the track: the first cue must not flex like the last one. | built: effects tiers follow the track, Epic, Legendary, Mythic, Mythic, Secret (Catalog.luau:258-262) |
| R2.9 | Every cue: unique model (not the standard cue shape; tips can differ), unique trail, finisher, aura, VFX, animation. **Better than every current cue**: flipbook animations, popping auras, heavy VFX. Use any tools needed. | built: all five reworked without ribbons (Justin 12:52), each with its own model and signature; the coordinator's read (13:23): in stills they read quieter than the Firework; Justin has not yet judged them better than every current cue |
| R2.10 | Concept art for Spider, Black Cat and Broom (plus the revised Jack-o'-Lantern and the new Candy Corn), approved before building. | verified: all five concepts approved after revisions (§9, PLAN §3); the 12:52 no-ribbon reworks were built from them without a new approval round |

## 3. Map

| # | Requirement | Status |
|---|---|---|
| R3.1 | Temporary spooky map: sky, ambience, trees/plants/decor replaced. Concept art "looks pretty good". | verified (Team Create plays since 12:15 boot Live: night rooftop, dead trees, strands, props; map's flip test Before/Countdown/Live/Ended) |
| R3.2 | Table colours still show the mode: **1v1 purple, 2v2 orange, 3v3 green** (colours pop and look good). | verified: orchid (185,90,230), charcoal (90,94,102) with orange glow, toxic green (88,176,32) in the contract test; rendered contrast checked by map; superseded: 2v2 charcoal + orange glow, 3v3 green changed 11:55 (§9) |
| R3.3 | **Custom haunted table models**: yes, implement. | built (map); superseded: black frames + decor kits (Orchid, Pumpkin, Toxic), no new table mesh (§9) |
| R3.4 | New **night mode**: not too dark, a beautiful purple sky, **same visibility as day and sunset**. Maybe permanent later. | built (map): the Night light takes Day's slot while Live, roof brightness L* 0.91 of Day's; not checked on a real phone screen |
| R3.5 | Lobby candy drops (pickups). | built (map): candy pieces near eligible players, +1 each to CandyService, 40 an hour cap; pickup quests 15/30/50 |

## 4. Pumpkin King

| # | Requirement | Status |
|---|---|---|
| R4.1 | Explain how he works: event NPC that spawns now and then, or always standing there? Hold E to challenge? Private server? Difficulty? Can you keep playing him? | built; superseded: a timed visitor (designer 12:30): UTC :15 and :45 for 12 min in the middle of the roof, hold E / tap / X to challenge, the King's line when no table is free, no private servers, replay any time |
| R4.2 | He is there **on day 1** and new players see him **in their first session**. Some exclusivity but not too rare. Everyone can play him. Maybe "respawns in X minutes/hours" after he's beaten. | verified (Team Create 13:16-13:29: he arrives at :15, a challenge seats, a paid win; the 13:19 fresh-player run saw the King pill after Skip); a first session can still fall between visits (the pill counts down to the next one) |
| R4.3 | Make his model: pumpkin head, his cue, aura, animation pose. | verified (Team Create 13:16-13:29: pumpkin-head King at 1.5x, his look, the Jack as his cue, the pumpkin portrait in the match bar and on the result card) |
| R4.4 | Bonus Candy for beating him + a **candy explosion animation**. | verified (Team Create 13:29 and 13:40: a paid win +150 Candy, +$2,500, +100 XP with the gold line over the card; fairness checked 13:09); the candy burst is map's, lane-checked; superseded: the reward is once a visit (designer 12:30) |

## 5. Boosts HUD (permanent)

| # | Requirement | Status |
|---|---|---|
| R5.1 | Friend boost for Candy (Grow a Garden style **+XX%**), 20%/friend or lower (10%) so it can't be abused with 10 friends. | verified by test: +10% a friend, max 4, on Candy (contract test, friends capped at 4; §9) |
| R5.2 | **Friend boost for money too**, about +10% per friend (as in Steal an Egg, Grow a Garden, Slime RNG). Check it won't inflate the economy. | verified by test: +10% a friend, max 4, on match money only (money_test; gui's Studio pay check +20% to +40% with 2 friends); estimate about +2 to 2.5% match money (DECISIONS) |
| R5.3 | VIP shows its boost (2x). One format everywhere: all multipliers or all percentages. Boosts stack. | verified (Team Create 12:15, the boost lines shot): VIP shows +100%, percentages everywhere, boosts add; superseded: no pill background, green "Money Boost: +XX%" and orange "Candy Boost: +XX%" text (Justin 11:50) |
| R5.4 | **Group join: +10% permanent**. | verified: the existing Group +10% (GroupBoost) with its own row on the card; counted in the lines seen in Team Create |
| R5.5 | The boost pill sits **next to the money pill**, and the invite button moves aside. It **must fit on mobile**. | built; superseded: the lines replace the VIP tag above money and Invite stays (§9); phone fit only by `hud_layout_test` and an emulated 750x311 frame, no real phone |
| R5.6 | Tapping it opens a tiny info card showing where each active boost comes from (group, friends, VIP). | built (gui): tap, click or A opens YOUR BOOSTS with each source; a real pad A press not checked |
| R5.7 | **Show a mock before implementing.** | done: built to the approved mock H1 |

## 6. Roaming during matches (permanent)

| # | Requirement | Status |
|---|---|---|
| R6.1 | Remove the invisible barriers: in-match players can **walk anywhere while waiting** for the opponent's shot. | built (sys, `Roam.Enabled` on): roaming 70 studs in the opponent's turn checked in the lane's Studio |
| R6.2 | While in a match they can't join another match (empty pads), can't use solo/bot pads (disabled), and anything else that would break. | built (sys): other pads refuse, the portal pad shows no dialog, lucky block Open refused "Busy" while roaming |
| R6.3 | On their turn they're **teleported back to the table**, however far away they are. | built (sys): home in 0.13 s on the player's turn; off the roof back at the table in 0.57 s |

## 7. Cue Preview (permanent, reusable)

| # | Requirement | Status |
|---|---|---|
| R7.1 | Click a cue to get a detailed preview: the **model**, plus the **trail and the pocket finisher**. | built but ships OFF: MODEL, TRAIL and FINISHER from My Cues and the Index; `Config.UI.CuePreview.Enabled = false` until a phone and controller check passes |
| R7.2 | A system and design that new limited cues and the Index reuse later. | built but ships OFF: one API `CuePreview.open(id, opts)` for the track, the Index and later limited cues |

## 8. Badges (permanent; not part of the event)

| # | Requirement | Status |
|---|---|---|
| R8.1 | Generic + special badges. "Welcome to Crazy 8 Ball" on first join. | built: Welcome on Roblox (`Config.Badges`, sys Studio award logs); the award queue verified in Team Create 13:29 and 14:07 |
| R8.2 | First win, counting the tutorial win so players see it right after the tutorial. | built: First Win counts the tutorial win (its "tutorial counts" text removed, Justin 12:20) |
| R8.3 | Win milestones 5, 10, 20 ... up to 500 or 1,000, each with its own name (novice, pro, 8 ball god ...). | built: Wins milestones up to 1,000 (Rookie, Contender, Hustler, Ace ... ; names per Justin 12:20) |
| R8.4 | One badge per new rank (Bronze, Silver, Gold ...). | built: one badge per rank (Justin OK with them; he asked for a fixed icon background, in the v2 icons) |
| R8.5 | First Rare, Epic, Legendary, Mythic and Secret cue. | built: first Rare, Epic, Legendary, Mythic and Secret badges, each named "... Find" (Justin 12:20) |
| R8.6 | Abilities badges (maybe). | built: ability badge on `UltService.Used`, solo practice skipped (sys 46b6ba78) |
| R8.7 | Rare/unique ones: **"Beat the Owner!"** = win a match against Painicane (544959133). | built: Beat the Owner (and Met the Owner) on Painicane 544959133, descriptions without his username |
| R8.8 | Collection: own 5 / 10 / 50 ... cues (not "full collection", because cues keep growing). | built: collection badges by cue count (Cues5 seen to award in Team Create 14:07; Super / Master / Grand Collector) |
| R8.9 | Win streaks: 3, 5, 10. | built: Streak3, Streak5, Streak10 |
| R8.10 | "Played in the 2026 Crazy 8 Ball Halloween Event". | built: Halloween2026 badge (its rule fired in core's Studio 11:42) |
| R8.11 | Existing players: they must get the badges they already earned. If that can't happen automatically, there must be a way. Check whether a burst of many badges is OK ("better later than never"). | built (sys): badges already earned are awarded from the save after the tutorial, queued one about every 3 s and held during pull reels (22 in sys's Studio check) |
| R8.12 | A good number of badges, and give Justin the **full list**. | verified: 50 live on Roblox (52 created, Tycoon and Part of the Crew disabled), list and v2 icons shown to Justin 12:18; icons partly still in Roblox moderation (3 of 50 approved at 12:31) |
| R8.13 | Built for longevity: room to add more, ideally an automated way to add badges later. | built: badges are `Config.Badges` rows; `tools/roblox_badges.py --sync` creates new ones and writes the ids back |
| R8.14 | Don't overthink it or spend too long on it. Use another terminal if needed. | done: one lane (hw-sys), finished 10:25, renames 12:20 |

## 9. Answers from the 06:50 interview (these settle the rows above)

| Row | Answer |
|---|---|
| R0.1, R0.2 | Go-live **7:00 PM EDT** (`1793228400`); builds stop 17:00; Justin playtests 17:00–18:30. |
| R0.3 | 7 windows: coordinator + 6 lanes (`docs/halloween/PLAN.md` §4). |
| R0.4 | Coordinator Opus 5.5 with ultracode; code lanes Opus 5.5 xhigh; the two cue lanes Fable 5.1 xhigh. |
| R0.5 | Studio window resizing (`tools/halloween/studio_size.sh`) + GuiQA "pad" in every lane; the coordinator also drives Studio's Device menu (screencapture + cliclick). Justin grants Terminal Accessibility + Screen Recording. |
| R1.1 | Ends Tue Nov 3 7:00 PM EST (`1793750400`). |
| R1.5 | 500 Candy / 49 R$, 2,000 / 149 R$; bought Candy counts all the way to the Broom. |
| R1.10, R5.3 | Pill shows summed %, Rush chip says "2x CANDY mm:ss". |
| R1.11 | Track gifts = spins + money between the cues (PLAN §2). |
| R2.1–R2.10 | All five concepts approved after revisions (PLAN §3): Black Cat rev 3, Spider rev 2, Broom rev 2, Jack and Candy Corn rev 1. |
| R2.6 | Spider = the 3 h 01 m active-play cue. |
| R3.2 | 1v1 orchid purple, 2v2 charcoal + orange glow (orange cloth hides balls 5/13), 3v3 toxic green. |
| R3.3 | Haunted look = black frames + decor kit (no new table mesh). |
| R4.x | Pumpkin King per PLAN §2. |
| R5.1, R5.2 | +10% per friend, max 4, permanent, money and Candy. |
| R5.5 | Pill replaces the VIP tag in the row above money; Invite stays (no room on a phone). |
| R8.x | All 52 badges created today (~4,700 R$ group funds, approved). Justin adds badge scopes to the API key. |
| — | Uploads of images, meshes, skybox, badge icons allowed without asking; no audio uploads. |
| — | The "Match prize" branch stays out of this update. |

Status updates (07:50): R0.3, R0.4, R0.5 decided (§9). R0.10 done (answered in chat and on the plan page:
~57 Candy a win, ~22 a loss, 400–475 an hour, $10 each at the end). Superseded by later answers: R2.3's
"cute, appealing to girls, not another black cue" (Black Cat rev 3 is tough, black, faceless), R5.5's
"invite button moves aside" (the pill replaces the VIP tag instead; no room on a phone), R1.10's
"bottom-left chip" (it sits above the pill in that same corner).

Statuses updated 2026-10-28 17:47 from the coordinator log (11:36-14:07), the six lane files and the code on `halloween` @16784c7c. `verified` = the coordinator checked it in Team Create or a test covers it; `built` = merged and lane-checked only. No real phone/iPad/TV sweep was done (emulated sizes only).
