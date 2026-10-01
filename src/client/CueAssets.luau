--!strict
-- CueAssets: a cue is shown only once the renderer has loaded its whole look (designer,
-- 2026-10-01: a switched-in cue must appear as itself, never white then textured, on any
-- device and graphics quality; the old cue stays until then and the two swap in one frame).
--
-- Why a hidden copy: a SurfaceAppearance's maps are fetched by the renderer only when one is
-- drawn (ContentProvider:PreloadAsync on its template loads just the mesh, and on the map ids
-- loads them in another form the renderer fetches again). So `warm(id)` draws a copy of the cue
-- Config.CueSkins.Warm.Transparency see-through in front of the camera: its surface (and every
-- moving-surface frame), its 3D piece, and one particle and one beam per effect sprite.
--
-- The cue is ready when every one of those textures has reported loaded (ContentProvider's
-- fetch status) for SettleSeconds, the copy has been drawn MinSeconds and MinFrames, and its
-- piece's meshes are preloaded. Nothing else in the game fetches these ids (pictures use the
-- Thumb images), so the status is the renderer's. A texture still never asked for after
-- UnrequestedSeconds (with nothing downloading) or UnrequestedMaxSeconds came from Roblox's
-- own cache on the device, which loads without a fetch status. A texture whose download failed
-- is remembered as failed by Roblox (its SurfaceAppearance stays blank, and a new one does not
-- ask again), so it is downloaded once more as a Decal's image (which clears the failure) and
-- the copy is built afresh, up to Retries times. After TimeoutSeconds the cue is ready anyway,
-- so a broken asset never hides a cue.
--
-- A ready copy stays drawn KeepSeconds after it was last asked for (it keeps the textures in
-- memory; Equip right after picking a cue in the inventory is then instant), at most MaxCopies
-- of them; then ready(id) is false again and the next ask warms it once more (quick when still
-- cached). A cue drawn with bands (no template) is always ready.
--
-- CueStickBuilder paints a stick's new cue only when ready (setLoader, from Main), BackCue
-- swaps a back's stick only when ready, CueViewport replaces its cue only when ready.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))
local Textures = require(Shared:WaitForChild("CueSkins"):WaitForChild("Textures"))

local W = Config.CueSkins.Warm

local CueAssets = {}

type Warm = {
	model: Model,
	skin: Instance, -- the cue's template
	retries: number, -- repairs of a failed download
	retriedAt: number,
	repairing: boolean, -- a failed texture is being downloaded again
	repaired: boolean, -- it has been: build the copy afresh

	parts: { BasePart }, -- moved with the camera every frame
	offsets: { CFrame }, -- each part's place relative to the copy's centre
	emitters: { ParticleEmitter },
	ids: { string }, -- every texture the copy draws
	started: number,
	frames: number,
	settledAt: number?, -- when every texture last became loaded
	meshes: boolean, -- the piece's meshes are preloaded
	ready: boolean,
	touched: number, -- last asked for
	waiters: { () -> () },
}

local warms: { [string]: Warm } = {}
local holder: Folder? = nil
local stepping: RBXScriptConnection? = nil
local lastEmit = 0

local function template(id: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild(Config.Cue.MeshSkinsFolder)
	return folder and folder:FindFirstChild(id)
end

-- Every "rbxassetid://..." string anywhere in `value`, once each.
local function collect(value: any, out: { string }, seen: { [string]: boolean })
	if type(value) == "string" then
		if value:match("^rbxassetid://%d+$") and not seen[value] then
			seen[value] = true
			table.insert(out, value)
		end
	elseif type(value) == "table" then
		for _, v in value do
			collect(v, out, seen)
		end
	end
end

local function folder(): Folder
	if holder == nil or holder.Parent == nil then
		local f = Instance.new("Folder")
		f.Name = "CueWarmup"
		f.Parent = Workspace
		holder = f
	end
	return holder :: Folder
end

-- A copy drawn but never seen: see-through, no shadow, no physics, no glow.
local function hide(root: Instance)
	for _, d in (root :: any):GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if d.Transparency < 1 then
				d.Transparency = W.Transparency
			end
			if d.Material == Enum.Material.Neon or d.Material == Enum.Material.ForceField then
				d.Material = Enum.Material.SmoothPlastic
			end
		elseif d:IsA("Decal") then
			d.Transparency = W.Transparency
		elseif
			d:IsA("ParticleEmitter")
			or d:IsA("Beam")
			or d:IsA("Trail")
			or d:IsA("Light")
			or d:IsA("Highlight")
		then
			(d :: any).Enabled = false
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

-- One hidden particle and one hidden beam drawing sprite `texture` on `host`.
local function sprite(host: BasePart, texture: string, emitters: { ParticleEmitter })
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-0.5, 0, 0)
	a0.Parent = host
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0.5, 0, 0)
	a1.Parent = host
	local beam = Instance.new("Beam")
	beam.Texture = texture
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Width0, beam.Width1 = 1, 1
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightEmission = 0
	beam.Brightness = 1
	beam.Transparency = NumberSequence.new(W.Transparency)
	beam.Parent = host
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Enabled = false
	e.Rate = 0
	e.Speed = NumberRange.new(0)
	e.Lifetime = NumberRange.new(W.SpriteEmitSeconds * 2)
	e.Size = NumberSequence.new(1)
	e.LightEmission = 0
	e.Brightness = 1
	e.Transparency = NumberSequence.new(W.Transparency)
	e.Parent = a0
	table.insert(emitters, e)
end

local function finish(w: Warm)
	if w.ready then
		return
	end
	w.ready = true
	local list = w.waiters
	w.waiters = {}
	for _, fn in list do
		task.spawn(fn)
	end
end

local function drop(id: string)
	local w = warms[id]
	if w then
		warms[id] = nil
		w.model:Destroy()
		finish(w) -- never leaves a waiter hanging
	end
end

-- Only MaxCopies loaded copies stay drawn: the least recently asked for go first.
local function trim()
	local kept: { { id: string, touched: number } } = {}
	for id, w in warms do
		if w.ready then
			table.insert(kept, { id = id, touched = w.touched })
		end
	end
	if #kept <= W.MaxCopies then
		return
	end
	table.sort(kept, function(a, b)
		return a.touched < b.touched
	end)
	for i = 1, #kept - W.MaxCopies do
		drop(kept[i].id)
	end
end

local retry: (w: Warm, id: string, now: number) -> ()
local repair: (w: Warm, failed: { string }) -> ()

local function step()
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local at = if camera
		then camera.CFrame * CFrame.new(0, 0, -W.DistanceStuds)
		else CFrame.new(0, -1e4, 0)
	local emit = now - lastEmit >= W.SpriteEmitSeconds
	if emit then
		lastEmit = now
	end
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for id, w in warms do
		if w.ready then
			if now - w.touched > W.KeepSeconds then
				drop(id)
				continue
			end
		else
			w.frames += 1
			local loaded = w.meshes
			if loaded then
				-- Never asked for while drawn this long and nothing downloading: it came from the
				-- device's cache, which loads without a fetch status.
				local drawn = now - w.started
				local resident = drawn >= W.UnrequestedMaxSeconds
					or (drawn >= W.UnrequestedSeconds and ContentProvider.RequestQueueSize == 0)
				local failed: { string } = {}
				for _, content in w.ids do
					local status = ContentProvider:GetAssetFetchStatus(content)
					if
						status == Enum.AssetFetchStatus.Loading
						or (status == Enum.AssetFetchStatus.None and not resident)
					then
						loaded = false
					elseif
						status == Enum.AssetFetchStatus.Failure
						or status == Enum.AssetFetchStatus.TimedOut
					then
						table.insert(failed, content)
					end
				end
				-- A failed download is repaired while repairs are left (retry), not shown.
				if w.repaired then
					loaded = false
					retry(w, id, now)
				elseif w.repairing then
					loaded = false
				elseif #failed > 0 and w.retries < W.Retries then
					loaded = false
					if now - w.retriedAt >= W.RetrySeconds then
						repair(w, failed)
					end
				end
			end
			if not loaded then
				w.settledAt = nil
			elseif w.settledAt == nil then
				w.settledAt = now
			end
			local settled = w.settledAt ~= nil and now - (w.settledAt :: number) >= W.SettleSeconds
			if settled and now - w.started >= W.MinSeconds and w.frames >= W.MinFrames then
				finish(w)
			elseif now - w.started >= W.TimeoutSeconds then
				if RunService:IsStudio() then
					warn(
						("[8ball] CueAssets: %s shown before its look loaded (timeout)"):format(id)
					)
				end
				finish(w)
			end
		end
		for i, part in w.parts do
			table.insert(parts, part)
			table.insert(frames, at * w.offsets[i])
		end
		if emit then
			for _, e in w.emitters do
				e:Emit(1)
			end
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if next(warms) == nil and stepping then
		stepping:Disconnect()
		stepping = nil
	end
end

-- Fill `w.model` with the hidden copy of cue `id`: its surface (and a copy of the mesh for
-- every moving-surface frame), its 3D piece and its effect sprites; `w.ids` lists every texture.
local function dress(w: Warm, id: string, skin: Instance)
	local model = w.model
	local seen: { [string]: boolean } = {}
	local row = CueSkins.get(id)
	local cue = skin:FindFirstChildWhichIsA("MeshPart", true)
	local surfaces: { MeshPart } = {}
	if cue then
		table.insert(surfaces, (cue:Clone() :: any) :: MeshPart)
		local frameFolder = skin:FindFirstChild("Frames")
		local frameList: { Instance } = if frameFolder then frameFolder:GetChildren() else {}
		for _, sa in frameList do
			if sa:IsA("SurfaceAppearance") then
				local copy = (cue:Clone() :: any) :: MeshPart
				for _, c in copy:GetChildren() do
					if c:IsA("SurfaceAppearance") then
						c:Destroy()
					end
				end
				sa:Clone().Parent = copy
				table.insert(surfaces, copy)
			end
		end
	end
	for i, mesh in surfaces do
		mesh.Name = "Surface" .. i
		mesh.Parent = model
		table.insert(w.parts, mesh)
		table.insert(w.offsets, CFrame.Angles(0, math.rad(90), 0))
	end
	if row then
		collect(row.Maps, w.ids, seen)
		collect(row.Frames, w.ids, seen)
	end
	-- The 3D piece, as built (its meshes preloaded, its textures drawn).
	local piece: Instance? = nil
	if row and row.Piece then
		local pieces = ReplicatedStorage:FindFirstChild(Config.CueSkins.PiecesFolder)
		piece = pieces and pieces:FindFirstChild(row.Piece)
		collect(CueSkins.piece(row.Piece), w.ids, seen)
	end
	if piece then
		local copy = piece:Clone()
		copy.Parent = model
		local centre: CFrame? = nil
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				centre = centre or d.CFrame
				table.insert(w.parts, d)
				table.insert(w.offsets, (centre :: CFrame):ToObjectSpace(d.CFrame))
			end
		end
		if not w.meshes then
			local source = piece
			task.spawn(function()
				pcall(function()
					ContentProvider:PreloadAsync({ source })
				end)
				w.meshes = true
			end)
		end
	else
		w.meshes = true
	end
	-- Every effect sprite: one hidden particle and one hidden beam each.
	local sprites: { string } = {}
	if row then
		collect(row.Aura, sprites, seen)
		collect(row.Moving, sprites, seen)
	end
	collect(Textures, sprites, seen)
	local host = Instance.new("Part")
	host.Name = "Sprites"
	host.Size = Vector3.new(1, 1, 1)
	host.Transparency = 1
	host.Parent = model
	for _, texture in sprites do
		sprite(host, texture, w.emitters)
		table.insert(w.ids, texture)
	end
	table.insert(w.parts, host)
	table.insert(w.offsets, CFrame.new())
	hide(model)
	model.Parent = folder()
end

-- Download the failed textures once more as Decal images: that clears Roblox's remembered
-- failure, so the fresh copy built next (retry) loads them.
function repair(w: Warm, failed: { string })
	w.retries += 1
	w.repairing = true
	local decals: { Instance } = {}
	for _, content in failed do
		local d = Instance.new("Decal")
		d.Texture = content
		table.insert(decals, d)
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(decals)
		end)
		w.repaired = true
	end)
end

-- Build the copy afresh: a SurfaceAppearance that missed a texture stays blank for good.
function retry(w: Warm, id: string, now: number)
	w.repairing, w.repaired = false, false
	w.retriedAt = now
	w.model:Destroy()
	local model = Instance.new("Model")
	model.Name = id
	w.model = model
	w.parts, w.offsets, w.emitters, w.ids = {}, {}, {}, {}
	w.settledAt = nil
	dress(w, id, w.skin)
end

-- Start drawing the hidden copy of cue `id` (which has a template).
local function warm(id: string, skin: Instance): Warm
	local now = os.clock()
	local model = Instance.new("Model")
	model.Name = id
	local w: Warm = {
		model = model,
		skin = skin,
		parts = {},
		offsets = {},
		emitters = {},
		ids = {},
		started = now,
		frames = 0,
		settledAt = nil,
		meshes = false,
		retries = 0,
		retriedAt = now,
		repairing = false,
		repaired = false,
		ready = false,
		touched = now,
		waiters = {},
	}
	dress(w, id, skin)
	warms[id] = w
	if stepping == nil then
		stepping = RunService.RenderStepped:Connect(step)
	end
	return w
end

--- True when cue `id` can be shown fully loaded now (a band cue always can).
function CueAssets.ready(id: string): boolean
	if template(id) == nil then
		return true
	end
	local w = warms[id]
	return w ~= nil and w.ready
end

--- Start loading cue `id` (or keep its loaded copy a while longer). Never blocks.
function CueAssets.preload(id: string)
	local w = warms[id]
	if w then
		w.touched = os.clock()
		return
	end
	local skin = template(id)
	if skin then
		warm(id, skin)
		trim()
	end
end

--- Call `fn` once cue `id` is ready: now when it already is, else when the renderer has loaded
--- it (loading starts here if needed).
function CueAssets.whenReady(id: string, fn: () -> ())
	CueAssets.preload(id)
	if CueAssets.ready(id) then
		fn()
		return
	end
	table.insert((warms[id] :: Warm).waiters, fn)
end

return CueAssets
