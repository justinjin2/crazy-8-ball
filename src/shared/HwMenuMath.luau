--!strict
-- HwMenuMath: the Halloween event menu's pure maths (src/client/Halloween/EventMenu; mock A,
-- designer 2026-10-29), so a Lune test checks it: the menu's scale on a phone and a computer
-- (Config.UI.Halloween.Menu.Layout units), today's quest board, when the next board opens, a
-- quest's line and count, and how many of today's quests wait for a CLAIM (the tile's red "!").
-- No Instances.
local Config = require(script.Parent.Config)
local Strings = require(script.Parent.Strings)
local Event = require(script.Parent.Halloween.Event)

local H = Config.Halloween
local L = Config.UI.Halloween.Menu.Layout
local QUEST_TEXT: { [string]: { One: string, Many: string } } = Strings.Halloween.Quests :: any

local HwMenuMath = {}

-- How the menu is drawn in a content box: `k` pixels per unit for heights and text, `kx` for
-- x positions and widths, the content starting `x0` in from the left. `whole`: everything fits
-- with no scrolling (a computer, a tablet). `short`: a phone's card units (taller buttons).
export type Plan = {
	k: number,
	kx: number,
	x0: number,
	whole: boolean,
	short: boolean,
}

--- A cue card's units (Layout.Card, a phone's Layout.ShortCard).
function HwMenuMath.card(short: boolean): any
	return if short then L.ShortCard else L.Card
end

--- The cue row's height in units.
function HwMenuMath.rowUnits(short: boolean): number
	return HwMenuMath.card(short).HeightUnits
end

--- TODAY'S QUESTS' (and GET CANDY's) height in units: the title row, four rows, the foot.
function HwMenuMath.boxUnits(): number
	return L.BoxTitleUnits + 4 * L.RowUnits + 3 * L.RowGapUnits + L.BoxPadUnits
end

--- The whole content's height in units.
function HwMenuMath.totalUnits(short: boolean): number
	return HwMenuMath.rowUnits(short) + L.SectionGapUnits + HwMenuMath.boxUnits()
end

--- The frame's fitHeight for a content `width` (the scroll bar taken off): a phone, the cue row
--- whole with PeekPx of the quests box under it; a computer, all of it (the frame caps that to
--- the room under the top bar, then plan shrinks the menu to fit).
function HwMenuMath.fitHeight(width: number, phone: boolean): number
	local kx = width / L.WidthUnits
	if phone then
		return math.ceil((HwMenuMath.rowUnits(true) + L.SectionGapUnits) * kx + L.PeekPx)
	end
	return math.ceil(HwMenuMath.totalUnits(false) * kx)
end

--- The plan for a content box `width` x `height`. A computer shrinks the menu to fit the box
--- whole (heights by k, widths up to MaxStretch times that, centred), unless that would go
--- under MinWholeScale; a phone (or a box too short) keeps the width's scale and scrolls.
function HwMenuMath.plan(width: number, height: number, phone: boolean): Plan
	local kxFull = math.max(0.01, width / L.WidthUnits)
	if not phone then
		local k = math.min(kxFull, height / HwMenuMath.totalUnits(false))
		if k >= L.MinWholeScale then
			local kx = math.min(kxFull, k * L.MaxStretch)
			return {
				k = k,
				kx = kx,
				x0 = math.floor((width - kx * L.WidthUnits) / 2),
				whole = true,
				short = false,
			}
		end
	end
	return { k = kxFull, kx = kxFull, x0 = 0, whole = false, short = phone }
end

--- Text `units` tall at scale `k`, never under Layout.MinTextPx.
function HwMenuMath.textPx(units: number, k: number): number
	return math.max(L.MinTextPx, math.floor(units * k + 0.5))
end

--- Today's quest board: the view's `today`, else the board open now by the clock (0 before the
--- event starts).
function HwMenuMath.today(view: any, now: number): number
	if type(view) == "table" and type(view.today) == "number" and view.today >= 1 then
		return math.min(H.Boards, math.floor(view.today))
	end
	return Event.boardIndex(now)
end

--- When the menu's quest timer ends: the next board's opening, or after the last board the
--- event's end (`final` true).
function HwMenuMath.nextQuestsAt(today: number): (number, boolean)
	if today < H.Boards then
		return Event.boardOpensAt(today + 1), false
	end
	return H.EndsAt, true
end

--- How many of today's quests are done and not yet claimed.
function HwMenuMath.claimable(view: any, today: number): number
	if type(view) ~= "table" or type(view.boards) ~= "table" then
		return 0
	end
	local board = view.boards[today]
	if type(board) ~= "table" or type(board.quests) ~= "table" then
		return 0
	end
	local count = 0
	for _, q in board.quests do
		if type(q) == "table" and not q.claimed and (q.have or 0) >= (q.need or 1) then
			count += 1
		end
	end
	return count
end

--- A quest's line ("Win 3 matches", "Play 30 min").
function HwMenuMath.questText(kind: string, need: number): string
	local t = QUEST_TEXT[kind]
	if t == nil then
		return kind
	end
	local n = if kind == "Active" then math.floor(need / 60) else need
	return if n == 1 then t.One else t.Many:format(n)
end

--- A quest's count ("7/10"; minutes for the Active kind).
function HwMenuMath.questCount(kind: string, have: number, need: number): string
	local got = math.min(have, need)
	if kind == "Active" then
		return ("%d/%d"):format(got // 60, need // 60)
	end
	return ("%d/%d"):format(got, need)
end

--- The King's drop chance as whole percent words ("5").
function HwMenuMath.chanceWords(chance: number): string
	return tostring(math.floor(chance * 100 + 0.5))
end

--- The Candy pack `key`'s Candy (Config.Products.List), 0 for none.
function HwMenuMath.packCandy(key: string): number
	local row = (Config.Products.List :: any)[key]
	return if type(row) == "table" and type(row.Candy) == "number" then row.Candy else 0
end

return HwMenuMath
