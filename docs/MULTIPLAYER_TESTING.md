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

- Heads belongs to the host's team; the coin names the breaker. Move the cue ball along
  the dotted line, confirm or shoot early. Keep the existing drag aim and pull-down power
  cue. Fine controls offer aim/power or placement buttons plus SHOOT. During placement,
  Lock finishes setup and Close returns to the drag controls.
- PC: drag aim, scroll zoom, power bar, spin disc; L opens leave confirmation.
- Touch: drag aim, pinch zoom, power bar, spin disc; use the visible leave button.
  Test portrait and landscape, including rotating during placement.
- Controller: left stick aims, right stick zooms, R2 shoots; A is the hold/release fallback.
  L1 + right stick selects spin, Y centers it, B backs out/opens leave. X toggles fine
  controls; select buttons/pockets with UI navigation and A. Pocket choice focuses a
  target automatically when controller input is active. Use fine placement buttons when
  dragging is unavailable.
- Finish a full rack in **each** mode. In teams the next teammate shoots after every
  accepted shot, including a scoring shot. Check the next time a team gains possession
  that rotation continues and skips disconnected players.
- Groups remain open after the break. A legal non-break scoring shot assigns the first
  pocketed ball's group. HUD ball slots remain in place and cross out sunk balls.
- On the 8, choose a blue pocket; only that call remains highlighted while aiming.
  Clicking/focusing another pocket changes the call without restarting the clock.

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
