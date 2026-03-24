import SwiftUI

struct AIMessageBubble: View {
    let summary: String
    let generatedTime: Date?
    
    init(summary: String, generatedTime: Date? = nil) {
        self.summary = summary
        self.generatedTime = generatedTime
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "brain")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                
                Text("AI 摘要")
                    .font(AppFonts.headline)
                    .foregroundStyle(AppColors.primaryText)
                
                Spacer()
            }
            
            Text(summary)
                .font(AppFonts.body)
                .foregroundStyle(AppColors.primaryText)
                .lineSpacing(4)
            
            if let time = generatedTime {
                Text("生成时间: \(time.relativeFormatted)")
                    .font(AppFonts.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

#Preview {
    VStack(spacing: 20) {
        AIMessageBubble(
            summary: "这封邮件是关于项目进度汇报，需要在周五前完成相关文档。",
            generatedTime: Date()
        )
        
        AIMessageBubble(
            summary: "这是一封比较长的邮件摘要，包含了多个重要事项的概述，需要仔细阅读并及时处理。",
            generatedTime: Date().addingTimeInterval(-3600)
        )
    }
    .padding()
}
