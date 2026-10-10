--!strict
-- OpponentPrompt: "<name> needs an opponent..." (or players, on the team tables) with Join and
-- Dismiss (designer, 2026-09-27). A host whose pad has room who pressed Request sends it to
-- everyone free in the server (TableService); Join asks the server to stand you on their pad,
-- which seats you, and a full pad starts after the join grace (MatchEngine.startsAt).
--
-- One at a time, the newest. It goes by itself after Queue.RequestSeconds, when you
-- dismiss it or join, and as soon as the table's snapshot says the ask no longer stands (the
-- pad filled, the host left, played solo or cancelled the request), or you sit down anywhere.
--
-- A white card at the bottom centre with the host's headshot, shrunk on narrow screens.
-- Gamepad (designer, 2026-10-10): L2 joins and B dismisses (HubPad), their pictures on the two
-- buttons; nothing is selected, so the stick never stops walking.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local BottomLift = require(script.Parent.BottomLift)
local HudParts = require(script.Parent.HudParts)
local PadMode = require(script.Parent.PadMode)
local UIAnim = require(script.Parent.UIAnim)
local Copy = Strings.Match.Request
local M = Config.Multiplayer
local S = M.Style
local K = Config.UI.Kit
local OpponentPrompt = {}
OpponentPrompt.__index = OpponentPrompt

function OpponentPrompt.new(screen: ScreenGui, onJoin: (number, number) -> ()): any
	local self: any = setmetatable({}, OpponentPrompt)
	self.ask = nil -- the ask on show: {tableId, epoch, userId, name, at}
	self.open = false
	local root = HudParts.frame(screen, "OpponentPrompt")
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Size = UDim2.fromOffset(S.PromptWidth, S.PromptHeight)
	root.Visible = false
	self.root = root
	self.scale = Instance.new("UIScale")
	self.scale.Parent = root
	local card = HudParts.card(root, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	self.card = card
	local pad = S.PromptPadding
	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.BackgroundTransparency = 1
	face.AnchorPoint = Vector2.new(0, 0.5)
	face.Position = UDim2.new(0, pad, 0.5, 0)
	face.Size = UDim2.fromOffset(S.PromptFaceSize, S.PromptFaceSize)
	face.Parent = card
	HudParts.corner(face, 12)
	self.face = face
	local left = pad * 2 + S.PromptFaceSize
	local textHeight = S.PromptHeight - 3 * pad - S.PromptButtonHeight
	self.title = HudParts.text(card, "Title", K.Text.Body, "")
	self.title.AutoLocalize = false -- a player's name inside; the phrase itself is in Strings
	self.title.TextXAlignment = Enum.TextXAlignment.Left
	self.title.Position = UDim2.fromOffset(left, pad)
	self.title.Size = UDim2.new(1, -left - pad, 0, textHeight)
	local half = UDim2.new(0.5, -(left + pad + S.HeaderGap) / 2, 0, S.PromptButtonHeight)
	self.join = HudParts.candy(card, Copy.Join, function()
		local ask = self.ask
		if ask then
			onJoin(ask.tableId, ask.epoch)
			self:close()
		end
	end, "Green")
	self.join.Name = "Join"
	self.join.AnchorPoint = Vector2.new(0, 1)
	self.join.Position = UDim2.new(0, left, 1, -pad)
	self.join.Size = half
	self.dismiss = HudParts.candy(card, Copy.Dismiss, function()
		self:close()
	end, "Red", "X")
	self.dismiss.Name = "Dismiss"
	self.dismiss.AnchorPoint = Vector2.new(1, 1)
	self.dismiss.Position = UDim2.new(1, -pad, 1, -pad)
	self.dismiss.Size = half
	-- Small to look at, still a full touch target (docs/UI_STYLE.md section 5).
	HudParts.setMinHit(self.join, S.TouchTargetPx)
	HudParts.setMinHit(self.dismiss, S.TouchTargetPx)
	-- The controller's buttons for them (HubPad).
	self.join.Selectable = false
	self.dismiss.Selectable = false
	HudParts.padKey(
		self.join,
		PadMode.key(Config.Input.Gamepad.Hub.Queue) :: Enum.KeyCode,
		K.PadKey.Button
	)
	HudParts.padKey(self.dismiss, Enum.KeyCode.ButtonB, K.PadKey.Button)
	return self
end

--- A new ask from the server; it replaces any on show.
function OpponentPrompt.show(self: any, ask: any)
	if type(ask) ~= "table" or type(ask.tableId) ~= "number" or type(ask.userId) ~= "number" then
		return
	end
	self.ask = ask
	local phrase = if ask.teamSize == 1 then Copy.NeedsOpponent else Copy.NeedsPlayers
	self.title.Text = phrase:format(tostring(ask.name))
	self.face.Image = S.PromptHeadshot:format(ask.userId)
	if self.open then
		UIAnim.bounce(self.card)
		return
	end
	self.open = true
	self.root.Visible = true
	self.card.Visible = false
	UIAnim.popIn(self.card)
end

function OpponentPrompt.close(self: any)
	self.ask = nil
	if not self.open then
		return
	end
	self.open = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.root) then
		GuiService.SelectedObject = nil
	end
	UIAnim.popOut(self.card, function()
		if not self.open then
			self.root.Visible = false
		end
	end)
end

function OpponentPrompt.isOpen(self: any): boolean
	return self.open
end

--- Join the ask on show (the controller's L2). Returns whether there was one.
function OpponentPrompt.padJoin(self: any): boolean
	if not self.open or self.ask == nil then
		return false
	end
	HudParts.pressCandy(self.join)
	return true
end

--- Dismiss it (the controller's B). Returns whether one was open.
function OpponentPrompt.padDismiss(self: any): boolean
	if not self.open then
		return false
	end
	HudParts.pressCandy(self.dismiss)
	return true
end

--- Step it. `snapshotFor` gives a table's latest snapshot; `seated` is true once the local
--- player is on a pad or playing; `now` is the server's clock.
function OpponentPrompt.update(
	self: any,
	now: number,
	seated: boolean,
	snapshotFor: (number) -> any?
)
	local ask = self.ask
	if not ask then
		return
	end
	local s = snapshotFor(ask.tableId)
	local stands = s ~= nil
		and s.epoch == ask.epoch
		and s.phase == "Waiting"
		and s.hostId == ask.userId
		and s.requestedAt == ask.at -- nil once the host cancels it (designer, 2026-09-27)
		and #s.seats < s.teamSize * 2
	local old = type(ask.at) == "number" and now - ask.at > M.Queue.RequestSeconds
	if seated or old or not stands then
		self:close()
		return
	end
	-- Fit a narrow screen, centred at the bottom.
	local screen: any = self.root.Parent
	local width = if screen then screen.AbsoluteSize.X else S.PromptWidth
	self.scale.Scale = math.clamp((width - 2 * S.HeaderMargin) / S.PromptWidth, S.PromptMinScale, 1)
	self.root.Position = UDim2.new(0.5, 0, 1, -S.PromptBottom - BottomLift.get())
end

return OpponentPrompt
