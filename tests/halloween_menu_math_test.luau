--!strict
-- The Halloween event menu's maths (HwMenuMath; mock A, designer 2026-10-29): a phone (844 x
-- 390) shows the cue row whole with the quests' header peeking, a computer and a tablet the
-- whole menu, no text under 12 px; today's board, the "New quests in" time and the tile's red
-- "!" count today's board only.

local H = require("./harness")

local function load()
	return H.require("HwMenuMath"), H.require("Config")
end

-- The content box MenuFrame gives a lively menu on a screen `w` x `h` (Roblox's top bar 58 px
-- tall), as MenuFrame.layout works it out; `fit` is the page's fitHeight.
local function content(
	Config: any,
	w: number,
	h: number,
	fit: (number, boolean) -> number
): (number, number, boolean)
	local F = Config.UI.Menu.Frame
	local LV = Config.UI.Menu.Lively
	local FR = setmetatable(table.clone(LV.Frame), { __index = F }) :: any
	local bar = 58
	local phone = h - bar < FR.ShortScreenPx
	local roomBottom = if phone then h else h - FR.BottomGapPx
	local roomHeight = roomBottom - bar
	local pw = math.floor(math.min(w - 2 * FR.MarginPx, FR.MaxSizePx[1]))
	pw = math.min(pw, math.floor(w * LV.MaxWidthShare))
	local ph = math.floor(math.min(roomHeight - 2 * FR.MarginPx, FR.MaxSizePx[2]))
	local k = math.clamp(ph / FR.DesignHeightPx, FR.MinScale, 1)
	local t = (k - FR.MinScale) / (1 - FR.MinScale)
	local function span(range: { number }): number
		return math.floor(range[1] + (range[2] - range[1]) * t + 0.5)
	end
	local pad, gap = span(FR.PaddingPx), span(FR.GapPx)
	local sheetTop = pad + span(FR.HeaderPx) + math.floor(gap / 2 + 0.5)
	local inset = Config.UI.Kit.SheetInsetPx
	local cp = span(FR.ContentPadPx)
	local cw = pw - 2 * (inset + cp)
	local bar6 = Config.UI.Shop.ScrollBarPx
	ph = math.min(ph, sheetTop + inset + 2 * cp + math.ceil(fit(cw - bar6, phone)))
	return cw - bar6, ph - sheetTop - inset - 2 * cp, phone
end

return {
	["a phone shows the cue row whole with the quests' header peeking"] = function()
		local Math, Config = load()
		local L = Config.UI.Halloween.Menu.Layout
		local w, h, phone = content(Config, 844, 390, Math.fitHeight)
		H.expect(phone, "844 x 390 is a phone")
		local plan = Math.plan(w, h, phone)
		H.expect(not plan.whole and plan.short, "a phone scrolls, with the phone's card units")
		local row = Math.rowUnits(true) * plan.k
		H.expect(
			row + L.SectionGapUnits * plan.k + L.PeekPx <= h + 1,
			"the cue row and the peek fit"
		)
		H.expect(Math.totalUnits(true) * plan.k > h, "the rest scrolls")
		-- The buttons a thumb presses stay big enough, the text readable.
		local C = Math.card(true)
		H.expect(
			C.RobuxUnits * plan.k >= 38,
			"the Robux button at least 38 px: " .. C.RobuxUnits * plan.k
		)
		H.expect(
			C.CandyUnits * plan.k >= 32,
			"the Candy button at least 32 px: " .. C.CandyUnits * plan.k
		)
		H.expect(Math.textPx(1, plan.k) == L.MinTextPx, "tiny text is lifted to the minimum")
	end,

	["a computer and a tablet show the whole menu"] = function()
		local Math, Config = load()
		for _, size in { { 1920, 1080 }, { 1366, 768 }, { 1280, 720 }, { 1024, 768 } } do
			local w, h, phone = content(Config, size[1], size[2], Math.fitHeight)
			H.expect(not phone, size[1] .. " is not a phone")
			local plan = Math.plan(w, h, phone)
			H.expect(plan.whole, size[1] .. "x" .. size[2] .. " fits whole")
			H.expect(Math.totalUnits(false) * plan.k <= h + 0.5, "its height fits")
			H.expect(
				plan.x0 >= 0 and plan.kx * Config.UI.Halloween.Menu.Layout.WidthUnits <= w + 0.5,
				"its width fits"
			)
			H.expect(plan.kx >= plan.k, "widths never narrower than heights")
			local nameUnits = Math.card(false).NameTextUnits
			H.expect(nameUnits * plan.k >= 12, "card names at least 12 px at " .. size[1])
		end
	end,

	["a computer window too short scrolls instead of shrinking past readable"] = function()
		local Math, Config = load()
		local L = Config.UI.Halloween.Menu.Layout
		local plan = Math.plan(900, 200, false)
		H.expect(not plan.whole and plan.k == 900 / L.WidthUnits, "it scrolls at the width's scale")
	end,

	["today's board, and when the next one opens"] = function()
		local Math, Config = load()
		local C = Config.Halloween
		H.expect(Math.today({ today = 3 }, C.StartsAt) == 3, "the view's today wins")
		H.expect(Math.today(nil, C.StartsAt + 10) == 1, "else the clock's board")
		H.expect(Math.today({}, C.StartsAt + 2 * C.BoardSeconds + 5) == 3, "day three")
		H.expect(Math.today(nil, C.StartsAt - 5) == 0, "none before the start")
		local at, final = Math.nextQuestsAt(2)
		H.expect(at == C.StartsAt + 2 * C.BoardSeconds and not final, "board 3 opens next")
		at, final = Math.nextQuestsAt(C.Boards)
		H.expect(at == C.EndsAt and final, "after the last board: the event's end")
		at = Math.nextQuestsAt(0)
		H.expect(at == C.StartsAt, "before the start: board 1")
	end,

	["the red ! counts today's board only"] = function()
		local Math = load()
		local view = {
			boards = {
				{ n = 1, quests = { { have = 1, need = 1, claimed = false } } },
				{
					n = 2,
					quests = {
						{ have = 3, need = 3, claimed = false },
						{ have = 2, need = 3, claimed = false },
						{ have = 5, need = 5, claimed = true },
					},
				},
			},
		}
		H.expect(Math.claimable(view, 2) == 1, "one waits on today's board")
		H.expect(Math.claimable(view, 1) == 1, "yesterday's is not today's")
		H.expect(Math.claimable(view, 3) == 0, "no board, nothing")
		H.expect(Math.claimable(nil, 2) == 0, "no view, nothing")
	end,

	["quest words, counts, the King's chance and the packs"] = function()
		local Math, Config = load()
		H.expect(Math.questText("Wins", 1) == "Win 1 match", "one")
		H.expect(Math.questText("Balls", 15) == "Pocket 15 balls", "many")
		H.expect(Math.questText("Active", 1800) == "Play 30 min", "minutes")
		H.expect(Math.questCount("Balls", 20, 15) == "15/15", "capped at the need")
		H.expect(Math.questCount("Active", 600, 1800) == "10/30", "minutes")
		H.expect(Math.chanceWords(0.05) == "5", "5%")
		for _, key in Config.Halloween.Packs.Keys do
			H.expect(Math.packCandy(key) > 0, key .. " gives Candy")
		end
		H.expect(Math.packCandy("Nope") == 0, "an unknown pack gives none")
	end,

	["the Strings the menu reads are there"] = function()
		local Strings = H.require("Strings")
		local W = Strings.Halloween :: any
		for _, key in
			{ "KingRibbon", "Owned", "BuyConfirm", "NeedCandy", "BoughtCue", "QuestsTitle" }
		do
			H.expect(type(W[key]) == "string", key)
		end
		for _, key in { "NewQuestsIn", "QuestsEndIn", "GetCandy", "Claim", "Claimed", "Reward" } do
			H.expect(type(W[key]) == "string", key)
		end
		for _, reason in { "Poor", "Owned", "Closed", "Busy", "Default" } do
			H.expect(type(W.BuyFailed[reason]) == "string", "BuyFailed." .. reason)
		end
		H.expect(W.KingRibbon:format("5"):find("5%", 1, true) ~= nil, "the ribbon's chance")
	end,
}
