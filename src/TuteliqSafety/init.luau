--!strict

--[[
	TuteliqSafety - Roblox Child Safety Moderation Module

	Monitors in-game chat for grooming, bullying, and unsafe content
	via the Tuteliq API. Drop-in module for any Roblox experience.

	Usage:
		local TuteliqSafety = require(game.ServerScriptService.TuteliqSafety)
		TuteliqSafety.start({
			apiKey = "tq_live_...",
			sensitivity = "high",
			detect = { "bullying", "grooming", "unsafe" },
		})
]]

local Players = game:GetService("Players")

local Types = require(script.Types)
local Config = require(script.Config)
local Logger = require(script.Logger)
local HttpClient = require(script.HttpClient)
local RateLimiter = require(script.RateLimiter)
local BatchQueue = require(script.BatchQueue)
local ConversationBuffer = require(script.ConversationBuffer)
local CrisisDetector = require(script.CrisisDetector)
local ActionDispatcher = require(script.ActionDispatcher)

local TuteliqSafety = {}

local _config: Types.Config? = nil
local _logger: Logger.Logger? = nil
local _httpClient: HttpClient.HttpClient? = nil
local _rateLimiter: RateLimiter.RateLimiter? = nil
local _batchQueue: BatchQueue.BatchQueue? = nil
local _conversationBuffer: ConversationBuffer.ConversationBuffer? = nil
local _crisisDetector: CrisisDetector.CrisisDetector? = nil
local _actionDispatcher: ActionDispatcher.ActionDispatcher? = nil
local _connections: { RBXScriptConnection } = {}
local _running = false

local MIN_MESSAGE_LENGTH = 3

local function getDetectionTypeForBatch(detectionTypes: { Types.DetectionType }): string
	-- For batch, default to bullying if detecting it, otherwise unsafe
	for _, dt in detectionTypes do
		if dt == "bullying" then
			return "bullying"
		end
	end
	return "unsafe"
end

local function getSeverityFromResponse(responseType: string, body: { [string]: any }): string
	if responseType == "bullying" then
		return body.severity or "low"
	elseif responseType == "grooming" then
		local risk = body.grooming_risk or "none"
		if risk == "none" then return "low" end
		return risk
	elseif responseType == "unsafe" then
		return body.severity or "low"
	end
	return "low"
end

local function isDetected(responseType: string, body: { [string]: any }, threshold: number): boolean
	local riskScore = body.risk_score or body.confidence or 0

	if responseType == "bullying" then
		return body.is_bullying == true and riskScore >= threshold
	elseif responseType == "grooming" then
		local risk = body.grooming_risk or "none"
		return risk ~= "none" and riskScore >= threshold
	elseif responseType == "unsafe" then
		return body.unsafe == true and riskScore >= threshold
	end

	return false
end

local function processApiResponse(
	responseType: Types.DetectionType,
	response: Types.HttpResponse,
	player: Player?,
	message: string?
)
	if not response.success or not response.body then
		return
	end

	local config = _config :: Types.Config
	local threshold = Config.getThreshold(config.sensitivity)
	local body = response.body

	if isDetected(responseType, body, threshold) then
		local result: Types.DetectionResult = {
			detected = true,
			type = responseType,
			severity = getSeverityFromResponse(responseType, body),
			confidence = body.confidence or 0,
			riskScore = body.risk_score or 0,
			rationale = body.rationale or "",
			recommendedAction = body.recommended_action or "",
			player = player,
			message = message,
		}

		local dispatcher = _actionDispatcher :: ActionDispatcher.ActionDispatcher
		dispatcher:dispatch(result)
	end
end

local function handleBatchFlush(items: { Types.BatchItem })
	local rateLimiter = _rateLimiter :: RateLimiter.RateLimiter
	if not rateLimiter:tryConsume(1) then
		local logger = _logger :: Logger.Logger
		logger:warn("Rate limit exceeded, dropping batch", { count = #items })
		return
	end

	local httpClient = _httpClient :: HttpClient.HttpClient
	local response = httpClient:batchAnalyze(items)

	if response.success and response.body and response.body.results then
		for _, result in response.body.results do
			if result.success and result.result then
				local detectionType = result.type :: Types.DetectionType
				local fakeResponse: Types.HttpResponse = {
					success = true,
					statusCode = 200,
					body = result.result,
					error = nil,
				}
				processApiResponse(detectionType, fakeResponse, nil, nil)
			end
		end
	end
end

local function onPlayerChatted(player: Player, message: string)
	if not _running then
		return
	end

	-- Skip short messages
	if #message < MIN_MESSAGE_LENGTH then
		return
	end

	local config = _config :: Types.Config
	local logger = _logger :: Logger.Logger
	local rateLimiter = _rateLimiter :: RateLimiter.RateLimiter

	-- Channel is the server instance (all chat goes to one buffer per server)
	local channel = tostring(game.JobId)

	local chatMessage: Types.ChatMessage = {
		sender = player.Name,
		senderId = player.UserId,
		text = message,
		timestamp = os.clock(),
		channel = channel,
	}

	-- 1. Push to conversation buffer for grooming detection
	local conversationBuffer = _conversationBuffer :: ConversationBuffer.ConversationBuffer
	conversationBuffer:push(channel, chatMessage)

	-- 2. Check crisis keywords → immediate unsafe analysis
	local crisisDetector = _crisisDetector :: CrisisDetector.CrisisDetector
	local isCrisis, matchedPattern = crisisDetector:check(message)

	if isCrisis then
		logger:warn("Crisis keyword detected", {
			player = player.Name,
			pattern = matchedPattern or "",
		})

		if rateLimiter:tryConsume(1) then
			task.spawn(function()
				local httpClient = _httpClient :: HttpClient.HttpClient
				local response = httpClient:analyzeUnsafe(message, {
					platform = "Roblox",
					age_group = "under-18",
				})
				processApiResponse("unsafe", response, player, message)
			end)
		end
		return -- Don't also batch this message
	end

	-- 3. Check grooming buffer readiness
	local detectsGrooming = false
	for _, dt in config.detect do
		if dt == "grooming" then
			detectsGrooming = true
			break
		end
	end

	if detectsGrooming and conversationBuffer:shouldAnalyze(channel) then
		if rateLimiter:tryConsume(1) then
			task.spawn(function()
				local messages = conversationBuffer:getMessages(channel)
				local httpClient = _httpClient :: HttpClient.HttpClient
				local response = httpClient:analyzeGrooming(messages, {
					platform = "Roblox",
				})
				processApiResponse("grooming", response, player, message)
			end)
		end
	end

	-- 4. Enqueue for batch analysis
	local batchQueue = _batchQueue :: BatchQueue.BatchQueue
	local batchType = getDetectionTypeForBatch(config.detect)
	batchQueue:enqueue(batchType, message, {
		platform = "Roblox",
	})
end

local function connectPlayer(player: Player)
	local connection = player.Chatted:Connect(function(message: string)
		onPlayerChatted(player, message)
	end)
	table.insert(_connections, connection)
end

--- Start monitoring chat for safety threats.
function TuteliqSafety.start(userConfig: Types.UserConfig)
	if _running then
		warn("[Tuteliq] Already running. Call stop() first.")
		return
	end

	-- Validate config
	local valid, err = Config.validate(userConfig)
	if not valid then
		error(`[Tuteliq] Invalid config: {err}`)
	end

	-- Initialize
	_config = Config.merge(userConfig)
	local config = _config :: Types.Config

	_logger = Logger.new("info")
	local logger = _logger :: Logger.Logger

	_httpClient = HttpClient.new(config.apiKey, logger)
	_rateLimiter = RateLimiter.new(config.httpBudgetPerMinute, config.httpBudgetPerMinute / 60)
	_crisisDetector = CrisisDetector.new()
	_conversationBuffer = ConversationBuffer.new()

	_batchQueue = BatchQueue.new(config.batchSize, config.batchFlushIntervalSeconds, handleBatchFlush)

	_actionDispatcher = ActionDispatcher.new(config, logger, _httpClient)

	-- Hook existing players
	for _, player in Players:GetPlayers() do
		connectPlayer(player)
	end

	-- Hook new players
	local addedConn = Players.PlayerAdded:Connect(connectPlayer)
	table.insert(_connections, addedConn)

	-- Start batch queue timer
	local batchQueue = _batchQueue :: BatchQueue.BatchQueue
	batchQueue:start()

	_running = true
	logger:info("TuteliqSafety started", {
		sensitivity = config.sensitivity,
		detect = table.concat(config.detect, ","),
		batchSize = config.batchSize,
		httpBudget = config.httpBudgetPerMinute,
	})
end

--- Stop monitoring and clean up.
function TuteliqSafety.stop()
	if not _running then
		return
	end

	_running = false

	-- Disconnect all chat listeners
	for _, conn in _connections do
		conn:Disconnect()
	end
	table.clear(_connections)

	-- Stop batch queue
	if _batchQueue then
		local batchQueue = _batchQueue :: BatchQueue.BatchQueue
		batchQueue:stop()
	end

	-- Clear buffers
	if _conversationBuffer then
		local buffer = _conversationBuffer :: ConversationBuffer.ConversationBuffer
		buffer:clearAll()
	end

	if _logger then
		local logger = _logger :: Logger.Logger
		logger:info("TuteliqSafety stopped")
	end
end

--- Get the BindableEvent for admin notifications.
--- Connect to this to build custom admin UI.
function TuteliqSafety.onDetection(): BindableEvent?
	if _actionDispatcher then
		local dispatcher = _actionDispatcher :: ActionDispatcher.ActionDispatcher
		return dispatcher:getAlertEvent()
	end
	return nil
end

--- Manually analyze a message (bypasses batching).
function TuteliqSafety.analyzeNow(text: string, detectionType: Types.DetectionType?, player: Player?)
	if not _running then
		warn("[Tuteliq] Not running. Call start() first.")
		return
	end

	local dtype: Types.DetectionType = detectionType or "unsafe"
	local httpClient = _httpClient :: HttpClient.HttpClient
	local rateLimiter = _rateLimiter :: RateLimiter.RateLimiter

	if not rateLimiter:tryConsume(1) then
		local logger = _logger :: Logger.Logger
		logger:warn("Rate limit exceeded for manual analysis")
		return
	end

	task.spawn(function()
		local response: Types.HttpResponse

		if dtype == "bullying" then
			response = httpClient:analyzeBullying(text, { platform = "Roblox" })
		elseif dtype == "unsafe" then
			response = httpClient:analyzeUnsafe(text, { platform = "Roblox" })
		else
			warn(`[Tuteliq] analyzeNow does not support type: {dtype}. Use grooming via conversation buffer.`)
			return
		end

		processApiResponse(dtype, response, player, text)
	end)
end

--- Check if the module is currently running.
function TuteliqSafety.isRunning(): boolean
	return _running
end

return TuteliqSafety
