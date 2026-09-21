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
