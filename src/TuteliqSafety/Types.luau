--!strict

local Types = {}

export type SensitivityLevel = "low" | "medium" | "high" | "maximum"

export type DetectionType = "bullying" | "grooming" | "unsafe"

export type ActionConfig = {
	mute: boolean,
	kick: boolean,
	notifyAdmins: boolean,
	log: boolean,
}

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
}

export type ChatMessage = {
	sender: string,
	senderId: number,
	text: string,
	timestamp: number,
	channel: string,
}

export type ConversationMessage = {
	sender_role: string,
	text: string,
}

export type BatchItem = {
	id: string,
	type: string,
	data: {
		text: string?,
		messages: { ConversationMessage }?,
		context: { [string]: any }?,
	},
}

export type DetectionResult = {
	detected: boolean,
	type: DetectionType,
	severity: string,
	confidence: number,
	riskScore: number,
	rationale: string,
	recommendedAction: string,
	player: Player?,
	message: string?,
}

export type HttpResponse = {
	success: boolean,
	statusCode: number,
	body: { [string]: any }?,
	error: string?,
}

export type RateLimiterConfig = {
	maxTokens: number,
	refillRate: number,
	refillIntervalSeconds: number,
}

return Types
