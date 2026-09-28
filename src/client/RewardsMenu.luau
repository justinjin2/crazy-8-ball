--!strict
-- RewardsMenu: the Rewards (docs/prompts/ECONOMY_UI_PROMPT.md section 11), opened from the left
-- column's Rewards tile (or the D-pad's down in the hub) through Menus. Tabs:
-- - Daily: seven day tiles (reward icon and text, "Day 1" ...), claimed ones with a check,
--   today's glowing with Claim, later ones dimmer; "Week 1 of 4: a Legendary Case on day 28".
-- - Playtime: 10 min $100, 30 min a Standard Case, 60 min 2 Standard Cases, progress bars from
--   the server's minutes today, Claim when ready.
-- - Codes: a TextBox and Redeem; the server's answers as a notice ("Code redeemed: +$500").
-- Claimed money flies into the money HUD; a case flies to the column's Inventory tile
-- (deps.column:tileCenter("Inventory")). The reminders when Roblox's menu opens live here too.
-- Data: ItemState ("Rewards" snapshot) and ItemState.request("RewardRequest", ...).
--
-- STUB (2026-09-28, overnight foundation): the frame, its tabs and a "Loading..." line on each
-- page. The contents are the next agent's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)

local NAME = "Rewards"
local TABS = { "Daily", "Playtime", "Codes" }
-- Each tab's icon (Config.UI.Kit.Icons; an empty id shows none).
local TAB_ICONS: { [string]: string } =
	{ Daily = "Calendar", Playtime = "Stopwatch", Codes = "Code" }

local RewardsMenu = {}

--- Build the Rewards (closed) and register it with Menus. `deps`: see InventoryMenu.new.
function RewardsMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local words: { [string]: string } = Strings.Menus.Tabs.Rewards :: any
	local tabs: { MenuFrame.Tab } = {}
	for _, key in TABS do
		table.insert(tabs, { key = key, text = words[key], icon = TAB_ICONS[key] })
	end
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Rewards,
		icon = "Rewards",
		tabs = tabs,
	})
	for _, key in TABS do
		MenuFrame.placeholder(frame:page(key))
	end
	local _ = deps
	local handle: Menus.Handle = {
		open = function(tab: string?)
			frame:open(tab)
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

return RewardsMenu
