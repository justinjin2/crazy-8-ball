--!strict
-- ScreenLayout: where the tutorial layer's pieces sit on any screen (designer, 2026-10-10, after
-- the tutorial on an Android phone: every lit hole sat beside its button, the line ran under
-- Skip). Pure rect math, no Instances; tests/tutorial_layout_test.luau runs it across screen
-- shapes (iPhone notch both sides, an Android cutout on one side, iPhone SE, iPad, laptops).
--
-- Every rect is in the tutorial layer's own pixels: TutorialGui covers the whole screen
-- (ScreenInsets None), so its (0, 0) is the screen's corner, past any notch. The client
-- measures three areas in those pixels (TutorialOverlay.areas):
-- - full: the whole screen;
-- - play: the free area, inside the notch and under Roblox's top bar;
-- - topbar: Roblox's top bar row right of its own buttons.
-- A GUI target's AbsolutePosition and every ScreenGui's share one space, whatever their
-- insets; the layer's own AbsolutePosition is subtracted (hole), never Roblox's inset added.

local Config = require(script.Parent.Parent.Config)

local O = Config.Tutorial.Overlay

local ScreenLayout = {}

export type Rect = { x: number, y: number, w: number, h: number }
export type Areas = { full: Rect, play: Rect, topbar: Rect }

function ScreenLayout.rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

function ScreenLayout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

--- Whether `inner` lies wholly inside `outer`.
function ScreenLayout.inside(inner: Rect, outer: Rect): boolean
	return inner.x >= outer.x
		and inner.y >= outer.y
		and inner.x + inner.w <= outer.x + outer.w
		and inner.y + inner.h <= outer.y + outer.h
end

--- The lit hole round a GUI target: its AbsolutePosition (ax, ay) and AbsoluteSize (w, h), the
--- layer's own AbsolutePosition (ox, oy), grown by `pad` on each side.
function ScreenLayout.hole(
	ax: number,
	ay: number,
	w: number,
	h: number,
	ox: number,
	oy: number,
	pad: number
): Rect
	return { x = ax - ox - pad, y = ay - oy - pad, w = w + 2 * pad, h = h + 2 * pad }
end

--- The Skip tutorial button's size on this screen: `width` (its words' measured need, from
--- the client) or SkipWidthRatio x its height.
function ScreenLayout.skipSize(phone: boolean, width: number?): (number, number)
	local h = if phone then O.SkipPhoneHeightPx else O.SkipHeightPx
	return width or h * O.SkipWidthRatio, h
end

--- Skip's spots, best first. A phone: right under Roblox's menu (the play area's top left),
--- then along the top bar row from just right of Roblox's buttons. A computer or tablet: top
--- right under the bar, top left under the bar, then along the top bar row (designer,
--- 2026-10-10). The client takes the first one none of our panels covers (a screen's title
--- pill in the row is stepped past, SkipRowStepPx at a time).
function ScreenLayout.skipSpots(areas: Areas, phone: boolean, width: number?): { Rect }
	local w, h = ScreenLayout.skipSize(phone, width)
	local play, bar = areas.play, areas.topbar
	local edge = O.SkipEdgePx
	local underLeft = { x = play.x + edge, y = play.y + O.SkipTopGapPx, w = w, h = h }
	local underRight = { x = play.x + play.w - edge - w, y = play.y + O.SkipTopGapPx, w = w, h = h }
	local spots = if phone then { underLeft } else { underRight, underLeft }
	local y = bar.y + math.max(0, (bar.h - h) / 2)
	local x = bar.x + edge
	repeat
		table.insert(spots, { x = x, y = y, w = w, h = h })
		x += O.SkipRowStepPx
	until x + w > bar.x + bar.w - edge
	return spots
end

--- The instruction line's box (its height is the client's: the words' measured lines): centred
--- on the play area, `top` (default: just under Roblox's top bar), at most LineWidthShare of the
--- play area and LineMaxWidthPx wide, narrowed to clear `skip` beside it, or moved under
--- `skip` when that would leave less than LineMinWidthPx.
function ScreenLayout.line(areas: Areas, skip: Rect?, top: number?): Rect
	local play = areas.play
	local cx = play.x + play.w / 2
	local y = math.max(play.y + O.LineTopGapPx, top or -math.huge)
	local w = math.min(play.w * O.LineWidthShare, O.LineMaxWidthPx)
	if skip and y < skip.y + skip.h and skip.y < y + O.LineBandPx then
		-- Skip beside the line: the line keeps clear of it on both sides (it stays centred).
		local room = if skip.x + skip.w / 2 < cx
			then cx - (skip.x + skip.w) - O.LineSkipGapPx
			else skip.x - cx - O.LineSkipGapPx
		if 2 * room >= O.LineMinWidthPx then
			w = math.min(w, 2 * room)
		else
			y = skip.y + skip.h + O.LineSkipGapPx
		end
	end
	return { x = cx - w / 2, y = y, w = w, h = 0 }
end

--- The line's top when it sits by the lit hole ("Near"): over it, or under it when there is no
--- room over it in the play area; never past the play area's foot.
function ScreenLayout.near(areas: Areas, hole: Rect, lineH: number): number
	local play = areas.play
	local above = hole.y - O.LineNearGapPx - lineH
	local y = if above >= play.y + O.LineTopGapPx then above else hole.y + hole.h + O.LineNearGapPx
	return math.min(y, play.y + play.h - lineH)
end

--- The line's tops to try, best first (`box` its usual place, from line): by the lit hole
--- first when `near` (over it, then under it), then its usual place and up to LineSteps steps
--- under it, then by the hole when not `near`. Each inside the play area and off the hole. The
--- client takes the first whose words would not sit on a screen's own words (a popup's title,
--- the rank HUD's goal line).
function ScreenLayout.lineTops(areas: Areas, box: Rect, hole: Rect?, near: boolean): { number }
	local play = areas.play
	local tops = {}
	local function add(y: number)
		local at = { x = box.x, y = y, w = box.w, h = box.h }
		local fits = y >= play.y and y + box.h <= play.y + play.h
		if fits and not (hole and ScreenLayout.overlaps(at, hole)) then
			table.insert(tops, y)
		end
	end
	local function byHole()
		if hole then
			add(hole.y - O.LineNearGapPx - box.h)
			add(hole.y + hole.h + O.LineNearGapPx)
		end
	end
	if near then
		byHole()
	end
	for i = 0, O.LineSteps do
		add(box.y + i * (box.h + O.LineStepGapPx))
	end
	if not near then
		byHole()
	end
	if #tops == 0 then
		table.insert(tops, if hole then ScreenLayout.near(areas, hole, box.h) else box.y)
	end
	return tops
end

--- The big text's box ("Place it!"): centred on the play area, BigYShare down it.
function ScreenLayout.big(areas: Areas, phone: boolean): Rect
	local play = areas.play
	local px = if phone then O.BigPhoneTextPx else O.BigTextPx
	local w = play.w * O.BigWidthShare
	local h = px * 1.3
	return { x = play.x + (play.w - w) / 2, y = play.y + play.h * O.BigYShare - h / 2, w = w, h = h }
end

--- A point on the play area by shares of its width and height (the gestures' places).
function ScreenLayout.at(areas: Areas, xShare: number, yShare: number): (number, number)
	local play = areas.play
	return play.x + play.w * xShare, play.y + play.h * yShare
end

--- The Next button's spots, best first: centred under the line's box, then beside its words
--- (`wordsW` wide, centred in the box), each inside the play area (the client takes the first
--- that covers no screen's words; with none inside, the one beside).
function ScreenLayout.nextSpots(areas: Areas, line: Rect, phone: boolean, wordsW: number): { Rect }
	local play = areas.play
	local h = if phone then O.NextPhoneHeightPx else O.NextHeightPx
	local w = h * O.NextWidthRatio
	local spots = {}
	local under = { x = line.x + (line.w - w) / 2, y = line.y + line.h + O.NextGapPx, w = w, h = h }
	if ScreenLayout.inside(under, play) then
		table.insert(spots, under)
	end
	local x =
		math.min(line.x + (line.w + wordsW) / 2 + O.NextGapPx, play.x + play.w - O.SkipEdgePx - w)
	local y = math.clamp(line.y + (line.h - h) / 2, play.y, play.y + play.h - h)
	table.insert(spots, { x = x, y = y, w = w, h = h })
	return spots
end

return ScreenLayout
