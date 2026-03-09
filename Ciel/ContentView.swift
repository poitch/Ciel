import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isRestoringSession {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Signing in...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
        .task {
            if !appState.isAuthenticated {
                await appState.restoreSession()
            }
        }
    }
}
