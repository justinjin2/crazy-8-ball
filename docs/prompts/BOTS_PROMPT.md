# BOTS lane brief (approved by the designer, 2026-10-02)

## Context

Nothing about bots exists yet: "Play against PC" on the host card is an empty button
(`src/client/QueueMenu.luau:322`), `e.pc` is read by `Progression/Settle.luau:64` but never set,
and `Config.Ults.Pc` is a policy with no player. The designer wants bots for launch, when the
first players may join alone: a real PC opponent of the player's rank, the tutorial's first
opponent, safety nets for the global queue, and lobby bots so an empty server looks alive.
No reference images (`~/Desktop/8ball-refs/bots/` is empty on purpose); everything below comes
from the designer's notes and the interview of 2026-10-02.

Studio window: `lane-bots.rbxl` only (studio id 169da90f-…). Rojo port 34874. Branch `lane-bots`.

## What the designer decided (interview, 2026-10-02)

Replaces older rules (GDD 6 "PC never plays PC", GDD 14 / lane file "never a real user's
avatar, never pretend to be real"; recorded in the lane file's Decisions):
- Disguised bots wear REAL Roblox avatars from random real user ids (accounts made 2020 or
  later, never banned, so the avatar loads) with a MADE-UP username, every one different,
  never the real person's name. They are not in Roblox's own Esc player list (the one hint).
  The GUI lane's custom player list shows them; I supply the data.
- Lobby bots play each other.

Gameplay, every bot:
- The real player ALWAYS breaks against bots (the coin flip is shown but rigged; on a rematch
  too).
- Lines up like a person: the cue swings onto the line, drifts a little left and right, pulls
  back, shoots. 2 to 4 s per shot (random each time, never over 4), +2 s when placing ball in
  hand. Same speed at every rank. The ability cutscene time is extra (it pauses the clock).
- Skill = one level per TIER (Gold I and Gold V meet the same bot).
- Player's win chance against the bot of their own rank (targets for a typical player of that
  rank; tuned in Lune):

  | Rank | Player wins | Behind boost (points, 2+ balls behind) |
  |---|---|---|
  | Bronze | 90% | +5 |
  | Silver | 80% | +6 |
  | Gold | 65% | +7 |
  | Platinum | 57% | +8 |
  | Diamond | 50% | +9 |
  | Expert | 50% | +10 |
  | Veteran | 45% | +8 |
  | Master | 40% | +6 |
  | Grandmaster | 35% | +4 |
  | Reyes | 30% (misses ~2-3% of shots) | +1.5 |

- Every shot it re-decides "really make it" or "near miss" (just off the pocket, a jaw rattle,
  never wild). Bronze: hits its own ball with little angling, scratches by accident; Silver
  a bit better; from Platinum up position play and safeties climb.
- Random ability weighted by the real spin odds (`Config.Ults.Roll.Normal`); no Legendary or
  higher when the player is Gold or below. Used by `Config.Ults.Pc` (bar full and behind, or
  no easy shot).
- Never chats or emotes (only the tutorial bot's "AUGHHHH!").
- Looks like a player: rank badge, a random cue on its back from a rank-based pool (Legendary
  as rare as for a real player; Economy lane owns the real odds, I ask them).
- What the player sees while it aims: the cue only, exactly like a real opponent (the
  guideline never travels for anyone, `Config.luau:1080`).

Play against PC (1v1, shown as PC):
- One robot look for all ten, from a Roblox catalog robot bundle (I screenshot 3-4 candidates
  in Studio first; the designer picks). Named "Bronze Bot" … "Reyes Bot", rank badge, random
  cue. Always the player's own tier; Unranked gets Bronze (the tutorial hides the button).
  Table difficulty never changes the bot. Rematch = the bot accepts at once. Leaving is a
  normal forfeit. Works in private servers. Pays as today's PC rows (x0.75 XP, $25/$8, PcWins).

2v2 / 3v3:
- Lobby tables: bots never join by themselves. The host gets a **Fill with PC** button that
  works once their own side is full and fills the whole OTHER team with PC robots at the real
  team's average tier. (Team PC bots never play teammates.)
- Global queue: after 25 s with no real team, a disguised all-bot team at the real team's
  average rank, each bot a different rank near it.

Tutorial bot (the Tutorial lane drives the flow; I build the bot and an API for it):
- Fake lobby: 15 lobby bots, Bronze to Gold, most in games, a few standing.
- Request opponent → 2 s later the tutorial bot teleports onto the pad, Silver badge, random
  real avatar + made-up name. Player breaks.
- First time the player gives up the turn: in that one visit the bot pots one of its balls,
  then scratches on its next shot. Next time: aims at its own ball and is guaranteed to knock
  the 8 in. Then "AUGHHHH!" (bubble over its head + a chat line), jumps, vanishes in mid-air.
  If the player runs to the 8, they just win. If the player loses: the bot requests a rematch
  and plays the same script; after a win it leaves; if the player leaves, it leaves.
- Second tutorial game: a disguised bot playing at BRONZE level, normal game, never requests
  and always refuses a rematch ("Find another" greyed).
- Both tutorial games count as REAL wins. The early 8 pays a full win even under the
  one-minute mark.

Global queue fallback (1v1): real players first; no real player after 10 s → "Match found!",
teleport to an arena, a disguised bot of the player's own tier walks in. No rematch.

Lobby bots (public servers only, never any private server):
- The server looks like 11: bots = 11 − real players (10 with one player … 0 at 11). When a
  player leaves, a bot "joins" again.
- Ranks: mostly Bronze/Silver/Gold, fewer Platinum/Diamond, none above Diamond.
- Some play each other at 1v1 tables (real shots), some wait on 1v1 pads, some stand, sit or
  stroll. Never at 2v2/3v3 tables.
- Stepping onto a waiting bot's pad plays it, disguised, at the skill of its own badge.
- A real Request opponent with nobody real in 10 s → an idle lobby bot (closest rank)
  teleports onto the pad. Bots never send requests.
- Bot-vs-bot games start only while at least 3 1v1 tables stay free; a real player stepping on
  a pad where bots are playing makes them end the game and walk off.
- When a real player joins, a bot vanishes: idle bots first, then bot-vs-bot players; a bot
  playing a real player is the last and forfeits only at 11 real players.
- Rematch: the bot waits for the player, then answers 1-3 s later, accepting ~85% of the time.

Pay and records:
- Disguised bot (lobby, global queue): money, XP and free case exactly like a real match, no
  win streak, stored with PC wins (never the most-wins board, not a "real win").
- Disguised bot that forfeits (vanishes): a full disguised win even under the one-minute mark.
- Tutorial bots: real wins (stored as Wins).

## Architecture

Pure brain (Lune-tested, deterministic, seeded, no Instances), `src/shared/Bots/`:
- `ShotFinder.luau`: ported from the ability harness's model shooter (`tests/ult_value.luau`
  `V.candidates`, `probe`, `V.calibrate`, `V.safePlan`, `V.shots`, `V.phased`, pick helpers):
  ghost-ball pots per own ball × pocket, blocked paths, cut and approach limits, calibrated by
  two-ball probes in our `Physics/Simulation` (`strike`, `step`, `settle`, `runHeadless`). The
  harness file stays untouched (not my area).
- `Skill.luau`: tier → make chance, behind boost, aim/power noise for "make" shots, blunder and
  accidental-scratch rates (Bronze/Silver), position-play depth (top-K pots simulated for the
  next shot, Platinum up), safety play (Diamond up). Numbers in `Config.Bots.Tiers`.
- `Brain.luau`: `Brain.decide(view, bot, rng) -> Decision` where view = balls, groups, team,
  ball in hand, called-pocket need, ult state. Make: calibrated plan with small noise, checked
  by `runHeadless` that it pots (retry draws). Near miss: aim offsets around the plan,
  simulated, choose one where the object ball stops near / rattles the mouth, no foul. Ball in
  hand: grid of legal spots (`Rules/CuePlacement.valid`) scored by best pot. 8-ball: call the
  plan's pocket. Break (bot-vs-bot only): a fixed strong break with noise. Ability: activate
  per `Ults/Match.pcShouldActivate`, picks (Heat Seeker own ball, Portals spot), Time Stop
  second strike, Rewind redo (from the harness logic).
- `Script.luau`: scripted visits for the tutorial: `PotThenScratch`, `EightBlunder` (search
  angles/powers that first-hit an own ball and drop the 8; fallback a direct 8 hit; scratch
  shot = a shot whose cue ball drops), deterministic search.
- `Look.luau`: aim-wiggle timeline (pure: angle/pull keyframes over the 2-4 s from a seed),
  name generator (word lists in `Strings.Bots`), cue rarity roll by tier, ability roll.

Server, `src/server/Bots/`:
- `BotService.luau`: the registry and public API. A bot = negative seat id (from −1000 down,
  clear of the QA fixtures), a spec `{ kind = "Pc"|"Disguised"|"Tutorial", tier, division,
  skillTier, name, avatarUserId | description, cueId, ultId, script?, noRematch? }`, and a
  character Model in `workspace.Bots` carrying the same attributes a Player has (`RankTier`,
  `RankDivision`, `EquippedCue`, `UltEquipped`, `DisplayName`, `AvatarUserId`, `BotKind`,
  `Money` for the player list).
- `BotDriver.luau`: runs a bot's turn on its table: waits the 2-4 s timeline, writes `t.aim`
  (so `broadcastAims` streams it like a person's), drags ball in hand via `Engine.moveCue`,
  calls the pocket, activates its ability, submits through the same server path as a person
  (`Engine.acceptShot` → flush → `shotAccepted` → `ShotResult` → broadcast). Brain work runs
  in a task with yields so a turn never stalls the heartbeat. Answers rematches.
- `Body.luau`: builds characters (`Players:CreateHumanoidModelFromDescription`), plays walk /
  idle tracks from the server Animator, anchors and places the body at the stance spot like
  `TableService.constrain` does for players, back cue, jump and vanish.
- `Avatars.luau`: real-avatar pool: random ids in `Config.Bots.Avatars` range (2020+),
  `GetHumanoidDescriptionFromUserId`; reject failures, blank/default looks (also catches
  terminated accounts), anyone in the server, the designer; prefetches a small pool at start.
- `Names.luau`: made-up names (Real-Roblox mix: `PixelPanda_482`, `itz_mikey77`,
  `xXShadowStrikeXx`…), each checked: not an existing username
  (`Players:GetUserIdFromNameAsync` must fail), passes `TextService` filtering, unique.
- `LobbyBots.luau`: the 11-person director, activities, pad waiting, request answers, step
  aside, leave order.
- `QueueBots.luau`: the global-queue fallbacks (1v1 at 10 s, team at 25 s) and the arena side.

Client: `src/client/People.luau` (new): one lookup `People.get(userId)` returning a Player or a
bot model with the same fields (character, name, rank, cue, ult, headshot id). A few display
modules switch their `Players:GetPlayerByUserId` to it (list below). A `BotSay` remote shows
the "AUGHHHH!" bubble (`TextChatService:DisplayBubble`) and chat line.

Changes in shared or other lanes' files (minimal, listed in the lane file):
- `MatchEngine.luau`: `t.bots` metadata survives rematch/reset; rigged coin (`breakTeam`).
- `TableService.luau`: a hook block (Play against PC, Fill with PC, request → lobby bot at
  10 s, search → fallback at 10/25 s, bot body hold, `seatSynthetic` usable by bots, pad
  occupancy counts bot seats, bots excluded from player-only paths).
- `ShotService.luau`: export the accepted-shot path for a non-Player seat.
- `UltService.luau`: export `activateFor`; `ultOf` reads the bot's ability.
- `Settle.luau`, `Ranks.luau`, `Money.luau`, `Ranking.luau`, `PlayerData.recordMatch`
  (Economy's): a `Disguised` opponent kind (Player money/XP/case, no streak, PcWins), Tutorial
  as a real win, bot forfeit counts as real; `Ranking.teamList` shows bot seats with their
  rank and headshot instead of "left".
- `QueueMenu.luau` (GUI): wire Play against PC; add Fill with PC (logic only; GUI owns look).
- `WatchedShooters`, `BackCue`, `Effects` (no owner), `Nameplates`, `MatchHUD` (GUI),
  `ResultScreen`, `UltCutscene`, `PostMatch` (Cutscenes): use `People.get`; headshots from
  `AvatarUserId` (`rbxthumb`); PC shows the robot.
- `GlobalQueue.luau` / `ArenaService.luau`: a block to start a bot match in a reserved arena
  (record carries the bot specs); pairing rules themselves are the integrator's.
- `Config.Bots`, `Strings.Bots`, `Net` (BotSay), new remote kinds `PlayPc`, `FillPc`.
- Requests: GUI (player list fields, Fill with PC look, greyed Find another), Economy
  (Disguised/tutorial pay rows in ECONOMY 3.2, the bot cue-rarity odds), Tutorial (the API),
  Integrator (global queue pairing rules; GDD 6/13/14 lines that changed).

## Build steps (in the designer's order; each: lint, test, Studio check in my window on PC,
phone and gamepad emulation, screenshots, commit, push, lane-file Status)

1. **Brain in Lune.** ShotFinder, Skill, Brain, Look; `tests/bots_*_test.luau` (finds pots,
   near misses never pot and never foul, ball-in-hand spots are legal, determinism, timeline
   2-4 s, name/ability/cue rolls). `tools/bot_duel.luau`: each tier's bot vs a model player of
   that tier (harness skill per tier) over seeded games; tune `Config.Bots.Tiers` until the
   win table holds within ±5 points; results saved to `tools/bot_duel_results.json`.
2. **Robot pick.** Load 3-4 catalog robot bundles on a rig in my window, screenshot, the
   designer picks (the one stop in the build).
3. **Play against PC.** BotService + BotDriver + Body + the client People shim; the button,
   rigged coin, the lining-up, ball in hand, abilities, result screen, Rematch, forfeit, PC
   pay. Studio: play full games at Bronze, Gold, Reyes (dev command `/botrank` sets the bot
   tier, designer-only, in DevCommands as its own block); watch the cue wiggle and the timing;
   console clean; check on PC, phone and gamepad.
4. **Disguised identity.** Avatars, Names, cue/ability rolls, attributes for nameplate, badge,
   back cue, player-list fields. Studio: spawn disguised bots, screenshot several avatars and
   names, confirm none is blank.
5. **Tutorial bot.** Script + API (`Bots.spawn`, `Bots.joinTable(table, bot, {delay = 2,
   teleport = true})`, `Bots.remove(bot, "Angry"|"Vanish")`, `Bots.startLobby({count = 15,
   tiers = {"Bronze","Silver","Gold"}, ignorePrivate = true})`, a `matchEnded` signal),
   AUGHHHH bubble + chat + jump + vanish, rematch request, the Bronze no-rematch bot, real-win
   pay. Studio: run the scripted game end to end with a dev command, all three devices.
6. **Global queue 1v1 fallback.** 10 s → arena with a disguised bot of the player's tier (Studio
   uses the `StudioArena` path since Studio cannot teleport). No rematch.
7. **Lobby bots.** The director, activities, bot-vs-bot games, pad waiting, request answers at
   10 s, step aside, leave/rejoin order, forfeit with full pay. Studio: an empty server with 10
   bots; join a waiting bot; request; second test client (multi-client test) to watch a bot
   leave.
8. **2v2 / 3v3.** Fill with PC (other team, team average tier) and the 25 s all-bot team in the
   global queue. Studio: fixture teammates via StudioMatchQA.

Then: lane-file Status (what works, devices checked, shared-file changes, how the Tutorial
lane drives the bot), Requests, Decisions; an analytics event per finished bot match (tier,
kind, who won) so the designer can see real win rates after launch.

## Verification

- `tools/lint.sh`, `tools/test.sh` after every step; `tools/bot_duel.luau` table in the status.
- Studio (lane-bots.rbxl only): play-tests with console reads and screenshots on PC, phone and
  gamepad emulation for: the bot lining up and shooting, nameplate/badge/back cue, match bar
  and result screen, AUGHHHH bubble and vanish, lobby bots walking/playing/leaving.
- By hand for the designer: play the Bronze bot (should win most), the Reyes bot (hard), the
  tutorial script, an empty-server lobby.
