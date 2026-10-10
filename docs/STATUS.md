# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-09 (branch `tutorial-v2`).

## Where the build is

- **Branch `release`** is the integration branch, and every lane of the parallel build is
  merged into it (Bots, Economy, GUI and cutscenes, Tutorial, Unique cues). Stage 5 of the
  road to release (`docs/ROADMAP.md`): tutorial, funnel, performance, game page.
- **Lint and tests (2026-10-08, branch `gui-v4` with the abilities rework merged in):** lint OK
  (three old LocalShadow warnings); all 1103 Lune tests pass.
- **In the game:** server-owned tables with our own physics and 8-ball rules; 1v1, 2v2, 3v3
  and solo; the global queue and arena with rematch; bots (ten tiers, Play against PC, lobby
  bots, disguised bots); ranks (XP only from winning) and money; economy v4; saves at version 10;
  13 abilities (Ultimates) with the spin screen; cue skins with VFX and outlines; lucky blocks
  as the only gacha (cases, the Magic 8 Ball and reward popups are gone); the Free Reward menu
  (daily, playtime, the 28-day track, group and invites), Cues (My Cues, Index; the Inventory renamed), trading, settings, our own player list and boards; the first-time tutorial;
  the rooftop map with a day and sunset cycle; pull cutscenes Rare to Legendary.

## Being tried right now (the designer's look, nothing final)

One line each; the long form is the 2026-10-08 entry at the top of
`docs/archive/STATUS_HISTORY.md`. Each still needs the designer on a real phone, PC and controller.

- **Fredoka One** stays (`Config.UI.FontTest`); **blur, not dims**; **NEW RANK! waits** for a
  free lobby (not yet a real arena trip back); **the 1v1 result cutscene**: not yet a real 1v1.
- **Cue outlines and the "pop" aura** (six cues, `Config.CueSkins.Pop.Ids`), **new cue card
  pictures** and **ball callouts** and the shorter pull-bar cue: not yet seen in a real game.
- **No fat-fingered shots on a phone** (`Config.Input.TouchPull`): needs a real phone.
- **The player list like Roblox's**: hidden on a phone for now; a PC size not yet looked at.
- **The matchmaking bar and spawn pill**: parked by the designer (2026-10-07); open: the spawn
  pill's 20 s, Play Global's X on a phone. **The queue portal**: not yet on a phone or gamepad.
- **Lighting**: day 10 min, sunset 5 min. **Pull cutscenes**: Mythic and Secret wait a redo.
- **Our own lucky blocks** (all 12 kinds, 2D icons), **the Gift drop** (`/giftdrop`; a test
  Gift waits in the designer's Studio save) and **the Mystery block's upgrade screen**: not yet
  on a phone, a controller or at full frame rate.

## Open, waiting on the designer

- **Economy v4, "the forgiving economy"** (approved and merged into `shop-lively` 2026-10-08;
  `docs/ECONOMY.md`, roadmap 7.8). The rules, saves (v9), model and docs are in, Lune-tested;
  the v4 Robux prices are **live on Roblox** (the four new products made, the six sale products
  off sale). Until the merged place is published, the live game sells at the new prices with
  the old grants: publish soon. Still to do: the designer's Studio check (shop prices, the
  Mystery screen, rewards, timers, the skip); set every random-item product to Not Listed in
  the Creator Hub; the GUI screens of the plan's hand-off (`docs/prompts/ECONOMY_V4_PLAN.md`
  section 18); Lucky Shot, Golden Shot, Lucky Rain and the stay bonus are planned only.
- **The GUI hand-off after economy v4** (2026-10-08, branch `gui-v4` from `shop-lively`): the
  designer's picks are in on the private page https://claude.ai/artifact/Q79pcvwxeos8AB7o8357Lw
  (prompts and pictures in `~/Desktop/8ball-refs/gui-mocks-v4`). Done and checked in Studio:
  Abilities films the real character; Lucky Spins retired (save v10); Ranked's reward tiles one
  size; Claim All's server side; the restock banner; bigger money packs and the Starter Pack
  at 29 R$ with its cue; the Shop's Blocks, Money and Passes tabs; the HUD's win track (A);
  the Free Reward menu (Daily A with Playtime, the track and Group in one menu; codes stay in
  Settings) with Claim All's six Robux products (Not Listed); Ranked in the lively frame (A);
  the ability spin screen (A); the Mystery screen (B, the Track); Settings (A); the reel's v4
  odds (look unchanged), the skip's dialog priced for the time left, every block's "Odds &
  Details" behind a sky-blue dice. The designer's second and third notes (2026-10-08), done on
  PC: Starter Pack and VIP side by side (VIP only there now), the Passes row of four, odds
  rounded and in the lively popup (Mystery: tiers, then pity meters), the folded win track, the
  rainbow THANK YOU! after a Robux purchase, the VIP tag and VIP's x2 pots; still to see on a
  phone, a controller and with a real purchase. The restock's rework waits for the economy pass.
  At publish: `tools/roblox_products.py --sync` (Starter Pack 29, pack texts, Lucky1 and
  Lucky3 off sale). Trade is not built (not in the release).
- **The Cues redo** (2026-10-08, `docs/prompts/CUES_LIVELY_PROMPT.md`, on `shop-lively`, in
  `gui-v4`): the new cue card, the Cues menu, the CUES icon, the smooth money chip, the reel and
  YOU GOT, checked in Studio. Still open: the see-through reel trial's verdict, a phone and a
  gamepad, the numbered card's mark A or B, the copy numbers' own plan. `shop-lively` is not
  yet merged into `release`.
- **The abilities rework** (in `gui-v4` since 2026-10-08, `docs/prompts/ABILITIES_REWORK_PLAN.md`):
  Fire Shot is the starter (2x speed, full orange guideline lines, a flame trail, scorch
  marks that fade in about a second); Super Bounce is back as a third Common; Verity
  (Rare) eats then shoves; Catch-a-Ball (Epic) catches two; Look Over There! (Rare) sneaks;
  Steel Ball (Legendary) pots one and lines up one, as Gyro's lime two-hexagon ball.
  Not yet checked: phone and controller, the sounds by
  ear, the tutorial spin's reveal, the sneak with two players, the designer's voice lines. The
  one-by-one review (since 2026-09-30) goes on; abilities not yet reviewed are provisional.
- **The lively Shop** is in `release` (2026-10-06); other menus take its frame as rebuilt.
- **Decision still open:** whether the VIP cue pays finder's money on the first join.
- **Tutorial v2** (branch `tutorial-v2`, not merged; `docs/prompts/TUTORIAL_V2_REPORT.md`):
  built and checked in Studio on PC (3 clean automated runs, one with fake lag; two review
  agents' 11 fixes; the team-table backup). On the test place (Crazy 8 Test Place, published
  by Open Cloud). The designer's first live notes are done (the combination's ghost replay,
  the Rank claim without a dim, the Daily Rewards popup, the rank HUD's next goal, the Starter
  Pack tile, ...) and the test place's saves were reset. Waiting on: the designer's next live
  pass, a real controller and phone, Max Players; economy v5.1 notes in the report.
- **The cue rarity rework** continues after the Unique cues (Beta, Grand Opening, Eclipse,
  Celestial Dragon, Kitsune). Apex's first look was reverted.
- **The place file:** save `place/8ball.rbxl` and publish once this milestone is done (lucky
  block templates and models, Unique cue templates, the renamed Firework Cue instances,
  `ReplicatedStorage.AbilityLooks.SteelBall`).

## Not yet checked (the Studio tools cannot do these)

- A real phone and a real controller on everything since the UI redo, including the lucky
  block hold and reel skip, the shop and the pull cutscene skip. Studio's MCP cannot fake a
  gamepad and cannot switch the phone emulator in Play mode.
- Real multiplayer: a two-player block or cue trade, 2v2 and 4-player matches, the global
  queue in the published game (`docs/MULTIPLAYER_TESTING.md`), real Robux purchases.
- Sounds by ear (the levels were measured, not listened to), the new click "boop" included.
- The analytics funnels in the Creator Dashboard (roadmap 8.2; `docs/TUTORIAL_FUNNELS.md`).

## Known gaps and test switches to remember

- `Config.LuckyBlocks.Test` (Refill, SeedOnJoin) is off since 2026-10-08: the designer's
  blocks are used up like a player's (`/giveblock` gives more); timers still skip for them.
