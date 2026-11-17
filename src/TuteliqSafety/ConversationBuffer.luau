--!strict

--[[
	Recent chat per channel, read as conversations between two players.

	Grooming is one person working on another, so each pair of players who
	talk in a channel is analysed as its own conversation, with each player's
	role and age where the game knows them.
]]

local Types = require(script.Parent.Types)

local ConversationBuffer = {}
ConversationBuffer.__index = ConversationBuffer

local MAX_MESSAGES_PER_CHANNEL = 50
local MIN_MESSAGES_FOR_ANALYSIS = 5
local MIN_TIME_BETWEEN_ANALYSIS_SECONDS = 30
local ADULT_AGE = 18

function ConversationBuffer.new(): ConversationBuffer
	local self = setmetatable({}, ConversationBuffer)
	self._buffers = {} :: { [string]: { Types.ChatMessage } }
	self._lastAnalysis = {} :: { [string]: number }
	return self
end

local function pairKey(channel: string, a: number, b: number): string
	return `{channel}:{math.min(a, b)}:{math.max(a, b)}`
end

local function roleFor(age: number?): Types.SenderRole
	if age == nil then
		return "unknown"
	end
	return if age < ADULT_AGE then "child" else "adult"
end

function ConversationBuffer:push(channel: string, message: Types.ChatMessage)
	if not self._buffers[channel] then
		self._buffers[channel] = {}
	end

	local buffer = self._buffers[channel]
	table.insert(buffer, message)

	-- Ring buffer: drop oldest when full
	while #buffer > MAX_MESSAGES_PER_CHANNEL do
		table.remove(buffer, 1)
	end
end

--- The other players who spoke in the channel, most recent first.
function ConversationBuffer:partnersOf(channel: string, senderId: number, limit: number): { number }
	local partners: { number } = {}
	local seen: { [number]: boolean } = {}
	local buffer = self._buffers[channel] or {}
	for i = #buffer, 1, -1 do
		local id = buffer[i].senderId
		if id ~= senderId and not seen[id] then
			seen[id] = true
			table.insert(partners, id)
			if #partners >= limit then
				break
			end
		end
	end
	return partners
end

function ConversationBuffer:_pairMessages(channel: string, a: number, b: number): { Types.ChatMessage }
	local messages: { Types.ChatMessage } = {}
	for _, msg in self._buffers[channel] or {} do
		if msg.senderId == a or msg.senderId == b then
			table.insert(messages, msg)
		end
	end
	return messages
end

function ConversationBuffer:shouldAnalyze(channel: string, a: number, b: number): boolean
	local messages = self:_pairMessages(channel, a, b)
	if #messages < MIN_MESSAGES_FOR_ANALYSIS then
		return false
	end

	local lastTime = self._lastAnalysis[pairKey(channel, a, b)]
	if lastTime and os.clock() - lastTime < MIN_TIME_BETWEEN_ANALYSIS_SECONDS then
		return false
	end

	-- Both players must have spoken
	local spoke: { [number]: boolean } = {}
	for _, msg in messages do
		spoke[msg.senderId] = true
	end
	return spoke[a] == true and spoke[b] == true
end

--- The conversation between two players, marking it as analysed now.
function ConversationBuffer:getConversation(channel: string, a: number, b: number): Types.Conversation
	self._lastAnalysis[pairKey(channel, a, b)] = os.clock()

	local messages: { Types.ConversationMessage } = {}
	local roles: { [number]: Types.SenderRole } = {}
	local childAge: number? = nil
	for _, msg in self:_pairMessages(channel, a, b) do
		local role = roleFor(msg.senderAge)
		roles[msg.senderId] = role
		if role == "child" and (childAge == nil or (msg.senderAge :: number) < childAge) then
			childAge = msg.senderAge
		end
		table.insert(messages, {
			sender_role = role,
			text = msg.text,
			sender_age = msg.senderAge,
		})
	end

	return { messages = messages, childAge = childAge, roles = roles }
end

--- Forgets everything a player said, for example when they leave.
function ConversationBuffer:removeSender(senderId: number)
	for _, buffer in self._buffers do
		for i = #buffer, 1, -1 do
			if buffer[i].senderId == senderId then
				table.remove(buffer, i)
			end
		end
	end
end

function ConversationBuffer:clear(channel: string)
	self._buffers[channel] = nil
	for key in self._lastAnalysis do
		if string.sub(key, 1, #channel + 1) == channel .. ":" then
			self._lastAnalysis[key] = nil
		end
	end
end

function ConversationBuffer:clearAll()
	table.clear(self._buffers)
	table.clear(self._lastAnalysis)
end

export type ConversationBuffer = typeof(ConversationBuffer.new())

return ConversationBuffer
