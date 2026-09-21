--!nocheck
-- Measure the real loudness of every clip in Config.Audio, so the Gain numbers there are a
-- measurement rather than a guess.
--
-- WHY THIS EXISTS. Each event picks a clip at random, and the recordings are not equally
-- loud: when this was first run the rail recording peaked at 0.18 while the pocket drops
-- peaked at 0.91, which is 14 dB apart. Left uncorrected, WHICH clip got picked decides how
-- loud the hit sounds, and the speed-driven volume curve is fighting it. Gain levels them so
-- speed is the only thing that sets loudness.
--
-- HOW TO RUN IT. This is not a Lune test - it needs Roblox's audio engine. Paste it into the
-- Studio command bar in EDIT mode (View -> Command Bar), or run it through the Studio MCP
-- with execute_luau. It builds its probe under Workspace, measures, and removes it.
--
-- HOW IT WORKS. It wires each clip through AudioPlayer -> AudioAnalyzer -> AudioFader(0) ->
-- AudioDeviceOutput. The fader is silent so nothing is heard, but the graph still runs and
-- the analyzer sits before it, so it reads the full level.
--
-- READING THE OUTPUT. Use PEAK for one-shots (impacts, where the transient is what you
-- hear) and meanRMS for continuous material (the rolling clips). Gain = target / measured.
-- The targets that produced the numbers currently in Config were 0.5 peak for impacts and
-- 0.055 RMS for rolls. floor dB is the quietest moment relative to the clip's own average:
-- close to 0 means the recording is mostly noise and must not be boosted hard; -10 dB or
-- lower means it has real dynamic structure and will survive a large gain.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

-- Every clip Config knows about, flattened to { label, assetId }.
local clips = {}
for event, list in Config.Audio.Clips do
	for i, clip in list do
		table.insert(clips, { ("%s[%d]"):format(event, i), clip.Id })
	end
end
for tier, list in Config.Audio.Roll.Tiers do
	for i, clip in list do
		table.insert(clips, { ("Roll.T%d[%d]"):format(tier, i), clip.Id })
	end
end

local probe = Instance.new("Folder")
probe.Name = "__AudioLevelProbe"
probe.Parent = workspace
local output = Instance.new("AudioDeviceOutput")
output.Parent = probe

local rigs = {}
for _, row in clips do
	local player = Instance.new("AudioPlayer")
	player.Asset = row[2]
	player.Parent = probe
	local analyzer = Instance.new("AudioAnalyzer")
	analyzer.Parent = probe
	local fader = Instance.new("AudioFader")
	fader.Volume = 0
	fader.Parent = probe
	for _, pair in { { player, analyzer }, { analyzer, fader }, { fader, output } } do
		local wire = Instance.new("Wire")
		wire.SourceInstance, wire.TargetInstance = pair[1], pair[2]
		wire.Parent = probe
	end
	table.insert(rigs, { name = row[1], player = player, analyzer = analyzer, peak = 0, samples = {} })
end

-- Nothing is measured half-loaded.
local deadline = os.clock() + 30
repeat
	local pending = 0
	for _, r in rigs do
		if not r.player.IsReady then
			pending += 1
		end
	end
	if pending == 0 then
		break
	end
	task.wait(0.2)
until os.clock() > deadline

for _, r in rigs do
	r.length = r.player.TimeLength
	r.player:Play()
end

-- Everything plays at once, each into its own analyzer, so this takes as long as the single
-- longest clip rather than the sum of them all.
local stop = os.clock() + 8
repeat
	local live = 0
	for _, r in rigs do
		if r.player.IsPlaying then
			live += 1
			r.peak = math.max(r.peak, r.analyzer.PeakLevel)
			table.insert(r.samples, r.analyzer.RmsLevel)
		end
	end
	if live == 0 and #rigs[1].samples > 0 then
		break
	end
	task.wait()
until os.clock() > stop

local lines =
	{ string.format("%-16s %8s %9s %9s %8s %7s", "clip", "peak", "meanRMS", "floorRMS", "floordB", "len") }
for _, r in rigs do
	local sorted = table.clone(r.samples)
	table.sort(sorted)
	local floor = sorted[math.max(1, math.floor(#sorted * 0.05))] or 0
	local sum = 0
	for _, v in r.samples do
		sum += v
	end
	local mean = if #r.samples > 0 then sum / #r.samples else 0
	local db = if floor > 0 and mean > 0 then 20 * math.log10(floor / mean) else -99
	table.insert(
		lines,
		string.format("%-16s %8.4f %9.5f %9.5f %8.1f %7.3f", r.name, r.peak, mean, floor, db, r.length or 0)
	)
end
table.insert(lines, "")
table.insert(lines, "Gain = 0.5 / peak for impacts, 0.055 / meanRMS for the rolling clips.")

probe:Destroy()
print(table.concat(lines, "\n"))
return table.concat(lines, "\n")
