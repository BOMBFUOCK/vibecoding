import SwiftUI

struct EmailRowView: View {
    let email: EmailRecord
    
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(AppColors.accent.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(email.fromName?.prefix(1).uppercased() ?? email.from.prefix(1).uppercased())
                        .font(AppFonts.headline)
                        .foregroundStyle(AppColors.accent)
                }
            
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack {
                    Text(email.fromName ?? email.from)
                        .font(AppFonts.headline)
                        .foregroundStyle(email.isRead ? AppColors.secondaryText : AppColors.primaryText)
                    
                    Spacer()
                    
                    Text(email.receivedAt.relativeFormatted)
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
                
                Text(email.subject ?? "无主题")
                    .font(AppFonts.subheadline)
                    .foregroundStyle(email.isRead ? AppColors.secondaryText : AppColors.primaryText)
                    .lineLimit(1)
                
                if let preview = email.preview {
                    Text(preview)
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                }
            }
            
            if email.isStarred {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .contentShape(Rectangle())
    }
}

#Preview {
    List {
        EmailRowView(email: EmailRecord(
            id: "1",
            accountID: "acc1",
            folderID: "inbox",
            messageID: "msg1",
            from: "sender@example.com",
            fromName: "发件人",
            to: ["recipient@example.com"],
            subject: "这是一封测试邮件",
            preview: "这是邮件的预览内容，显示邮件的部分文字...",
            textBody: "邮件正文内容",
            isRead: false,
            receivedAt: Date()
        ))
        
        EmailRowView(email: EmailRecord(
            id: "2",
            accountID: "acc1",
            folderID: "inbox",
            messageID: "msg2",
            from: "another@example.com",
            fromName: "另一个发件人",
            to: ["recipient@example.com"],
            subject: "已读的邮件",
            preview: "这是一封已经读过的邮件预览",
            textBody: "邮件正文",
            isRead: true,
            isStarred: true,
            receivedAt: Date().addingTimeInterval(-86400)
        ))
    }
}
