--!strict
-- HubPad: the controller in the lobby (designer, 2026-10-10; GDD section 5). One button, one
-- job, and the left stick always walks unless the player chose to be on a button:
--   D-pad up / right / down  the Shop, Cues, Free Reward (Progression.padRoute; their pictures
--                            on the left column's tiles)
--   D-pad left               the right side: Daily Challenge first, then the offer, Settings,
--                            Invite, Plus, and up onto the player list (Progression.padSide); the
--                            stick or D-pad moves, A presses, B goes back to walking
--   Y                        Rank, open or close (its picture on the Rank badge)
--   L2                       Play Global on a waiting pad, or stop its search; Join an
--                            opponent's ask (their pictures on those buttons)
--   B                        leave the pad (on one, not playing); dismiss an opponent's ask
--   View (Select); R3        Skip tutorial; the tutorial's Next (TutorialOverlay binds both)
--   X; LB / RB, R2, L3       Abilities (MenuColumn); the lucky blocks (LuckyClient)
-- In a match the table's own binding (Input) has the pad, so nothing here fires there.
--
-- It also keeps the stick free (the designer was stuck after Rank, 2026-10-10): with no menu
-- or popup up, a selection on something hidden or not a stop is dropped; a selection on the
-- right side that wanders off it ends the side; and a hard push that does not move the
-- selection (it hit the edge) lets go, so the player walks again.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Menus = require(script.Parent.Menus)
local PadMode = require(script.Parent.PadMode)
local Progression = require(script.Parent.Progression)

local HUB = Config.Input.Gamepad.Hub
local RANK = PadMode.key(HUB.Rank)
local QUEUE = PadMode.key(HUB.Queue)
local SIDE = PadMode.key(HUB.Side)

-- The tutorial's ScreenGui (TutorialOverlay): its question (Skip's) keeps the selection.
local TUTORIAL_GUI = "TutorialGui"
-- B while the right side has the controller: back to walking (above Roblox's own B).
local SIDE_BACK = "8ballHubSideBack"

export type Deps = {
	-- The table the player is at now (its snapshot), or nil in the open lobby.
	snapshot: () -> any?,
	-- Whether the table's controls are live (the player's turn): then nothing here fires.
	playing: () -> boolean,
	leave: () -> (),
	matchBar: any,
	opponentPrompt: any,
}

local HubPad = {}

local deps: Deps
local started = false
local sideBound = false
local freeStick = { at = nil :: number?, from = nil :: GuiObject?, moved = false }

local function bindSideBack(on: boolean)
	if on == sideBound then
		return
	end
	sideBound = on
	if on then
		ContextActionService:BindActionAtPriority(
			SIDE_BACK,
			function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
				if state == Enum.UserInputState.Begin then
					Progression.padSideBlur()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value + 15,
			Enum.KeyCode.ButtonB
		)
	else
		ContextActionService:UnbindAction(SIDE_BACK)
	end
end

--- A controller press in the lobby (UserInputService.InputBegan, or Studio's GuiQA "pad").
--- Returns whether it did something.
function HubPad.press(key: Enum.KeyCode): boolean
	if not started or deps.playing() then
		return false
	end
	local snapshot = deps.snapshot()
	if key == SIDE then
		if Progression.padSideOn() then
			Progression.padSideBlur()
			return true
		end
		return Progression.padSide()
	elseif Progression.padRoute(key) then
		return true
	elseif key == RANK then
		if snapshot ~= nil and snapshot.phase ~= "Waiting" then
			return false -- at a table whose game is on (or over): Rank waits for the lobby
		end
		return Progression.toggleRank()
	elseif key == QUEUE then
		if UserInputService:GetFocusedTextBox() ~= nil or Menus.isOpen() then
			return false
		end
		if deps.matchBar:padPress() then
			return true
		end
		return snapshot == nil and deps.opponentPrompt:padJoin()
	elseif key == Enum.KeyCode.ButtonB then
		if snapshot ~= nil and not Progression.isBusy() then
			deps.leave()
			return true
		end
		return snapshot == nil and deps.opponentPrompt:padDismiss()
	end
	return false
end

-- A selection the player cannot see or use: dropped while no menu or popup is up, or it would
-- keep the left stick from walking with nothing to show for it.
local function dropStray()
	local selected = GuiService.SelectedObject
	if Progression.isBusy() then
		return
	end
	if selected == nil then
		Progression.padSideBlur() -- Roblox's own B, or a menu from the side closed
		return
	end
	if Progression.padSideOn() then
		if not Progression.padSideHolds(selected) then
			Progression.padSideBlur() -- wandered off the side: back to walking
			if GuiService.SelectedObject == selected then
				GuiService.SelectedObject = nil
			end
		end
		return
	end
	if not Menus.selectable(selected) then
		GuiService.SelectedObject = nil
	end
end

-- A hard push that has not moved the selection after FreeStickSeconds (it hit the edge of the
-- side's buttons) lets go of it, so the player walks again. Never the tutorial's own question
-- (Skip's Yes / No): it waits for an answer.
local function freeTheStick()
	local G = Config.Input.Gamepad
	local selected = GuiService.SelectedObject
	local gui = if selected then selected:FindFirstAncestorOfClass("ScreenGui") else nil
	local push = 0
	if selected ~= nil and not Progression.isBusy() and not (gui and gui.Name == TUTORIAL_GUI) then
		for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 then
				push = Vector2.new(state.Position.X, state.Position.Y).Magnitude
			end
		end
	end
	if push < G.FreeStickPush then
		freeStick.at, freeStick.from, freeStick.moved = nil, nil, false
		return
	end
	local now = os.clock()
	if freeStick.at == nil then
		freeStick.at, freeStick.from, freeStick.moved = now, selected, false
		return
	end
	if selected ~= freeStick.from then
		freeStick.moved = true -- this push went somewhere: it is moving between buttons
	end
	if not freeStick.moved and now - (freeStick.at :: number) >= G.FreeStickSeconds then
		Progression.padSideBlur()
		GuiService.SelectedObject = nil
		freeStick.at, freeStick.from, freeStick.moved = nil, nil, false
	end
end

--- Every frame (Main): keep the stick free in the lobby.
function HubPad.update()
	if not started then
		return
	end
	if deps.playing() then
		Progression.padSideBlur()
		bindSideBack(false)
		return
	end
	dropStray()
	freeTheStick()
	bindSideBack(Progression.padSideOn())
end

function HubPad.start(given: Deps)
	if started then
		return
	end
	started = true
	deps = given
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not string.find(input.UserInputType.Name, "^Gamepad") then
			return
		end
		HubPad.press(input.KeyCode)
	end)
end

return HubPad
