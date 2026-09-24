--!strict
-- Test harness: lets the shared game modules (src/shared) run inside Lune, outside Studio.
--
-- It builds a fake Instance tree from the folder layout that Rojo would produce, so a
-- module can keep writing `require(script.Parent.Config)` and load here unchanged.
--
-- The environment handed to those modules has NO Roblox globals (no game, Vector3, task,
-- Instance, ...). If a Physics or Rules module touches one, the test fails loudly. That is
-- exactly what keeps the simulation portable to the server and to these tests.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Harness = {}

-- Relative to the repo root; tools/test.sh cds there before running.
local SHARED_ROOT = "src/shared"

---------------------------------------------------------------------------------------------
-- Fake instances
---------------------------------------------------------------------------------------------
export type Node = {
	Name: string,
	ClassName: string,
	Parent: Node?,
	_children: { [string]: Node },
	_file: string?,
}

local nodeMethods = {}

function nodeMethods.FindFirstChild(self: Node, name: string): Node?
	return self._children[name]
end

function nodeMethods.WaitForChild(self: Node, name: string): Node
	local child = self._children[name]
	if child == nil then
		error(("WaitForChild: %s has no child named %s"):format(self.Name, name), 2)
	end
	return child
end

function nodeMethods.GetChildren(self: Node): { Node }
	local list = {}
	for _, child in self._children do
		table.insert(list, child)
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

function nodeMethods.IsA(self: Node, className: string): boolean
	return self.ClassName == className
end

function nodeMethods.GetFullName(self: Node): string
	local parts = {}
	local node: Node? = self
	while node do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end

local nodeMeta = {
	__index = function(t, key)
		local child = rawget(t, "_children")[key]
		if child ~= nil then
			return child
		end
		return nodeMethods[key]
	end,
	__tostring = function(t)
		return t.Name
	end,
}

local function newNode(name: string, className: string, parent: Node?, file: string?): Node
	local node = setmetatable({
		Name = name,
		ClassName = className,
		Parent = parent,
		_children = {},
		_file = file,
	}, nodeMeta)
	if parent then
		parent._children[name] = node
	end
	return (node :: any) :: Node
end

local function buildTree(dir: string, name: string, parent: Node?): Node
	local initFile = dir .. "/init.luau"
	local hasInit = fs.isFile(initFile)
	local node = newNode(
		name,
		if hasInit then "ModuleScript" else "Folder",
		parent,
		if hasInit then initFile else nil
	)
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			buildTree(path, entry, node)
		elseif entry ~= "init.luau" and entry:match("%.luau$") then
			local moduleName = (entry:gsub("%.luau$", ""))
			newNode(moduleName, "ModuleScript", node, path)
		end
	end
	return node
end

---------------------------------------------------------------------------------------------
-- Module loading with a Roblox-free environment
---------------------------------------------------------------------------------------------
local root: Node? = nil
local cache: { [Node]: any } = {}
local loading: { [Node]: boolean } = {}

-- Roblox globals that must never be visible to shared modules. Lune has none of these, and
-- the smoke test checks they stay absent.
local FORBIDDEN_GLOBALS = { "game", "workspace", "Instance", "Vector3", "CFrame", "task", "Enum" }

local function loadSource(source: string, node: Node, requireFn: (any) -> any): any
	-- The module keeps its `--!strict` line first; `script` and `require` arrive as chunk
	-- arguments so the chunk compiles with full optimisation (a custom environment would
	-- turn optimisation off and make the physics tests several times slower).
	local firstLineEnd = source:find("\n") or #source
	local firstLine = source:sub(1, firstLineEnd)
	local rest = source:sub(firstLineEnd + 1)
	local wrapped
	if firstLine:match("^%-%-!") then
		wrapped = firstLine .. "local script, require = ...\n" .. rest
	else
		wrapped = "local script, require = ...\n" .. source
	end
	local fn = luau.load(wrapped, { debugName = node._file or node.Name })
	return fn(node, requireFn)
end

local function requireNode(target: any): any
	if type(target) ~= "table" or rawget(target, "_file") == nil then
		error(("require: expected a ModuleScript, got %s"):format(tostring(target)), 2)
	end
	local node = target :: Node
	if cache[node] ~= nil then
		return cache[node]
	end
	if loading[node] then
		error("cyclic require of " .. node:GetFullName(), 2)
	end
	loading[node] = true
	local result = loadSource(fs.readFile(node._file :: string), node, requireNode)
	loading[node] = nil
	if result == nil then
		error(node:GetFullName() .. " must return a value", 2)
	end
	cache[node] = result
	return result
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

--- The fake ReplicatedStorage.Shared folder.
function Harness.shared(): Node
	if root == nil then
		root = buildTree(SHARED_ROOT, "Shared", nil)
	end
	return root :: Node
end

--- Require a shared module by dotted path, e.g. Harness.require("Physics.Simulation").
function Harness.require(dottedPath: string): any
	local node: Node = Harness.shared()
	for segment in dottedPath:gmatch("[^%.]+") do
		local child = node._children[segment]
		if child == nil then
			error(("no shared module %q (missing %s)"):format(dottedPath, segment), 2)
		end
		node = child
	end
	return requireNode(node)
end

--- Forget all loaded modules so the next require starts from a clean state.
function Harness.reset()
	cache = {}
	loading = {}
	root = nil
end

--- Run a snippet of Luau the way shared modules run (with `script` and `require`).
function Harness.evalInModuleEnv(source: string): any
	local fake = newNode("Snippet", "ModuleScript", Harness.shared(), nil)
	return loadSource(source, fake, requireNode)
end

--- Names of Roblox-only globals that shared code must never touch.
function Harness.forbiddenGlobals(): { string }
	return FORBIDDEN_GLOBALS
end

--- Assertion helpers -----------------------------------------------------------------------

function Harness.expect(condition: boolean, message: string?)
	if not condition then
		error(message or "expectation failed", 2)
	end
end

function Harness.near(actual: number, expected: number, tolerance: number, message: string?)
	if math.abs(actual - expected) > tolerance then
		error(
			("%s: expected %.6g to be within %.3g of %.6g"):format(
				message or "near",
				actual,
				tolerance,
				expected
			),
			2
		)
	end
end

local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

--- Check `actual` against `expected`, a value decoded from JSON: the same shape, numbers
--- within `tolerance`, strings and booleans exactly, arrays the same length and order, and
--- objects compared on the EXPECTED side's keys (sorted, so the first mismatch reported is
--- always the same one). Keys only `actual` has are ignored; call it both ways to catch
--- those too. Fails naming `path` extended down to the first value that differs.
function Harness.matchesJson(actual: any, expected: any, path: string, tolerance: number)
	if type(expected) == "number" then
		if type(actual) ~= "number" then
			error(
				("%s is %s, expected the number %.17g"):format(path, tostring(actual), expected),
				0
			)
		end
		-- NaN compares false with everything, so a NaN on either side would slip past the
		-- tolerance check below (and serde writes NaN and inf as null).
		if actual ~= actual or expected ~= expected or math.abs(actual) == math.huge then
			error(("%s is %s, not a finite number"):format(path, tostring(actual)), 0)
		end
		if math.abs(actual - expected) > tolerance then
			error(
				("%s is %.17g, expected %.17g (within %.3g)"):format(
					path,
					actual,
					expected,
					tolerance
				),
				0
			)
		end
	elseif type(expected) == "table" then
		if type(actual) ~= "table" then
			error(("%s is %s, expected a table"):format(path, tostring(actual)), 0)
		end
		if #expected > 0 then
			if #actual ~= #expected then
				error(("%s has %d entries, expected %d"):format(path, #actual, #expected), 0)
			end
			for i = 1, #expected do
				Harness.matchesJson(actual[i], expected[i], ("%s[%d]"):format(path, i), tolerance)
			end
		else
			for _, key in sortedKeys(expected) do
				Harness.matchesJson(actual[key], expected[key], path .. "." .. key, tolerance)
			end
		end
	elseif actual ~= expected then
		error(("%s is %s, expected %s"):format(path, tostring(actual), tostring(expected)), 0)
	end
end

return Harness
