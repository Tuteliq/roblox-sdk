--!strict

local CrisisDetector = {}
CrisisDetector.__index = CrisisDetector

local CRISIS_PATTERNS: { string } = {
	-- Self-harm / suicide
	"kill myself",
	"want to die",
	"going to end it",
	"no reason to live",
	"better off dead",
	"suicide",
	"self harm",
	"cut myself",
	"hurt myself",
	"overdose",
	-- Immediate danger
	"someone is hurting me",
	"being abused",
	"help me please",
	"i'm scared of him",
	"i'm scared of her",
	"he hits me",
	"she hits me",
	"touching me",
	"send me pictures",
	"send pics",
	"meet me in real life",
	"meet irl",
	"don't tell anyone",
	"our secret",
	"come to my house",
	"where do you live",
	"how old are you really",
}

function CrisisDetector.new(): CrisisDetector
	local self = setmetatable({}, CrisisDetector)
	self._patterns = CRISIS_PATTERNS
	return self
end

function CrisisDetector:check(text: string): (boolean, string?)
	local lower = text:lower()

	for _, pattern in self._patterns do
		if lower:find(pattern, 1, true) then
			return true, pattern
		end
	end

	return false, nil
end

export type CrisisDetector = typeof(CrisisDetector.new())

return CrisisDetector
