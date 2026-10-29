--!strict
-- The custom-model path (Halloween 2026, docs/prompts/HW_CUES_A_PROMPT.md 2.4): a cue drawn by
-- its own body piece over the hidden shared mesh. The body rules on every Index Body and on the
-- Cues A bodies' piece.json files (checked while their skins are still draft), CueSkins.bodyOf
-- (the one decision) and the Aim joint key Motion.rig keeps.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local H = require("./harness")

-- The mesh frame: the tip sits at Z = +3.5, the butt at Z = -3.5 (Z = 3.5 - AtStuds).
local TIP_Z, BUTT_Z = 3.5, -3.5

-- A piece row or piece.json spec, in the shape both share (Frame, Parts with Offset/Size/Joint,
-- Joints with Parent/Aura/Low/Aim).
local function checkBody(name: string, spec: any, B: any)
	H.expect(spec.Frame == "cue", name .. ": a body is built in the cue frame")
	H.expect(
		#spec.Parts <= B.MaxParts,
		("%s: %d parts, at most %d"):format(name, #spec.Parts, B.MaxParts)
	)
	-- Aim joints, by inheritance.
	local aim: { [string]: boolean } = {}
	local function isAim(j: string): boolean
		if aim[j] == nil then
			local joint = spec.Joints[j]
			aim[j] = joint ~= nil
				and (joint.Aim == "fade" or (joint.Parent ~= nil and isAim(joint.Parent)))
		end
		return aim[j]
	end
	for jname, joint in spec.Joints do
		H.expect(joint.Aura ~= true, ("%s: body joint %s must not be Aura"):format(name, jname))
		H.expect(
			joint.Low ~= "hide",
			("%s: body joint %s must not hide under Lower effects"):format(name, jname)
		)
	end
	local front = -math.huge
	for _, part in spec.Parts do
		H.expect(
			spec.Joints[part.Joint] ~= nil,
			("%s: part %s names the unknown joint %s"):format(name, part.Name, tostring(part.Joint))
		)
		local z0 = part.Offset[3] - part.Size[3] / 2
		local z1 = part.Offset[3] + part.Size[3] / 2
		front = math.max(front, z1)
		-- Nothing past the tip (2026-10-29, the Pitchfork's fork at the tip): the tip is what
		-- meets the ball, so a part reaching further would go through the cue ball.
		H.expect(
			z1 <= TIP_Z + B.TipSlackStuds + 1e-4,
			("%s: part %s reaches %.3f studs past the tip (at most %.2f)"):format(
				name,
				part.Name,
				z1 - TIP_Z,
				B.TipSlackStuds
			)
		)
		local limit = if isAim(part.Joint) then B.MaxOverhangStuds else B.PastButtStuds
		H.expect(
			z0 >= BUTT_Z - limit - 1e-4,
			("%s: part %s ends %.2f studs past the butt (at most %.2f%s)"):format(
				name,
				part.Name,
				BUTT_Z - z0,
				limit,
				if isAim(part.Joint) then ", Aim" else ""
			)
		)
	end
	H.expect(
		front >= TIP_Z - B.TipSlackStuds - 1e-4,
		("%s: the body stops %.3f studs short of the tip"):format(name, TIP_Z - front)
	)
end

return {
	["every Index Body has a cue-frame piece row within the body rules"] = function()
		local Config = H.require("Config")
		local CueSkins = H.require("CueSkins")
		local B = Config.CueSkins.Bodies
		local bodies = 0
		for _, id in CueSkins.ids() do
			local index = CueSkins.index(id)
			local row = CueSkins.get(id)
			H.expect(index.Body == row.Body, id .. ": the Index and the row agree on the Body")
			if row.Body then
				bodies += 1
				local piece = CueSkins.piece(row.Body)
				H.expect(piece ~= nil, id .. ": body piece " .. tostring(row.Body) .. " has no row")
				checkBody(id .. "/" .. row.Body, piece, B)
			end
		end
		-- The Halloween 2026 skins may still be draft (no row yet); nothing else has a Body
		-- (Cues A: the Candy Corn, the Jack and the Halloween Sword; Cues B: its three).
		H.expect(bodies <= 6, "only the six event cues have bodies")
	end,

	["the Cues A bodies' piece.json files obey the body rules (checked while draft)"] = function()
		local Config = H.require("Config")
		local B = Config.CueSkins.Bodies
		for _, pid in { "jack_o_lantern" } do
			local path = ("assets/cue/pieces/%s/piece.json"):format(pid)
			H.expect(fs.isFile(path), path .. " exists")
			local spec = serde.decode("json", fs.readFile(path))
			checkBody(pid, spec, B)
		end
		-- The pocket piece is not a body: its own frame, no body rules.
		local pocket =
			serde.decode("json", fs.readFile("assets/cue/pieces/jack_o_lantern_pocket/piece.json"))
		H.expect(pocket.Frame == "pocket", "jack_o_lantern_pocket is a pocket piece")
		H.expect(
			pocket.Joints.Jaw ~= nil and pocket.Joints.Jaw.Parent == "Skull",
			"the jaw hinges on the skull"
		)
	end,

	["CueSkins.bodyOf: no Body, the switch off, the template missing, present"] = function()
		local CueSkins = H.require("CueSkins")
		local Index = H.require("CueSkins.Index")
		local function has(set: { [string]: boolean }): (string) -> boolean
			return function(name: string): boolean
				return set[name] == true
			end
		end
		H.expect(CueSkins.bodyOf("EclipseCue", has({}), true) == nil, "a cue with no Body")
		H.expect(CueSkins.bodyOf("NoSuchCue", has({}), true) == nil, "an unknown id")
		H.expect(CueSkins.bodyOf(nil, has({}), true) == nil, "nil")
		-- A stand-in Index row with a shipped Body row (the harness shares the module table;
		-- since the robustness pass a body also needs its data row, so a real one is used).
		Index.BodyTestCue = {
			Id = "body_test",
			Name = "Body Test",
			Tier = "Epic",
			Thumb = "",
			Look = {},
			Body = "jack_o_lantern",
		}
		H.expect(CueSkins.index("BodyTestCue") ~= nil, "the stand-in row is seen")
		H.expect(
			CueSkins.bodyOf("BodyTestCue", has({ jack_o_lantern = true }), true) == "jack_o_lantern",
			"present"
		)
		H.expect(
			CueSkins.bodyOf("BodyTestCue", has({ jack_o_lantern = true }), false) == nil,
			"the switch off"
		)
		H.expect(CueSkins.bodyOf("BodyTestCue", has({}), true) == nil, "the template missing")
		Index.BodyTestCue = nil
	end,

	["CueSkins.bodyOf: a template with no data row is no body (robustness pass)"] = function()
		local CueSkins = H.require("CueSkins")
		local Index = H.require("CueSkins.Index")
		local function has(set: { [string]: boolean }): (string) -> boolean
			return function(name: string): boolean
				return set[name] == true
			end
		end
		-- A real piece row (jack_o_lantern) with its template: a body. The same stand-in with a
		-- body whose row does not exist, template present: no body, so the mesh stays shown.
		H.expect(CueSkins.piece("jack_o_lantern") ~= nil, "the Jack body row is shipped")
		Index.BodyRowTestCue = {
			Id = "body_row_test",
			Name = "Body Row Test",
			Tier = "Epic",
			Thumb = "",
			Look = {},
			Body = "jack_o_lantern",
		}
		H.expect(
			CueSkins.bodyOf("BodyRowTestCue", has({ jack_o_lantern = true }), true)
				== "jack_o_lantern",
			"row and template: the body"
		)
		Index.BodyRowTestCue.Body = "no_such_piece_row"
		H.expect(
			CueSkins.bodyOf("BodyRowTestCue", has({ no_such_piece_row = true }), true) == nil,
			"template without a row: no body"
		)
		Index.BodyRowTestCue = nil
	end,

	["Motion.rig keeps a joint's Aim key, and the body config numbers make sense"] = function()
		local Motion = H.require("CueSkins.Motion")
		local Config = H.require("Config")
		local rig = Motion.rig({
			Frame = "cue",
			Joints = {
				A = { Parent = nil, PivotRoblox = { 0, 0, 0 }, Aim = "fade" },
				B = { Parent = "A", PivotRoblox = { 0, 0, 0 } },
			},
		})
		H.expect(rig.joints.A.aim == "fade", "A keeps Aim")
		H.expect(rig.joints.B.aim == nil, "B has none of its own")
		local B = Config.CueSkins.Bodies
		H.expect(type(B.Enabled) == "boolean" and type(B.Outline) == "boolean", "the switches")
		H.expect(
			B.MaxParts >= 1 and B.PastButtStuds > 0 and B.MaxOverhangStuds >= B.PastButtStuds,
			"the limits"
		)
		H.expect(B.AimFadeSeconds > 0 and B.TipSlackStuds > 0, "the times and slack")
	end,
}
