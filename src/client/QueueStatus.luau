--!strict
-- QueueStatus: one small card at the top middle for the global queue (designer,
-- 2026-09-28): an arena's "Waiting for players 1/2", a teammate's "Searching worldwide 0:07"
-- (the host has their own card), and for a few seconds why a teleport did not happen.
-- Main says what the line is each frame (setLine); a notice (flash) wins while it lasts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)

local Q = Config.UI.Queue
local QueueStatus = {}
QueueStatus.__index = QueueStatus

function QueueStatus.new(screen: ScreenGui): any
	local self: any = setmetatable({}, QueueStatus)
	local root = HudParts.frame(screen, "QueueStatus")
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.ZIndex = Q.ZIndex
	root.Visible = false
	self.root = root
	local card = HudParts.card(root, "Card")
	card.Size = UDim2.fromScale(1, 1)
	self.card = card
	self.text = HudParts.text(card, "Line", Q.StatusTextPx, "")
	self.text.TextWrapped = false
	self.text.Position = UDim2.fromOffset(10, 4)
	self.text.Size = UDim2.new(1, -20, 1, -8)
	self.line = nil
	self.notice = nil
	self.noticeUntil = 0
	self.shown = false
	return self
end

--- The standing line, or nil for none.
function QueueStatus.setLine(self: any, text: string?)
	self.line = text
end

--- A one-off line for Queue.NoticeSeconds.
function QueueStatus.flash(self: any, text: string)
	self.notice = text
	self.noticeUntil = os.clock() + Q.NoticeSeconds
end

function QueueStatus.update(self: any)
	if self.notice and os.clock() > self.noticeUntil then
		self.notice = nil
	end
	local text = self.notice or self.line
	local show = text ~= nil and text ~= ""
	if show and self.text.Text ~= text then
		self.text.Text = text :: string
	end
	if show ~= self.shown then
		self.shown = show
		if show then
			self.root.Visible = true
			UIAnim.popIn(self.card)
		else
			UIAnim.popOut(self.card, function()
				if not self.shown then
					self.root.Visible = false
				end
			end)
		end
	end
	if show then
		local screen: any = self.root.Parent
		local width = if screen
			then math.min(Q.StatusWidth, screen.AbsoluteSize.X - 20)
			else Q.StatusWidth
		self.root.Size = UDim2.fromOffset(width, Q.StatusHeight)
		-- The screen already starts under Roblox's top bar (UI.screen).
		self.root.Position = UDim2.new(0.5, 0, 0, Q.StatusTop)
	end
end

return QueueStatus
