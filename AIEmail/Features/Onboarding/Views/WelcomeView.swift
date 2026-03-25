import SwiftUI

struct WelcomeView: View {
    @State private var showAccountSetup = false
    
    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()
            
            VStack(spacing: AppSpacing.lg) {
                Spacer()
                
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 80))
                        .foregroundStyle(AppColors.accent)
                    
                    Text("探索 AI 邮箱的全新方式")
                        .font(AppFonts.title1)
                        .foregroundStyle(AppColors.primaryText)
                        .multilineTextAlignment(.center)
                    
                    Text("智能摘要 · 语义搜索 · AI 回复")
                        .font(AppFonts.subheadline)
                        .foregroundStyle(AppColors.secondaryText)
                }
                
                Spacer()
                
                Button {
                    showAccountSetup = true
                } label: {
                    Text("开始使用")
                        .font(AppFonts.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xxl)
            }
        }
        .sheet(isPresented: $showAccountSetup) {
            AccountSetupView()
        }
    }
}

#Preview {
    WelcomeView()
}
