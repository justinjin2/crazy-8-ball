--!strict
-- Progression: the client side of ranks, money and the economy. It builds the screens (the rank
-- HUD top left, the money HUD bottom left, nameplates, the flying cash, the result screen, NEW
-- RANK!, the roadmap; the left column, the Shop, Inventory, Rewards and Trade menus, the lucky
-- blocks and the top banner) and routes the server's messages to them:
-- - MoneyGrant (a shot paid you): cash chips fly from the pockets into the money HUD.
-- - MatchSummary (your match ended): the result screen, then NEW RANK! if you ranked up.
-- - RankEvent (/xp, /newrank): NEW RANK!, never during a shot.
-- - DevNotice: a private line in the chat window (the developer commands).
-- - ItemState, ShopState, RewardState: the economy's snapshots (ItemState keeps them).
-- It also starts ChatTags (the [TIER] tag before names in chat).
--
-- Every full menu (the roadmap too) opens through Menus, one at a time. The left column hides
-- in a match and under the popups (the result screen, NEW RANK!, a lucky block's reel, the
-- teleport screen); a match starting (or its result screen) closes the reel and any open
-- menu. No reward ever pops up by itself: the daily login and playtime gifts are claimed in
-- Rewards (designer, 2026-10-04). Nothing here ever sends an amount back: the numbers are
-- already in the save.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Banner = require(script.Parent.Banner)
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
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local ResultScreen = require(script.Parent.ResultScreen)
local RewardChips = require(script.Parent.RewardChips)
local RewardsMenu = require(script.Parent.RewardsMenu)
local Roadmap = require(script.Parent.Roadmap)
local RankClaimBlock = require(script.Parent.RankClaimBlock)
local ShopMenu = require(script.Parent.ShopMenu)
local FreeRewardMenu = require(script.Parent.FreeRewardMenu)
local HubCorners = require(script.Parent.HubCorners)
local PlayerList = require(script.Parent.PlayerList)
local ResultCutscene = require(script.Parent.ResultCutscene)
local SettingsMenu = require(script.Parent.SettingsMenu)
local SettingsState = require(script.Parent.SettingsState)
local TeleportScreen = require(script.Parent.TeleportScreen)
local TradeMenu = require(script.Parent.TradeMenu)
local UISound = require(script.Parent.UISound)
local LuckyClient = require(script.Parent.LuckyClient)

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
local corners: any = nil
local playerList: any = nil
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
	return result:isOpen() or newRank:isOpen() or LuckyClient.isOpen()
end

-- Close a lucky block's reel (and its pull cutscene) and then any open menu, in that order,
-- so the gamepad's selection is not handed back to a button in a menu that is closing.
local function closeScreens()
	LuckyClient.close()
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
	SettingsState.start() -- the switches (sound groups, Lower effects) and the seen moments
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
	-- The tutorial lane's hand points at these (TutorialAnchors).
	TutorialAnchors.set("Rank", rankHud.holder)
	TutorialAnchors.set("MoneyHud", money.root)

	-- The economy's screens share one table of the things they fly to and open; a field set
	-- after a menu is built is still seen by it (they read it when used). A lucky block
	-- flies to the hotbar (hotbarCenter, bumpHotbar) when it shows, else to deps.column's
	-- Inventory tile.
	local deps: any = {
		money = money,
		flyer = flyer,
		rankHud = rankHud,
		hotbarCenter = LuckyClient.hotbarCenter,
		bumpHotbar = LuckyClient.bumpHotbar,
	}
	-- The result screen and NEW RANK! were built before this table: they read it when used
	-- (the win's block and rank rewards fly to the hotbar or deps.column).
	result:setDeps(deps)
	newRank:setDeps(deps)
	ShopMenu.new(screen, deps)
	InventoryMenu.new(screen, deps)
	RewardsMenu.new(screen, deps)
	TradeMenu.new(screen, deps)
	FreeRewardMenu.new(screen, deps)
	SettingsMenu.new(screen, deps)
	-- Held rank rewards: the claim block over the roadmap (the tutorial lane).
	RankClaimBlock.new(screen, deps, function(): boolean
		return roadmap:isOpen()
	end, function()
		Menus.close(RANKED)
	end)
	column = MenuColumn.new(screen, {
		rankHud = rankHud,
		money = money,
		onPress = function(name: string)
			Menus.open(name)
		end,
		shopNew = deps.shopNew,
	})
	deps.column = column
	corners = HubCorners.new(screen, deps)
	deps.corners = corners
	-- The list keeps clear of the Settings gear and its word in the top row.
	playerList =
		PlayerList.new(screen, { avoid = { corners.gearTile.button, corners.gearTile.word } })
	banner = Banner.new(screen, { avoid = { rankHud.holder } })
	Menus.setBlocker(function(): boolean
		return lastState.inMatch or popupUp()
	end)
	LuckyClient.start(screen) -- lucky blocks: the hotbar, the throw, the reel
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
			-- A loss is remembered for a minute (the ult screen's need-money notice).
			if summary.you.outcome ~= "Win" then
				deps.lostAt = os.clock()
			end
			closeScreens() -- the result screen takes the screen from them
			-- A 1v1 first plays its cutscene (GUI lane, C11a); the result screen opens partway
			-- through, and closing it puts the scene back. One still waiting on Continue keeps
			-- the screen: this one waits its turn, with no cutscene.
			local played = not result:isOpen()
				and ResultCutscene.play(summary, function()
					result:show(summary, function()
						ResultCutscene.stop()
					end)
				end)
			if not played then
				result:show(summary)
			end
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
--- RANK!, a lucky block's reel, or any full menu: the roadmap, Shop, Inventory, Rewards,
--- Trade): Main's B-to-leave waits while one is up.
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

--- The rematch row's time ran out (no rematch): Continue takes its place.
function Progression.dropChoices()
	if started then
		result:dropChoices()
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

--- The D-pad in the hub (Main, for a press no GUI took): up, right and down open the Shop,
--- Inventory and Free Reward (the Daily Challenge once that is gone), as the left column's
--- tiles; left focuses the player list (GUI lane, 2026-10-03). Never in a match (the D-pad
--- aims there), while a menu is open (the D-pad moves its selection), while a text box has
--- focus, or while the column is hidden. Returns whether it took the press.
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
	-- Left focuses the player list.
	if name == "PlayerList" then
		return playerList:focus()
	end
	-- Down is Free Reward while it is up, else the Daily Challenge.
	if name == "FreeReward" and not column:freeShown() then
		corners:pressChallenge()
		return true
	end
	column:press(name)
	return true
end

--- Where something earned elsewhere flies to: a column tile's centre in absolute pixels
--- ("Inventory" for a cue), or nil.
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
--- hide in a match and under the popups, a match starting closes the reel and any open menu,
--- the banner waits during a match, the nameplates of your match's players hide, and held
--- rank popups wait for a quiet moment.
function Progression.update(state: State)
	if not started then
		return
	end
	lastState = state
	local busy = result:isOpen() or newRank:isOpen() or ResultCutscene.isPlaying()
	local reelUp = LuckyClient.isOpen()
	rankHud:setVisible(not state.inMatch and not busy and not TutorialAnchors.hidden("Rank"))
	-- Under the result screen and NEW RANK! the column and the hotbar still show while a block
	-- or cue flies into them (RewardChips), so the target is there to catch it.
	local catching = RewardChips.catching()
	column:setVisible(
		not state.inMatch and (not busy or catching) and not reelUp and not teleportUp()
	)
	corners:setVisible(not state.inMatch and not busy and not reelUp and not teleportUp())
	playerList:setVisible(
		not state.inMatch and not busy and not reelUp and not teleportUp() and not Menus.isOpen()
	)
	-- The lucky block hotbar: the lobby with nothing over it (its own bag aside).
	local menu = Menus.current()
	LuckyClient.setVisible(
		not state.inMatch
			and (not busy or catching)
			and not reelUp
			and not teleportUp()
			and (menu == nil or menu == "LuckyBag")
	)
	column:setPadRoute(not state.inMatch and not Menus.isOpen())
	money:setPlusShown(not state.inMatch) -- no shop trips during a game (designer, 2026-10-06)
	banner:setInMatch(state.inMatch)
	if state.inMatch and ResultCutscene.isPlaying() then
		-- A rematch (or any match) starting ends the result cutscene.
		ResultCutscene.stop()
	end
	if state.inMatch and not wasInMatch then
		-- A full menu or the reel would cover the table (and the overlay would keep the
		-- gamepad's A and B): a player waiting on a pad may have opened either.
		closeScreens()
	end
	wasInMatch = state.inMatch
	plates:setHidden(if state.inMatch then state.matchUserIds else NOBODY)
	-- Held rank popups also wait for the reel to close.
	if #heldRanks > 0 and not state.shooting and not popupUp() then
		-- The menus draw over the HUD screen, so they make way for the popup.
		Menus.close()
		newRank:show(table.remove(heldRanks, 1))
	end
end

return Progression
