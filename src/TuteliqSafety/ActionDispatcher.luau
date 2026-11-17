--!strict

local Types = require(script.Parent.Types)
local Logger = require(script.Parent.Logger)
local Verdict = require(script.Parent.Verdict)

local ActionDispatcher = {}
ActionDispatcher.__index = ActionDispatcher

local MUTE_FROM = Verdict.rank("block")
local KICK_FROM = Verdict.rank("immediate_intervention")

local function describeParticipants(result: Types.DetectionResult): { { playerName: string, playerId: number } }?
	if not result.participants then
		return nil
	end
	local described = {}
	for _, participant in result.participants do
		table.insert(described, { playerName = participant.Name, playerId = participant.UserId })
	end
	return described
end

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

--- Acts on a reported detection. Every detection reaches admins and the
--- webhook; mute and kick only ever apply to `actionTarget`, a player
--- harming someone else.
function ActionDispatcher:dispatch(result: Types.DetectionResult)
	local actionRank = Verdict.rank(result.recommendedAction)
	local player = result.player
	local target = result.actionTarget

	-- Always log if enabled
	if self._config.actions.log then
		self._logger:warn("Detection triggered", {
			type = result.type,
			recommendedAction = result.recommendedAction,
			severity = result.severity,
			riskScore = result.riskScore,
			needsSupport = result.needsSupport,
			player = if player then player.Name else "unknown",
		})
	end

	if self._config.actions.notifyAdmins then
		self:_notifyAdmins(result)
	end

	if self._config.actions.mute and target and actionRank >= MUTE_FROM then
		self:_mutePlayer(target)
	end

	if self._config.actions.kick and target and actionRank >= KICK_FROM then
		self:_kickPlayer(target, result)
	end

	if self._config.webhookUrl then
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
			needsSupport = result.needsSupport,
			participants = describeParticipants(result),
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
			needsSupport = result.needsSupport,
			participants = describeParticipants(result),
			gameId = game.GameId,
			placeId = game.PlaceId,
			timestamp = os.time(),
		})
	end)
end

export type ActionDispatcher = typeof(ActionDispatcher.new({} :: any, Logger.new(), {}))

return ActionDispatcher
