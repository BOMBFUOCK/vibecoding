import SwiftUI

struct MailboxView: View {
    @State private var viewModel = MailboxViewModel()
    @State private var showSearch = false
    @State private var showCompose = false
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.emails.isEmpty {
                LoadingIndicator(message: "加载中...")
            } else if viewModel.filteredEmails.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "没有邮件",
                    message: "收件箱为空，没有新邮件",
                    actionTitle: "刷新",
                    action: {
                        Task {
                            await viewModel.refreshEmails()
                        }
                    }
                )
            } else {
                emailList
            }
        }
        .navigationTitle("收件箱")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if viewModel.unreadCount > 0 {
                    Text("\(Image(systemName: "envelope.badge")) \(viewModel.unreadCount) 封新邮件")
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: AppSpacing.md) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    
                    Button {
                        showCompose = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .foregroundStyle(AppColors.accent)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索邮件...")
        .refreshable {
            await viewModel.refreshEmails()
        }
        .task {
            await viewModel.loadEmails()
        }
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                SearchView()
            }
        }
        .sheet(isPresented: $showCompose) {
            NavigationStack {
                ComposeView()
            }
        }
    }
    
    private var emailList: some View {
        List {
            ForEach(viewModel.filteredEmails) { email in
                NavigationLink {
                    MailDetailView(email: email)
                } label: {
                    EmailRowView(email: email)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.md, bottom: 0, trailing: AppSpacing.md))
                .listRowSeparator(.visible)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteEmail(email)
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        Task {
                            if email.isRead {
                                await viewModel.markAsUnread(email)
                            } else {
                                await viewModel.markAsRead(email)
                            }
                        }
                    } label: {
                        Label(
                            email.isRead ? "标记未读" : "标记已读",
                            systemImage: email.isRead ? "envelope.badge" : "envelope.open"
                        )
                    }
                    .tint(AppColors.accent)
                }
            }
        }
        .listStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        MailboxView()
    }
}
