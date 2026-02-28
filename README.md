<p align="center">
  <img src=".github/banner.png" alt="Tuteliq — AI-Powered Child Safety API" width="600" />
</p>

<h1 align="center">Tuteliq Safety for Roblox</h1>

<p align="center">
  AI-powered child safety moderation for Roblox experiences.<br/>
  Detects grooming, bullying, and unsafe content in real-time chat.
</p>

<p align="center">
  <a href="https://github.com/Tuteliq/roblox-sdk/releases/latest"><img src="https://img.shields.io/github/v/release/Tuteliq/roblox-sdk?label=latest&color=00c896" alt="Latest Release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
  <a href="https://docs.tuteliq.ai/integrations/roblox"><img src="https://img.shields.io/badge/docs-tuteliq.ai-00c896" alt="Documentation" /></a>
</p>

---

## Why Tuteliq?

Roblox's default chat filter catches profanity — but **grooming, manipulation, and social engineering bypass word filters entirely**. Tuteliq uses AI to understand *intent and context*, detecting:

- **Grooming & predatory behavior** — trust-building, isolation tactics, boundary testing
- **Bullying & harassment** — targeted abuse, exclusion, intimidation
- **Unsafe content** — requests to move off-platform, personal info solicitation

All processing runs server-side. No client mods, no data leaves Roblox except via your secure API key.

## Quick Start

1. Download `TuteliqSafety.rbxm` from the [latest release](https://github.com/Tuteliq/roblox-sdk/releases/latest)
2. In Roblox Studio, right-click `ServerScriptService` > **Insert from File**
3. Select the downloaded `.rbxm` file
4. Create a server script:

```lua
local TuteliqSafety = require(script.Parent.TuteliqSafety)

TuteliqSafety.start({
    apiKey = "tq_live_YOUR_API_KEY_HERE",
    sensitivity = "high",
    detect = { "bullying", "grooming", "unsafe" },
})
```

That's it — Tuteliq monitors all chat messages automatically.

## Installation

### Roblox Model File (.rbxm)

1. Download `TuteliqSafety.rbxm` from the [latest release](https://github.com/Tuteliq/roblox-sdk/releases/latest)
2. In Roblox Studio, right-click `ServerScriptService` > **Insert from File**
3. Select the downloaded `.rbxm` file

### Creator Store

Search for **Tuteliq Safety** in the [Roblox Creator Store](https://create.roblox.com/store) and add it to your inventory.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `apiKey` | string | *required* | Your Tuteliq API key |
| `sensitivity` | string | `"high"` | Detection sensitivity: `low`, `medium`, `high`, `maximum` |
| `detect` | table | all | Categories to detect: `"bullying"`, `"grooming"`, `"unsafe"` |
| `actions.mute` | boolean | `true` | Mute flagged players temporarily |
| `actions.kick` | boolean | `false` | Kick on critical severity |
| `actions.notifyAdmins` | boolean | `true` | Fire `TuteliqAlert` BindableEvent |
| `actions.log` | boolean | `true` | Log detections to output |
| `muteDurationSeconds` | number | `60` | Mute duration in seconds |
| `webhookUrl` | string | `nil` | Webhook URL for external alerts |

## Listening for Detections

Build custom admin dashboards and alerts by subscribing to detection events:

```lua
local alertEvent = TuteliqSafety.onDetection()
alertEvent.Event:Connect(function(data)
    -- data.type, data.severity, data.confidence, data.riskScore
    -- data.rationale, data.recommendedAction
    -- data.playerName, data.playerId, data.message, data.timestamp
    print(("[ALERT] %s | %s | %s"):format(data.type, data.severity, data.playerName))
end)
```

## How It Works

1. **Chat listener** hooks into `TextChatService` (or legacy `Chat`) automatically
2. **Conversation buffer** maintains per-player context for multi-message analysis
3. **Batch queue** groups messages for efficient API calls with rate limiting
4. **AI analysis** detects harmful intent and context — not just keywords
5. **Action dispatcher** executes configured responses (mute, kick, alert, webhook)

## Documentation

Full documentation, integration guides, and API reference:

**[docs.tuteliq.ai/integrations/roblox](https://docs.tuteliq.ai/integrations/roblox)**

## Get an API Key

Sign up at **[tuteliq.ai](https://tuteliq.ai)** to get your API key. Free tier available for development and testing.

## Support

- **Documentation** — [docs.tuteliq.ai](https://docs.tuteliq.ai)
- **Email** — [support@tuteliq.ai](mailto:support@tuteliq.ai)
- **Issues** — [GitHub Issues](https://github.com/Tuteliq/roblox-sdk/issues)

## License

[MIT](LICENSE) — free for commercial and personal use.
