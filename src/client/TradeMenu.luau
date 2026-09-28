--!strict
-- TradeMenu: the Trade menu (docs/prompts/ECONOMY_UI_PROMPT.md section 11), opened from the left
-- column's Trade tile (or the D-pad's left in the hub) through Menus. No tabs. Trading itself
-- is a later session: tonight it is the frame marked Soon, a list of the players in this
-- server (headshot, username, rank badge) with a greyed Trade button each, and a "Trading is
-- coming soon" note.
--
-- STUB (2026-09-28, overnight foundation): the frame and a "Loading..." line on its one page
-- (frame:page()). The contents are the next agent's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)

local NAME = "Trade"

local TradeMenu = {}

--- Build the Trade menu (closed) and register it with Menus. `deps`: see InventoryMenu.new.
function TradeMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Trade,
		icon = "Trade",
	})
	MenuFrame.placeholder(frame:page())
	local _ = deps
	local handle: Menus.Handle = {
		open = function(_tab: string?)
			frame:open()
		end,
		close = function()
			frame:close()
		end,
		isOpen = function(): boolean
			return frame:isOpen()
		end,
		root = frame.root,
	}
	Menus.register(NAME, handle)
	return handle
end

return TradeMenu
