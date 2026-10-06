# Pitfalls: what broke or looked wrong, and the fix

## Rendering

- **Whole-pixel snapping.** Roblox draws GUI positions and sizes in whole pixels, with no
  sub-pixel GUI rendering. A slow Position, Size or UIScale tween steps (still, still, jump)
  and reads as a 2 fps sprite. Fix: move the picture inside a still label (`ImageRectOffset`
  / `ImageRectSize`) or rotate (motion.md, section 3).
- **A rect past the texture's edge is clamped**: the window stops moving. Give every moving
  picture a clear border and keep windows inside (tested in Lune).
- **A shared border stretches wide pictures**: `breatheRect` trims pixels; trim each axis by its
  share of the border (`border * side / max(w, h)`) or a 1024 x 344 picture draws 10% too tall.
- **CanvasGroup** for reveals or fades: black, blank or flickering on phones, blurry at low
  graphics, and it clips the overshoot. Never use it; the Stage code fader fades groups.
- **ViewportFrame**: costs a render target and dipped now and then in the scroll test; at most
  one per screen, upright (it is neither rotated nor clipped inside a rotated frame).
- **Only the first UIScale on an object applies** (a second one does nothing). Animate the
  object's one UIScale (UIAnim's `AnimScale`, which Stage shares); a candy button's press
  scale sits on its inner `Body`.
- **Images over 1024 px** are downscaled by Roblox: make every picture at most 1024 on its
  longest side and lay out pieces so none needs more.
- **`ImageColor3` only darkens**: a white picture can be tinted any colour, a coloured one
  cannot be brightened. Draw tintable effects white; bake hot cores into coloured flipbooks.
- **Clipping**: `ClipsDescendants` clips to the rectangle, not the UICorner; rotated children
  clip only with `StarterGui.ClipsDescendantsSupportsRotation`.

## Motion and taste

- **A low-frame-rate flipbook looks choppy.** The Firework Cue's gold ribbons played at
  6.7 fps (half speed, as asked) and the designer called them choppy. A breathe of the whole
  cue moved the hero; a rock swung the long ribbons off the cue. What stayed: one still frame
  that dims and glows (`glowPulse`). Play flipbooks at 30 fps or use a still with a pulse.
- **Moving the hero instead of its decoration.** "Make the ribbons breathe" meant the ribbons,
  not the cue. Ask which part moves when a note could mean either; default to the small part.
- **Rocking long things**: a few degrees moves a long picture's ends many pixels; rock small,
  round things (icons, the flair, stars), pulse or sweep long ones.
- **Two labels animated in step drift apart** (two UIScales, two loops at different phases).
  Bake them into one picture (the crowned block) or drive both from one loop (the breathe
  takes a list of pictures).
- **Loops in sync look mechanical**: give every loop a random phase.
- **Shine everywhere is noise**: shine only what should draw the eye (only the Robux buttons).
- **Text never moves slowly, never pulses its scale endlessly**, and never tweens a UIStroke's
  thickness. Pop it in, then leave it still (a big word may rattle now and then).

## Layout

- **The target's proportions may not fit the panel**: 13b's 3:1 card at the panel's width made
  28 px buttons and 10 px words. Keep the target's look and order, choose the screen's own
  units, and check touch targets (44 px) and text minimums at the real size.
- **A phone page restacked** the card into a tall column the designer did not want: keep the
  computer arrangement and scale it to fit the page whole.
- **Kit text minimums are in screen pixels** (a UITextSizeConstraint holds even inside a
  UIScale below 1), so a screen scaled down draws its small words bigger than their boxes. Lay
  out at the drawn size, or allow a smaller minimum for that screen in its Config (`MinTextPx`).
- **`TextScaled` and `TextWrapped` are coupled**: setting `TextWrapped = false` turns
  `TextScaled` off.
- **A UIGradient on a TextButton tints its text too**: draw a button's face as a child frame
  and its words as a separate label.
- **The menu covered the whole phone**: the lively panel is capped (66% of the width, out of
  Roblox's top bar row, as tall as its first card).

## Studio and tools

- **The emulator cannot be switched by the MCP**, and only with Play stopped; ask the designer.
- **Mouse input in the emulator lands off by (-62, -20)**: click by raw coordinates
  (verification.md).
- **A play session started before a change runs the old client**: restart Play after Rojo syncs.
- **An MCP `execute_luau` that waits** (a long `task.wait`) can time out into the background and
  fail later with "Target is closed" when Play stops; keep waits short.
- **A module required from the MCP is a separate copy**: it cannot read live player data; use
  the QA hooks (`PlayerDataQA` `read`, docs/STUDIO_NOTES.md) or the console.
- **Upload returns a Decal id**, which fails in `ImageLabel.Image`; read the image id in
  Studio (art-pipeline.md).
- **Studio's `GetProductInfo` shows about 0.8x each price** for the designer's account; it is
  not a bug.
- **Regenerating cue skin data** (`tools/cue_skins_data.py`) rewrites every skin file; revert
  the ones another session owns before committing.
- **No Studio-beta features in the build** (the upgraded UIGradient cannot be published).
  Welcome and live: UIShadow, several UIStrokes per object, per-corner radii.
- **Parallel sessions share the tree**: commit only your own files by explicit path; never
  `place/8ball.rbxl`.
