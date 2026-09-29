--!strict
-- RewardsCodes: the Rewards menu's Codes tab (docs/prompts/ECONOMY_UI_PROMPT.md section 11,
-- ECONOMY 18): "Got a code?", a text box and a green Redeem, the server's answer under them
-- ("Code redeemed: +$500 and a Standard Case", or "Code redeemed: 3 Ability Spins" for ABILITIES, in
-- green, or why not in red: "That code doesn't exist.", "You already used that code.", "That
-- code has expired."), and a short note. Kept high on the page, so a phone's keyboard never
-- covers it; the answer sits right under the box (not in the menu's bottom notice, which the
-- keyboard would hide).
--
-- The box is Selectable: a gamepad lands on it when the tab opens and A starts typing; Enter
-- (or the console keyboard's done) redeems, as Redeem does. The client sends the typed text
-- only; the server trims it, ignores its case and decides. Redeem calls ctx.claim("Redeem",
-- text, "Code", button, onReply) (RewardsMenu), which flies what it gave.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)
local RewardsParts = require(script.Parent.RewardsParts)
local UISound = require(script.Parent.UISound)

local R = Config.UI.Rewards
local K = Config.UI.Kit
local W = Strings.Menus.Rewards
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local INK = HudParts.tone("Ink")
local GOLD = HudParts.tone("Gold")
local span = RewardsParts.span
local round = RewardsParts.round
local MAX_LENGTH: number = Config.Daily.CodeMaxLength

local RewardsCodes = {}
RewardsCodes.__index = RewardsCodes

--- The Codes tab in `page` (a MenuFrame page). `ctx` is RewardsMenu's: claim(action, arg, key,
--- button, onReply) and busy(key).
function RewardsCodes.new(page: Frame, ctx: any): any
	local self: any = setmetatable({}, RewardsCodes)
	self.page = page
	self.ctx = ctx
	self.geo = nil :: any
	self.lit = false -- the box is selected or typing: its outline is gold

	local title = HudParts.text(page, "Title", R.CodeTitlePx[2], W.CodeTitle)
	title.TextWrapped = false
	title.ZIndex = 3
	self.title = title

	-- The box: a white field with an ink outline, the typed text in ink, a hint while empty.
	local box = HudParts.frame(page, "CodeBox")
	box.BackgroundTransparency = 0
	box.BackgroundColor3 = HudParts.tone("White")
	box.ClipsDescendants = true
	box.ZIndex = 3
	HudParts.corner(box, K.ButtonCornerPx)
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = R.CodeStrokePx
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	self.box, self.stroke = box, stroke
	local hint = HudParts.note(box, "Hint", R.CodeTextPx[2], W.CodeHint)
	hint.TextTransparency = 0.5
	hint.TextWrapped = false
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.ZIndex = 4
	self.hint = hint
	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.BackgroundTransparency = 1
	input.BorderSizePixel = 0
	input.Font = FONT
	input.TextColor3 = INK
	input.TextSize = R.CodeTextPx[2]
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ClearTextOnFocus = false
	input.PlaceholderText = "" -- the hint is a label, so it can be translated
	input.Text = ""
	input.AutoLocalize = false -- what the player types
	input.Selectable = true
	local noBox = Instance.new("Frame")
	noBox.BackgroundTransparency = 1
	input.SelectionImageObject = noBox -- the gold outline shows selection
	input.ZIndex = 5
	input.Parent = box
	self.input = input

	local redeem = HudParts.candy(page, W.Redeem, function()
		self:redeem()
	end, "Green")
	redeem.Name = "Redeem"
	redeem.ZIndex = 3
	HudParts.setMinHit(redeem, R.TouchPx)
	self.redeemButton = redeem
	input.NextSelectionRight = redeem
	redeem.NextSelectionLeft = input

	local answer = HudParts.text(page, "Answer", R.CodeAnswerPx[2], "")
	answer.TextWrapped = true
	answer.ZIndex = 3
	answer.Visible = false
	self.answer = answer
	local note = HudParts.note(page, "Note", R.CodeNotePx[2], W.CodeNote)
	note.TextWrapped = true
	note.ZIndex = 3
	self.note = note

	local function light()
		local on = self.lit or input:IsFocused()
		stroke.Color = if on then GOLD else INK
		stroke.Thickness = if on then K.SelectedStrokePx else R.CodeStrokePx
	end
	input.SelectionGained:Connect(function()
		self.lit = true
		light()
	end)
	input.SelectionLost:Connect(function()
		self.lit = false
		light()
	end)
	input.Focused:Connect(light)
	input.FocusLost:Connect(function(enterPressed: boolean)
		light()
		if enterPressed then
			self:redeem()
		end
	end)
	-- A gamepad's A on the selected box starts typing (the console's keyboard comes up).
	input.InputBegan:Connect(function(inputObject: InputObject)
		if inputObject.KeyCode == Enum.KeyCode.ButtonA and not input:IsFocused() then
			task.defer(function()
				if input.Parent and not input:IsFocused() then
					input:CaptureFocus()
				end
			end)
		end
	end)
	input:GetPropertyChangedSignal("Text"):Connect(function()
		if #input.Text > MAX_LENGTH then
			input.Text = string.sub(input.Text, 1, MAX_LENGTH)
			return
		end
		hint.Visible = input.Text == ""
		-- Typing a new code clears the last answer.
		if input.Text ~= "" and answer.Visible then
			answer.Visible = false
		end
	end)
	return self
end

--- Show the server's answer under the box (green for good news, red for a refusal).
function RewardsCodes.showAnswer(self: any, text: string, toneName: string)
	local answer: TextLabel = self.answer
	answer.Text = text
	answer.TextColor3 = HudParts.tone(toneName)
	answer.Visible = text ~= ""
end

--- Send the typed code (nothing typed: a reminder to type one).
function RewardsCodes.redeem(self: any)
	if self.ctx.busy("Code") then
		return
	end
	local text: string = self.input.Text
	if string.match(text, "^%s*$") then
		UISound.play("Click")
		self:showAnswer(W.NoCode, "Red")
		return
	end
	self:showAnswer("", "Green")
	self.ctx.claim("Redeem", text, "Code", self.redeemButton, function(reply: any)
		if reply.ok then
			local reward = RewardsParts.reward(reply)
			self:showAnswer(W.Redeemed:format(RewardsParts.summary(reward)), "Green")
			self.input.Text = ""
		else
			self:showAnswer(MenuFrame.reason(reply), "Red")
		end
	end)
end

--- Draw a RewardState: only Redeem's in-flight state matters here.
function RewardsCodes.set(self: any, _state: any)
	HudParts.setEnabled(self.redeemButton, not self.ctx.busy("Code"))
end

function RewardsCodes.setActive(_self: any, _on: boolean) end

function RewardsCodes.claimable(_self: any): boolean
	return false
end

function RewardsCodes.tick(_self: any, _now: number) end

--- Where a gamepad lands on this tab: the box.
function RewardsCodes.primary(self: any): GuiObject?
	return self.input
end

--- Size and place everything from the menu's layout (MenuFrame's onLayout geo): one centred
--- column at the top of the page.
function RewardsCodes.layout(self: any, geo: any)
	self.geo = geo
	local width = geo.content.X
	local t = geo.t
	local columnW = math.min(width, span(R.CodeWidthPx, t))
	local x = round((width - columnW) / 2)
	local gap = span(R.CodeGapPx, t)
	local y = gap
	local titlePx = span(R.CodeTitlePx, t)
	HudParts.setTextSize(self.title, titlePx)
	self.title.Position = UDim2.fromOffset(x, y)
	self.title.Size = UDim2.fromOffset(columnW, titlePx + 8)
	y += titlePx + 8 + gap
	local boxH = span(R.CodeBoxPx, t)
	local redeemW = span(R.RedeemWidthPx, t)
	local boxW = math.max(1, columnW - redeemW - gap)
	self.box.Position = UDim2.fromOffset(x, y)
	self.box.Size = UDim2.fromOffset(boxW, boxH)
	local textPx = span(R.CodeTextPx, t)
	local inset = math.max(8, round(boxH * 0.25))
	self.input.TextSize = textPx
	self.input.Position = UDim2.fromOffset(inset, 0)
	self.input.Size = UDim2.fromOffset(math.max(1, boxW - 2 * inset), boxH)
	HudParts.setTextSize(self.hint, textPx)
	self.hint.Position = UDim2.fromOffset(inset, 0)
	self.hint.Size = UDim2.fromOffset(math.max(1, boxW - 2 * inset), boxH)
	self.redeemButton.Position = UDim2.fromOffset(x + boxW + gap, y)
	self.redeemButton.Size = UDim2.fromOffset(redeemW, boxH)
	HudParts.setButtonTextSize(self.redeemButton, math.max(K.Text.Min, geo.button))
	y += boxH + gap
	local answerPx = span(R.CodeAnswerPx, t)
	HudParts.setTextSize(self.answer, answerPx)
	self.answer.Position = UDim2.fromOffset(x, y)
	self.answer.Size = UDim2.fromOffset(columnW, 2 * answerPx + 8)
	y += 2 * answerPx + 8 + gap
	local notePx = span(R.CodeNotePx, t)
	HudParts.setTextSize(self.note, notePx)
	self.note.Position = UDim2.fromOffset(x, y)
	self.note.Size = UDim2.fromOffset(columnW, 2 * notePx + 8)
end

return RewardsCodes
