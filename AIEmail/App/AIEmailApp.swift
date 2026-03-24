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
    var body: some View {
        NavigationStack {
            MailboxView()
        }
    }
}
