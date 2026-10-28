--!strict
-- CuePreviewMath: the Cue Preview's panel at the four sizes, the camera that frames the focus
-- in the window's centre, and the loop's timeline (hw-gui lane; R7).

local H = require("./harness")

-- The menu screen (under Roblox's top bar) and the viewport (the whole window) per size.
local SIZES = {
	{
		name = "phone 844x390",
		screen = { w = 750, h = 311 },
		viewport = { w = 844, h = 390 },
		offset = { x = 47, y = 58 },
	},
	{
		name = "phone 844x332",
		screen = { w = 844, h = 332 },
		viewport = { w = 844, h = 390 },
		offset = { x = 0, y = 58 },
	},
	{
		name = "iPad 1024x768",
		screen = { w = 1024, h = 700 },
		viewport = { w = 1024, h = 768 },
		offset = { x = 0, y = 68 },
	},
	{
		name = "PC 1920x1080",
		screen = { w = 1920, h = 1022 },
		viewport = { w = 1920, h = 1080 },
		offset = { x = 0, y = 58 },
	},
}

local function inside(r: any, outer: any): boolean
	return r.x >= outer.x
		and r.y >= outer.y
		and r.x + r.w <= outer.x + outer.w
		and r.y + r.h <= outer.y + outer.h
end

local function touches(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return {
	["the panel fits every size: a big window, 44 px buttons, nothing overlapping"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		for _, size in SIZES do
			local p = M.panel(size.screen)
			local where = size.name
			H.expect(
				inside(p.panel, { x = 0, y = 0, w = size.screen.w, h = size.screen.h }),
				"panel inside: " .. where
			)
			H.expect(p.window.w >= C.WindowMinShare * p.panel.w, "window wide enough: " .. where)
			H.expect(p.window.h >= 200, "window 200 px tall: " .. where .. " " .. p.window.h)
			local pieces = { p.header, p.window, p.sheet }
			for _, r in pieces do
				H.expect(inside(r, p.panel), "inside the panel: " .. where)
			end
			for _, r in { p.name, p.pill, p.note, p.equip, p.tabs[1], p.tabs[2], p.tabs[3] } do
				H.expect(inside(r, p.sheet), "inside the sheet: " .. where)
			end
			for _, r in { p.equip, p.tabs[1], p.tabs[2], p.tabs[3] } do
				H.expect(r.h >= C.MinHitPx and r.w >= C.MinHitPx, "a 44 px button: " .. where)
			end
			H.expect(
				p.close.h >= 28 and inside(p.close, p.header),
				"the X in the header: " .. where
			)
			local list = { p.name, p.pill, p.note, p.tabs[1], p.tabs[2], p.tabs[3], p.equip }
			for i = 1, #list do
				for j = i + 1, #list do
					H.expect(
						not touches(list[i], list[j]),
						("sheet pieces %d and %d overlap: %s"):format(i, j, where)
					)
				end
			end
			H.expect(not touches(p.window, p.sheet), "window and sheet apart: " .. where)
			H.expect(inside(p.hint, p.window), "the hint on the window: " .. where)
		end
	end,

	["the camera puts the focus at the window's centre, at every size and turn"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		local focus = { x = 2400, y = 2401, z = 0 }
		for _, size in SIZES do
			local p = M.panel(size.screen)
			local at = {
				x = p.window.x + p.window.w / 2 + size.offset.x,
				y = p.window.y + p.window.h / 2 + size.offset.y,
			}
			for _, yaw in { 0, 45, 137, 270 } do
				for _, pitch in { C.PitchMinDeg, 12, C.PitchMaxDeg } do
					for _, distance in { 4.5, 9 } do
						local eye, target =
							M.camera(focus, yaw, pitch, distance, C.FovDeg, size.viewport, at)
						local px, depth = M.project(focus, eye, target, C.FovDeg, size.viewport)
						H.expect(depth > 0, "in front")
						local err = math.sqrt((px.x - at.x) ^ 2 + (px.y - at.y) ^ 2)
						H.expect(
							err <= 4,
							("%s yaw %d pitch %d: %.2f px off"):format(size.name, yaw, pitch, err)
						)
					end
				end
			end
		end
	end,

	["the loop: TRAIL strokes, rolls, drops, holds the finisher; FINISHER rolls its last share"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		local trail = M.timeline("Trail", nil)
		local names = {}
		for _, phase in trail do
			table.insert(names, phase.name)
		end
		H.expect(
			table.concat(names, " ") == "back hit roll drop finisher gap",
			table.concat(names, " ")
		)
		local total = C.StrokeBackSeconds
			+ C.StrokeHitSeconds
			+ C.RollSeconds
			+ C.DropSeconds
			+ C.FinisherHoldSeconds
			+ C.GapSeconds
		H.near(trail[#trail].to, total, 1e-9, "the loop's length")
		H.near(
			M.timeline("Trail", 3)[5].to - M.timeline("Trail", 3)[5].from,
			3,
			1e-9,
			"the cue's finisher length"
		)
		local fin = M.timeline("Finisher", nil)
		H.expect(fin[1].name == "roll" and #fin == 4, "FINISHER: roll, drop, finisher, gap")
		H.near(fin[1].to, C.RollSeconds * C.FinisherRollShare, 1e-9)
		local name, progress = M.phaseAt(trail, C.StrokeBackSeconds / 2)
		H.expect(name == "back" and math.abs(progress - 0.5) < 1e-9, "half way back")
		name = M.phaseAt(trail, total + 0.01)
		H.expect(name == "back", "it wraps")
		H.near(
			M.rollShare("Finisher", 0),
			1 - C.FinisherRollShare,
			1e-9,
			"the finisher's roll starts late"
		)
		H.near(M.rollShare("Trail", 0.5), 0.5, 1e-9)
		H.expect(M.easeOut(0) == 0 and M.easeOut(1) == 1 and M.easeOut(0.5) > 0.5, "eases out")
	end,

	["turning: a flick decays, the auto-turn waits, the pitch stays in its limits"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		local yaw, spin = M.turn(10, 0, C.IdleResumeSeconds, 1)
		H.near(yaw, 10 + C.TurnDegPerSecond, 1e-9, "auto-turn")
		yaw, spin = M.turn(10, 0, 0, 1)
		H.expect(yaw == 10 and spin == 0, "no auto-turn right after a drag")
		local _, left = M.turn(0, 200, 0, 0.1)
		H.expect(left < 200 and left > 0, "a flick decays")
		H.expect(M.pitch(40, 30) == C.PitchMaxDeg and M.pitch(0, -90) == C.PitchMinDeg, "clamped")
		local y2 = M.turn(350, 0, 99, 1)
		H.expect(y2 >= 0 and y2 < 360, "yaw wraps")
	end,
}
