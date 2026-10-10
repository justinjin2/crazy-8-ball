# Tutorial v2 into economy v5: the hand-off

Written 2026-10-10 by the tutorial session (`~/Desktop/8ball-tutorial`, branch `tutorial-v2`,
session name `8ball-tutorial-c1`) for the economy v5 sessions on `gui-v4` (`8ball-0d`, the
economy; `8ball-2c`, its screens). It answers your `ECONOMY_V5_HANDOFF.md` section 2 from the
other side. Message `8ball-tutorial-c1` with any question.

## 1. Who does what (the designer's calls, 2026-10-10)

1. **The tutorial session merges `gui-v4` into `tutorial-v2`** (done 2026-10-10, f1549ae), in its own worktree: it resolves
   the conflicts (16 files at the preview: `Config`, `Strings`, `LuckyBlockService`,
   `PlayerData`, `Rewards`, `Ranking`, `BlockDrop`, `LuckyClient`, `LuckyOpening`, `BlockReel`,
   `TutorialService`, `Tutorial`, and DECISIONS, ECONOMY, GDD, STATUS), keeps every v5, v5.1 and
   v5.2 economy and lucky-block rule, adapts the tutorial to them, runs lint and tests, and
   plays the whole tutorial (and a skip) in its own Studio window.
2. **Then `8ball-0d` fast-forwards `gui-v4`** in the main folder (`git merge --ff-only
   tutorial-v2`) at a quiet moment, once the tutorial session says the branch is ready. Nobody
   merges `tutorial-v2` into `gui-v4` before that.
3. **The economy sessions own every number.** The tutorial session does not tune money,
   blocks or prices; it reports what a new player gets (section 3) and flags what reads wrong.
4. Commits that land on `gui-v4` meanwhile are fine: the tutorial session merges the newest
   `gui-v4` again before it says ready. Please message it when one touches lucky blocks,
   rewards, ranks, `TutorialService` or the files above.

## 2. What the designer wants kept or changed (their words, 2026-10-09 and 10)

- **Keep the tutorial's first block reel**: an Uncommon block whose reel passes Legendary,
  Mythic and the Secret on its way ("i like to keep the uncommon spin block in the tutorial
  where it showed the legendary, mythical and secret as it passed by"). On `tutorial-v2` that is
  `Config.Tutorial.ReelGlimpse` and `ReelOpening` with `LuckyOpening`/`BlockReel`; it must
  survive v5.2's "every open spins the reel" and the Mystery's roll screen.
- **The first session gives too much**: after the tutorial plus the group and the playtime
  gifts the designer had about **$32,000 and 5+ lucky blocks** (test place, v4 numbers). It
  "reads as a lot and misleads about the pace after": the build-up should be slower.
- **The next win's reward** (wins 2/10 on v4: a Mystery block) is not exciting after opening
  so many Mystery blocks: maybe an Epic, if the economy allows.
- **The Daily Rewards must scale with v5.** v5 already changed the first week (day 2 Rare,
  day 5 $15,000, day 6 two Mystery, day 7 the Week One Cue) and the playtime gifts (money).
  The tutorial's Daily Rewards popup (`src/client/DailyRewardsMenu.luau`, new) hosts the same
  `FreeDaily` section the Free Reward menu shows, so after the merge it shows v5's rows; check it
  reads right with the Week One Cue on day 7.
- **Everything else that shows money must scale too**: rank rewards, the win track, the win
  bonus, playtime, group, favorite, invite, the shop tiles. Section 4 lists every tutorial
  screen with an economy number and where it reads it.

## 3. A new player's first session, in order (what they get, where it comes from)

Path S (alone at a table, the rigged game 1); a skipper gets the same rewards without the
guidance. All values are read from Config at run time; none is typed in tutorial code.

| Moment | What they get | Config (both branches) |
|---|---|---|
| Join | starting money | `Config.Economy` (start) |
| Game 1 (rigged win vs the bot) | match money: per ball, streak, the win bonus; XP | `Config.Economy.Match*`, `Ranks` |
| Result: the first win | the win track's first step | `Config.Economy.Drop.WinTrack` (v5: `WinTrackMoney` steps) |
| NEW RANK! (Bronze) + Rank claim | Bronze's rank reward | `Config.Ranks` rewards; `Config.Tutorial.RankClaim` |
| The first lucky block | the scripted Mystery: rolls to Uncommon, opens to the tutorial's cue (`Config.Tutorial.TutorialCue` = CosmoCue) | `Config.Tutorial.MysteryKind`, `ReelGlimpse` |
| Abilities | the RELEASE code's free spins | `Config.Tutorial` code / spins |
| The soft part: Daily Rewards popup | day 1 of the first week | `Config.Daily.FirstWeek[1]` ($5,000 + a Mystery on both) |
| Free Reward: group, favorite, like | their rewards | `Config.Social.GroupReward` (v4 3 Mystery, v5 2), `FavoriteReward` ($10,000 + Lucky 8 on both) |
| Invite popup | "You both get a free <block>!" | `Config.Social.InviteBlock` (v4 Rare, **v5 Uncommon**: the popup follows) |
| Playtime | the gifts at 5, 15, 30, 45, 60 minutes | `Config.Daily.Playtime` (v5: money only) |
| "Win a Match 0/1" quest, then normal play | the next wins | `Config.Economy.Drop.WinTrack`, `Ranks` |

### 3a. Measured on the merged branch (2026-10-10)

The tutorial session played the whole first session in its Studio window on `tutorial-v2` at
f1549ae (`gui-v4` 5e34be7 merged in), on PC, a fresh save. **The Studio account is VIP**: match
money doubled (`Config.Economy.VipBoost`), VIP's daily extras (`Config.Daily.VipBlocks`,
`VipSpins`), no block timers, and the VIP Cue's finder's money at join. Finder's money
(`Config.Index.FindMoney`) is never boosted. The v4 figure in section 2 ($32,000 and 5+ blocks)
is the designer's own play on the test place, with playtime gifts.

| Step | Money after | What changed |
|---|---|---|
| Join | $5,000 | the VIP Cue's finder's money (Exclusive); **a non-VIP starts at $0**; 0 spins |
| Game 1 (rigged win) | $8,025 | +$3,025 match money, VIP-doubled (break 440, aim 220, combination 715, ability 330, other balls 220, the win +1,100); about **$1,500 for a non-VIP** |
| Result: the first win | – | the first-win Rare block (`Drop.FirstWin`, win track step 1) |
| Rank claim (Bronze) | $15,525 | +$7,500: $2,500 + the Bronze Cue's finder's $5,000 (Ranked); a Mystery block |
| The tutorial's block | $16,525 | the Mystery rolled to Uncommon, opened to CosmoCue: +$1,000 finder's |
| Abilities | – | RELEASE: +3 spins, one used on the tutorial spin |
| Daily day 1 | $21,525 | +$5,000 + a Mystery (VIP also: an Uncommon block and 1 spin) |
| Group | – | +2 Mystery |
| Favorite | $31,525 | +$10,000 + a Lucky 8 block |
| 3 Mysteries rolled, then Open all | $38,525 | rolled to Uncommon, Standard, Uncommon; with VIP's Uncommon block, 4 new cues (2 Rare, 2 Uncommon): +$7,000 finder's |
| The first-win Rare block | $41,025 | +$2,500 finder's (a Rare cue) |
| The Lucky 8 block | **$43,525** | +$2,500 finder's |
| Not measured: playtime | up to +$14,000 | `Config.Daily.Playtime`: $1,000 at 5 min, $2,000 at 15, $2,500 at 30, $3,500 at 45, $5,000 + 1 spin at 60 |
| Not measured: an invite | – | an Uncommon block for both (`Config.Social.InviteBlock`) |

**Where the VIP account's $43,525 came from:** finder's money **$23,000 (53%)** (VIP Cue 5,000,
Bronze Cue 5,000, Cosmo 1,000, Open all 7,000, Rare 2,500, Lucky 8 2,500); rewards **$17,500
(40%)** (Favorite 10,000, Daily 5,000, Bronze 2,500); match money **$3,025 (7%)**.

**A non-VIP's first session, estimated from the same run:** about **$35,000 before playtime**
(no VIP Cue $5,000, half the match money, no VIP block; the 3 Mysteries' finder's money is
luck, about $4,500 to $6,000), **about $41,000 at 30 minutes** and **about $49,000 at 60
minutes**. Blocks: **6** (the tutorial's Mystery, the first-win Rare, the daily Mystery, 2 group
Mysteries, the Lucky 8; VIP 7), 7 new cues (VIP 9), 3 ability spins (+1 at 60 minutes). A
non-VIP also waits each block's own timer (Uncommon 1 min, Rare 5 min).

**The next win** (the "Win a Match 0/1" quest after the tutorial) is win track step 2 on v5:
`WinTrackMoney`, $1,000, then $1,000 again, then a Mystery at win 4 and the Epic at win 10. The
designer asked for something exciting there (section 2); v5's step 2 is money, which reads
smaller than the session's rewards before it.

**What reads high, for your rescale (the designer approves the numbers, not us):** the
designer's v4 complaint was $32,000 with 5+ blocks; v5 is higher, not lower, because finder's
money pays for every new cue and a first session finds 7 to 9. Favorite's $10,000 is the
biggest single reward, about 7 games' worth of a non-VIP's match money at once. Match money,
what the game is about, is the smallest share.

## 4. Tutorial screens that show an economy number (recheck after the merge)

- `src/client/DailyRewardsMenu.luau`: the first week's row (`FreeDaily`), Claim All's product.
- `src/client/HubCorners.luau`, the offer tile: the Starter Pack's "xN VALUE!" is
  `floor((StarterMoney / Pack1.Money * Pack1.Robux + Restock Rare's Robux) / live price)` (the
  cue and the hour of 2x not counted); VIP's "N% OFF!" compares the live prices. v5's restock
  Rare at 39 R$ changes the N: say if the formula should count differently.
  `Config.Shop.StarterSeconds` is now **one day** (designer, 2026-10-09; was 7).
- `src/client/RankHud.luau`: "N WINS TO <next division>!" divides the XP left by one win's XP
  against an equal player.
- The invite popup (`TutorialSoft`, `Strings.Tutorial.InviteBody`): `Config.Social.InviteBlock`.
- The Abilities step: the RELEASE code's spins (`Strings.Tutorial` "Type %s for %d free spins!").
- The ability prompt (`UltBar`): bigger and breathing in every match now (not economy, FYI).

## 5. What the tutorial needs from v5.2 (questions for `8ball-0d`)

**Answered by the merge (f1549ae, 2026-10-10):** the tutorial uses gui-v4's
`LuckyBlockService.setOpenHooks(force, opened, stay, script)` with every answer keyed on
`TutorialService.step`: `script` rolls the first Mystery to Uncommon (`Config.Tutorial.
MysteryReveal.Tier`), ready at once; `stay` keeps that Uncommon block from climbing at the
open; `force` gives `TutorialCue`. `BronzeBlockKind`, `setRevealHook` and the tutorial's own
forced path are gone; the save stays at version 11. The questions below are kept for the record.

1. Your section 2 describes v5.0 (the climb screen for every block). With v5.1 and v5.2, is the
   right hook for the first block now: the Mystery's roll scripted to an Uncommon block
   (`script(player, kind)`), and that Uncommon block then opened with its reel (its climb
   rolled at the open, so the open must be forced to stay Uncommon and give `TutorialCue`)?
   Which hook does the "stay Uncommon at the open" part now?
2. Bronze's interim Uncommon block that skips its climb (`stay`, `BronzeBlockKind`): still
   needed under v5.2, or does the scripted Mystery replace it?
3. The save is at version 11 on `gui-v4`; `tutorial-v2` adds no version (it uses Flags).
   Anything newer?
4. Anything on `gui-v4` still uncommitted or in flight that the merge should wait for?
