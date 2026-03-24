import SwiftUI

struct LoadingIndicator: View {
    var message: String?
    
    init(message: String? = nil) {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(AppColors.accent)
            
            if let message = message {
                Text(message)
                    .font(AppFonts.subheadline)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}

#Preview {
    LoadingIndicator(message: "加载中...")
}
