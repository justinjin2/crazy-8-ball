--!strict
-- HubDecor: the client's own touches to the hub map. While the player is seated at a table,
-- that table's pendant is hidden for them alone (LocalTransparencyModifier), so it never
-- hangs between the pool camera and the balls. Everyone else still sees it lit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HubDecor = {}

local hidden: Model? = nil

local function setHidden(model: Model, value: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = value
		end
	end
end

--- Call every frame with the table the player is seated at (nil when not seated). The
--- pendant may still be streaming in, so it is looked up until found.
function HubDecor.update(seatId: number?)
	local want: Model? = nil
	if seatId then
		local map = workspace:FindFirstChild(Config.HubMap.Folder)
		local props = map and map:FindFirstChild("Props")
		local found = props and props:FindFirstChild(Config.HubMap.PendantPrefix .. seatId)
		if found and found:IsA("Model") then
			want = found
		end
	end
	if want == hidden then
		return
	end
	if hidden and hidden.Parent then
		setHidden(hidden, 0)
	end
	hidden = want
	if want then
		setHidden(want, 1)
	end
end

return HubDecor
