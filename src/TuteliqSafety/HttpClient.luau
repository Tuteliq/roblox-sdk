--!strict

local HttpService = game:GetService("HttpService")
local Types = require(script.Parent.Types)
local Logger = require(script.Parent.Logger)
local VERSION = require(script.Parent.Version)

local HttpClient = {}
HttpClient.__index = HttpClient

local BASE_URL = "https://api.tuteliq.ai"

--- The API's error envelope, { error = { code, message } }, as one line and its code.
local function describeError(body: { [string]: any }?, statusCode: number): (string, string?)
	local err = if body then body.error else nil
	if type(err) == "table" then
		local code = if type(err.code) == "string" then err.code else nil
		local message = if type(err.message) == "string" then err.message else `HTTP {statusCode}`
		return if code then `{code}: {message}` else message, code
	elseif type(err) == "string" then
		return err, nil
	end
	return `HTTP {statusCode}`, nil
end

--- Seconds to wait before retrying: the Retry-After header, else the envelope's retry_after_ms.
local function retryAfterSeconds(headers: { [string]: string }?, body: { [string]: any }?): number?
	for name, value in headers or {} do
		if string.lower(name) == "retry-after" then
			local seconds = tonumber(value)
			if seconds then
				return seconds
			end
		end
	end
	local err = if body then body.error else nil
	if type(err) == "table" and type(err.retry_after_ms) == "number" then
		return err.retry_after_ms / 1000
	end
	return nil
end

function HttpClient.new(apiKey: string, logger: Logger.Logger): HttpClient
	local self = setmetatable({}, HttpClient)
	self._apiKey = apiKey
	self._logger = logger
	return self
end

function HttpClient:_makeRequest(method: string, path: string, body: { [string]: any }?): Types.HttpResponse
	local url = BASE_URL .. path
	local headers = {
		["Authorization"] = "Bearer " .. self._apiKey,
		["Content-Type"] = "application/json",
		["X-Request-ID"] = HttpService:GenerateGUID(false),
		["User-Agent"] = `Tuteliq-Roblox/{VERSION}`,
	}

	local requestBody: string? = nil
	if body then
		requestBody = HttpService:JSONEncode(body)
	end

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = method,
			Headers = headers,
			Body = requestBody,
		})
	end)

	if not success then
		self._logger:error("HTTP request failed", { url = url, error = tostring(response) })
		return {
			success = false,
			statusCode = 0,
			body = nil,
			error = tostring(response),
			errorCode = nil,
			retryAfterSeconds = nil,
		}
	end

	local responseBody: { [string]: any }? = nil
	if response.Body and response.Body ~= "" then
		local decodeSuccess, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if decodeSuccess then
			responseBody = decoded
		end
	end

	local isSuccess = response.StatusCode >= 200 and response.StatusCode < 300
	if isSuccess then
		return {
			success = true,
			statusCode = response.StatusCode,
			body = responseBody,
			error = nil,
			errorCode = nil,
			retryAfterSeconds = nil,
		}
	end

	local errorMsg, errorCode = describeError(responseBody, response.StatusCode)
	local retryAfter = retryAfterSeconds(response.Headers, responseBody)
	self._logger:warn("API error", {
		url = url,
		status = response.StatusCode,
		error = errorMsg,
		retryAfter = retryAfter,
	})

	return {
		success = false,
		statusCode = response.StatusCode,
		body = responseBody,
		error = errorMsg,
		errorCode = errorCode,
		retryAfterSeconds = retryAfter,
	}
end

function HttpClient:analyzeBullying(text: string, context: { [string]: any }?): Types.HttpResponse
	return self:_makeRequest("POST", "/api/v1/safety/bullying", {
		text = text,
		context = context or { platform = "Roblox" },
	})
end

function HttpClient:analyzeGrooming(messages: { Types.ConversationMessage }, context: { [string]: any }?): Types.HttpResponse
	return self:_makeRequest("POST", "/api/v1/safety/grooming", {
		messages = messages,
		context = context or { platform = "Roblox" },
	})
end

function HttpClient:analyzeUnsafe(text: string, context: { [string]: any }?): Types.HttpResponse
	return self:_makeRequest("POST", "/api/v1/safety/unsafe", {
		text = text,
		context = context or { platform = "Roblox" },
	})
end

function HttpClient:batchAnalyze(items: { Types.BatchItem }): Types.HttpResponse
	return self:_makeRequest("POST", "/api/v1/batch/analyze", {
		items = items,
		parallel = true,
	})
end

function HttpClient:sendWebhook(url: string, payload: { [string]: any }): Types.HttpResponse
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode(payload),
		})
	end)

	if not success then
		return { success = false, statusCode = 0, body = nil, error = tostring(response), errorCode = nil, retryAfterSeconds = nil }
	end

	return {
		success = response.StatusCode >= 200 and response.StatusCode < 300,
		statusCode = response.StatusCode,
		body = nil,
		error = nil,
		errorCode = nil,
		retryAfterSeconds = nil,
	}
end

export type HttpClient = typeof(HttpClient.new("", Logger.new()))

return HttpClient
