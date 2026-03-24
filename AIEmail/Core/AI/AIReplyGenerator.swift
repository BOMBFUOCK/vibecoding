import Foundation

// MARK: - Reply Tone

enum ReplyTone: String, Sendable, CaseIterable {
    case professional
    case casual
    case brief
    
    var displayName: String {
        switch self {
        case .professional:
            return "专业正式"
        case .casual:
            return "轻松随意"
        case .brief:
            return "简洁明了"
        }
    }
    
    var systemPromptSuffix: String {
        switch self {
        case .professional:
            return "使用专业、正式的语气。保持礼貌和尊重。"
        case .casual:
            return "使用轻松、友好的语气。可以适当随意但保持礼貌。"
        case .brief:
            return "保持回复简洁明了，直切主题，不需要过多的客套话。"
        }
    }
}

// MARK: - Reply Prompt Templates

let REPLY_SYSTEM_PROMPT = """
你是一个专业的邮件回复助手。请根据原邮件内容生成合适的回复草稿。

要求：
1. 回复简洁、专业、有礼貌
2. 适当引用原邮件中的关键信息
3. 如果原邮件有明确的 action items，在回复中确认收到并说明你会处理
4. 根据邮件的语气调整回复风格

请直接生成回复草稿，不要有多余的解释。
"""

let REPLY_USER_PROMPT_TEMPLATE = """
请为以下邮件生成回复：

发件人：%@
主题：%@
日期：%@

原邮件内容：
%@

语气要求：%@

回复草稿：
"""

let REPLY_WITH_CONTEXT_PROMPT_TEMPLATE = """
请为以下邮件生成回复，适当引用对话历史：

发件人：%@
主题：%@
日期：%@

对话历史：
%@

原邮件内容：
%@

语气要求：%@

回复草稿：
"""

// MARK: - AI Reply Generator

final class AIReplyGenerator: Sendable {
    private let openAIClient: OpenAIClient
    
    init(openAIClient: OpenAIClient) {
        self.openAIClient = openAIClient
    }
    
    convenience init() {
        guard let client = OpenAIClient.shared else {
            fatalError("OpenAIClient not configured. Call OpenAIClient.configure(with:) first.")
        }
        self.init(openAIClient: client)
    }
    
    func generateReply(
        originalEmail: Email,
        tone: ReplyTone = .professional,
        includePreviousContext: Bool = true
    ) async throws -> String {
        let userPrompt = buildUserPrompt(
            for: originalEmail,
            tone: tone,
            includePreviousContext: includePreviousContext
        )
        
        let systemPrompt = REPLY_SYSTEM_PROMPT + "\n\n" + tone.systemPromptSuffix
        
        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.user(userPrompt)
        ]
        
        let reply = try await openAIClient.chatCompletion(
            messages: messages,
            model: AIConfig.defaultModel,
            temperature: AIConfig.replyTemperature,
            maxTokens: AIConfig.maxTokensForReply
        )
        
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func generateReplyFromText(
        text: String,
        tone: ReplyTone = .professional
    ) async throws -> String {
        let userPrompt = "请为以下邮件内容生成回复草稿：\n\n\(text)"
        
        let systemPrompt = REPLY_SYSTEM_PROMPT + "\n\n" + tone.systemPromptSuffix
        
        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.user(userPrompt)
        ]
        
        let reply = try await openAIClient.chatCompletion(
            messages: messages,
            model: AIConfig.defaultModel,
            temperature: AIConfig.replyTemperature,
            maxTokens: AIConfig.maxTokensForReply
        )
        
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Private Helpers
    
    private func buildUserPrompt(
        for email: Email,
        tone: ReplyTone,
        includePreviousContext: Bool
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.current
        
        let dateString = dateFormatter.string(from: email.date)
        let content = email.displayText.isEmpty ? "(无正文内容)" : email.displayText
        
        let basePrompt: String
        if includePreviousContext, let references = email.references, !references.isEmpty {
            basePrompt = REPLY_WITH_CONTEXT_PROMPT_TEMPLATE
        } else {
            basePrompt = REPLY_USER_PROMPT_TEMPLATE
        }
        
        if includePreviousContext, let references = email.references, !references.isEmpty {
            return String(
                format: basePrompt,
                email.from,
                email.subject,
                dateString,
                references.joined(separator: "\n"),
                content,
                tone.displayName
            )
        } else {
            return String(
                format: basePrompt,
                email.from,
                email.subject,
                dateString,
                content,
                tone.displayName
            )
        }
    }
}
