--!strict
-- ResultCutscene: the 1v1 match result (GUI lane, designer 2026-10-03, C11a, D2; reference
-- ~/Desktop/8ball-refs/gui/11-match-result-winner-loser.webp). For a 1v1 (a person, a
-- disguised bot or a PC robot, at a lobby table or in an arena), before the result screen:
--   * the screen fades to black;
--   * beside the table, the winner stands holding their cue upright with the other arm up, and
--     the loser lies face down with their cue dropped beside them. Both are local copies of the
--     real bodies (the real ones and their back cues are hidden meanwhile), so nobody else
--     sees anything and nothing moves on the server;
--   * the screen fades back in and the camera comes down onto the two of them, then the result
--     screen opens in the top part of the screen (ResultScreen.setLifted) with both in view
--     below it. When the result screen closes, everything goes back (stop).
-- Not for 2v2, 3v3 or Solo, a draw, or when a player left or forfeited (the plain result
-- screen). Once seen (Seen "Result"), a tap, click or A skips the pan. A match starting stops
-- it (Progression). Numbers in Config.Cutscenes.Result.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvatarPose = require(Shared:WaitForChild("AvatarPose"))
local Config = require(Shared:WaitForChild("Config"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local Placement = require(Shared:WaitForChild("Placement"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local People = require(script.Parent.People)
local Seen = require(script.Parent.Seen)

local R = Config.Cutscenes.Result
local RENDER_NAME = "ResultCutscene"
local SEEN_KIND = "Result"
-- Results that end a match without a real finish at the table: the plain screen.
local NO_SCENE: { [string]: boolean } = {
	Surrender = true,
	EmptyTeam = true,
	surrender = true,
	empty_team = true,
}

local ResultCutscene = {}

type Hidden = { object: Instance, key: string, value: any }

type Scene = {
	gui: ScreenGui,
	black: Frame,
	hint: TextLabel?,
	folder: Folder,
	hidden: { Hidden },
	connections: { RBXScriptConnection },
	ids: { [number]: boolean },
	from: CFrame,
	to: CFrame,
	started: number?, -- os.clock when the pan began
	skipped: boolean,
	done: boolean,
}

local scene: Scene? = nil

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The body of a seat: a player's character or a bot's model.
local function bodyOf(userId: number): (Model?, any)
	local owner = People.owner(userId)
	local character = owner and owner.Character
	if typeof(character) == "Instance" and character:IsA("Model") and character.Parent then
		return character, owner
	end
	return nil, nil
end

--- Whether this summary gets the cutscene: a 1v1 that ended at the table with a winner,
--- both bodies here and a known table.
function ResultCutscene.wants(summary: any): boolean
	if type(summary) ~= "table" or summary.solo == true or summary.preview == true then
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
		if bodyOf(seat.userId) == nil then
			return false
		end
	end
	return type(summary.tableId) == "number" and Placement.forTable(summary.tableId) ~= nil
end

local function hide(s: Scene, object: Instance, key: string, value: any)
	table.insert(s.hidden, { object = object, key = key, value = (object :: any)[key] })
	pcall(function()
		(object :: any)[key] = value
	end)
end

-- Hide a real body and the cue on its back (only on this screen).
local function hideBody(s: Scene, character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			hide(s, d, "LocalTransparencyModifier", 1)
		elseif d:IsA("BillboardGui") then
			hide(s, d, "Enabled", false)
		end
	end
	local backs = workspace:FindFirstChild("BackCues")
	if not backs then
		return
	end
	for _, stick in backs:GetChildren() do
		local carried = false
		for _, d in stick:GetDescendants() do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				local a, b = (d :: any).Part0, (d :: any).Part1
				if (a and a:IsDescendantOf(character)) or (b and b:IsDescendantOf(character)) then
					carried = true
					break
				end
			end
		end
		if not carried then
			for _, d in character:GetDescendants() do
				if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
					local a, b = (d :: any).Part0, (d :: any).Part1
					if (a and a:IsDescendantOf(stick)) or (b and b:IsDescendantOf(stick)) then
						carried = true
						break
					end
				end
			end
		end
		if carried then
			for _, d in stick:GetDescendants() do
				if d:IsA("BasePart") then
					hide(s, d, "LocalTransparencyModifier", 1)
				elseif
					d:IsA("ParticleEmitter")
					or d:IsA("Beam")
					or d:IsA("Trail")
					or d:IsA("Light")
				then
					hide(s, d, "Enabled", false)
				end
			end
		end
	end
end

-- A still copy of a body: no scripts, no name tags, no physics; only its root anchored, so
-- the joints hold the rest to it.
local function copyBody(character: Model, parent: Instance): (Model?, BasePart?)
	local was = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(function(): Instance
		return character:Clone()
	end)
	character.Archivable = was
	if not ok or typeof(copy) ~= "Instance" or not (copy :: Instance):IsA("Model") then
		return nil, nil
	end
	local model = copy :: Model
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		elseif d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint") then
			(d :: any).Enabled = false -- ragdoll limits: the pose turns past them
		elseif d:IsA("AnimationConstraint") then
			d.IsKinematic = true -- held exactly where the pose puts it
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not (root and root:IsA("BasePart")) then
		model:Destroy()
		return nil, nil
	end
	root.Anchored = true
	model.Name = "ResultCutsceneBody"
	model.Parent = parent
	return model, root
end

-- Turn a shoulder forward by `degrees`. R15 swings an arm about its joint's X: a Motor6D's C0,
-- or (Roblox's newer avatar joints) the AnimationConstraint's torso-side attachment. R6 swings
-- about its Motor6D's Z.
local function swing(model: Model, side: "Right" | "Left", degrees: number)
	local turn = CFrame.Angles(math.rad(degrees), 0, 0)
	for _, d in model:GetDescendants() do
		if d.Name == side .. "Shoulder" then
			if d:IsA("Motor6D") then
				d.C0 = d.C0 * turn
			elseif d:IsA("AnimationConstraint") then
				local a0 = d.Attachment0
				if a0 then
					a0.CFrame = a0.CFrame * turn
				end
			end
		elseif d.Name == side .. " Shoulder" and d:IsA("Motor6D") then
			local sign = if side == "Right" then 1 else -1
			d.C0 = d.C0 * CFrame.Angles(0, 0, sign * math.rad(degrees))
		end
	end
end

local function standHeight(character: Model, root: BasePart): number
	local ok, height = pcall(AvatarPose.standHeight, character)
	if ok and type(height) == "number" and height > 0 then
		return height
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 0
	return if hip > 0 then hip + root.Size.Y / 2 else 3
end

local function cueOf(owner: any): string
	local ok, id = pcall(CueStickBuilder.equippedCue, owner)
	return if ok and type(id) == "string" then id else CueStickBuilder.equippedCue(nil)
end

local function restore(s: Scene)
	RunService:UnbindFromRenderStep(RENDER_NAME)
	for _, c in s.connections do
		c:Disconnect()
	end
	table.clear(s.connections)
	for i = #s.hidden, 1, -1 do
		local h = s.hidden[i]
		if h.object.Parent then
			pcall(function()
				(h.object :: any)[h.key] = h.value
			end)
		end
	end
	table.clear(s.hidden)
	s.folder:Destroy()
	s.gui:Destroy()
	-- Back to the player's own camera (never a frozen Scriptable one).
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local me = Players.LocalPlayer
	local humanoid = me and me.Character and me.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		cam.CameraSubject = humanoid
	end
end

--- Play it for `summary` (ResultCutscene.wants said yes). `onReady` runs once the camera has
--- come down (the result screen opens then). False when it could not be set up (then
--- nothing changed and the caller shows the result screen at once).
function ResultCutscene.play(summary: any, onReady: () -> ()): boolean
	ResultCutscene.stop()
	if not ResultCutscene.wants(summary) then
		return false
	end
	local p = Placement.forTable(summary.tableId) :: Placement.Placement
	local winnerSeat = summary.teams[summary.winner][1]
	local loserSeat = summary.teams[3 - summary.winner][1]
	local winnerBody, winnerOwner = bodyOf(winnerSeat.userId)
	local loserBody, loserOwner = bodyOf(loserSeat.userId)
	if not winnerBody or not loserBody then
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
	local me = Players.LocalPlayer
	gui.Parent = me and me:FindFirstChildOfClass("PlayerGui")
	local folder = Instance.new("Folder")
	folder.Name = "ResultCutscene"
	folder.Parent = workspace

	local s: Scene = {
		gui = gui,
		black = black,
		hint = nil,
		folder = folder,
		hidden = {},
		connections = {},
		ids = { [winnerSeat.userId] = true, [loserSeat.userId] = true },
		from = CFrame.identity,
		to = CFrame.identity,
		started = nil,
		skipped = false,
		done = false,
	}
	scene = s

	-- Where: beside the table's long side nearest the camera.
	local s2 = Config.Table.StudsPerInch
	local lx, lz = Placement.dirToWorld(p, 1, 0)
	local wx, wz = Placement.dirToWorld(p, 0, 1)
	local along = Vector3.new(lx, 0, lz).Unit
	local across = Vector3.new(wx, 0, wz).Unit
	local centre = Vector3.new(p.x, p.y, p.z)
	local cam = workspace.CurrentCamera
	if (cam.CFrame.Position - centre):Dot(across) < 0 then
		across = -across
	end
	local halfWidth = (Config.Table.WidthInches / 2 + Config.Table.RailWidthInches) * s2
	local up = Vector3.yAxis
	-- Whether the final view of one side is clear: nothing solid between the camera and the
	-- two (bodies, the lobby signs and the cutscene's own parts aside).
	local ignore = RaycastParams.new()
	ignore.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { folder }
	for _, person in People.everyone() do
		if typeof(person.Character) == "Instance" then
			table.insert(skip, person.Character)
		end
	end
	local signs = workspace:FindFirstChild("Leaderboards")
	if signs then
		table.insert(skip, signs)
	end
	ignore.FilterDescendantsInstances = skip
	local function clear(side: Vector3): boolean
		local at = centre + side * (halfWidth + R.SideStuds)
		local from = at + side * R.CameraOutStuds + up * R.CameraUpStuds
		local target = at + up * 2
		return workspace:Raycast(from, target - from, ignore) == nil
	end
	if not clear(across) and clear(-across) then
		across = -across
	end
	local base = centre + across * (halfWidth + R.SideStuds)
	local winnerAt = base - along * (R.GapStuds / 2)
	local loserAt = base + along * (R.GapStuds / 2)
	local look = base + up * R.LookUpStuds
	local camAt = base + across * R.CameraOutStuds + up * R.CameraUpStuds
	s.to = CFrame.lookAt(camAt, look)
	local startAt = camAt + up * R.StartUpStuds - across * R.StartInStuds
	s.from = CFrame.lookAt(startAt, base)

	local function setScene(): boolean
		local winner, winnerRoot = copyBody(winnerBody, folder)
		local loser, loserRoot = copyBody(loserBody, folder)
		if not winner or not winnerRoot or not loser or not loserRoot then
			return false
		end
		hideBody(s, winnerBody)
		hideBody(s, loserBody)
		-- The lobby signs stand by the front tables: never in the way of the view.
		if signs then
			for _, d in signs:GetDescendants() do
				if d:IsA("BasePart") then
					hide(s, d, "LocalTransparencyModifier", 1)
				elseif d:IsA("SurfaceGui") then
					hide(s, d, "Enabled", false)
				end
			end
		end
		-- The winner stands facing out (the camera), cue upright in the hand.
		local rootAt = winnerAt + up * standHeight(winnerBody, winnerRoot)
		winnerRoot.CFrame = CFrame.lookAt(rootAt, rootAt + across)
		swing(winner, "Right", R.HoldDegrees)
		swing(winner, "Left", R.WaveDegrees)
		-- The loser lies face down, head away from the winner, arms past the head.
		local lieAt = loserAt + up * R.LieHeightStuds
		loserRoot.CFrame = CFrame.lookAt(lieAt, lieAt - up, along)
		swing(loser, "Right", R.DiveDegrees)
		swing(loser, "Left", R.DiveDegrees)
		-- The cues: built now, placed once the joints have moved the hands.
		local L = Config.Cue.CueLengthStuds
		local upright = CueStickBuilder.build(folder, cueOf(winnerOwner))
		local dropped = CueStickBuilder.build(folder, cueOf(loserOwner))
		local tilt = CFrame.fromAxisAngle(up, math.rad(R.CueAngleDegrees))
		local lying = tilt:VectorToWorldSpace(along)
		local tip = loserAt + across * R.CueSideStuds + lying * (L / 2) + up * R.CueLiftStuds
		CueStickBuilder.placeAt(dropped, CFrame.lookAt(tip, tip + lying))
		local function placeUpright()
			local hand = winner:FindFirstChild("RightHand") or winner:FindFirstChild("Right Arm")
			local at = if hand and hand:IsA("BasePart")
				then hand.Position
				else rootAt + winnerRoot.CFrame.RightVector * 1.5
			local butt = Vector3.new(at.X, p.y, at.Z)
			local top = butt + up * L
			CueStickBuilder.placeAt(upright, CFrame.lookAt(top, top + up, across))
		end
		placeUpright()
		task.defer(placeUpright)
		task.delay(0.1, placeUpright)
		-- Anyone else standing near (a player or bot walking past) is hidden too, so nobody
		-- steps in front of the camera; looked at again while it plays.
		local cleared: { [Model]: boolean } = { [winnerBody] = true, [loserBody] = true }
		local function clearAround()
			for _, person in People.everyone() do
				local body = person.Character
				if typeof(body) == "Instance" and body:IsA("Model") and not cleared[body] then
					local pivot = body:GetPivot().Position
					if (pivot - base).Magnitude <= R.ClearStuds then
						cleared[body] = true
						hideBody(s, body)
					end
				end
			end
		end
		clearAround()
		task.spawn(function()
			while scene == s do
				task.wait(R.ClearEverySeconds)
				if scene == s then
					clearAround()
				end
			end
		end)
		return true
	end

	-- The skip hint (only once this kind was seen).
	local canSkip = Seen.get(SEEN_KIND)
	if canSkip then
		local W = Strings.CaseOpening
		local text = if UserInputService.GamepadEnabled
				and string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
			then W.SkipPad
			elseif UserInputService.TouchEnabled then W.SkipTouch
			else W.SkipMouse
		local hint = HudParts.text(gui, "Hint", 22, text)
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -24)
		hint.Size = UDim2.fromOffset(320, 30)
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

	local function ready()
		if s.done or scene ~= s then
			return
		end
		s.done = true
		if s.hint then
			s.hint.Visible = false
		end
		Seen.mark(SEEN_KIND)
		task.spawn(onReady)
	end

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 10, function()
		-- The camera is taken only once the scene is set (under the black).
		local started = s.started
		if started == nil then
			return
		end
		local c = workspace.CurrentCamera
		if c.CameraType ~= Enum.CameraType.Scriptable then
			c.CameraType = Enum.CameraType.Scriptable
		end
		local t = if s.skipped then 1 else (os.clock() - started) / R.PanSeconds
		c.CFrame = s.from:Lerp(s.to, smooth(t))
		if t >= 1 then
			ready()
		end
	end)

	task.spawn(function()
		local fadeIn = TweenService:Create(
			black,
			TweenInfo.new(R.FadeInSeconds),
			{ BackgroundTransparency = 0 }
		)
		fadeIn:Play()
		task.wait(R.FadeInSeconds)
		if scene ~= s then
			return
		end
		if not setScene() then
			-- Nothing to show after all: straight to the result screen.
			ResultCutscene.stop()
			task.spawn(onReady)
			return
		end
		s.started = os.clock() + R.HoldSeconds
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

--- The seats in the scene (their nameplates stay hidden), or nil.
function ResultCutscene.hiddenIds(): { [number]: boolean }?
	return if scene then scene.ids else nil
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
