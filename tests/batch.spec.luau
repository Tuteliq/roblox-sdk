--[[
	Every chat message is analysed, and a batch result acts on the player who
	sent that message.
]]

local Harness = require("./harness")
local Expect = require("./expect")

local NOTHING = { recommended_action = "none", risk_score = 0, severity = "low" }

local function start(world, config: { [string]: any }?)
	local TuteliqSafety = world.load()
	local startConfig = {
		apiKey = "tq_test_invented_key",
		detect = { "bullying", "unsafe" },
		batchFlushIntervalSeconds = 0.05,
	}
	for k, v in config or {} do
		startConfig[k] = v
	end
	TuteliqSafety.start(startConfig)
	return TuteliqSafety
end

local function batchResponder(resultFor: (item: { [string]: any }) -> { [string]: any })
	return function(request, body)
		if not string.find(request.Url, "/batch/analyze", 1, true) then
			return { StatusCode = 200, Body = NOTHING }
		end
		local results = {}
		for _, item in body.items do
			table.insert(results, { id = item.id, type = item.type, success = true, result = resultFor(item) })
		end
		return { StatusCode = 200, Body = { results = results } }
	end
end

local function batchedTexts(world)
	local texts = {}
	for _, request in world.requestsTo("/api/v1/batch/analyze") do
		for _, item in request.body.items do
			table.insert(texts, `{item.type}:{item.data.text}`)
		end
	end
	return texts
end

local function contains(list, value)
	return table.find(list, value) ~= nil
end

return {
	["every message is analysed for bullying and unsafe content"] = function()
		local world = Harness.new()
		world.respond = batchResponder(function()
			return NOTHING
		end)
		local TuteliqSafety = start(world)
		local player = world.addPlayer("PlayerOne", 101)
		player.Chatted:Fire("an invented ordinary message")
		Harness.settle(0.2)
		TuteliqSafety.stop()
		local texts = batchedTexts(world)
		Expect.truthy(contains(texts, "bullying:an invented ordinary message"), "bullying item")
		Expect.truthy(contains(texts, "unsafe:an invented ordinary message"), "unsafe item")
	end,

	["messages that look alarming still go through full analysis"] = function()
		local world = Harness.new()
		world.respond = batchResponder(function()
			return NOTHING
		end)
		local TuteliqSafety = start(world)
		local player = world.addPlayer("PlayerOne", 101)
		player.Chatted:Fire("this is our secret ok")
		Harness.settle(0.2)
		TuteliqSafety.stop()
		local texts = batchedTexts(world)
		Expect.truthy(contains(texts, "bullying:this is our secret ok"), "bullying item")
		Expect.truthy(contains(texts, "unsafe:this is our secret ok"), "unsafe item")
	end,

	["a batch hit acts on the player who sent the message"] = function()
		local world = Harness.new()
		world.respond = batchResponder(function(item)
			if item.type == "bullying" then
				return {
					is_bullying = true,
					speaker_role = "enacting",
					severity = "high",
					risk_score = 0.9,
					recommended_action = "block",
				}
			end
			return NOTHING
		end)
		local TuteliqSafety = start(world)
		local alerts = world.alerts()
		local sender = world.addPlayer("Sender", 101)
		local bystander = world.addPlayer("Bystander", 102)
		sender.Chatted:Fire("an invented hurtful message")
		Harness.settle(0.2)
		TuteliqSafety.stop()
		Expect.equal(#alerts, 1, "alerts")
		Expect.equal(alerts[1].playerId, 101, "alert playerId")
		Expect.equal(alerts[1].message, "an invented hurtful message", "alert message")
		Expect.truthy(sender:GetAttribute("TuteliqMuted"), "sender muted")
		Expect.falsy(bystander:GetAttribute("TuteliqMuted"), "bystander muted")
	end,

	["a rate-limited batch is kept and retried after Retry-After"] = function()
		local world = Harness.new()
		local calls = 0
		local ok = batchResponder(function()
			return NOTHING
		end)
		world.respond = function(request, body)
			if string.find(request.Url, "/batch/analyze", 1, true) then
				calls += 1
				if calls == 1 then
					return {
						StatusCode = 429,
						Headers = { ["retry-after"] = "1" },
						Body = { error = { code = "RATE_LIMIT", message = "Too many requests", retryable = true } },
					}
				end
			end
			return ok(request, body)
		end
		local TuteliqSafety = start(world)
		local player = world.addPlayer("PlayerOne", 101)
		player.Chatted:Fire("an invented ordinary message")
		Harness.settle(0.3)
		Expect.equal(calls, 1, "calls before Retry-After elapsed")
		Harness.settle(1.2)
		TuteliqSafety.stop()
		Expect.equal(calls, 2, "calls after Retry-After")
		local retried = world.requestsTo("/api/v1/batch/analyze")[2]
		Expect.equal(#retried.body.items, 2, "retried items")
	end,

	["a failure that is not retryable is not retried"] = function()
		local world = Harness.new()
		local calls = 0
		world.respond = function(request)
			if string.find(request.Url, "/batch/analyze", 1, true) then
				calls += 1
				return { StatusCode = 400, Body = { error = { code = "VALIDATION", message = "Invalid request" } } }
			end
			return { StatusCode = 200, Body = NOTHING }
		end
		local TuteliqSafety = start(world)
		local player = world.addPlayer("PlayerOne", 101)
		player.Chatted:Fire("an invented ordinary message")
		Harness.settle(0.3)
		TuteliqSafety.stop()
		Expect.equal(calls, 1, "calls")
	end,
}
