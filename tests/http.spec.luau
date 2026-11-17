local Harness = require("./harness")
local Expect = require("./expect")

local function client(world)
	local Logger = world.load("Logger")
	local HttpClient = world.load("HttpClient")
	return HttpClient.new("tq_test_invented_key", Logger.new("error"))
end

return {
	["the error envelope is read as code and message"] = function()
		local world = Harness.new()
		world.respond = function()
			return {
				StatusCode = 401,
				Body = { error = { code = "AUTH_1001", message = "Invalid API key" } },
			}
		end
		local response = client(world):analyzeUnsafe("an invented message")
		Expect.falsy(response.success, "success")
		Expect.equal(response.error, "AUTH_1001: Invalid API key", "error")
		Expect.equal(response.errorCode, "AUTH_1001", "errorCode")
	end,

	["429 reports when to retry from Retry-After"] = function()
		local world = Harness.new()
		world.respond = function()
			return {
				StatusCode = 429,
				Headers = { ["retry-after"] = "3" },
				Body = { error = { code = "RATE_LIMIT", message = "Too many requests", retryable = true } },
			}
		end
		local response = client(world):analyzeUnsafe("an invented message")
		Expect.equal(response.retryAfterSeconds, 3, "retryAfterSeconds")
	end,

	["429 without the header falls back to retry_after_ms"] = function()
		local world = Harness.new()
		world.respond = function()
			return {
				StatusCode = 429,
				Body = { error = { code = "RATE_LIMIT", message = "Too many requests", retry_after_ms = 2500 } },
			}
		end
		local response = client(world):analyzeUnsafe("an invented message")
		Expect.equal(response.retryAfterSeconds, 2.5, "retryAfterSeconds")
	end,

	["requests identify the SDK version"] = function()
		local world = Harness.new()
		client(world):analyzeUnsafe("an invented message")
		Expect.equal(world.requests[1].headers["User-Agent"], "Tuteliq-Roblox/1.1.0", "User-Agent")
	end,
}
