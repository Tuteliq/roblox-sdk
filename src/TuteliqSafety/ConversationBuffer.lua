--!strict

local Types = require(script.Parent.Types)

local ConversationBuffer = {}
ConversationBuffer.__index = ConversationBuffer

local MAX_MESSAGES_PER_CHANNEL = 50
local MIN_MESSAGES_FOR_ANALYSIS = 5
local MIN_TIME_BETWEEN_ANALYSIS_SECONDS = 30

function ConversationBuffer.new(): ConversationBuffer
	local self = setmetatable({}, ConversationBuffer)
	self._buffers = {} :: { [string]: { Types.ChatMessage } }
	self._lastAnalysis = {} :: { [string]: number }
	return self
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

function ConversationBuffer:shouldAnalyze(channel: string): boolean
	local buffer = self._buffers[channel]
	if not buffer or #buffer < MIN_MESSAGES_FOR_ANALYSIS then
		return false
	end

	local lastTime = self._lastAnalysis[channel]
	if lastTime then
		local elapsed = os.clock() - lastTime
		if elapsed < MIN_TIME_BETWEEN_ANALYSIS_SECONDS then
			return false
		end
	end

	-- Need at least 2 unique senders for grooming analysis
	local senders = {}
	for _, msg in buffer do
		senders[msg.senderId] = true
	end
	local senderCount = 0
	for _ in senders do
		senderCount += 1
	end
	if senderCount < 2 then
		return false
	end

	return true
end

function ConversationBuffer:getMessages(channel: string): { Types.ConversationMessage }
	local buffer = self._buffers[channel]
	if not buffer then
		return {}
	end

	self._lastAnalysis[channel] = os.clock()

	local messages: { Types.ConversationMessage } = {}
	for _, msg in buffer do
		table.insert(messages, {
			sender_role = "unknown",
			text = msg.text,
		})
	end

	return messages
end

function ConversationBuffer:clear(channel: string)
	self._buffers[channel] = nil
	self._lastAnalysis[channel] = nil
end

function ConversationBuffer:clearAll()
	table.clear(self._buffers)
	table.clear(self._lastAnalysis)
end

export type ConversationBuffer = typeof(ConversationBuffer.new())

return ConversationBuffer
