import SwiftUI
import ATProtoKit
import AppKit

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

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

                HStack {
                    Label("Notifications", systemImage: "bell")
                    Spacer()
                    if appState.unreadNotificationCount > 0 {
                        Text("\(appState.unreadNotificationCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                }
                .tag(FeedTab.notifications)

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
            let isFeed = appState.selectedTab.isFeedTab
            ZStack {
                FeedView()
                    .opacity(isFeed ? 1 : 0)
                    .allowsHitTesting(isFeed)

                if appState.selectedTab == .profile {
                    ProfileView()
                }

                if appState.selectedTab == .notifications {
                    NotificationsView()
                }

                if case .thread = appState.selectedTab {
                    ThreadView()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    appState.replyContext = nil
                    appState.quoteTarget = nil
                    appState.showCompose = true
                }) {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Post")
                .keyboardShortcut("n", modifiers: .command)
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task {
                        switch appState.selectedTab {
                        case .profile:
                            await appState.loadProfile()
                        case .notifications:
                            await appState.loadNotifications()
                        case .thread(let uri):
                            await appState.loadThread(uri: uri)
                        default:
                            await appState.loadFeed()
                        }
                    }
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
        .sheet(item: $state.selectedImageURL) { url in
            ImageViewerSheet(url: url)
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

struct ImageViewerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padding()
            }

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    ContentUnavailableView(
                        "Failed to Load",
                        systemImage: "photo",
                        description: Text("Could not load this image.")
                    )
                default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}
