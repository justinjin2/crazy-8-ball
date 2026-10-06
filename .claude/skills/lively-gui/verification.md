# Verification: seeing it, measuring it, showing it

## Contents

1. The loop for every step
2. Driving Studio (MCP, GuiQA, the emulator)
3. Recordings and contact sheets
4. Devices: phone, PC, gamepad
5. Lower effects and Reduce Motion
6. Budgets and performance
7. Gate pages

## 1. The loop for every step

1. `tools/lint.sh` and `tools/test.sh` (the whole suite takes a few minutes; run one file with
   `lune run tests/run.luau stage_math`).
2. Rojo synced (the script shows up under `ReplicatedStorage.Shared` or `StarterPlayer`).
3. Stop and start Play so the client runs the new code (`start_stop_play`).
4. Open the screen through `GuiQA`, read the console, take a screenshot, read the numbers
   that matter (sizes, rotation, transparency over time) with a Client `execute_luau`.
5. Look at it yourself against the target before showing anyone; fix what is off first. If the
   design plugin's `design-critique` skill is available, run it on gate pictures.
6. Commit the verified step (only your files), push, and record the step in the brief.

## 2. Driving Studio

- Every Studio MCP call needs `studio_id` from `list_roblox_studios`. Only one agent drives
  Studio at a time. Never create or edit scripts through the MCP; renaming place instances in
  Edit mode is fine.
- **GuiQA** (Studio only, `src/client/GuiQA.luau`): a BindableFunction in PlayerScripts.

```lua
local qa = game.Players.LocalPlayer.PlayerScripts:WaitForChild("GuiQA", 20)
qa:Invoke("open", "Shop", "Money")   -- open a menu on a tab (Menus.open)
qa:Invoke("close")
qa:Invoke("list")                   -- the registered menus
qa:Invoke("quality", true)          -- Lower effects on (false: off)
qa:Invoke("reduced", true)          -- act as if Reduce Motion were on
qa:Invoke("lab", "stage", 14)       -- Stage on real pieces, the open slowed to 14 s
qa:Invoke("gift", "GrandOpening1", 3) -- the Gift Player popup with 3 stand-in players
```

  Add a screen's own actions with `GuiQA.add(name, fn)` (fake data, a slowed open, a popup with
  stand-ins). They do nothing outside Studio.
- **Measuring motion without a recording**: sample a property in a loop from the Client
  datamodel, e.g. a rock's `Rotation` or a pulse's `ImageTransparency` every 0.5 s, or count
  a shine by connecting `DescendantAdded` on each button's face for a few seconds (the Shop
  check: Robux buttons shone 3 times in 4 s, money buttons 0).
- **Clicking in the phone emulator** (750 x 362): `user_mouse_input` lands (-62, -20) px off,
  and clicks by `instance_path` miss the same way. Click raw x/y = `AbsolutePosition +
  AbsoluteSize / 2 + (62, 20)` and confirm each click by its effect. `AbsolutePosition` is
  relative to the GUI inset (a root at y -58). In the PC window clicks take GUI coordinates.
- `screen_capture` lands a second or two after it is called; for a moment, trigger it in the
  same `execute_luau` call and capture in the same batch.
- Image ids: `InsertService.LoadAsset` in Play's Server datamodel (art-pipeline.md).

## 3. Recordings and contact sheets

- Before a run the designer gives the terminal app Screen Recording permission (System
  Settings, Privacy and Security, Screen and System Audio Recording) and reopens it.
- `tools/gui/record_studio.sh SECONDS OUT.mov` raises the game's Studio window, records the
  screen with `screencapture -v` (Retina, up to 120 fps) and gives focus back. Trigger the open
  through GuiQA right after it starts. Crop to the game view with ffmpeg.
- `tools/gui/contact_sheet.py sheet VIDEO OUT.png --box x y w h --every 2 --cols 6 --width 480`
  numbers every second frame (about 33 ms apart) like the designer's reference stills;
  `contact_sheet.py strip ... --zoom 4` blows up one region frame by frame, so a whole-pixel
  step (still, still, jump) shows.
- `tools/gui/motion_measure.py VIDEO REGIONS.json OUT_DIR` scores how evenly regions move
  (jitter in physical px; 0 is perfect, about 0.4-0.5 means whole-pixel steps). Use it when a
  new slow motion is in doubt.
- Record: the full open, a tab switch, the idle loops for a few seconds, a close, reopening
  mid-close, tab spam. Compare the sheet with the target and the reference videos yourself.
- Keep recordings and sheets in `~/Desktop/8ball-refs/gui-lively/work/<gate>/`, never the repo.

## 4. Devices: phone, PC, gamepad

- **Phone**: Studio's device emulator (the designer switches it by hand, only with Play
  stopped; it applies in Edit too). The Shop was checked at 750 x 362: the panel 495 x 296,
  the first card whole, nothing scrolling inside the first screen.
- **PC**: the designer switches the emulator off or to a computer size. A true 100% DPI view is
  not possible on the Retina Mac (Actual Resolution still draws 2x); use a 1x monitor or macOS
  Low Resolution mode if it matters.
- **Gamepad**: a real controller, plugged in before Play; the designer does it (an agent cannot).
  The checklist: open the menu from the HUD, LB/RB through the tabs, the stick or D-pad
  through every button, A presses, a hover-only thing opens with A (the block's odds), B closes
  the popup then the menu, the selection never escapes the panel (`SelectionGroup`, Stop at the
  edges), nothing unreachable.
- Write these by-hand steps out in the gate message in short numbered clicks; the designer is a
  beginner.

## 5. Lower effects and Reduce Motion

- `GuiQA:Invoke("quality", true)`: bursts off, half the counts, slower sweeps. Count pictures
  shown with it off and on (the Shop: 92 to 67).
- `GuiQA:Invoke("reduced", true)`: only fades; nothing floats, scrolls, rocks or sweeps.
  Check by sampling Position, Rotation and ImageRectOffset: they stay put.

## 6. Budgets and performance

- Each image at most 1024 px. About 6 flipbook sheets visible at once; about 100 animated
  labels; at most 100 UIShadows; at most one ViewportFrame per screen.
- Measure with the screen open: average and worst frame (`Stats`, MicroProfiler), GUI texture
  memory, pictures on screen, with Lower effects off and on. The Shop: 16.7 ms average (60
  fps), worst 26 ms during the open, 20 ms with Lower effects; +53 MB texture while open.
- Every loop stops when its screen closes (check the handles are released: reopen ten times,
  the numbers stay level).

## 7. Gate pages

Show each gate as a private page (the Artifact tool, a dark page in the card's own navy): the
questions first (at most three, short), then one station per change with a screenshot or a
looping video and a caption saying exactly what changed and what to try. The Shop's pages:
gate 2 `https://claude.ai/artifact/VsFSVNxe1VBMgYNxt4oCUA`, the animatic
`https://claude.ai/artifact/ABF5JjwmsSNMqNXw2SU2tJ`, gate 4
`https://claude.ai/artifact/6MinwiDaKQLB8uLoozzu6E`; their sources in
`~/Desktop/8ball-refs/gui-lively/work/gate*/page/`. Republish the same page for a second round
so the link stays.
