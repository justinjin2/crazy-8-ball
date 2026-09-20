# Crazy 8 Ball: Game Design Document

Working name: **Crazy 8 Ball** (final name check is a release task). Rewritten 2026-09-20 from the
designer's full idea dump plus the earlier GDD. Every section has **Decided** (build to this) and
**Open** (not yet decided; do not guess, ask). Numbers marked *(tune)* live in `src/shared/Config.luau`
and are playtest values, not design decisions. Ideas that are not scheduled live in section 18.

## 1. The pitch

A 3D, satisfying, chill, competitive and social 8-ball pool game on Roblox. Your own avatar lines
up and plays every shot in a bright pool lounge. It feels as crisp as GamePigeon 8-ball, with a
twist: every player brings one ability that helps them or sabotages the opponent. Every ball you
pocket pays money, win or lose. Money opens loot boxes of rare cues and tables, ranks climb from
Bronze to Reyes, and the rarest items can be traded. Built for phones first, with PC and console.

The goal is longevity: the respected, premier 8-ball game on Roblox that people come back to,
not a trend that dies.

## 2. Audience and why Roblox

**Decided**
- Three audiences at once: adults who know pool and want a chill, skill-respecting game; pool
  lovers wanting a fresh 3D take; kids (the platform majority) who come for the abilities and
  the collecting. The appeal for all of them is the same: satisfying sound, visuals and
  gameplay, replayability, the gacha and economy, socialising, and competition.
- Why Roblox: it is the only platform where the player's own avatar plays the shot (2D pool
  games and first-person 3D ones cannot), the avatar catalog already exists, and its biggest
  markets (US, Philippines, Europe) are pool countries. Pool needs almost no language, so the
  game crosses language barriers by design.
- **All ages.** The game is not age-restricted. Both R6 and R15 avatars are allowed.
- Mobile first, PC and console (Xbox, gamepad) supported from the start. See section 5.

**Open**
- Whether age-verified adult purchases earn the higher DevEx rate under the chosen settings.
  Verify on Roblox's current policy page before writing any rule about it.

## 3. Design pillars

Every feature is checked against these. If it serves none, it waits.

1. **The shot is the game.** Aiming, striking and sinking must feel and sound incredible with
   nothing else in the game.
2. **Always something happening.** Fast turns, constant feedback, a reward for every ball.
   Always give the player something to do.
3. **Your avatar is the star.** You see yourself line up, shoot and celebrate.
4. **Skill respected, chaos welcome.** Abilities are balanced, never banned. Skill still wins
   over time, and the ranks make that visible.
5. **Nobody leaves empty-handed.** Losing still pays. Casual players can still get rare things.

## 4. Core loop

**Decided**
- Inside a match (seconds): aim, shoot, watch, feedback (sound, popup, money), next turn.
- Across matches (minutes): play, earn money for every ball plus bonuses, spend money on loot
  boxes for cues and tables, roll abilities, rank up, trade, repeat.
- The currency is called **money** everywhere (UI, code, docs). Never "coins".

## 5. Platforms, controls and camera

**Decided**
- **Every feature works on phone, PC and gamepad, and is checked on all three in every
  milestone.** Every screen has a button alternative to every drag.
- PC: hold click and drag left or right to aim, scroll wheel to zoom, pull the power bar on the
  right down and release to shoot, click the cue-ball icon to set spin.
- Mobile: swipe left or right to aim, pinch to zoom, pull the power bar with a thumb, tap the
  cue-ball icon for spin.
- Gamepad: left stick aims, up and down on the right stick (or triggers) zooms, a hold-and-
  release button shoots with power, the spin selector is a stick target. Exact bindings are a
  milestone task, not a design question.
- Aim ticks: a soft tick sound on every step of rotation; a stretch sound while pulling the
  power bar back (GamePigeon style, original audio).
- **Camera:** one 3D orbit view (no toggle, no top-down). It sits on the side opposite the aim
  and looks across the table along the aim line, framing the whole table automatically for any
  ball position, aim and screen shape. Zoom is one continuous gesture from "whole table" down
  to a low "down the cue" view behind the ball. Fully zoomed out always shows the whole table.
  After the strike the camera pulls out to the whole table so every ball's path is visible,
  then returns to the player's zoom. Your avatar is at the table in an aiming pose, faded to
  mostly transparent, invisible when the camera is close to it.
- **Guideline** (Classic difficulty): a corridor one ball wide from the cue ball to first
  contact, a ring at the contact point, a short line for the object ball and a short line for
  the cue ball's deflection. See section 7 for the harder difficulties.
- Balls not in your group are marked with an X and your group gets a slight highlight, drawn on
  each viewer's own screen. A HUD shows which balls you have pocketed.

## 6. Modes, tables and joining

**Decided**
- Players spawn in the lounge and walk to any free table. There are no menus to find a game.
- **Joining: step on the table's floor pad.** Entering the pad plays a sound and a VFX and the
  pad turns green so everyone can see someone is queueing. The first person on a free table's
  pad is the **host**. A small floating popup gives the host: **Play Solo** ("still earn money"),
  **Wait for a player**, **Play against PC** ("earn rewards and rank too"), plus difficulty
  (Classic preselected and marked recommended) and abilities on or off (on by default). If the
  host does nothing, the match starts against PC after 15 seconds *(tune)* unless they chose
  Wait. Solo starts immediately.
- The next player to step on the pad joins as the opponent, no accept step. Anyone may join a
  waiting table. Everyone else can stand around and watch. If the host leaves before the start
  the table frees. The host's own custom table model is the table the match is played on.
- **Modes at release: Solo, 1v1, 2v2, 3v3**, each with friends or PC fill.
  Solo: normal rules with no opponent, clear one group then the other then the 8, a foul gives
  yourself ball in hand, sinking the 8 early re-racks, no shot clock, money per ball, no win
  bonus, no rank change.
  Teams: teams alternate turns and teammates rotate (A1, B1, A2, B2), teammates share a group,
  each player uses their own ability, the shot clock is per shooter, a whole team must agree to
  forfeit, PC can fill any seat, team matches are rated by team average.
- Before any two-sided match a short **versus screen** shows each player's avatar, cue and
  rank. Never for Solo.
- After a match the post-match screen shows **Rematch** and **Leave**. If both sides press
  Rematch within 15 seconds *(tune)* the same match restarts with the same host and settings
  and a fresh coin flip; otherwise the table frees. PC and Solo matches get an instant Play
  again.
- One **Find another server** button, hidden during a match. Cross-server and worldwide
  matchmaking are not planned for release (section 18).
- Servers hold about 30 players *(tune)* and all 12 tables can host any mode. PC never plays PC.

- **Spectator seating:** the chairs and sofas are sittable, and sitting is free look - the
  player is seated and the camera is left alone. Watching a table through its own camera is
  a separate feature and waits for spectating proper (Roadmap 2.3).

## 7. Rules

**Decided**
- Standard 8-ball. A coin flip decides who breaks (the first-time player always breaks, see
  section 14). The table stays **open after the break**: the first ball legally sunk after the
  break decides solids and stripes. Sink your ball, shoot again; miss, the turn passes. Fouls
  (scratch, wrong group first, no ball hit) give the opponent **ball in hand anywhere**. Clear
  your group then sink the 8 to win. Sinking the 8 early, or scratching on the 8, loses the
  game immediately. The 8 sunk on the break is re-spotted and the same player continues. No
  calling pockets.
- **Shot clock** about 20 seconds *(tune)*. Zero = foul with ball in hand. Two timeouts in a
  row = automatic forfeit *(tune)*.
- **Forfeit** button, costs rating. Leaving or disconnecting mid-match is an immediate forfeit:
  the opponent gets the win and reward, the table frees, no PC takes over.
- **Three difficulty levels, chosen by the host for the whole table** (both players see the
  same guideline):
  - **Classic** (default, recommended): full guideline as in section 5.
  - **Difficult**: the cue ball path only, no object-ball line and no deflection line.
  - **Challenger**: a short aim stub that only reaches balls close to the cue ball, nothing
    else.
  All three exist from the start. Until ranks exist there is no lock. Once ranks exist, the
  host cannot pick Difficult or Challenger until their peak rank unlocks them *(tune,
  placeholder Diamond I for both)*; a guest below that rank sees "Your rank is not qualified
  for this difficulty" with a Play anyway button. Unlocks never re-lock. Ball highlights and X
  marks stay on in every difficulty.

## 8. Feel: the satisfying layer

This is pillar 1 and 2 in practice. It is part of the core, not polish for later.

**Decided**
- Sounds: cue strike, ball-on-ball clack scaled by speed, soft rail thud, deep pocket drop, aim
  ticks, power-bar stretch, UI clicks. ASMR quality, original or licensed audio only.
- A small VFX and a rewarding sound on every pocketed ball, bigger and flashier for the 8.
- **Streak:** the first pocketed ball in a turn starts x1, the next x2 "on fire", x3 blue fire,
  and so on, with rising sound pitch and a money multiplier.
- **Trickshot bonuses:** extra money and a popup for bank shots (one or more rails before the
  pocket), combos (your ball knocks another in), and multi-ball shots ("Double", "Triple").
  Lucky sinks count and get the full celebration.
- "Nice shot" popup with a dopamine sound, shown on about half of good shots *(tune)*.
- Victory screen for the winner. The loser is simply shown as having lost. No finisher effect.
- Emotes during the opponent's turn for players and spectators.

## 9. Abilities

**Decided**
- Every player equips **exactly one** ability per match. Abilities are balanced: they add fun
  and moments worth clipping, they do not decide matches by themselves. At the strongest they
  can guarantee one ball goes in or stop the opponent pocketing one ball.
- Every ability declares **who it targets** (me or opponent) and **when it may fire** (my turn,
  opponent's turn, any time). The framework supports all of these from day one.
- **Cooldowns count in the user's own turns** ("ready in 2 turns"), scaled to the ability's
  power: weak abilities return fast, strong ones rarely.
- Abilities are on by default; the host can turn them off for a match. Abilities-off matches
  still count for rank.
- **At release every player has one starter ability: Magnet Pocket**, kept free forever. All
  other abilities come from the ability gacha (section 12). Before release, friend tests may
  unlock every built ability with a developer flag in Config.
- First three to build, in this order: **Magnet Pocket** (choose a pocket, for one shot it
  gently pulls your balls toward it; a nudge that rescues near misses, never a vacuum),
  **Time Stop** (freezes the shot clock for one turn with an original dramatic effect and
  sound; no copyrighted audio), **Super Bounce** (rainbow cue ball that loses almost no speed
  off rails for one shot; built into the physics). Every later ability follows the same
  framework. Rarities match the item rarities (section 12).

**Open**
- The full ability list and how many exist at release.
- Exact cooldown lengths per ability *(tune)*.

## 10. The lounge and the world

**Decided**
- **Look:** the bright, warm, upscale lounge that was built (golden-hour windows, cream walls,
  honey timber, teal seating, coral and yellow accents, twelve tables in three rising rows of
  four, a snack counter, plants, cue racks, signs). Package in `assets/lounge/`.
- Chairs and sofas are sittable. The **snack counter** hands out non-alcoholic drinks and
  snacks that the player can drink or eat (a tool with a short animation). No alcohol.
- **Pro lobby:** a separate Roblox place, reached by a teleport door, for Diamond I *(tune)*
  and above, where only Difficult and Challenger are available. Its look is decided later
  (the old "dim moody neon room" idea is the candidate).
- A player's win streak shows above their head, and their country flag next to their name.

## 11. Progression and ranks

**Decided**
- Tiers: **Bronze, Silver, Gold, Platinum, Diamond, Expert, Veteran, Master, Grandmaster,
  Reyes**. Each has divisions **I to V** (I is the bottom, V the top) except Reyes. Reyes is
  named after Efren Reyes (placeholder, check rights before launch).
- Players are **Unranked** until their first rated match, then Bronze I after one game.
- **One visible rating number** drives the rank; bands per division live in Config and widen
  higher up. Rank follows the number both ways with a floor at Bronze I. A **peak rank** is
  saved: rank-up rewards are granted once per division, difficulty unlocks use the peak.
- Every match against a person or PC changes rating. Solo never does. Beating a much higher
  rating pays more, a higher-rated player beating a lower one gains little.
- **Difficulty multiplies gains and losses** *(tune, placeholders 1x Classic, 5x Difficult,
  10x Challenger)*. Classic gains shrink to a trickle above Diamond, and PC matches give full
  rating only up to the top of Diamond and a fraction beyond, so Expert and above come only
  from the harder difficulties against people. PC skill scales with the player's rating.
- Bronze to Platinum is fast, Diamond is a buffer, and the top ranks are exponentially harder.
  Reyes should be held by a few dozen to a few hundred players depending on population.
- Rating is saved under a season label ("Season 0"); no resets at launch.

**Open**
- The rating formula, points per game and division widths *(tune)*: solve on paper, then test.

## 12. Economy

**Decided**
- **Money** is earned for every ball pocketed, more on streaks and trickshots, in every mode
  including Solo and PC. Solo and PC income slows after a daily amount *(tune)*, never to zero.
  Money farming with macros is not punished.
- **Money packs are sold for Robux.** Because of that, every loot box, gacha and trade is a
  paid random item under Roblox policy: odds are shown on every box, and players in regions
  where paid random items are restricted get a direct-purchase catalog instead of boxes.
- **Permanent loot boxes** bought with money: one for cues, one for tables. Goal at release:
  30 cues. Rarities for everything: **common, uncommon, rare, epic, legendary, ultra**
  (name of the top tier to be picked). Rarer cues and tables have special pocket VFX.
- **Limited seasonal boxes** that leave and may or may not return. Season 0 has one for cues
  and one for tables.
- **Shop** with high-priced, quantity-limited items that sell out and become limited forever.
  At release: a Founder's cue and table (about 25 to 50 copies) and a Beta cue and table
  (about 500 to 1000 copies). All economy screens live under one menu.
- **Ability gacha:** spins cost Robux (packs of 1, 5, 10, 50) and there is one free spin per
  day. You keep every ability you roll; duplicates give spin credit that only buys more spins.
- **VIP** (one-time pass): 2x money, an exclusive cue and table, other perks. Never better odds.
- **Starter offer:** a cheap cue-and-table set for each player's first three days *(tune)*.
- **Items:** one catalog for cues, tables and abilities (stable id, type, rarity, model,
  effect). Every cue and table is a unique object with its own ID and a serial number for
  limited items. Abilities are owned flags. **Cues and tables can be traded, including VIP and
  starter-offer ones. Abilities are account-bound. Money is never traded.**
- **Cue and table models:** every cue is its own small mesh; **every table is its own full 3D
  model** with a strict performance budget per table (see ARCHITECTURE.md). Hundreds of both
  are expected, added as data rows plus assets.
- **Shop, inventory, save data and the first-time flow exist before the game is public.**

**Open**
- Money per ball, box prices, drop odds, pack prices *(tune)*: research other games first.
- The name of the top rarity.
- Whether limited-quantity table models get serial plaques in the world.

## 13. Fair play and security

**Decided**
- The server owns every match, validates every shot and ability, and never trusts the client.
- **Anti-boost:** the server tracks "opponents played today" per player with counts *(tune,
  placeholders 3 and 5)*. Past the first threshold rating gains shrink; past the second, zero
  rating and the match is not a win for streaks or leaderboards. Money shrinks but never
  reaches zero, so friends can keep rematching. No friend exemption. PC is exempt.
- Wins against PC are a separate stat and never count on the "most wins" board.
- No wagering of any kind (against Roblox rules).

## 14. First-time playthrough and onboarding

**Decided**
- The first match: the host popup is hidden. The new player joins a match against what looks
  like a real player and is actually a **disguised PC** (made-up name, never a real user's
  name; random avatar; a higher rank badge once ranks exist) that walks onto the pad from the
  edge of the player's view a few seconds after they arrive. They always break first. A
  passive, looping ghost animation shows pulling the cue back and moving the ball on the break
  line, and disappears on the first drag. No shot clock. They pocket a few balls, see the
  sounds and the money, and get to use their starter ability. The PC blunders and pockets the
  8 so they win early. Normal rules stand: if they lose, the same throwing PC repeats until the
  first win.
- **First win:** a free cue box opened right on the post-match screen with a reveal (skewed
  toward rare, epic or legendary) and an Equip button, plus extra money.
- Unranked to Bronze after one game. The first opponent shows a much higher rank so the win
  feels earned. PC is labelled "PC" everywhere else; disguised PCs never appear on
  leaderboards and are stored as PC in match records.
- **Daily 7-day streak:** every day's reward is meaningful (day 1 a box, day 2 a rarer box,
  day 7 something great). A stay-long-enough playtime reward (for example a cue).
- **Reminders:** Roblox cannot put text inside its own leave menu, but the game knows when the
  menu opens (`GuiService.MenuOpened`) and when the window loses focus. Both trigger a subtle
  in-game reminder ("Come back tomorrow for your free rare box"). The same reminder sits on
  the post-match screen.
- A funnel is tracked with Roblox's built-in analytics: joined, reached a table, first shot,
  first pocket, used ability, won, opened box, equipped, second match.

## 15. Social

**Decided**
- Leaderboards: top rating, most wins against people (global, all-time, refreshed every few
  minutes), and a nation board by total wins. Country flag auto-detected from Roblox's region,
  changeable in settings.
- Per-player match history: totals plus the last 20 matches.
- Trickshot clips are the organic marketing: creator outreach once clips look good.

## 16. Art direction

**Decided**
- Bright, warm, upscale lounge (section 10). Clean glossy balls (sphere meshes with baked
  textures), tournament blue cloth, black Diamond-style tables. Effects (streak fire, sink
  bursts, rainbow cue ball) must read at phone size.
- UI: clean, thumb-friendly, icons before words. All text lives in one strings module; Roblox
  automatic translation is switched on at release; no hand translation before then.

## 17. Data and engineering principles

Design-level rules; the technical detail is in ARCHITECTURE.md.
- Modular systems that can be tweaked without rewrites; every tunable in Config.
- Built for hundreds of cues and tables: items are data rows plus assets.
- Session-locked, versioned player saves with loss prevention from the first saved money.
- Track important metrics, especially the first-time funnel.

## 18. Parked ideas (not scheduled)

- Cross-server and worldwide matchmaking, a global server for 1v1 and 2v2.
- Private friend-locked tables. Party up with friends.
- Replay or "clip that" feature. Cinematic replay camera.
- Trading UI polish, item showcases, serial plaques.
- Seasons with themed sets beyond Season 0.
- More abilities: extended bounce guideline, shrink the opponent's guideline, fog, shaky aim,
  and anything new. New ideas go here.
- Offline play if Roblox ships it.
- New game modes and table types.

## 19. Open questions (collected)

- Age-rating and DevEx rate verification (section 2).
- Full ability list (section 9).
- Pro lobby look (section 10).
- Rating formula (section 11).
- Economy numbers and the top rarity name (section 12).
