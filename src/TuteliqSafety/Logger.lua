--!strict

local Logger = {}
Logger.__index = Logger

type LogLevel = "debug" | "info" | "warn" | "error"

local LOG_LEVELS: { [LogLevel]: number } = {
	debug = 0,
	info = 1,
	warn = 2,
	error = 3,
}

function Logger.new(minLevel: LogLevel?): Logger
	local self = setmetatable({}, Logger)
	self._minLevel = minLevel or "info"
	return self
end

function Logger:_shouldLog(level: LogLevel): boolean
	return LOG_LEVELS[level] >= LOG_LEVELS[self._minLevel]
end

function Logger:_format(level: LogLevel, message: string, data: { [string]: any }?): string
	local timestamp = os.date("%Y-%m-%dT%H:%M:%S")
	local parts = { `[Tuteliq][{level:upper()}][{timestamp}] {message}` }

	if data then
		for key, value in data do
			table.insert(parts, `  {key}={tostring(value)}`)
		end
	end

	return table.concat(parts, " |")
end

function Logger:debug(message: string, data: { [string]: any }?)
	if self:_shouldLog("debug") then
		print(self:_format("debug", message, data))
	end
end

function Logger:info(message: string, data: { [string]: any }?)
	if self:_shouldLog("info") then
		print(self:_format("info", message, data))
	end
end

function Logger:warn(message: string, data: { [string]: any }?)
	if self:_shouldLog("warn") then
		warn(self:_format("warn", message, data))
	end
end

function Logger:error(message: string, data: { [string]: any }?)
	if self:_shouldLog("error") then
		warn(self:_format("error", message, data))
	end
end

export type Logger = typeof(Logger.new())

return Logger
