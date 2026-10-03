# Lane: Bots

Folder `~/Desktop/8ball-bots`, branch `lane-bots`, Rojo port 34874, Studio file
`place/lane-bots.rbxl`. Rules for all lanes: [README.md](README.md).

## The job

Nothing exists yet: "Play against PC" on the host card says "Coming soon" (ROADMAP 2.4, GDD
sections 6 and 11). Build, in this order, each step verified before the next:

1. **The PC opponent at a 1v1 table.** A bot per rank: ten levels, Bronze (a beginner can
   beat it) to Reyes (hard for a strong player). It picks reasonable shots through the real
   rules and physics (pure code under `src/shared/Bots/` so it is Lune-tested: shot search,
   skill as aim and power error, safeties and ball in hand), plays with a human-like delay,
   and uses its ability by the policy already in `Config.Ults.Pc`. A player meets the bot of
   their rank. PC matches already pay PC XP and money (Config.Ranks.PcXp, Config.Economy PC
   rows): use those, do not change them.
2. **PC fill** for empty seats at 2v2 and 3v3 tables.
3. **Lobby bots** (the designer, 2026-10-02): in an empty server, a few bots walk around and
   play at tables so a new player is not alone. Roblox rules: they must not pretend to be real
   people. Give them generated outfits (random catalog items), never a copy of a real user's
   avatar; made-up names; never on a leaderboard or a player count; a real player can always
   tell, or ask the designer how they should be labelled. They step aside when real players
   want the table.

The Tutorial lane needs a "disguised PC" for a new player's first match (GDD section 14): make
the bot's look and name settable so the tutorial can use it; tell the Tutorial lane how (in
your status).

## You own

- New: `src/shared/Bots/`, `src/server/Bots/` (or `BotService.luau`), `Config.Bots`,
  `Strings.Bots`, tests `tests/bots_*_test.luau`.
- The PC paths in shared files: the "Play against PC" and seat-fill hooks in `TableService`
  and the server side of the host card; `Config.Ults.Pc`. The host card's look (`QueueMenu`,
  `OpponentPrompt`) is the GUI lane's: change only the logic you need there and list it.

## Ask the designer (in the interview)

- How each bot should feel (reference clips or images): how fast it shoots, how it misses,
  does it talk or emote, does it show a name and rank, a versus screen?
- Lobby bots: how many, what they do, how they look, how they are labelled, when they leave.
- Does the bot of your rank use your current rank or your peak? Can you pick an easier bot?

## Status

**2026-10-02: brief approved** (`docs/prompts/BOTS_PROMPT.md`).

- **Step 1, the bot brain (done, 22213d1).** `src/shared/Bots/` (Rng, ShotFinder, Brain, Look,
  Script), `Config.Bots`, `Strings.Bots`; `tests/bots_brain_test.luau`; the duel tuner
  `tools/bot_duel.luau` (results in `tools/bot_duel_results.json`).
- **Step 2, the robot (done):** the designer picked the Bludroid (bundle 196).
- **Step 3, Play against PC (done).** `src/server/Bots/` (BotService, Driver, Body, Identity),
  the client stand-in `src/client/People.luau` and `BotChat.luau`. Checked in Studio (PC
  window): the real button seats a Bronze Bot (Unranked player) with a random cue and ability;
  the coin lands for the player, who breaks; the robot bends over the table and lines up with
  a small to-and-fro; its shots take 3 to 3.4 s of aiming after the turn intro, about 4 to 6 s
  with ball in hand; result screen shows the robot, "Bronze Bot", its badge and the series;
  Rematch is accepted at once and the player breaks again; Leave removes the bot; console
  clean. `/botrank <tier>|off` (designer only) sets the bots' tier for testing. Phone and
  gamepad: no new controls (the existing Play against PC button); the HUD and result screen are
  the existing ones with the robot's picture.
- **Shared or other lanes' files changed (each a small block or a few lines):**
  `Config.luau` (Bots block, `Debug.Commands.BotRank`), `Strings.luau` (Bots block, three Dev
  lines), `Net.luau` (BotSay), `MatchEngine.luau` (`breakFor`: the player's side breaks, on a
  rematch too), `Settle.luau` (bot kinds: botKind, isBot, botReal, recordAs, streakCounts;
  opponentKind gives PC for a PC bot), `Ranking.luau` (bot seats in teamList, record as PC win,
  no streak against bots, bot forfeit counts), `Economy.luau` (bots never paid as opponents),
  `TableService.luau` (bot block: onAction, onRequest, all, seatBot, setBotAim, moveBotCue,
  holdBot, botShotAccepted, padSpot; the action and request hooks), `ShotService.luau`
  (submitFor), `UltService.luau` (botUlt, activateFor), `Bootstrap` (starts BotService),
  `DevCommands.luau` (/botrank block), `QueueMenu.luau` (Play against PC sends PlayPc),
  `WatchedShooters`, `BackCue`, `Nameplates`, `MatchHUD`, `ResultScreen`, `Effects`,
  `UltCutscene`, `Main.client` (look people up through People, so bots show like players).
  Step 6 added: `GlobalQueue.luau` (`botMatch` block), `TableService.luau` (`searchToMatch`,
  `waitingSearch` in the bot block), `ArenaService.luau` (`seatBots` block, two calls before
  `begin()`, the `StudioArenaBot` attribute).
- **Step 4, disguised identity (done).** Real avatars from random accounts (2020 on): most
  accounts wear a starter outfit or nothing (measured: 30 of 60 in three default outfits, 6
  blank), so a look must be styled (two or more accessories that are not face parts, no
  starter shirt unless covered by layered clothing); about 1 in 7 passes and the server keeps
  6 ready, so a bot appears at once. Made-up names (never an existing Roblox username, never
  two alike). Checked in Studio: six bots in a row, all different real-looking avatars, each
  with its own name and tier badge on the game's nameplate and its cue on its back; they are
  not Players, so Roblox's Esc list never shows them. For the GUI lane's player list: every bot
  body is a Model in `workspace.Bots` with attributes `BotSeat` (its id), `BotKind`
  (Pc/Disguised/Tutorial), `DisplayName`, `RankTier`, `RankDivision`, `RankIndex`,
  `EquippedCue`, `UltEquipped`, `AvatarUserId` (headshot); `src/client/People.luau` gives
  them as Player-like stand-ins (`People.everyone()`, `People.botAdded/botRemoved`).
  `BotService.stand(bot, at)` puts a bot standing in the lobby. Studio-only test hook:
  `ServerStorage.BotsQA` (spawn, stand, seat, remove, say, list).
- **Step 5, the tutorial bot (done; its fake lobby comes with step 7).** Checked in Studio: the
  bot appears on the player's pad 2 s after Request opponent, the player breaks; on its first
  visit it pots one ball then scratches, on its second it knocks the 8 in early (EarlyEight:
  the player wins), says AUGHHHH! (bubble + chat line), jumps and vanishes; the player's result
  screen shows WINNER, the bot's real avatar and Silver badge, +100 XP and a full win's money,
  "Opponent left". If the player loses, the bot asks for a rematch at once and plays the script
  again. The second tutorial bot plays a normal Bronze-level game and declines any rematch.
  **Bug fixed on the way:** the brain's simulation now follows the server's shot path exactly
  (placement rule, ShotInput, quantised seed, resting spin kept); before, a ball in hand after
  a scratch could make a planned shot miss for real. A test now checks the brain and the
  engine end every shot in the same place.
  **How the Tutorial lane drives it** (server, `src/server/Bots/BotService.luau`):
  `local bot = BotService.tutorialBot()` (yields for its look; nil if Roblox answers nothing:
  try again), then `BotService.joinTable(bot, t, { delay = Config.Bots.Tutorial.JoinDelay })`
  from the table's Request opponent (`TableService.onRequest(function(t, player) ... end)`);
  the table starts by itself and the player always breaks. Second game:
  `BotService.tutorialSecondBot()` the same way. `BotService.matchEnded.Event:Connect(function(
  botId, info) end)` tells who won (`info.won` is the bot's); the bot leaves by itself after its
  game (and when the player leaves). The snapshot's seat carries `bot = { kind = "Tutorial",
  noRematch = true }` for the second game, so the GUI can grey "Find another". Both games pay
  and count as real wins, whatever the match time (Settle.botReal).
- **Step 6, the global queue 1v1 fallback (done; the lobby half needs the published game).**
  A 1v1 search with no real opponent after 10 s (`Config.Bots.Fallback.SoloSeconds`) comes out
  of the queue (`TableService.searchToMatch`: if the queue matched it with a real player first,
  that match stands) and goes ahead as a found match: "Match found!", then the teleport to a
  reserved arena whose player list (`GlobalQueue.botMatch`, written before anyone is told)
  names a disguised bot of the player's tier (`bots = { { team = 2, kind = "Disguised", tier,
  rematch = "Never" } }`). In the arena (`ArenaService`, a small block) the bot is made once the
  player is in, walks in to its spot and sits; the player breaks; no rematch (it declines, the
  arena's Play another and Lobby stay). Checked in Studio with the Studio arena
  (`ServerStorage` attributes `StudioArena = 1` and the new `StudioArenaBot = "Gold"`): the
  Gold bot with a real avatar sat on side 2, the game started 6 s after the list, the player
  broke, and after the game Rematch was greyed ("Opponent left") with Play another and Lobby.
  The lobby half could not run in this unpublished window (the queue's MemoryStore answers
  "publish this place"): **to check in the published game:** Join Global Queue alone, wait 10
  s: "Match found!", the teleport, a disguised bot of your tier walks in.
- Next: step 7, lobby bots.

## Requests to other lanes or the integrator

- **Integrator, global queue pairing** (the designer, 2026-10-02; `GlobalQueue.luau` is not
  mine): 1v1 always pairs the closest rank, even 3+ divisions apart, and a real player always
  beats a bot; at most 4 tiers apart (Bronze with Diamond yes, Bronze with Expert never).
  2v2 / 3v3: rank barely matters, pair whoever is queueing. This replaces GDD 6's "anyone after
  10 s". The bot fallbacks (1v1 at 10 s, teams at 25 s) are mine and come as a block.
- **Integrator, GDD lines that changed** (move them over at the merge): GDD 6 "PC never plays
  PC" (lobby bots play each other) and "each with friends or PC fill" (2v2/3v3 lobby tables:
  only a host's Fill with PC for the other team); GDD 11 Open "Bots" (all decided, see
  Decisions); GDD 13/14 "never a real user's avatar" and "disguised PCs stored as PC" (the
  tutorial's wins count as real wins).
- **GUI, the custom in-server player list**: show every bot model in `workspace.Bots` whose
  `BotKind` attribute is `Disguised` or `Tutorial` exactly like a player (attributes on the
  model: `DisplayName`, `RankTier`, `RankDivision`, `Money`, `AvatarUserId` for the headshot
  via `rbxthumb://type=AvatarHeadShot&id=<id>&w=150&h=150`). PC robots (`BotKind = "Pc"`)
  are not listed. Details firm up in my Status as I build.
- **Economy**: (1) ECONOMY 3.2 needs a "Disguised bot" column: pays like a person (money, XP,
  free case), no win streak, the win stored as a PC win; a disguised bot that forfeits pays a
  full win even under the one-minute mark; the tutorial's two games are real wins (the early 8
  pays in full). (2) The odds of a bot's cue rarity by tier (the designer: lower ranks mostly
  the lower rarities, but a Legendary as likely as a real player pulling one, so a Silver bot
  CAN carry a Legendary). Until you answer I use the Standard Case's odds.

## Decisions (dated; the integrator copies them to DECISIONS.md)

- 2026-10-02 (designer): **disguised bots wear real Roblox avatars** from random real user ids
  (accounts from 2020 on, never banned or blank) with a made-up username, each unique and never
  an existing username. They are not in Roblox's own Esc player list (the one hint); the custom
  in-server player list shows them. Replaces "never a real user's avatar, never pretend to be a
  real person" (lane file, GDD 14). The designer knows other games do this; it is their call.
- 2026-10-02 (designer): **lobby bots play each other** (replaces GDD 6 "PC never plays PC").
- 2026-10-02 (designer): the real player **always breaks** against any bot (the coin is shown,
  rigged; rematches too).
- 2026-10-02 (designer): a bot shot takes **2 to 4 s** (random, +2 s with ball in hand), the
  same at every rank; it lines up with small left-right adjustments. The ability cutscene is
  extra.
- 2026-10-02 (designer): **one skill level per tier**; the player's chance of beating the bot of
  their own rank: Bronze 90%, Silver 80, Gold 65, Platinum 57, Diamond 50, Expert 50, Veteran
  45, Master 40, Grandmaster 35, Reyes 30 (Reyes misses about 2-3% of shots). Behind by 2+
  balls it makes its shots more often: +5, +6, +7, +8, +9, +10, +8, +6, +4, +1.5 points.
  Misses are near misses, never wild.
- 2026-10-02 (designer): a bot's ability is random, weighted like a real spin; none Legendary
  or higher when the player is Gold or below. Bots never chat or emote (the tutorial bot's
  "AUGHHHH!" is the one exception). The opponent's aim line is never shown (like a person's).
- 2026-10-02 (designer): **Play against PC**: one robot from a Roblox catalog bundle (picked
  from screenshots), named "<Tier> Bot", always the player's own tier (Unranked: Bronze),
  table difficulty does not change it, Rematch accepted at once, works in private servers,
  pays the PC rows.
- 2026-10-02 (designer): **2v2/3v3 lobby tables**: bots never join by themselves; the host can
  press **Fill with PC** once their own side is full, filling the other team with PC robots at
  the team's average tier (replaces "PC can fill any seat"). The global queue's 2v2/3v3 gives a
  disguised all-bot team after 25 s at the real team's average rank.
- 2026-10-02 (designer): **global 1v1 fallback**: no real player after 10 s, a disguised bot of
  the player's own tier in a real arena (teleport and all); no rematch.
- 2026-10-02 (designer): **disguised wins** pay money, XP and the free case like a real match,
  with no win streak, stored as PC wins (never on the most-wins board). A disguised bot that
  forfeits gives a full disguised win even under the one-minute mark. Both tutorial games are
  real wins; the tutorial bot's early 8 pays in full.
- 2026-10-02 (designer): disguised lobby bot rematch: it waits for the player, answers 1-3 s
  later and accepts about 85% of the time.
- 2026-10-02 (designer): lobby bots start bot-vs-bot games only while at least 3 1v1 tables
  stay free; a real player stepping onto their pad makes them stop and walk off.
- 2026-10-02 (designer): bot names in a real-Roblox mix (`PixelPanda_482`, `itz_mikey77`,
  `xXShadowStrikeXx`, `coolkid2013`...).
