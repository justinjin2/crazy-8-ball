# Lane: Cutscenes and reward moments

Folder `~/Desktop/8ball-cutscenes`, branch `lane-cutscenes`, Rojo port 34875, Studio file
`place/lane-cutscenes.rbxl`. Rules for all lanes: [README.md](README.md).

## The job

Turn the big moments into cutscenes the designer has very specific pictures of:

- **After a match**: the result (win and loss), the money and XP counting up, the free case.
- **Pulling a rare cue** from a case: the build-up and the reveal by rarity (Epic, Legendary,
  Mythic, Secret should each feel bigger than the last).
- **Opening a case**: the reel, Fast Open's grid.
- **Rank-up** (NEW RANK!, a new tier) and **ability spin reveals**, if the designer wants them in.
- The in-match ability cutscene (`UltCutscene`) only if the designer asks for it.

The basic versions exist; read them first and keep what works (the server already sends
everything: the match summary, case results, rank results).

## You own

- Client: `CaseOpening*.luau`, `ResultScreen`, `PostMatch`, `NewRankPopup`, `RewardsFlyer`,
  `CashFlyer`, `Banner`, `UltSpinAnim`, `UltStage`, `UltCutscene` (only if asked), and any new
  cutscene modules.
- Config: `UI.CaseOpening`, the result screen and rank popup rows of `Config.UI`, new
  `Config.Cutscenes`; the sounds for these moments in `Config.Audio`/`UISound`.
- Uploaded images, sounds and meshes for these moments (ids in Config).

Not yours: what a reward is or costs, and what the server sends (Economy; ask in your lane
file if you need more data in a payload); every other screen and the shared UI kit (GUI lane:
follow `docs/UI_STYLE.md` and any new style GUI writes there).

## Ask the designer (in the interview)

- For each moment: reference images or clips, what happens second by second, the camera,
  colours, text, sounds, how long, can it be skipped (it must be skippable after the first
  time or two), what other players in the server see.
- Phone, PC and gamepad: how each is skipped or continued.

## Status

## Requests to other lanes or the integrator

## Decisions (dated; the integrator copies them to DECISIONS.md)
