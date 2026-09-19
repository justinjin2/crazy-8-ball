# Roadmap

How to use this file:

- Work on **one milestone at a time**, top to bottom. Do not skip ahead.
- Every milestone ends in something you can **play or see**.
- "Done means" is the test. If it doesn't pass, the milestone isn't done.
- New ideas go in the **Parking lot** at the bottom, not into the current milestone.
- After each milestone: playtest, commit to Git, tick the box, start a fresh AI session.

Version 1 = Phases 0 to 4. Everything after is only worth building if v1 is fun.

---

## Phase 0: Setup

- [x] **0.1 Project folder.** Folder created, Git initialized, Rojo project syncing into Studio, StyLua, Selene, and luau-lsp installed.
  Done means: a test script edited on disk shows up in Studio, and the lint command runs.
- [x] **0.2 AI connected.** Studio MCP server enabled and connected to Claude Code. CLAUDE.md written with project rules.
  Done means: the AI can start a playtest, read the console, and take a screenshot.

## Phase 1: The shot (solo, grey boxes, no art)

The most important phase. No rules, no opponents, no menus. Just: does hitting a ball feel good?

- [x] **1.1 One ball rolls.** Grey-box table. Custom physics module moves one cue ball: it rolls, slows with friction, bounces off rails, stops.
  Done means: a ball fired by a test command bounces around believably and comes to rest.
- [x] **1.2 Balls collide and sink.** Ball-to-ball collisions, six pockets, full 15-ball rack, break shot.
  Done means: a hard break scatters the rack convincingly and balls drop into pockets.
- [x] **1.3 Aim and shoot.** Drag to aim, guideline showing cue ball path and first contact, pull-back power bar. Works on PC and mobile.
  Done means: you can play shot after shot with touch and with mouse.
- [x] **1.4 Camera and avatar.** One 3D orbit camera that sits opposite the aim and looks across the table along the aim line, framing the whole table automatically for any ball position, aim and screen shape (never top-down); scroll or pinch zooms in on the cue ball. Avatar in aiming pose with cue, mostly transparent while aiming and invisible when close to the camera. Camera holds and follows the action after the strike.
  Done means: aiming never feels blocked on phone or PC, zoom is one gesture, and watching the shot feels like a replay.
- [ ] **1.5 Spin.** Spin selector that changes how the cue ball behaves after contact.
  Done means: top spin follows through, back spin draws back, visibly.
- [ ] **1.6 Sound and juice, pass one.** Cue strike, clack scaled by speed, rail thud, pocket drop, aim ticks, sink burst effect, "Nice shot" popup.
  Done means: you catch yourself shooting balls around for fun with no goal.

**FRIEND TEST 1.** Hand it to a friend with no explanation. Do they keep shooting? Compare side by side with GamePigeon. Fix the feel before moving on.

## Phase 2: A real match

- [ ] **2.1 Rules, hot-seat.** Full 8-ball rules with turns, solids and stripes, fouls, ball in hand, win and lose. One player controls both sides.
  Done means: a full legal game can be played start to finish, and every foul is handled.
- [ ] **2.2 Two players, one server.** Sit at a table to join. Server validates shots and owns the result, all clients play the same simulation.
  Done means: you and a friend finish a match, and both screens always agree on where the balls are.
- [ ] **2.3 Pace and presence.** Shot timer, emotes during the opponent's turn, spectators can watch.
  Done means: there is never a moment where a player has nothing to do or see.
- [ ] **2.4 Bot opponent.** Bot that picks reasonable shots, with easy and medium difficulty and human-like aiming delay.
  Done means: a solo player can sit down and get a fair, beatable match.
- [ ] **2.5 Juice, pass two.** Turn streaks (x2 on fire, x3 blue fire), trickshot detection (bank, combo, multi-ball) with popups, coins per ball win or lose, victory screen, elimination finisher on the loser.
  Done means: a lucky bank shot makes you react out loud.

**FRIEND TEST 2.** Two friends play each other. Do they rematch without being asked?

## Phase 3: The twist

- [ ] **3.1 Ability framework.** Equip one ability before the match, one ability button during your turn, cooldown scaled to the ability's power, server-validated.
  Done means: a placeholder ability can be equipped, used, and is then greyed out until its cooldown ends.
- [ ] **3.2 Time Stop.** Freezes the shot clock with an original dramatic effect and sound.
- [ ] **3.3 Super Bounce.** Rainbow cue ball, almost no speed loss off rails for one shot.
- [ ] **3.4 Magnet Pocket.** Chosen pocket gently pulls your balls for one shot. Tune until it rescues near misses without feeling like cheating.
  Done means (3.2 to 3.4): each ability creates at least one "did you see that" moment in a test match, and the bot's matches still feel fair.

**FRIEND TEST 3.** Do abilities make matches more fun, or just more random? Tune cooldowns and strength.

## Phase 4: Make it beautiful, then soft launch

- [ ] **4.1 Lounge art pass.** Moody lounge: dim room, warm table lights, neon accents, glossy balls, real felt. Several tables.
- [ ] **4.2 UI art pass.** Clean, consistent HUD, popups, victory screen. Thumb-friendly on mobile.
- [ ] **4.3 Save data.** Coins and basic stats persist between sessions.
- [ ] **4.4 Performance and bug pass.** Test on a low-end phone. Fix anything that stutters.
- [ ] **4.5 Name, icon, thumbnails.** Pick the name. Make the game page.
- [ ] **4.6 Soft launch.** Public release, shared with friends and small communities. Watch what players do and where they quit.

**VERSION 1 COMPLETE.** Stop and review: what do players love, what do they ignore? That decides the order of everything below.

---

## Phase 5: Reasons to come back

- [ ] Ability gacha: roll for new abilities with earned coins, rarities and odds designed on paper first (check Roblox paid-random-item policy before any Robux link)
- [ ] Ability catalogue: grow the pool well past the first three, each with a cooldown matched to its power
- [ ] Cue collection: cosmetic cues with rarities, bought with coins
- [ ] Loot boxes with earned coins (same policy check as the gacha)
- [ ] Bonus box for winning
- [ ] Daily login streak: day 2 rare box, day 7 guaranteed legendary, reminder on post-match screen
- [ ] Playtime reward: stay long enough, earn a cue
- [ ] Collectible finishers and sink effects

## Phase 6: Competitive

- [ ] Rank tiers and rating (Valorant / League style)
- [ ] Ranked rules: self-help abilities only
- [ ] Cross-server matchmaking by rank
- [ ] Global and friends leaderboards
- [ ] Bot fill for empty queues and losing streaks (decide on labeling)

## Phase 7: Social and chaos

- [ ] 2v2
- [ ] Sabotage abilities, casual only
- [ ] More abilities from the parking lot
- [ ] Party up with friends, private tables
- [ ] Replay or clip feature for trickshots

## Phase 8: Deep economy

Design on paper first. These are very hard to undo once live.

- [ ] Limited-quantity cues with serial numbers
- [ ] Trading
- [ ] Decorated personal tables
- [ ] Wagering in advanced lobbies only
- [ ] New game modes and table types

---

## Parking lot

Ideas land here so they are safe and out of the way.

- Extended bounce-path guideline ability
- Sabotage ideas: shrink opponent guideline, fog, shaky aim
- Creator outreach once trickshot clips look good
- (add new ideas below)
