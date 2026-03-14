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

                            ThreadPostDetails(post: mainPost)

                            ThreadReplySeparator(replyCount: mainPost.replyCount ?? 0)
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

// MARK: - Thread Post Details

private struct ThreadPostDetails: View {
    let post: AppBskyLexicon.Feed.PostViewDefinition

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a · MMM d, yyyy"
        return f
    }()

    private var threadgateRecord: AppBskyLexicon.Feed.ThreadgateRecord? {
        post.threadgate?.record.getRecord(ofType: AppBskyLexicon.Feed.ThreadgateRecord.self)
    }

    private enum ReplyRestriction {
        case disabled
        case limitedTo(String)
    }

    private var replyRestriction: ReplyRestriction? {
        guard let rules = threadgateRecord?.allow else { return nil }
        if rules.isEmpty { return .disabled }

        var parts: [String] = []
        for rule in rules {
            switch rule {
            case .mentionRule:
                parts.append("mentioned users")
            case .followerRule:
                parts.append("followers")
            case .followingRule:
                parts.append("people you follow")
            case .listRule:
                parts.append("list members")
            case .unknown:
                break
            }
        }
        if parts.isEmpty { return nil }
        return .limitedTo(parts.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.fullDateFormatter.string(from: post.indexedAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let restriction = replyRestriction {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.circle")
                        .font(.subheadline)
                    switch restriction {
                    case .disabled:
                        Text("Replies disabled")
                            .font(.subheadline)
                    case .limitedTo(let who):
                        Text("Replies limited to \(who)")
                            .font(.subheadline)
                    }
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                if let reposts = post.repostCount, reposts > 0 {
                    statLabel(count: reposts, label: reposts == 1 ? "repost" : "reposts")
                }
                if let quotes = post.quoteCount, quotes > 0 {
                    statLabel(count: quotes, label: quotes == 1 ? "quote" : "quotes")
                }
                if let likes = post.likeCount, likes > 0 {
                    statLabel(count: likes, label: likes == 1 ? "like" : "likes")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func statLabel(count: Int, label: String) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .fontWeight(.semibold)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

// MARK: - Reply Separator

private struct ThreadReplySeparator: View {
    let replyCount: Int

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.separator)
                .frame(height: 1)

            HStack {
                if replyCount > 0 {
                    Text(replyCount == 1 ? "1 reply" : "\(replyCount) replies")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Replies")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))

            Rectangle()
                .fill(.separator)
                .frame(height: 1)
        }
    }
}
