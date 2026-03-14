import SwiftUI
import ATProtoKit
import AppKit
import NukeUI
import AVKit

struct PostRowView: View {
    @Environment(AppState.self) private var appState
    private let feedPost: AppBskyLexicon.Feed.FeedViewPostDefinition?
    private let _post: AppBskyLexicon.Feed.PostViewDefinition
    var showThreadLineAbove = false
    var showThreadLineBelow = false
    @State private var likeAnimating = false
    @State private var likePending = false

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
                    LazyImage(url: post.author.avatarImageURL) { state in
                        if let image = state.image {
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Circle()
                                .fill(.quaternary)
                        }
                    }
                    .transaction { $0.animation = nil }
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.viewThread(uri: post.uri)
        }
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

            case .embedVideoView(let videoView):
                videoPlayerView(videoView)

            case .embedExternalView(let externalView):
                externalLinkView(externalView.external)

            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func imageGrid(_ images: [AppBskyLexicon.Embed.ImagesDefinition.ViewImage]) -> some View {
        if images.count == 1, let image = images.first {
            let ratio: CGFloat = image.aspectRatio.map {
                CGFloat($0.width) / CGFloat($0.height)
            } ?? (4.0 / 3.0)

            Button {
                appState.selectedImageURL = image.fullSizeImageURL
            } label: {
                LazyImage(url: image.thumbnailImageURL) { state in
                    if let img = state.image {
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                    }
                }
                .transaction { $0.animation = nil }
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxHeight: 300)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        } else {
            let columns = 2
            let cellHeight: CGFloat = 150
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Button {
                        appState.selectedImageURL = image.fullSizeImageURL
                    } label: {
                        GeometryReader { geo in
                            LazyImage(url: image.thumbnailImageURL) { state in
                                if let img = state.image {
                                    img.resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Rectangle()
                                        .fill(.quaternary)
                                }
                            }
                            .transaction { $0.animation = nil }
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
                        .frame(height: cellHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func videoPlayerView(_ video: AppBskyLexicon.Embed.VideoDefinition.View) -> some View {
        VideoThumbnailView(video: video)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func externalLinkView(_ external: AppBskyLexicon.Embed.ExternalDefinition.ViewExternal) -> some View {
        Button {
            if let url = URL(string: external.uri) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if let thumb = external.thumbnailImageURL {
                    LazyImage(url: thumb) { state in
                        if let img = state.image {
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .transaction { $0.animation = nil }
                    .frame(height: 160)
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
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        let liked = appState.isLiked(post)
        let reposted = appState.isReposted(post)

        return HStack(spacing: 24) {
            Button(action: { appState.reply(to: post, feedPost: feedPost) }) {
                Label(formatCount(post.replyCount), systemImage: "bubble.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Menu {
                Button {
                    Task { await appState.toggleRepost(post: post) }
                } label: {
                    Label(reposted ? "Undo Repost" : "Repost", systemImage: "arrow.2.squarepath")
                }
                Button {
                    appState.quotePost(post)
                } label: {
                    Label("Quote Post", systemImage: "quote.opening")
                }
            } label: {
                Label(formatCount(appState.repostCount(post)), systemImage: "arrow.2.squarepath")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(reposted ? .green : .secondary)

            Button {
                Task {
                    likePending = true
                    let success = await appState.toggleLike(post: post)
                    likePending = false
                    if success {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
                            likeAnimating = true
                        }
                        try? await Task.sleep(for: .milliseconds(300))
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            likeAnimating = false
                        }
                    }
                }
            } label: {
                Label(formatCount(appState.likeCount(post)), systemImage: liked ? "heart.fill" : "heart")
                    .overlay {
                        if likePending {
                            HeartPulseView()
                        }
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(liked ? .red : .secondary)
            .scaleEffect(likeAnimating ? 1.4 : 1.0)

            Spacer()
        }
        .font(.callout)
        .padding(.top, 4)
    }

}

private struct VideoThumbnailView: View {
    let video: AppBskyLexicon.Embed.VideoDefinition.View
    @State private var player: AVPlayer?

    private var aspectRatio: CGFloat {
        video.aspectRatio.map { CGFloat($0.width) / CGFloat($0.height) } ?? (16.0 / 9.0)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = min(width / aspectRatio, 300)

            if let player {
                VideoPlayer(player: player)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onDisappear {
                        self.player?.pause()
                        self.player = nil
                    }
            } else {
                Button {
                    if let url = URL(string: video.playlistURI) {
                        let newPlayer = AVPlayer(url: url)
                        player = newPlayer
                        newPlayer.play()
                    }
                } label: {
                    ZStack {
                        if let thumbStr = video.thumbnailImageURL, let thumbURL = URL(string: thumbStr) {
                            LazyImage(url: thumbURL) { state in
                                if let image = state.image {
                                    image.resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Rectangle().fill(.quaternary)
                                }
                            }
                            .transaction { $0.animation = nil }
                        } else {
                            Rectangle().fill(.quaternary)
                        }

                        Circle()
                            .fill(.black.opacity(0.5))
                            .frame(width: 50, height: 50)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .offset(x: 2)
                            }
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxHeight: 300)
    }
}

private struct HeartPulseView: View {
    @State private var pulse = false

    var body: some View {
        Image(systemName: "heart.fill")
            .foregroundStyle(.red.opacity(0.5))
            .scaleEffect(pulse ? 2.0 : 1.0)
            .opacity(pulse ? 0 : 0.6)
            .animation(
                .easeOut(duration: 0.8)
                .repeatForever(autoreverses: false),
                value: pulse
            )
            .onAppear { pulse = true }
    }
}
