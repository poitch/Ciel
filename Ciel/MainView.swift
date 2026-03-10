import SwiftUI
import ATProtoKit

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var showSignOutConfirmation = false

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            List(selection: Binding(
                get: { appState.selectedTab },
                set: { tab in
                    if let tab {
                        Task { await appState.switchTab(tab) }
                    }
                }
            )) {
                Label("Profile", systemImage: "person.circle")
                    .tag(FeedTab.profile)

                Label("Following", systemImage: "person.2")
                    .tag(FeedTab.following)

                if !appState.savedFeeds.isEmpty {
                    Section("My Feeds") {
                        ForEach(appState.savedFeeds, id: \.feedURI) { feed in
                            feedLabel(feed)
                                .tag(FeedTab.custom(uri: feed.feedURI, name: feed.displayName))
                        }
                    }
                }

                if !appState.suggestedFeeds.isEmpty {
                    Section("Explore") {
                        ForEach(appState.suggestedFeeds, id: \.feedURI) { feed in
                            feedLabel(feed)
                                .tag(FeedTab.custom(uri: feed.feedURI, name: feed.displayName))
                        }
                    }
                }

                Section {
                    Button(action: { showSignOutConfirmation = true }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            let isShowingProfile = appState.selectedTab == .profile
            ZStack {
                FeedView()
                    .opacity(isShowingProfile ? 0 : 1)
                    .allowsHitTesting(!isShowingProfile)

                if isShowingProfile {
                    ProfileView()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    appState.replyContext = nil
                    appState.showCompose = true
                }) {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Post")
                .keyboardShortcut("n", modifiers: .command)
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task { await appState.loadFeed() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .sheet(isPresented: $state.showCompose) {
            ComposeView()
        }
        .alert("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                appState.logout()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    @ViewBuilder
    private func feedLabel(_ feed: AppBskyLexicon.Feed.GeneratorViewDefinition) -> some View {
        Label {
            Text(feed.displayName)
        } icon: {
            if let avatarURL = feed.avatarImageURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "number")
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "number")
            }
        }
    }
}
