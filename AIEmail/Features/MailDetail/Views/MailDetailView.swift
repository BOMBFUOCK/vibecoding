import SwiftUI

struct MailDetailView: View {
    let email: EmailRecord
    @State private var viewModel: MailDetailViewModel
    @State private var showCompose = false
    @Environment(\.dismiss) private var dismiss
    
    init(email: EmailRecord) {
        self.email = email
        self._viewModel = State(initialValue: MailDetailViewModel(email: email))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    headerSection
                    
                    Divider()
                        .background(AppColors.separator)
                    
                    contentSection
                    
                    if let summary = viewModel.aiSummary {
                        AIMessageBubble(summary: summary, generatedTime: viewModel.email.aiSummaryGeneratedAt)
                    }
                }
                .padding(AppSpacing.md)
            }
            
            Divider()
                .background(AppColors.separator)
            
            bottomToolbar
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task {
                            await viewModel.toggleStarred()
                        }
                    } label: {
                        Label(
                            viewModel.email.isStarred ? "取消星标" : "标记星标",
                            systemImage: viewModel.email.isStarred ? "star.slash" : "star"
                        )
                    }
                    
                    Button {
                        Task {
                            await viewModel.generateSummary()
                        }
                    } label: {
                        Label("AI 摘要", systemImage: "brain")
                    }
                    .disabled(viewModel.isGeneratingSummary)
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            NavigationStack {
                ComposeView(viewModel: ComposeViewModel())
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                Circle()
                    .fill(AppColors.accent.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Text(viewModel.email.fromName?.prefix(1).uppercased() ?? viewModel.email.from.prefix(1).uppercased())
                            .font(AppFonts.title2)
                            .foregroundStyle(AppColors.accent)
                    }
                
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(viewModel.email.fromName ?? viewModel.email.from)
                        .font(AppFonts.headline)
                        .foregroundStyle(AppColors.primaryText)
                    
                    Text(viewModel.email.from)
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text(viewModel.email.receivedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.secondaryText)
                    
                    if viewModel.email.isStarred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(AppColors.warning)
                    }
                }
            }
            
            Text(viewModel.email.subject ?? "无主题")
                .font(AppFonts.title2)
                .foregroundStyle(AppColors.primaryText)
                .padding(.top, AppSpacing.sm)
        }
    }
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(viewModel.email.textBody ?? viewModel.email.preview ?? "无内容")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.primaryText)
                .lineSpacing(6)
            
            if viewModel.email.hasAttachments {
                attachmentsSection
            }
        }
    }
    
    @ViewBuilder
    private var attachmentsSection: some View {
        if viewModel.email.hasAttachments {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("附件")
                    .font(AppFonts.headline)
                    .foregroundStyle(AppColors.primaryText)
                
                Text("附件 (点击查看)")
                    .font(AppFonts.subheadline)
                    .foregroundStyle(AppColors.accent)
                    .padding(AppSpacing.sm)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton(icon: "arrowshape.turn.up.left", title: "回复") {
                showCompose = true
            }
            
            Divider()
                .frame(height: 24)
            
            toolbarButton(icon: "arrowshape.turn.up.right", title: "转发") {
                showCompose = true
            }
            
            Divider()
                .frame(height: 24)
            
            toolbarButton(icon: "brain", title: "AI摘要") {
                Task {
                    await viewModel.generateSummary()
                }
            }
            .disabled(viewModel.isGeneratingSummary)
        }
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.background)
    }
    
    private func toolbarButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(AppFonts.caption)
            }
            .foregroundStyle(AppColors.accent)
            .frame(maxWidth: .infinity)
        }
    }
    
    private func formatFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

extension AttachmentInfo: Identifiable {
    var id: String { partID }
}

#Preview {
    NavigationStack {
        MailDetailView(email: EmailRecord(
            id: "1",
            accountID: "acc1",
            folderID: "inbox",
            messageID: "msg1",
            from: "sender@example.com",
            fromName: "发件人",
            to: ["recipient@example.com"],
            subject: "测试邮件主题",
            preview: "这是邮件的预览内容",
            textBody: "这是邮件的正文内容，包含很多文字...",
            hasAttachments: true,
            isRead: true,
            isStarred: true,
            receivedAt: Date()
        ))
    }
}
