--!strict
-- Smoke tests for the harness itself and the Config module.

local H = require("./harness")

return {
	["Config loads through the fake instance tree"] = function()
		local Config = H.require("Config")
		H.expect(Config.Table.StudsPerInch > 0, "StudsPerInch must be positive")
		H.near(Config.Table.LengthInches / Config.Table.WidthInches, 2, 1e-9, "9-foot table is 2:1")
		H.expect(Config.Physics.BallRestitution <= 1, "restitution above 1 would create energy")
		H.expect(Config.Physics.RailRestitution <= 1, "restitution above 1 would create energy")
	end,

	["shared modules cannot see Roblox globals"] = function()
		local clean = H.evalInModuleEnv([[
			return game == nil and workspace == nil and Vector3 == nil and CFrame == nil
				and task == nil and Instance == nil and os == nil
		]])
		H.expect(clean == true, "a Roblox global leaked into the module environment")
	end,

	["shared modules can require each other via script.Parent"] = function()
		local Config = H.evalInModuleEnv("return require(script.Parent.Config)")
		H.expect(
			type(Config) == "table" and Config.Balls.RadiusInches == 1.125,
			"require via script.Parent failed"
		)
	end,
}
