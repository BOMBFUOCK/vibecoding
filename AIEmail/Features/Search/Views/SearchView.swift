import SwiftUI

struct SearchView: View {
    @State var viewModel = SearchViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool
    
    private let suggestions = [
        ("calendar", "上周的邮件"),
        ("paperclip", "有附件的邮件"),
        ("star", "标星邮件")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.results.isEmpty && viewModel.query.isEmpty {
                suggestionsView
            } else if viewModel.results.isEmpty && !viewModel.query.isEmpty && !viewModel.isSearching {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "无结果",
                    message: "没有找到匹配的邮件"
                )
            } else {
                resultsList
            }
            
            Divider()
                .background(AppColors.separator)
            
            searchModeSelector
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .searchable(
            text: $viewModel.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索邮件..."
        )
        .onSubmit(of: .search) {
            Task {
                await viewModel.search()
            }
        }
        .onChange(of: viewModel.query) { _, newValue in
            if newValue.isEmpty {
                viewModel.clearSearch()
            }
        }
    }
    
    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("搜索建议")
                .font(AppFonts.headline)
                .foregroundStyle(AppColors.primaryText)
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)
            
            VStack(spacing: AppSpacing.sm) {
                ForEach(suggestions, id: \.0) { icon, title in
                    Button {
                        viewModel.query = title
                        Task {
                            await viewModel.search()
                        }
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .foregroundStyle(AppColors.accent)
                                .frame(width: 32)
                            
                            Text(title)
                                .font(AppFonts.body)
                                .foregroundStyle(AppColors.primaryText)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            
            Spacer()
        }
    }
    
    private var resultsList: some View {
        List {
            ForEach(viewModel.results) { result in
                NavigationLink {
                    MailDetailView(email: result.email)
                } label: {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack {
                            Text(result.email.fromName ?? result.email.from)
                                .font(AppFonts.headline)
                                .foregroundStyle(AppColors.primaryText)
                            
                            Spacer()
                            
                            Text(result.email.receivedAt.relativeFormatted)
                                .font(AppFonts.caption)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                        
                        Text(result.email.subject ?? "无主题")
                            .font(AppFonts.subheadline)
                            .foregroundStyle(AppColors.primaryText)
                            .lineLimit(1)
                        
                        Text(result.snippet)
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(2)
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private var searchModeSelector: some View {
        HStack(spacing: AppSpacing.md) {
            ForEach(SearchViewModel.SearchMode.allCases) { mode in
                Button {
                    viewModel.searchMode = mode
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: mode.icon)
                            .font(.caption)
                        Text(mode.rawValue)
                            .font(AppFonts.caption)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(viewModel.searchMode == mode ? AppColors.accent : AppColors.secondaryBackground)
                    .foregroundStyle(viewModel.searchMode == mode ? .white : AppColors.primaryText)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.background)
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
}
