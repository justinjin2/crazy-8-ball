--!strict
-- Leaderboards: the global boards (GUI lane, designer 2026-10-03, D9): Most wins vs players
-- (the WinsVsPlayers attribute, Stats.Wins) and Highest rank (RankXp). Each is an
-- OrderedDataStore (Config.Leaderboards.Boards): the one exception to "saves go through the
-- save layer", since a board is a public ranking, never a save. Only the server writes.
-- - Writes: a loaded player whose value changed is written at most once every WriteSeconds,
--   and once more when they leave. Bots are never written.
-- - Reads: the top Size of each board every ReadSeconds (names asked of Roblox once, cached),
--   sent to everyone on the Leaderboards remote (and to a player as they load).
-- - The lobby signs: two boards standing in front of the spawn (Config.Leaderboards.Signs),
--   built by code, showing the top SignRows; off while Config.Leaderboards.SignsOn is false.
-- Studio without DataStores (an unpublished place): the boards are this server's players.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)
local Format = require(Shared.Progression.Format)
local Ranks = require(Shared.Progression.Ranks)
local PlayerData = require(script.Parent.PlayerData)

local L = Config.Leaderboards
local IS_STUDIO = RunService:IsStudio()
local W = Strings.PlayerList

export type Entry = { userId: number, name: string, value: number }

local Leaderboards = {}

local started = false
local remote: RemoteEvent? = nil
local stores: { [string]: OrderedDataStore? } = {}
local storesTried = false
local written: { [Player]: { [string]: number } } = {} -- the last value written, per board
local lastWrite: { [Player]: number } = {}
local names: { [number]: string } = {}
local current: { [string]: { Entry } } = {}
local lastWarn: { [string]: number } = {}
local signs: { [string]: { rows: { TextLabel } } } = {}

local function complain(what: string, err: any)
	local now = os.clock()
	if now - (lastWarn[what] or -math.huge) >= 120 then
		lastWarn[what] = now
		warn(("[8ball] Leaderboards: %s failed: %s"):format(what, tostring(err)))
	end
end

local function openStores()
	if storesTried then
		return
	end
	storesTried = true
	for _, board in L.Boards do
		local name = board.Store .. (if IS_STUDIO then L.StudioSuffix else "")
		local ok, result = pcall(function(): OrderedDataStore
			return DataStoreService:GetOrderedDataStore(name)
		end)
		if ok then
			stores[board.Key] = result
		else
			complain("opening " .. name, result)
		end
	end
end

local function valueOf(player: Player, attribute: string): number?
	local v = player:GetAttribute(attribute)
	if type(v) == "number" and v == v and v >= 0 and v < 2 ^ 53 then
		return math.floor(v)
	end
	return nil
end

-- Writes the player's values that changed since the last write. Yields.
local function write(player: Player)
	if not PlayerData.isLoaded(player) then
		return
	end
	openStores()
	local mine = written[player] or {}
	written[player] = mine
	lastWrite[player] = os.clock()
	for _, board in L.Boards do
		local value = valueOf(player, board.Attribute)
		local store = stores[board.Key]
		if value ~= nil and value > 0 and mine[board.Key] ~= value and store then
			local ok, err = pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
			if ok then
				mine[board.Key] = value
			else
				complain("writing " .. board.Key, err)
			end
		end
	end
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local here = Players:GetPlayerByUserId(userId)
	if here then
		names[userId] = here.Name
		return here.Name
	end
	local ok, name = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		names[userId] = name
		return name
	end
	return "#" .. tostring(userId)
end

-- This server's players as a board (Studio with no DataStores).
local function localBoard(attribute: string): { Entry }
	local list: { Entry } = {}
	for _, player in Players:GetPlayers() do
		local value = valueOf(player, attribute)
		if value and value > 0 then
			table.insert(list, { userId = player.UserId, name = player.Name, value = value })
		end
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)
	return list
end

-- Reads every board's top Size. Yields.
local function read()
	openStores()
	for _, board in L.Boards do
		local store = stores[board.Key]
		local list: { Entry } = {}
		local ok, err = false, "no store" :: any
		if store then
			ok, err = pcall(function()
				local pages = store:GetSortedAsync(false, L.Size)
				for _, item in pages:GetCurrentPage() do
					local id = tonumber(item.key)
					if id and type(item.value) == "number" then
						table.insert(list, { userId = id, name = "", value = item.value })
					end
				end
			end)
		end
		if ok then
			for _, entry in list do
				entry.name = nameOf(entry.userId)
			end
			current[board.Key] = list
		elseif IS_STUDIO then
			current[board.Key] = localBoard(board.Attribute)
		else
			complain("reading " .. board.Key, err)
		end
	end
end

local function payload(): any
	return { at = os.time(), boards = current }
end

---------------------------------------------------------------------------------------------
-- The lobby signs
---------------------------------------------------------------------------------------------

local function color(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function label(
	parent: Instance,
	name: string,
	text: string,
	size: number,
	y: number,
	h: number
): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.Text = text
	t.TextSize = size
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0
	t.TextStrokeColor3 = color(L.SignColor)
	t.Position = UDim2.fromOffset(0, y)
	t.Size = UDim2.new(1, 0, 0, h)
	t.Parent = parent
	return t
end

local function buildSigns()
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = workspace
	local size = Vector3.new(L.SignSize[1], L.SignSize[2], L.SignSize[3])
	for _, sign in L.Signs do
		local part = Instance.new("Part")
		part.Name = sign.Board .. "Board"
		part.Anchored = true
		part.CanCollide = true
		part.Material = Enum.Material.SmoothPlastic
		part.Color = color(L.SignColor)
		part.Size = size
		part.CFrame = CFrame.new(sign.X, L.SignLiftStuds + size.Y / 2, sign.Z)
			* CFrame.Angles(0, math.rad(sign.YawDegrees), 0)
		part.Parent = folder
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = L.SignPixelsPerStud
		gui.LightInfluence = 0
		gui.Brightness = 1.5
		gui.Parent = part
		local px = Vector2.new(size.X, size.Y) * L.SignPixelsPerStud
		local title = if sign.Board == "Wins" then W.SignWins else W.SignRank
		label(gui, "Title", title, L.SignTitlePx, 16, L.SignTitlePx + 16).TextColor3 =
			color(Config.UI.Kit.Numbers.Money)
		local rowH = math.floor((px.Y - L.SignTopPx - 10) / L.SignRows)
		local rows: { TextLabel } = {}
		for i = 1, L.SignRows do
			local row =
				label(gui, "Row" .. i, "", L.SignRowTextPx, L.SignTopPx + (i - 1) * rowH, rowH)
			row.TextXAlignment = Enum.TextXAlignment.Left
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, L.SignPadPx)
			pad.PaddingRight = UDim.new(0, L.SignPadPx)
			pad.Parent = row
			table.insert(rows, row)
		end
		signs[sign.Board] = { rows = rows }
	end
end

local function paintSigns()
	for key, sign in signs do
		local list = current[key] or {}
		for i, row in sign.rows do
			local entry = list[i]
			if entry then
				local value = if key == "Rank"
					then Ranks.name(Ranks.fromXp(entry.value, true))
					else W.Wins:format(Format.commas(entry.value))
				row.Text = ("%d.  %s   —   %s"):format(i, entry.name, value)
			else
				row.Text = if i == 1 and #list == 0 then W.SignEmpty else ""
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

--- Starts the writes, reads and the signs (Bootstrap calls this once).
function Leaderboards.start()
	if started then
		return
	end
	started = true
	remote = Net.get("Leaderboards")
	if L.SignsOn then
		buildSigns()
	end
	PlayerData.Loaded:Connect(function(player: Player)
		task.spawn(function()
			write(player)
			local r = remote
			if r and player.Parent == Players then
				r:FireClient(player, payload())
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		task.spawn(function()
			pcall(write, player)
			written[player] = nil
			lastWrite[player] = nil
		end)
	end)
	-- Writes: changed values, at most once a WriteSeconds per player.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in Players:GetPlayers() do
				local mine = written[player]
				local due = os.clock() - (lastWrite[player] or 0) >= L.WriteSeconds
				if mine and due then
					for _, board in L.Boards do
						if valueOf(player, board.Attribute) ~= mine[board.Key] then
							task.spawn(write, player)
							break
						end
					end
				end
			end
		end
	end)
	-- Reads: the top of each board, to everyone.
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				read()
			end)
			if not ok then
				complain("the read", err)
			end
			local shown, why = pcall(function()
				paintSigns()
				local r = remote
				if r then
					r:FireAllClients(payload())
				end
			end)
			if not shown then
				complain("the signs", why)
			end
			task.wait(L.ReadSeconds)
		end
	end)
end

return Leaderboards
