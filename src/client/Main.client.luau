--!strict
-- Client entry point. Wires the systems together; each system is its own module.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

print(("[8ball] client ready. Camera aim mode: %s"):format(Config.Camera.AimMode))
