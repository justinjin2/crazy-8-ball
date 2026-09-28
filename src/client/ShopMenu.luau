--!strict
-- ShopMenu: the Shop (docs/prompts/ECONOMY_UI_PROMPT.md sections 11 and 12), opened from the
-- left column's Shop tile (or the D-pad's up in the hub) through Menus. Tabs:
-- - Cases: a card per case (chest icon, name, price with the cash icon, "Guaranteed Uncommon
--   or better"), Buy, Buy 10 (for the price of 9), and an "Odds" button (the word) opening
--   every cue's % grouped by rarity, totalling 100. A sale shows the old price struck through
--   and a real countdown. Not enough money: "Need $X more", jumping to Money with the
--   smallest pack that covers it (never right after a lost match). Restricted regions
--   (ShopState): a short note instead of Buy.
-- - Limited: the Founder's Cue (Robux, placeholder) and the Beta Cue (money, numbered copies,
--   "412 of 1,000 sold", a countdown, "Owned #412").
-- - Money: the seven packs (icons, amounts, "+7%" pills, the Robux price with the U+E002
--   glyph) and the "First purchase: double money" ribbon.
-- - VIP: VIP and its perks, the welcome offer while its window is open, the Starter Pack,
--   Money Party, Fast Open; "Owned" on what is owned; "Coming soon" while an id is 0.
-- Data: ItemState ("Shop" and "Items" snapshots) and ItemState.request("ItemRequest" |
-- "StoreRequest", ...).
--
-- STUB (2026-09-28, overnight foundation): the frame, its tabs and a "Loading..." line on each
-- page. The contents are the next agent's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)

local NAME = "Shop"
local TABS = { "Cases", "Limited", "Money", "Vip" }
-- Each tab's icon (Config.UI.Kit.Icons; an empty id shows none).
local TAB_ICONS: { [string]: string } = {
	Cases = "CaseStandard",
	Limited = "Limited",
	Money = "CashStack",
	Vip = "Vip",
}

local ShopMenu = {}

--- Build the Shop (closed) and register it with Menus. `deps`: see InventoryMenu.new.
function ShopMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local words: { [string]: string } = Strings.Menus.Tabs.Shop :: any
	local tabs: { MenuFrame.Tab } = {}
	for _, key in TABS do
		table.insert(tabs, { key = key, text = words[key], icon = TAB_ICONS[key] })
	end
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Shop,
		icon = "Shop",
		tabs = tabs,
		money = true,
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

return ShopMenu
