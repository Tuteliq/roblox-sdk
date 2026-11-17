--[[
	Grooming is analysed per pair of players, with ages and roles where the
	game knows them, and only the player a tactic is attributed to is muted.
]]

local Harness = require("./harness")
local Expect = require("./expect")

local NOTHING = { recommended_action = "none", risk_score = 0, severity = "low", grooming_risk = "none" }

local function start(world, ages: { [number]: number }?)
	local TuteliqSafety = world.load()
	TuteliqSafety.start({
		apiKey = "tq_test_invented_key",
		detect = { "grooming" },
		batchFlushIntervalSeconds = 60,
		getPlayerAge = if ages
			then function(player)
				return ages[player.UserId]
			end
			else nil,
	})
	return TuteliqSafety
end

local function say(player, n: number)
	player.Chatted:Fire(`invented line {n} from {player.Name}`)
end

local function speakersIn(request)
	local speakers = {}
	for _, message in request.body.messages do
		speakers[string.match(message.text, "from (%w+)$")] = true
	end
	local count = 0
	for _ in speakers do
		count += 1
	end
	return count, speakers
end

local function groomingHit(attribution: { [string]: { string } }?)
	return function(request)
		if string.find(request.Url, "/safety/grooming", 1, true) then
			return {
				StatusCode = 200,
				Body = {
					grooming_risk = "high",
					risk_score = 0.9,
					recommended_action = "block",
					flags = { "secrecy_request" },
					flag_attribution = attribution,
				},
			}
		end
		return { StatusCode = 200, Body = NOTHING }
	end
end

return {
	["each conversation holds two players, not the whole server"] = function()
		local world = Harness.new()
		world.respond = function()
			return { StatusCode = 200, Body = NOTHING }
		end
		local TuteliqSafety = start(world)
		local a = world.addPlayer("Alpha", 1)
		local b = world.addPlayer("Bravo", 2)
		local c = world.addPlayer("Charlie", 3)
		for n = 1, 4 do
			say(a, n)
			say(b, n)
			say(c, n)
		end
		Harness.settle()
		TuteliqSafety.stop()
		local requests = world.requestsTo("/api/v1/safety/grooming")
		Expect.truthy(#requests > 0, "grooming analysed")
		for _, request in requests do
			Expect.equal((speakersIn(request)), 2, "speakers per conversation")
		end
	end,

	["known ages are sent as roles, sender_age and child_age"] = function()
		local world = Harness.new()
		world.respond = function()
			return { StatusCode = 200, Body = NOTHING }
		end
		local TuteliqSafety = start(world, { [1] = 12, [2] = 34 })
		local child = world.addPlayer("Alpha", 1)
		local adult = world.addPlayer("Bravo", 2)
		for n = 1, 3 do
			say(adult, n)
			say(child, n)
		end
		Harness.settle()
		TuteliqSafety.stop()
		local request = world.requestsTo("/api/v1/safety/grooming")[1]
		Expect.truthy(request, "grooming analysed")
		Expect.equal(request.body.context.child_age, 12, "child_age")
		for _, message in request.body.messages do
			if string.find(message.text, "Alpha", 1, true) then
				Expect.equal(message.sender_role, "child", "child role")
				Expect.equal(message.sender_age, 12, "child sender_age")
			else
				Expect.equal(message.sender_role, "adult", "adult role")
				Expect.equal(message.sender_age, 34, "adult sender_age")
			end
		end
	end,

	["a grooming hit mutes the adult it is attributed to, never the child"] = function()
		local world = Harness.new()
		world.respond = groomingHit({ secrecy_request = { "adult" } })
		local TuteliqSafety = start(world, { [1] = 12, [2] = 34 })
		local alerts = world.alerts()
		local child = world.addPlayer("Alpha", 1)
		local adult = world.addPlayer("Bravo", 2)
		-- The child speaks last, so the message that triggers analysis is theirs.
		for n = 1, 3 do
			say(child, n)
			say(adult, n)
		end
		say(child, 4)
		Harness.settle()
		TuteliqSafety.stop()
		Expect.truthy(#alerts >= 1, "alerted")
		Expect.truthy(adult:GetAttribute("TuteliqMuted"), "adult muted")
		Expect.falsy(child:GetAttribute("TuteliqMuted"), "child muted")
	end,

	["with unknown ages a grooming hit alerts with both players and mutes nobody"] = function()
		local world = Harness.new()
		world.respond = groomingHit(nil)
		local TuteliqSafety = start(world)
		local alerts = world.alerts()
		local a = world.addPlayer("Alpha", 1)
		local b = world.addPlayer("Bravo", 2)
		for n = 1, 3 do
			say(a, n)
			say(b, n)
		end
		Harness.settle()
		TuteliqSafety.stop()
		Expect.truthy(#alerts >= 1, "alerted")
		Expect.equal(#alerts[1].participants, 2, "participants")
		Expect.falsy(a:GetAttribute("TuteliqMuted"), "Alpha muted")
		Expect.falsy(b:GetAttribute("TuteliqMuted"), "Bravo muted")
	end,
}
