--!strict

--[[
	Reads an API result: whether it is reported, and whether the speaker is
	harming someone else. Routing follows `recommended_action`, the API's
	routing key; mute and kick are only ever for a speaker harming others.
]]

local Types = require(script.Parent.Types)

local Verdict = {}

local ACTION_RANK: { [string]: number } = {
	none = 0,
	monitor = 1,
	flag_for_review = 2,
	block = 3,
	immediate_intervention = 4,
}

-- The action a level implies, for a result that carries no recommended action.
local LEVEL_ACTIONS: { [string]: Types.RecommendedAction } = {
	critical = "immediate_intervention",
	high = "flag_for_review",
	medium = "monitor",
	low = "monitor",
	none = "none",
}

-- Unsafe-content categories about harm done to someone else. Every other
-- category concerns the speaker's own safety.
local HARM_TO_OTHERS: { [string]: boolean } = {
	violence = true,
	threats = true,
	hate_speech = true,
	sexual_content = true,
	sexual_exploitation = true,
}

-- Bullying speaker roles in which the speaker is not doing the bullying.
local NOT_ENACTING: { [string]: boolean } = {
	experiencing = true,
	reporting_other = true,
	self_directed = true,
	unclear = true,
}

function Verdict.rank(action: Types.RecommendedAction): number
	return ACTION_RANK[action]
end

--- The result's recommended action, read from its level when it has none.
function Verdict.actionOf(detectionType: Types.DetectionType, body: { [string]: any }): Types.RecommendedAction
	local action = body.recommended_action
	if type(action) == "string" and ACTION_RANK[action] ~= nil then
		return action :: Types.RecommendedAction
	end
	local level = if detectionType == "grooming" then body.grooming_risk else body.severity
	return LEVEL_ACTIONS[level or "none"] or "none"
end

local function hasSignal(detectionType: Types.DetectionType, body: { [string]: any }): boolean
	if detectionType == "bullying" then
		return body.is_bullying == true or body.bullying_reported == true
	elseif detectionType == "grooming" then
		return body.grooming_risk ~= nil and body.grooming_risk ~= "none"
	end
	return body.unsafe == true
end

--- True when the result reaches the floor the configured sensitivity reports.
function Verdict.isReported(
	detectionType: Types.DetectionType,
	body: { [string]: any },
	minimumAction: Types.RecommendedAction,
	includeSignalsWithoutAction: boolean
): boolean
	if ACTION_RANK[Verdict.actionOf(detectionType, body)] >= ACTION_RANK[minimumAction] then
		return true
	end
	return includeSignalsWithoutAction and hasSignal(detectionType, body)
end

--- True when the speaker of a single message is harming someone else.
function Verdict.speakerHarmsOthers(detectionType: Types.DetectionType, body: { [string]: any }): boolean
	if detectionType == "bullying" then
		if body.bullying_reported == true then
			return false
		end
		local role = body.speaker_role
		if type(role) == "string" then
			return not NOT_ENACTING[role]
		end
		return body.is_bullying == true
	elseif detectionType == "unsafe" then
		if body.third_party_concern == true then
			return false
		end
		for _, category in body.categories or {} do
			if HARM_TO_OTHERS[category] then
				return true
			end
		end
		return false
	end
	return false
end

--- True when a grooming result is a disclosure rather than an incident.
function Verdict.isDisclosure(body: { [string]: any }): boolean
	return body.speaker_stance == "describing_third_party" or body.disclosure_cleared == true
end

--- The roles a grooming result attributes its tactics to. Empty when the
--- conversation is a disclosure: a speaker describing someone else's conduct
--- is not performing it.
function Verdict.attributedRoles(body: { [string]: any }): { [string]: boolean }
	local roles: { [string]: boolean } = {}
	if Verdict.isDisclosure(body) or type(body.flag_attribution) ~= "table" then
		return roles
	end
	for _, senders in body.flag_attribution do
		if type(senders) == "table" then
			for _, role in senders do
				roles[role] = true
			end
		end
	end
	return roles
end

return Verdict
