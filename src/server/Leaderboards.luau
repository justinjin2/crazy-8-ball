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
--
-- The lobby boards (designer, 2026-10-25; Config.Leaderboards.Lobby, off = all of the above as
-- it was): Most wins (the Wins store, now its top WinsRows) and Top countries (CountryStore).
-- - Every server (arenas too, where most real wins happen) adds each player's new wins vs
--   people to their country (Roblox's country, a hidden flag too) and flushes the sums with one
--   IncrementAsync per country every TallySeconds and on shutdown; a failed add is kept.
-- - Lobby servers build the two stands (workspace.Leaderboards), read the wins' first page and
--   every country every TopReadSeconds and the later pages every DeepReadSeconds, and answer
--   LeaderboardRead: nothing is pushed; a screen asks while near (LobbyBoards).
local DataStoreService = game:GetService("DataStoreService")
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)
local Format = require(Shared.Progression.Format)
local Ranks = require(Shared.Progression.Ranks)
local LeaderboardMath = require(Shared.LeaderboardMath)
local Funnel = require(script.Parent.Funnel)
local PlayerData = require(script.Parent.PlayerData)

local L = Config.Leaderboards
local LB = L.Lobby
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
-- The lobby boards: the country tally (every server)
---------------------------------------------------------------------------------------------

local countryStore: OrderedDataStore? = nil
local countryStoreTried = false
local tally: LeaderboardMath.Tally = {}
local countryOf: { [Player]: string } = {}
local baseline: { [Player]: number? } = {}
local watching: { [Player]: RBXScriptConnection } = {}

local function openCountryStore(): OrderedDataStore?
	if not countryStoreTried then
		countryStoreTried = true
		local name = L.CountryStore .. (if IS_STUDIO then L.StudioSuffix else "")
		local ok, result = pcall(function(): OrderedDataStore
			return DataStoreService:GetOrderedDataStore(name)
		end)
		if ok then
			countryStore = result
		else
			complain("opening " .. name, result)
		end
	end
	return countryStore
end

-- The player's country from Roblox, asked once. Yields.
local function countryFor(player: Player): string?
	local known = countryOf[player]
	if known then
		return known
	end
	local ok, result = pcall(function(): string
		return LocalizationService:GetCountryRegionForPlayerAsync(player)
	end)
	if ok and type(result) == "string" and #result == 2 and player.Parent == Players then
		local code = string.upper(result)
		countryOf[player] = code
		return code
	end
	return nil
end

-- Watch a loaded player's wins vs people: each new one goes to their country.
local function watchWins(player: Player)
	if watching[player] then
		return
	end
	local attribute = "WinsVsPlayers"
	baseline[player] = select(2, LeaderboardMath.newWins(nil, player:GetAttribute(attribute)))
	watching[player] = player:GetAttributeChangedSignal(attribute):Connect(function()
		local added, now = LeaderboardMath.newWins(baseline[player], player:GetAttribute(attribute))
		baseline[player] = now
		if added > 0 then
			task.spawn(function()
				LeaderboardMath.add(tally, countryFor(player), added)
			end)
		end
	end)
	task.spawn(countryFor, player)
end

local function unwatch(player: Player)
	local connection = watching[player]
	if connection then
		connection:Disconnect()
	end
	watching[player] = nil
	baseline[player] = nil
	countryOf[player] = nil
end

-- Add the tally's sums to the store; a failed add goes back in. Yields.
local function flushTally()
	if next(tally) == nil then
		return
	end
	local store = openCountryStore()
	local sums = LeaderboardMath.take(tally)
	for code, n in sums do
		local ok, err = false, "no store" :: any
		if store then
			ok, err = pcall(function()
				store:IncrementAsync(code, n)
			end)
		end
		if not ok then
			LeaderboardMath.add(tally, code, n)
			complain("adding to " .. code, err)
		end
	end
end

---------------------------------------------------------------------------------------------
-- The lobby boards: the lists (lobby servers)
---------------------------------------------------------------------------------------------

type WinsRow = { u: number, n: string, v: number } -- a user id, their name, their wins
type CountryRow = { c: string, v: number } -- a country code, its wins

local winsTop: { WinsRow } = {} -- the first page, fresh every TopReadSeconds
local winsDeep: { WinsRow } = {} -- the later pages, fresh every DeepReadSeconds
local winsAll: { WinsRow } = {} -- the two together, no one twice
local countries: { CountryRow } = {}
local listsAt = 0
local seen: { [Player]: { [string]: boolean } } = {}
local deepest: { [Player]: { [string]: number } } = {}
local requestBuckets: { [Player]: { tokens: number, at: number } } = {}

-- Ask Roblox for the names of `ids` not known yet, NamesPerCall at a time. Yields.
local function learnNames(ids: { number })
	local missing: { number } = {}
	for _, id in ids do
		if names[id] == nil then
			local here = Players:GetPlayerByUserId(id)
			if here then
				names[id] = here.Name
			else
				table.insert(missing, id)
			end
		end
	end
	for i = 1, #missing, LB.NamesPerCall do
		local batch = table.move(missing, i, math.min(#missing, i + LB.NamesPerCall - 1), 1, {})
		local ok, infos = pcall(function(): any
			return UserService:GetUserInfosByUserIdsAsync(batch)
		end)
		if ok and type(infos) == "table" then
			for _, info in infos do
				if
					type(info) == "table"
					and type(info.Id) == "number"
					and type(info.Username) == "string"
				then
					names[info.Id] = info.Username
				end
			end
		else
			complain("names", infos)
		end
	end
end

local function joinWins()
	local all: { WinsRow } = table.clone(winsTop)
	local inTop: { [number]: boolean } = {}
	for _, row in winsTop do
		inTop[row.u] = true
	end
	for _, row in winsDeep do
		if not inTop[row.u] and #all < LB.WinsRows then
			table.insert(all, row)
		end
	end
	for _, row in all do
		row.n = names[row.u] or ("#" .. tostring(row.u))
	end
	winsAll = all
end

-- Read `pages` pages of a store, best first, calling `each(key, value)` per row. Yields.
local function readPages(
	store: OrderedDataStore,
	pages: number,
	gap: number,
	each: (string, number) -> ()
)
	local sorted = store:GetSortedAsync(false, LB.PageRows)
	for page = 1, pages do
		for _, item in sorted:GetCurrentPage() do
			if type(item.value) == "number" then
				each(item.key, item.value)
			end
		end
		if sorted.IsFinished or page == pages then
			break
		end
		if gap > 0 then
			task.wait(gap)
		end
		sorted:AdvanceToNextPageAsync()
	end
end

local function readWins(first: boolean)
	openStores()
	local store = stores.Wins
	local rows: { WinsRow } = {}
	local ok, err = false, "no store" :: any
	if store then
		ok, err = pcall(function()
			local pages = math.ceil(LB.WinsRows / LB.PageRows)
			local skip = if first then 0 else LB.PageRows
			local index = 0
			readPages(
				store,
				if first then 1 else pages,
				if first then 0 else LB.DeepPageGapSeconds,
				function(key, value)
					index += 1
					local id = tonumber(key)
					if id and index > skip then
						table.insert(rows, { u = id, n = "", v = value })
					end
				end
			)
		end)
	end
	if not ok then
		if IS_STUDIO and first then
			for _, entry in localBoard("WinsVsPlayers") do
				table.insert(rows, { u = entry.userId, n = entry.name, v = entry.value })
			end
		else
			complain(if first then "reading wins" else "reading later wins", err)
			return
		end
	end
	local ids: { number } = {}
	for _, row in rows do
		table.insert(ids, row.u)
	end
	learnNames(ids)
	if first then
		winsTop = rows
	else
		winsDeep = rows
	end
	joinWins()
end

local function readCountries()
	local store = openCountryStore()
	local rows: { CountryRow } = {}
	local ok, err = false, "no store" :: any
	if store then
		ok, err = pcall(function()
			readPages(store, math.ceil(LB.CountryRows / LB.PageRows), 0, function(key, value)
				if string.match(key, "^%u%u$") and value > 0 then
					table.insert(rows, { c = key, v = value })
				end
			end)
		end)
	end
	if ok then
		countries = rows
	else
		complain("reading countries", err)
	end
end

local function allowed(player: Player): boolean
	local now = os.clock()
	local b = requestBuckets[player]
	if not b then
		b = { tokens = LB.RequestBurst, at = now }
		requestBuckets[player] = b
	end
	b.tokens = math.min(LB.RequestBurst, b.tokens + (now - b.at) * LB.RequestPerSecond)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

-- A deepest-row bucket for the Scrolled event (the dashboard takes few distinct values).
local function depthBucket(row: number): string
	for _, edge in { 10, 50, 100, 250, 500 } do
		if row <= edge then
			return tostring(edge)
		end
	end
	return tostring(LB.WinsRows)
end

local function onRead(player: Player, kind: any, a: any, b: any): any
	if not allowed(player) then
		return { ok = false, reason = "TooFast" }
	end
	if kind == "top" then
		local you = LeaderboardMath.place(winsAll, "u", player.UserId)
		-- Asked once and cached; a board read right after joining waits for it (it said "isn't on
		-- the board yet" for a minute).
		local code = countryFor(player)
		-- Before the save loads, the wins come from the player's own row.
		local mine = player:GetAttribute("WinsVsPlayers")
		if mine == nil and you then
			mine = winsAll[you].v
		end
		return {
			ok = true,
			at = listsAt,
			total = #winsAll,
			wins = table.move(winsAll, 1, math.min(#winsAll, LB.PageRows), 1, {}),
			countries = countries,
			you = you,
			wins_mine = mine,
			country = code,
			countryPlace = LeaderboardMath.place(countries, "c", code),
		}
	elseif kind == "wins" then
		local page = if type(a) == "number" then math.floor(a) else 0
		local last = math.ceil(LB.WinsRows / LB.PageRows)
		if page < 1 or page > last then
			return { ok = false, reason = "BadRequest" }
		end
		local from = (page - 1) * LB.PageRows + 1
		return {
			ok = true,
			at = listsAt,
			page = page,
			rows = table.move(winsAll, from, math.min(#winsAll, from + LB.PageRows - 1), 1, {}),
		}
	elseif kind == "seen" then
		-- ("seen", board, deepest row): Viewed once a session per board, Scrolled when deeper.
		local board = if a == "Wins" or a == "Countries" then a else nil
		if board == nil then
			return { ok = false, reason = "BadRequest" }
		end
		local mine = seen[player] or {}
		seen[player] = mine
		if not mine[board] then
			mine[board] = true
			Funnel.event(player, "Leaderboard", 1, "Viewed", board, Funnel.device(player))
		end
		local row = if type(b) == "number" then math.floor(b) else 0
		local deep = deepest[player] or {}
		deepest[player] = deep
		local bucket = depthBucket(row)
		if row > 10 and tonumber(bucket) ~= tonumber(depthBucket(deep[board] or 0)) then
			Funnel.event(player, "Leaderboard", row, "Scrolled", board, bucket)
		end
		deep[board] = math.max(deep[board] or 0, row)
		return { ok = true }
	end
	return { ok = false, reason = "BadRequest" }
end

local function buildStands()
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	local face = Vector3.new(LB.FaceSize[1], LB.FaceSize[2], LB.FaceSize[3])
	local legH = LB.LiftStuds + face.Y / 2
	for _, stand in LB.Stands do
		local model = Instance.new("Model")
		model.Name = stand.Board
		local base = CFrame.new(stand.X, 0, stand.Z)
			* CFrame.Angles(0, math.rad(stand.YawDegrees), 0)
		local function part(
			name: string,
			size: Vector3,
			at: CFrame,
			tone: { number },
			wood: boolean
		): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.Size = size
			p.CFrame = base * at
			p.Color = color(tone)
			p.Material = if wood then Enum.Material.Wood else Enum.Material.SmoothPlastic
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.CastShadow = true
			p.Parent = model
			return p
		end
		local board =
			part("Face", face, CFrame.new(0, LB.LiftStuds + face.Y / 2, 0), LB.FaceColor, false)
		board.CanCollide = false -- the legs hold it up; nobody snags on the board's edge
		board.CanQuery = true
		board.CanTouch = false
		for side = -1, 1, 2 do
			local x = side * (face.X / 2 - LB.LegInsetStuds)
			part(
				"Leg",
				Vector3.new(LB.LegSize[1], legH, LB.LegSize[2]),
				CFrame.new(x, legH / 2, face.Z / 2 + LB.LegSize[2] / 2),
				LB.WoodColor,
				true
			)
			part(
				"Foot",
				Vector3.new(LB.FootSize[1], LB.FootSize[2], LB.FootSize[3]),
				CFrame.new(x, LB.FootSize[2] / 2, face.Z / 2 + LB.LegSize[2] / 2),
				LB.WoodColor,
				true
			)
		end
		model.PrimaryPart = board
		model.Parent = folder
	end
	folder.Parent = workspace
end

local function startLobbyBoards(isLobby: boolean)
	Players.PlayerRemoving:Connect(function(player: Player)
		unwatch(player)
		seen[player] = nil
		deepest[player] = nil
		requestBuckets[player] = nil
	end)
	-- The tally: every server.
	task.spawn(function()
		while true do
			task.wait(LB.TallySeconds)
			local ok, err = pcall(function()
				flushTally()
			end)
			if not ok then
				complain("the tally", err)
			end
		end
	end)
	game:BindToClose(function()
		pcall(flushTally)
	end)
	if not isLobby then
		return
	end
	buildStands()
	local read = Net.get("LeaderboardRead") :: RemoteFunction
	read.OnServerInvoke = function(player: Player, kind: any, a: any, b: any): any
		local ok, result = pcall(onRead, player, kind, a, b)
		if ok then
			return result
		end
		complain("a read request", result)
		return { ok = false, reason = "Error" }
	end
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				readWins(true)
				readCountries()
				listsAt = os.time()
			end)
			if not ok then
				complain("the lobby read", err)
			end
			task.wait(LB.TopReadSeconds)
		end
	end)
	task.spawn(function()
		task.wait(5) -- after the first page
		while true do
			local ok, err = pcall(function()
				readWins(false)
			end)
			if not ok then
				complain("the later pages", err)
			end
			task.wait(LB.DeepReadSeconds)
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

--- Starts the writes, reads and the signs (Bootstrap calls this once); `isLobby` builds the
--- lobby boards there (Config.Leaderboards.Lobby).
function Leaderboards.start(isLobby: boolean?)
	if started then
		return
	end
	started = true
	local lobbyBoards = LB.Enabled == true
	remote = Net.get("Leaderboards")
	if L.SignsOn then
		buildSigns()
	end
	PlayerData.Loaded:Connect(function(player: Player)
		if lobbyBoards then
			watchWins(player)
		end
		task.spawn(function()
			write(player)
			local r = remote
			if r and player.Parent == Players and not lobbyBoards then
				r:FireClient(player, payload())
			end
		end)
	end)
	if lobbyBoards then
		startLobbyBoards(isLobby == true)
	end
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
	-- Reads: the top of each board, to everyone (the lobby boards read their own instead).
	if lobbyBoards then
		return
	end
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
