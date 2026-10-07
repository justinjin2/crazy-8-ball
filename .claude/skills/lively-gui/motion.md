# Motion: tokens, easing, the smooth technique, Stage and the idle library

## Contents

1. The tokens (Config names)
2. Easing
3. The smooth-motion technique (gate 1, measured)
4. Stage: the reveal player
5. The idle library (UIAnim)
6. Reduce Motion and Lower effects

## 1. The tokens

Approved by the designer in the animatic (2026-10-06). Use them; add new ones to Config with a
comment, never a literal in code.

`Config.UI.Motion` (seconds unless said):

| Token | Value | Meaning |
|---|---|---|
| `Stagger` | 0.04 | between pieces of one group (tabs, buttons, a card's insides) |
| `PopSeconds` | 0.28 | one pop |
| `PopFrom`, `PopPeak`, `PopPeakAt` | 0.6, 1.1, 0.6 | a pop starts at 60%, peaks at 110% at 60% of the way (Quad Out), settles at 100% (Sine InOut) |
| `FadeSeconds` | 0.1 | a piece's fade in, alongside its pop |
| `UnrollSeconds`, `UnrollOvershoot`, `UnrollPeakAt` | 0.2, 1.04, 0.7 | a panel opening from a bar (Quart Out past full height, then settle) |
| `BarPx` | 7 | the bar an unroll starts from |
| `SlamFrom`, `SlamBounce`, `SlamLandAt` | 1.6, 0.05, 0.6 | a slam starts at 160% (Quad In), lands, bulges 5% once |
| `GrowSeconds` | 0.15 | a background opening from its centre, lines growing out (Quart Out) |
| `DropPx` | 45 | a drop falls from this high (Bounce Out) |
| `CloseSeconds` | 0.15 | close: everything fades while the panel folds, no stagger |
| `TabSeconds` | 0.5 | a tab switch: the new page staggers in, no unroll |
| `BurstFps`, `BurstShare` | 30, 1.4 | a reveal's firework: 64 frames at 30 fps, 1.4 x its piece |
| `ReducedFadeSeconds` | 0.2 | Reduce Motion: pieces only fade in |

The frame: `Config.UI.Menu.Lively` (header scroll `HeaderPxPerSecond` 23 along 45 degrees,
`HeaderTilePx` 260, `HeaderTransparency` 0.6; dots `DotsTransparency` 0.92; flair rock 5.7
degrees over 2.9 s, hop 9 px every 5 s; icon rock 3.4 degrees, lit tab 6.9 degrees, 2.9 s).

A screen's own loop numbers live beside its layout (the Shop card's `Config.UI.GrandOpeningCard.Loops`:
glow pulse 2.6 s, rays 8.6 degrees/s, breathe 1.5% over 2.3 s, block shine every 4 s, button shine
every 3 s staggered 0.35 s (Robux only), ball float 6 x 9 px, fireworks at 15 fps every 1.5 s,
ribbons dimming to 0.6 transparency over 2.4 s).

### The open schedule

`Config.UI.<Name>.Open` (`Config.UI.Shop.Open` is the model):

```lua
Config.UI.Shop.Open = {
	OpenSeconds = 0.91, -- the whole open; a longer or shorter open scales every At, not the lengths
	Steps = {
		{ Ids = { "Panel" }, Kind = "Unroll", At = 0 },
		{ Ids = { "Header" }, Kind = "Fade", At = 0.12, Length = 0.15 },
		{ Ids = { "Basket", "Title", "Money", "Close" }, Kind = "Pop", At = 0.18 },
		{ Ids = { "Tab1", "Tab2", "Tab3", "Tab4" }, Kind = "Pop", At = 0.3, Stagger = 1.25,
			Badge = true, BadgeAfter = 0.08 },
		{ Ids = { "Card" }, Kind = "Grow", At = 0.36 },
		{ Ids = { "Block" }, Kind = "Slam", At = 0.41, Length = 0.16, Burst = "Gold" },
		-- ... the cards (Burst = "Cyan" / "Pink"), the buttons, the timer ...
		{ Ids = { "Flair" }, Kind = "Drop", At = 0.82, Length = 0.25 },
	},
	Poppers = true, Streamers = true, Twinkles = true, -- optional flair switches
}
```

`Kind` is `Unroll`, `Fade`, `Pop`, `Grow`, `Slam`, `Drop`. `Stagger` multiplies
`Motion.Stagger` between the ids of one step. `Burst` names a firework colour from
`Config.UI.Effects.Firework` (Gold, Pink, Cyan, Purple, Orange). The frame's ids are `Panel`,
`Header`, `Basket`, `Title`, `Money`, `Close`, `Tab<n>`, `Tab<n>Badge`, `Flair`; the page adds
its own.

## 2. Easing

`StageMath.ease(style, direction, p)` matches TweenService (Quad, Quart, Quint, Sine, Back,
Bounce...). The animatic's JS copies the same curves, so what the designer approved is what
plays. The reveal curves are `StageMath.popScale`, `unrollShare`, `slamScale`, `dropShare`,
`growShare`, `closeShare`; `StageMath.schedule(open, M, openSeconds)` turns a schedule into
timed entries, `pieceState(entry, t, M, reduced)` gives a piece's scale, alpha and offset at a
time. All of it is tested in Lune.

## 3. The smooth-motion technique

Roblox draws GUI positions and sizes in **whole pixels**, so a slow move by Position, Size or
UIScale steps (still, still, jump). Measured at gate 1 (jitter in physical px, 0 = perfect,
Retina / phone at low graphics): Tile by Scale 0.93 / 0.95; float by Offset 0.66; float by Scale
0.45; breathe by UIScale 0.21. **Move the picture inside a still label instead**: fractional
`ImageRectOffset` / `ImageRectSize` are drawn with sub-texel filtering. Header scroll by window
0.24 / 0.15; float by whole px + fraction in the rect 0.06 / 0.03; breathe by ImageRectSize
0.01. **Rotation is smooth.** Fast moves (pops, slams, drops, confetti falling) may use
Position or UIScale: they move several pixels a frame.

| Motion | Technique | Helper |
|---|---|---|
| Scroll a pattern | a still label showing a window into a seamless tile repeated across a bigger picture; the window's offset moves and wraps at one period | `UIAnim.scrollTile` |
| Float or drift slowly | whole-pixel Position plus the leftover fraction in `ImageRectOffset` (the picture has a clear border) | `UIAnim.glide`, `UIAnim.float` |
| Breathe (zoom) | `ImageRectSize`/`ImageRectOffset` zooming the window inside a clear border | `UIAnim.breathe`, `StageMath.breatheRect` |
| Rock, turn, spin | `Rotation` | `UIAnim.turn(obj, degPerSec, rockDegrees?, seconds?)` |
| Pulse a glow, dim and glow | `ImageTransparency` | `UIAnim.glowPulse(label, low, high, seconds)` |
| A light across a shape | a white silhouette mask over the piece with a moving `UIGradient` band | `UIAnim.maskedSweep` |
| Frame animation | one ImageLabel stepping `ImageRectOffset` over an 8 x 8 sheet | `UIAnim.flipbook` |

**Every window must stay inside its picture**: a rect past the texture's edge is clamped and
stops moving. Give pictures a clear border and test the window maths in Lune.

### Scroll (the header)

```lua
-- label.Image: the tile repeated across a sheetPx square; shown tilePx screen px per period.
UIAnim.scrollTile(label, period, tilePx, pxPerSecond, Vector2.new(-1, -1), sheetPx)
-- inside: offset = (t * speed * texelsPerPx) % period on each axis (StageMath.scrollOffset);
-- the window is at most sheetPx - period texels across.
```

### Float

```lua
-- whole pixels by Position, the fraction by moving the picture back inside the label
local wx, fx = StageMath.floatSplit(dx) -- whole = floor(dx + 0.5), fraction = dx - whole
label.Position = rest + UDim2.fromOffset(wx, wy)
label.ImageRectOffset = Vector2.new(2 - fx * texel, 2 - fy * texel) -- window 2 texels in
```

### Breathe, keeping the picture's shape

`StageMath.breatheRect(imageSize, border, scale)` returns the window size and offset on one
axis. **Share the border by length on each axis**, or a wide picture stretches (a 1024 x 344
picture with the same 48 px border on both axes would draw 10% too tall). The Shop card's
breathe (`GrandOpeningCard.luau`):

```lua
local function breathe(pictures: { ImageLabel }, px: { number }): UIAnim.Handle
	local w, h = px[1], px[2]
	local per = px[3] / math.max(w, h) -- the border shared by length
	local phase = Random.new():NextNumber(0, math.pi * 2)
	return UIAnim.loop(pictures[1], function(clock)
		local scale = if UIAnim.reduced() then 1
			else 1 + LOOP.BreatheScale * math.sin(2 * math.pi * clock / LOOP.BreatheSeconds + phase)
		local sw, ow = StageMath.breatheRect(w, w * per, scale)
		local sh, oh = StageMath.breatheRect(h, h * per, scale)
		for _, picture in pictures do -- the picture and its shine mask together
			picture.ImageRectSize = Vector2.new(sw, sh)
			picture.ImageRectOffset = Vector2.new(ow, oh)
		end
	end)
end
```

The window at rest shows the picture less a share of its border, so size the label to that
window (or accept the small zoom) when the picture must line up with something.

### Rock and pulse

```lua
UIAnim.turn(icon, 0, 3.4, 2.9)                      -- rock 3.4 degrees either way over 2.9 s
UIAnim.glowPulse(ribbons, 0, 0.6, 2.4)              -- full, dim to 0.6, back, over 2.4 s
```

A long picture rocked by a few degrees swings its ends far (5.7 degrees on a 225 px picture
moves the tips 11 px); keep rocks for small, round things.

## 4. Stage: the reveal player

```lua
local stage = Stage.new(Config.UI.<Name>.Open) -- MenuFrame makes it for a lively menu
stage:add("Block", self.block, function()       -- id from the schedule; onLand starts the loops
	keep(all({ UIAnim.glowPulse(self.glow, 0.05, 0.45, 2.6), UIAnim.turn(self.rays, 8.6) }))
end)
stage:play()                                     -- MenuFrame calls this on open
stage:replay(stage:idsUnder(page))               -- a tab switch: the page's pieces again
stage:close(done)                                -- fades all, folds the panel
stage:finish()                                   -- jump to the end
```

- Pop, Slam and Grow drive the piece's **one** UIScale (UIAnim's `AnimScale`): only the first
  UIScale on an object takes effect.
- Fade is the **code fader**: it caches each descendant's transparencies (Background, Image,
  Text, TextStroke, UIStroke, ScrollBar) and drives them from one alpha. Never a CanvasGroup.
- A piece's rest (place, size, transparencies) is read when a run starts, so lay the screen
  out before `play`. Every call cancels the run before it, so spam ends clean.
- `keep(handle)` (the frame's `idle`) holds loops until the menu closes; stop them there.

## 5. The idle library (UIAnim)

| Helper | Use |
|---|---|
| `glowPulse(label, low, high, seconds)` | glows, bokeh, a picture dimming and glowing |
| `turn(obj, degPerSec, rock?, seconds?)` | rays turning, stars and icons rocking |
| `breathe(...)` / the card's shape-keeping breathe | the hero picture |
| `maskedSweep(mask, every, seconds, strength)` | a shine across a shape (block, cue, badge) |
| `float(label, imagePx, px, seconds)`, `glide` | 8-balls at depths (far ones smaller, slower) |
| `scrollTile(...)` | header pattern, glyph code |
| `flipbook(label, sheet, opts)`, `burstLoop(...)` | fireworks, sparkles (30 fps sheets) |
| `confettiDrift(area, pictures, count, sizePx, imagePx, fallPxPerSecond)` | gold confetti tumbling down |
| `sparkle`, `scanLine`, `glitch`, `rainbow`, `stripes`, `shake`, `sway` | special touches |
| `popIn`, `slam`, `expandIn`, `bounce`, `glowBurst` | one-off entrances and presses outside Stage |

Every loop starts at a random phase so pieces never pulse in sync, and runs only while its
screen is open (stopped through `keep`).

## 6. Reduce Motion and Lower effects

- **Reduce Motion** (`GuiService.ReducedMotionEnabled`, read by `UIAnim.reduced()`): pieces
  only fade in (`ReducedFadeSeconds`); no unroll, bulge, float, scroll, rock or sweep; glows may
  still pulse softly. Test with `GuiQA:Invoke("reduced", true)`.
- **Lower effects** (`Quality.isLow()`, the game's setting): no reveal bursts, half the
  counts (bokeh, balls, confetti, twinkles), sweeps half as often (`Quality.rate()`). Test with
  `GuiQA:Invoke("quality", true)`.
