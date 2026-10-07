--!strict
-- ResultCutscene: the 1v1 match result (GUI lane, designer 2026-10-03, C11a, D2; redone by the
-- designer 2026-10-07). For a 1v1 (a person, a disguised bot or a PC robot, at a lobby table
-- or in an arena), before the result screen:
--   * black letterbox bars slide in (like the Legendary pull's) as the screen fades to black;
--   * the screen fades back in and the camera comes down from high above into the player's
--     own camera (Roblox's, which keeps running underneath, so the hand-back is seamless);
--   * partway down, the result screen opens (centred) and the bars slide away off the
--     screen's edges. When the result screen closes, it all goes back (stop).
-- Not for 2v2, 3v3 or Solo, a draw, or when a player left or forfeited (the plain result
-- screen). Once seen (Seen "Result"), a tap, click or A skips the pan. A match starting stops
-- it (Progression). Numbers in Config.Cutscenes.Result.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local Seen = require(script.Parent.Seen)

local R = Config.Cutscenes.Result
-- Around Roblox's camera script: before it, its own last pose goes back; after it, the pan.
local RENDER_BEFORE = "ResultCutsceneRestore"
local RENDER_AFTER = "ResultCutscene"
local SEEN_KIND = "Result"
-- Results that end a match without a real finish at the table: the plain screen.
local NO_SCENE: { [string]: boolean } = {
	Surrender = true,
	EmptyTeam = true,
	surrender = true,
	empty_team = true,
}

local ResultCutscene = {}

type Scene = {
	gui: ScreenGui,
	black: Frame,
	bars: { Frame },
	hint: TextLabel?,
	connections: { RBXScriptConnection },
	started: number?, -- os.clock when the pan began
	own: CFrame?, -- the player's own camera, as Roblox's script last left it
	skipped: boolean,
	done: boolean, -- the result screen has been asked for
}

local scene: Scene? = nil

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The local player's humanoid and the point the pan looks at (their head).
local function myBody(): (Humanoid?, Vector3?)
	local me = Players.LocalPlayer
	local character = me and me.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return nil, nil
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return humanoid, head.Position
	end
	return humanoid, character:GetPivot().Position
end

local function stopPan()
	RunService:UnbindFromRenderStep(RENDER_BEFORE)
	RunService:UnbindFromRenderStep(RENDER_AFTER)
end

local function restore(s: Scene)
	stopPan()
	for _, c in s.connections do
		c:Disconnect()
	end
	table.clear(s.connections)
	s.gui:Destroy()
	-- Back to the player's own camera (never a frozen Scriptable one).
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local humanoid = myBody()
	if humanoid then
		cam.CameraSubject = humanoid
	end
end

--- Whether this summary gets the cutscene: a 1v1 that ended at the table with a winner, and
--- the player's own body here. /result's preview gets it too.
function ResultCutscene.wants(summary: any): boolean
	if type(summary) ~= "table" or summary.solo == true then
		return false
	end
	if summary.winner ~= 1 and summary.winner ~= 2 then
		return false
	end
	if NO_SCENE[tostring(summary.reason)] then
		return false
	end
	if type(summary.you) == "table" and summary.you.forfeited == true then
		return false
	end
	local teams = summary.teams
	if type(teams) ~= "table" or type(teams[1]) ~= "table" or type(teams[2]) ~= "table" then
		return false
	end
	if #teams[1] ~= 1 or #teams[2] ~= 1 then
		return false
	end
	for _, team in teams do
		local seat = team[1]
		if type(seat) ~= "table" or seat.left == true or type(seat.userId) ~= "number" then
			return false
		end
	end
	return myBody() ~= nil
end

--- Play it for `summary` (ResultCutscene.wants said yes). `onReady` runs partway down the
--- pan (the result screen opens then). False when it could not be set up (then nothing
--- changed and the caller shows the result screen at once).
function ResultCutscene.play(summary: any, onReady: () -> ()): boolean
	ResultCutscene.stop()
	if not ResultCutscene.wants(summary) then
		return false
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ResultCutscene"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = Config.Cutscenes.DisplayOrder
	local black = Instance.new("Frame")
	black.Name = "Black"
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Size = UDim2.fromScale(1, 1)
	black.Parent = gui
	-- The letterbox bars, top and bottom: they slide in with the fade.
	local bars = {}
	for i, edge in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.ZIndex = 2
		bar.AnchorPoint = Vector2.new(0, edge)
		bar.Position = UDim2.fromScale(0, edge)
		bar.Size = UDim2.fromScale(1, 0)
		bar.Parent = gui
		bars[i] = bar
	end
	local me = Players.LocalPlayer
	gui.Parent = me and me:FindFirstChildOfClass("PlayerGui")

	local s: Scene = {
		gui = gui,
		black = black,
		bars = bars,
		hint = nil,
		connections = {},
		started = nil,
		own = nil,
		skipped = false,
		done = false,
	}
	scene = s

	-- The skip hint (only once this kind was seen).
	if Seen.get(SEEN_KIND) then
		local W = Strings.Reel
		local text = if UserInputService.GamepadEnabled
				and string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
			then W.SkipPad
			elseif UserInputService.TouchEnabled then W.SkipTouch
			else W.SkipMouse
		local hint = HudParts.text(gui, "Hint", 22, text)
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -24)
		hint.Size = UDim2.fromOffset(320, 30)
		hint.ZIndex = 3
		hint.Visible = false
		s.hint = hint
		table.insert(
			s.connections,
			UserInputService.InputBegan:Connect(function(input: InputObject)
				local kind = input.UserInputType
				if
					kind == Enum.UserInputType.MouseButton1
					or kind == Enum.UserInputType.Touch
					or input.KeyCode == Enum.KeyCode.ButtonA
				then
					s.skipped = true
				end
			end)
		)
	end

	-- The result screen opens and the bars slide away.
	local function ready()
		if s.done or scene ~= s then
			return
		end
		s.done = true
		if s.hint then
			s.hint.Visible = false
		end
		-- Each shrinks back into its own edge (anchored there), the way it came in.
		for _, bar in s.bars do
			TweenService:Create(
				bar,
				TweenInfo.new(R.BarsOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.fromScale(1, 0) }
			):Play()
		end
		Seen.mark(SEEN_KIND)
		task.spawn(onReady)
	end

	-- Roblox's camera keeps running underneath: its own pose goes back before it runs, and
	-- after it the view is blended from high above into that pose.
	RunService:BindToRenderStep(RENDER_BEFORE, Enum.RenderPriority.Camera.Value - 2, function()
		if s.own then
			workspace.CurrentCamera.CFrame = s.own
		end
	end)
	RunService:BindToRenderStep(RENDER_AFTER, Enum.RenderPriority.Camera.Value + 10, function()
		local started = s.started
		local _, focus = myBody()
		if started == nil or focus == nil then
			return
		end
		local cam = workspace.CurrentCamera
		local own = cam.CFrame
		s.own = own
		local t = if s.skipped then 1 else (os.clock() - started) / R.PanSeconds
		if t >= R.ResultsAtShare then
			ready()
		end
		if t >= 1 then
			-- Down: the camera is simply the player's own again.
			s.own = nil
			stopPan()
			return
		end
		local from = CFrame.lookAt(own.Position + Vector3.yAxis * R.RiseStuds, focus)
		cam.CFrame = from:Lerp(own, smooth(t))
	end)

	task.spawn(function()
		TweenService:Create(black, TweenInfo.new(R.FadeInSeconds), { BackgroundTransparency = 0 })
			:Play()
		for _, bar in bars do
			TweenService:Create(
				bar,
				TweenInfo.new(R.FadeInSeconds, Enum.EasingStyle.Quad),
				{ Size = UDim2.fromScale(1, R.BarsShare) }
			):Play()
		end
		task.wait(R.FadeInSeconds)
		if scene ~= s then
			return
		end
		-- Under the black: the player's own camera, following them (the match's is gone).
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Custom
		local humanoid = myBody()
		if humanoid then
			cam.CameraSubject = humanoid
		end
		task.wait(R.HoldSeconds)
		if scene ~= s then
			return
		end
		s.started = os.clock()
		TweenService:Create(black, TweenInfo.new(R.FadeOutSeconds), { BackgroundTransparency = 1 })
			:Play()
		local hint = s.hint
		if hint then
			task.delay(Config.Cutscenes.HintAfterSeconds, function()
				if scene == s and not s.done then
					hint.Visible = true
				end
			end)
		end
	end)
	return true
end

--- Whether a cutscene is up (from the fade until stop).
function ResultCutscene.isPlaying(): boolean
	return scene ~= nil
end

--- Put everything back (the result screen closed, a match started). Safe to call twice.
function ResultCutscene.stop()
	local s = scene
	if not s then
		return
	end
	scene = nil
	restore(s)
end

return ResultCutscene
