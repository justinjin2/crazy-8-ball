--!strict
-- TutorialReveal: the tutorial's case reveals after game 1 (docs/prompts/TUTORIAL_PROMPT.md
-- step 5): Bronze's Standard Case with "Open now", then the match's Rare Case on its timer with
-- OK. A STAND-IN: the GUI lane's magic 8-ball (MagicBall) is the real reveal and is not merged
-- into this lane; once it is, `show` hands the drop to it instead (see the request in
-- docs/parallel/tutorial.md) and this card goes. Anchors for the hand: OpenNow, RevealOk.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local HudParts = require(script.Parent.HudParts)
local RewardChips = require(script.Parent.RewardChips)
local UIAnim = require(script.Parent.UIAnim)
local TutorialAnchors = require(script.Parent.TutorialAnchors)

local R = Config.Tutorial.Reveal
local Copy = Strings.Tutorial.Reveal
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any

local TutorialReveal = {}
TutorialReveal.__index = TutorialReveal

export type Reveal = typeof(setmetatable(
	{} :: {
		root: Frame,
		title: TextLabel,
		picture: ImageLabel,
		note: TextLabel,
		open: TextButton,
		ok: TextButton,
		kind: string?,
		readyAt: number?,
		onOpen: (() -> ())?,
		onOk: (() -> ())?,
	},
	TutorialReveal
))

function TutorialReveal.new(gui: ScreenGui): Reveal
	local root = HudParts.card(gui, "TutorialReveal")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(R.WidthPx, R.HeightPx)
	root.BackgroundColor3 = HudParts.tone("White")
	root.BackgroundTransparency = 0
	root.Visible = false
	root.ZIndex = 5 -- over the dim (1), under the hand (8)
	local title = HudParts.text(root, "Title", R.TitlePx, "")
	title.Position = UDim2.fromOffset(0, R.PadPx)
	title.Size = UDim2.new(1, 0, 0, R.TitlePx + 8)
	title.ZIndex = 21
	local picture = Instance.new("ImageLabel")
	picture.Name = "Case"
	picture.BackgroundTransparency = 1
	picture.AnchorPoint = Vector2.new(0.5, 0)
	picture.Position = UDim2.new(0.5, 0, 0, R.PadPx + R.TitlePx + 12)
	picture.Size = UDim2.fromOffset(R.PicturePx, R.PicturePx)
	picture.ScaleType = Enum.ScaleType.Fit
	picture.ZIndex = 21
	picture.Parent = root
	local note = HudParts.text(root, "Note", R.NotePx, "")
	note.Position = UDim2.new(0, 0, 1, -(R.PadPx + R.ButtonPx + R.NotePx + 14))
	note.Size = UDim2.new(1, 0, 0, R.NotePx + 6)
	note.ZIndex = 21
	local self: Reveal
	local function button(name: string, text: string, tone: string, fn: () -> ()): TextButton
		local b = HudParts.candy(root, text, fn, tone)
		b.Name = name
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 1, -R.PadPx)
		b.Size = UDim2.fromOffset(R.ButtonWidthPx, R.ButtonPx)
		b.ZIndex = 22
		HudParts.setMinHit(b, 44)
		return b
	end
	local open = button("OpenNow", Copy.OpenNow, "Green", function()
		local fn = self.onOpen
		self:hide()
		if fn then
			fn()
		end
	end)
	local ok = button("Ok", Copy.Ok, "Blue", function()
		local fn = self.onOk
		self:hide()
		if fn then
			fn()
		end
	end)
	TutorialAnchors.set("OpenNow", open)
	TutorialAnchors.set("RevealOk", ok)
	self = setmetatable({
		root = root,
		title = title,
		picture = picture,
		note = note,
		open = open,
		ok = ok,
		kind = nil,
		readyAt = nil,
		onOpen = nil,
		onOk = nil,
	}, TutorialReveal)
	return self
end

--- Shows a case: "Drop" (an instant case: Open now -> `onOpen`) or "Rare" (on its timer:
--- "Opens in 59:58", OK -> `onOk`). Showing the same kind again does nothing.
function TutorialReveal.show(
	self: Reveal,
	kind: string,
	caseId: string,
	readyAt: number?,
	onOpen: (() -> ())?,
	onOk: (() -> ())?
)
	self.onOpen, self.onOk, self.readyAt = onOpen, onOk, readyAt
	if self.kind == kind and self.root.Visible then
		return
	end
	self.kind = kind
	self.title.Text = Copy.Got:format(CASE_NAMES[caseId] or caseId)
	HudParts.setIcon(self.picture, RewardChips.caseIcon(caseId))
	self.open.Visible = kind == "Drop"
	self.ok.Visible = kind ~= "Drop"
	self.note.Text = ""
	self.root.Visible = true
	UIAnim.popIn(self.root)
end

--- The card's button now (the gamepad's selection goes here).
function TutorialReveal.button(self: Reveal): TextButton
	return if self.kind == "Drop" then self.open else self.ok
end

function TutorialReveal.hide(self: Reveal)
	self.root.Visible = false
	self.kind = nil
end

function TutorialReveal.showing(self: Reveal): boolean
	return self.root.Visible
end

--- Every frame: the timer's words.
function TutorialReveal.update(self: Reveal)
	if not self.root.Visible or self.readyAt == nil then
		return
	end
	local left = math.max(0, math.floor((self.readyAt :: number) - workspace:GetServerTimeNow()))
	self.note.Text = Copy.ReadyIn:format(("%d:%02d"):format(left // 60, left % 60))
end

return TutorialReveal
