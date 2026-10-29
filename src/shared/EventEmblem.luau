--!strict
-- EventEmblem: which event emblem a cue's card wears (Config.UI.EventEmblem; designer,
-- 2026-10-29: the "Halloween 2026" badge on the four Halloween cues). Data-driven: the cue's
-- Catalog row's Event picks the picture, so a new event's cues need only a picture in Config
-- and never code per cue. Pure (no Instances): InventoryCard and the Halloween event menu put
-- the picture on their cards.
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

return EventEmblem
