# Lane: Bots

Folder `~/Desktop/8ball-bots`, branch `lane-bots`, Rojo port 34874, Studio file
`place/lane-bots.rbxl`. Rules for all lanes: [README.md](README.md).

## The job

Nothing exists yet: "Play against PC" on the host card says "Coming soon" (ROADMAP 2.4, GDD
sections 6 and 11). Build, in this order, each step verified before the next:

1. **The PC opponent at a 1v1 table.** A bot per rank: ten levels, Bronze (a beginner can
   beat it) to Reyes (hard for a strong player). It picks reasonable shots through the real
   rules and physics (pure code under `src/shared/Bots/` so it is Lune-tested: shot search,
   skill as aim and power error, safeties and ball in hand), plays with a human-like delay,
   and uses its ability by the policy already in `Config.Ults.Pc`. A player meets the bot of
   their rank. PC matches already pay PC XP and money (Config.Ranks.PcXp, Config.Economy PC
   rows): use those, do not change them.
2. **PC fill** for empty seats at 2v2 and 3v3 tables.
3. **Lobby bots** (the designer, 2026-10-02): in an empty server, a few bots walk around and
   play at tables so a new player is not alone. Roblox rules: they must not pretend to be real
   people. Give them generated outfits (random catalog items), never a copy of a real user's
   avatar; made-up names; never on a leaderboard or a player count; a real player can always
   tell, or ask the designer how they should be labelled. They step aside when real players
   want the table.

The Tutorial lane needs a "disguised PC" for a new player's first match (GDD section 14): make
the bot's look and name settable so the tutorial can use it; tell the Tutorial lane how (in
your status).

## You own

- New: `src/shared/Bots/`, `src/server/Bots/` (or `BotService.luau`), `Config.Bots`,
  `Strings.Bots`, tests `tests/bots_*_test.luau`.
- The PC paths in shared files: the "Play against PC" and seat-fill hooks in `TableService`
  and the server side of the host card; `Config.Ults.Pc`. The host card's look (`QueueMenu`,
  `OpponentPrompt`) is the GUI lane's: change only the logic you need there and list it.

## Ask the designer (in the interview)

- How each bot should feel (reference clips or images): how fast it shoots, how it misses,
  does it talk or emote, does it show a name and rank, a versus screen?
- Lobby bots: how many, what they do, how they look, how they are labelled, when they leave.
- Does the bot of your rank use your current rank or your peak? Can you pick an easier bot?

## Status

## Requests to other lanes or the integrator

## Decisions (dated; the integrator copies them to DECISIONS.md)
