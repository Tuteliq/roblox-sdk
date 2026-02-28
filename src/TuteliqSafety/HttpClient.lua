--!strict

local HttpService = game:GetService("HttpService")
local Types = require(script.Parent.Types)
local Logger = require(script.Parent.Logger)

local HttpClient = {}
HttpClient.__index = HttpClient

local BASE_URL = "https://api.tuteliq.ai"
local REQUEST_TIMEOUT = 30

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
		["User-Agent"] = "Tuteliq-Roblox/1.0.0",
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

	if not isSuccess then
		local errorMsg = if responseBody and responseBody.error
			then tostring(responseBody.error)
			else `HTTP {response.StatusCode}`
		self._logger:warn("API error", {
			url = url,
			status = response.StatusCode,
			error = errorMsg,
		})
	end

	return {
		success = isSuccess,
		statusCode = response.StatusCode,
		body = responseBody,
		error = if not isSuccess then (if responseBody and responseBody.error then tostring(responseBody.error) else `HTTP {response.StatusCode}`) else nil,
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
		return { success = false, statusCode = 0, body = nil, error = tostring(response) }
	end

	return {
		success = response.StatusCode >= 200 and response.StatusCode < 300,
		statusCode = response.StatusCode,
		body = nil,
		error = nil,
	}
end

export type HttpClient = typeof(HttpClient.new("", Logger.new()))

return HttpClient
