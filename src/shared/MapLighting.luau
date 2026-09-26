--!strict
-- MapLighting: puts a light state (LightCycle.state) onto the place. That means:
--  - Lighting's own values, and its Atmosphere, Sky and post effects;
--  - the Terrain's water;
--  - the props' Neon glass and flames and their PointLights;
--  - the self-lit (emissive) under-table glow and skyline windows.
--
-- Two callers:
--  - MapLighting.preview, in Edit mode. Run it from the command bar or MCP execute_luau, with
--    fresh copies (Edit-mode requires are cached, STUDIO_NOTES):
--      local S = game.ReplicatedStorage.Shared
--      local ML, LC = require(S.MapLighting:Clone()), require(S.LightCycle:Clone())
--      local cfg = require(S.Config:Clone())
--      print(ML.preview(LC.state(1, cfg.Lighting), cfg.Map)) -- 0 Day, 1 Sunset, or between
--    It makes sure the place has one of each effect, then lights the place for captures, so it
--    is saved lit.
--  - DayCycle, on each client. It applies the cycle's state as it changes; that is visual only
--    and local, and it never creates anything.
--
-- The caller passes the state in, so this module requires nothing and a :Clone() of it works.
-- Colours arrive as hex strings (Config.Lighting).

local MapLighting = {}

-- Lighting's children, by the state's block name: the class each is.
local BLOCKS: { [string]: string } = {
	Atmosphere = "Atmosphere",
	Sky = "Sky",
	ColorCorrection = "ColorCorrectionEffect",
	Bloom = "BloomEffect",
	SunRays = "SunRaysEffect",
	DepthOfField = "DepthOfFieldEffect",
}

export type Handles = {
	blocks: { [string]: Instance },
	glows: { [string]: { BasePart } }, -- Map.Props' <Kind>__Glow meshes, by kind
	lights: { PointLight },
	tableGlow: { SurfaceAppearance },
	windows: { SurfaceAppearance },
	complete: boolean, -- false while the map's props, rooftop or backdrop are yet to stream in
}

-- A Luau colour from a hex string; anything else as it is.
local function value(v: any): any
	if type(v) == "string" and v:sub(1, 1) == "#" then
		return Color3.fromHex(v)
	end
	return v
end

-- Whether a part is one of the map's glow, light or emissive pieces, so a client re-collects
-- when one streams in (it would otherwise keep the look it was saved with).
function MapLighting.relevant(inst: Instance): boolean
	if inst:IsA("PointLight") then
		return true
	elseif inst:IsA("SurfaceAppearance") then
		local parent = inst.Parent
		return parent ~= nil
			and (parent.Name == "TableGlow" or parent.Name:match("^Skyline_") ~= nil)
	elseif inst:IsA("BasePart") then
		return inst.Name:match("__Glow$") ~= nil
			or inst.Name == "TableGlow"
			or inst.Name:match("^Skyline_") ~= nil
	end
	return false
end

--- Finds everything a state is written to. spec is Config.Map.
function MapLighting.collect(spec: any): Handles
	local Lighting = game:GetService("Lighting")
	local h: Handles =
		{ blocks = {}, glows = {}, lights = {}, tableGlow = {}, windows = {}, complete = true }
	for name, class in BLOCKS do
		local inst = Lighting:FindFirstChildOfClass(class)
		if inst then
			h.blocks[name] = inst
		end
	end
	local map = workspace:FindFirstChild(spec.Name)
	local props = map and map:FindFirstChild(spec.Props.Placed)
	local rooftop = map and map:FindFirstChild(spec.Architecture)
	local backdrop = map and map:FindFirstChild(spec.Backdrop.Import)
	h.complete = props ~= nil and rooftop ~= nil and backdrop ~= nil
	if props then
		for _, d in props:GetDescendants() do
			if d:IsA("PointLight") then
				table.insert(h.lights, d)
			elseif d:IsA("BasePart") then
				local kind = d.Name:match("^(%a+)__Glow$")
				if kind then
					h.glows[kind] = h.glows[kind] or {}
					table.insert(h.glows[kind], d)
				end
			end
		end
	end
	local glow = rooftop and rooftop:FindFirstChild("TableGlow")
	local glowLook = glow and glow:FindFirstChildOfClass("SurfaceAppearance")
	if glowLook then
		table.insert(h.tableGlow, glowLook)
	end
	if backdrop then
		for _, part in backdrop:GetChildren() do
			local look = part.Name:match("^Skyline_")
				and part:FindFirstChildOfClass("SurfaceAppearance")
			if look then
				table.insert(h.windows, look)
			end
		end
	end
	return h
end

-- Emissive writes are tried once per session; if a LocalScript may not make them, the windows
-- and table glow keep their saved look and the painted sky carries the sunset (a warning says so).
local emissiveBlocked = false

--- Writes a state onto the handles. `last` is what the previous call wrote (by property path),
--- so a hold writes nothing and a fade only what moved; pass nil to write everything (after a
--- fresh collect). Returns the new `last`.
function MapLighting.apply(
	state: { [string]: any },
	h: Handles,
	last: { [string]: any }?
): { [string]: any }
	local written: { [string]: any } = last or {}
	-- Whether path's value moved since it was last written (numbers to 1e-4).
	local function moved(path: string, v: any): boolean
		if type(v) == "number" then
			v = math.floor(v * 1e4 + 0.5) / 1e4
		end
		if written[path] == v then
			return false
		end
		written[path] = v
		return true
	end
	local Lighting = game:GetService("Lighting")
	for key, v in state do
		if type(v) ~= "table" and moved(key, v) then
			(Lighting :: any)[key] = value(v)
		end
	end
	for name, inst in h.blocks do
		local values = state[name]
		if values then
			for key, v in values do
				if moved(name .. "." .. key, v) then
					(inst :: any)[key] = value(v)
				end
			end
		end
	end
	for key, v in state.Water or {} do
		if moved("Water." .. key, v) then
			(workspace.Terrain :: any)[key] = value(v)
		end
	end
	for kind, parts in h.glows do
		local hex = state.Glow and state.Glow[kind]
		if hex and moved("Glow." .. kind, hex) then
			local colour = Color3.fromHex(hex)
			for _, part in parts do
				part.Color = colour
			end
		end
	end
	for key, v in state.Lights or {} do
		if moved("Lights." .. key, v) then
			for _, light in h.lights do
				(light :: any)[key] = value(v)
			end
		end
	end
	if not emissiveBlocked then
		local groups: { [string]: { SurfaceAppearance } } =
			{ TableGlow = h.tableGlow, Windows = h.windows }
		for name, looks in groups do
			for key, v in state[name] or {} do
				if moved(name .. "." .. key, v) then
					for _, look in looks do
						local ok, err = pcall(function()
							(look :: any)[key] = value(v)
						end)
						if not ok then
							emissiveBlocked = true
							warn(
								"MapLighting: the glow's emissive can't be set here ("
									.. tostring(err)
									.. ")"
							)
							break
						end
					end
				end
			end
		end
	end
	return written
end

--- Edit mode: makes sure Lighting has one of each effect (the Atmosphere, the Sky and the post
--- effects, enabled; a second Sky clashes, so extras go), then writes the state. Returns a report.
function MapLighting.preview(state: { [string]: any }, spec: any): string
	if game:GetService("RunService"):IsRunning() then
		error(
			"MapLighting.preview runs in Edit mode; in Play each client's DayCycle lights the place"
		)
	end
	local Lighting = game:GetService("Lighting")
	local removed = 0
	for name, class in BLOCKS do
		local found = {}
		for _, child in Lighting:GetChildren() do
			if child.ClassName == class then
				table.insert(found, child)
			end
		end
		for i = 2, #found do
			found[i]:Destroy()
			removed += 1
		end
		local inst = found[1] or Instance.new(class)
		inst.Name = name
		if inst:IsA("PostEffect") then
			inst.Enabled = true
		end
		inst.Parent = Lighting
	end
	local h = MapLighting.collect(spec)
	MapLighting.apply(state, h, nil)
	local glows = 0
	for _, parts in h.glows do
		glows += #parts
	end
	return ("Lighting: clock %.2f, latitude %.1f; %d glow meshes, %d lights, %d table glow, %d skyline chunks%s."):format(
		Lighting.ClockTime,
		Lighting.GeographicLatitude,
		glows,
		#h.lights,
		#h.tableGlow,
		#h.windows,
		if removed > 0 then (", %d extra effects removed"):format(removed) else ""
	)
end

return MapLighting
