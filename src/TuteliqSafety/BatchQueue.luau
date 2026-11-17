--!strict

local HttpService = game:GetService("HttpService")
local Types = require(script.Parent.Types)

local BatchQueue = {}
BatchQueue.__index = BatchQueue

-- Items held while the API asks us to wait. Beyond this the oldest are dropped.
local MAX_PENDING_ITEMS = 500

function BatchQueue.new(
	batchSize: number,
	flushIntervalSeconds: number,
	onFlush: (items: { Types.QueuedItem }) -> (),
	onDrop: ((count: number) -> ())?
): BatchQueue
	local self = setmetatable({}, BatchQueue)
	self._queue = {} :: { Types.QueuedItem }
	self._batchSize = batchSize
	self._flushInterval = flushIntervalSeconds
	self._onFlush = onFlush
	self._onDrop = onDrop
	self._flushThread = nil :: thread?
	self._running = false
	self._resumeAt = 0
	return self
end

function BatchQueue:start()
	if self._running then
		return
	end
	self._running = true

	self._flushThread = task.spawn(function()
		while self._running do
			task.wait(self._flushInterval)
			if #self._queue > 0 then
				self:flush()
			end
		end
	end)
end

function BatchQueue:stop()
	self._running = false
	if self._flushThread then
		task.cancel(self._flushThread)
		self._flushThread = nil
	end
	-- Flush remaining, even while paused: the queue will not run again
	self._resumeAt = 0
	if #self._queue > 0 then
		self:flush()
	end
end

function BatchQueue:_trim()
	local excess = #self._queue - MAX_PENDING_ITEMS
	if excess > 0 then
		for _ = 1, excess do
			table.remove(self._queue, 1)
		end
		if self._onDrop then
			self._onDrop(excess)
		end
	end
end

function BatchQueue:enqueue(
	detectionType: string,
	text: string,
	context: { [string]: any }?,
	player: Player?
)
	local item: Types.QueuedItem = {
		request = {
			id = HttpService:GenerateGUID(false),
			type = detectionType,
			data = {
				text = text,
				context = context or { platform = "Roblox" },
			},
		},
		player = player,
		message = text,
	}

	table.insert(self._queue, item)
	self:_trim()

	if #self._queue >= self._batchSize then
		self:flush()
	end
end

--- Puts items that could not be sent back at the front of the queue.
function BatchQueue:requeue(items: { Types.QueuedItem })
	for i = #items, 1, -1 do
		table.insert(self._queue, 1, items[i])
	end
	self:_trim()
end

--- Holds every flush for the given number of seconds.
function BatchQueue:pauseFor(seconds: number)
	self._resumeAt = math.max(self._resumeAt, os.clock() + seconds)
end

function BatchQueue:isPaused(): boolean
	return os.clock() < self._resumeAt
end

function BatchQueue:flush()
	if #self._queue == 0 or self:isPaused() then
		return
	end

	-- Take current batch and clear queue
	local items = self._queue
	self._queue = {}

	-- Split into chunks of batchSize (max 50 per API call)
	local maxPerRequest = math.min(self._batchSize, 50)
	for i = 1, #items, maxPerRequest do
		local chunk = {}
		for j = i, math.min(i + maxPerRequest - 1, #items) do
			table.insert(chunk, items[j])
		end
		task.spawn(function()
			self._onFlush(chunk)
		end)
	end
end

function BatchQueue:getPendingCount(): number
	return #self._queue
end

export type BatchQueue = typeof(BatchQueue.new(0, 0, function() end))

return BatchQueue
