--!nocheck
-- Transient Studio SERVER art preview. Overrides only the replicated equipped appearance;
-- never grants ownership, touches a profile or changes a sale. A profile refresh can rewrite
-- EquippedCue, so keep the override until this Play session ends or CLEAR is run.
local CUE = "BetaCue"
local CLEAR = false
assert(game:GetService("RunService"):IsStudio(), "art preview is Studio only")
local Config = require(game.ReplicatedStorage.Shared.Config)
local Catalog = require(game.ReplicatedStorage.Shared.Progression.Catalog)
local player = assert(game.Players:GetPlayers()[1], "start a Play client first")
assert(table.find(Config.Debug.Commands.UserIds, player.UserId), "designer preview only")
if _G.CuePreviewEquip then
	_G.CuePreviewEquip.stop()
	_G.CuePreviewEquip = nil
end
if CLEAR then return "restored profile appearance" end
assert(Catalog.exists(CUE), "not a catalog cue")
local attr = Config.Cue.EquippedAttribute
local restoreTo = player:GetAttribute(attr)
local connection = player:GetAttributeChangedSignal(attr):Connect(function()
	local value = player:GetAttribute(attr)
	if value ~= CUE then
		restoreTo = value
		player:SetAttribute(attr, CUE)
	end
end)
_G.CuePreviewEquip = {
	stop = function()
		connection:Disconnect()
		player:SetAttribute(attr, restoreTo)
	end,
}
player:SetAttribute(attr, CUE)
return "temporary appearance: " .. CUE
