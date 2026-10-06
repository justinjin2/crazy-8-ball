--!strict
-- FreeRewardMenu: the Free Reward page (GUI lane, designer 2026-10-03, D4), opened from the
-- left column's glowing gift (or the D-pad's down) through Menus. Two big cards side by side
-- (stacked on a narrow screen), each gone once claimed:
-- - Join the group: Join is Roblox's own join prompt (GroupService:PromptJoinAsync); then the
--   server asks Roblox again and gives the group reward (RewardRequest "ClaimGroup"). Once a
--   member, the button reads Claim.
-- - Favorite the game: Favorite is Roblox's own favorite prompt (AvatarEditorService:
--   PromptSetFavorite on the place); when it answers yes (and GetFavorite agrees, when Roblox
--   answers it), the client claims (RewardRequest "ClaimFavorite": $10,000 + a Mystery block,
--   once; a server cannot check a favorite). Under it: "Liking the game helps us too!" with no
--   reward tied to it (Roblox gives games no way to check a like).
-- What a claim gave flies out of its button (RewardsFlyer); its blocks land in the hotbar.
-- With both claimed the page says thank you (and the column's tile goes). Gamepad: opening
-- lands on the first card's button; B closes (Menus). Sizes in Config.UI.FreeReward.
local AvatarEditorService = game:GetService("AvatarEditorService")
local GroupService = game:GetService("GroupService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HoleFill = require(script.Parent.HoleFill)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local RewardsFlyer = require(script.Parent.RewardsFlyer)
local RewardsParts = require(script.Parent.RewardsParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local NAME = "FreeReward"
local F = Config.UI.FreeReward
local K = Config.UI.Kit
local W = Strings.FreeReward

local FreeRewardMenu = {}

type Card = {
	key: string,
	root: Frame,
	icon: ImageLabel,
	title: TextLabel,
	reward: TextLabel,
	line: TextLabel,
	note: TextLabel?,
	button: TextButton,
	sparkle: any,
}

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function gamepad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

--- Build the page (closed) and register it with Menus. `deps`: Progression's shared table.
function FreeRewardMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.FreeReward,
		icon = "FreeReward",
	})
	local page = frame:page()
	local flyer = deps.rewardsFlyer or RewardsFlyer.new(screen, deps)
	deps.rewardsFlyer = flyer
	local geo: MenuFrame.Geo? = nil
	local busy: { [string]: boolean } = {}
	local cards: { [string]: Card } = {}

	local thanks = HudParts.text(page, "Thanks", 24, W.AllDone)
	thanks.Size = UDim2.fromScale(1, 1)
	thanks.Visible = false
	thanks.ZIndex = 3

	local function makeCard(key: string, iconKey: string, titleText: string, press: () -> ()): Card
		local root = HudParts.card(page, key)
		root.ZIndex = 3
		if HudParts.paleEdged(NAME) then
			HudParts.paleEdge(root)
		end
		local icon = HudParts.icon(root, iconKey, "Icon")
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.ZIndex = 4
		local title = HudParts.text(root, "Title", 24, titleText)
		title.ZIndex = 4
		local reward = HudParts.text(root, "Reward", 28, "", HudParts.color(K.Numbers.Money))
		reward.AutoLocalize = false
		reward.ZIndex = 4
		local line = HudParts.note(root, "Line", 15, "")
		line.ZIndex = 4
		local button = HudParts.candy(root, "", press, "Green")
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.ZIndex = 5
		local made: Card = {
			key = key,
			root = root,
			icon = icon,
			title = title,
			reward = reward,
			line = line,
			note = nil,
			button = button,
			sparkle = nil,
		}
		cards[key] = made
		return made
	end

	local claim: (key: string, action: string) -> ()

	local group = makeCard("Group", "Group", W.GroupTitle, function()
		UISound.play("Click")
		local state = ItemState.rewards()
		local view = if type(state) == "table" then state.group else nil
		if type(view) == "table" and view.member == true then
			claim("Group", "ClaimGroup")
			return
		end
		task.spawn(function()
			pcall(function()
				GroupService:PromptJoinAsync(Config.Social.GroupId)
			end)
			-- Roblox's join prompt has closed: the server asks Roblox again on Claim.
			claim("Group", "ClaimGroup")
		end)
	end)
	local favorite = makeCard("Favorite", "Star", W.FavoriteTitle, function()
		UISound.play("Click")
		task.spawn(function()
			local result: any = nil
			local connection = AvatarEditorService.PromptSetFavoriteCompleted:Connect(
				function(r: any)
					result = r
				end
			)
			local ok = pcall(function()
				AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
			end)
			local waited = 0
			while ok and result == nil and waited < 120 do
				waited += task.wait(0.2)
			end
			connection:Disconnect()
			if result ~= Enum.AvatarPromptResult.Success then
				frame:notice(W.NotYet, "Red")
				return
			end
			-- Roblox's own answer, when it gives one (it may say no a moment after the prompt).
			local seen = false
			local deadline = os.clock() + F.FavoriteCheckSeconds
			repeat
				local okGet, fav = pcall(function(): boolean
					return AvatarEditorService:GetFavorite(game.PlaceId, Enum.AvatarItemType.Asset)
				end)
				seen = not okGet or fav == true -- no answer: trust the prompt
				if not seen then
					task.wait(0.5)
				end
			until seen or os.clock() > deadline
			if not seen then
				frame:notice(W.NotYet, "Red")
				return
			end
			claim("Favorite", "ClaimFavorite")
		end)
	end)
	local note = HudParts.note(favorite.root, "Like", 14, W.LikeToo)
	note.ZIndex = 4
	favorite.note = note

	claim = function(key: string, action: string)
		if busy[key] then
			return
		end
		busy[key] = true
		local card = cards[key]
		HudParts.setEnabled(card.button, false)
		local reply = ItemState.request("RewardRequest", action)
		busy[key] = false
		HudParts.setEnabled(card.button, true)
		if type(reply) == "table" and reply.ok then
			UISound.play("Claim")
			local from = card.button.AbsolutePosition + card.button.AbsoluteSize / 2
			flyer:reward(reply, from)
			UIAnim.glowBurst(card.root, HudParts.color(K.Numbers.Money), 0.4)
		elseif type(reply) == "table" and reply.reason == "NotMember" then
			frame:notice(W.NotMember, "Red")
		else
			frame:notice(MenuFrame.reason(reply), "Red")
		end
	end

	local function shown(): { Card }
		local state = ItemState.rewards()
		local list: { Card } = {}
		local g = if type(state) == "table" then state.group else nil
		local f = if type(state) == "table" then state.favorite else nil
		if type(g) == "table" and g.claimed ~= true then
			table.insert(list, group)
		end
		if type(f) == "table" and f.claimed ~= true then
			table.insert(list, favorite)
		end
		return list
	end

	local function paint()
		local state = ItemState.rewards()
		local g = if type(state) == "table" then state.group else nil
		local f = if type(state) == "table" then state.favorite else nil
		if type(g) == "table" then
			group.reward.Text = RewardsParts.words(RewardsParts.reward(g.reward))
			group.line.Text = W.GroupLine:format(round((tonumber(g.boost) or 0) * 100))
			HudParts.setText(group.button, if g.member == true then W.Claim else W.Join)
		end
		if type(f) == "table" then
			favorite.reward.Text = RewardsParts.words(RewardsParts.reward(f.reward))
			favorite.line.Text = W.FavoriteLine
			HudParts.setText(favorite.button, W.Favorite)
		end
	end

	local function layout()
		local g = geo
		if not g then
			return
		end
		paint()
		local list = shown()
		group.root.Visible = table.find(list, group) ~= nil
		favorite.root.Visible = table.find(list, favorite) ~= nil
		thanks.Visible = #list == 0
		local size = g.content
		local t = g.t
		local function span(pair: { number }): number
			return round(pair[1] + (pair[2] - pair[1]) * t)
		end
		local n = math.max(1, #list)
		local gap = g.gap * 2
		local side = size.X >= n * 260 + (n - 1) * gap -- side by side when both fit
		local cw = if side
			then math.min(F.CardMaxWidthPx, math.floor((size.X - (n - 1) * gap) / n))
			else math.min(F.CardMaxWidthPx * 1.4, size.X)
		local ch = if side then size.Y else math.floor((size.Y - (n - 1) * gap) / n)
		local totalW = if side then n * cw + (n - 1) * gap else cw
		local x0 = math.floor((size.X - totalW) / 2)
		local iconPx = math.min(span(F.IconPx), math.floor(ch * 0.32))
		local titlePx = math.max(K.Text.Min, span(F.TitlePx))
		local rewardPx = math.max(K.Text.Min, span(F.RewardPx))
		local linePx = math.max(K.Text.Min, span(F.LinePx))
		local buttonPx = math.max(44, span(F.ButtonPx))
		-- A card is as tall as its contents (plus a little air), centred in the page.
		local need = iconPx + titlePx + rewardPx + 3 * (linePx + 6) + buttonPx + 4 * g.pad + 24
		local y0 = 0
		if side and need < ch then
			y0 = math.floor((ch - need) / 2)
			ch = need
		end
		for index, card in list do
			local x = if side then x0 + (index - 1) * (cw + gap) else x0
			local y = if side then y0 else (index - 1) * (ch + gap)
			card.root.Position = UDim2.fromOffset(x, y)
			card.root.Size = UDim2.fromOffset(cw, ch)
			local pad = g.pad
			local inner = cw - 2 * pad
			local stackY = pad
			if not side and ch < iconPx + titlePx + rewardPx + linePx + buttonPx + 5 * pad then
				iconPx = math.max(40, ch - (titlePx + rewardPx + buttonPx + 4 * pad))
			end
			card.icon.Size = UDim2.fromOffset(iconPx, iconPx)
			card.icon.Position = UDim2.new(0.5, 0, 0, stackY)
			stackY += iconPx + 4
			HudParts.setTextSize(card.title, titlePx)
			card.title.Position = UDim2.fromOffset(pad, stackY)
			card.title.Size = UDim2.fromOffset(inner, titlePx + 6)
			stackY += titlePx + 6
			HudParts.setTextSize(card.reward, rewardPx)
			card.reward.Position = UDim2.fromOffset(pad, stackY)
			card.reward.Size = UDim2.fromOffset(inner, rewardPx + 6)
			stackY += rewardPx + 6
			HudParts.setTextSize(card.line, linePx)
			card.line.Position = UDim2.fromOffset(pad, stackY)
			card.line.Size = UDim2.fromOffset(inner, 2 * (linePx + 4))
			local cardNote = card.note
			if cardNote then
				HudParts.setTextSize(cardNote, linePx)
				cardNote.Position = UDim2.new(0, pad, 1, -pad - buttonPx - linePx - 10)
				cardNote.Size = UDim2.fromOffset(inner, linePx + 6)
			end
			card.button.Size = UDim2.fromOffset(math.min(inner, 240), buttonPx)
			card.button.Position = UDim2.new(0.5, 0, 1, -pad)
			HudParts.setButtonTextSize(card.button, math.max(K.Text.Min, span({ 18, 24 })))
		end
		if #list == 2 then
			list[1].button.NextSelectionRight = list[2].button
			list[2].button.NextSelectionLeft = list[1].button
			list[1].button.NextSelectionDown = (if side then nil else list[2].button) :: any
			list[2].button.NextSelectionUp = (if side then nil else list[1].button) :: any
		end
	end

	frame.onLayout = function(g: MenuFrame.Geo)
		geo = g
		layout()
	end
	frame.onOpen = function()
		layout()
		for _, card in cards do
			if card.sparkle == nil then
				card.sparkle = UIAnim.sparkle(card.root, HudParts.color(K.Numbers.Money))
			end
		end
		local list = shown()
		if gamepad() and list[1] then
			GuiService.SelectedObject = list[1].button
		end
	end
	frame.onClose = function()
		for _, card in cards do
			if card.sparkle then
				card.sparkle.stop()
				card.sparkle = nil
			end
		end
	end
	ItemState.Changed.Rewards:Connect(function()
		if frame:isOpen() then
			layout()
			local list = shown()
			if gamepad() then
				GuiService.SelectedObject = if list[1] then list[1].button else nil
			end
		end
	end)

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
	if F.TextDrop then
		HoleFill.watch(frame.root, true)
	end
	Menus.register(NAME, handle)
	return handle
end

return FreeRewardMenu
