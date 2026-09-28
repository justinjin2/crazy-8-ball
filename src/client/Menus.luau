--!strict
-- Menus: every full menu (the Ranked roadmap, Shop, Inventory, Rewards, Trade) opens and closes
-- through here, one at a time (docs/prompts/ECONOMY_UI_PROMPT.md section 5): opening one closes
-- whatever else is open first. A menu registers a handle, { open, close, isOpen, root? }, and
-- keeps drawing itself; this module only decides which one is up.
--
-- Close rules, the same for every menu: gamepad B and Escape (here), the red X and a tap
-- outside the panel (MenuFrame routes both to Menus.close). The roadmap still handles its own
-- X, backdrop, B and Escape; this module reads its state from its handle, so it never goes
-- stale. The gamepad's selection from before the first menu opened (GuiService.SelectedObject)
-- comes back when the last one closes, and switching from one menu to another hands the next
-- one that same selection, never a button inside the menu that just closed.
--
-- B is bound at a priority above the table's own B (Leave) and the roadmap's, only while a
-- menu is open, so B closes the menu before anything else hears it.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

export type Handle = {
	open: (tab: string?) -> (),
	close: () -> (),
	isOpen: () -> boolean,
	-- What the menu draws in (its ScreenGui or root frame): a selection inside it is dropped
	-- when it closes. Optional (the roadmap puts its own selection back).
	root: Instance?,
}

local Menus = {}

local CLOSE_ACTION = "8ballMenusClose"
-- Above the roadmap's own B (High + 10) and the table's (High): B closes a menu first.
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 20

local handles: { [string]: Handle } = {}
local order: { string } = {} -- registration order, so current() never depends on hash order
local saved: GuiObject? = nil -- the selection from before the first menu opened
local bound = false
local watcher: RBXScriptConnection? = nil
local blocker: (() -> boolean)? = nil
local escapeHooked = false

local function isOpenHandle(handle: Handle): boolean
	local ok, open = pcall(handle.isOpen)
	return ok and open == true
end

--- The menu that is open now, or nil.
function Menus.current(): string?
	for _, name in order do
		local handle = handles[name]
		if handle and isOpenHandle(handle) then
			return name
		end
	end
	return nil
end

--- Whether any menu (or the named one) is open.
function Menus.isOpen(name: string?): boolean
	if name then
		local handle = handles[name]
		return handle ~= nil and isOpenHandle(handle)
	end
	return Menus.current() ~= nil
end

--- Whether a menu of that name has registered.
function Menus.isRegistered(name: string): boolean
	return handles[name] ~= nil
end

--- A registered menu's handle (for a menu that jumps to another's tab).
function Menus.handle(name: string): Handle?
	return handles[name]
end

--- Refuse to open menus while `fn` says so (Progression: in a match, under the result
--- screen, NEW RANK! or the case opening). Closing always works.
function Menus.setBlocker(fn: (() -> boolean)?)
	blocker = fn
end

local function blocked(): boolean
	local fn = blocker
	if not fn then
		return false
	end
	local ok, result = pcall(fn)
	return ok and result == true
end

local function valid(object: GuiObject?): boolean
	return object ~= nil and object:IsDescendantOf(game)
end

-- The selection goes back to where it was before the menus, if it is still there.
local function restoreSelection(closedRoot: Instance?)
	local selected = GuiService.SelectedObject
	local inClosed = selected ~= nil and closedRoot ~= nil and selected:IsDescendantOf(closedRoot)
	if selected == nil or inClosed then
		GuiService.SelectedObject = if valid(saved) then saved else nil
	end
end

local function unbind()
	if bound then
		bound = false
		ContextActionService:UnbindAction(CLOSE_ACTION)
	end
	if watcher then
		watcher:Disconnect()
		watcher = nil
	end
end

-- While any menu is open: B closes it; every frame, notice a menu that closed itself (the
-- roadmap's X) so B is let go at once.
local function bind()
	if bound then
		return
	end
	bound = true
	ContextActionService:BindActionAtPriority(
		CLOSE_ACTION,
		function(_name: string, state: Enum.UserInputState, _input: InputObject)
			if state == Enum.UserInputState.Begin then
				Menus.close()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		CLOSE_PRIORITY,
		Enum.KeyCode.ButtonB
	)
	watcher = RunService.Heartbeat:Connect(function()
		if Menus.current() == nil then
			unbind()
			saved = nil
		end
	end)
end

local swallowed: InputObject? = nil

--- A dialog inside a menu answered this Escape press itself: the menu stays open.
function Menus.swallowEscape(input: InputObject)
	swallowed = input
end

-- Escape closes the open menu (Roblox's own menu may open too; that is Roblox's key). It waits
-- a moment, so a confirm dialog hearing the same press can keep the menu open (swallowEscape),
-- whichever of the two listeners runs first.
local function hookEscape()
	if escapeHooked then
		return
	end
	escapeHooked = true
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode ~= Enum.KeyCode.Escape or Menus.current() == nil then
			return
		end
		task.defer(function()
			if swallowed == input then
				swallowed = nil
				return
			end
			Menus.close()
		end)
	end)
end

--- Add a menu. `name` is how everything else opens it ("Shop", "Ranked"); a second register
--- with the same name replaces the first.
function Menus.register(name: string, handle: Handle)
	if handles[name] == nil then
		table.insert(order, name)
	end
	handles[name] = handle
	hookEscape()
end

--- Open a menu (on `tab`, if it has tabs), closing whatever else is open first. False if it
--- is not registered or menus are blocked right now. Opening the open menu on another tab
--- just switches the tab.
function Menus.open(name: string, tab: string?): boolean
	local handle = handles[name]
	if not handle or blocked() then
		return false
	end
	local current = Menus.current()
	if current == nil then
		local selected = GuiService.SelectedObject
		saved = selected
	elseif current ~= name then
		local other = handles[current]
		other.close()
		-- The next menu starts from the selection from before the menus (never a button in
		-- the one that just closed, which the next one would later "restore").
		GuiService.SelectedObject = if valid(saved) then saved else nil
	end
	handle.open(tab)
	if isOpenHandle(handle) then
		bind()
		return true
	end
	return false
end

--- Close the open menu (or only `name`, if that is the one open). The selection from before
--- the menus comes back.
function Menus.close(name: string?)
	local current = Menus.current()
	if current == nil or (name ~= nil and name ~= current) then
		return
	end
	local handle = handles[current]
	handle.close()
	if Menus.current() == nil then
		restoreSelection(handle.root)
		saved = nil
		unbind()
	end
end

--- Open the menu, or close it if it is the one open. Returns whether it is open now.
function Menus.toggle(name: string, tab: string?): boolean
	if Menus.current() == name then
		Menus.close(name)
		return false
	end
	return Menus.open(name, tab)
end

return Menus
