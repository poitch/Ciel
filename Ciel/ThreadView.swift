import SwiftUI
import ATProtoKit

struct ThreadView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isLoadingThread && appState.threadPost == nil {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.threadPost == nil {
                ContentUnavailableView(
                    "Thread Unavailable",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Could not load this thread.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Parent chain
                        ForEach(Array(appState.threadParents.enumerated()), id: \.element.uri) { index, parent in
                            PostRowView(
                                post: parent,
                                showThreadLineAbove: index > 0,
                                showThreadLineBelow: true
                            )
                            Divider()
                        }

                        // Main post (highlighted)
                        if let mainPost = appState.threadPost {
                            PostRowView(
                                post: mainPost,
                                showThreadLineAbove: !appState.threadParents.isEmpty
                            )
                            .background(Color.accentColor.opacity(0.05))

                            Divider()
                        }

                        // Replies
                        ForEach(appState.threadReplies, id: \.uri) { reply in
                            PostRowView(post: reply)
                            Divider()
                        }

                        if appState.isLoadingThread {
                            ProgressView()
                                .padding()
                        }
                    }
                }
            }
        }
        .navigationTitle("Thread")
        .toolbar {
            if appState.canGoBack {
                ToolbarItem(placement: .navigation) {
                    Button(action: { appState.goBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .help("Back")
                }
            }
        }
    }
}
