import SwiftUI
import ATProtoKit

struct PostRowView: View {
    @Environment(AppState.self) private var appState
    private let feedPost: AppBskyLexicon.Feed.FeedViewPostDefinition?
    private let _post: AppBskyLexicon.Feed.PostViewDefinition
    var showThreadLineAbove = false
    var showThreadLineBelow = false

    init(feedPost: AppBskyLexicon.Feed.FeedViewPostDefinition, showThreadLineAbove: Bool = false, showThreadLineBelow: Bool = false) {
        self.feedPost = feedPost
        self._post = feedPost.post
        self.showThreadLineAbove = showThreadLineAbove
        self.showThreadLineBelow = showThreadLineBelow
    }

    init(post: AppBskyLexicon.Feed.PostViewDefinition, showThreadLineAbove: Bool = false, showThreadLineBelow: Bool = false) {
        self.feedPost = nil
        self._post = post
        self.showThreadLineAbove = showThreadLineAbove
        self.showThreadLineBelow = showThreadLineBelow
    }

    private var post: AppBskyLexicon.Feed.PostViewDefinition { _post }

    private var postRecord: AppBskyLexicon.Feed.PostRecord? {
        post.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)
    }

    private var repostBy: String? {
        if case .reasonRepost(let reason) = feedPost?.reason {
            return reason.by.displayName ?? reason.by.actorHandle
        }
        return nil
    }

    private var replyParentAuthor: String? {
        if let reply = feedPost?.reply {
            if case .postView(let parent) = reply.parent {
                return parent.author.displayName ?? parent.author.actorHandle
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let repostBy {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.caption)
                    Text("Reposted by \(repostBy)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 52)
            }

            if !showThreadLineAbove, let replyParentAuthor {
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.caption)
                    Text("Replying to \(replyParentAuthor)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 52)
            }

            HStack(alignment: .top, spacing: 12) {
                Button { appState.viewProfile(did: post.author.actorDID) } label: {
                    AsyncImage(url: post.author.avatarImageURL) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(.quaternary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Button { appState.viewProfile(did: post.author.actorDID) } label: {
                            HStack(spacing: 4) {
                                if let displayName = post.author.displayName, !displayName.isEmpty {
                                    Text(displayName)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                }

                                Text("@\(post.author.actorHandle)")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text(relativeTime(post.indexedAt))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let record = postRecord {
                        Text(record.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    embedView

                    actionBar
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay {
            if showThreadLineAbove || showThreadLineBelow {
                GeometryReader { geo in
                    let x = Self.threadLineX
                    let avatarCenterY: CGFloat = threadAvatarCenterY

                    Path { path in
                        if showThreadLineAbove {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: avatarCenterY))
                        }
                        if showThreadLineBelow {
                            path.move(to: CGPoint(x: x, y: avatarCenterY))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                    }
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Thread Line

    private static let avatarSize: CGFloat = 40
    private static let horizontalPadding: CGFloat = 16
    private static let verticalPadding: CGFloat = 10
    private static let indicatorHeight: CGFloat = 22
    private static let threadLineX: CGFloat = horizontalPadding + avatarSize / 2

    private var threadAvatarCenterY: CGFloat {
        var y = Self.verticalPadding
        if repostBy != nil { y += Self.indicatorHeight }
        if !showThreadLineAbove, replyParentAuthor != nil { y += Self.indicatorHeight }
        return y + Self.avatarSize / 2
    }

    // MARK: - Embeds

    @ViewBuilder
    private var embedView: some View {
        if let embed = post.embed {
            switch embed {
            case .embedImagesView(let imagesView):
                imageGrid(imagesView.images)

            case .embedExternalView(let externalView):
                externalLinkView(externalView.external)

            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func imageGrid(_ images: [AppBskyLexicon.Embed.ImagesDefinition.ViewImage]) -> some View {
        let columns = images.count == 1 ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                AsyncImage(url: image.thumbnailImageURL) { img in
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                }
                .frame(maxHeight: images.count == 1 ? 300 : 150)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func externalLinkView(_ external: AppBskyLexicon.Embed.ExternalDefinition.ViewExternal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let thumb = external.thumbnailImageURL {
                AsyncImage(url: thumb) { img in
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(maxHeight: 160)
                .clipped()
            }
            Text(external.title)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(2)
            Text(external.uri)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 4)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 24) {
            Button(action: { appState.reply(to: post, feedPost: feedPost) }) {
                Label(formatCount(post.replyCount), systemImage: "bubble.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button(action: { Task { await appState.toggleRepost(post: post) } }) {
                Label(formatCount(post.repostCount), systemImage: "arrow.2.squarepath")
            }
            .buttonStyle(.plain)
            .foregroundStyle(post.viewer?.repostURI != nil ? .green : .secondary)

            Button(action: { Task { await appState.toggleLike(post: post) } }) {
                Label(formatCount(post.likeCount), systemImage: post.viewer?.likeURI != nil ? "heart.fill" : "heart")
            }
            .buttonStyle(.plain)
            .foregroundStyle(post.viewer?.likeURI != nil ? .red : .secondary)

            Spacer()
        }
        .font(.callout)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func formatCount(_ count: Int?) -> String {
        guard let count, count > 0 else { return "" }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private static let olderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private func relativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }

        return Self.olderDateFormatter.string(from: date)
    }
}
