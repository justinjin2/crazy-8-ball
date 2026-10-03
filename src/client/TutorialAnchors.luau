--!strict
-- TutorialAnchors: where the tutorial's hand points (docs/prompts/TUTORIAL_PROMPT.md). Screens
-- built by other lanes register their buttons here with one line each, so the hand finds them
-- whatever their layout:
--
--     TutorialAnchors.set("Abilities", tile)
--
-- Names in use: Request, GlobalQueue (the host card), PowerBar, UltButton (the ability bar's
-- press), UltConfirm (the pick's Confirm), Abilities, Inventory, Shop, FreeReward, Rank (the
-- column and the rank HUD), SpinButton, CodeBox, SpinBack (the spin screen), OpenNow (the
-- 8-ball's Open now), Lobby (the arena's result row), MoneyHud.
--
-- A screen may also hide one of its parts while the tutorial says so (TutorialAnchors.hidden).

local TutorialAnchors = {}

local anchors: { [string]: GuiObject? } = {}
local hiddenSet: { [string]: boolean } = {}

local changed = Instance.new("BindableEvent")
--- Fires (name) when an anchor is set or the hidden set changes.
TutorialAnchors.Changed = changed.Event

--- Registers the GuiObject the hand points at for `name` (nil removes it).
function TutorialAnchors.set(name: string, object: GuiObject?)
	anchors[name] = object
	changed:Fire(name)
end

--- The registered GuiObject for `name`, if it is still in the game.
function TutorialAnchors.get(name: string): GuiObject?
	local object = anchors[name]
	if object and object.Parent == nil then
		anchors[name] = nil
		return nil
	end
	return object
end

--- Whether the object for `name` can be pointed at now: registered, in the game and showing
--- (itself and every GuiObject above it visible).
function TutorialAnchors.showing(name: string): boolean
	local object: Instance? = TutorialAnchors.get(name)
	while object do
		if object:IsA("GuiObject") and not object.Visible then
			return false
		elseif object:IsA("LayerCollector") then
			return object.Enabled
		end
		object = object.Parent
	end
	return false
end

--- Whether the tutorial hides `name` now (the column and HUD items it brings in one by one).
function TutorialAnchors.hidden(name: string): boolean
	return hiddenSet[name] == true
end

--- The tutorial's call: hide exactly the items in `names` (a set), show the rest.
function TutorialAnchors.setHidden(names: { [string]: boolean })
	local same = true
	for name in names do
		if not hiddenSet[name] then
			same = false
		end
	end
	for name in hiddenSet do
		if not names[name] then
			same = false
		end
	end
	if same then
		return
	end
	table.clear(hiddenSet)
	for name, on in names do
		if on then
			hiddenSet[name] = true
		end
	end
	changed:Fire("")
end

return TutorialAnchors
