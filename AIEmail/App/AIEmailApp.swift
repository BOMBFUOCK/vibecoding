import SwiftUI

@main
struct AIEmailApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    
    var body: some View {
        NavigationStack {
            if hasCompletedOnboarding {
                MailboxView()
            } else {
                WelcomeView()
            }
        }
    }
}
