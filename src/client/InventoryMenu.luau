--!strict
-- InventoryMenu: the Inventory (docs/prompts/ECONOMY_UI_PROMPT.md section 11), opened from the
-- left column's Inventory tile (or the D-pad's right in the hub) through Menus. Tabs:
-- - Cues: a grid of cue cards (the tinted thumbnail, CueThumb; the name; the rarity's dressing;
--   "x3" for copies; a gold NEW pill until opened; a green Equipped pill; a lock on Exclusive
--   and Unique), rarity filter chips (All, Common ... Secret, Exclusive, Unique), rarest
--   first. Choosing one shows a detail panel: the bigger thumbnail, name, rarity, "1,284 exist"
--   (ReplicatedStorage.CueCounts), Equip, Sell (confirm from Config.Cases.ConfirmSellFrom up:
--   MenuFrame:confirm, red for sell, blue for keep), "Sell duplicates" for that cue; and "Sell
--   all duplicates" at the top of the tab with the total it pays. Classic is always there.
-- - Cases: a row per case type owned (chest icon, name, "x4"), Open (and Open 10 with Fast
--   Open) into CaseOpening, and "Buy more" (Menus.open("Shop", "Cases")). Empty state: a
--   friendly line and the jump.
-- - Index: every cue by rarity (Exclusive and Unique last), never-owned cues as dark
--   silhouettes with "?" and no name, "5 / 7" per row with its reward and Claim, titles
--   earned at the top.
-- Data: ItemState ("Items" snapshot, ItemState.Changed.Items) and ItemState.request(
-- "ItemRequest", ...). Answers that did not work: frame:notice(MenuFrame.reason(reply), "Red").
--
-- STUB (2026-09-28, overnight foundation): the frame, its tabs and a "Loading..." line on each
-- page. The contents are the next agent's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)

local NAME = "Inventory"
local TABS = { "Cues", "Cases", "Index" }
-- Each tab's icon (Config.UI.Kit.Icons; an empty id shows none).
local TAB_ICONS: { [string]: string } = { Cues = "Cue", Cases = "CaseStandard", Index = "Index" }

local InventoryMenu = {}

--- Build the Inventory (closed) and register it with Menus. `deps` is Progression's shared
--- table: money (MoneyHud), flyer (CashFlyer), column (MenuColumn), caseOpening
--- (CaseOpening), rankHud; a field may be filled after this returns, so read it when used.
function InventoryMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local words: { [string]: string } = Strings.Menus.Tabs.Inventory :: any
	local tabs: { MenuFrame.Tab } = {}
	for _, key in TABS do
		table.insert(tabs, { key = key, text = words[key], icon = TAB_ICONS[key] })
	end
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Inventory,
		icon = "Inventory",
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

return InventoryMenu
