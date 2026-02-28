--!strict

local Types = require(script.Parent.Types)

local Config = {}

local SENSITIVITY_THRESHOLDS: { [Types.SensitivityLevel]: number } = {
	low = 0.7,
	medium = 0.5,
	high = 0.3,
	maximum = 0.1,
}

local DEFAULTS: Types.Config = {
	apiKey = "",
	sensitivity = "medium",
	detect = { "bullying", "grooming", "unsafe" },
	actions = {
		mute = true,
		kick = false,
		notifyAdmins = true,
		log = true,
	},
	muteDurationSeconds = 60,
	batchSize = 25,
	batchFlushIntervalSeconds = 5,
	httpBudgetPerMinute = 400,
	webhookUrl = nil,
}

function Config.validate(userConfig: Types.UserConfig): (boolean, string?)
	if not userConfig.apiKey or userConfig.apiKey == "" then
		return false, "apiKey is required"
	end

	if not userConfig.apiKey:match("^tq_") then
		return false, "apiKey must start with 'tq_'"
	end

	if userConfig.sensitivity then
		if not SENSITIVITY_THRESHOLDS[userConfig.sensitivity] then
			return false, "sensitivity must be one of: low, medium, high, maximum"
		end
	end

	if userConfig.detect then
		local validTypes = { bullying = true, grooming = true, unsafe = true }
		for _, dt in userConfig.detect do
			if not validTypes[dt] then
				return false, `invalid detection type: {dt}. Must be one of: bullying, grooming, unsafe`
			end
		end
	end

	if userConfig.batchSize and (userConfig.batchSize < 1 or userConfig.batchSize > 50) then
		return false, "batchSize must be between 1 and 50"
	end

	if userConfig.httpBudgetPerMinute and userConfig.httpBudgetPerMinute < 10 then
		return false, "httpBudgetPerMinute must be at least 10"
	end

	return true, nil
end

function Config.merge(userConfig: Types.UserConfig): Types.Config
	local config: Types.Config = {
		apiKey = userConfig.apiKey,
		sensitivity = userConfig.sensitivity or DEFAULTS.sensitivity,
		detect = userConfig.detect or DEFAULTS.detect,
		actions = DEFAULTS.actions,
		muteDurationSeconds = userConfig.muteDurationSeconds or DEFAULTS.muteDurationSeconds,
		batchSize = userConfig.batchSize or DEFAULTS.batchSize,
		batchFlushIntervalSeconds = userConfig.batchFlushIntervalSeconds or DEFAULTS.batchFlushIntervalSeconds,
		httpBudgetPerMinute = userConfig.httpBudgetPerMinute or DEFAULTS.httpBudgetPerMinute,
		webhookUrl = userConfig.webhookUrl,
	}

	if userConfig.actions then
		config.actions = {
			mute = if userConfig.actions.mute ~= nil then userConfig.actions.mute else DEFAULTS.actions.mute,
			kick = if userConfig.actions.kick ~= nil then userConfig.actions.kick else DEFAULTS.actions.kick,
			notifyAdmins = if userConfig.actions.notifyAdmins ~= nil then userConfig.actions.notifyAdmins else DEFAULTS.actions.notifyAdmins,
			log = if userConfig.actions.log ~= nil then userConfig.actions.log else DEFAULTS.actions.log,
		}
	end

	return config
end

function Config.getThreshold(sensitivity: Types.SensitivityLevel): number
	return SENSITIVITY_THRESHOLDS[sensitivity]
end

return Config
