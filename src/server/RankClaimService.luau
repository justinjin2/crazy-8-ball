--!strict
-- RankClaimService: rank rewards held until the player claims them in Rank (designer,
-- 2026-10-03; Tutorial/RankClaim). Keeps two player attributes current: RankPending (true
-- while something waits: the Rank button's dot and glow) and RankTag (the tier whose chat tag
-- shows: the claimed one, since the tag is one of the rewards). Answers the RankClaim remote:
-- pays everything held in one save change and tells the client what flew where.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Inventory = require(Shared.Progression.Inventory)
local RankClaim = require(Shared.Tutorial.RankClaim)
local PlayerData = require(script.Parent.PlayerData)
local Counters = require(script.Parent.Counters)
local Funnel = require(script.Parent.Funnel)

local RankClaimService = {}

local Config = require(Shared.Config)

local MIN_GAP_SECONDS = Config.Tutorial.RankClaim.MinGapSeconds
local lastClaim: { [Player]: number } = {}

local function refresh(player: Player)
	local pending = PlayerData.rankPending(player)
	if pending == nil then
		return
	end
	player:SetAttribute("RankPending", RankClaim.any(pending))
	player:SetAttribute("RankTag", RankClaim.tagTier(PlayerData.flag(player, "RankClaimed")))
	-- The claim block works out the chips from this and PeakDivision.
	local claimed = PlayerData.flag(player, "RankClaimed")
	player:SetAttribute("RankClaimed", if type(claimed) == "number" then claimed else nil)
end

local function onClaim(player: Player)
	local now = os.clock()
	if now - (lastClaim[player] or -math.huge) < MIN_GAP_SECONDS then
		return
	end
	lastClaim[player] = now
	local before = PlayerData.read(player)
	if before == nil then
		return
	end
	local owned: { [string]: number } = {}
	local preview = RankClaim.pending(before.Flags.RankClaimed, before.PeakDivision)
	for _, cue in preview.cues do
		owned[cue] = Inventory.count(before, cue)
	end
	local paid = PlayerData.claimRank(player)
	if paid == nil then
		Net.get("RankClaim"):FireClient(player, { ok = false })
		return
	end
	-- The tier cues it gave count in the copies in existence (an Exclusive cue already owned
	-- is skipped by PlayerData), as Ranking does for a rank-up.
	local after = PlayerData.read(player)
	if after then
		for cue, count in owned do
			local gained = Inventory.count(after, cue) - count
			if gained > 0 then
				Counters.add(cue, gained)
			end
		end
	end
	Net.get("RankClaim"):FireClient(player, {
		ok = true,
		money = paid.money,
		cases = paid.cases,
		drops = paid.drops,
		cues = paid.cues,
		spins = paid.spins,
		rows = paid.rows,
	})
	Funnel.onboarding(player, "ClaimedRank")
end

--- Wires the remote and the attributes. Call after PlayerData.start.
function RankClaimService.start()
	Net.get("RankClaim").OnServerEvent:Connect(onClaim)
	PlayerData.Loaded:Connect(refresh)
	PlayerData.Changed:Connect(function(player: Player)
		refresh(player)
	end)
	for _, player in Players:GetPlayers() do
		if PlayerData.isLoaded(player) then
			refresh(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastClaim[player] = nil
	end)
end

return RankClaimService
