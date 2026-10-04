--!strict
-- LuckyWorld: lucky blocks in the world, drawn the same on every screen (designer, 2026-10-03).
-- The server owns the models and their attributes (LuckyBlockService); this module only moves
-- them on this screen, from Phase and PhaseAt (server time):
--
-- - Flying: from the hands (where the server made it) to To on an arc, turning over.
-- - Landed: the pack's own bounce (Config.LuckyBlocks.Anim.BlockIdle) on its AnimationController.
-- - Rising: up HeightStuds, spinning faster and faster with a growing shiver, its glow and
--   particles swelling. Burst: it swells and fades out with a puff of its particles.
-- - Over a block held in someone's hands that is still on its timer: the countdown.
-- - For the owner of a landed block only: the open prompt (Roblox's native ProximityPrompt:
--   hold E, the gamepad's X, or touch and hold it for Open.HoldSeconds), which calls onOpen.
-- Tuning in Config.LuckyBlocks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local LuckyBlocks = require(Shared:WaitForChild("Progression"):WaitForChild("LuckyBlocks"))
local HudParts = require(script.Parent.HudParts)
local UISound = require(script.Parent.UISound)

local L = Config.LuckyBlocks
local U = L.UI
local W = Strings.LuckyBlocks

export type Options = {
	onOpen: (id: number) -> (), -- the owner held the prompt through
}

type Glow = { object: Instance, base: number }
type Tracked = {
	model: Model,
	part: BasePart?,
	from: CFrame, -- where it was made (the hands)
	scale: number, -- its scale as made
	idle: AnimationTrack?,
	glows: { Glow },
	burstPuffed: boolean,
	lastPhase: string?,
	prompt: ProximityPrompt?,
	promptAnchor: Attachment?,
	asked: boolean, -- the prompt was held through: no new prompt unless the open is refused
}
type Timer = { model: Model, gui: BillboardGui, label: TextLabel }

local World = {}

local tracked: { [Model]: Tracked } = {}
local timers: { [Model]: Timer } = {}
local options: Options? = nil
local started = false
local shiver = Random.new()

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function playerGui(): PlayerGui?
	local player = Players.LocalPlayer
	return player and player:FindFirstChildOfClass("PlayerGui")
end

local function myId(): number
	local player = Players.LocalPlayer
	return if player then player.UserId else 0
end

-- Turns over `turns` of a full rotation per second rising from `s0` to `s1` across `seconds`
-- (rate s0 + (s1 - s0) u^2): the angle reached at share `u`.
local function rampAngle(u: number, seconds: number, s0: number, s1: number): number
	return 2 * math.pi * seconds * (s0 * u + (s1 - s0) * u * u * u / 3)
end

---------------------------------------------------------------------------------------------
-- The open prompt
---------------------------------------------------------------------------------------------

local function dropPrompt(t: Tracked)
	if t.prompt then
		t.prompt:Destroy()
		t.prompt = nil
	end
	if t.promptAnchor then
		t.promptAnchor:Destroy()
		t.promptAnchor = nil
	end
end

local function addPrompt(t: Tracked)
	if t.prompt or t.asked or t.part == nil or options == nil then
		return
	end
	local part = t.part :: BasePart
	local id = t.model:GetAttribute("BlockId")
	if type(id) ~= "number" then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LuckyOpen"
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.ClickablePrompt = true
	prompt.ActionText = W.Open
	prompt.ObjectText = (W.Names :: { [string]: string })[tostring(t.model:GetAttribute("Kind"))]
		or ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = L.Open.HoldSeconds
	prompt.MaxActivationDistance = L.Open.MaxDistanceStuds
	prompt.RequiresLineOfSight = false
	local anchor = Instance.new("Attachment")
	anchor.Name = "LuckyOpenAnchor"
	anchor.Position = part.CFrame:PointToObjectSpace(
		t.model:GetPivot().Position + Vector3.new(0, L.Open.PromptLiftStuds, 0)
	)
	anchor.Parent = part
	t.promptAnchor = anchor
	t.prompt = prompt
	prompt.Triggered:Connect(function()
		if t.asked then
			return
		end
		t.asked = true
		prompt.Enabled = false
		local opts = options
		if opts then
			opts.onOpen(id)
		end
	end)
	-- Connect before parenting: Roblox owns display, hold progress and all input devices.
	prompt.Parent = anchor
end

---------------------------------------------------------------------------------------------
-- Thrown blocks
---------------------------------------------------------------------------------------------

local function track(model: Model)
	if tracked[model] or not model:IsA("Model") then
		return
	end
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local glows: { Glow } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			table.insert(glows, { object = d :: Instance, base = d.Rate })
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			table.insert(glows, { object = d :: Instance, base = d.Brightness })
		end
	end
	local t: Tracked = {
		model = model,
		part = part,
		from = model:GetPivot(),
		scale = model:GetScale(),
		idle = nil,
		glows = glows,
		burstPuffed = false,
		prompt = nil,
		promptAnchor = nil,
		asked = false,
	}
	tracked[model] = t
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			local gone = tracked[model]
			tracked[model] = nil
			if gone then
				dropPrompt(gone)
			end
		end
	end)
end

-- The kind's own idle (Config.LuckyBlocks.Kinds[kind].Idle), else the shared one.
local function idleId(model: Model): string
	local row = LuckyBlocks.kind(model:GetAttribute("Kind"))
	return if row and row.Idle and row.Idle ~= "" then row.Idle else L.Anim.BlockIdle
end

local function playIdle(t: Tracked)
	local id = idleId(t.model)
	if t.idle or id == "" then
		return
	end
	local controller = t.model:FindFirstChildOfClass("AnimationController")
	local animator = controller and controller:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, trackOrErr = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if ok then
		local idle = trackOrErr :: AnimationTrack
		idle.Looped = true
		idle:Play(0.2)
		t.idle = idle
	end
end

local function setGlow(t: Tracked, factor: number)
	for _, g in t.glows do
		local object = g.object
		if object:IsA("ParticleEmitter") then
			object.Rate = g.base * factor
		elseif object:IsA("Light") then
			object.Brightness = g.base * factor
		end
	end
end

local function step(t: Tracked, now: number)
	local model = t.model
	local to = model:GetAttribute("To")
	local phase = model:GetAttribute("Phase")
	local phaseAt = model:GetAttribute("PhaseAt")
	if typeof(to) ~= "CFrame" or type(phase) ~= "string" or type(phaseAt) ~= "number" then
		return
	end
	local target = to :: CFrame
	local edge = model:GetAttribute("SizeStuds")
	local half = (if type(edge) == "number" then edge else L.FloorSizeStuds) / 2
	local elapsed = math.max(0, now - phaseAt)
	local mine = model:GetAttribute("Owner") == myId()
	if t.lastPhase ~= phase then
		if mine and phase == "Landed" then
			UISound.play("LuckyPlace")
		end
		if mine and phase == "Rising" then
			UISound.play("LuckyAnticipation")
		end
		t.lastPhase = phase
	end
	if phase == "Flying" then
		local T = L.Throw
		local u = math.clamp(elapsed / T.Seconds, 0, 1)
		local fromCentre = t.from.Position + Vector3.new(0, half, 0)
		local toCentre = target.Position + Vector3.new(0, half, 0)
		local centre = fromCentre:Lerp(toCentre, u)
			+ Vector3.new(0, T.ArcHeightStuds * 4 * u * (1 - u), 0)
		local turn = -2 * math.pi * T.SpinTurns * u
		model:PivotTo(
			CFrame.new(centre)
				* target.Rotation
				* CFrame.Angles(turn, 0, 0)
				* CFrame.new(0, -half, 0)
		)
	elseif phase == "Landed" then
		model:PivotTo(target)
		playIdle(t)
		if mine then
			addPrompt(t)
			if t.prompt then
				local readyAt = model:GetAttribute("ReadyAt")
				local left = if type(readyAt) == "number" then readyAt - now else 0
				local kind = model:GetAttribute("Kind")
				local name = if type(kind) == "string" then W.Names[kind] or "" else ""
				t.prompt.ObjectText = if left > 0
					then name .. " · " .. LuckyBlocks.clockText(left)
					else name
			end
		end
	elseif phase == "Rising" or phase == "Burst" then
		dropPrompt(t)
		local R = L.Rise
		local riseFor = if phase == "Burst" then R.Seconds else elapsed
		local u = math.clamp(riseFor / R.Seconds, 0, 1)
		local lift = R.HeightStuds * (1 - (1 - u) ^ 2)
		local angle = rampAngle(u, R.Seconds, R.SpinStart, R.SpinEnd)
		if phase == "Burst" then
			angle += 2 * math.pi * R.SpinEnd * elapsed
		end
		local shake = R.ShakeStuds * u * u
		local jitter =
			Vector3.new(shiver:NextNumber(-shake, shake), 0, shiver:NextNumber(-shake, shake))
		local centre = target.Position + Vector3.new(0, half + lift, 0) + jitter
		model:PivotTo(
			CFrame.new(centre)
				* target.Rotation
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, -half, 0)
		)
		setGlow(t, 1 + (R.GlowBoost - 1) * u)
		if phase == "Burst" then
			local b = math.clamp(elapsed / L.BurstSeconds, 0, 1)
			if not t.burstPuffed then
				t.burstPuffed = true
				for _, g in t.glows do
					if g.object:IsA("ParticleEmitter") then
						(g.object :: ParticleEmitter):Emit(12)
					end
				end
			end
			local grow = 1 + (L.BurstScale - 1) * b
			model:ScaleTo(t.scale * grow)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = b
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- The countdown over a held block
---------------------------------------------------------------------------------------------

local function watchHeld(model: Instance)
	if not model:IsA("Model") or model.Name ~= "LuckyHeld" or timers[model] then
		return
	end
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local parentGui = playerGui()
	if part == nil or parentGui == nil then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "LuckyTimer"
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	gui.Size = UDim2.fromOffset(140, U.BillboardTimerPx + 10)
	gui.StudsOffsetWorldSpace = Vector3.new(0, L.Held.TimerLiftStuds, 0)
	gui.Enabled = false
	local label = HudParts.text(gui, "Time", U.BillboardTimerPx, "")
	label.AutoLocalize = false
	label.Size = UDim2.fromScale(1, 1)
	label.TextWrapped = false
	gui.Parent = parentGui
	timers[model] = { model = model, gui = gui, label = label }
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			local timer = timers[model]
			timers[model] = nil
			if timer then
				timer.gui:Destroy()
			end
		end
	end)
end

local function stepTimer(timer: Timer, now: number)
	local readyAt = timer.model:GetAttribute("ReadyAt")
	local left = if type(readyAt) == "number" then readyAt - now else 0
	if left > 0 then
		timer.label.Text = LuckyBlocks.clockText(left)
		timer.gui.Enabled = true
	else
		timer.gui.Enabled = false
	end
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

--- The open was refused (too far, too fast...): the prompt may show again.
function World.allowPrompt(id: number)
	for model, t in tracked do
		if model:GetAttribute("BlockId") == id and model:GetAttribute("Owner") == myId() then
			t.asked = false
			if t.prompt then
				t.prompt.Enabled = true
			end
		end
	end
end

--- My block on the floor (its id), or nil.
function World.myLiveIds(): { [number]: boolean }
	local ids: { [number]: boolean } = {}
	local me = myId()
	for model in tracked do
		if model:GetAttribute("Owner") == me then
			local id = model:GetAttribute("BlockId")
			if type(id) == "number" then
				ids[id] = true
			end
		end
	end
	return ids
end

function World.start(opts: Options)
	if started then
		return
	end
	started = true
	options = opts
	task.spawn(function()
		local folder = workspace:WaitForChild(L.LiveFolder, 60)
		if folder == nil then
			return
		end
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				track(child)
			end
		end
		folder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				track(child)
			end
		end)
	end)
	for _, d in workspace:GetDescendants() do
		if d.Name == "LuckyHeld" then
			watchHeld(d)
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		if d.Name == "LuckyHeld" then
			watchHeld(d)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local now = serverNow()
		for _, t in tracked do
			local ok, err = pcall(function(): any
				step(t, now)
				return nil
			end)
			if not ok then
				warn("[8ball] LuckyWorld: " .. tostring(err))
			end
		end
		for _, timer in timers do
			stepTimer(timer, now)
		end
	end)
end

return World
