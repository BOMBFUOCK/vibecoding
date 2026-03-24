import Foundation

// MARK: - Prompt Templates

let SUMMARY_SYSTEM_PROMPT = """
你是一个专业的邮件摘要助手。请为邮件生成简洁、准确的摘要。

要求：
1. 摘要长度不超过 50 字
2. 包含邮件的核心内容
3. 突出重要的 action items 或截止日期
4. 使用用户的语言（根据邮件内容判断）

请直接输出摘要，不要有多余的解释。
"""

let SUMMARY_USER_PROMPT_TEMPLATE = """
请为以下邮件生成摘要：

发件人：%@
主题：%@
日期：%@

内容：
%@

摘要：
"""

let CONVERSATION_SYSTEM_PROMPT = """
你是一个专业的邮件对话摘要助手。请为邮件串（多封相关邮件）生成简洁、准确的对话摘要。

要求：
1. 摘要长度不超过 100 字
2. 包含对话的核心内容和结论
3. 突出最终的决策或 action items
4. 按时间顺序组织（从旧到新）
5. 使用用户的语言

请直接输出摘要，不要有多余的解释。
"""

let CONVERSATION_USER_PROMPT_TEMPLATE = """
请为以下邮件对话生成摘要：

%@

摘要：
"""

// MARK: - AI Summarizer

final class AISummarizer: Sendable {
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
    
    func summarize(email: Email) async throws -> String {
        let userPrompt = buildUserPrompt(for: email)
        
        let messages = [
            ChatMessage.system(SUMMARY_SYSTEM_PROMPT),
            ChatMessage.user(userPrompt)
        ]
        
        let summary = try await openAIClient.chatCompletion(
            messages: messages,
            model: AIConfig.defaultModel,
            temperature: AIConfig.summaryTemperature,
            maxTokens: AIConfig.maxTokensForSummary
        )
        
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func summarizeConversation(emails: [Email]) async throws -> String {
        guard !emails.isEmpty else {
            return ""
        }
        
        if emails.count == 1 {
            return try await summarize(email: emails[0])
        }
        
        let sortedEmails = emails.sorted { $0.date < $1.date }
        let conversationText = buildConversationText(from: sortedEmails)
        
        let userPrompt = String(format: CONVERSATION_USER_PROMPT_TEMPLATE, conversationText)
        
        let messages = [
            ChatMessage.system(CONVERSATION_SYSTEM_PROMPT),
            ChatMessage.user(userPrompt)
        ]
        
        let summary = try await openAIClient.chatCompletion(
            messages: messages,
            model: AIConfig.defaultModel,
            temperature: AIConfig.summaryTemperature,
            maxTokens: AIConfig.maxTokensForSummary * 2
        )
        
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func summarizeText(_ text: String) async throws -> String {
        let userPrompt = "请为以下文本生成简短摘要（不超过50字）：\n\n\(text)"
        
        let messages = [
            ChatMessage.system(SUMMARY_SYSTEM_PROMPT),
            ChatMessage.user(userPrompt)
        ]
        
        let summary = try await openAIClient.chatCompletion(
            messages: messages,
            model: AIConfig.defaultModel,
            temperature: AIConfig.summaryTemperature,
            maxTokens: AIConfig.maxTokensForSummary
        )
        
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func summarizeTexts(_ texts: [String]) async throws -> String {
        let combined = texts.joined(separator: "\n---\n")
        return try await summarizeText(combined)
    }
    
    // MARK: - Private Helpers
    
    private func buildUserPrompt(for email: Email) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.current
        
        let dateString = dateFormatter.string(from: email.date)
        let content = email.displayText.isEmpty ? "(无正文内容)" : email.displayText
        
        return String(
            format: SUMMARY_USER_PROMPT_TEMPLATE,
            email.from,
            email.subject,
            dateString,
            content
        )
    }
    
    private func buildConversationText(from emails: [Email]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.current
        
        var result = ""
        
        for (index, email) in emails.enumerated() {
            if index > 0 {
                result += "\n\n---\n\n"
            }
            
            let dateString = dateFormatter.string(from: email.date)
            let content = email.displayText.isEmpty ? "(无正文内容)" : email.displayText
            
            result += "【邮件 \(index + 1)】\n"
            result += "发件人: \(email.from)\n"
            result += "时间: \(dateString)\n"
            result += "主题: \(email.subject)\n"
            result += "内容:\n\(content)"
        }
        
        return result
    }
}
