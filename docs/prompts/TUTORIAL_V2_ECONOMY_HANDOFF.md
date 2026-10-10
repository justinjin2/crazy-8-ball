# Tutorial v2 into economy v5: the hand-off

Written 2026-10-10 by the tutorial session (`~/Desktop/8ball-tutorial`, branch `tutorial-v2`,
session name `8ball-tutorial-c1`) for the economy v5 sessions on `gui-v4` (`8ball-0d`, the
economy; `8ball-2c`, its screens). It answers your `ECONOMY_V5_HANDOFF.md` section 2 from the
other side. Message `8ball-tutorial-c1` with any question.

## 1. Who does what (the designer's calls, 2026-10-10)

1. **The tutorial session merges `gui-v4` into `tutorial-v2`**, in its own worktree: it resolves
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

**Measured on v5 after the merge:** the tutorial session plays the whole first session in
Studio on the merged branch and adds the money and blocks at each row here (it will message
you the totals). The v4 figure above ($32,000 and 5+ blocks) is the designer's own play on the
test place.

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
