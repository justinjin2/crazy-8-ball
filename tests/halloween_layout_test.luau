--!strict
-- The Halloween tile's place on the hub's right side (Halloween/TileLayout; HubCorners): at a
-- phone's, a tablet's and a computer's size, with the offer tile shown and hidden, it clears
-- the offer tile, the touch jump button, the top bar row and the left column.

local H = require("./harness")

local function load()
	return H.require("Halloween.TileLayout"), H.require("Config")
end

-- The HUD screen sits under Roblox's top bar (UI.luau: IgnoreGuiInset false).
local INSETS = { 36, 58 }

local SIZES = {
	{ name = "phone", w = 844, h = 390, touch = true },
	{ name = "iPad", w = 1024, h = 768, touch = true },
	{ name = "PC", w = 1920, h = 1080, touch = false },
}

-- The offer tile's whole box as HubCorners lays it out (timer pill to price line), its words
-- 2.4 tiles wide.
local function offerBox(Config: any, h: number, short: boolean, centreX: number): any
	local C = Config.UI.Corners
	local px = if short then C.ShortOfferPx else C.OfferPx
	local wordPx = if short then C.ShortBigWordPx else C.BigWordPx
	local dealPx = if short then C.ShortDealPx else C.DealPx
	local pricePx = if short then C.ShortPricePx else C.PricePx
	local pillPx = if short then C.ShortTimerPillPx else C.TimerPillPx
	local cy = h * C.ChallengeYShare
	local top = cy - px / 2 + C.TimerPillAt[2] * px - pillPx / 2
	local wordBottom = 0.92 * px + wordPx / 2 + 2
	local bottom = cy - px / 2 + wordBottom + dealPx + 2 + pricePx + 2
	local width = 2.4 * px
	return { x = centreX - width / 2, y = top, w = width, h = bottom - top }
end

-- Roblox's touch jump button in the HUD screen's pixels.
local function jumpBox(w: number, fullH: number, inset: number): any
	local small = math.min(w, fullH) <= 500
	local size = if small then 70 else 120
	local x = if small then w - 95 else w - 170
	local y = (if small then fullH - 90 else fullH - 210) - inset
	return { x = x, y = y, w = size, h = size }
end

return {
	["the tile clears the offer, the jump button, the top row and the left column"] = function()
		local TileLayout, Config = load()
		local T = Config.UI.Halloween.Tile
		local C = Config.UI.Corners
		for _, size in SIZES do
			for _, inset in INSETS do
				local h = size.h - inset
				local short = h < Config.Multiplayer.Style.ShortHeight
				local big = if short then C.ShortChallengePx else C.ChallengePx
				local offerPx = if short then C.ShortOfferPx else C.OfferPx
				-- HubCorners keeps the widest word clear of the edge; the offer's words are the
				-- widest (2.4 tiles), so the column's middle is at least this far in.
				local right = math.max(
					C.ChallengeRightPx,
					math.ceil((2.4 * offerPx - big) / 2) + C.WordEdgePx
				)
				local centreX = size.w - right - big / 2
				local tilePx = if short then T.ShortPx else T.Px
				local wordPx = if short then T.ShortWordPx else T.WordPx
				for _, offerShown in { false, true } do
					local offer = if offerShown then offerBox(Config, h, short, centreX) else nil
					local input = {
						w = size.w,
						h = h,
						touch = size.touch,
						centreX = centreX,
						yShare = C.ChallengeYShare,
						tilePx = tilePx,
						wordPx = wordPx,
						wordWidth = 0.62 * wordPx * 9, -- "HALLOWEEN" in Fredoka One, generously
						pillPx = if short then T.ShortPillPx else T.PillPx,
						gapPx = T.GapPx,
						offer = offer,
					}
					local _, _, box = TileLayout.place(input)
					local where = ("%s (inset %d, offer %s)"):format(
						size.name,
						inset,
						tostring(offerShown)
					)
					H.expect(box.y >= 4, where .. ": under the top bar row")
					H.expect(box.x + box.w <= size.w, where .. ": on screen")
					H.expect(
						box.x > size.w / 2,
						where .. ": on the right, clear of the left column"
					)
					if offer then
						H.expect(
							not TileLayout.overlaps(box, offer),
							where .. ": clear of the offer tile"
						)
					end
					if size.touch then
						H.expect(
							not TileLayout.overlaps(box, jumpBox(size.w, size.h, inset)),
							where .. ": clear of the jump button"
						)
					end
					H.expect(box.y + box.h <= h, where .. ": above the screen's foot")
				end
			end
		end
	end,

	["with no offer the tile takes the Daily Challenge's spot"] = function()
		local TileLayout, Config = load()
		local _, cy = TileLayout.place({
			w = 1920,
			h = 1000,
			touch = false,
			centreX = 1800,
			yShare = Config.UI.Corners.ChallengeYShare,
			tilePx = 94,
			wordPx = 21,
			wordWidth = 120,
			pillPx = 22,
			gapPx = 10,
		})
		H.expect(cy == 420, "at 0.42 of the height")
	end,
}
