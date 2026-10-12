--!strict
-- OwnerMessage: the owner's announcements (the admin panel, designer 2026-10-11; Grow a
-- Garden style). Big white words with a dark outline at the top middle of the screen,
-- "[OWNER]" first in black outlined in white (ChatTags.ownerTag), then "Painicane: message",
-- popping in and out (the house's small-HUD entrance), queued one at a time for
-- Config.Admin.Message's time; the same line goes in the chat window as a system line.
-- Only a message from an owner's user id (Admin.isOwner) is shown, whoever sent it on.
-- It shows in a match too: an announcement is rare and meant for everyone at once.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared:WaitForChild("Admin"))
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local ChatTags = require(script.Parent.ChatTags)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)

local M = Config.Admin.Message
local K = Config.UI.Kit

local OwnerMessage = {}

type Line = { name: string, text: string }

local queue: { Line } = {}
local showing = false
local label: TextLabel? = nil
local limit: UITextSizeConstraint? = nil
local started = false

-- The line as RichText: the tag, then "name: text" in white with the kit's ink outline
-- (`big`: on screen, the tag's white outline thicker so it reads over the world).
local function richLine(line: Line, big: boolean?): string
	local ink = HudParts.tone("Ink"):ToHex()
	local words = ChatTags.paint(
		Strings.Admin.MessageLine:format(line.name, line.text),
		HudParts.tone("White")
	)
	return ChatTags.ownerTag(if big then M.TagOutlinePx else nil)
		.. ' <stroke color="#'
		.. ink
		.. '" thickness="2">'
		.. words
		.. "</stroke>"
end

local function build(): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "OwnerMessage"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60 -- over the HUD and menus: the owner speaks to everyone
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	local object = Instance.new("TextLabel")
	object.Name = "Line"
	object.AnchorPoint = Vector2.new(0.5, 0)
	object.Position = UDim2.fromScale(0.5, M.TopShare)
	object.Size = UDim2.new(M.WidthShare, 0, 0, M.TextPx * 3)
	object.BackgroundTransparency = 1
	object.Font = (Enum.Font :: any)[K.Font]
	object.RichText = true
	object.TextScaled = true
	object.TextWrapped = true
	object.TextColor3 = HudParts.tone("White")
	object.TextYAlignment = Enum.TextYAlignment.Top
	object.AutoLocalize = false -- the owner's own words
	object.Visible = false
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = M.TextPx
	size.Parent = object
	limit = size
	object.Parent = gui
	return object
end

-- Fits the line's size to the screen: a phone's short screen gets the smaller size.
local function fit(object: TextLabel)
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 800
	local px = if height < M.PhoneBelowPx then M.PhoneTextPx else M.TextPx
	object.Size = UDim2.new(M.WidthShare, 0, 0, px * 3)
	if limit then
		limit.MaxTextSize = px
	end
end

local function showNext()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local line = table.remove(queue, 1) :: Line
	local object = label or build()
	label = object
	fit(object)
	object.Text = richLine(line, true)
	UIAnim.popIn(object)
	local seconds =
		math.min(M.MaxSeconds, M.Seconds + M.SecondsPerChar * utf8.len(line.text) :: number)
	task.delay(seconds, function()
		UIAnim.popOut(object, function()
			showing = false
			showNext()
		end)
	end)
end

local function onMessage(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local name, text = payload.name, payload.text
	if not Admin.isOwner(payload.userId) or type(name) ~= "string" or type(text) ~= "string" then
		return
	end
	if name == "" or text == "" or utf8.len(text) == nil then
		return
	end
	local line: Line = { name = name, text = text }
	ChatTags.system(richLine(line))
	table.insert(queue, line)
	showNext()
end

--- Listens for the owner's announcements (Progression calls this once).
function OwnerMessage.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local ok, remote = pcall(Net.get, "OwnerMessage")
		if not ok or typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
			warn("[8ball] OwnerMessage: no OwnerMessage remote")
			return
		end
		(remote :: RemoteEvent).OnClientEvent:Connect(onMessage)
	end)
end

return OwnerMessage
