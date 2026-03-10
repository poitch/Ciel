import SwiftUI
import ATProtoKit

enum FeedTab: Hashable {
    case profile
    case following
    case custom(uri: String, name: String)

    static func == (lhs: FeedTab, rhs: FeedTab) -> Bool {
        switch (lhs, rhs) {
        case (.profile, .profile): return true
        case (.following, .following): return true
        case (.custom(let a, _), .custom(let b, _)): return a == b
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .profile: hasher.combine("profile")
        case .following: hasher.combine("following")
        case .custom(let uri, _): hasher.combine(uri)
        }
    }

    var displayName: String {
        switch self {
        case .profile: return "Profile"
        case .following: return "Following"
        case .custom(_, let name): return name
        }
    }
}

@MainActor
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
    var replyContext: ReplyContext?

    var profile: AppBskyLexicon.Actor.ProfileViewDetailedDefinition?
    var profilePosts: [AppBskyLexicon.Feed.FeedViewPostDefinition] = []
    var profileCursor: String?
    var isLoadingProfile = false
    var viewingProfileDID: String?
    var previousTab: FeedTab?

    struct ReplyContext {
        let target: AppBskyLexicon.Feed.PostViewDefinition
        let rootRef: ComAtprotoLexicon.Repository.StrongReference?
    }

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
        resetProfileState()
        selectedTab = .following
        clearStoredSession()
    }

    private func resetProfileState() {
        profile = nil
        profilePosts = []
        profileCursor = nil
        viewingProfileDID = nil
        previousTab = nil
    }

    private func clearStoredSession() {
        UserDefaults.standard.removeObject(forKey: Self.keychainUUIDKey)
        UserDefaults.standard.removeObject(forKey: Self.pdsURLKey)
        UserDefaults.standard.removeObject(forKey: Self.handleKey)
    }

    // MARK: - Feed Loading

    func loadFeed(loadMore: Bool = false) async {
        guard let kit = atProtoKit, selectedTab != .profile else { return }
        if isLoadingFeed { return }

        isLoadingFeed = true
        feedError = nil

        do {
            let feedCursor = loadMore ? cursor : nil

            switch selectedTab {
            case .profile:
                break

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
        if case .profile = tab {
            resetProfileState()
            await loadProfile()
        } else {
            posts = []
            cursor = nil
            await loadFeed()
        }
    }

    func viewProfile(did: String) {
        let from = selectedTab
        resetProfileState()
        previousTab = from
        viewingProfileDID = did
        selectedTab = .profile
        Task { await loadProfile() }
    }

    func goBack() {
        guard let tab = previousTab else { return }
        previousTab = nil
        viewingProfileDID = nil
        selectedTab = tab
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

            if feedURIs.isEmpty {
                savedFeeds = []
            } else {
                let generators = try await kit.getFeedGenerators(by: feedURIs)
                savedFeeds = generators.feeds
            }
        } catch {
            savedFeeds = []
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

    // MARK: - Profile

    func loadProfile(loadMore: Bool = false) async {
        guard let kit = atProtoKit else { return }
        let did = viewingProfileDID ?? sessionDID
        guard let did else { return }
        if isLoadingProfile { return }

        isLoadingProfile = true

        do {
            let feedCursor = loadMore ? profileCursor : nil

            if profile == nil {
                async let profileTask = kit.getProfile(for: did)
                async let feedTask = kit.getAuthorFeed(
                    by: did, limit: 50, cursor: feedCursor,
                    postFilter: .postsWithNoReplies
                )
                profile = try await profileTask
                let result = try await feedTask
                profilePosts = result.feed
                profileCursor = result.cursor
            } else {
                let result = try await kit.getAuthorFeed(
                    by: did, limit: 50, cursor: feedCursor,
                    postFilter: .postsWithNoReplies
                )
                if loadMore {
                    profilePosts.append(contentsOf: result.feed)
                } else {
                    profilePosts = result.feed
                }
                profileCursor = result.cursor
            }
        } catch {
            print("Failed to load profile: \(error)")
        }

        isLoadingProfile = false
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

    func reply(to post: AppBskyLexicon.Feed.PostViewDefinition, feedPost: AppBskyLexicon.Feed.FeedViewPostDefinition? = nil) {
        var rootRef: ComAtprotoLexicon.Repository.StrongReference?
        if let reply = feedPost?.reply, case .postView(let rootPost) = reply.root {
            rootRef = ComAtprotoLexicon.Repository.StrongReference(
                recordURI: rootPost.uri,
                cidHash: rootPost.cid
            )
        }
        replyContext = ReplyContext(target: post, rootRef: rootRef)
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
        if let context = replyContext {
            let parentRef = ComAtprotoLexicon.Repository.StrongReference(
                recordURI: context.target.uri,
                cidHash: context.target.cid
            )
            replyRef = AppBskyLexicon.Feed.PostRecord.ReplyReference(
                root: context.rootRef ?? parentRef,
                parent: parentRef
            )
        }

        _ = try await bluesky.createPostRecord(
            text: text,
            replyTo: replyRef,
            embed: embed
        )

        replyContext = nil
        showCompose = false
        await loadFeed()
    }

    // MARK: - Helpers

    private func refreshPost(uri: String) async {
        await loadFeed()
    }
}
