# Parallel build: five lanes and one integrator (2026-10-02)

The designer is finishing the release with several Claude terminals at once. Each terminal is a
**lane**: one system, its own git worktree and branch, its own Rojo port and its own Studio
window. One more terminal, the **integrator** (in `~/Desktop/8ball`, branch `release`), merges
the lanes, owns the real Team Create place and publishes.

If you are a lane, read this whole file, then your own lane file, before doing anything else.
CLAUDE.md still applies in full; this file only adds the rules for working side by side.

## The lanes

| Lane | Folder (worktree) | Branch | Rojo port | Studio file | Lane file |
|---|---|---|---|---|---|
| Integrator | `~/Desktop/8ball` | `release` | 34872 | the Team Create place | this file |
| Economy | `~/Desktop/8ball-economy` | `lane-economy` | 34873 | `place/lane-economy.rbxl` | [economy.md](economy.md) |
| Bots | `~/Desktop/8ball-bots` | `lane-bots` | 34874 | `place/lane-bots.rbxl` | [bots.md](bots.md) |
| GUI and cutscenes | `~/Desktop/8ball-gui` | `lane-gui` | 34876 | `place/lane-gui.rbxl` | [gui.md](gui.md) |
| Tutorial & funnel | `~/Desktop/8ball-tutorial` | `lane-tutorial` | 34877 | `place/lane-tutorial.rbxl` | [tutorial.md](tutorial.md) |

`tools/lanes.sh` creates the worktrees and place copies (`setup`) and starts a lane's Rojo in
the background so it outlives the terminal (`rojo <lane>`; `status` shows them all).

## How a lane works

1. **Interview first, in plan mode.** The designer has exact pictures in mind. Their reference
   images are in `~/Desktop/8ball-refs/<your lane>/` (outside git, readable by every terminal;
   a filename or a `notes.md` there may say what each shows), and they may paste more into your
   terminal; they may also paste design notes they organised beforehand. Look at every image
   in your folder first. Pasted images are not saved anywhere, so your brief must describe each
   reference in words and name its file: what it shows, which parts to copy (layout, colours,
   timing, motion, sound) and which to ignore. Reopen the files whenever you check your work
   against them. Ask until nothing is guessed. Then write
   `docs/prompts/<LANE>_PROMPT.md` (the brief) and get the designer's approval.
2. **Build in small verified steps** inside your own worktree. After each step: `tools/lint.sh`,
   `tools/test.sh`, a Studio check in YOUR window, commit and push your branch.
3. **Write your status** in your lane file (below its "Status" heading): what works, what is
   checked on PC / phone / gamepad, what you changed in shared files, what you need from
   another lane or the designer. The integrator reads these at every merge.
4. **Take the integrator's merges.** When the integrator says `release` moved, run
   `git merge origin/release` (after `git fetch`), fix anything it broke in your area, run the
   tests, push.

## Rules that keep the lanes from breaking each other

- **Studio.** Use only YOUR Studio window. Every MCP call names its `studio_id`; pick the one
  whose name is your place file (`lane-bots.rbxl`, ...), never the Team Create place
  ("Crazy 8 Ball"), never another lane's. Start and stop play only in your window. If you
  cannot find your window, stop and ask the designer.
- **Rojo.** Only your port. Never connect anything to 34872 (the integrator's).
- **Use your Studio window freely to check your work in the real game**: play-test (start
  and stop play), inspect, read the console, take screenshots, emulate phone, PC and gamepad,
  watch bots play and cutscenes run. That is expected for every step.
- **Building and importing in your window is allowed** (parts, models, imports, lighting), to
  test or to see how something looks. But your window is a private copy of the place, and a
  merge carries your folder (code and files), not your copy. So before you call anything done,
  everything the real game needs must travel with your branch, one of three ways:
  1. made by code at run time (preferred), or
  2. saved as a model file (`.rbxm`/`.rbxmx`) under `src/` so Rojo syncs it (code clones it
     where it belongs), or
  3. written in your lane file's Requests with exact details (asset ids, sizes, positions,
     properties) so the integrator rebuilds it once in the real place.
  Anything only built by hand in your copy is lost at the merge.
- **Your area is yours; other areas are read-only.** Each lane file lists what it owns. To
  change something another lane owns, write a request in your lane file and keep going.
- **Shared files** (`Config.luau`, `Strings.luau`, `Net.luau`, `Main.client.luau`,
  `Bootstrap.server.luau`, `TableService.luau`, `PlayerData.luau`, `Ranking.luau`): add your
  own new section or function, as a block, near the end of the matching part of the file;
  change existing lines only when your feature needs it, and list each such change in your lane
  file. Never reformat, reorder or rename what is not yours. Run `tools/format.sh` only on
  files you changed.
- **The save format belongs to the Economy lane alone.** Only Economy bumps
  `SaveSchema.Version` (to 6, once). Other lanes do not change the save layout; a yes/no flag
  goes in the existing `Flags` map (a PlayerData mutation such as `setFlag`, added as a new
  function). If you truly need a new save field, ask Economy through your lane file.
- **Docs.** Do not edit `docs/STATUS.md`, `docs/ROADMAP.md` or `docs/DECISIONS.md`: write your
  status and your dated decisions in your lane file and the integrator moves them over. You
  may edit your own GDD section and your own brief/report in `docs/prompts/`. ECONOMY.md
  belongs to the Economy lane.
- **Git.** Commit only on your branch, small and often, with the attribution line. Push your
  branch. Never push to `release` or `main`, never force-push, never merge another lane's
  branch.
- **Designer-only commands** stay designer-only (CLAUDE.md). New dev commands go in
  `DevCommands.luau` as a block of their own.

## The integrator

- About every 2 hours (or when a lane says a step is done): fetch, merge each lane into
  `release`, run lint and tests, sync `release` into the Team Create place, playtest, and tell
  the lanes to take the merge. Moves lane statuses and decisions into STATUS, DECISIONS and
  ROADMAP.
- Builds in the real place anything a lane listed in its Requests (way 3 above).
- Owns the game page, the Roblox compliance questionnaire, the performance pass, the final
  check on a real phone and controller, and publishing. `release` goes to `main` at release.

## Order and dependencies

- Bots is the biggest job: start it first.
- The tutorial's first opponent is a disguised PC from the Bots lane. Build the tutorial's
  flow, popups and guidance first with a stand-in, and plug the real bot in once Bots is merged.
- **Numbers vs screens.** Economy decides every number (money, XP, odds, rarities, prices,
  products) and the server code behind purchases; GUI decides how every screen looks and
  works, the shop and every reveal moment included (match result, case opening, pulling a
  cue, rank-up). A screen shows what the server already sends; if GUI needs a new field, ask
  the integrator in your lane file.
- **GUI owns every screen and cutscene** (the Cutscenes lane was folded into it, 2026-10-03).
  It follows `docs/UI_STYLE.md` and writes any new style the designer agrees there.
