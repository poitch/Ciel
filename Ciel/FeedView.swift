import SwiftUI
import ATProtoKit

struct FeedView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isLoadingFeed && appState.posts.isEmpty {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = appState.feedError, appState.posts.isEmpty {
                ContentUnavailableView {
                    Label("Failed to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await appState.loadFeed() }
                    }
                }
            } else if appState.posts.isEmpty {
                ContentUnavailableView(
                    "No Posts",
                    systemImage: "text.bubble",
                    description: Text("Nothing to show yet.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(appState.posts.enumerated()), id: \.offset) { index, feedPost in
                            PostRowView(feedPost: feedPost)

                            Divider()

                            if index == appState.posts.count - 5 {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        Task { await appState.loadFeed(loadMore: true) }
                                    }
                            }
                        }

                        if appState.isLoadingFeed {
                            ProgressView()
                                .padding()
                        }
                    }
                }
            }
        }
        .navigationTitle(appState.selectedTab.displayName)
    }
}
