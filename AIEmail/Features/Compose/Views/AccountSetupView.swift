import SwiftUI

struct AccountSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var selectedProvider: EmailProvider = .gmail
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("邮箱地址", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("账户信息")
                }
                
                Section {
                    Picker("邮件提供商", selection: $selectedProvider) {
                        ForEach(EmailProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                } header: {
                    Text("服务器设置")
                } footer: {
                    Text("我们将自动配置您的服务器设置")
                }
            }
            .navigationTitle("添加账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") {
                        setupAccount()
                    }
                    .fontWeight(.semibold)
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                }
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func setupAccount() {
        isLoading = true
        
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                
                DispatchQueue.main.async {
                    isLoading = false
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

#Preview {
    AccountSetupView()
}
