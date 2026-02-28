--!strict

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(maxTokens: number, refillRate: number): RateLimiter
	local self = setmetatable({}, RateLimiter)
	self._maxTokens = maxTokens
	self._tokens = maxTokens
	self._refillRate = refillRate -- tokens per second
	self._lastRefill = os.clock()
	return self
end

function RateLimiter:_refill()
	local now = os.clock()
	local elapsed = now - self._lastRefill
	local tokensToAdd = elapsed * self._refillRate
	self._tokens = math.min(self._maxTokens, self._tokens + tokensToAdd)
	self._lastRefill = now
end

function RateLimiter:tryConsume(count: number?): boolean
	self:_refill()
	local needed = count or 1
	if self._tokens >= needed then
		self._tokens -= needed
		return true
	end
	return false
end

function RateLimiter:getAvailable(): number
	self:_refill()
	return math.floor(self._tokens)
end

export type RateLimiter = typeof(RateLimiter.new(0, 0))

return RateLimiter
