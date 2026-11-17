local Harness = require("./harness")
local Expect = require("./expect")

return {
	["the default sensitivity is medium"] = function()
		local Config = Harness.new().load("Config")
		local config = Config.merge({ apiKey = "tq_test_invented_key" })
		Expect.equal(config.sensitivity, "medium", "sensitivity")
	end,

	["getPlayerAge must be a function"] = function()
		local Config = Harness.new().load("Config")
		local ok = Config.validate({ apiKey = "tq_test_invented_key", getPlayerAge = 12 :: any })
		Expect.falsy(ok, "accepted a number")
		ok = Config.validate({
			apiKey = "tq_test_invented_key",
			getPlayerAge = function()
				return nil
			end,
		})
		Expect.truthy(ok, "rejected a function")
	end,

	["an age lookup that errors is treated as unknown"] = function()
		local world = Harness.new()
		world.respond = function()
			return { StatusCode = 200, Body = { recommended_action = "none", grooming_risk = "none" } }
		end
		local TuteliqSafety = world.load()
		TuteliqSafety.start({
			apiKey = "tq_test_invented_key",
			detect = { "grooming" },
			batchFlushIntervalSeconds = 60,
			getPlayerAge = function()
				error("invented lookup failure")
			end,
		})
		local a = world.addPlayer("Alpha", 1)
		local b = world.addPlayer("Bravo", 2)
		for n = 1, 3 do
			a.Chatted:Fire(`invented line {n} from Alpha`)
			b.Chatted:Fire(`invented line {n} from Bravo`)
		end
		Harness.settle()
		TuteliqSafety.stop()
		local request = world.requestsTo("/api/v1/safety/grooming")[1]
		Expect.truthy(request, "grooming analysed")
		Expect.equal(request.body.messages[1].sender_role, "unknown", "role")
		Expect.equal(request.body.context.child_age, nil, "child_age")
	end,
}
