--!strict

local Types = require(script.Parent.Types)
local Logger = require(script.Parent.Logger)

local ActionDispatcher = {}
ActionDispatcher.__index = ActionDispatcher

local SEVERITY_LEVELS: { [string]: number } = {
	low = 1,
	medium = 2,
	high = 3,
	critical = 4,
}

function ActionDispatcher.new(config: Types.Config, logger: Logger.Logger, httpClient: any): ActionDispatcher
	local self = setmetatable({}, ActionDispatcher)
	self._config = config
	self._logger = logger
	self._httpClient = httpClient
	self._alertEvent = nil :: BindableEvent?
	self:_setupAlertEvent()
	return self
end

function ActionDispatcher:_setupAlertEvent()
	local existing = game:GetService("ServerStorage"):FindFirstChild("TuteliqAlert")
	if existing then
		self._alertEvent = existing :: BindableEvent
	else
		local event = Instance.new("BindableEvent")
		event.Name = "TuteliqAlert"
		event.Parent = game:GetService("ServerStorage")
		self._alertEvent = event
	end
end

function ActionDispatcher:getAlertEvent(): BindableEvent?
	return self._alertEvent
end

function ActionDispatcher:dispatch(result: Types.DetectionResult)
	local severityLevel = SEVERITY_LEVELS[result.severity] or 0
	local player = result.player

	-- Always log if enabled
	if self._config.actions.log then
		self._logger:warn("Detection triggered", {
			type = result.type,
			severity = result.severity,
			confidence = result.confidence,
			riskScore = result.riskScore,
			player = if player then player.Name else "unknown",
			rationale = result.rationale,
		})
	end

	-- Notify admins on medium+ severity
	if self._config.actions.notifyAdmins and severityLevel >= SEVERITY_LEVELS.medium then
		self:_notifyAdmins(result)
	end

	-- Mute on high+ severity
	if self._config.actions.mute and severityLevel >= SEVERITY_LEVELS.high and player then
		self:_mutePlayer(player)
	end

	-- Kick on critical severity (if enabled)
	if self._config.actions.kick and severityLevel >= SEVERITY_LEVELS.critical and player then
		self:_kickPlayer(player, result)
	end

	-- Webhook if configured
	if self._config.webhookUrl and severityLevel >= SEVERITY_LEVELS.medium then
		self:_sendWebhook(result)
	end
end

function ActionDispatcher:_notifyAdmins(result: Types.DetectionResult)
	if self._alertEvent then
		self._alertEvent:Fire({
			type = result.type,
			severity = result.severity,
			confidence = result.confidence,
			riskScore = result.riskScore,
			rationale = result.rationale,
			recommendedAction = result.recommendedAction,
			playerName = if result.player then result.player.Name else nil,
			playerId = if result.player then result.player.UserId else nil,
			message = result.message,
			timestamp = os.time(),
		})
	end
end

function ActionDispatcher:_mutePlayer(player: Player)
	player:SetAttribute("TuteliqMuted", true)
	self._logger:info("Player muted", {
		player = player.Name,
		duration = self._config.muteDurationSeconds,
	})

	task.delay(self._config.muteDurationSeconds, function()
		if player and player.Parent then
			player:SetAttribute("TuteliqMuted", false)
			self._logger:info("Player unmuted", { player = player.Name })
		end
	end)
end

function ActionDispatcher:_kickPlayer(player: Player, result: Types.DetectionResult)
	self._logger:warn("Kicking player", {
		player = player.Name,
		reason = result.type,
	})
	player:Kick("You have been removed for violating community safety guidelines.")
end

function ActionDispatcher:_sendWebhook(result: Types.DetectionResult)
	task.spawn(function()
		self._httpClient:sendWebhook(self._config.webhookUrl, {
			event = "detection",
			type = result.type,
			severity = result.severity,
			confidence = result.confidence,
			riskScore = result.riskScore,
			rationale = result.rationale,
			recommendedAction = result.recommendedAction,
			playerName = if result.player then result.player.Name else nil,
			playerId = if result.player then result.player.UserId else nil,
			gameId = game.GameId,
			placeId = game.PlaceId,
			timestamp = os.time(),
		})
	end)
end

export type ActionDispatcher = typeof(ActionDispatcher.new({} :: any, Logger.new(), {}))

return ActionDispatcher
