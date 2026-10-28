# Halloween update: every requirement (source of truth)

Written 2026-10-28 06:30 EDT from Justin's messages. Every lane brief points here.
Before you mark a lane done, check that each row it owns is met.
Status: `open` = not built, `decided` = design agreed, `built`, `verified`, `cut` (with reason).
Quotes are Justin's own words.

## 0. Ground rules for this run

| # | Requirement | Status |
|---|---|---|
| R0.1 | Release **today Oct 28**. 5 PM EDT was the target. Justin added at 06:30: "if you think this requires more time like 6-7-8pm, i dont mind pushing it a few hours back ... as long as it gets released by end of today still in high quality". | open |
| R0.2 | Build tasks finish by about **3 PM** (or 2 h before the chosen release time), so Justin gets 1-2 h to playtest before it goes public. | open |
| R0.3 | Runs in the **Claude CLI in the terminal**, not the desktop app: 3 lane terminals + 1 coordinator = 4 windows (a 5th is allowed for badges if needed). Give Justin clear move instructions before starting. | open |
| R0.4 | Recommend the effort level (ultracode? max?) and when to use Opus 5.5 vs Fable 5.1 for hard or visual tasks. Usage limits don't matter ("you can use all of this week's usage"). | open |
| R0.5 | Test every new GUI and feature on **phone, tablet, console and PC** without Justin switching devices by hand. Find a way. | open |
| R0.6 | Feasible, optimized, bug-free on console/mobile/PC, little tweaking after, done in time. AI runs on its own after the first approval. | open |
| R0.7 | Push back when it gives better results. Interview Justin about anything unclear before implementing. | ongoing |
| R0.8 | Justin is awake for the next ~5 h (from 06:15) and can test short gates any time. Do as much as possible without him and ask only when his input is needed. | ongoing |
| R0.9 | Don't lose detail as the conversation gets long (this file, the plan page and memory hold it all). | ongoing |
| R0.10 | Before starting the Halloween work, report back how Candy works: how much per Candy and per win. | open |

## 1. Event core (from the first request plus answers)

| # | Requirement | Status |
|---|---|---|
| R1.1 | Event length **6 days, ends Tue Nov 3** (Justin: "event length is good"). If release moves later, keep the end time or shift it (to decide). | decided |
| R1.2 | Halloween currency (Candy) + quests to earn the cues. Quest board ideas: pocket XX balls, win XX games. Enough fun, achievable, rewarding content for 5-6 days. | decided |
| R1.3 | Cues never come back after the event. | decided |
| R1.4 | Leftover Candy converts to money at **$10 per Candy**, with a GUI arrow showing what it became. Auto end. | decided |
| R1.5 | **2 Robux Candy packs** ("candy packs are good"). Draft prices 49 R$ and 149 R$. | decided |
| R1.6 | **In-game countdown starting 30 min before** release, then everything switches on at release time. | decided |
| R1.7 | **Automated update countdown on the game icon/thumbnail**, starting about 5 h before release (Justin referenced an "image #3" that did not come through). Or use a Roblox feature if one exists. Set it up when we get there. | open |
| R1.8 | Clear Halloween icon/button on the right side of the screen. | decided |
| R1.9 | New game icon (an edit of the current one) + Halloween thumbnail. | decided |
| R1.10 | Candy Rush boost: clear **bottom-left chip "x2 Candy" with a countdown timer**. | open |
| R1.11 | Track gifts between cues: Justin didn't understand Q4. Explain it simply and propose (more cues means more rewards between quests). | open |
| R1.12 | Halloween abilities: optional idea from the first request. The plan said no new ability. | decided (no) |

## 2. Event cues: 5 cues, all Exclusive, gold standard for future cue reworks

| # | Requirement | Status |
|---|---|---|
| R2.1 | **Candy Corn** (new 5th cue): starter of the track. Candy corn texture + candy corn aura, smaller trail and finisher. Visual tier about **Rare-Epic**, still unique in model, trail, finisher, aura and VFX. | open |
| R2.2 | **Jack-o'-Lantern**: no candy corn on it. Pumpkin auras. Finisher = **laughing jack-o'-lantern**. Tier about **Epic-Legendary**. | open |
| R2.3 | **Black Cat** (replaces Bone): cute (especially appealing to girls), detailed animated cat VFX/auras, colours clearly different from Spider (not another black cue). Tier about **Legendary-Mythic**. Unique model twist. Concept art first. | open |
| R2.4 | **Spider** (replaces Phantom, which already exists in the game): cool black arachnid cue with extra model extensions, not creepy for people with arachnophobia, "kinda like hela's helmet from thor". Tier about **Legendary-Mythic**. Concept art, then **Justin's approval before building**. | open |
| R2.5 | **Witch's Broom**: last and hardest prize, tier about **Mythic-Secret**. Unique model, doesn't have to follow cue conventions, as long as the shape roughly matches so holding looks right. Keep the little **witch-hat charm, and make it sway**. | open |
| R2.6 | Playtime cue at **3 h 01 m** ("31"), not 3 h 06 m. (Spider took Phantom's slot as the playtime cue: confirm.) | open |
| R2.7 | Broom must be hard but reachable: at least **100+ owners by the end of the event** ("generously rewarded while maintaining status and exclusivity for grinders"). | open |
| R2.8 | The rarity ladder follows the track: the first cue must not flex like the last one. | open |
| R2.9 | Every cue: unique model (not the standard cue shape; tips can differ), unique trail, finisher, aura, VFX, animation. **Better than every current cue**: flipbook animations, popping auras, heavy VFX. Use any tools needed. | open |
| R2.10 | Concept art for Spider, Black Cat and Broom (plus the revised Jack-o'-Lantern and the new Candy Corn), approved before building. | open |

## 3. Map

| # | Requirement | Status |
|---|---|---|
| R3.1 | Temporary spooky map: sky, ambience, trees/plants/decor replaced. Concept art "looks pretty good". | decided |
| R3.2 | Table colours still show the mode: **1v1 purple, 2v2 orange, 3v3 green** (colours pop and look good). | open |
| R3.3 | **Custom haunted table models**: yes, implement. | open |
| R3.4 | New **night mode**: not too dark, a beautiful purple sky, **same visibility as day and sunset**. Maybe permanent later. | open |
| R3.5 | Lobby candy drops (pickups). | decided |

## 4. Pumpkin King

| # | Requirement | Status |
|---|---|---|
| R4.1 | Explain how he works: event NPC that spawns now and then, or always standing there? Hold E to challenge? Private server? Difficulty? Can you keep playing him? | open |
| R4.2 | He is there **on day 1** and new players see him **in their first session**. Some exclusivity but not too rare. Everyone can play him. Maybe "respawns in X minutes/hours" after he's beaten. | open |
| R4.3 | Make his model: pumpkin head, his cue, aura, animation pose. | open |
| R4.4 | Bonus Candy for beating him + a **candy explosion animation**. | open |

## 5. Boosts HUD (permanent)

| # | Requirement | Status |
|---|---|---|
| R5.1 | Friend boost for Candy (Grow a Garden style **+XX%**), 20%/friend or lower (10%) so it can't be abused with 10 friends. | open |
| R5.2 | **Friend boost for money too**, about +10% per friend (as in Steal an Egg, Grow a Garden, Slime RNG). Check it won't inflate the economy. | open |
| R5.3 | VIP shows its boost (2x). One format everywhere: all multipliers or all percentages. Boosts stack. | open |
| R5.4 | **Group join: +10% permanent**. | open |
| R5.5 | The boost pill sits **next to the money pill**, and the invite button moves aside. It **must fit on mobile**. | open |
| R5.6 | Tapping it opens a tiny info card showing where each active boost comes from (group, friends, VIP). | open |
| R5.7 | **Show a mock before implementing.** | open |

## 6. Roaming during matches (permanent)

| # | Requirement | Status |
|---|---|---|
| R6.1 | Remove the invisible barriers: in-match players can **walk anywhere while waiting** for the opponent's shot. | open |
| R6.2 | While in a match they can't join another match (empty pads), can't use solo/bot pads (disabled), and anything else that would break. | open |
| R6.3 | On their turn they're **teleported back to the table**, however far away they are. | open |

## 7. Cue Preview (permanent, reusable)

| # | Requirement | Status |
|---|---|---|
| R7.1 | Click a cue to get a detailed preview: the **model**, plus the **trail and the pocket finisher**. | open |
| R7.2 | A system and design that new limited cues and the Index reuse later. | open |

## 8. Badges (permanent; not part of the event)

| # | Requirement | Status |
|---|---|---|
| R8.1 | Generic + special badges. "Welcome to Crazy 8 Ball" on first join. | open |
| R8.2 | First win, counting the tutorial win so players see it right after the tutorial. | open |
| R8.3 | Win milestones 5, 10, 20 ... up to 500 or 1,000, each with its own name (novice, pro, 8 ball god ...). | open |
| R8.4 | One badge per new rank (Bronze, Silver, Gold ...). | open |
| R8.5 | First Rare, Epic, Legendary, Mythic and Secret cue. | open |
| R8.6 | Abilities badges (maybe). | open |
| R8.7 | Rare/unique ones: **"Beat the Owner!"** = win a match against Painicane (544959133). | open |
| R8.8 | Collection: own 5 / 10 / 50 ... cues (not "full collection", because cues keep growing). | open |
| R8.9 | Win streaks: 3, 5, 10. | open |
| R8.10 | "Played in the 2026 Crazy 8 Ball Halloween Event". | open |
| R8.11 | Existing players: they must get the badges they already earned. If that can't happen automatically, there must be a way. Check whether a burst of many badges is OK ("better later than never"). | open |
| R8.12 | A good number of badges, and give Justin the **full list**. | open |
| R8.13 | Built for longevity: room to add more, ideally an automated way to add badges later. | open |
| R8.14 | Don't overthink it or spend too long on it. Use another terminal if needed. | decided |

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
