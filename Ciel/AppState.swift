import SwiftUI
import ATProtoKit

enum FeedTab: Hashable {
    case profile
    case following
    case notifications
    case thread(uri: String)
    case custom(uri: String, name: String)

    static func == (lhs: FeedTab, rhs: FeedTab) -> Bool {
        switch (lhs, rhs) {
        case (.profile, .profile): return true
        case (.following, .following): return true
        case (.notifications, .notifications): return true
        case (.thread(let a), .thread(let b)): return a == b
        case (.custom(let a, _), .custom(let b, _)): return a == b
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .profile: hasher.combine("profile")
        case .following: hasher.combine("following")
        case .notifications: hasher.combine("notifications")
        case .thread(let uri): hasher.combine("thread"); hasher.combine(uri)
        case .custom(let uri, _): hasher.combine(uri)
        }
    }

    var displayName: String {
        switch self {
        case .profile: return "Profile"
        case .following: return "Following"
        case .notifications: return "Notifications"
        case .thread: return "Thread"
        case .custom(_, let name): return name
        }
    }

    var isFeedTab: Bool {
        switch self {
        case .following, .custom: return true
        default: return false
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
    var lastSeenPostURI: String?

    /// URIs of posts already shown as self-thread parents, used to deduplicate the feed.
    var feedParentURIs: Set<String> {
        var uris = Set<String>()
        for feedPost in posts {
            if let reply = feedPost.reply,
               case .postView(let parent) = reply.parent,
               parent.author.actorDID == feedPost.post.author.actorDID {
                uris.insert(parent.uri)
            }
        }
        return uris
    }

    var savedFeeds: [AppBskyLexicon.Feed.GeneratorViewDefinition] = []
    var isLoadingSavedFeeds = false

    var suggestedFeeds: [AppBskyLexicon.Feed.GeneratorViewDefinition] = []
    var isLoadingSuggestedFeeds = false

    var showCompose = false
    var replyContext: ReplyContext?
    var quoteTarget: AppBskyLexicon.Feed.PostViewDefinition?

    var profile: AppBskyLexicon.Actor.ProfileViewDetailedDefinition?
    var profilePosts: [AppBskyLexicon.Feed.FeedViewPostDefinition] = []
    var profileCursor: String?
    var isLoadingProfile = false
    var viewingProfileDID: String?
    struct NavigationEntry {
        let tab: FeedTab
        let profileDID: String?
    }
    var navigationStack: [NavigationEntry] = []

    var notifications: [AppBskyLexicon.Notification.Notification] = []
    var notificationsCursor: String?
    var isLoadingNotifications = false
    var unreadNotificationCount: Int = 0
    private var notificationPollTask: Task<Void, Never>?

    var threadParents: [AppBskyLexicon.Feed.PostViewDefinition] = []
    var threadPost: AppBskyLexicon.Feed.PostViewDefinition?
    var threadReplies: [AppBskyLexicon.Feed.PostViewDefinition] = []
    var isLoadingThread = false

    var selectedImageURL: URL?
    // Tracks local like/repost state overrides before the server catches up
    var likeOverrides: [String: String?] = [:]    // uri -> likeURI (nil = unliked)
    var repostOverrides: [String: String?] = [:]  // uri -> repostURI (nil = unreposted)
    var likeCountAdjustments: [String: Int] = [:]   // uri -> delta
    var repostCountAdjustments: [String: Int] = [:] // uri -> delta

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
            await fetchUnreadCount()
            startNotificationPolling()
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
            await fetchUnreadCount()
            startNotificationPolling()
        } catch {
            // Password not in keychain or auth failed — user needs to log in again
            clearStoredSession()
        }

        isRestoringSession = false
    }

    func logout() {
        notificationPollTask?.cancel()
        notificationPollTask = nil
        unreadNotificationCount = 0
        lastSeenPostURI = nil
        NSApplication.shared.dockTile.badgeLabel = nil

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
        navigationStack = []
        notifications = []
        notificationsCursor = nil
        isLoadingNotifications = false
        threadParents = []
        threadPost = nil
        threadReplies = []
        isLoadingThread = false
        selectedImageURL = nil
        likeOverrides = [:]
        repostOverrides = [:]
        likeCountAdjustments = [:]
        repostCountAdjustments = [:]
        selectedTab = .following
        clearStoredSession()
    }

    private func resetProfileState() {
        profile = nil
        profilePosts = []
        profileCursor = nil
        isLoadingProfile = false
        viewingProfileDID = nil
    }

    private func clearStoredSession() {
        UserDefaults.standard.removeObject(forKey: Self.keychainUUIDKey)
        UserDefaults.standard.removeObject(forKey: Self.pdsURLKey)
        UserDefaults.standard.removeObject(forKey: Self.handleKey)
    }

    // MARK: - Feed Loading

    func loadFeed(loadMore: Bool = false) async {
        guard let kit = atProtoKit, selectedTab.isFeedTab else { return }
        if isLoadingFeed { return }

        isLoadingFeed = true
        feedError = nil

        // Remember the first visible post so we can show an "unread" marker after refresh
        if !loadMore {
            lastSeenPostURI = posts.first(where: { feedPost in
                // Skip replies to other people — those are filtered from the feed
                if let reply = feedPost.reply,
                   case .postView(let parent) = reply.parent,
                   parent.author.actorDID != feedPost.post.author.actorDID {
                    return false
                }
                return true
            })?.post.uri
        }

        // Clear optimistic overrides on full refresh — new posts carry fresh viewer state
        if !loadMore {
            likeOverrides.removeAll()
            repostOverrides.removeAll()
            likeCountAdjustments.removeAll()
            repostCountAdjustments.removeAll()
        }

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

            default:
                break
            }
        } catch {
            feedError = error.localizedDescription
        }

        isLoadingFeed = false
    }

    func switchTab(_ tab: FeedTab) async {
        navigationStack = []
        selectedTab = tab
        switch tab {
        case .profile:
            resetProfileState()
            await loadProfile()
        case .notifications:
            notifications = []
            notificationsCursor = nil
            await loadNotifications()
            await markNotificationsSeen()
        default:
            posts = []
            cursor = nil
            lastSeenPostURI = nil
            await loadFeed()
        }
    }

    func viewProfile(did: String) {
        navigationStack.append(NavigationEntry(tab: selectedTab, profileDID: viewingProfileDID))
        resetProfileState()
        viewingProfileDID = did
        selectedTab = .profile
        Task { await loadProfile() }
    }

    func goBack() {
        guard let entry = navigationStack.popLast() else { return }
        selectedTab = entry.tab
        if entry.tab == .profile {
            viewingProfileDID = entry.profileDID
            resetProfileState()
            viewingProfileDID = entry.profileDID
            Task { await loadProfile() }
        } else {
            viewingProfileDID = nil
        }
    }

    var canGoBack: Bool {
        !navigationStack.isEmpty
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
        if loadMore && profileCursor == nil { return }
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

    // MARK: - Notifications

    func loadNotifications(loadMore: Bool = false) async {
        guard let kit = atProtoKit else { return }
        if loadMore && notificationsCursor == nil { return }
        if isLoadingNotifications { return }

        isLoadingNotifications = true

        do {
            let cursor = loadMore ? notificationsCursor : nil
            let result = try await kit.listNotifications(limit: 50, cursor: cursor)
            if loadMore {
                notifications.append(contentsOf: result.notifications)
            } else {
                notifications = result.notifications
            }
            notificationsCursor = result.cursor
        } catch {
            print("Failed to load notifications: \(error)")
        }

        isLoadingNotifications = false
    }

    func fetchUnreadCount() async {
        guard let kit = atProtoKit else { return }
        do {
            let result = try await kit.getUnreadCount(priority: nil)
            unreadNotificationCount = result.count
            NSApplication.shared.dockTile.badgeLabel = result.count > 0 ? "\(result.count)" : nil
        } catch {
            print("Failed to fetch unread count: \(error)")
        }
    }

    func markNotificationsSeen() async {
        guard let kit = atProtoKit else { return }
        do {
            try await kit.updateSeen()
            unreadNotificationCount = 0
            NSApplication.shared.dockTile.badgeLabel = nil
        } catch {
            print("Failed to mark notifications seen: \(error)")
        }
    }

    private func startNotificationPolling() {
        notificationPollTask?.cancel()
        notificationPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await fetchUnreadCount()
            }
        }
    }

    // MARK: - Thread

    func viewThread(uri: String) {
        if case .thread(let currentURI) = selectedTab, currentURI == uri { return }
        navigationStack.append(NavigationEntry(tab: selectedTab, profileDID: viewingProfileDID))
        threadParents = []
        threadPost = nil
        threadReplies = []
        isLoadingThread = false
        selectedTab = .thread(uri: uri)
        Task { await loadThread(uri: uri) }
    }

    func loadThread(uri: String) async {
        guard let kit = atProtoKit else { return }
        if isLoadingThread { return }

        isLoadingThread = true

        do {
            let result = try await kit.getPostThread(from: uri, depth: 6, parentHeight: 80)
            if case .threadViewPost(let thread) = result.thread {
                threadParents = flattenParents(thread)
                threadPost = thread.post
                threadReplies = thread.replies?.compactMap { reply in
                    if case .threadViewPost(let r) = reply { return r.post }
                    return nil
                } ?? []
            }
        } catch {
            print("Failed to load thread: \(error)")
        }

        isLoadingThread = false
    }

    private func flattenParents(_ thread: AppBskyLexicon.Feed.ThreadViewPostDefinition) -> [AppBskyLexicon.Feed.PostViewDefinition] {
        var parents: [AppBskyLexicon.Feed.PostViewDefinition] = []
        var current = thread.parent
        while case .threadViewPost(let parentThread) = current {
            parents.append(parentThread.post)
            current = parentThread.parent
        }
        parents.reverse()
        return parents
    }

    // MARK: - Follow

    func toggleFollow(did: String) async {
        guard let bluesky = atProtoBluesky else { return }

        do {
            if let followingURI = profile?.viewer?.followingURI {
                try await bluesky.deleteRecord(.recordURI(atURI: followingURI))
            } else {
                _ = try await bluesky.createFollowRecord(actorDID: did)
            }
            // Refresh profile to get updated viewer state
            if let kit = atProtoKit {
                profile = try await kit.getProfile(for: did)
            }
        } catch {
            print("Follow action failed: \(error)")
        }
    }

    // MARK: - Post Actions

    @discardableResult
    func toggleLike(post: AppBskyLexicon.Feed.PostViewDefinition) async -> Bool {
        guard let bluesky = atProtoBluesky else { return false }

        let wasLiked = isLiked(post)
        let likeURI = likeOverrides[post.uri] ?? post.viewer?.likeURI

        do {
            if wasLiked, let likeURI {
                try await bluesky.deleteRecord(.recordURI(atURI: likeURI))
                likeOverrides[post.uri] = .some(nil)
                likeCountAdjustments[post.uri, default: 0] -= 1
            } else {
                let ref = ComAtprotoLexicon.Repository.StrongReference(
                    recordURI: post.uri,
                    cidHash: post.cid
                )
                let result = try await bluesky.createLikeRecord(ref)
                likeOverrides[post.uri] = result.recordURI
                likeCountAdjustments[post.uri, default: 0] += 1
            }
            return true
        } catch {
            print("Like action failed: \(error)")
            return false
        }
    }

    func toggleRepost(post: AppBskyLexicon.Feed.PostViewDefinition) async {
        guard let bluesky = atProtoBluesky else { return }

        let wasReposted = isReposted(post)
        let repostURI = repostOverrides[post.uri] ?? post.viewer?.repostURI

        do {
            if wasReposted, let repostURI {
                try await bluesky.deleteRecord(.recordURI(atURI: repostURI))
                repostOverrides[post.uri] = .some(nil)
                repostCountAdjustments[post.uri, default: 0] -= 1
            } else {
                let ref = ComAtprotoLexicon.Repository.StrongReference(
                    recordURI: post.uri,
                    cidHash: post.cid
                )
                let result = try await bluesky.createRepostRecord(ref)
                repostOverrides[post.uri] = result.recordURI
                repostCountAdjustments[post.uri, default: 0] += 1
            }
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
        quoteTarget = nil
        replyContext = ReplyContext(target: post, rootRef: rootRef)
        showCompose = true
    }

    func quotePost(_ post: AppBskyLexicon.Feed.PostViewDefinition) {
        replyContext = nil
        quoteTarget = post
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
        } else if let quote = quoteTarget {
            let ref = ComAtprotoLexicon.Repository.StrongReference(
                recordURI: quote.uri,
                cidHash: quote.cid
            )
            embed = .record(strongReference: ref)
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
        quoteTarget = nil
        showCompose = false
        await loadFeed()
    }

    // MARK: - Helpers

    func isLiked(_ post: AppBskyLexicon.Feed.PostViewDefinition) -> Bool {
        if let override = likeOverrides[post.uri] {
            return override != nil
        }
        return post.viewer?.likeURI != nil
    }

    func likeCount(_ post: AppBskyLexicon.Feed.PostViewDefinition) -> Int? {
        guard let base = post.likeCount else { return nil }
        return base + (likeCountAdjustments[post.uri] ?? 0)
    }

    func isReposted(_ post: AppBskyLexicon.Feed.PostViewDefinition) -> Bool {
        if let override = repostOverrides[post.uri] {
            return override != nil
        }
        return post.viewer?.repostURI != nil
    }

    func repostCount(_ post: AppBskyLexicon.Feed.PostViewDefinition) -> Int? {
        guard let base = post.repostCount else { return nil }
        return base + (repostCountAdjustments[post.uri] ?? 0)
    }
}
