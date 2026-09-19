# Game Design Document

Working title: undecided (see "Name" at the bottom).
Status: v1 scope locked. Anything not in "Version 1 scope" is parked, not deleted.

## 1. The pitch

A 3D 8-ball pool game on Roblox where your own avatar plays the shot. It feels as crisp and satisfying as GamePigeon 8-ball, but you bring one equipped ability (stop time, magnet a pocket, super-bounce the cue ball, and many more) that creates moments worth clipping. Abilities come from a gacha system, so there is always a new one to chase. Win or lose, you earn. Long term: collect rare cues and abilities, climb ranks, own the leaderboard.

## 2. Design pillars

Every feature gets checked against these. If it doesn't serve one, it waits.

1. **The shot is the game.** Aiming, striking, and sinking a ball must feel and sound incredible with nothing else in the game. Everything else is built on top of this.
2. **Always something happening.** Fast turns, constant feedback, rewards for every ball. No dead time.
3. **Your avatar is the star.** You see yourself line up, shoot, celebrate, and get finished off. This is what 2D pool games can't copy.
4. **Skill respected, chaos available.** Ranked is clean and fair. Casual is where things get unhinged.
5. **Nobody leaves empty-handed.** Losers still earn. Casual players can still get rare things.

## 3. Feel reference

GamePigeon 8-ball is the target for: aim and shoot controls, guideline, power pull, spin selector, ball physics, sound crispness, and rules. We copy the *feel and design*, never the actual sounds, art, or assets. All audio and visuals are original or properly licensed.

## 4. Core loops

**Inside a match (seconds):** aim, shoot, watch the result, get feedback (sound, popup, coins), next turn.

**Across matches (minutes, mostly built after v1):** play a match, earn coins for every ball plus bonuses, spend coins on cues and abilities, climb ranks.

## 5. Match rules

Standard 8-ball, kept simple like GamePigeon:

- 15 balls racked, break shot to start.
- First legally sunk ball decides who is solids and who is stripes.
- Sink a ball of yours: shoot again. Miss: turn passes.
- Fouls (scratching the cue ball, hitting the wrong group first, hitting nothing): opponent gets ball in hand, meaning they place the cue ball anywhere.
- Clear your group, then sink the 8 to win. Sinking the 8 early, or scratching on the 8, loses.
- No calling pockets in v1.

## 6. Controls and camera

**Aiming:** drag to rotate the aim. A guideline shows the cue ball path and the first contact. Each step of rotation plays a soft tick sound. Fine-aim control for small adjustments.

**Power:** pull back on a power bar, release to shoot.

**Spin:** tap a cue ball icon and choose where to strike it.

**Camera while aiming:** one 3D view, elevated and behind the shooter, looking down the aim line so the table lays out ahead. It turns with the aim. Scroll (PC) or pinch (mobile) zooms between a close view behind the cue ball and a high view where the whole table fits on screen. There is no view toggle and no separate top-down mode (decided 2026-09-19). Your avatar is visible at the table in an aiming pose with the cue, faded to mostly transparent so it never blocks the balls.

**Camera after the strike:** holds its position and lets its gaze follow the action. Avatar returns to fully visible.

**Platforms:** mobile and PC from the start. Most Roblox players are on phones, so every control must work with one thumb. (Assumption, not yet confirmed by the designer.)

## 7. Juice: the satisfying layer

This is pillar 1 and 2 in practice. It is not polish to do "later", it is part of the core.

- **Sounds:** cue strike, ball-on-ball clack (louder with speed), soft rail thud, deep satisfying pocket drop, aim ticks, UI clicks. ASMR quality. No voice announcer.
- **Popups:** short text on good shots ("Nice shot", "Bank shot", "Combo").
- **Sink effect:** a small burst on every ball pocketed, bigger on the 8.
- **Turn streak:** sinking multiple balls in one turn builds a streak. x2 "on fire", x3 blue fire, and so on, with rising sound pitch and a coin multiplier.
- **Trickshot bonuses:** extra coins and a popup for bank shots (one or more rails before the pocket), combos (your ball knocks another in), and multi-ball shots.
- **Lucky sinks count.** An unplanned ball dropping in gets the full celebration. That surprise is a feature.
- **Victory:** winner gets a victory screen, and a finisher effect that comically eliminates the loser's avatar. Finishers become collectible later.

## 8. Abilities (the twist)

Updated 2026-09-19. More detail to come from the designer; this is the current shape.

- There are **many abilities**, and the pool keeps growing. Players collect them through a **gacha system** (roll for a random ability; rarity and odds to be designed, see the Phase 5 note on Roblox's paid-random-item policy).
- Each player **equips exactly one ability** for a match. No loadout of three.
- An ability is activated during your own turn, before you shoot.
- Instead of a fixed number of uses, each ability has a **cooldown scaled to its power**: weak abilities come back quickly, strong ones rarely. The unit of the cooldown (turns, shots or seconds) is an open question; turns is the working assumption.
- **Ranked (later):** self-help abilities only. **Casual (later):** sabotage abilities also allowed.

**First three abilities to build (examples of the format, all self-help):**

| Ability | What it does | Notes |
| --- | --- | --- |
| Time Stop | Freezes the shot clock for this turn, with a dramatic screen effect and sound | Original sound design. Do not use the JoJo audio, it is copyrighted and gets games taken down |
| Super Bounce | Cue ball turns rainbow and loses almost no speed off rails for this shot | Must be built into the physics simulation |
| Magnet Pocket | Choose one pocket. For this shot it gently pulls your balls toward it | Pull must be subtle, a nudge that rescues near misses, not a vacuum |

These three prove the framework (equip, activate, cooldown, server validation). The gacha and the wider ability catalogue come after v1 proves the core is fun.

**Parked ability ideas:** extended bounce guideline, sabotage set (shrink opponent's guideline, fog the table, shaky aim), and anything else. New ideas go here, not into the current sprint.

## 9. The opponent's turn

- **Shot timer:** about 20 seconds per turn. Tune in playtests.
- **Emotes:** the waiting player can fire off avatar emotes and reactions.
- Spectators standing around the table can emote too.

## 10. The lounge

Players spawn in a walkable pool lounge. Walk up to a free table, sit down, and a match starts when a second player (or a bot) joins. Anyone can stand around and watch. No menus needed to find a game in v1.

Later, ranked play adds cross-server matchmaking on top of this. The lounge remains the home of casual and friend matches.

## 11. Art direction

**Stylized moody lounge.** Dim room, warm light pooled over each table, neon accents, clean glossy balls, rich felt. Not realistic, not kid-cartoony.

Why: it suits Roblox avatars, it reads as a "real" pool game, and a dark room makes every effect (streak fire, sink bursts, finishers, rainbow cue ball) stand out, which matters for clips and thumbnails.

## 12. Technical approach (plain words)

**Do not use Roblox's built-in physics for the balls.** It jitters, it behaves differently across the network, and pool needs precision.

Instead: **our own small physics simulation**, in one shared code module. Pool balls on a table are really a 2D problem: circles with position, velocity, friction, rail bounces, ball-to-ball collisions, and spin. The 3D ball models just follow what the simulation says.

How a shot flows:

1. The shooter's device sends only the shot inputs to the server: angle, power, spin, active ability.
2. The server checks it is really that player's turn and the numbers are legal, then runs the simulation to get the official result.
3. The server tells every player the shot inputs. Each device plays the same simulation locally, so motion is perfectly smooth with no lag.
4. When the balls stop, every device snaps to the server's official final positions, in case of tiny differences.

This gives the smoothness of local physics (the designer's original instinct) and keeps it cheat-proof, because the server decides what really happened. It is also what makes abilities like Magnet and Super Bounce possible: they are just modifiers inside our simulation.

Code rules: one module per system (Physics, Rules, Match, Abilities, Audio, UI), all tuning numbers in a shared config file, never trust the client.

## 13. Version 1 scope

**In:**
- One lounge, a few tables
- 1v1 against a friend in the same server, or against a bot
- Full 8-ball rules
- GamePigeon-quality aim, power, spin
- One 3D aim camera with scroll and pinch zoom, transparent avatar, shot camera that follows the action
- Full juice layer: sounds, popups, streaks, trickshot bonuses, victory screen, finisher
- One equipped ability with a power-scaled cooldown; the first three built are Time Stop, Super Bounce, Magnet Pocket
- Shot timer and emotes
- Coins earned per ball, win or lose (displayed and saved, nothing to spend on yet)

**Out, parked for later phases (see ROADMAP.md):**
2v2, ranks, leaderboards, cross-server matchmaking, cue shop, ability gacha and the wider ability catalogue, loot boxes, daily streaks, trading, limited-quantity cues, decorated tables, sabotage abilities, wagering lobbies, disguised bots, other game modes.

**The test for v1:** friends play it and ask for one more game without being prompted. If not, fix the shot feel before adding anything.

## 14. Notes on parked systems

So future decisions start informed:

- **Ability gacha and loot boxes:** fine with earned coins. The moment coins, rolls or boxes can be bought with Robux, Roblox's rules on paid random items apply (such as disclosing odds, and regional restrictions). Check the current policy before building.
- **"Come back tomorrow" on leaving:** Roblox does not let games interrupt the leave menu. Show the streak reminder on the post-match screen instead.
- **Bots that pass as humans:** common in mobile games and good for losing streaks and empty queues. Risk: if players discover it, it can hurt the "respected pool game" goal. Decide later whether bots are labeled in ranked.
- **Economy, trading, limited cues:** powerful retention drivers and very hard to undo once live. Design carefully on paper after v1 proves the core is fun.
- **Decorated tables:** open question whose table is used. Simplest answer later: the table's seat-one player, or random.
- **Content strategy:** trickshot replays and a clean cinematic camera are the organic marketing. A replay or "clip that" feature is worth considering after v1.

## 15. Name

Goal: short, says billiards, not tied to Roblox, passes the "wanna hop on ___?" test, not generic, not edgy.

Starting candidates: **Chalk**, **Rack'd**, **Side Pocket**, **Cue Club**, **Break**, **Eightfold**. Undecided. Check Roblox search for clashes before committing.

## 16. Open questions

- Exact shot timer length
- Cooldown unit for abilities (turns, shots or seconds) and the power-to-cooldown scale
- Gacha rarities, odds and what a roll costs
- Coin amounts per ball, streak, and trickshot
- Bot difficulty levels
- Confirm mobile-first assumption
