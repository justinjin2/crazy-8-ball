# Lane: Tutorial (first-time playthrough)

Folder `~/Desktop/8ball-tutorial`, branch `lane-tutorial`, Rojo port 34877, Studio file
`place/lane-tutorial.rbxl`. Rules for all lanes: [README.md](README.md).

## The job

ROADMAP 8.1, GDD section 14 (read it first): a brand-new player's first minutes. The GDD has a
plan (a hidden popup, a disguised PC that walks in and blunders, a ghost break guide, the longer
tutorial guideline `Config.Guideline.TutorialStubLengthInches`, the first win's Rare Case that
already exists, Unranked to Bronze I on that first win). Confirm it all with the designer: their
pictures may differ.

- **Depends on Bots.** The first opponent is a disguised PC from the Bots lane, which is being
  built at the same time. Build the flow, the guidance, the popups and the camera moments first
  against a stand-in (a scripted opponent or Solo), keep the opponent behind one small
  interface, and plug the real bot in once Bots is merged into `release` (watch `bots.md`).
- Remember who has done it with a flag in the existing save `Flags` map (add a PlayerData
  mutation as a new function); do not change the save layout (only Economy may).
- Every step must work on phone, PC and gamepad, and be skippable for players who know pool.

## You own

- New: `src/client/Tutorial*.luau`, `src/server/TutorialService.luau` (or similar),
  `Config.Tutorial`, `Strings.Tutorial`, GDD section 14.
- The tutorial hooks you add to `TableService`, `Main.client.luau`, `Bootstrap.server.luau`
  (list each).

## Ask the designer (in the interview)

- What a new player sees from the moment they join, step by step, with reference images:
  where they spawn, what points them to a table, what is explained and how (arrows, text, a
  hand, a voice?), how the first match goes, what happens after.
- Is the first opponent disguised as a real player or shown as PC? (GDD: disguised in the
  first match only, never on a leaderboard, stored as PC.)

## Status

## Requests to other lanes or the integrator

## Decisions (dated; the integrator copies them to DECISIONS.md)
