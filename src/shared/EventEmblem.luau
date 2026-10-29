--!strict
-- EventEmblem: which event emblem a cue's card wears (Config.UI.EventEmblem; designer,
-- 2026-10-29: the "Halloween 2026" badge on the four Halloween cues) and where it sits: bottom
-- right, just above the cue's name (designer, 2026-10-29: "move it to the right bottom right
-- above the name of the cue instead of top left corner"), in the picture's clear corner (every
-- cue picture runs from bottom left to top right). Data-driven: the cue's Catalog row's Event
-- picks the picture, so a new event's cues need only a picture in Config and never code per
-- cue. Pure (no Instances): InventoryCard and the Halloween event menu put the picture on their
-- cards.
local Config = require(script.Parent.Config)
local Catalog = require(script.Parent.Progression.Catalog)

local E = Config.UI.EventEmblem
local IMAGES: { [string]: string } = E.Images :: any

local EventEmblem = {}

--- The emblem picture for catalog cue `cueId` ("rbxassetid://..."), or nil: no such cue, no
--- event, no picture for its event, or the emblem switched off.
function EventEmblem.image(cueId: string?): string?
	if E.Enabled ~= true or type(cueId) ~= "string" then
		return nil
	end
	local row = Catalog.get(cueId)
	local event = if row then row.Event else nil
	if type(event) ~= "string" then
		return nil
	end
	local image = IMAGES[event]
	return if type(image) == "string" and image ~= "" then image else nil
end

--- The emblem's size in pixels for a `height` pixels tall slot (its picture's aspect kept).
function EventEmblem.size(height: number): (number, number)
	local h = math.max(1, math.floor(height + 0.5))
	return math.max(1, math.floor(h * E.Aspect + 0.5)), h
end

--- Where the emblem sits on a card `width` pixels wide: its right side `right` px in from the
--- card's right edge, its foot `gap` px over `above` (the top of the cue's name, or of a chip
--- over the name), `height` px tall with its picture's shape kept, never wider than `room` px
--- (then shorter, still its shape). Returns its left, top, width and height in whole pixels.
function EventEmblem.place(
	width: number,
	above: number,
	right: number,
	gap: number,
	height: number,
	room: number?
): (number, number, number, number)
	local w, h = EventEmblem.size(height)
	local most = math.max(1, math.floor((room or w) + 0.5))
	if w > most then
		w, h = most, math.max(1, math.floor(most / E.Aspect + 0.5))
	end
	local left = math.floor(width - right - w + 0.5)
	local top = math.floor(above - gap - h + 0.5)
	return left, top, w, h
end

return EventEmblem
