--!strict
-- Smoke tests for the harness itself and the Config module.

local H = require("./harness")

return {
	["Config loads through the fake instance tree"] = function()
		local Config = H.require("Config")
		H.expect(Config.Table.StudsPerInch > 0, "StudsPerInch must be positive")
		H.near(Config.Table.LengthInches / Config.Table.WidthInches, 2, 1e-9, "pool tables are 2:1")
		H.expect(
			Config.Table.CornerMouthInches > 2 * Config.Balls.RadiusInches * 1.5,
			"corner mouth must fit a ball easily"
		)
		H.expect(Config.Physics.BallRestitution <= 1, "restitution above 1 would create energy")
		H.expect(Config.Physics.RailRestitution <= 1, "restitution above 1 would create energy")
	end,

	["the home view sits strictly inside the zoom range"] = function()
		local V = H.require("Config").Camera.View
		-- The camera fits the whole-table end of the zoom clear of the match HUD, blended in
		-- from the home view up to ZoomMax. A home view at either end would make that blend
		-- all or nothing, and would leave the player no room to zoom one way.
		H.expect(V.ZoomMin < V.ZoomDefault, "the home view must be further out than the close view")
		H.expect(V.ZoomDefault < V.ZoomMax, "the home view must be closer than the whole table")
	end,

	["the audio config cannot silently clip its own loudest sound"] = function()
		local Config = H.require("Config")
		local SoundMix = H.require("SoundMix")
		local A = Config.Audio

		H.expect(A.QuietSpeed < A.LoudSpeed, "the speed range must run upward")
		H.expect(A.Roll.MinSpeed < A.Roll.LoudSpeed, "the roll speed range must run upward")
		local previous = 0
		for _, speed in A.Roll.TierSpeeds do
			H.expect(speed > previous, "tier boundaries must ascend")
			previous = speed
		end

		-- The roll's first tier carries a large gain, because its recording is much quieter
		-- than the others. Raise Roll.MaxVolume far enough and that gain pushes past the
		-- clamp, which would silently flatten the top of the roll with nothing to say so.
		local loudestTierSpeed = A.Roll.TierSpeeds[1] + A.Roll.TierMargin
		for tier, clips in A.Roll.Tiers do
			for _, clip in clips do
				local speed = if tier == 1 then loudestTierSpeed else A.Roll.LoudSpeed
				local k = SoundMix.loudness(speed, A.Roll.MinSpeed, A.Roll.LoudSpeed)
				local peak = A.Roll.MaxVolume * k * clip.Gain
				H.expect(
					peak <= A.MaxVolume,
					("roll tier %d reaches %.2f against a clamp of %.2f"):format(
						tier,
						peak,
						A.MaxVolume
					)
				)
			end
		end

		-- Same for the one-shots: every band at its loudest, times its loudest clip.
		for name, clips in A.Clips do
			local band = (A :: any)[({
				CueStrike = "Strike",
				BallClack = "Clack",
				RailThud = "Rail",
				PocketDrop = "Pocket",
				PocketBonus = "Bonus",
				AimTick = "Tick",
			} :: any)[name]]
			local gain = 0
			for _, clip in clips do
				gain = math.max(gain, clip.Gain)
			end
			H.expect(
				band.MaxVolume * gain <= A.MaxVolume,
				("%s reaches %.2f against a clamp of %.2f"):format(
					name,
					band.MaxVolume * gain,
					A.MaxVolume
				)
			)
		end
	end,

	["the three strike takes land where the power bar says they do"] = function()
		local Config = H.require("Config")
		local SoundMix = H.require("SoundMix")
		local Cue = H.require("Physics.Cue")
		local A = Config.Audio
		local clips = A.Clips.CueStrike
		H.expect(#clips == 3, ("expected three strike takes, found %d"):format(#clips))

		-- The bands are written as power fractions; what pickBanded sees is speed. These have
		-- to agree, or the lines move without anyone touching them.
		H.near(
			clips[1].UpToSpeed,
			Cue.speedForPower(A.StrikeSoftUpToPower),
			1e-9,
			"the soft band does not end where the power fraction says"
		)
		H.near(
			clips[3].FromSpeed,
			Cue.speedForPower(A.StrikeHardFromPower),
			1e-9,
			"the hard band does not start where the power fraction says"
		)

		-- Inside each band, only that take may play, whatever the roll.
		local function only(power: number, want: number)
			local speed = Cue.speedForPower(power)
			for step = 0, 40 do
				local i = SoundMix.pickBanded(clips, speed, nil, step / 41)
				H.expect(
					i == want,
					("power %.2f (%.1f in/s) picked take %d, wanted %d"):format(
						power,
						speed,
						i,
						want
					)
				)
			end
		end
		for _, p in { 0, 0.05, 0.15, 0.24 } do
			only(p, 1)
		end
		for _, p in { 0.26, 0.4, 0.6, 0.74 } do
			only(p, 2)
		end
		for _, p in { 0.76, 0.9, 1.0 } do
			only(p, 3)
		end

		-- Nothing may fall through a gap: at every power the band the speed lands in must be
		-- a real one, never the "no band matched, use everything" fallback.
		for step = 0, 200 do
			local speed = Cue.speedForPower(step / 200)
			local eligible = 0
			for _, c in clips do
				local from = c.FromSpeed or -math.huge
				local upTo = c.UpToSpeed or math.huge
				if speed >= from and speed <= upTo then
					eligible += 1
				end
			end
			H.expect(
				eligible >= 1,
				("power %.3f (%.1f in/s) matches no strike band"):format(step / 200, speed)
			)
		end
	end,

	["a gentle touch plays the soft take, and is not silenced"] = function()
		local Config = H.require("Config")
		local SoundMix = H.require("SoundMix")
		local A = Config.Audio

		-- Measured over 48 shots: the median ball-on-ball contact is 3.6 in/s and 66% of them
		-- are under 12. A floor above that silences most of the game's contacts, which is
		-- exactly the bug this guards.
		H.expect(A.MinClackSpeed <= 4, "the clack floor must sit below the median contact")
		-- ...but not so low that two balls already touching, re-detected, start buzzing.
		H.expect(A.MinClackSpeed > 0.05, "resting contacts must stay silent")

		-- The soft take is clips[1]. At a gentle speed it must be the ONLY one eligible, or a
		-- ball rolling into another one thuds instead of clicking.
		for _, speed in { 0.5, 1, 2, 3, 5 } do
			for step = 0, 40 do
				local i = SoundMix.pickBanded(A.Clips.BallClack, speed, nil, step / 41)
				H.expect(
					i == 1,
					("%.1f in/s should pick the soft take, picked %d"):format(speed, i)
				)
			end
		end
		-- And at a firm speed it must NOT be chosen: it is a recording of a gentle contact.
		for step = 0, 40 do
			local i = SoundMix.pickBanded(A.Clips.BallClack, 120, nil, step / 41)
			H.expect(i ~= 1, "a firm contact must not pick the soft take")
		end
		-- In between, every take is reachable, which is what blends one into the other.
		local seen = {}
		for step = 0, 300 do
			seen[SoundMix.pickBanded(A.Clips.BallClack, 12, nil, step / 301)] = true
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		H.expect(
			n == #A.Clips.BallClack,
			("the overlap should reach all takes, reached %d"):format(n)
		)

		-- A gentle contact must actually be audible, not sitting at zero.
		local volume = SoundMix.mix(A.Clack, A.MinClackSpeed, A.QuietSpeed, A.LoudSpeed)
		H.expect(
			volume > 0.02,
			("the quietest clack plays at %.3f, which is inaudible"):format(volume)
		)
	end,

	["a break can stack, and ordinary play cannot"] = function()
		local Config = H.require("Config")
		local A = Config.Audio
		local C = Config.Cue

		-- Stacking is what turns a break into one crack. It must be out of reach in normal
		-- play, and a contact can never be faster than the ball that struck it - so the cue
		-- ball's speed at a given power is a hard ceiling on whether it can trigger at all.
		local function cueSpeed(power: number): number
			return C.MinSpeed + (C.MaxSpeed - C.MinSpeed) * power ^ C.PowerCurve
		end
		H.expect(cueSpeed(0.5) < A.StackSpeed, "half power must not be able to stack")
		H.expect(cueSpeed(1.0) > A.StackSpeed, "full power must be able to stack")
		-- Measured on a full-power break: nine contacts cleared the threshold inside one 90ms
		-- window with pairwise contacts, and 12-15 inside the first millisecond now the rack
		-- is a soft cluster. The ceiling has to allow at least the nine, and the window has
		-- to be wide enough to hold them.
		H.expect(A.MaxStackedClacks >= 9, "the stack ceiling must fit a real break")
		H.expect(A.StackWindowSeconds >= 0.09, "the window must span a real break's contacts")

		-- Nine voices summing must not run into the per-sound clamp.
		local SoundMix = H.require("SoundMix")
		local loudest = SoundMix.mix(A.Clack, C.MaxSpeed, A.QuietSpeed, A.LoudSpeed)
		local gain = 0
		for _, clip in A.Clips.BallClack do
			gain = math.max(gain, clip.Gain)
		end
		H.expect(
			loudest * gain <= A.MaxVolume,
			("a break clack reaches %.2f against a clamp of %.2f"):format(
				loudest * gain,
				A.MaxVolume
			)
		)
		-- And the stack must fit in the voice pool alongside everything else sounding.
		H.expect(A.MaxVoices > A.MaxStackedClacks * 2, "the pool must hold a stack and more")

		-- Cushions sit right at the back: they are the most frequent contact in the game.
		local railV = SoundMix.mix(A.Rail, 300, A.QuietSpeed, A.LoudSpeed)
		local clackV = SoundMix.mix(A.Clack, 300, A.QuietSpeed, A.LoudSpeed)
		H.expect(
			railV < clackV * 0.2,
			("a rail is only %.1f dB under a clack; it should be far back"):format(
				20 * math.log10(railV / clackV)
			)
		)
	end,

	["the cue's profile runs tip to butt and never narrows"] = function()
		local C = H.require("Config").Cue
		local looks = { Tip = true, Shaft = true, Butt = true }
		local lastTo, lastTaper = 0, 0
		for i, row in C.Profile do
			H.expect(row.To > lastTo, ("Profile row %d does not move toward the butt"):format(i))
			H.expect(row.Taper >= lastTaper, ("Profile row %d narrows"):format(i))
			H.expect(
				row.Taper >= 0 and row.Taper <= 1,
				("Profile row %d taper out of 0..1"):format(i)
			)
			H.expect(
				looks[row.Look] == true,
				("Profile row %d has no colour: %s"):format(i, row.Look)
			)
			lastTo, lastTaper = row.To, row.Taper
		end
		H.expect(lastTo == 1, "the profile must end at the butt (To = 1)")
		H.expect(lastTaper == 1, "the butt end is the butt's diameter")
		H.expect(C.CueTipDiameterStuds < C.CueButtDiameterStuds, "the tip is the narrow end")
		-- The drawn pitch starts at the physics elevation and can only rise from it.
		H.expect(C.VisualPitchMaxDegrees > C.CueElevationDegrees, "no room to tilt")
		H.expect(C.VisualPitchMaxDegrees < 90, "a cue cannot stand on end")
		H.expect(C.VisualRailClearanceInches >= 0 and C.VisualBallClearanceInches >= 0, "gaps")
		H.expect(C.VisualPitchRiseSeconds <= C.VisualPitchFallSeconds, "rise faster than fall")
	end,

	-- Every difficulty says what it draws, the menu lists each once, and the default is one.
	["every difficulty level is complete and the default is one of them"] = function()
		local D = H.require("Config").Difficulty
		H.expect(D.Levels[D.Default] ~= nil, "the default is a level")
		local listed = 0
		for _, name in D.Order do
			local row = D.Levels[name]
			H.expect(row ~= nil, name .. " is a level")
			for _, key in { "Corridor", "Stubs", "Landings" } do
				H.expect(type(row[key]) == "boolean", ("%s.%s"):format(name, key))
			end
			listed += 1
		end
		local count = 0
		for _ in D.Levels do
			count += 1
		end
		H.expect(listed == count, "the menu lists every level")
		H.expect(D.Levels.Challenger.Corridor == false, "Challenger draws no lines")
		H.expect(
			D.Levels.Difficult.Corridor and not D.Levels.Difficult.Stubs,
			"Difficult: aim only"
		)
	end,

	["a body fits between the barrier and the fence at every facing"] = function()
		local Config = H.require("Config")
		local Placement = H.require("Placement")
		local S = Config.Stance
		local body = S.DefaultBody
		-- The worst facing puts the footprint's diagonal across the band.
		local half = math.sqrt(body.HalfDepth ^ 2 + body.HalfWidth ^ 2)
		local grow = math.max(half, Config.Multiplayer.Barrier.ReleaseClearanceStuds)
		local bx, by = Placement.barrierHalfExtents()
		local fx, fy, cx = Placement.fenceHalfExtents()
		-- Both ends: the head reaches cx - fx, the foot cx + fx.
		H.expect(bx + grow <= fx + cx - half - S.FenceMarginStuds, "no room at the foot")
		H.expect(bx + grow <= fx - cx - half - S.FenceMarginStuds, "no room at the head")
		H.expect(by + grow <= fy - half - S.FenceMarginStuds, "no room along the sides")
		H.expect(body.WaistHeight < body.ShoulderHeight, "the torso has a length")
		H.expect(body.RootHeight > 0 and body.ArmReach > 0, "a body")
		H.expect(S.LeanMinDegrees <= S.LeanNaturalDegrees, "natural lean below the most upright")
		H.expect(S.LeanNaturalDegrees <= S.LeanMaxDegrees, "natural lean past the most")
		H.expect(S.ArmNaturalFraction <= S.ArmMaxFraction and S.ArmMaxFraction <= 1, "reach")
		H.expect(S.GripMinFromTipFraction + S.GripFromButtFraction < 1, "the grip has room")
		H.expect(S.SteepGripMinFromTipFraction <= S.GripMinFromTipFraction, "steep chokes up")
		H.expect(body.HipHeight < body.WaistHeight and body.ThighLength > 0, "legs")
		H.expect(S.BridgeMinRiseStuds < S.BridgeMaxRiseStuds, "a bridge has a height range")
		H.expect(S.BridgeFrozenInsetInches < S.BridgeCushionInsetInches, "frozen is closer")
		H.expect(S.MaxBridgeInches >= S.BridgeFromBallInches, "the bridge may reach further")
		H.expect(S.ExtraLeanDegrees[1] == 0, "the least lean is always tried first")
		H.expect(#S.Sides > 0 and S.Sides[1].Cost == 0, "the classic stance comes first")
		H.expect(Config.Aim.PullSteps >= 1 and Config.Aim.PullSteps % 1 == 0, "whole pull steps")
	end,

	-- Config.Ranks (ECONOMY 4): every tier has its rows, and nothing can make XP negative.
	-- The numbers themselves are checked against ECONOMY's tables in tests/ranks_test.
	["the rank config is complete and never takes XP away"] = function()
		local Config = H.require("Config")
		local R = Config.Ranks
		local tiers: { string } = R.Tiers
		local isTier: { [string]: boolean } = {}
		for _, tier in tiers do
			isTier[tier] = true
		end
		local top = tiers[#tiers]
		local division: { [string]: { number } } = R.DivisionXp :: any
		local base: { [string]: { Win: number, Loss: number } } = R.BaseXp :: any
		local steps: { [string]: number } = R.Rewards.Step :: any
		local firsts: { [string]: any } = R.Rewards.Tier :: any
		local caseList: { [string]: any } = Config.Cases.List :: any
		local cues: { [string]: boolean } = {}
		for _, tier in tiers do
			if tier ~= top then
				local widths = division[tier]
				H.expect(widths ~= nil and #widths == R.DivisionsPerTier, tier .. " DivisionXp")
				for _, width in widths do
					H.expect(width > 0 and width % 1 == 0, tier .. " widths are whole and > 0")
				end
				H.expect(type(steps[tier]) == "number" and steps[tier] > 0, tier .. " Step")
			end
			local row = base[tier]
			H.expect(row ~= nil and row.Win > 0, tier .. " BaseXp.Win")
			H.expect(row.Loss >= 0 and row.Loss <= row.Win, tier .. " a loss never costs XP")
			local first = firsts[tier]
			H.expect(first ~= nil and first.Money > 0, tier .. " Rewards.Tier")
			for id, count in first.Cases or {} do
				H.expect(caseList[id] ~= nil, ("%s rewards an unknown case %s"):format(tier, id))
				H.expect(table.find(Config.Cases.Order, id) ~= nil, id .. " is in Cases.Order")
				H.expect(count >= 1 and count % 1 == 0, tier .. " case counts are whole")
			end
			H.expect(
				type(first.Cue) == "string" and not cues[first.Cue],
				tier .. " has its own cue"
			)
			cues[first.Cue] = true
		end
		H.expect(steps[top] == nil, "the top tier has one division, so no steps")
		for tier, fade in R.ClassicWinFade :: any do
			H.expect(isTier[tier] and fade > 0 and fade <= 1, "ClassicWinFade " .. tostring(tier))
		end
		-- Every difficulty has an XP multiplier; Classic is the plain one.
		for _, level in Config.Difficulty.Order do
			H.expect((R.ModeXp :: any)[level] ~= nil, level .. " has a ModeXp")
		end
		H.expect(R.ModeXp.Classic == 1, "Classic XP is x1")
		for level, tier in R.Unlocks :: any do
			H.expect(table.find(Config.Difficulty.Order, level) ~= nil, "Unlocks: " .. level)
			H.expect(isTier[tier], "Unlocks " .. level .. ": " .. tostring(tier))
		end
		H.expect((R.Unlocks :: any).Classic == nil, "anyone may host Classic")
		-- The gap: gentle then strict, never above Max, a loss at most LossMax.
		local G = R.Gap
		H.expect(isTier[G.StrictFromTier], "Gap.StrictFromTier is a tier")
		H.expect(G.Scale > 0 and G.StrictScale > 0, "scales")
		H.expect(G.StrictFloor > 0 and G.StrictFloor <= G.Floor and G.Floor <= 1, "floors")
		H.expect(G.Max >= 1 and G.LossMax >= 0 and G.LossMax <= G.Max, "Max and LossMax")
		H.expect(R.PcXp.High > 0 and R.PcXp.High <= R.PcXp.Low and R.PcXp.Low <= 1, "PcXp")
		local B = R.Boosts
		for _, key in { "Rookie", "Vip", "FirstWin", "Streak" } do
			H.expect((B :: any)[key] >= 0, "Boosts." .. key)
		end
		H.expect(B.RookieMatches >= 1 and B.RookieMatches % 1 == 0, "RookieMatches")
		H.expect(B.StreakFrom == Config.Economy.StreakFrom, "one streak for XP and money")
		-- Rank cues are Exclusive: never traded or sold (ECONOMY 4.8).
		local ok, Catalog = pcall(H.require, "Progression.Catalog")
		if ok and type(Catalog) == "table" and Catalog.get then
			for cue in cues do
				local row = Catalog.get(cue)
				H.expect(row ~= nil, "the catalog has " .. cue)
				H.expect(row.Rarity == "Exclusive", cue .. " is Exclusive")
				H.expect(row.Tradable ~= true and row.Sellable ~= true, cue .. " stays yours")
			end
		end
	end,

	-- Config.Economy (ECONOMY 3): shares are shares, rows are in order, the caps are sane.
	["the money config is complete"] = function()
		local Config = H.require("Config")
		local E = Config.Economy
		H.expect(E.BallPay > 0 and E.WinBonus > E.LossBonus and E.LossBonus > 0, "bonuses")
		H.expect(E.PcWinBonus > E.PcLossBonus and E.PcLossBonus > 0, "PC bonuses")
		H.expect(E.PcWinBonus < E.WinBonus, "PC pays less than people")
		for _, kind in { "Bank", "Kick", "Combo", "Carom" } do
			H.expect((E.NiceShotPay :: any)[kind] > 0, "NiceShotPay." .. kind)
		end
		H.expect(E.WinBonusGapFloor > 0 and E.WinBonusGapFloor <= 1, "WinBonusGapFloor")
		for _, share in { E.SoloShare, E.PcAfterCapShare } do
			H.expect(share > 0 and share <= 1, "a share is in (0, 1]")
		end
		H.expect(E.SoloDailyCap > 0 and E.PcDailyCap > 0 and E.ShortDailyCap > 0, "caps")
		H.expect(E.SoloAfterCapPay >= 1 and E.ShortAfterCapPay >= 1, "never zero a ball")
		H.expect(E.VipBoost >= 0 and E.PartyBoost >= 0, "boosts")
		H.expect(E.StreakBonus > 0 and E.StreakFrom >= 1, "streak")
		-- The same-opponent rows rise in UpTo; only the last has none; shares are shares.
		local rows: { any } = E.SameOpponent :: any
		H.expect(#rows >= 1 and rows[#rows].UpTo == nil, "the last row covers every match after")
		local last = 0
		for i, row in rows do
			if i < #rows then
				H.expect(type(row.UpTo) == "number" and row.UpTo > last, "UpTo rises")
				last = row.UpTo
			end
			for _, key in { "Xp", "Bonus", "Balls" } do
				H.expect(row[key] >= 0 and row[key] <= 1, ("row %d %s"):format(i, key))
			end
			H.expect(type(row.FreeCase) == "boolean", "row FreeCase")
		end
		H.expect(rows[1].Xp == 1 and rows[1].Bonus == 1 and rows[1].Balls == 1, "first row full")
		H.expect(E.SameOpponentMaxEntries >= 1 and E.FreeCasesPerOpponent >= 1, "limits")
		H.expect(E.FreeCaseLoserMinMatches >= 1, "FreeCaseLoserMinMatches")
	end,

	["shared modules cannot see Roblox globals"] = function()
		local clean = H.evalInModuleEnv([[
			return game == nil and workspace == nil and Vector3 == nil and CFrame == nil
				and task == nil and Instance == nil and Enum == nil
		]])
		H.expect(clean == true, "a Roblox global leaked into the module environment")
	end,

	["shared modules can require each other via script.Parent"] = function()
		local Config = H.evalInModuleEnv("return require(script.Parent.Config)")
		H.expect(
			type(Config) == "table" and Config.Balls.RadiusInches > 0,
			"require via script.Parent failed"
		)
	end,
}
