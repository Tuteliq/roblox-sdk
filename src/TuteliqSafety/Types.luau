--!strict

local Types = {}

export type SensitivityLevel = "low" | "medium" | "high" | "maximum"

export type DetectionType = "bullying" | "grooming" | "unsafe"

-- The API's routing key, weakest to strongest.
export type RecommendedAction = "none" | "monitor" | "flag_for_review" | "block" | "immediate_intervention"

-- The role a player has in a conversation sent for grooming analysis.
export type SenderRole = "child" | "adult" | "unknown"

export type ActionConfig = {
	mute: boolean,
	kick: boolean,
	notifyAdmins: boolean,
	log: boolean,
}

-- Returns the player's age when the game knows it, or nil.
export type AgeLookup = (player: Player) -> number?

export type Config = {
	apiKey: string,
	sensitivity: SensitivityLevel,
	detect: { DetectionType },
	actions: ActionConfig,
	muteDurationSeconds: number,
	batchSize: number,
	batchFlushIntervalSeconds: number,
	httpBudgetPerMinute: number,
	webhookUrl: string?,
	getPlayerAge: AgeLookup?,
}

export type UserConfig = {
	apiKey: string,
	sensitivity: SensitivityLevel?,
	detect: { DetectionType }?,
	actions: ActionConfig?,
	muteDurationSeconds: number?,
	batchSize: number?,
	batchFlushIntervalSeconds: number?,
	httpBudgetPerMinute: number?,
	webhookUrl: string?,
	getPlayerAge: AgeLookup?,
}

export type ChatMessage = {
	sender: string,
	senderId: number,
	senderAge: number?,
	text: string,
	timestamp: number,
	channel: string,
}

export type ConversationMessage = {
	sender_role: SenderRole,
	text: string,
	sender_age: number?,
}

-- One conversation between two players, ready for grooming analysis.
export type Conversation = {
	messages: { ConversationMessage },
	childAge: number?,
	-- The role each of the two players was sent with, by UserId.
	roles: { [number]: SenderRole },
}

-- An item as the batch endpoint receives it.
export type BatchItem = {
	id: string,
	type: string,
	data: {
		text: string?,
		messages: { ConversationMessage }?,
		context: { [string]: any }?,
	},
}

-- A batch item with the player and message it came from, kept in the game.
export type QueuedItem = {
	request: BatchItem,
	player: Player?,
	message: string?,
}

export type DetectionResult = {
	detected: boolean,
	type: DetectionType,
	severity: string,
	confidence: number,
	riskScore: number,
	rationale: string,
	recommendedAction: RecommendedAction,
	-- The player the detection is about, when there is one.
	player: Player?,
	-- The player mute and kick apply to: only ever someone harming others.
	actionTarget: Player?,
	-- True when the speaker is not harming anyone else (a report, a disclosure,
	-- distress): route to support, not moderation.
	needsSupport: boolean,
	-- Both players of a grooming conversation.
	participants: { Player }?,
	message: string?,
}

export type HttpResponse = {
	success: boolean,
	statusCode: number,
	body: { [string]: any }?,
	error: string?,
	errorCode: string?,
	retryAfterSeconds: number?,
}

export type RateLimiterConfig = {
	maxTokens: number,
	refillRate: number,
	refillIntervalSeconds: number,
}

return Types
