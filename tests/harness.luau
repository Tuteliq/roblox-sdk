--[[
	Test harness: loads the module sources under Lune with stubbed Roblox
	services, so no test ever reaches the network or needs Roblox Studio.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local task = require("@lune/task")

local SRC_DIR = "src/TuteliqSafety"

-- Read once up front: Lune's file reads yield, and a metamethod cannot.
local SOURCES: { [string]: string } = {}
for _, file in fs.readDir(SRC_DIR) do
	local name = string.match(file, "^(.-)%.luau$")
	if name then
		SOURCES[name] = fs.readFile(SRC_DIR .. "/" .. file)
	end
end

local Harness = {}

local function newSignal()
	local signal = { _handlers = {} }
	function signal:Connect(fn)
		local entry = { fn = fn, connected = true }
		table.insert(self._handlers, entry)
		return {
			Disconnect = function()
				entry.connected = false
			end,
		}
	end
	function signal:Fire(...)
		for _, entry in self._handlers do
			if entry.connected then
				entry.fn(...)
			end
		end
	end
	return signal
end

local function newPlayer(name: string, userId: number)
	local player = {
		Name = name,
		UserId = userId,
		Parent = true,
		Chatted = newSignal(),
		_attributes = {},
		kicked = false,
	}
	function player:SetAttribute(key, value)
		self._attributes[key] = value
	end
	function player:GetAttribute(key)
		return self._attributes[key]
	end
	function player:Kick()
		self.kicked = true
	end
	return player
end

--- Creates an isolated world: fresh module state, players and HTTP stub.
function Harness.new()
	local world = {
		requests = {},
		logs = {},
		players = {},
		-- Replace to control responses: (request, decodedBody) -> { StatusCode, Body, Headers }
		respond = function(_request, _body)
			return { StatusCode = 200, Body = "{}", Headers = {} }
		end,
	}

	local guidCounter = 0
	local HttpService = {}
	function HttpService:GenerateGUID()
		guidCounter += 1
		return string.format("guid-%d", guidCounter)
	end
	function HttpService:JSONEncode(value)
		return serde.encode("json", value)
	end
	function HttpService:JSONDecode(text)
		return serde.decode("json", text)
	end
	function HttpService:RequestAsync(request)
		local body = if request.Body then serde.decode("json", request.Body) else nil
		table.insert(world.requests, { url = request.Url, headers = request.Headers, body = body })
		local response = world.respond(request, body)
		if type(response.Body) == "table" then
			response.Body = serde.encode("json", response.Body)
		end
		response.Headers = response.Headers or {}
		return response
	end

	local Players = { PlayerAdded = newSignal() }
	function Players:GetPlayers()
		return world.players
	end

	local storage = {}
	local ServerStorage = {}
	function ServerStorage:FindFirstChild(name)
		return storage[name]
	end

	local services = { HttpService = HttpService, Players = Players, ServerStorage = ServerStorage }
	local game = { JobId = "job-test", GameId = 1, PlaceId = 2 }
	function game:GetService(name)
		return assert(services[name], "no stub for service " .. name)
	end

	local Instance = {}
	function Instance.new(className)
		assert(className == "BindableEvent", "no stub for " .. className)
		local event = { Event = newSignal(), Name = "" }
		function event:Fire(...)
			self.Event:Fire(...)
		end
		setmetatable(event, {
			__newindex = function(t, k, v)
				rawset(t, k, v)
				if k == "Parent" and v == ServerStorage then
					storage[t.Name] = t
				end
			end,
		})
		return event
	end

	local cache = {}
	local nodes = {}
	local requireModule

	local function capture(level)
		return function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring(select(i, ...))
			end
			table.insert(world.logs, { level = level, text = table.concat(parts, " ") })
		end
	end

	local function node(name: string, sourceName: string)
		if nodes[sourceName] then
			return nodes[sourceName]
		end
		local n = { Name = name, _source = sourceName }
		nodes[sourceName] = n
		return n
	end

	local root = node("TuteliqSafety", "init")
	setmetatable(root, {
		__index = function(_, key)
			if key ~= "init" and SOURCES[key] then
				local child = node(key, key)
				child.Parent = root
				return child
			end
			return nil
		end,
	})

	requireModule = function(n)
		if cache[n] ~= nil then
			return cache[n]
		end
		local source = SOURCES[n._source]
		local env = {
			script = n,
			game = game,
			Instance = Instance,
			task = task,
			require = requireModule,
			print = capture("info"),
			warn = capture("warn"),
		}
		local chunk = luau.load(source, { debugName = n._source, environment = env })
		local result = chunk()
		cache[n] = result
		return result
	end

	function world.load(name: string?)
		if name == nil then
			return requireModule(root)
		end
		return requireModule(root[name])
	end

	function world.addPlayer(name: string, userId: number)
		local player = newPlayer(name, userId)
		table.insert(world.players, player)
		Players.PlayerAdded:Fire(player)
		return player
	end

	function world.alerts()
		local alerts = {}
		local event = storage.TuteliqAlert
		if event then
			event.Event:Connect(function(data)
				table.insert(alerts, data)
			end)
		end
		return alerts
	end

	--- Requests sent to a path, in order.
	function world.requestsTo(path: string)
		local out = {}
		for _, r in world.requests do
			if string.sub(r.url, -#path) == path then
				table.insert(out, r)
			end
		end
		return out
	end

	return world
end

--- Lets spawned and delayed threads run.
function Harness.settle(seconds: number?)
	task.wait(seconds or 0)
end

return Harness
