import SwiftUI

@main
struct CielApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 700)
    }
}
