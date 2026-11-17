--[[
	A detection is routed on `recommended_action`, and mute or kick only ever
	land on a player who is doing the harm, never on one who reports it.
]]

local Harness = require("./harness")
local Expect = require("./expect")

local API_KEY = "tq_test_invented_key"

local function analyse(detectionType: string, body: { [string]: any }, config: { [string]: any }?)
	local world = Harness.new()
	local player = world.addPlayer("PlayerOne", 101)
	world.respond = function()
		return { StatusCode = 200, Body = body }
	end
	local TuteliqSafety = world.load()
	local startConfig = { apiKey = API_KEY }
	for k, v in config or {} do
		startConfig[k] = v
	end
	TuteliqSafety.start(startConfig)
	local alerts = world.alerts()
	TuteliqSafety.analyzeNow("an invented message", detectionType, player)
	Harness.settle()
	TuteliqSafety.stop()
	return alerts, player
end

return {
	["reported bullying reaches moderators"] = function()
		local alerts = analyse("bullying", {
			is_bullying = false,
			bullying_reported = true,
			bullying_reported_by = "target",
			speaker_role = "experiencing",
			severity = "high",
			risk_score = 0.8,
			recommended_action = "flag_for_review",
		})
		Expect.equal(#alerts, 1, "alerts")
		Expect.equal(alerts[1].recommendedAction, "flag_for_review", "recommendedAction")
	end,

	["a player reporting bullying is never muted"] = function()
		local alerts, player = analyse("bullying", {
			is_bullying = false,
			bullying_reported = true,
			speaker_role = "experiencing",
			severity = "high",
			risk_score = 0.9,
			recommended_action = "block",
		})
		Expect.equal(#alerts, 1, "alerts")
		Expect.falsy(player:GetAttribute("TuteliqMuted"), "reporter muted")
	end,

	["a player bullying someone is muted on block"] = function()
		local alerts, player = analyse("bullying", {
			is_bullying = true,
			speaker_role = "enacting",
			severity = "high",
			risk_score = 0.9,
			recommended_action = "block",
		})
		Expect.equal(#alerts, 1, "alerts")
		Expect.truthy(player:GetAttribute("TuteliqMuted"), "bully muted")
	end,

	["an action below the sensitivity floor does not alert"] = function()
		local alerts = analyse("bullying", {
			is_bullying = true,
			speaker_role = "enacting",
			severity = "medium",
			risk_score = 0.9,
			recommended_action = "monitor",
		})
		Expect.equal(#alerts, 0, "alerts")
	end,

	["high sensitivity reports monitor"] = function()
		local alerts = analyse("bullying", {
			is_bullying = true,
			speaker_role = "enacting",
			severity = "low",
			risk_score = 0.2,
			recommended_action = "monitor",
		}, { sensitivity = "high" })
		Expect.equal(#alerts, 1, "alerts")
	end,

	["a child in distress is alerted on and never muted or kicked"] = function()
		local alerts, player = analyse("unsafe", {
			unsafe = true,
			categories = { "self_harm" },
			severity = "critical",
			risk_score = 0.95,
			recommended_action = "immediate_intervention",
		}, { actions = { mute = true, kick = true, notifyAdmins = true, log = true } })
		Expect.equal(#alerts, 1, "alerts")
		Expect.truthy(alerts[1].needsSupport, "needsSupport")
		Expect.falsy(player:GetAttribute("TuteliqMuted"), "child muted")
		Expect.falsy(player.kicked, "child kicked")
	end,

	["a threat towards others is muted"] = function()
		local alerts, player = analyse("unsafe", {
			unsafe = true,
			categories = { "threats" },
			severity = "high",
			risk_score = 0.9,
			recommended_action = "block",
		})
		Expect.equal(#alerts, 1, "alerts")
		Expect.truthy(player:GetAttribute("TuteliqMuted"), "muted")
	end,
}
