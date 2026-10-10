--!strict
-- UltSpinState: the client's copy of the ult spin screen's state (docs/prompts/ULTIMATES_PROMPT.md
-- sections 8-10; the server is src/server/UltSpins.luau, the payload Ults/SpinView.Payload).
-- It listens to UltState (the snapshot, on load and after every change), keeps the latest
-- snapshot and asks through the UltRequest RemoteFunction. It never decides anything: every spin, slot,
-- lock and purchase is the server's, and a request names a kind and its choices only.
--
-- Started early by MenuColumn (and by UltScreen), so the snapshot sent on load is heard:
-- Roblox holds a remote's events until something listens.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

export type Reply = { [string]: any }

local UltSpinState = {}

local changed = Instance.new("BindableEvent")

--- Fires with the new snapshot whenever one arrives (UltState, or a reply that carried one).
UltSpinState.Changed = changed.Event

local started = false
local latest: any = nil
local inFlight = false

local function take(payload: any)
	if type(payload) ~= "table" then
		return
	end
	latest = payload
	changed:Fire(payload)
end

--- Listen to UltState (once; the remote is waited for in its own thread).
function UltSpinState.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local ok, remote = pcall(Net.get, "UltState")
		if ok and typeof(remote) == "Instance" and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(take)
		else
			warn("[8ball] UltSpinState: no UltState remote")
		end
	end)
end

--- The latest snapshot, or nil before the first.
function UltSpinState.get(): any?
	return latest
end

--- Whether the spin screen is open to this player (UltState.live: Config.Ults.ScreenLive,
--- Studio, or the developer flag). False before the first snapshot.
function UltSpinState.isLive(): boolean
	return type(latest) == "table" and latest.live == true
end

--- Whether today's free spin is unused (the UltFreeSpin attribute, else the snapshot).
function UltSpinState.freeSpinReady(): boolean
	local player = Players.LocalPlayer
	local value = if player then player:GetAttribute("UltFreeSpin") else nil
	if type(value) == "boolean" then
		return value
	end
	return type(latest) == "table" and latest.freeSpinReady == true
end

--- Whether a request is on its way.
function UltSpinState.isBusy(): boolean
	return inFlight
end

--- Ask the server (UltRequest): `kind` and its small table of choices, as Net.luau and
--- Ults/SpinView describe them. Yields until the answer; never errors. The reply always has
--- `ok`, and `reason` whenever ok is false ("Network" when the server did not answer in
--- time, "Busy" when another request of ours is still on its way). A reply's `state` becomes
--- the latest snapshot.
function UltSpinState.request(kind: string, args: any?): Reply
	if inFlight then
		return { ok = false, reason = "Busy" }
	end
	local got, remote = pcall(Net.get, "UltRequest")
	if not got or typeof(remote) ~= "Instance" or not remote:IsA("RemoteFunction") then
		return { ok = false, reason = "Network" }
	end
	local fn = remote :: RemoteFunction
	inFlight = true
	local done = false
	local answer: any = nil
	local signal = Instance.new("BindableEvent")
	task.spawn(function()
		local ok, reply = pcall(fn.InvokeServer, fn, kind, args)
		if done then
			return
		end
		done = true
		answer = if ok then reply else nil
		signal:Fire()
	end)
	if not done then
		task.delay(Config.UI.Menu.RequestTimeoutSeconds, function()
			if not done then
				done = true
				signal:Fire()
			end
		end)
		signal.Event:Wait()
	end
	signal:Destroy()
	inFlight = false
	if type(answer) ~= "table" then
		return { ok = false, reason = "Network" }
	end
	local reply: Reply = answer
	if reply.ok ~= true then
		reply.ok = false
		if type(reply.reason) ~= "string" then
			reply.reason = "Error"
		end
	end
	if type(reply.state) == "table" then
		take(reply.state)
	end
	return reply
end

return UltSpinState
