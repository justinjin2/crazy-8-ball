# Lane v3-core (the Halloween economy, 2026-10-29 afternoon)

Branch `hw3-core` from `90e23dc8`, worktree `.claude/worktrees/wf_a0729e1c-dc8-1`. No Studio, no
uploads (only the menu lane uses Studio). Numbers and their sources: `docs/ECONOMY.md`,
"Halloween Candy and the event cues"; the model: `python3 tools/halloween/pacing.py`.

## What was built

1. **Candy per pocket** (designer decisions 3 and 4). Every pot that pays the player money pays
   `Config.Halloween.Match.PerPocket` = **3 Candy** with it, x the money's anti-farm ball factor
   (`Money.farmRow().Balls`), x the event multiplier (Rush UTC :00-:09, Oct 31) and friends +
   group (`CandyMath.multiplier`), rounded over the match (round of the running sum). Against
   people and **disguised bots** (the team pads' "Fill with PC" seats disguised bots, so those
   pay too, like their money); never PC practice, solo, the King's seat or the tutorial's bot; a
   pot money pays at the flat short-match rate pays none. Only while Live and HwOn.
   - Pure rules: `src/shared/Halloween/PotCandy.luau` (eligible, shot, settle).
   - Server: `Economy.payOne` asks `CandyService.pots` right after the shot's money commit
     (pcall, warned once); one save commit a shot, `PlayerData.hwPot` (op "hwPot", in
     `Items.QUIET_OPS` and `Badges.SKIP_OPS`); the Candy attribute set at once; each pot's Candy
     rides on its MoneyGrant grant (`candy`) with the balance after it (`candyBalance`).
     Replay-safe: money is paid once per accepted or late-judged shot (ShotService.judged,
     Engine.takeLateShot once, Rewind shots never); on top, PotCandy pays a shot's seq once.
   - **No Candy at settle** (Finished 10 and Win 25 folded into the pots). At settle
     (`CandyService.matchSettled`, now called by Ranking before the short-match return): the
     match's total goes out **once** as `HwCandy` "Match" (b: x2 when some came in a Rush) and
     **once** as the end-of-match "+N" chip (CandyToast, to the HALLOWEEN tile); a real match
     against people or a disguised bot counts for the quests (HwMatch how "Paid" / "Disguised");
     a short match logs and shows its pots' Candy, no quest; tutorial / PC: nothing (the King's
     quest rule kept).
   - Client: `src/client/Halloween/CandyFlyer.luau` (CashFlyer's twin): a candy and "+3" pop just
     under the pot's cash chip as the replay drops the ball, fly into the Candy pill
     (`Config.UI.BoostPill.CandyPill`) whose icon thumps; `BoostPill` shows
     `CandyFlyer.shown(balance)` so the number counts up as chips land. No pill on screen: the
     HALLOWEEN tile; neither: fades in place. Lower effects: one chip a shot. One RenderStepped
     only while a chip is up, 6 pooled frames. Tuning `Config.UI.CandyFlyer`.
   - **Switch**: `Config.Halloween.Match.PerPocketEnabled = false` gives exactly the old
     settle-time Candy (3 a ball, 10 finished, 25 a win; real matches against people only).
2. **The thirds** (decision 3): ground `Pickup.HourCap` 400 -> **150**, `HalloweenMap.Candy`
   spawn 3.5 -> **4.5 s**, life 25 -> **30 s** (about as many candies stay around a player);
   quest boards 2-6 reshaped for the King off (first three ~6 / ~13 / ~16-20 min of play, the
   fourth 50-95 min; the King rows' Alts: Active 60 min, Wins 6, Nice shots 5; no Alt is a hooked
   kind). Rewards 60/100/150/250 unchanged. No Robux price, product or pack touched.
3. **The King off** (task 4), checked by reading: BossService.start returns at once with
   `Boss.Enabled` false (no challenge listener, visits, banners, throne, KingSpawn); MapClient
   starts no KingDropSign, KingCape or KingEntrance (cutscene) with it off; no throne, so no
   KingChallenge prompt; Countdown's King timer needs `Rules.kingVisits()` (false); CandyToast's
   King line comes only from `bossWon`; `CandyService.hooks().king` false, so his quests read as
   their Alts; the menu's King-drop card needs `KingDrop.Enabled` (false). Fixed in core:
   `bossWon` now refuses with the King off (the designer's `/hw kingwin` paid King Candy), and the
   end screen listed the Jack-o'-Lantern twice (shop cue + King drop; `Ledger.eventCues`).

## The numbers (docs/ECONOMY.md has the tables and every source)

Creator Hub (read 2026-10-29 12:30, 2-day lag): 21.9 min of play a day per DAU, sessions 15.9 min
(new 15.2), ~90% of DAU new, D1 ~12%, D7 ~1%. Model: ~46.5 eligible pots an hour (9.5 matches x
5.75 balls x an assumed 85% against people or disguised bots) -> ~170 Candy an hour from pockets
(~290 on Oct 31), ~130 from the ground (assumed), 560 a day from quests.

| | Pitchfork 300 | Broom 2,500 | Jack 4,500 | Sword 7,500 | Shares at the end |
|---|---|---|---|---|---|
| 3 h a day | ~17 min | ~4.6 h | ~8.4 h | ~14.4 h | pockets 38%, quests 36%, ground 25% |
| ~22 min a day | ~22 min of play (day 1) | ~2,100 by the end | | | |

## Check by hand (Studio, then live)

1. A real match (two accounts, or a disguised bot: a 1v1 pad with nobody else): each ball you pot
   shows the green cash chip and, just under it, an orange candy "+3" that flies into the Candy
   pill over the money pill; the pill's number rises as each lands (not before). In a Rush
   (`/hw time rush`) "+6".
2. After the result: one "+N" Candy chip (the match's total) flies to the HALLOWEEN tile.
3. Practice against PC, solo and the tutorial's match: no candy chips, no "+N".
4. Settings > Lower effects: one candy chip a shot.
5. Walk about in the lobby: candies keep spawning around you; at 150 pickups in a UTC hour the
   bag-full note and they stop to the next hour.
6. The HALLOWEEN menu (after the release, board 2): Play 1 match, Win 1 match, Pocket 15 balls,
   Play 60 min (the King's quest reads as its Alt). Console clean through all of it.

## Open issues

- **Not verified in Studio** (this lane has no Studio): the flying chips, the pill's held
  number, the end chip, the console. Lune tests and lint only.
- `src/client/BoostPill.luau` (no lane owns it this run) got one guarded read of
  `CandyFlyer.shown`; `src/server/Badges.luau`, `src/server/Items.luau` one op each.
- `BossService.qa` (the designer's `/king`) still seats a King match with the King off (map
  file, designer account only); not changed.
- A player who leaves mid-match keeps their pots' Candy, but that match's `HwCandy` "Match" is not
  logged (Ranking settles only players still in the game), so the event undercounts leavers.
- Assumptions to measure after publishing: the 85% paying share and the +5% boosts (`HwMatch`),
  ~130 ground an hour (`CandyPickups`), the 5 min tutorial (the Halloween funnel's 3_FirstCandy
  -> 4_Pitchfork).
- `docs/halloween/RELEASE.md` (the coordinator's) still says "3 a ball, +10 for finishing, +25 for
  a win", "every 4 seconds" and "400 pickups"; the Match switch row should name
  `Match.PerPocketEnabled`.
- If the publish lands after 19:00 EDT, a live (old-build) server may have counted board-2
  progress under the old board 2's quests; the new board reads that progress by slot key (capped
  at each need, a claimed slot stays claimed): harmless, but a few players may see a quest
  already part-done.
