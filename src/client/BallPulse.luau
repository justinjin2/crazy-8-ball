--!strict
-- BallPulse: makes a few balls on the table glow and pulse a few slow times
-- (Config.Multiplayer.Style.BallPulse). Main starts one when BallCallouts calls the groups or a
-- team's last ball out, and leaves a pulsing ball's usual outline off while it runs, so a ball
-- never carries two Highlights (7 at most here, inside Roblox's per-client budget).
--
-- A Highlight follows its ball, so a reveal mid-replay glows on balls still rolling; a ball
-- that sinks takes its glow down with it as it fades.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local P = Config.Multiplayer.Style.BallPulse

export type Item = { part: BasePart, color: Color3 }

local BallPulse = {}
BallPulse.__index = BallPulse

export type BallPulse = typeof(setmetatable(
	{} :: {
		glows: { { part: BasePart, highlight: Highlight } },
		started: number,
		seconds: number,
	},
	BallPulse
))

function BallPulse.new(): BallPulse
	return setmetatable({ glows = {}, started = 0, seconds = 0 }, BallPulse)
end

function BallPulse.active(self: BallPulse): boolean
	return #self.glows > 0
end

--- Whether `part` is pulsing now (its usual outline stays off meanwhile).
function BallPulse.has(self: BallPulse, part: BasePart): boolean
	for _, glow in self.glows do
		if glow.part == part then
			return true
		end
	end
	return false
end

function BallPulse.clear(self: BallPulse)
	for _, glow in self.glows do
		glow.highlight:Destroy()
	end
	table.clear(self.glows)
end

--- Pulse `items` for `seconds`, replacing any pulse already running.
function BallPulse.start(self: BallPulse, items: { Item }, seconds: number)
	self:clear()
	self.started, self.seconds = os.clock(), seconds
	for _, item in items do
		local h = Instance.new("Highlight")
		h.Name = "BallPulse"
		h.Adornee = item.part
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.FillColor = item.color
		h.OutlineColor = item.color
		h.FillTransparency = 1
		h.OutlineTransparency = 1
		h.Parent = item.part
		table.insert(self.glows, { part = item.part, highlight = h })
	end
	self:step()
end

--- Call every frame. True on the frame the pulse ends (the caller puts its outlines back).
function BallPulse.step(self: BallPulse): boolean
	if #self.glows == 0 then
		return false
	end
	local t = os.clock() - self.started
	if t >= self.seconds then
		self:clear()
		return true
	end
	-- Each pulse rises from nothing to full and falls back over PulseSeconds, so the last one
	-- ends dark and the glow never pops off.
	local beat = 0.5 - 0.5 * math.cos(2 * math.pi * t / P.PulseSeconds)
	local glow = P.Low + (1 - P.Low) * beat
	for _, g in self.glows do
		-- A ball fading out of a pocket takes its glow with it.
		local strength = glow * (1 - g.part.Transparency)
		g.highlight.Enabled = strength > 0.01
		g.highlight.OutlineTransparency = 1 - strength
		g.highlight.FillTransparency = 1 - strength * P.FillPeak
	end
	return false
end

return BallPulse
