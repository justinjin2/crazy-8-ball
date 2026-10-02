# Lane: Leaderboards

Folder `~/Desktop/8ball-leaderboards`, branch `lane-leaderboards`, Rojo port 34876, Studio file
`place/lane-leaderboards.rbxl`. Rules for all lanes: [README.md](README.md).

## The job

ROADMAP 6.4 (GDD section 11): nothing exists yet except the win streak over the head. Build the
leaderboards the designer wants, for example highest rank (rank XP) and most wins against
people, all-time and weekly, with "your place" shown even when you are not on the board.

- Scores come from the server only (rank XP and wins already live in the save:
  `RankXp`, `Progress.Wins`, `Stats`). PC matches and bots never put anyone on a board, and
  bots never appear on one.
- Storage: CLAUDE.md says saves never use a raw DataStore call. A board needs an
  OrderedDataStore; ask the designer to allow that one exception, kept in one server module,
  written from the server when a score changes, never read as a save. Respect DataStore limits
  (batch writes, refresh boards every minute or so).
- Boards in the world are built by code at positions in Config (no Edit-mode building; if the
  designer wants a physical board model, ask the integrator). A menu version for phones may be
  needed too.
- Zone signs on the hub map (ROADMAP 4.1) are yours if there is time.

## You own

- New: `src/server/Leaderboards.luau`, `src/client/Leaderboard*.luau`, `Config.Leaderboards`,
  `Strings.Leaderboards`, tests for any pure ranking or formatting code.

## Ask the designer (in the interview)

- Which boards, how many rows, all-time and/or weekly (when does the week reset), where they
  stand in the world, what a row shows (avatar, name, rank badge, number), reference images.
- Country flags and a nation board (ROADMAP 6.4): in or out for release?

## Status

## Requests to other lanes or the integrator

## Decisions (dated; the integrator copies them to DECISIONS.md)
