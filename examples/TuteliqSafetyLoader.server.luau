--[[
	TuteliqSafety Loader - Example Server Script

	Place this in ServerScriptService to start monitoring chat.
	Customize the config below to match your needs.

	IMPORTANT: Store your API key securely. In production, use
	a Secret Store or environment variable rather than hardcoding.
]]

local TuteliqSafety = require(script.Parent.TuteliqSafety)

-- Start monitoring with your configuration
TuteliqSafety.start({
	apiKey = "tq_live_YOUR_API_KEY_HERE", -- Replace with your Tuteliq API key
	sensitivity = "high",                  -- low | medium | high | maximum
	detect = { "bullying", "grooming", "unsafe" },
	actions = {
		mute = true,          -- Mute flagged players temporarily
		kick = false,         -- Kick on critical severity (disabled by default)
		notifyAdmins = true,  -- Fire TuteliqAlert BindableEvent
		log = true,           -- Log detections to output
	},
	muteDurationSeconds = 60,
	-- webhookUrl = "https://your-webhook.example.com/alerts", -- Optional
})

-- Optional: Listen for detections to build custom admin UI
local alertEvent = TuteliqSafety.onDetection()
if alertEvent then
	alertEvent.Event:Connect(function(data)
		-- data contains: type, severity, confidence, riskScore, rationale,
		--                recommendedAction, playerName, playerId, message, timestamp

		-- Example: Print to admin console
		print(string.format(
			"[SAFETY ALERT] %s detected | Severity: %s | Player: %s | %s",
			data.type,
			data.severity,
			data.playerName or "unknown",
			data.rationale or ""
		))

		-- Example: Send to admin players via RemoteEvent
		-- local adminRemote = game.ReplicatedStorage:FindFirstChild("AdminAlert")
		-- if adminRemote then
		--     for _, player in game.Players:GetPlayers() do
		--         if player:GetRankInGroup(YOUR_GROUP_ID) >= 200 then
		--             adminRemote:FireClient(player, data)
		--         end
		--     end
		-- end
	end)
end

print("[Tuteliq] Safety monitoring active")
