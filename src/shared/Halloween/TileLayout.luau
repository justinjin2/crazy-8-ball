--!strict
-- TileLayout: where the Halloween tile sits on the hub's right side (hw-core; HubCorners lays it
-- out with this). Pure: plain numbers in the HUD screen's pixels (its top is under Roblox's top
-- bar), so a Lune test can check it clears its neighbours at every screen size.
--
-- With no offer tile showing, the tile takes the Daily Challenge's spot (Config.UI.Corners
-- ChallengeYShare). While the Starter/VIP offer tile shows, the offer never moves (moved down it
-- sits on a phone's jump button): on a touch screen (a phone, a tablet) the event tile stands
-- right above it, clear of the jump button under it; on a computer (no jump button) right below
-- its price, where the open Players list (top right, down to about the offer's top) never
-- reaches.
local TileLayout = {}

export type Box = { x: number, y: number, w: number, h: number } -- top-left corner and size

export type Input = {
	w: number, -- the HUD screen's size
	h: number,
	touch: boolean, -- a touch screen (Roblox's jump button at the bottom right)
	centreX: number, -- the right column's middle (the challenge's and the offer's)
	yShare: number, -- Config.UI.Corners.ChallengeYShare
	tilePx: number, -- the tile's icon
	wordPx: number, -- its word under the icon
	wordWidth: number, -- that word's width in pixels (it overhangs the icon)
	pillPx: number, -- the "ENDS IN" pill's height, over the tile's top edge
	gapPx: number, -- kept from the offer tile
	offer: Box?, -- the offer tile's whole box (timer pill to price), nil when it is hidden
}

-- The tile's whole box (the ends pill over its top, the word under it) for its icon's centre.
function TileLayout.extent(cx: number, cy: number, input: Input): Box
	local half = input.tilePx / 2
	local top = cy - half - input.pillPx / 2
	-- The word's middle is at 0.92 of the icon (HubCorners' corner tiles).
	local bottom = cy - half + 0.92 * input.tilePx + input.wordPx / 2 + 2
	local width = math.max(input.tilePx, input.wordWidth)
	return { x = cx - width / 2, y = top, w = width, h = bottom - top }
end

-- The icon's centre (x, y) and the tile's whole box.
function TileLayout.place(input: Input): (number, number, Box)
	local cx = input.centreX
	local cy = input.h * input.yShare
	local offer = input.offer
	if offer ~= nil then
		local probe = TileLayout.extent(cx, 0, input)
		if input.touch then
			-- Right above: the box's bottom a gap over the offer's top.
			cy = offer.y - input.gapPx - (probe.y + probe.h)
		else
			-- Right below: the box's top a gap under the offer's price.
			cy = offer.y + offer.h + input.gapPx - probe.y
		end
	end
	cy = math.floor(cy + 0.5)
	return cx, cy, TileLayout.extent(cx, cy, input)
end

-- Whether two boxes overlap (touching edges do not).
function TileLayout.overlaps(a: Box, b: Box): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return TileLayout
