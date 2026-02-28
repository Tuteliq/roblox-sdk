--!strict

local HttpService = game:GetService("HttpService")
local Types = require(script.Parent.Types)
local Logger = require(script.Parent.Logger)

local BatchQueue = {}
BatchQueue.__index = BatchQueue

function BatchQueue.new(
	batchSize: number,
	flushIntervalSeconds: number,
	onFlush: (items: { Types.BatchItem }) -> ()
): BatchQueue
	local self = setmetatable({}, BatchQueue)
	self._queue = {} :: { Types.BatchItem }
	self._batchSize = batchSize
	self._flushInterval = flushIntervalSeconds
	self._onFlush = onFlush
	self._flushThread = nil :: thread?
	self._running = false
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
	-- Flush remaining
	if #self._queue > 0 then
		self:flush()
	end
end

function BatchQueue:enqueue(detectionType: string, text: string, context: { [string]: any }?)
	local item: Types.BatchItem = {
		id = HttpService:GenerateGUID(false),
		type = detectionType,
		data = {
			text = text,
			context = context or { platform = "Roblox" },
		},
	}

	table.insert(self._queue, item)

	if #self._queue >= self._batchSize then
		self:flush()
	end
end

function BatchQueue:flush()
	if #self._queue == 0 then
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
