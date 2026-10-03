--!strict
-- Progression: the client side of ranks, money and the economy. It builds the screens (the rank
-- HUD top left, the money HUD bottom left, nameplates, the flying cash, the result screen, NEW
-- RANK!, the roadmap; the left column, the Shop, Inventory, Rewards and Trade menus, the case
-- opening and the top banner) and routes the server's messages to them:
-- - MoneyGrant (a shot paid you): cash chips fly from the pockets into the money HUD.
-- - MatchSummary (your match ended): the result screen, then NEW RANK! if you ranked up.
-- - RankEvent (/xp, /newrank): NEW RANK!, never during a shot.
-- - DevNotice: a private line in the chat window (the developer commands).
-- - ItemState, ShopState, RewardState: the economy's snapshots (ItemState keeps them).
-- It also starts ChatTags (the [TIER] tag before names in chat).
--
-- Every full menu (the roadmap too) opens through Menus, one at a time. The left column hides
-- in a match and under the popups (the result screen, NEW RANK!, the case opening, the
-- teleport screen); a match starting (or its result screen) closes the case opening and any
-- open menu. Nothing here ever sends an amount back: the numbers are already in the save.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Banner = require(script.Parent.Banner)
local CaseOpening = require(script.Parent.CaseOpening)
local CashFlyer = require(script.Parent.CashFlyer)
local ChatTags = require(script.Parent.ChatTags)
local InventoryMenu = require(script.Parent.InventoryMenu)
local ItemState = require(script.Parent.ItemState)
local MenuColumn = require(script.Parent.MenuColumn)
local Menus = require(script.Parent.Menus)
local MoneyHud = require(script.Parent.MoneyHud)
local Nameplates = require(script.Parent.Nameplates)
local NewRankPopup = require(script.Parent.NewRankPopup)
local RankHud = require(script.Parent.RankHud)
local ResultScreen = require(script.Parent.ResultScreen)
local RewardChips = require(script.Parent.RewardChips)
local RewardsMenu = require(script.Parent.RewardsMenu)
local Roadmap = require(script.Parent.Roadmap)
local ShopMenu = require(script.Parent.ShopMenu)
local ShopOfferPopup = require(script.Parent.ShopOfferPopup)
local ShopThanks = require(script.Parent.ShopThanks)
local MagicBall = require(script.Parent.MagicBall)
local Popups = require(script.Parent.Popups)
local TeleportScreen = require(script.Parent.TeleportScreen)
local TradeMenu = require(script.Parent.TradeMenu)
local UISound = require(script.Parent.UISound)

export type Hooks = {
	-- A pocket of a table, in the ScreenGui's pixels (may be off screen), or nil.
	pocketToScreen: (tableId: number, pocket: number) -> Vector2?,
}

export type State = {
	inMatch: boolean, -- seated at a table whose game is on (the match bar owns the top)
	shooting: boolean, -- your shot is being aimed or is rolling: no popups now
	matchUserIds: { [number]: boolean }, -- everyone at your table, for the nameplates
}

local Progression = {}

-- The roadmap's name in Menus.
local RANKED = "Ranked"
-- The D-pad route in the hub (MenuColumn): each direction's menu, from Config key names.
local PAD_ROUTE: { [Enum.KeyCode]: string } = {}
for menu, keyName in Config.UI.Menu.Column.PadKeys :: { [string]: string } do
	local ok, code = pcall(function()
		return (Enum.KeyCode :: any)[keyName]
	end)
	if ok and typeof(code) == "EnumItem" then
		PAD_ROUTE[code :: Enum.KeyCode] = menu
	end
end

local money: any = nil
local flyer: any = nil
local newRank: any = nil
local result: any = nil
local roadmap: any = nil
local rankHud: any = nil
local plates: any = nil
local column: any = nil
local banner: any = nil
local caseOpening: any = nil
local started = false
-- RankEvents held while you shoot or a result screen is up, shown in order afterwards.
local heldRanks: { any } = {}
local lastState: State = { inMatch = false, shooting = false, matchUserIds = {} }
local wasInMatch = false
local NOBODY: { [number]: boolean } = {}
-- Every teleport screen in PlayerGui (TeleportScreen's own, and the one a teleport brought:
-- src/first/Arrival keeps it up until the arena is ready).
local teleportGuis: { [ScreenGui]: boolean } = {}

local function valid(payload: any): boolean
	return type(payload) == "table"
end

local function showSystem(text: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local system = channels and channels:FindFirstChild("RBXSystem")
	if system and system:IsA("TextChannel") then
		system:DisplaySystemMessage(text)
	else
		print("[8ball] " .. text)
	end
end

-- Watch PlayerGui for the teleport screen (by its name), whoever made it.
local function watchTeleportScreens(playerGui: Instance)
	local function consider(child: Instance)
		if child:IsA("ScreenGui") and child.Name == TeleportScreen.GuiName then
			teleportGuis[child] = true
		end
	end
	for _, child in playerGui:GetChildren() do
		consider(child)
	end
	playerGui.ChildAdded:Connect(consider)
	playerGui.ChildRemoved:Connect(function(child)
		if child:IsA("ScreenGui") then
			teleportGuis[child] = nil
		end
	end)
end

local function teleportUp(): boolean
	for gui in teleportGuis do
		if gui.Enabled and gui.Parent then
			return true
		end
	end
	return false
end

-- A popup that has the player's attention: menus and held rank popups wait for it, the column
-- hides under it.
local function popupUp(): boolean
	return result:isOpen() or newRank:isOpen() or caseOpening:isOpen()
end

-- Close the case opening (its overlay; the first win's reveal belongs to the result screen)
-- and then any open menu, in that order, so the gamepad's selection is not handed back to a
-- button in a menu that is closing.
local function closeScreens()
	caseOpening:close()
	Menus.close()
end

--- Build every screen and listen to the server. Main calls this once, with the ScreenGui
--- and the hooks into the tables.
function Progression.start(screen: ScreenGui, hooks: Hooks)
	if started then
		return
	end
	started = true
	UISound.preload()
	ItemState.start() -- early, so the snapshots sent on load are heard
	money = MoneyHud.new(screen)
	flyer = CashFlyer.new(screen, money, hooks.pocketToScreen)
	newRank = NewRankPopup.new(screen, flyer, money)
	result = ResultScreen.new(screen, flyer, money, newRank)
	roadmap = Roadmap.new(screen)
	-- The roadmap is a full menu like the others: opening one closes the other.
	Menus.register(RANKED, {
		open = function(_tab: string?)
			roadmap:open()
		end,
		close = function()
			roadmap:close()
		end,
		isOpen = function(): boolean
			return roadmap:isOpen()
		end,
	})
	rankHud = RankHud.new(screen, function()
		Menus.open(RANKED)
	end)
	plates = Nameplates.new()
	ChatTags.start() -- the [TIER] tag before names in chat

	-- The economy's screens share one table of the things they fly to and open; a field set
	-- after a menu is built is still seen by it (they read it when used).
	local deps: any = { money = money, flyer = flyer, rankHud = rankHud }
	-- The result screen and NEW RANK! were built before this table: they read it when used
	-- (the free case and rank rewards fly to deps.column; the first win's reveal is
	-- deps.caseOpening's).
	result:setDeps(deps)
	newRank:setDeps(deps)
	caseOpening = CaseOpening.new(screen, deps)
	deps.caseOpening = caseOpening
	ShopMenu.new(screen, deps)
	InventoryMenu.new(screen, deps)
	RewardsMenu.new(screen, deps)
	TradeMenu.new(screen, deps)
	column = MenuColumn.new(screen, {
		rankHud = rankHud,
		money = money,
		onPress = function(name: string)
			Menus.open(name)
		end,
		shopNew = deps.shopNew,
	})
	deps.column = column
	banner = Banner.new(screen, { avoid = { rankHud.holder } })
	Menus.setBlocker(function(): boolean
		return lastState.inMatch or popupUp()
	end)
	-- Join and reward popups wait for the hub: no match, no screen or menu up.
	Popups.setGate(function(): boolean
		return not lastState.inMatch and not popupUp() and not Menus.isOpen() and not teleportUp()
	end)
	ShopThanks.start(screen)
	ShopOfferPopup.start(screen)
	MagicBall.start(screen, deps) -- the Case Drop reveals, through the popup queue
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		watchTeleportScreens(playerGui)
	end

	Net.get("MoneyGrant").OnClientEvent:Connect(function(payload: any)
		if valid(payload) and type(payload.grants) == "table" then
			flyer:onGrant(payload)
		end
	end)
	Net.get("MatchSummary").OnClientEvent:Connect(function(summary: any)
		if valid(summary) and valid(summary.you) and valid(summary.money) then
			-- A loss is remembered for a minute: no need-money popup right after it.
			if summary.you.outcome ~= "Win" then
				deps.lostAt = os.clock()
			end
			closeScreens() -- the result screen takes the screen from them
			result:show(summary)
		end
	end)
	Net.get("RankEvent").OnClientEvent:Connect(function(event: any)
		if valid(event) and valid(event.after) then
			table.insert(heldRanks, event)
			Progression.update(lastState)
		end
	end)
	Net.get("DevNotice").OnClientEvent:Connect(function(text: any)
		if type(text) == "string" then
			showSystem(text)
		end
	end)
end

--- Whether a rank, money or economy screen has the player's attention (the result screen, NEW
--- RANK!, the case opening, or any full menu: the roadmap, Shop, Inventory, Rewards, Trade):
--- Main's B-to-leave waits while one is up.
function Progression.isBusy(): boolean
	return started and (popupUp() or Menus.isOpen())
end

--- The rematch row on the result screen (designer, 2026-09-28): Main presses its buttons
--- (`fn(kind, summary)`), asks which summary's row is up, draws its state and ends it.
function Progression.setChoiceHandler(fn: (string, any) -> ())
	if started then
		result:setChoiceHandler(fn)
	end
end

function Progression.choosing(): any?
	return if started then result:choosing() else nil
end

function Progression.setChoices(state: any, now: number)
	if started then
		result:setChoices(state, now)
	end
end

function Progression.endChoices()
	if started then
		result:endChoices()
	end
end

--- Gamepad Y in the hub (Main): open the roadmap, or close it if it is up (designer,
--- 2026-09-27). Through Menus, so it closes any other menu first. Returns whether it did
--- anything.
function Progression.toggleRank(): boolean
	if not started then
		return false
	end
	if Menus.isOpen(RANKED) then
		Menus.close(RANKED)
		return true
	end
	return Menus.open(RANKED)
end

--- The D-pad in the hub (Main, for a press no GUI took): up, right, down and left open the
--- Shop, Inventory, Rewards and Trade, as the left column's tiles (overnight assumption,
--- 2026-09-28). Never in a match (the D-pad aims there), while a menu is open (the D-pad moves
--- its selection), while a text box has focus, or while the column is hidden. Returns whether
--- it took the press.
function Progression.padRoute(key: Enum.KeyCode): boolean
	local name = PAD_ROUTE[key]
	if not name or not started or lastState.inMatch then
		return false
	end
	if Menus.isOpen() or popupUp() or UserInputService:GetFocusedTextBox() ~= nil then
		return false
	end
	if not column:isShown() then
		return false
	end
	column:press(name)
	return true
end

--- Where something earned elsewhere flies to: a column tile's centre in absolute pixels
--- ("Inventory" for a case or a cue), or nil.
function Progression.menuTarget(name: string): Vector2?
	return if started then column:tileCenter(name) else nil
end

--- A column tile bounces as something lands on it.
function Progression.bumpMenu(name: string)
	if started then
		column:bump(name)
	end
end

--- Main calls this every frame with where the player is: the rank HUD and the left column
--- hide in a match and under the popups, a match starting closes the case opening and any open
--- menu, the banner waits during a match, the nameplates of your match's players hide, and held
--- rank popups wait for a quiet moment.
function Progression.update(state: State)
	if not started then
		return
	end
	lastState = state
	local busy = result:isOpen() or newRank:isOpen()
	rankHud:setVisible(not state.inMatch and not busy)
	-- Under the result screen and NEW RANK! the column still shows while a case or cue flies
	-- into its Inventory tile (RewardChips), so the tile is there to catch it.
	column:setVisible(
		not state.inMatch
			and (not busy or RewardChips.catching())
			and not caseOpening:isOpen()
			and not teleportUp()
	)
	column:setPadRoute(not state.inMatch and not Menus.isOpen())
	banner:setInMatch(state.inMatch)
	if state.inMatch and not wasInMatch then
		-- A full menu or the case opening would cover the table (and the overlay would keep
		-- the gamepad's A and B): a player waiting on a pad may have opened either.
		closeScreens()
	end
	wasInMatch = state.inMatch
	plates:setHidden(if state.inMatch then state.matchUserIds else NOBODY)
	-- Held rank popups also wait for the case opening's overlay to close.
	if #heldRanks > 0 and not state.shooting and not popupUp() then
		-- The menus draw over the HUD screen, so they make way for the popup.
		Menus.close()
		newRank:show(table.remove(heldRanks, 1))
	end
end

return Progression
