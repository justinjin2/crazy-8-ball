--!strict
-- EmoteHud: the EMOTE button and its tray (designer, 2026-10-26; Config.EmoteMenu.Button). The
-- designer's hand-drawn noob with EMOTE under it, at the bottom right between the screen's
-- centre and its right edge (their red circle): right of the lucky-block hotbar in the lobby,
-- under the power bar's column in a match, left of Roblox's jump button on a phone. Its own
-- ScreenGui just above the HUD, so it also shows over the results screen.
-- - Shown in the lobby, while waiting your turn and on the results; hidden while you shoot (and
--   your dance stops as your turn takes the body), under a full menu, the lucky block reel, a
--   popup, the Gift's cutscene, the freecam and the guided tutorial, and for an R6 body.
-- - A press (or R3 on a controller, its glyph on the button) opens or closes the tray
--   (EmoteMenu). It sways only while hovered (the candy's own hover), never idle.
-- Main calls update(inMatch, shooting) every frame; it only changes what changed.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local EmoteMenu = require(script.Parent.EmoteMenu)
local EmotePlayer = require(script.Parent.EmotePlayer)
local EmoteScene = require(script.Parent.EmoteScene)
local Freecam = require(script.Parent.Freecam)
local GiftDrop = require(script.Parent.GiftDrop)
local HudParts = require(script.Parent.HudParts)
local LuckyClient = require(script.Parent.LuckyClient)
local Menus = require(script.Parent.Menus)
local Progression = require(script.Parent.Progression)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local E = Config.EmoteMenu
local B = E.Button
local S = Config.Multiplayer.Style
local ACTION = "8ballEmoteOpen"

--- The ScreenGui's name (HubPad lets a controller's selection rest in it).
local SCREEN_NAME = "EmoteHud"

local EmoteHud = {}
EmoteHud.ScreenName = SCREEN_NAME

local started = false
local screen: ScreenGui
local button: TextButton
local menu: any
local shown = false
local bound = false

local function r15(): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.Health > 0
end

local function toggle()
	if not shown then
		return
	end
	UISound.play("Click")
	UIAnim.bounce(button)
	if menu:isOpen() then
		menu:close()
	else
		menu:show()
	end
end

local function bind(on: boolean)
	if on == bound then
		return
	end
	bound = on
	if on then
		ContextActionService:BindAction(ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				toggle()
			end
			return Enum.ContextActionResult.Sink
		end, false, (Enum.KeyCode :: any)[B.PadKey])
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

local function layout()
	local size = screen.AbsoluteSize
	if size.X <= 0 then
		return
	end
	local phone = math.min(size.X, size.Y) < S.ShortHeight
	local px = if phone then B.PhoneSizePx else B.SizePx
	local share = if phone then B.PhoneXShare else B.XShare
	local bottom = if phone then B.PhoneBottomPx else B.BottomPx
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(share, 0, 1, -bottom)
	button.Size = UDim2.fromOffset(px, px)
	local word = button:FindFirstChild("Word", true)
	if word and word:IsA("TextLabel") then
		HudParts.setTextSize(word, if phone then B.PhoneWordPx else B.WordPx)
	end
	-- The tray's arrow points at the top of the noob, which reaches above the button.
	local artTop = size.Y - bottom - px - px * math.max(0, B.ArtScale / 2 - B.ArtY)
	menu:layout(size, Vector2.new(size.X * share, artTop), phone)
end

--- Whether the tray is open (Main lets a controller's selection rest there in a match).
function EmoteHud.isOpen(): boolean
	return started and menu:isOpen()
end

--- Every frame (Main): show or hide the button from where the player is.
function EmoteHud.update(inMatch: boolean, shooting: boolean)
	if not started then
		return
	end
	if shooting and EmotePlayer.current() then
		EmotePlayer.stop("Turn") -- the turn takes the body
	end
	EmoteScene.setShooting(shooting) -- our own emotes' tall props hide from your shot
	local player = Players.LocalPlayer
	local blocked = Progression.isBusy() and not Progression.resultUp()
	local visible = not shooting
		and r15()
		and player:GetAttribute("TutorialActive") ~= true
		and not Freecam.active()
		and not Menus.isOpen()
		and not LuckyClient.isOpen()
		and not GiftDrop.isPlaying()
		and not blocked
	-- Sync only in the lobby: in a match the controller's X is the ult's and the pick's.
	EmotePlayer.allowSync(visible and not inMatch)
	if visible == shown then
		return
	end
	shown = visible
	bind(visible)
	if visible then
		UIAnim.popIn(button)
	else
		if menu:isOpen() then
			menu:close()
		end
		button.Visible = false
	end
end

--- Build the button and the tray (client, once, after Progression has started).
function EmoteHud.start(playerGui: PlayerGui)
	if started or not E.Enabled then
		return
	end
	started = true
	screen = Instance.new("ScreenGui")
	screen.Name = SCREEN_NAME
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 2 -- over the HUD and its results screen, under the popups' own
	screen.Parent = playerGui
	button = HudParts.candy(screen, "", toggle, "Blue", nil)
	button.Name = "EmoteButton"
	button.Selectable = false -- never takes the left stick from walking; R3 opens it
	button.Visible = false
	local parts = HudParts.candyParts(button)
	parts.face.Visible = false
	local icon = Instance.new("ImageLabel")
	icon.Name = "Art"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = B.Icon
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, B.ArtY)
	icon.Size = UDim2.fromScale(B.ArtScale, B.ArtScale)
	icon.ZIndex = 3
	icon.Parent = parts.body
	local word = HudParts.text(parts.body, "Word", B.WordPx, Strings.Emotes.Button)
	word.TextWrapped = false
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Position = UDim2.fromScale(0.5, 0.95)
	word.Size = UDim2.fromScale(1.4, 0.32)
	word.ZIndex = 4
	HudParts.padKey(button, (Enum.KeyCode :: any)[B.PadKey], Config.UI.Kit.PadKey.Corner)
	menu = EmoteMenu.new(screen, B.Icon)
	EmotePlayer.start()
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
end

return EmoteHud
