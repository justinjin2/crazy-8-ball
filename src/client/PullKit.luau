--!strict
-- PullKit: the pieces every pull cutscene shares (PullCutscene's Rare to Legendary, PullMythic,
-- PullSecret): the scene's record of everything it changed (so it all goes back), screen layers
-- on the veil, ghost parts and glowing emitters in the world, the camera kept short of walls,
-- the letterbox bars, the world's sounds muted, and the real 3D cue floating in a scene.
-- Visual only. Tuning in Config.Cutscenes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local CueAssets = require(script.Parent.CueAssets)
local CueSkinLook = require(script.Parent.CueSkinLook)
local Letterbox = require(script.Parent.Letterbox)
local UISound = require(script.Parent.UISound)

local CS = Config.Cutscenes
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local PullKit = {}

PullKit.WHITE = WHITE
PullKit.BLACK = BLACK

-- One playing cutscene: its screens, what it changed and its own pieces.
export type Scene = {
	rarity: string,
	cueId: string,
	clock: number,
	ended: boolean,
	done: (() -> ())?,
	skippable: boolean,
	gui: ScreenGui,
	root: Frame,
	skip: TextButton,
	hint: TextLabel,
	veil: ScreenGui, -- over every other screen: the black, and a redone scene's own layers
	veilRoot: Frame,
	black: Frame,
	white: Frame,
	onBlack: (() -> ())?, -- runs once the screen is fully black
	cc: ColorCorrectionEffect,
	model: Model,
	release: () -> (),
	held: { [string]: any }?, -- the player's Humanoid as it was, while it stands still
	camera: { [string]: any }?,
	lighting: { [string]: any },
	atmosphere: { [string]: any }?,
	sky: Sky?, -- the map's own sky, taken out while ours shows
	ourSky: Sky?,
	lights: { { light: Light, enabled: boolean } },
	sounds: { { sound: Sound, volume: number } },
	saved: { { inst: Instance, values: { [string]: any } } }, -- held values, put back in reverse
	cleanup: { () -> () }, -- run once when the scene ends (a cue's look, a sound's speed)
	parts: { [string]: any }, -- this rarity's own pieces (streaks, beam, aurora...)
	fired: { [string]: boolean },
	random: Random,
	connections: { RBXScriptConnection },
}

--------------------------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------------------------

function PullKit.rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

function PullKit.smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

--- 0 -> 1 -> 0 over [from, from + seconds] with `edge` seconds of fade each side.
function PullKit.window(t: number, from: number, seconds: number, edge: number): number
	if t < from or t > from + seconds then
		return 0
	end
	local inside = math.min(t - from, from + seconds - t)
	return math.clamp(inside / math.max(edge, 1e-3), 0, 1)
end

--- 0..1 eased (smoothstep) between `from` and `to` seconds.
function PullKit.between(t: number, from: number, to: number): number
	return PullKit.smooth((t - from) / math.max(to - from, 1e-3))
end

--- A NumberSequence point, with `envelope` (the random spread either side) when given.
function PullKit.key(at: number, value: number, envelope: number?): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(at, value, envelope or 0)
end

--- A colour from a palette of `colours` at `t` seconds, cycling once every `seconds`.
function PullKit.cycle(colours: { Color3 }, t: number, seconds: number): Color3
	local n = #colours
	local x = (t / math.max(seconds, 1e-3)) % 1 * n
	local i = math.floor(x)
	return colours[i % n + 1]:Lerp(colours[(i + 1) % n + 1], x - i)
end

--------------------------------------------------------------------------------------------
-- The player
--------------------------------------------------------------------------------------------

--- The local player's root part and the point between their feet (nil while they have none).
function PullKit.character(): (BasePart?, Vector3?)
	local player = Players.LocalPlayer
	local body = player and player.Character
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local humanoid = body and body:FindFirstChildOfClass("Humanoid")
		local hip = if humanoid then humanoid.HipHeight else 2
		return root, root.Position - Vector3.new(0, hip + root.Size.Y / 2, 0)
	end
	return nil, nil
end

--------------------------------------------------------------------------------------------
-- Held values: anything a scene changes outside its own pieces goes back when it ends
--------------------------------------------------------------------------------------------

--- Take the camera for the scene (once): how it was is noted, so the end puts it back.
function PullKit.takeCamera(s: Scene)
	if s.camera then
		return
	end
	local cam = workspace.CurrentCamera
	s.camera = {
		kind = cam.CameraType,
		subject = cam.CameraSubject,
		cframe = cam.CFrame,
		focus = cam.Focus,
		fov = cam.FieldOfView,
	}
	cam.CameraType = Enum.CameraType.Scriptable
end

--- Save `inst`'s `props` (once per instance and property) so the scene's end puts them back.
function PullKit.hold(s: Scene, inst: Instance?, props: { string })
	if inst == nil then
		return
	end
	local entry: { inst: Instance, values: { [string]: any } }? = nil
	for _, e in s.saved do
		if e.inst == inst then
			entry = e
			break
		end
	end
	if entry == nil then
		entry = { inst = inst, values = {} }
		table.insert(s.saved, entry :: any)
	end
	local values = (entry :: any).values
	for _, prop in props do
		if values[prop] == nil then
			values[prop] = (inst :: any)[prop]
		end
	end
end

--- Put every held value back (the last held first). Safe to call twice.
function PullKit.putBack(s: Scene)
	for i = #s.saved, 1, -1 do
		local entry = s.saved[i]
		if entry.inst.Parent ~= nil or entry.inst:IsA("Sky") then
			for prop, value in entry.values do
				pcall(function()
					(entry.inst :: any)[prop] = value
				end)
			end
		end
	end
	table.clear(s.saved)
	local cleanup = s.cleanup
	s.cleanup = {}
	for _, fn in cleanup do
		local ok, err = pcall(fn :: any)
		if not ok then
			warn("[8ball] PullKit cleanup: " .. tostring(err))
		end
	end
end

--------------------------------------------------------------------------------------------
-- Screen layers on the veil
--------------------------------------------------------------------------------------------

function PullKit.fullFrame(parent: Instance, name: string, colour: Color3, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = colour
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end

--- A round soft glow on the veil, centred (the kit's SoftGlow image; a plain circle without it).
function PullKit.makeGlow(s: Scene, name: string, colour: Color3, z: number): GuiObject
	local art: string = Config.UI.Kit.Art.SoftGlow
	local glow: GuiObject
	if art ~= "" then
		local image = Instance.new("ImageLabel")
		image.Image = art
		image.ImageColor3 = colour
		image.BackgroundTransparency = 1
		glow = image
	else
		local circle = Instance.new("Frame")
		circle.BackgroundColor3 = colour
		circle.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = circle
		glow = circle
	end
	glow.Name = name
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromOffset(0, 0)
	glow.ZIndex = z
	glow.Visible = false
	glow.Parent = s.veilRoot
	return glow
end

--- A tinted piece of white art on the veil, centred and hidden until it is placed.
function PullKit.makeArt(s: Scene, name: string, art: string, colour: Color3, z: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.Image = art
	image.ImageColor3 = colour
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromOffset(0, 0)
	image.ZIndex = z
	image.Visible = false
	image.Parent = s.veilRoot
	return image
end

--- The letterbox bars, top and bottom, `share` of the screen's height each (Letterbox keeps
--- them over the HUD's rows), hidden until setBars.
function PullKit.bars(s: Scene, share: number, z: number): { Frame }
	local bars = {}
	for i, edge in { 0, 1 } do
		local bar = PullKit.fullFrame(s.veilRoot, "Bar", BLACK, z)
		bar.BackgroundTransparency = 0
		bar.AnchorPoint = Vector2.new(0, edge)
		bar.Position = UDim2.fromScale(0, edge)
		bar.Size = UDim2.fromScale(1, 0)
		bars[i] = bar
	end
	s.parts.bars = bars
	s.parts.barPx = Letterbox.px(share)
	return bars
end

--- The bars at `k` of their height (0 gone, 1 in).
function PullKit.setBars(s: Scene, k: number)
	local px = (s.parts.barPx or 0) * math.clamp(k, 0, 1)
	for _, bar: Frame in s.parts.bars or {} do
		bar.Size = UDim2.new(1, 0, 0, px)
	end
end

--------------------------------------------------------------------------------------------
-- World pieces (all in the scene's own model)
--------------------------------------------------------------------------------------------

function PullKit.ghostPart(s: Scene, name: string, size: Vector3, at: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = CFrame.new(at)
	part.Parent = s.model
	return part
end

--- A glowing particle emitter that emits nothing until it is told to.
function PullKit.emitter(
	parent: Instance,
	name: string,
	art: string,
	a: Color3,
	b: Color3
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = art
	e.Color = ColorSequence.new(a, b)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 0
	e.Speed = NumberRange.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = parent
	return e
end

--- A flat piece of art lying on the ground at `at` (the scene's feet when not given).
function PullKit.groundArt(
	s: Scene,
	name: string,
	art: string,
	colour: Color3,
	at: Vector3?
): (Part, Decal)
	local part = PullKit.ghostPart(s, name, Vector3.new(1, 0.05, 1), at or s.parts.feet)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = art
	decal.Color3 = colour
	decal.Transparency = 1
	decal.Parent = part
	return part, decal
end

--- A flat piece of art lying on the ground at `at`, drawn unlit (a SurfaceGui on its top), so
--- it glows in the dark where a Decal would be lit like the floor; `brightness` over 1 glows
--- into the bloom. Size the part to size the art; the image starts hidden.
function PullKit.glowArt(
	s: Scene,
	name: string,
	art: string,
	colour: Color3,
	at: Vector3,
	brightness: number?
): (Part, ImageLabel)
	local part = PullKit.ghostPart(s, name, Vector3.new(1, 0.05, 1), at)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = brightness or 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.ResetOnSpawn = false
	gui.Adornee = part
	gui.Parent = part
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Image = art
	image.ImageColor3 = colour
	image.ImageTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = gui
	return part, image
end

--- A camera-facing picture in the world, `studs` across (BillboardGui), hidden until shown;
--- `brightness` over 1 makes it glow.
function PullKit.billboard(
	parent: Instance,
	name: string,
	art: string,
	colour: Color3,
	studs: number,
	z: number?,
	brightness: number?
): (BillboardGui, ImageLabel)
	local board = Instance.new("BillboardGui")
	board.Name = name
	board.Size = UDim2.fromScale(studs, studs)
	board.LightInfluence = 0
	board.Brightness = brightness or 1 -- over 1 it glows into the bloom
	board.AlwaysOnTop = false
	board.ResetOnSpawn = false
	board.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	board.MaxDistance = math.huge
	if parent:IsA("BasePart") or parent:IsA("Attachment") then
		board.Adornee = parent
	end
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.Image = art
	image.ImageColor3 = colour
	image.ImageTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(1, 1)
	image.ZIndex = z or 1
	image.Parent = board
	board.Parent = parent
	return board, image
end

--- The ray filter for the camera's clamp: every character and the scene's own model are seen
--- through.
function PullKit.rayParams(s: Scene): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local skip: { Instance } = { s.model }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(skip, other.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	return params
end

--- The camera wants to be at `to`, looking from about `from`: it stops CameraPadStuds short of
--- anything solid in between (a table, a wall), never inside it. Near-invisible parts (zones,
--- triggers) are seen through. Uses s.parts.params (rayParams).
function PullKit.clampEye(s: Scene, from: Vector3, to: Vector3): Vector3
	local params: RaycastParams = s.parts.params
	local pad = CS.Legendary.CameraPadStuds
	local origin = from
	for _ = 1, 6 do
		local offset = to - origin
		if offset.Magnitude < 1e-3 then
			return to
		end
		local hit = workspace:Raycast(origin, offset, params)
		if not hit then
			return to
		end
		local part = hit.Instance
		if part:IsA("BasePart") and part.Transparency > 0.9 then
			params:AddToFilter(part)
		else
			local back = (from - hit.Position)
			local room = math.min(pad, back.Magnitude)
			return hit.Position + (if back.Magnitude > 1e-3 then back.Unit * room else Vector3.zero)
		end
	end
	return to
end

--- A camera shake on top of `frame`: smooth noise moving and rolling it by `amount` studs at
--- `hz`, plus a jolt `kick` studs down.
function PullKit.shake(
	frame: CFrame,
	t: number,
	amount: number,
	kick: number,
	hz: number,
	rollDegrees: number
): CFrame
	if amount <= 0 and kick <= 0 then
		return frame
	end
	local f = t * hz
	return frame
		* CFrame.new(math.noise(f, 1.3) * amount * 2, math.noise(f, 7.1) * amount * 2 - kick, 0)
		* CFrame.Angles(
			math.rad(math.noise(f, 3.7) * amount * 2) - math.rad(kick * 4),
			math.rad(math.noise(f, 5.3) * amount * 2),
			math.rad(math.noise(f, 9.9) * rollDegrees)
		)
end

--------------------------------------------------------------------------------------------
-- The world falling away
--------------------------------------------------------------------------------------------

-- A piece of the map faded out for this player alone (LocalTransparencyModifier, never seen
-- by anyone else), `at` 0..1 its turn in the dissolve (the farthest first).
type Faded = { inst: Instance, from: number, at: number, step: number }

-- A sign, light or effect put out: its property, the value it had and the one it is held at.
type Out = { inst: Instance, prop: string, from: any, value: any }

local INVISIBLE = NumberSequence.new(1)

-- How each kind is put out so it stays out while its own script keeps switching it on (the
-- queue pads turn their JOIN arrows, rings and portal sparks on every frame): switched off,
-- and hidden by properties such a script leaves alone (hidden from this player, out of sight,
-- see-through, reaching nothing). Never switched off again each frame: a sign flipped on and
-- off every frame skips its distance check and shows (docs/STUDIO_NOTES.md).
local function outRule(d: Instance): { [string]: any }?
	if d:IsA("BillboardGui") then
		return { Enabled = false, MaxDistance = 1e-3, PlayerToHideFrom = Players.LocalPlayer }
	elseif d:IsA("SurfaceGui") then
		return { Enabled = false, MaxDistance = 1e-3 }
	elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
		return { Enabled = false, Transparency = INVISIBLE }
	elseif d:IsA("Light") then
		return { Enabled = false, Range = 0 }
	elseif d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
		return { Enabled = false }
	end
	return nil
end

--- Everything standing above the ground within `radius` studs of `feet` (the map's trees,
--- walls, signs, tables, other players) is noted to fade away for this player alone, so the
--- scene's shots see only the player, the bare ground they stand on and the sky. Its decals
--- fade with it; the signs, lights and effects on it and on the ground go out now (the screen
--- is black). PullKit.fadeWorld runs the dissolve; the scene's end puts it all back.
function PullKit.clearWorld(s: Scene, feet: Vector3, radius: number, groundStuds: number)
	local me = Players.LocalPlayer and Players.LocalPlayer.Character
	local faded: { Faded } = {}
	local hidden: { [Instance]: boolean } = {}
	local ground: { [Instance]: boolean } = {}
	local outs: { Out } = {}
	local done: { [Instance]: boolean } = {}
	local function putOut(d: Instance)
		local rule = outRule(d)
		if not rule or done[d] then
			return
		end
		done[d] = true
		for prop, value in rule do
			local ok, from = pcall(function()
				return (d :: any)[prop]
			end)
			if ok and from ~= value then
				table.insert(outs, { inst = d, prop = prop, from = from, value = value })
				pcall(function()
					(d :: any)[prop] = value
				end)
			end
		end
	end
	-- Every part, not a spatial query: decoration is often left out of queries (CanQuery off).
	for _, part in workspace:GetDescendants() do
		if
			not part:IsA("BasePart")
			or part:IsA("Terrain")
			or part:IsDescendantOf(s.model)
			or (me ~= nil and part:IsDescendantOf(me))
		then
			continue
		end
		local flat = Vector3.new(part.Position.X, feet.Y, part.Position.Z)
		local reach = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2
		if (flat - feet).Magnitude - reach > radius then
			continue
		end
		-- Its top: the part's highest corner (turned parts too).
		local r = part.CFrame
		local size = part.Size
		local up = math.abs(r.RightVector.Y) * size.X
			+ math.abs(r.UpVector.Y) * size.Y
			+ math.abs(r.LookVector.Y) * size.Z
		local top = part.Position.Y + up / 2
		if top <= feet.Y + groundStuds then
			-- The ground (and anything lying flat in it) stays, bare: what is drawn on it,
			-- floats over it or glows from it (a pad's count, a marker, a lamp, sparkles) goes.
			ground[part] = true
			for _, d in part:GetDescendants() do
				putOut(d)
			end
			continue
		end
		local distance = (flat - feet).Magnitude
		hidden[part] = true
		-- (an invisible part only carries signs and lights: those go below)
		if part.Transparency < 0.99 then
			table.insert(faded, {
				inst = part,
				from = part.LocalTransparencyModifier,
				at = 1 - math.clamp(distance / radius, 0, 1),
				step = 0,
			})
		end
		for _, d in part:GetDescendants() do
			if d:IsA("Decal") then
				table.insert(faded, {
					inst = d,
					from = d.LocalTransparencyModifier,
					at = 1 - math.clamp(distance / radius, 0, 1),
					step = 0,
				})
			else
				putOut(d)
			end
		end
	end
	-- Signs drawn on those parts from elsewhere (a SurfaceGui or BillboardGui adorned to them).
	local player = Players.LocalPlayer
	local holders: { Instance } = { workspace }
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		table.insert(holders, playerGui)
	end
	for _, holder in holders do
		for _, d in holder:GetDescendants() do
			if d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
				local adornee = d.Adornee
				local on = adornee
					and (if adornee:IsA("Attachment") then adornee.Parent else adornee)
				if on and (hidden[on] or ground[on]) then
					putOut(d)
				end
			end
		end
	end
	s.parts.faded = faded
	s.parts.outs = outs
	table.insert(s.cleanup, function()
		for _, f in faded do
			pcall(function()
				(f.inst :: any).LocalTransparencyModifier = f.from
			end)
		end
		for i = #outs, 1, -1 do
			local o = outs[i]
			pcall(function()
				(o.inst :: any)[o.prop] = o.from
			end)
		end
	end)
end

--- The dissolve at `k` (0 none, 1 all gone): each piece fades in four steps over the last
--- `share` of the run once its turn comes (the farthest first), so few change in any frame.
function PullKit.fadeWorld(s: Scene, k: number, share: number)
	local faded: { Faded }? = s.parts.faded
	if not faded then
		return
	end
	local lead = 1 - share
	for _, f in faded do
		local u = math.clamp((k - f.at * lead) / math.max(share, 1e-3), 0, 1)
		local step = math.floor(u * 4 + 1e-6)
		if step ~= f.step then
			f.step = step
			local inst = f.inst :: any
			inst.LocalTransparencyModifier = f.from + (1 - f.from) * step / 4
		end
	end
end

--------------------------------------------------------------------------------------------
-- Sounds
--------------------------------------------------------------------------------------------

--- Note every sound playing in the world and the interface (to fade them out and put them
--- back): the map's ambience, the music, the reel's last ticks.
function PullKit.collectSounds(s: Scene)
	if #s.sounds > 0 then
		return
	end
	for _, holder in { workspace, SoundService } :: { Instance } do
		for _, sound in holder:GetDescendants() do
			if sound:IsA("Sound") and sound.IsPlaying and sound.Volume > 0 then
				table.insert(s.sounds, { sound = sound, volume = sound.Volume })
			end
		end
	end
end

--- Leave the scene's own sounds (Config.Audio.Ui `keys`) out of the noted ones: one still
--- playing from an earlier pull (a card's ambience) is the scene's to play, not to mute.
function PullKit.spareSounds(s: Scene, keys: { string })
	local own: { [Sound]: boolean } = {}
	for _, k in keys do
		local sound = UISound.sound(k)
		if sound then
			own[sound] = true
		end
	end
	for i = #s.sounds, 1, -1 do
		if own[s.sounds[i].sound] then
			table.remove(s.sounds, i)
		end
	end
end

--- The noted sounds at `share` of their volume (0 silent, 1 as they were).
function PullKit.quietSounds(s: Scene, share: number)
	for _, entry in s.sounds do
		if entry.sound.Parent then
			entry.sound.Volume = entry.volume * math.clamp(share, 0, 1)
		end
	end
end

--------------------------------------------------------------------------------------------
-- The real cue, floating in a scene
--------------------------------------------------------------------------------------------

export type ShownCue = {
	model: Model,
	look: any,
}

--- The pulled cue as itself (its mesh, surface, aura and 3D piece), floating with its tip at
--- `tip`'s position and the stick running along `tip`'s +Z (CueStickBuilder's frame), or nil
--- when its look is not loaded yet (CueAssets): never a grey or half-textured cue. It goes
--- with the scene.
function PullKit.showCue(s: Scene, cueId: string, tip: CFrame): ShownCue?
	if not CueAssets.ready(cueId) then
		return nil
	end
	local stick = CueStickBuilder.build(s.model, cueId)
	stick.Name = "PulledCue"
	if stick:GetAttribute("CueId") ~= cueId then
		stick:Destroy() -- it would wait for its look: not a cue to show now
		return nil
	end
	CueStickBuilder.setVisible(stick, true)
	stick:PivotTo(tip)
	local look = CueSkinLook.attach(stick, { aura = true })
	table.insert(s.cleanup, function()
		look:destroy()
	end)
	return { model = stick, look = look }
end

--- Place a shown cue: its tip at `tip`, the stick down its +Z.
function PullKit.placeCue(cue: ShownCue?, tip: CFrame)
	if cue and cue.model.Parent then
		cue.model:PivotTo(tip)
	end
end

--- The tip frame of a cue standing upright, its middle at `middle`, turned `angle` radians
--- about its own length: the tip up, the butt down.
function PullKit.uprightTip(middle: Vector3, angle: number): CFrame
	local half = Config.Cue.CueLengthStuds / 2
	local tip = middle + Vector3.new(0, half, 0)
	-- lookAt points -Z at the target: aimed up, +Z runs down the stick to the butt.
	return CFrame.lookAt(tip, tip + Vector3.yAxis, Vector3.zAxis) * CFrame.Angles(0, 0, angle)
end

return PullKit
