--!strict

--[[
	TuteliqSafety - Roblox Child Safety Moderation Module

	Monitors in-game chat for grooming, bullying, and unsafe content
	via the Tuteliq API. Drop-in module for any Roblox experience.

	Usage:
		local TuteliqSafety = require(game.ServerScriptService.TuteliqSafety)
		TuteliqSafety.start({
			apiKey = "tq_live_...",
			sensitivity = "medium",
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
local ActionDispatcher = require(script.ActionDispatcher)
local Verdict = require(script.Verdict)

local TuteliqSafety = {}

local _config: Types.Config? = nil
local _logger: Logger.Logger? = nil
local _httpClient: HttpClient.HttpClient? = nil
local _rateLimiter: RateLimiter.RateLimiter? = nil
local _batchQueue: BatchQueue.BatchQueue? = nil
local _conversationBuffer: ConversationBuffer.ConversationBuffer? = nil
local _actionDispatcher: ActionDispatcher.ActionDispatcher? = nil
local _connections: { RBXScriptConnection } = {}
local _running = false

local MIN_MESSAGE_LENGTH = 3
-- Conversations started per message: the sender with each of the players
-- who spoke most recently in the same channel.
local MAX_PARTNERS_PER_MESSAGE = 3
-- Wait before retrying a batch held back by the local HTTP budget.
local LOCAL_BUDGET_RETRY_SECONDS = 1
-- Wait before retrying a retryable failure that named no wait.
local DEFAULT_RETRY_SECONDS = 5

-- Detection types analysed one message at a time, through the batch queue.
local SINGLE_MESSAGE_TYPES: { Types.DetectionType } = { "bullying", "unsafe" }

local function detects(detectionType: Types.DetectionType): boolean
	local config = _config :: Types.Config
	return table.find(config.detect, detectionType) ~= nil
end

local function isReported(detectionType: Types.DetectionType, body: { [string]: any }): boolean
	local config = _config :: Types.Config
	return Verdict.isReported(
		detectionType,
		body,
		Config.getMinimumAction(config.sensitivity),
		config.sensitivity == "maximum"
	)
end

local function newResult(detectionType: Types.DetectionType, body: { [string]: any }): Types.DetectionResult
	return {
		detected = true,
		type = detectionType,
		severity = (if detectionType == "grooming" then body.grooming_risk else body.severity) or "low",
		confidence = body.confidence or 0,
		riskScore = body.risk_score or 0,
		rationale = body.rationale or "",
		recommendedAction = Verdict.actionOf(detectionType, body),
		player = nil,
		actionTarget = nil,
		needsSupport = false,
		participants = nil,
		message = nil,
	}
end

local function dispatch(result: Types.DetectionResult)
	local dispatcher = _actionDispatcher :: ActionDispatcher.ActionDispatcher
	dispatcher:dispatch(result)
end

--- Acts on a bullying or unsafe-content result for one message.
local function processSingleResult(
	detectionType: Types.DetectionType,
	body: { [string]: any },
	player: Player?,
	message: string?
)
	if not isReported(detectionType, body) then
		return
	end

	local harmsOthers = Verdict.speakerHarmsOthers(detectionType, body)
	local result = newResult(detectionType, body)
	result.player = player
	result.actionTarget = if harmsOthers then player else nil
	result.needsSupport = not harmsOthers
	result.message = message
	dispatch(result)
end

--- The one player a grooming tactic is attributed to. Nobody when the
--- attributed roles cover both players or only the child.
local function groomingTarget(
	body: { [string]: any },
	conversation: Types.Conversation,
	players: { [number]: Player }
): Player?
	local attributed = Verdict.attributedRoles(body)
	local holders: { Player } = {}
	for userId, role in conversation.roles do
		if role ~= "child" and attributed[role] then
			table.insert(holders, players[userId])
		end
	end
	return if #holders == 1 then holders[1] else nil
end

--- Acts on a grooming result for the conversation between two players.
local function processGroomingResult(
	body: { [string]: any },
	conversation: Types.Conversation,
	players: { [number]: Player }
)
	if not isReported("grooming", body) then
		return
	end

	local participants: { Player } = {}
	for _, participant in players do
		table.insert(participants, participant)
	end
	table.sort(participants, function(a, b)
		return a.UserId < b.UserId
	end)

	local target = if Verdict.isDisclosure(body) then nil else groomingTarget(body, conversation, players)
	local result = newResult("grooming", body)
	result.player = target
	result.actionTarget = target
	result.needsSupport = Verdict.isDisclosure(body)
	result.participants = participants
	dispatch(result)
end

local function handleBatchFlush(items: { Types.QueuedItem })
	local logger = _logger :: Logger.Logger
	local batchQueue = _batchQueue :: BatchQueue.BatchQueue
	local rateLimiter = _rateLimiter :: RateLimiter.RateLimiter
	if not rateLimiter:tryConsume(1) then
		logger:warn("HTTP budget reached, holding batch", { count = #items })
		batchQueue:requeue(items)
		batchQueue:pauseFor(LOCAL_BUDGET_RETRY_SECONDS)
		return
	end

	local requests: { Types.BatchItem } = {}
	local byId: { [string]: Types.QueuedItem } = {}
	for _, item in items do
		table.insert(requests, item.request)
		byId[item.request.id] = item
	end

	local httpClient = _httpClient :: HttpClient.HttpClient
	local response = httpClient:batchAnalyze(requests)

	if not response.success then
		local retryable = response.statusCode == 429
			or (response.body and type(response.body.error) == "table" and response.body.error.retryable == true)
		if retryable then
			local delaySeconds = response.retryAfterSeconds or DEFAULT_RETRY_SECONDS
			logger:warn("API asked to retry later, holding batch", { count = #items, seconds = delaySeconds })
			batchQueue:requeue(items)
			batchQueue:pauseFor(delaySeconds)
		end
		return
	end

	for _, result in (response.body :: { [string]: any }).results or {} do
		local item = byId[result.id]
		if item and result.success and result.result then
			processSingleResult(result.type :: Types.DetectionType, result.result, item.player, item.message)
		end
	end
end

local function analyseConversation(channel: string, sender: Player, partnerId: number)
	local conversationBuffer = _conversationBuffer :: ConversationBuffer.ConversationBuffer
	local rateLimiter = _rateLimiter :: RateLimiter.RateLimiter
	local partner = Players:GetPlayerByUserId(partnerId)
	if not partner or not conversationBuffer:shouldAnalyze(channel, sender.UserId, partnerId) then
		return
	end
	if not rateLimiter:tryConsume(1) then
		return
	end

	local conversation = conversationBuffer:getConversation(channel, sender.UserId, partnerId)
	local players = { [sender.UserId] = sender, [partnerId] = partner }
	task.spawn(function()
		local httpClient = _httpClient :: HttpClient.HttpClient
		local context: { [string]: any } = { platform = "Roblox" }
		if conversation.childAge then
			context.child_age = conversation.childAge
		end
		local response = httpClient:analyzeGrooming(conversation.messages, context)
		if response.success and response.body then
			processGroomingResult(response.body, conversation, players)
		end
	end)
end

local function ageOf(player: Player): number?
	local config = _config :: Types.Config
	if not config.getPlayerAge then
		return nil
	end
	local ok, age = pcall(config.getPlayerAge, player)
	if ok and type(age) == "number" then
		return age
	end
	return nil
end

--- A whisper is its own channel; everything else is the server's channel.
local function channelFor(player: Player, recipient: Player?): string
	if recipient then
		local a, b = math.min(player.UserId, recipient.UserId), math.max(player.UserId, recipient.UserId)
		return `whisper:{a}:{b}`
	end
	return "server"
end

local function onPlayerChatted(player: Player, message: string, recipient: Player?)
	if not _running then
		return
	end

	-- Skip short messages
	if #message < MIN_MESSAGE_LENGTH then
		return
	end

	local channel = channelFor(player, recipient)

	-- 1. Grooming: analyse the sender's conversations with recent partners
	if detects("grooming") then
		local conversationBuffer = _conversationBuffer :: ConversationBuffer.ConversationBuffer
		conversationBuffer:push(channel, {
			sender = player.Name,
			senderId = player.UserId,
			senderAge = ageOf(player),
			text = message,
			timestamp = os.clock(),
			channel = channel,
		})
		for _, partnerId in conversationBuffer:partnersOf(channel, player.UserId, MAX_PARTNERS_PER_MESSAGE) do
			analyseConversation(channel, player, partnerId)
		end
	end

	-- 2. Every message is analysed for each single-message type, keeping the
	-- player so a hit can act on them
	local batchQueue = _batchQueue :: BatchQueue.BatchQueue
	for _, detectionType in SINGLE_MESSAGE_TYPES do
		if detects(detectionType) then
			batchQueue:enqueue(detectionType, message, { platform = "Roblox" }, player)
		end
	end
end

local function connectPlayer(player: Player)
	local connection = player.Chatted:Connect(function(message: string, recipient: Player?)
		onPlayerChatted(player, message, recipient)
	end)
	table.insert(_connections, connection)
end

local function disconnectPlayer(player: Player)
	if _conversationBuffer then
		local buffer = _conversationBuffer :: ConversationBuffer.ConversationBuffer
		buffer:removeSender(player.UserId)
	end
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
	_conversationBuffer = ConversationBuffer.new()

	_batchQueue = BatchQueue.new(config.batchSize, config.batchFlushIntervalSeconds, handleBatchFlush, function(count)
		logger:warn("Too many messages waiting, dropped the oldest", { count = count })
	end)

	_actionDispatcher = ActionDispatcher.new(config, logger, _httpClient)

	-- Hook existing players
	for _, player in Players:GetPlayers() do
		connectPlayer(player)
	end

	-- Hook new players
	local addedConn = Players.PlayerAdded:Connect(connectPlayer)
	table.insert(_connections, addedConn)

	-- Forget what a player said once they leave
	local removingConn = Players.PlayerRemoving:Connect(disconnectPlayer)
	table.insert(_connections, removingConn)

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

		if response.success and response.body then
			processSingleResult(dtype, response.body, player, text)
		end
	end)
end

--- Check if the module is currently running.
function TuteliqSafety.isRunning(): boolean
	return _running
end

return TuteliqSafety
