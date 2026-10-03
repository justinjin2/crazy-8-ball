--!strict
-- LiveCodes: the Live promo codes switched on in a live game (the like milestone codes,
-- Config.Daily.Codes rows with Live = true; designer, 2026-10-03). The designer types
-- `/code on <CODE>` and every server takes it at once, with no republish.
--
-- One DataStore key ("On" in Config.Daily.LiveStore) holds the set { [CODE] = true }; a switch
-- is an UpdateAsync (Daily.setLive) and then a MessagingService message (LiveTopic) so every
-- server reads the key again; every LiveReadSeconds each server reads it anyway, in case a
-- message was missed. Studio without DataStore access keeps the set in memory.
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Daily = require(Shared.Progression.Daily)

local D = Config.Daily
local IS_STUDIO = RunService:IsStudio()
local KEY = "On"

local LiveCodes = {}

local started = false
local store: DataStore? = nil
local storeTried = false
-- The set as last read (or switched here).
local on: { [string]: boolean } = {}
-- When the last warning of each kind was logged (os.clock), so a failing store is not spam.
local lastWarn: { [string]: number } = {}

local function complain(what: string, err: any)
	local now = os.clock()
	if now - (lastWarn[what] or -math.huge) >= 60 then
		lastWarn[what] = now
		warn(("[8ball] LiveCodes: %s failed: %s"):format(what, tostring(err)))
	end
end

-- The store, or nil when DataStores cannot be reached (Studio without API access).
local function storeOf(): DataStore?
	if storeTried then
		return store
	end
	storeTried = true
	local name = if IS_STUDIO then D.LiveStudioStore else D.LiveStore
	local ok, result = pcall(function(): DataStore
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		store = result
	else
		complain("opening " .. name, result)
	end
	return store
end

-- Reads the set from the store. Yields. True when it was read.
local function read(): boolean
	local s = storeOf()
	if s == nil then
		return false
	end
	local ok, value = pcall(function(): any
		return s:GetAsync(KEY)
	end)
	if not ok then
		complain("reading the codes", value)
		return false
	end
	on = Daily.readLive(value)
	return true
end

--- The Live codes switched on now, as a fresh { [CODE] = true }.
function LiveCodes.on(): { [string]: boolean }
	return table.clone(on)
end

--- Every Live code in Config, sorted.
function LiveCodes.all(): { string }
	local list: { string } = {}
	for code in D.Codes do
		if Daily.isLive(code) then
			table.insert(list, code)
		end
	end
	table.sort(list)
	return list
end

--- Switches Live code `code` on or off in every server (the /code dev command; the command
--- checks the caller). Yields. Returns false when it is not a Live code or could not be saved.
function LiveCodes.set(code: string, value: boolean): boolean
	if not Daily.isLive(code) then
		return false
	end
	local s = storeOf()
	local saved = false
	if s ~= nil then
		local ok, err = pcall(function(): any
			return s:UpdateAsync(KEY, function(stored: any): any
				return Daily.setLive(stored, code, value)
			end)
		end)
		if ok then
			saved = true
		else
			complain("saving the codes", err)
		end
	end
	if not saved then
		if not IS_STUDIO then
			return false
		end
		-- Studio without DataStores: this server only.
		on = Daily.setLive(on, code, value) or on
		return true
	end
	on = Daily.setLive(on, code, value) or on
	local ok, err = pcall(function()
		MessagingService:PublishAsync(D.LiveTopic, code)
	end)
	if not ok then
		complain("telling the other servers", err)
	end
	return true
end

--- Reads the set, listens for switches from other servers and re-reads every
--- LiveReadSeconds (Bootstrap calls this once).
function LiveCodes.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local ok, err = pcall(function(): any
			return MessagingService:SubscribeAsync(D.LiveTopic, function()
				read()
			end)
		end)
		if not ok then
			complain("listening for switches", err)
		end
	end)
	task.spawn(function()
		while true do
			read()
			task.wait(D.LiveReadSeconds)
		end
	end)
end

return LiveCodes
