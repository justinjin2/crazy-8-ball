# Multiplayer acceptance and reproducible checks

The three tables are left-to-right **1v1, 2v2, 3v3** when arriving from the spawn.
Source is saved in git and streamed by Rojo. Results are match-only; nothing awards money
or saved wins. The lounge is intentionally disabled.

## Start the current build

1. In the original Crazy 8 Ball Studio window, choose **Test → End Session** to close
   old local tests. Already-running clients retain the source from when they launched.
2. Check the Rojo plugin says connected to `8ball` / `localhost:34872`.
3. Choose **Test → Start Test Session → Server and Clients**, set **6** clients and Play.
4. Use two clients for the left table, four for the middle, or all six for the right.
   Each person steps into one white square. Each side's A/B slots choose that team.
   Remain in the queue area until it fills and the five-second countdown finishes.

## Play each mode

- Heads belongs to the host's team; the coin names the breaker (a HUD overlay; nobody's
  camera is taken for it). The breaker starts in the **home view**. Drag the cue ball
  along the dotted line (press on the ball itself) and shoot whenever you like; there is
  no Lock button. After 15 seconds the ball stays put and the 20-second aim clock runs.
  Keep the existing drag aim and pull-down power cue. Fine controls offer aim/power and
  camera-relative placement arrows (hold to repeat) plus SHOOT.
- Ball in hand after a foul works the same way, anywhere on the cloth: the ball follows
  the finger with no lag and slides around balls and cushions. Watch it from a second
  client: the watcher's ball should glide, not jump.
- The ONLY top-down view is calling the 8-ball pocket. After the call (or its timeout)
  the camera returns to the home view. Ball in hand on the 8: call first, then place.
- PC: drag aim, scroll zoom, power bar, spin disc; L opens leave confirmation.
- Touch: drag aim, pinch zoom, power bar, spin disc; use the visible leave button.
  Test portrait and landscape, including rotating during placement.
- Controller: left stick aims, right stick zooms, R2 shoots; A is the hold/release fallback.
  L1 + right stick selects spin, Y centers it, B backs out/opens leave. Hold LT + left
  stick to move the cue ball during placement. X toggles fine
  controls; select buttons/pockets with UI navigation and A. Pocket choice focuses a
  target automatically when controller input is active. Use fine placement buttons when
  dragging is unavailable.
- Finish a full rack in **each** mode. In teams the next teammate shoots after every
  accepted shot, including a scoring shot. Check the next time a team gains possession
  that rotation continues and skips disconnected players.
- Groups remain open after the break. A legal non-break scoring shot assigns the first
  pocketed ball's group: the HUD rows appear and the owning team hears the bonus the
  instant that ball drops, not when the balls stop. HUD ball slots remain in place and a
  red X crosses out each sunk ball the moment it drops.
- On the 8, choose a blue pocket; only that call remains highlighted while aiming.
  The call is final: the other pockets disappear and cannot be picked.

## Play solo

- Stand alone on any white square of any table. A green **Play Solo** button appears under
  the header (controller: select it with UI navigation, then A). Press it: the break starts
  at once with YOUR TURN, no countdown or coin, and nobody else can join that table.
- There is no clock anywhere. A foul (illegal break, scratch, wrong first ball, no rail)
  gives you ball in hand again. The first ball you pocket legally after the break picks the
  group you clear first; the HUD row shows that group, then the other, then the 8.
- Clear both groups, call the 8 and sink it: YOU WIN. The 8 early, on a foul or in the
  wrong pocket: YOU LOSE. Leave → Yes: MATCH ENDED. Step off and back on to play again.

## Shooter pose (2026-09-24)

Use **Server and Clients** with 2 clients on the 1v1 table (or 3 with a spectator).
- Shooter: your body is translucent. Aim all the way round the table: you never stand in
  it. Near your own cushion you lean or bridge on the rail; further out a rake appears under
  the cue; for far balls the cue grows an extension. Near a rail the cue tilts up and never
  goes through the wood.
- Watcher (the other client): the shooter is fully visible, bent over the cue with both
  hands on it (or on the rake), and turns with the aim.
- Pull the power bar slowly: both screens show the cue drawing back. Release: a quick stroke
  through the ball, then the shooter stands in the normal idle on the spot, facing the table.
- Pot a ball (same shooter): straight back into the aiming pose. Miss: the camera and
  walking come back from exactly that spot, with no jump, and the watcher sees no jump either.
- Respawn, leave or rebind mid-aim: no limb stays frozen in the air on either screen.
- Repeat once with an R6 avatar (Game Settings → Avatar → R6) and once on phone emulation
  and a controller.

## Edge cases

1. Fill a queue, leave during countdown, return: it cancels and restarts once. First host
   leaves: the longest-waiting remaining player hosts. Crossing another queue cannot
   reserve two tables. Empty/occupied pads and occupancy text agree on all clients.
2. Wrong first target, no contact, scratch, no rail/pocket, illegal break and clock expiry:
   wait for the shot to settle, then opponent gets legal 10-second ball-in-hand. Try
   overlapping/outside placements, early shooting, and allowing placement to expire.
3. Let a team's shooting clock expire twice without that team accepting a shot between:
   the team loses. Opening a leave dialog never pauses any deadline.
4. Team leave: one Yes starts a 10-second vote; one No or expiry cancels it. All connected
   teammates agreeing loses the match. Repeated requests respect the 30-second cooldown.
5. Reset the current shooter's character before a shot: foul, seat retained, respawn near
   the same table. Reset while balls roll: that shot completes normally.
6. Close one client, keeping its server running: teammates continue shorthanded. If a
   team becomes empty it forfeits; an already accepted shot finishes settling first.
7. Test early/wrong-pocket/foul 8 losses. Scratch without pocketing the 8 is an ordinary
   foul. Sinking the last group ball and the 8 on the same shot loses.
8. Verify both sides' win/lose messages, restored camera/movement/turning and another
   successful queue/match on the same table. Look for old guides, highlights or dialogs.
9. With six clients, run **1v1 and 2v2 simultaneously**. Balls, turns, clocks, private
   controls and bonus sounds must stay independent. Three completely full simultaneous
   modes require 12 participants; the automated engine tests cover that logical state.
10. Inspect all six portraits, long names, ball numbers/stripes, low red tenths timer,
    placement handle, pocket targets and dialogs. Listen for coin/turn/foul availability,
    ownership-correct bonus sound, comfortable volumes and no excessive overlap.

## What has actually been verified

- 195 Lune tests plus StyLua, Selene and luau-lsp (see progress for latest run).
- Pure full-flow tests for all three sizes, legal/foul rules, placement, deadlines,
  rotation, votes, disconnect/reset, epoch isolation and table reuse.
- Real client remote shots and duplicate rejection. Prepared final-8 positions produced
  actual simulated LegalEight wins for all three modes, followed by results/reset. These
  are finishing-position scenarios, not full human matches from the break.
- Three concurrent fixture matches replayed on one actual client; all 45 object balls
  matched the server within 0.000006 inches. No replay-drift warnings.
- Actual desktop placement drag preserves the break line. Focus/Return activates pocket
  calls, precision aim and SHOOT, and Yes/No confirmation. 1v1 surrender restores normal
  camera, WalkSpeed, AutoRotate and all limb anchors. Actual death respawns inside bounds.
- Scripted controller Input handling covers aim, spin, center, shoot-once and leave. It
  does not prove a physical controller works end to end.
- Native screenshots of desktop and iPhone-emulator portrait/landscape layouts include
  all modes, six-player setup, pocket choice, low timer, foul, confirmation, coin and result.
  Camera/coin timing was sampled at runtime; still images do not prove animation quality.

Full six-client gameplay, physical touch/controller play and human listening remain
required acceptance. Tools expose only the original Studio window even though six
separate local clients were confirmed running during preflight.

## Automated / Studio diagnostic entry points

`tools/lint.sh` and `tools/test.sh` run normal verification.

During Studio Play only, ServerStorage.PoolMatchQA is a BindableFunction accessed from
server inspection tools. Commands include snapshot, fixture, phase, action, shot, death,
remove and advance. A fixture uses synthetic identities; `spectator=true` lets multiple
fixture tables run without assigning the real client to all of them. `finalEight=true`
prepares the named final-8 scenario. These controls create nothing outside Studio and
are never client remotes. Stop Play to clear all fixtures and return to the real queues.

If Edit-mode assets are changed in a future pass, save `place/8ball.rbxl` and publish from
Studio once that milestone is accepted. This update generates tables/pads at runtime;
source files and git are the durable implementation save.
