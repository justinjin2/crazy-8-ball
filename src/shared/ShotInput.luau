--!strict
-- ShotInput: pure validation and replay-seed preparation shared by the server and tests.
-- Ownership stays with server services: an ability id needs explicit authorization here.

local Config = require(script.Parent.Config)
local Ball = require(script.Parent.Physics.Ball)
local Cue = require(script.Parent.Physics.Cue)

local ShotInput = {}

export type Seed = { vx: number, vy: number, wx: number, wy: number, wz: number }

function ShotInput.isFinite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

--- Return a fresh, bounded shot. No client-supplied material coefficients are accepted.
--- `authorizedAbility` comes from server ownership/cooldown checks, never the payload.
function ShotInput.validate(payload: any, authorizedAbility: string?): (Cue.Shot?, string?)
	if type(payload) ~= "table" then
		return nil, "payload is not a table"
	end
	if not ShotInput.isFinite(payload.angle) then
		return nil, "angle is not finite"
	end
	if not ShotInput.isFinite(payload.power) then
		return nil, "power is not finite"
	end
	if payload.power < Config.Input.MinPowerToShoot or payload.power > 1 then
		return nil, "power out of range"
	end
	local sx, sy = 0, 0
	if payload.spin ~= nil then
		if type(payload.spin) ~= "table" then
			return nil, "spin is not a table"
		end
		if not ShotInput.isFinite(payload.spin.x) or not ShotInput.isFinite(payload.spin.y) then
			return nil, "spin is not finite"
		end
		sx, sy = Cue.clampSpin(payload.spin.x, payload.spin.y)
	end
	local elevation = Config.Cue.CueElevationDegrees
	if payload.elevation ~= nil then
		if not ShotInput.isFinite(payload.elevation) then
			return nil, "elevation is not finite"
		end
		if payload.elevation ~= elevation then
			return nil, "cue elevation is fixed"
		end
	end
	if payload.overrides ~= nil then
		return nil, "material overrides are server-owned"
	end
	local ability = payload.ability
	if ability ~= nil then
		if type(ability) ~= "string" or ability ~= authorizedAbility then
			return nil, "ability is not authorized"
		end
		local material = Config.Physics.ShotMaterials[ability]
		if material == nil then
			return nil, "unknown ability material"
		end
		for _, name in { "RailRestitution", "RailFriction" } do
			local coefficient = material[name]
			if
				coefficient ~= nil
				and (not ShotInput.isFinite(coefficient) or coefficient < 0 or coefficient > 1)
			then
				return nil, "ability material is out of range"
			end
		end
	end
	return {
		angle = payload.angle % (2 * math.pi),
		power = payload.power,
		spin = { x = sx, y = sy },
		elevation = elevation,
		ability = ability,
	},
		nil
end

--- Quantise in place before the server integrates, then return exactly what goes on wire.
function ShotInput.quantiseSeed(cue: Ball.Ball): Seed
	local function quantise(value: number): number
		local places = Config.Physics.SeedPlaces
		return math.floor(value * places + 0.5) / places
	end
	cue.vx, cue.vy = quantise(cue.vx), quantise(cue.vy)
	cue.wx, cue.wy, cue.wz = quantise(cue.wx), quantise(cue.wy), quantise(cue.wz)
	return { vx = cue.vx, vy = cue.vy, wx = cue.wx, wy = cue.wy, wz = cue.wz }
end

return ShotInput
