--!strict
-- ScreenLayout (Tutorial/ScreenLayout, designer 2026-10-10): the tutorial layer's pieces on
-- every screen shape. On a phone with a notch the lit holes sat beside their buttons and the
-- line ran under Skip; these shapes keep that from coming back.
local H = require("./harness")

local function load()
	return H.require("Tutorial.ScreenLayout"), H.require("Config").Tutorial.Overlay
end

type Rect = { x: number, y: number, w: number, h: number }
type Screen = {
	name: string,
	origin: { number }, -- the layer's own AbsolutePosition (ScreenInsets None)
	full: { number }, -- w, h
	play: Rect, -- in the layer's pixels
	topbar: Rect,
}

local function r(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- Screens in the layer's pixels. The iPhone row is Studio's phone emulator as measured
-- (2026-10-10: the whole screen 874 x 401 at (-62, -78), the play area 750 x 303).
local SCREENS: { Screen } = {
	{
		name = "iPhone, notch both sides",
		origin = { -62, -78 },
		full = { 874, 401 },
		play = r(62, 78, 750, 303),
		topbar = r(270, 20, 542, 58),
	},
	{
		name = "Android, cutout on the left",
		origin = { -56, -58 },
		full = { 800, 369 },
		play = r(56, 58, 744, 311),
		topbar = r(206, 0, 594, 58),
	},
	{
		name = "iPhone SE",
		origin = { 0, -58 },
		full = { 667, 375 },
		play = r(0, 58, 667, 317),
		topbar = r(146, 0, 521, 58),
	},
	{
		name = "iPad",
		origin = { 0, -58 },
		full = { 1024, 768 },
		play = r(0, 58, 1024, 710),
		topbar = r(150, 0, 874, 58),
	},
	{
		name = "laptop 1366 x 768",
		origin = { 0, -58 },
		full = { 1366, 695 },
		play = r(0, 58, 1366, 637),
		topbar = r(150, 0, 1216, 58),
	},
	{
		name = "computer 1920 x 1080",
		origin = { 0, -58 },
		full = { 1920, 1007 },
		play = r(0, 58, 1920, 949),
		topbar = r(150, 0, 1770, 58),
	},
}

local function areas(screen: Screen): any
	return {
		full = r(0, 0, screen.full[1], screen.full[2]),
		play = screen.play,
		topbar = screen.topbar,
	}
end

local function phone(screen: Screen, O: any): boolean
	return math.min(screen.full[1], screen.full[2]) < O.PhoneBelowPx
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 0.5
end

return {
	["a hole lands on its button on every screen (the layer's own place, not Roblox's inset)"] = function()
		local L = load()
		for _, screen in SCREENS do
			-- A button at GUI (216, -53), 225 x 58 (the rank HUD in the iPhone emulator).
			local hole = L.hole(216, -53, 225, 58, screen.origin[1], screen.origin[2], 10)
			local midX = hole.x + hole.w / 2 + screen.origin[1]
			local midY = hole.y + hole.h / 2 + screen.origin[2]
			H.expect(near(midX, 216 + 112.5) and near(midY, -53 + 29), screen.name .. ": middle")
			H.expect(hole.w == 245 and hole.h == 78, screen.name .. ": padded 10 each side")
		end
	end,

	["Skip: a phone's right under Roblox's menu, a computer's top right, inside the play area"] = function()
		local L, O = load()
		for _, screen in SCREENS do
			local a = areas(screen)
			local small = phone(screen, O)
			local spots = L.skipSpots(a, small)
			local first = spots[1]
			H.expect(L.inside(first, a.play), screen.name .. ": inside the play area")
			H.expect(
				near(first.y, a.play.y + O.SkipTopGapPx),
				screen.name .. ": just under the bar"
			)
			if small then
				H.expect(near(first.x, a.play.x + O.SkipEdgePx), screen.name .. ": top left")
				H.expect(first.h == O.SkipPhoneHeightPx, screen.name .. ": small")
			else
				H.expect(
					near(first.x + first.w, a.play.x + a.play.w - O.SkipEdgePx),
					screen.name .. ": top right"
				)
			end
			for i, spot in spots do
				H.expect(L.inside(spot, a.full), ("%s: spot %d on screen"):format(screen.name, i))
			end
			-- The fallbacks run along the top bar row from right of Roblox's buttons, inside it.
			local row = spots[if small then 2 else 3]
			H.expect(near(row.x, a.topbar.x + O.SkipEdgePx), screen.name .. ": the row starts left")
			for i = if small then 2 else 3, #spots do
				H.expect(
					L.inside(spots[i], a.topbar),
					("%s: row spot %d in the row"):format(screen.name, i)
				)
			end
		end
	end,

	["the line: centred on the play area, under the bar, clear of Skip"] = function()
		local L, O = load()
		for _, screen in SCREENS do
			local a = areas(screen)
			local small = phone(screen, O)
			for i, skip in L.skipSpots(a, small) do
				local line = L.line(a, skip)
				local what = ("%s, Skip at spot %d"):format(screen.name, i)
				H.expect(near(line.x + line.w / 2, a.play.x + a.play.w / 2), what .. ": centred")
				H.expect(
					line.x >= a.play.x and line.x + line.w <= a.play.x + a.play.w,
					what .. ": inside"
				)
				H.expect(line.w <= a.play.w * O.LineWidthShare + 1e-6, what .. ": not too wide")
				H.expect(line.y >= a.play.y, what .. ": under Roblox's top bar")
				local band = r(line.x, line.y, line.w, O.LineBandPx)
				H.expect(not L.overlaps(band, skip), what .. ": never under Skip")
				H.expect(line.w >= O.LineMinWidthPx, what .. ": still wide enough")
			end
			-- With Skip where it goes first, the line stays right at the top.
			local line = L.line(a, L.skipSpots(a, small)[1])
			H.expect(near(line.y, a.play.y + O.LineTopGapPx), screen.name .. ": at the top")
		end
	end,

	["a line that would cover a button at the top goes under it, clear of the hand"] = function()
		local L, O = load()
		for _, screen in SCREENS do
			local a = areas(screen)
			local line = L.line(a, L.skipSpots(a, phone(screen, O))[1])
			line.h = 30
			-- The rank HUD's hole: in Roblox's top bar row, reaching a little into the play area.
			local hole = r(a.play.x + a.play.w / 2 - 125, a.topbar.y - 6, 250, a.topbar.h + 16)
			H.expect(L.overlaps(line, hole), screen.name .. ": the line covered it")
			local y = L.near(a, hole, line.h)
			H.expect(near(y, hole.y + hole.h + O.LineNearGapPx), screen.name .. ": moved under it")
		end
	end,

	["a banner at the top pushes the line under it"] = function()
		local L = load()
		local a = areas(SCREENS[1])
		local line = L.line(a, nil, 150)
		H.expect(line.y == 150, "under the banner")
	end,

	["a Near line sits over the hole, or under it when there is no room, inside the play area"] = function()
		local L, O = load()
		for _, screen in SCREENS do
			local a = areas(screen)
			local p = a.play
			local low = r(p.x + 100, p.y + p.h - 80, 200, 60)
			local y = L.near(a, low, 30)
			H.expect(near(y, low.y - O.LineNearGapPx - 30), screen.name .. ": over a low hole")
			local high = r(p.x + 100, p.y + 4, 200, 40)
			local y2 = L.near(a, high, 30)
			H.expect(y2 >= high.y + high.h, screen.name .. ": under a hole at the top")
			H.expect(y2 + 30 <= p.y + p.h, screen.name .. ": inside the play area")
		end
	end,

	["a line tries its place and lower, by the hole first when near, never on the hole"] = function()
		local L, O = load()
		for _, screen in SCREENS do
			local a = areas(screen)
			local p = a.play
			local line = L.line(a, L.skipSpots(a, phone(screen, O))[1])
			line.h = 28
			local step = line.h + O.LineStepGapPx
			-- No hole: its place, then LineSteps steps lower.
			local tops = L.lineTops(a, line, nil, false)
			H.expect(#tops == O.LineSteps + 1, screen.name .. ": its place and the steps")
			H.expect(tops[1] == line.y and near(tops[2], line.y + step), screen.name .. ": steps")
			-- A popup's button in the middle, "Near": over it, under it, then its place.
			local hole = r(p.x + p.w / 2 - 100, p.y + p.h / 2 - 25, 200, 50)
			local byHole = L.lineTops(a, line, hole, true)
			H.expect(byHole[1] + line.h <= hole.y, screen.name .. ": over it first")
			H.expect(byHole[3] == line.y, screen.name .. ": then its place")
			-- Not near: its place first, the hole's spots last.
			local far = L.lineTops(a, line, hole, false)
			H.expect(far[1] == line.y, screen.name .. ": its place first")
			for _, list in { tops, byHole, far } do
				for _, y in list do
					local box = r(line.x, y, line.w, line.h)
					H.expect(
						not L.overlaps(box, hole) or list == tops,
						screen.name .. ": off the hole"
					)
					H.expect(y >= p.y and y + line.h <= p.y + p.h, screen.name .. ": inside")
				end
			end
			-- A hole filling the play area's height: nowhere clear, so the old fallback.
			local tall = r(p.x + 10, p.y, p.w - 20, p.h)
			H.expect(#L.lineTops(a, line, tall, true) == 1, screen.name .. ": one fallback")
		end
	end,

	["the big text and the Next button stay centred in the play area"] = function()
		local L, O = load()
		for _, screen in SCREENS do
			local a = areas(screen)
			local small = phone(screen, O)
			local big = L.big(a, small)
			H.expect(L.inside(big, a.play), screen.name .. ": big text inside")
			H.expect(
				near(big.x + big.w / 2, a.play.x + a.play.w / 2),
				screen.name .. ": big centred"
			)
			local line = L.line(a, L.skipSpots(a, small)[1])
			line.h = 30
			local spots = L.nextSpots(a, line, small, 200)
			local nextBox = spots[1]
			H.expect(
				near(nextBox.x + nextBox.w / 2, line.x + line.w / 2),
				screen.name .. ": Next centred"
			)
			H.expect(nextBox.y >= line.y + line.h, screen.name .. ": Next under the line")
			H.expect(
				spots[2].x >= line.x + (line.w + 200) / 2,
				screen.name .. ": then beside the words"
			)
			-- A line at the play area's foot: only beside its words, still on screen.
			local low = r(line.x, a.play.y + a.play.h - 30, line.w, 30)
			local only = L.nextSpots(a, low, small, 200)
			H.expect(#only == 1 and L.inside(only[1], a.play), screen.name .. ": Next inside")
			local x, y = L.at(a, 0.5, 0.62)
			H.expect(
				near(x, a.play.x + a.play.w / 2) and y > a.play.y and y < a.play.y + a.play.h,
				screen.name .. ": a gesture's middle"
			)
		end
	end,
}
