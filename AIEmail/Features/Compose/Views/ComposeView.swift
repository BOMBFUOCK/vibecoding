import SwiftUI

struct ComposeView: View {
    @State var viewModel: ComposeViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    
    enum Field {
        case to, cc, subject, body
    }
    
    init(viewModel: ComposeViewModel = ComposeViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    recipientField(title: "收件人:", text: $viewModel.to, field: .to)
                    
                    Divider()
                        .background(AppColors.separator)
                    
                    recipientField(title: "抄送:", text: $viewModel.cc, field: .cc)
                    
                    Divider()
                        .background(AppColors.separator)
                    
                    subjectField
                    
                    Divider()
                        .background(AppColors.separator)
                    
                    bodyField
                }
            }
            
            Divider()
                .background(AppColors.separator)
            
            bottomToolbar
        }
        .navigationTitle("撰写")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") {
                    dismiss()
                }
                .foregroundStyle(AppColors.secondaryText)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button("发送") {
                    Task {
                        try? await viewModel.send()
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(viewModel.canSend ? AppColors.accent : AppColors.secondaryText)
                .disabled(!viewModel.canSend)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                }
            }
        }
    }
    
    private func recipientField(title: String, text: Binding<String>, field: Field) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppFonts.body)
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 60, alignment: .leading)
            
            TextField(" ", text: text)
                .font(AppFonts.body)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: field)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }
    
    private var subjectField: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("主题:")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 60, alignment: .leading)
            
            TextField(" ", text: $viewModel.subject)
                .font(AppFonts.body)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .subject)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }
    
    private var bodyField: some View {
        TextEditor(text: $viewModel.body)
            .font(AppFonts.body)
            .foregroundStyle(AppColors.primaryText)
            .frame(minHeight: 200)
            .focused($focusedField, equals: .body)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
    }
    
    private var bottomToolbar: some View {
        HStack(spacing: AppSpacing.lg) {
            toolbarButton(icon: "paperclip", title: "附件") {
            }
            
            toolbarButton(icon: "wand.and.stars", title: "AI辅助") {
            }
            
            toolbarButton(icon: "textformat", title: "格式") {
            }
            
            Spacer()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.secondaryBackground)
    }
    
    private func toolbarButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(AppFonts.caption)
            }
            .foregroundStyle(AppColors.accent)
        }
    }
}

#Preview {
    NavigationStack {
        ComposeView()
    }
}
