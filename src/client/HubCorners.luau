--!strict
-- HubCorners: the hub's small corner buttons (GUI lane, designer 2026-10-03, C2), shown with the
-- left column (Progression.update: never in a match or under a popup):
-- - Right edge, a little above the middle: the Daily Challenge target, its glow flashing. Daily
--   challenges are not built yet, so a press only says "Soon" in a bubble beside it. The
--   gamepad's D-pad down presses it when the Free Reward tile is gone (Progression.padRoute).
-- - Bottom left, just right of the money HUD: Invite (Roblox's invite prompt, carrying the
--   invite's launch data, Progression/Social.launchData) and Roblox Plus (the Store's Plus
--   prompt; hidden for members and where the shop does not offer Plus).
-- Sizes in Config.UI.Corners; words in Strings.Corners. Never gamepad stops (a selected button
-- would take the left stick from walking); the D-pad reaches the challenge.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local SocialRules = require(Shared:WaitForChild("Progression"):WaitForChild("Social"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Corners
local K = Config.UI.Kit
local S = Config.Multiplayer.Style
local W = Strings.Corners

local HubCorners = {}
HubCorners.__index = HubCorners

type Corner = {
	button: TextButton,
	icon: ImageLabel,
	word: TextLabel,
}

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- An icon button with the candy's hover, squish and bounce but no box (like the column's tiles),
-- its word across the icon's lower edge.
local function corner(
	parent: Instance,
	name: string,
	iconKey: string,
	words: string,
	press: () -> ()
): Corner
	local button = HudParts.candy(parent, "", press, "Blue", nil)
	button.Name = name
	button.Selectable = false
	local parts = HudParts.candyParts(button)
	parts.face.Visible = false
	local icon = HudParts.icon(parts.body, iconKey, "Art")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.45)
	icon.Size = UDim2.fromScale(1.05, 1.05)
	icon.ZIndex = 3
	local word = HudParts.text(parts.body, "Word", C.WordPx, words)
	word.TextWrapped = false
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Position = UDim2.fromScale(0.5, 0.92)
	word.ZIndex = 4
	return { button = button, icon = icon, word = word }
end

--- Build the corners into `screen` (the HUD ScreenGui), hidden until setVisible(true). `deps`:
--- money (MoneyHud: Invite and Plus sit right of it).
function HubCorners.new(screen: ScreenGui, deps: any): any
	local self: any = setmetatable({}, HubCorners)
	self.screen = screen
	self.deps = deps
	self.wanted = false
	self.showing = false
	self.connections = {} :: { RBXScriptConnection }
	local root = HudParts.frame(screen, "HubCorners")
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = Config.UI.Menu.Column.ZIndex
	root.Visible = false
	self.root = root

	self.challenge = corner(root, "Challenge", "Challenge", W.Challenge, function()
		self:pressChallenge()
	end)
	self.inviteTile = corner(root, "Invite", "Invite", W.Invite, function()
		UISound.play("Click")
		self:invite()
	end)
	self.plusTile = corner(root, "Plus", "RobloxPlus", W.Plus, function()
		UISound.play("Click")
		task.spawn(ItemState.request, "StoreRequest", "RobloxPlus")
	end)

	-- The challenge's glow flashes behind it.
	local glow = Instance.new("ImageLabel")
	glow.Name = "Flash"
	glow.BackgroundTransparency = 1
	glow.Image = K.Art.SoftGlow
	glow.ImageColor3 = HudParts.tone("Gold")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.45)
	glow.Size = UDim2.fromScale(2, 2)
	glow.ZIndex = 1
	glow.Parent = HudParts.candyParts(self.challenge.button).body
	self.flash = UIAnim.loop(glow, function(clock: number)
		local phase = (clock % C.ChallengeFlashSeconds) / C.ChallengeFlashSeconds
		glow.ImageTransparency = 0.25 + 0.75 * phase
	end)

	local function queueLayout()
		self:layout()
	end
	table.insert(
		self.connections,
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout)
	)
	local moneyRoot = deps.money and deps.money.root
	if typeof(moneyRoot) == "Instance" and moneyRoot:IsA("GuiObject") then
		table.insert(
			self.connections,
			moneyRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout)
		)
		table.insert(
			self.connections,
			moneyRoot:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueLayout)
		)
	end
	local player = Players.LocalPlayer
	if player then
		table.insert(
			self.connections,
			player:GetPropertyChangedSignal("MembershipType"):Connect(function()
				self:refreshPlus()
			end)
		)
	end
	table.insert(
		self.connections,
		ItemState.Changed.Shop:Connect(function()
			self:refreshPlus()
		end)
	)
	self:refreshPlus()
	self:layout()
	return self
end

function HubCorners.refreshPlus(self: any)
	local player = Players.LocalPlayer
	local member = player ~= nil and player.MembershipType == Enum.MembershipType.Premium
	local shop = ItemState.shop()
	local offered = type(shop) == "table" and shop.robloxPlus == true
	local show = offered and not member
	if self.plusTile.button.Visible ~= show then
		self.plusTile.button.Visible = show
	end
end

function HubCorners.layout(self: any)
	local size = self.screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local short = size.Y < S.ShortHeight
	local big = if short then C.ShortChallengePx else C.ChallengePx
	local small = if short then C.ShortSmallPx else C.SmallPx
	local wordPx = if short then C.ShortWordPx else C.WordPx
	local ch = self.challenge
	ch.button.AnchorPoint = Vector2.new(1, 0.5)
	ch.button.Size = UDim2.fromOffset(big, big)
	ch.button.Position = UDim2.new(1, -C.ChallengeRightPx, C.ChallengeYShare, 0)
	-- The word is wider than the icon: it overhangs both sides.
	ch.word.Size = UDim2.fromOffset(big * 2, wordPx + 4)
	HudParts.setTextSize(ch.word, wordPx)

	-- Invite and Plus right of the money HUD, centred on it.
	local origin = self.screen.AbsolutePosition
	local found = self.deps.money and self.deps.money.root
	local moneyRoot: GuiObject? = if typeof(found) == "Instance" and found:IsA("GuiObject")
		then found
		else nil
	local x, y = 200, size.Y - small
	if moneyRoot and moneyRoot.AbsoluteSize.X > 0 then
		x = moneyRoot.AbsolutePosition.X - origin.X + moneyRoot.AbsoluteSize.X + C.SmallGapPx
		y = moneyRoot.AbsolutePosition.Y - origin.Y + moneyRoot.AbsoluteSize.Y / 2
	end
	for index, c in { self.inviteTile, self.plusTile } do
		c.button.AnchorPoint = Vector2.new(0, 0.5)
		c.button.Size = UDim2.fromOffset(small, small)
		c.button.Position =
			UDim2.fromOffset(round(x + (index - 1) * (small + C.SmallGapPx)), round(y))
		c.word.Size = UDim2.fromOffset(small * 2, wordPx + 4)
		HudParts.setTextSize(c.word, wordPx)
	end
end

--- Show or hide the corners (Progression, with the column). Cheap to call every frame.
function HubCorners.setVisible(self: any, visible: boolean)
	local player = Players.LocalPlayer
	local loaded = player == nil or player:GetAttribute("DataLoaded") == true
	local show = visible and loaded
	if show == self.showing then
		return
	end
	self.showing = show
	if show then
		self.root.Visible = true
		self:layout()
		UIAnim.popIn(self.challenge.button)
	else
		self.root.Visible = false
	end
end

function HubCorners.isShown(self: any): boolean
	return self.showing
end

--- The Daily Challenge: a "Soon" bubble beside it (a press, or the D-pad's down).
function HubCorners.pressChallenge(self: any)
	if not self.showing then
		return
	end
	UISound.play("Click")
	local button = self.challenge.button
	UIAnim.bounce(button)
	UIAnim.glowBurst(self.challenge.icon, HudParts.tone("Gold"), 0.5)
	self:say(W.ChallengeSoon, button, -1)
end

--- A white bubble with `text` beside `button`: to its left (`side` -1) or right (1).
function HubCorners.say(self: any, text: string, button: GuiObject, side: number)
	if self.bubble then
		self.bubble:Destroy()
	end
	local bubble = HudParts.pill(self.root, "Bubble", HudParts.tone("White"))
	bubble.AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5)
	local words = HudParts.note(bubble, "Words", C.BubblePx, text)
	words.Size = UDim2.new(1, -16, 1, 0)
	words.Position = UDim2.fromOffset(8, 0)
	words.TextWrapped = false
	local wide = TextService:GetTextSize(
		text,
		C.BubblePx,
		(Enum.Font :: any)[K.Font],
		Vector2.new(2000, 200)
	).X
	local width = math.min(self.screen.AbsoluteSize.X - 40, wide + 28)
	bubble.Size = UDim2.fromOffset(round(width), C.BubblePx + 18)
	local pos = button.AbsolutePosition - self.root.AbsolutePosition
	local x = if side < 0 then pos.X - 8 else pos.X + button.AbsoluteSize.X + 8
	bubble.Position = UDim2.fromOffset(round(x), round(pos.Y + button.AbsoluteSize.Y / 2))
	bubble.ZIndex = 8
	words.ZIndex = 9
	self.bubble = bubble
	UIAnim.popIn(bubble)
	task.delay(C.BubbleSeconds, function()
		if self.bubble == bubble then
			self.bubble = nil
			UIAnim.popOut(bubble, function()
				bubble:Destroy()
			end)
		end
	end)
end

--- Roblox's invite prompt, carrying our launch data (the invite rewards).
function HubCorners.invite(self: any)
	local player = Players.LocalPlayer
	if not player then
		return
	end
	task.spawn(function()
		local okCan, can = pcall(function(): boolean
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not okCan or not can then
			self:say(W.InviteFailed, self.inviteTile.button, 1)
			return
		end
		local options = Instance.new("ExperienceInviteOptions")
		options.LaunchData = SocialRules.launchData(player.UserId)
		local ok = pcall(function()
			SocialService:PromptGameInvite(player, options)
		end)
		if not ok then
			self:say(W.InviteFailed, self.inviteTile.button, 1)
		end
	end)
end

function HubCorners.destroy(self: any)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.flash.stop()
	self.root:Destroy()
end

return HubCorners
