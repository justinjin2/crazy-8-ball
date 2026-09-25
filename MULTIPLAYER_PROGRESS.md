# Multiplayer progress

Updated 2026-09-22. User authorized implementation with **begin**.
Read MULTIPLAYER_SPEC.md, inspect git and verify the live place before resuming.

## Implemented
- Shared pure MatchEngine, ShotJudge and CuePlacement; configurable 1v1/2v2/3v3.
- Three tables, individual team queue slots, host reassignment, cancellation-safe
  intermission and one server coin result. Baseplate retained.
- Server-owned turns, teammate rotation, open-table assignment, break and 8-ball rules,
  placement, pocket calls, synchronized deadlines, timeouts and shot settling.
- Unanimous surrender, shorthanded disconnects, reset/death handling, empty-team loss,
  table reuse, character/camera restoration and action/rate validation.
- Responsive team HUD, six portraits/fallbacks, stable numbered ball slots/X marks,
  perimeter clock, status/coin/result presentation, modal confirmation and voting.
- Existing orbit/physics/spin/power/audio retained. Temporary top-down setup views,
  private placement/pocket controls, precision buttons, invalid-target crossed ghost,
  own-ball highlights and team-only bonus audio integrated.
- All source changes saved under src; agreed decisions saved in MULTIPLAYER_SPEC.md.
  Studio-only QA hook in ServerStorage creates nothing in published servers.

## Verification so far
- 195 Lune tests pass; latest StyLua, Selene, luau-lsp and diff whitespace checks pass.
- Correct Studio place 107430170196919, universe 10767330648; Rojo source sync checked.
- Fresh desktop and iPhone-emulator portrait/landscape runs start without project errors.
- Native screenshots inspected for queue, 1v1 red tenths clock, 2v2 confirmation,
  3v3 placement, pocket choice and desktop aiming. Six-player crowding, target inset,
  camera clearance, hover-tween error and avatar-anchor cleanup defects repaired.
- Actual client remote shot accepted and replayed to completion without drift warning.
- Three concurrent server fixture shots replayed on one real client. All 45 object balls
  matched server positions within 0.000006 inches after settling; three clean replay logs.
  Fixture participants are synthetic identities, not six real network clients.
- Live L -> No cancels; L -> Yes in 1v1 produces YOU LOSE and restores CameraType.Custom,
  WalkSpeed 16, AutoRotate true and zero anchored character parts.
- Team-mode Yes sends a vote without ending play; a fixture teammate's Yes completes
  unanimous surrender. Pocket target keyboard focus + Return enters Aiming with that call.
- Coin, turn and foul sound asset preload availability verified earlier in this experience.

- Prepared final-8 positions produced actual simulated LegalEight wins in every mode.
  Each duplicate client shot was rejected; each original produced one replay/result.
- Actual current-shooter death retained all six seats, applied a foul, respawned alive
  inside the match bounds, and left deadlines running.
- Actual cue-ball drag preserved the break line; precision aim changed the angle and
  SHOOT accepted a shot. The final phone portrait/landscape controls were visually checked;
  Lock advanced to Aiming with 15 seconds. Short controls replace the placement panel,
  and camera clearance follows the visible panel height.
- Sampled coin animation rotated, narrowed, landed and cleared on schedule. Result,
  foul and coin screenshots were inspected; screenshots do not prove motion quality.
- Latest fresh runtime console contains only server/client ready messages. Final lint
  and 195 tests pass (6.81 s). No Edit-mode content was modified.

## Current work / next concrete step
Implementation and available automated/Studio QA are finished. Core implementation was
committed and pushed as 61e3eab; final responsive polish and this evidence are saved in the
following git commit. Studio Play was stopped to remove all synthetic fixtures.
Next: relaunch six clients on the current Rojo source and follow docs/MULTIPLAYER_TESTING.md
for real multiplayer and device acceptance. Do not describe these pending checks as done.

## Remaining acceptance / tool limits
- Six actual clients launched earlier and joined their local server, but MCP exposes only
  original Studio instance b77c47f1-c381-429e-bb30-6183779536e0. Cannot drive/read those
  separate clients. They must be relaunched for the new source before real acceptance.
- Full human multiplayer matches, physical touch/controller play and listening acceptance
  remain unverified. Emulated layouts and scripted inputs do not replace them.
- Direct pointer automation fails/scales incorrectly in device emulator; native coordinate
  clicks fail noWindowsAvailable. AX menus, screenshots and keyboard focus work.
- Existing imported table art differs slightly from the regulation physics pocket geometry;
  preserve it per instruction. No Edit-mode assets changed or published.

## Recovery
Do not edit Script.Source in Studio. Verify correct place after reconnection. Check whether
an interrupted operation completed before repeating it. Source files are the durable save;
notes do not replace source. Stop/start Play to refresh Rojo's runtime copy.

## Follow-up: compact top HUD (2026-09-22)
User reported oversized panels in real multiplayer screenshots. Team panels now fit
portraits plus ball rows, 56 px high on desktop (formerly 150), at y=4 beside Roblox
menu where there is room. Narrow screens reflow ball rows without shrinking the whole UI.
Screenshots inspected for all three modes; component bounds checked at 402/750/1000 px;
all phase labels fit. Lint clean, 195 tests pass (7.09 s), Rojo confirmed in correct place.
Play stopped to clear fixtures. Relaunch existing test clients to load the new source.

## Follow-up: playtest fixes (2026-09-22)
Commits 08d5bc8 (home view camera, top-down only for the 8 call), 7c38f9a (bonus at the
drop, instant group reveal, live red X), ab2752a (3D placement with prediction, no Lock,
call-before-placement). Lint clean, 222 tests pass.

Studio checks on one client with fixtures:
- The home view pose matches `Camera.viewAt(..., ZoomDefault)` exactly (35 deg, 5.28 studs).
  The same holds after the pocket call.
- The pocket call is top-down.
- A real mouse drag moved the ball under the pointer every step while the camera held.
  On release the server's spot matched the client.
- On an assignment shot the HUD reveal and the red X appeared in the drop frame. The local
  team's bonus played in the same frame as its drop; the opponent's ball played none.
- No drift warnings.

Not yet checked: phone emulator layout of the new placement instruction, LT + stick and
held arrows on a real controller, watcher smoothness on a second client, and listening.
