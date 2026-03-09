import SwiftUI
import ATProtoKit

enum FeedTab: Hashable {
    case following
    case custom(uri: String, name: String)

    static func == (lhs: FeedTab, rhs: FeedTab) -> Bool {
        switch (lhs, rhs) {
        case (.following, .following): return true
        case (.custom(let a, _), .custom(let b, _)): return a == b
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .following: hasher.combine("following")
        case .custom(let uri, _): hasher.combine(uri)
        }
    }

    var displayName: String {
        switch self {
        case .following: return "Following"
        case .custom(_, let name): return name
        }
    }
}

@Observable
final class AppState {
    var isAuthenticated = false
    var isLoggingIn = false
    var isRestoringSession = false
    var loginError: String?

    var config: ATProtocolConfiguration?
    var atProtoKit: ATProtoKit?
    var atProtoBluesky: ATProtoBluesky?
    var sessionDID: String?

    var selectedTab: FeedTab = .following
    var posts: [AppBskyLexicon.Feed.FeedViewPostDefinition] = []
    var cursor: String?
    var isLoadingFeed = false
    var feedError: String?

    var savedFeeds: [AppBskyLexicon.Feed.GeneratorViewDefinition] = []
    var isLoadingSavedFeeds = false

    var suggestedFeeds: [AppBskyLexicon.Feed.GeneratorViewDefinition] = []
    var isLoadingSuggestedFeeds = false

    var showCompose = false
    var replyTarget: AppBskyLexicon.Feed.PostViewDefinition?

    // MARK: - Session Persistence Keys

    private static let keychainUUIDKey = "ciel.session.keychainUUID"
    private static let pdsURLKey = "ciel.session.pdsURL"
    private static let handleKey = "ciel.session.handle"

    // MARK: - Auth

    func login(handle: String, appPassword: String, server: String) async {
        isLoggingIn = true
        loginError = nil

        do {
            let pdsURL = server.isEmpty ? "https://bsky.social" : server
            let keychain = AppleSecureKeychain()
            let configuration = ATProtocolConfiguration(pdsURL: pdsURL, keychainProtocol: keychain)
            try await configuration.authenticate(with: handle, password: appPassword)

            let kit = await ATProtoKit(sessionConfiguration: configuration)
            let bluesky = ATProtoBluesky(atProtoKitInstance: kit)

            let session = try await kit.getUserSession()
            self.sessionDID = session?.sessionDID

            self.config = configuration
            self.atProtoKit = kit
            self.atProtoBluesky = bluesky
            self.isAuthenticated = true

            // Persist session metadata (non-sensitive) for restoration
            let keychainID = await keychain.identifier
            UserDefaults.standard.set(keychainID.uuidString, forKey: Self.keychainUUIDKey)
            UserDefaults.standard.set(pdsURL, forKey: Self.pdsURLKey)
            UserDefaults.standard.set(handle, forKey: Self.handleKey)

            await loadFeed()
            await loadSavedFeeds()
            await loadSuggestedFeeds()
        } catch {
            loginError = error.localizedDescription
        }

        isLoggingIn = false
    }

    func restoreSession() async {
        guard let uuidString = UserDefaults.standard.string(forKey: Self.keychainUUIDKey),
              let uuid = UUID(uuidString: uuidString),
              let pdsURL = UserDefaults.standard.string(forKey: Self.pdsURLKey),
              let handle = UserDefaults.standard.string(forKey: Self.handleKey) else {
            return
        }

        isRestoringSession = true

        do {
            // Retrieve the stored password from the keychain using the same UUID
            let keychain = AppleSecureKeychain(identifier: uuid)
            let password = try await keychain.retrievePassword()

            // Re-authenticate with stored credentials
            let configuration = ATProtocolConfiguration(pdsURL: pdsURL, keychainProtocol: keychain)
            try await configuration.authenticate(with: handle, password: password)

            let kit = await ATProtoKit(sessionConfiguration: configuration)
            let bluesky = ATProtoBluesky(atProtoKitInstance: kit)

            let session = try await kit.getUserSession()
            self.sessionDID = session?.sessionDID
            self.config = configuration
            self.atProtoKit = kit
            self.atProtoBluesky = bluesky
            self.isAuthenticated = true

            await loadFeed()
            await loadSavedFeeds()
            await loadSuggestedFeeds()
        } catch {
            // Password not in keychain or auth failed — user needs to log in again
            clearStoredSession()
        }

        isRestoringSession = false
    }

    func logout() {
        // Clean up keychain credentials
        if let uuidString = UserDefaults.standard.string(forKey: Self.keychainUUIDKey),
           let uuid = UUID(uuidString: uuidString) {
            let keychain = AppleSecureKeychain(identifier: uuid)
            Task {
                try? await keychain.deletePassword()
                try? await keychain.deleteRefreshToken()
                try? await keychain.deleteAccessToken()
            }
        }

        isAuthenticated = false
        config = nil
        atProtoKit = nil
        atProtoBluesky = nil
        sessionDID = nil
        posts = []
        cursor = nil
        savedFeeds = []
        suggestedFeeds = []
        selectedTab = .following
        clearStoredSession()
    }

    private func clearStoredSession() {
        UserDefaults.standard.removeObject(forKey: Self.keychainUUIDKey)
        UserDefaults.standard.removeObject(forKey: Self.pdsURLKey)
        UserDefaults.standard.removeObject(forKey: Self.handleKey)
    }

    // MARK: - Feed Loading

    func loadFeed(loadMore: Bool = false) async {
        guard let kit = atProtoKit else { return }
        if isLoadingFeed { return }

        isLoadingFeed = true
        feedError = nil

        do {
            let feedCursor = loadMore ? cursor : nil

            switch selectedTab {
            case .following:
                let result = try await kit.getTimeline(limit: 50, cursor: feedCursor)
                if loadMore {
                    posts.append(contentsOf: result.feed)
                } else {
                    posts = result.feed
                }
                cursor = result.cursor

            case .custom(let uri, _):
                let result = try await kit.getFeed(by: uri, limit: 50, cursor: feedCursor)
                if loadMore {
                    posts.append(contentsOf: result.feed)
                } else {
                    posts = result.feed
                }
                cursor = result.cursor
            }
        } catch {
            feedError = error.localizedDescription
        }

        isLoadingFeed = false
    }

    func switchTab(_ tab: FeedTab) async {
        selectedTab = tab
        posts = []
        cursor = nil
        await loadFeed()
    }

    // MARK: - Saved Feeds

    func loadSavedFeeds() async {
        guard let kit = atProtoKit else { return }
        isLoadingSavedFeeds = true

        do {
            let prefs = try await kit.getPreferences()
            var feedURIs: [String] = []

            for pref in prefs.preferences {
                if case .savedFeedsVersion2(let savedFeedsPref) = pref {
                    for item in savedFeedsPref.items {
                        if case .feed = item.feedType {
                            feedURIs.append(item.value)
                        }
                    }
                }
            }

            if !feedURIs.isEmpty {
                let generators = try await kit.getFeedGenerators(by: feedURIs)
                savedFeeds = generators.feeds
            }
        } catch {
            print("Failed to load saved feeds: \(error)")
        }

        isLoadingSavedFeeds = false
    }

    func loadSuggestedFeeds() async {
        guard let kit = atProtoKit else { return }
        isLoadingSuggestedFeeds = true

        do {
            let result = try await kit.getSuggestedFeeds(limit: 25)
            let savedURIs = Set(savedFeeds.map(\.feedURI))
            suggestedFeeds = result.feeds.filter { !savedURIs.contains($0.feedURI) }
        } catch {
            print("Failed to load suggested feeds: \(error)")
        }

        isLoadingSuggestedFeeds = false
    }

    // MARK: - Post Actions

    func toggleLike(post: AppBskyLexicon.Feed.PostViewDefinition) async {
        guard let bluesky = atProtoBluesky else { return }

        let ref = ComAtprotoLexicon.Repository.StrongReference(
            recordURI: post.uri,
            cidHash: post.cid
        )

        do {
            if let likeURI = post.viewer?.likeURI {
                try await bluesky.deleteRecord(.recordURI(atURI: likeURI))
            } else {
                _ = try await bluesky.createLikeRecord(ref)
            }
            await refreshPost(uri: post.uri)
        } catch {
            print("Like action failed: \(error)")
        }
    }

    func toggleRepost(post: AppBskyLexicon.Feed.PostViewDefinition) async {
        guard let bluesky = atProtoBluesky else { return }

        let ref = ComAtprotoLexicon.Repository.StrongReference(
            recordURI: post.uri,
            cidHash: post.cid
        )

        do {
            if let repostURI = post.viewer?.repostURI {
                try await bluesky.deleteRecord(.recordURI(atURI: repostURI))
            } else {
                _ = try await bluesky.createRepostRecord(ref)
            }
            await refreshPost(uri: post.uri)
        } catch {
            print("Repost action failed: \(error)")
        }
    }

    func reply(to post: AppBskyLexicon.Feed.PostViewDefinition) {
        replyTarget = post
        showCompose = true
    }

    func createPost(text: String, imageData: Data?, altText: String?) async throws {
        guard let bluesky = atProtoBluesky else { return }

        var embed: ATProtoBluesky.EmbedIdentifier?

        if let imageData {
            let query = ATProtoTools.ImageQuery(
                imageData: imageData,
                fileName: "photo.jpg",
                altText: altText ?? "",
                aspectRatio: nil
            )
            embed = .images(images: [query])
        }

        var replyRef: AppBskyLexicon.Feed.PostRecord.ReplyReference?
        if let target = replyTarget {
            let parentRef = ComAtprotoLexicon.Repository.StrongReference(
                recordURI: target.uri,
                cidHash: target.cid
            )
            replyRef = AppBskyLexicon.Feed.PostRecord.ReplyReference(
                root: parentRef,
                parent: parentRef
            )
        }

        _ = try await bluesky.createPostRecord(
            text: text,
            replyTo: replyRef,
            embed: embed
        )

        replyTarget = nil
        showCompose = false
        await loadFeed()
    }

    // MARK: - Helpers

    private func refreshPost(uri: String) async {
        await loadFeed()
    }
}
