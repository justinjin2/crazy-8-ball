--!strict
-- Server bootstrap. For the solo MVP the server only builds the table; later it becomes
-- the shot authority (validates inputs, runs Simulation, broadcasts results).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

print(
	("[8ball] server ready. Table %dx%d in, %.2f studs/in"):format(
		Config.Table.LengthInches,
		Config.Table.WidthInches,
		Config.Table.StudsPerInch
	)
)
