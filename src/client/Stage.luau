--!strict
-- Stage: plays a lively screen's reveal (docs/prompts/SHOP_LIVELY_PROMPT.md sections 3 and 4).
-- A screen registers its pieces by id, then Stage runs the open schedule from Config (for the
-- Shop, Config.UI.Shop.Open with the tokens in Config.UI.Motion), every frame, in code:
--   * Pop, Slam, Grow: the piece's UIScale, shared with UIAnim (its AnimScale; only the first
--     UIScale on an object takes effect, tested 2026-10-06);
--   * Unroll: the panel's chrome opens up and down from a thin bar (its Size, fast);
--   * Drop: the piece falls into place (its Position, fast, Bounce Out);
--   * Fade (and every kind's fade in): the code fader, which caches each descendant's
--     transparencies and drives them from one alpha (never a CanvasGroup: black or blank on
--     phones, blurry at low graphics, and it clips the overshoot);
--   * Burst: a firework flipbook from the effects library behind the piece as it appears.
-- A piece's `onLand` runs once its reveal is over: that is where its idle loops start (so they
-- start as it lands, at their own random phases). `close` fades everything fast while the panel
-- folds to a line; `replay` staggers a page's pieces in again (a tab switch, no unroll); `finish`
-- jumps to the end. Opening again mid-close, or spamming a tab, always ends on a clean screen:
-- every call cancels the run before it. A piece's place, size and transparencies at rest are
-- read when a run starts (the screen lays itself out on open), unless an earlier run left it
-- moved or faded part way. Reduce Motion: pieces only fade in. Lower effects: no
-- bursts. All the maths is StageMath (tested in Lune).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local StageMath = require(Shared:WaitForChild("StageMath"))
local Quality = require(script.Parent.Quality)
local UIAnim = require(script.Parent.UIAnim)

local M = Config.UI.Motion
local FX = Config.UI.Effects

-- The transparencies the fader drives, by class.
local FADED: { [string]: { string } } = {
	Frame = { "BackgroundTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextBox = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
	UIStroke = { "Transparency" },
}

type Cached = { object: Instance, prop: string, rest: number }

type Piece = {
	id: string,
	object: GuiObject,
	onLand: (() -> ())?,
	landed: boolean,
	burst: boolean,
	scale: UIScale?,
	restPosition: UDim2,
	restSize: UDim2,
	moved: boolean, -- a run moved or sized it: restPosition and restSize hold where it belongs
	faded: boolean, -- a run faded it: its cache holds its transparencies at rest
	cache: { Cached }?,
}

local Stage = {}
Stage.__index = Stage

export type Stage = typeof(setmetatable(
	{} :: {
		open: any,
		pieces: { [string]: Piece },
		order: { string },
		burstLayer: GuiObject?,
		connection: RBXScriptConnection?,
		running: string?, -- "play", "replay" or "close" while one runs
	},
	Stage
))

--- A stage for one screen, playing `open` (a Config schedule such as Config.UI.Shop.Open).
--- Bursts go into `burstLayer` (default: the piece's parent).
function Stage.new(open: any, burstLayer: GuiObject?): Stage
	return setmetatable({
		open = open,
		pieces = {},
		order = {},
		burstLayer = burstLayer,
		connection = nil,
		running = nil,
	}, Stage)
end

--- Register `object` as piece `id` (an id in the schedule's steps). `onLand` runs once its
--- reveal is over (start its idle loops there). Returns the object.
function Stage.add<T>(self: Stage, id: string, object: T & GuiObject, onLand: (() -> ())?): T
	self.pieces[id] = {
		id = id,
		object = object,
		onLand = onLand,
		landed = false,
		burst = false,
		scale = nil,
		restPosition = object.Position,
		restSize = object.Size,
		moved = false,
		faded = false,
		cache = nil,
	}
	table.insert(self.order, id)
	return object
end

-- The piece's own transparencies, not those inside another registered piece (that piece fades
-- itself, on its own schedule).
local function buildCache(self: Stage, piece: Piece): { Cached }
	local others: { [Instance]: boolean } = {}
	for id, other in self.pieces do
		if id ~= piece.id then
			others[other.object] = true
		end
	end
	local cache: { Cached } = {}
	local function visit(object: Instance)
		local list = FADED[object.ClassName]
		if list then
			for _, prop in list do
				table.insert(cache, { object = object, prop = prop, rest = (object :: any)[prop] })
			end
		end
		for _, child in object:GetChildren() do
			if not others[child] then
				visit(child)
			end
		end
	end
	visit(piece.object)
	return cache
end

local function fade(self: Stage, piece: Piece, alpha: number)
	if not piece.cache then
		piece.cache = buildCache(self, piece)
	end
	piece.faded = alpha < 1
	for _, c in piece.cache :: { Cached } do
		(c.object :: any)[c.prop] = 1 - (1 - c.rest) * alpha
	end
end

local function scaleOf(piece: Piece): UIScale
	if piece.scale and piece.scale.Parent == piece.object then
		return piece.scale
	end
	local scale = piece.object:FindFirstChildOfClass("UIScale") or UIAnim.scaleOf(piece.object)
	piece.scale = scale
	return scale
end

-- Read the piece's rest (place, size, transparencies) as it is now, unless a run left it part
-- way (then the rest kept from before is the right one).
local function settle(piece: Piece)
	if not piece.moved then
		piece.restPosition = piece.object.Position
		piece.restSize = piece.object.Size
	end
	if not piece.faded then
		piece.cache = nil
	end
end

-- Put a piece back at rest.
local function restore(piece: Piece)
	piece.object.Position = piece.restPosition
	piece.object.Size = piece.restSize
	piece.moved = false
end

-- The panel's chrome at `share` of its height, opening about its middle whatever its anchor.
local function unroll(piece: Piece, share: number)
	piece.moved = true
	local rest = piece.restSize
	local bar = M.BarPx * (1 - math.min(1, share))
	local height = UDim.new(rest.Y.Scale * share, rest.Y.Offset * share + bar)
	piece.object.Size = UDim2.new(rest.X, height)
	local anchor = piece.object.AnchorPoint.Y
	local lost = UDim.new(rest.Y.Scale - height.Scale, rest.Y.Offset - height.Offset)
	local shift = 0.5 - anchor
	local y = piece.restPosition.Y
	piece.object.Position = UDim2.new(
		piece.restPosition.X,
		UDim.new(y.Scale + lost.Scale * shift, y.Offset + lost.Offset * shift)
	)
end

local function burst(self: Stage, piece: Piece, colour: string)
	if Quality.isLow() or UIAnim.reduced() then
		return
	end
	local layer = self.burstLayer or (piece.object.Parent :: any)
	if not layer or not layer:IsA("GuiObject") then
		return
	end
	local size = piece.object.AbsoluteSize
	local centre = piece.object.AbsolutePosition + size / 2 - layer.AbsolutePosition
	local px = math.max(size.X, size.Y) * M.BurstShare
	local label = Instance.new("ImageLabel")
	label.Name = "Burst" .. piece.id
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(centre.X, centre.Y)
	label.Size = UDim2.fromOffset(px, px)
	label.ZIndex = math.max(1, piece.object.ZIndex - 1)
	label.Parent = layer
	UIAnim.flipbook(label, FX.Firework, {
		image = (FX.Firework :: any)[colour] or FX.Firework.Gold,
		fps = M.BurstFps,
		done = function()
			label:Destroy()
		end,
	})
end

local function apply(self: Stage, piece: Piece, e: StageMath.Entry, t: number, reduced: boolean)
	local s = StageMath.pieceState(e, t, M, reduced)
	if e.kind == "Unroll" and not reduced then
		if piece.faded then
			fade(self, piece, 1) -- a Reduce Motion close faded it
		end
		unroll(piece, s.scale)
	else
		fade(self, piece, s.alpha)
		if not reduced and (e.kind == "Pop" or e.kind == "Slam" or e.kind == "Grow") then
			scaleOf(piece).Scale = s.scale
		elseif e.kind == "Drop" then
			piece.moved = true
			piece.object.Position = piece.restPosition + UDim2.fromOffset(0, -M.DropPx * s.drop)
		end
	end
	if e.burst and not piece.burst and t >= e.at then
		piece.burst = true
		burst(self, piece, e.burst)
	end
	if s.landed and not piece.landed then
		piece.landed = true
		if piece.moved then
			restore(piece)
		end
		if piece.onLand then
			task.spawn(piece.onLand)
		end
	end
end

local function stop(self: Stage)
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.running = nil
end

-- Run `entries` (only the registered pieces) from t = 0; `finish` when the last one lands.
local function run(self: Stage, entries: { StageMath.Entry }, finish: number, done: (() -> ())?)
	stop(self)
	local reduced = UIAnim.reduced()
	local live: { { piece: Piece, entry: StageMath.Entry } } = {}
	for _, e in entries do
		local piece = self.pieces[e.id]
		if piece then
			settle(piece)
			piece.landed = false
			piece.burst = false
			table.insert(live, { piece = piece, entry = e })
			apply(self, piece, e, 0, reduced)
		end
	end
	local t = 0
	local last = finish + (if reduced then M.ReducedFadeSeconds else 0)
	self.connection = RunService.RenderStepped:Connect(function(dt)
		t += dt
		for _, l in live do
			apply(self, l.piece, l.entry, t, reduced)
		end
		if t > last then
			stop(self)
			if done then
				done()
			end
		end
	end)
end

--- Play the whole open (`openSeconds` overrides the schedule's length, 1 to 2 s).
function Stage.play(self: Stage, openSeconds: number?, done: (() -> ())?)
	local entries, finish = StageMath.schedule(self.open, M, openSeconds)
	run(self, entries, finish, done)
	self.running = "play"
end

--- What is running: "play" (the open), "replay" (a tab switch), "close", or nil.
function Stage.busy(self: Stage): string?
	return self.running
end

--- The ids of the registered pieces inside `root` (a page: what a tab switch replays).
function Stage.idsUnder(self: Stage, root: Instance): { string }
	local ids: { string } = {}
	for _, id in self.order do
		if self.pieces[id].object:IsDescendantOf(root) then
			table.insert(ids, id)
		end
	end
	return ids
end

--- Stagger only `ids` in again over Config.UI.Motion.TabSeconds (a tab switch: no unroll).
function Stage.replay(self: Stage, ids: { string }, done: (() -> ())?)
	local entries = StageMath.schedule(self.open, M)
	local wanted: { [string]: boolean } = {}
	for _, id in ids do
		wanted[id] = true
	end
	local picked: { StageMath.Entry } = {}
	local from, to = math.huge, 0
	for _, e in entries do
		if wanted[e.id] or (e.badgeOf and wanted[e.badgeOf]) then
			table.insert(picked, e)
			from = math.min(from, e.at)
			to = math.max(to, e.at)
		end
	end
	local squeeze = if to > from then M.TabSeconds / (to - from) else 1
	local finish = 0
	for i, e in picked do
		local moved = table.clone(e)
		moved.at = (e.at - from) * math.min(1, squeeze)
		picked[i] = moved
		finish = math.max(finish, moved.at + moved.length)
	end
	run(self, picked, finish, done)
	self.running = "replay"
end

--- Fade everything fast while the panel (the "Unroll" piece) folds back to a line, then `done`.
function Stage.close(self: Stage, done: (() -> ())?)
	stop(self)
	local panel: Piece? = nil
	for _, e in StageMath.schedule(self.open, M) do
		if e.kind == "Unroll" and self.pieces[e.id] then
			panel = self.pieces[e.id]
		end
	end
	for _, id in self.order do
		settle(self.pieces[id])
	end
	local t = 0
	self.running = "close"
	self.connection = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local p = math.min(1, t / M.CloseSeconds)
		for _, id in self.order do
			local piece = self.pieces[id]
			if piece ~= panel then
				fade(self, piece, 1 - p)
			end
		end
		if panel then
			if UIAnim.reduced() then
				fade(self, panel, 1 - p)
			else
				unroll(panel, StageMath.closeShare(p))
			end
		end
		if p >= 1 then
			stop(self)
			if panel then
				restore(panel) -- hidden now; the next open unrolls it again from its rest
			end
			if done then
				done()
			end
		end
	end)
end

--- Jump to the end: every piece shown at rest, every `onLand` run once.
function Stage.finish(self: Stage)
	stop(self)
	for _, id in self.order do
		local piece = self.pieces[id]
		fade(self, piece, 1)
		if piece.scale then
			piece.scale.Scale = 1
		end
		restore(piece)
		if not piece.landed then
			piece.landed = true
			if piece.onLand then
				task.spawn(piece.onLand)
			end
		end
	end
end

--- Stop playing (the screen is being destroyed).
function Stage.destroy(self: Stage)
	stop(self)
	table.clear(self.pieces)
	table.clear(self.order)
end

return Stage
