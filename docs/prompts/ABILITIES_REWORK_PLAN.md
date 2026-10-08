# Abilities rework (2026-10-08): the plan

Branch `abilities-rework`, worktree `~/Desktop/8ball-abilities` (from `shop-lively`). The
designer's brief is the 2026-10-08 session message; their interview answers are in section 1.
This session touches abilities only: never spin prices, `Ults.Earn`, the Roll odds tables,
slot passes (economy v4) or screen layouts (GUI session; see the hand-off list at the end).

## 1. Decisions from the interview

- Studio: our own second Studio window on a **local copy of the place** (not Team Create, so
  our scripts never reach the GUI session) with Rojo on its own port (34875).
- Uploads of ability assets (models, images, sounds, voice placeholders) are pre-approved,
  group 675425213, always dry-run first.
- Heat Seeker and Ghost leave the game. A slot holding either becomes Magnet when the profile
  loads (`Config.Ults.Retired`, mapped in `Ults/Slots`; no save version bump, so it can never
  collide with economy v4's SaveSchema change).
- The ladder (13 abilities):

  | Rarity | Abilities |
  |---|---|
  | Common | Eagle's Eye, Super Bounce |
  | Uncommon | **Magnet** (everyone's starter, the tutorial's), Rewind (was Rare) |
  | Rare | **Catch-a-Ball** (new), Portals |
  | Epic | **Look Over There!** (new), Time Stop, Chain Lightning |
  | Legendary | **Verity** (new), Steel Ball, Black Flash |
  | Mythic | Black Hole, Guangdong Tiger |

- Rare and above should nearly always pot a ball ("a free shot").
- Look Over There!: drag **one** of your balls into a pocket in about 3 s; it counts as potted
  and you still take your shot. Out of time: the ball stays where you let go (if the spot is
  free) and you shoot as normal.
- Catch-a-Ball and Verity trigger on **whatever** the cue ball hits first (an opponent's ball
  goes down for them). The 8 is the one exception: off your legal 8 shot it breaks free
  (Catch-a-Ball) or is put back on its spot (Verity), never a lost game by ability.
- After the priorities: buff Portals, Time Stop and Chain Lightning toward the Rare+ rule.

## 2. Order of work (priorities first)

1. **Clean-up and ladder.** Remove Heat Seeker and Ghost (catalog, effects, looks, icons,
   tests, bots, tutorial), the retired-id map, the new ladder, `Default = "Magnet"`, the
   tutorial back to Magnet.
2. **Magnet buff.** Bigger zone and stronger bend; a ball in the zone is visibly *caught*:
   braked hard as it enters, then crept in slowly, even when it was already going in.
   Measured with `tools/ult_value.luau`; field lines and pocket glow brighter.
3. **Catch-a-Ball (Rare).** A red and white catch ball (square button, a black band with a
   zig-zag hinge: clearly the reference, not the trademark). Physics: at the first contact
   the hit ball is caught (`Ops.remove`, counted as a pot for its owner), the cue ball stops
   dead, a `slow` event holds the shot for the catch. Look: the ball pops open, a red beam
   pulls the target in as a warped glowing silhouette, the ball snaps shut, hops, drops to the
   cloth, wobbles one, two, three times with a click and sparkle stars. Our own soundalike
   catch sounds.
4. **Verity (Legendary).** The cue ball becomes a yellow smiley ball; arming plays "Hi, I'm
   Verity, trust me, I know everything!" (a TTS placeholder until the designer uploads the
   real clip). At the first contact the ball unfolds into the full Verity (Meshy model,
   rigged), grabs the hit ball and hurls it off the table (counted as a pot), then sprints
   forward along the shot line through the pack: every ball in its path is kicked aside
   (deterministic, it can help or hurt both sides). It shrinks back into the cue ball where it
   stops.
5. **Look Over There! (Epic).** Its own cutscene: the shooter's avatar points, a chat bubble
   "LOOK OVER THERE!", the alert "!" sting. Every opponent's camera swings away from the
   table and their avatar turns round ("?" over their head). The shooter gets the sneak:
   grab any one of their balls (touch, mouse or gamepad stick) and drag it into a pocket
   before the ~3 s bar runs out. The opponent turns back, the ball is gone, vine boom.
   A new engine phase `Sneak` with a server-checked drop.
6. **Steel Ball (Legendary) look.** A real chrome cue ball; armed, it spins up like a fidget
   spinner (motion rings, rising whine). At the hit the golden spiral (golden rectangle
   squares plus the spiral) draws itself in yellow over the contact, and each guided ball spins
   visibly fast while it is auto-aimed into its pocket. Rules unchanged.
7. **Guangdong Tiger (Mythic) model.** A new tiger from Meshy, cleaned and decimated in
   Blender, rigged with a quadruped skeleton and animated by bones (run in, leap, claw swipe,
   roar), its cut ball halves lingering like Black Flash's.
8. **Rare+ buffs** (Portals, Time Stop, Chain Lightning), then extra polish on the other looks
   if time remains.
9. **Bots** use the new abilities (the PC's activation policy, a PC sneak), and the value
   harness measures each new one.

Every step: `tools/lint.sh`, `tools/test.sh`, then Studio play-tests in our own window on PC
and the phone emulator (gamepad by hand), console read, screenshots, commit, push
`abilities-rework`.

## 3. Rules details (pure, Lune-tested)

- **Catch-a-Ball** `Effects/CatchABall`: `after` finds the cue ball's first `ballHit`; the
  hit ball (unless it is the 8 off the legal 8 shot) is removed with an `ult` "catch" event
  (ball, x, y); the cue ball's velocity and spin are zeroed and it is moved to the contact
  point less a small bounce back; a `slow` event holds the shot for `HoldSeconds`. The 8:
  a "breakfree" event, the 8 bounces off as a normal contact.
- **Verity** `Effects/Verity`: the first contact removes the hit ball ("throw"; the 8 off the
  legal 8 shot is respotted instead), then a run of `RunInches` along the cue ball's heading
  at `RunSpeed`: the cue ball is ghosted and moved kinematically; every object ball whose
  centre comes within `KickRadius` of the runner is kicked away from the run line at
  `KickSpeed` (plus a forward share), once each. The run stops at a cushion; the cue ball is
  put down on the nearest free spot (Ghost's old clear-off logic, kept here).
- **Look Over There!** catalog row `Sneak = true`: after the arming wait the engine enters
  phase `Sneak` for `SneakSeconds` (shot clock paused). The shooter's `Sneak` action carries
  `{ ball, x, y }` (the drop); the server checks the phase and deadline (with a grace), that
  the ball is the shooter's legal ball, and the drop: inside a pocket's opening = potted
  (into that pocket; the 8 only into the called pocket on the legal 8 shot), else a free spot
  on the cloth = moved there, else nothing. The ult is spent, the table returns to the phase
  it came from. Snapshot carries `sneak = { by, ball, pocket?, x, y, endsAt }` for the looks.
- **Magnet buff** numbers come from the harness; target Uncommon worth about 0.5 ball.

## 4. Assets

| Asset | Tool | Notes |
|---|---|---|
| Catch ball shell halves, button, hinge | Blender script `tools/blender/abilities/catchball.py` | two halves for the open/close, the ball mesh's UVs |
| Verity smiley ball skin | GPT image + Blender | the cue ball's texture while armed |
| Verity monster | Meshy (image-to-3D from the designer's picture), Blender clean, rig, decimate (~8k tris) | bones driven by baked keyframes in a client data module |
| Tiger | GPT image reference, Meshy image-to-3D, Blender quadruped rig (~10k tris) | run, leap, swipe, roar baked to keyframes |
| Steel ball chrome, spinner rings, golden spiral | Blender script, generated textures | the spiral as a decal drawn in by a gradient mask |
| Icons for the three new abilities | Blender renders like `icons.py` | |
| Cutscene art | as the existing panels | |
| Sounds | Creator Store soundalikes (catch wobble/click, alert "!", vine boom, whoosh), OpenAI TTS placeholders for the two voice lines | the designer can replace the Verity line |

## 5. Hand-off list for the GUI session (screens we do not build)

Filled in as the work goes: the Abilities screen's cards for the three new abilities (icons
and names are data, so they show up by themselves), the spin screen's odds panel (data driven),
anything else a screen should show.
