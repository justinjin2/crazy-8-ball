--!strict
-- StageMath: the lively screens' maths (easing, reveals, the open schedule, flipbooks, the
-- smooth-motion windows, the timer) and the Grand Opening odds the card shows.

local H = require("./harness")

local function load()
	return H.require("StageMath"), H.require("Config")
end

return {
	["easing matches TweenService at its ends and known points"] = function()
		local S = load()
		for _, style in
			{
				"Linear",
				"Sine",
				"Quad",
				"Cubic",
				"Quart",
				"Quint",
				"Exponential",
				"Circular",
				"Back",
				"Elastic",
				"Bounce",
			}
		do
			for _, dir in { "In", "Out", "InOut" } do
				H.near(S.ease(style, dir, 0), 0, 1e-9, style .. dir .. " starts at 0")
				H.near(S.ease(style, dir, 1), 1, 1e-9, style .. dir .. " ends at 1")
			end
		end
		H.near(S.ease("Quad", "Out", 0.5), 0.75, 1e-9, "Quad Out")
		H.near(S.ease("Sine", "InOut", 0.5), 0.5, 1e-9, "Sine InOut middle")
		H.near(S.ease("Quart", "In", 0.5), 0.0625, 1e-9, "Quart In")
		-- Back Out overshoots by about 10% of the change (TweenService's s = 1.70158).
		local peak = 0
		for i = 0, 1000 do
			peak = math.max(peak, S.ease("Back", "Out", i / 1000))
		end
		H.near(peak, 1.1, 0.001, "Back Out peak")
		H.near(S.ease("Bounce", "Out", 1 / 2.75), 1, 1e-9, "Bounce Out first landing")
		H.near(S.ease("Linear", "In", 2), 1, 1e-9, "p is clamped")
	end,

	["a pop starts small, peaks past full size on time, settles at exactly 1"] = function()
		local S, Config = load()
		local M = Config.UI.Motion
		H.near(S.popScale(0, M), M.PopFrom, 1e-9, "start")
		H.near(S.popScale(M.PopPeakAt, M), M.PopPeak, 1e-9, "peak")
		H.near(S.popScale(1, M), 1, 1e-9, "settled")
		H.near(S.popScale(5, M), 1, 1e-9, "after")
		local most = 0
		for i = 0, 1000 do
			most = math.max(most, S.popScale(i / 1000, M))
		end
		H.near(most, M.PopPeak, 1e-6, "never past the peak")
	end,

	["unroll, slam, drop, grow and close start and end where they should"] = function()
		local S, Config = load()
		local M = Config.UI.Motion
		H.near(S.unrollShare(0, M), 0, 1e-9, "unroll from a bar")
		H.near(S.unrollShare(M.UnrollPeakAt, M), M.UnrollOvershoot, 1e-9, "unroll overshoot")
		H.near(S.unrollShare(1, M), 1, 1e-9, "unroll settles")
		H.near(S.slamScale(0, M), M.SlamFrom, 1e-9, "slam from big")
		H.near(S.slamScale(M.SlamLandAt, M), 1, 1e-9, "slam lands")
		H.near(S.slamScale(1, M), 1, 1e-9, "slam settles")
		H.expect(S.slamScale(9, M) == 1, "slam stays settled long after (no runaway wobble)")
		H.near(S.dropShare(0), 1, 1e-9, "drop from the top")
		H.near(S.dropShare(1), 0, 1e-9, "drop lands")
		H.near(S.growShare(1), 1, 1e-9, "grow")
		H.near(S.closeShare(0), 1, 1e-9, "close starts open")
		H.near(S.closeShare(1), 0, 1e-9, "close folds to a line")
	end,

	["the Shop's open schedule follows Config, staggers groups, scales with the open length"] = function()
		local S, Config = load()
		local M, open = Config.UI.Motion, Config.UI.Shop.Open
		local list, finish = S.schedule(open, M)
		local byId = {}
		for _, e in list do
			H.expect(byId[e.id] == nil, "one entry per piece: " .. e.id)
			byId[e.id] = e
		end
		H.near(byId.Panel.at, 0, 1e-9, "the panel unrolls first")
		H.near(byId.Panel.length, M.UnrollSeconds, 1e-9, "unroll length from Motion")
		H.near(byId.Money.at - byId.Title.at, M.Stagger, 1e-9, "a group staggers")
		H.near(
			byId.Tab2.at - byId.Tab1.at,
			M.Stagger * 1.25,
			1e-9,
			"the tabs stagger a little wider"
		)
		H.near(byId.Tab1Badge.at - byId.Tab1.at, 0.08, 1e-9, "a NEW badge right after its tab")
		H.expect(byId.Block.burst == "Gold", "the block arrives with a burst")
		H.expect(byId.Flair.at > byId.Money10.at, "the flair lands last")
		for i = 2, #list do
			H.expect(list[i].at >= list[i - 1].at, "sorted by start")
		end
		H.near(finish, byId.Flair.at + byId.Flair.length, 1e-9, "ends when the flair lands")
		-- A 2 s open moves every start out by 2 / OpenSeconds; lengths stay.
		local slow, slowFinish = S.schedule(open, M, 2)
		local slowById = {}
		for _, e in slow do
			slowById[e.id] = e
		end
		H.near(slowById.Block.at, byId.Block.at * 2 / open.OpenSeconds, 1e-9, "starts scale")
		H.near(slowById.Block.length, byId.Block.length, 1e-9, "lengths do not")
		H.expect(slowFinish > finish, "a longer open ends later")
		H.expect(
			finish >= 0.8 and finish <= 2,
			"the open lasts about 1 to 2 s (designer; 0.91 s since 2026-10-07)"
		)
	end,

	["the Cues menu's open names every piece it stages and lands its flair last"] = function()
		local S, Config = load()
		local M, I = Config.UI.Motion, Config.UI.Inventory
		local list, finish = S.schedule(I.Open, M)
		local byId = {}
		for _, e in list do
			H.expect(byId[e.id] == nil, "one entry per piece: " .. e.id)
			byId[e.id] = e
		end
		-- A piece staged but missing from the schedule stays faded after a close.
		local wanted = { "Panel", "Header", "Basket", "Title", "Money", "Close", "Flair" }
		for _, id in { "Switch", "Sort", "Sell" } do
			table.insert(wanted, id)
			table.insert(wanted, id .. "Badge") -- the dots, the hanging pills
		end
		for i = 1, I.StagedCards do
			table.insert(wanted, "Card" .. i)
		end
		table.insert(wanted, "IndexDetail")
		for _, id in wanted do
			H.expect(byId[id] ~= nil, "the open names " .. id)
		end
		H.expect(byId.IndexHead1 ~= nil and byId.IndexCell1 ~= nil, "the Index's first pieces")
		H.expect(byId["Card" .. (I.StagedCards + 1)] == nil, "only StagedCards cards are staged")
		H.near(byId.Panel.at, 0, 1e-9, "the panel unrolls first")
		H.expect(byId.Card1.at < byId.Card2.at, "the cards pop in reading order")
		for id, e in byId do
			if id ~= "Flair" then
				H.expect(e.at <= byId.Flair.at, "the flair drops on last, after " .. id)
			end
		end
		H.expect(finish >= 0.8 and finish <= 2, "the open lasts about 1 to 2 s")
	end,

	["a piece's state: hidden before, landed after, fades only with Reduce Motion"] = function()
		local S, Config = load()
		local M = Config.UI.Motion
		local e = { id = "X", kind = "Pop", at = 0.5, length = M.PopSeconds }
		local before = S.pieceState(e, 0.4, M)
		H.expect(before.alpha == 0 and not before.landed, "hidden before its start")
		local after = S.pieceState(e, 2, M)
		H.expect(after.alpha == 1 and after.scale == 1 and after.landed, "landed after")
		local mid = S.pieceState(e, 0.5 + M.PopSeconds * M.PopPeakAt, M)
		H.near(mid.scale, M.PopPeak, 1e-9, "at its peak mid-pop")
		local reduced = S.pieceState(e, 0.25 + M.ReducedFadeSeconds / 2, M, true)
		H.expect(reduced.scale == 1, "Reduce Motion: no growing")
		H.near(reduced.alpha, 0.5, 1e-9, "Reduce Motion: a fade")
		local unroll = S.pieceState({ id = "P", kind = "Unroll", at = 0, length = 0.2 }, 0.01, M)
		H.expect(unroll.alpha == 1, "the panel's chrome is solid while it unrolls")
	end,

	["flipbook frames step, loop or end, and sit on the sheet's grid"] = function()
		local S, Config = load()
		local fw = Config.UI.Effects.Firework
		H.expect(S.flipFrame(-0.1, fw.Fps, fw.Frames, false) == nil, "not started")
		H.expect(S.flipFrame(0, fw.Fps, fw.Frames, false) == 0, "first frame")
		H.expect(
			S.flipFrame((fw.Frames - 0.5) / fw.Fps, fw.Fps, fw.Frames, false) == fw.Frames - 1,
			"last frame"
		)
		H.expect(
			S.flipFrame(fw.Frames / fw.Fps + 0.01, fw.Fps, fw.Frames, false) == nil,
			"a burst ends"
		)
		H.expect(
			S.flipFrame(fw.Frames / fw.Fps + 0.01, fw.Fps, fw.Frames, true) == 0,
			"a loop wraps"
		)
		local x, y = S.flipOffset(9, fw.Columns, fw.FramePx, fw.FramePx)
		H.expect(x == fw.FramePx and y == fw.FramePx, "frame 9 is row 1, column 1")
		local lx, ly = S.flipOffset(63, 8, 128, 128)
		H.expect(lx + 128 <= 1024 and ly + 128 <= 1024, "the last frame stays on a 1024 sheet")
	end,

	["the smooth-motion windows stay inside their pictures"] = function()
		local S, Config = load()
		for t = 0, 30, 0.37 do
			local o = S.scrollOffset(t, 32, 512 / 380, 512)
			H.expect(o >= 0 and o < 512, "a scroll window stays within one period")
		end
		local whole, frac = S.floatSplit(3.7)
		H.expect(whole == 4, "whole pixels")
		H.near(frac, -0.3, 1e-9, "the fraction left over")
		local w2, f2 = S.floatSplit(-2.2)
		H.expect(w2 == -2, "negative floats round too")
		H.near(f2, -0.2, 1e-9, "negative fraction")
		for _, scale in { 0.97, 1, 1.03 } do
			local size, offset = S.breatheRect(256, 16, scale)
			H.expect(
				offset >= 0 and offset + size <= 256,
				"a breathe window inside the picture at " .. scale
			)
		end
		-- The card's breathing picture (the crowned block), its border shared by length as the
		-- card does: inside the picture and keeping its shape.
		local card = Config.UI.GrandOpeningCard
		local amount = card.Loops.BreatheScale
		for _, px in { card.Layout.CrownedBlockPx } do
			local per = px[3] / math.max(px[1], px[2])
			for _, scale in { 1 - amount, 1, 1 + amount } do
				local sw, ow = S.breatheRect(px[1], px[1] * per, scale)
				local sh, oh = S.breatheRect(px[2], px[2] * per, scale)
				H.expect(ow >= 0 and oh >= 0 and ow + sw <= px[1] and oh + sh <= px[2], "inside")
				H.near(sw / sh, px[1] / px[2], 1e-9, "the picture keeps its shape")
			end
		end
	end,

	["the timer reads 20d 23h, then 23h 59m, then 59:59"] = function()
		local S = load()
		local words = H.require("Strings").Menus.Shop.Featured
		H.expect(S.timeLeft(20 * 86400 + 23 * 3600 + 59, words) == "20d 23h", "days")
		H.expect(S.timeLeft(86399, words) == "23h 59m", "the last day")
		H.expect(S.timeLeft(3599, words) == "59:59", "the last hour")
		H.expect(S.timeLeft(-5, words) == "0:00", "never below zero")
		H.expect(
			string.format(words.EndsIn, S.timeLeft(86400, words)) == "Ends in 1d 0h",
			"the sentence"
		)
	end,

	["the Grand Opening odds the card shows add up to exactly 100%"] = function()
		local BlockOdds = H.require("Progression.BlockOdds")
		local total = 0
		for _, row in BlockOdds.odds("GrandOpening") do
			total += row.percent
		end
		for _, row in BlockOdds.uniqueRows("GrandOpening") do
			total += row.percent
		end
		H.near(total, 100, 1e-9, "every outcome")
	end,
}
