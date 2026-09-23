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
		-- Measured on a full-power break: nine contacts clear the threshold inside one 90ms
		-- window. The ceiling has to allow those, and the window has to be wide enough to
		-- hold them.
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
