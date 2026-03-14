import SwiftUI
import ATProtoKit

struct UnreadMarker: View {
    var body: some View {
        VStack(spacing: 0) {
            ZigzagEdge()
                .fill(Color.accentColor.opacity(0.08))
                .frame(height: 6)

            HStack(spacing: 6) {
                zigzagLine
                Image(systemName: "arrow.up")
                    .font(.caption2.weight(.bold))
                Text("New posts")
                    .font(.caption.weight(.semibold))
                Image(systemName: "arrow.up")
                    .font(.caption2.weight(.bold))
                zigzagLine
            }
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.08))

            ZigzagEdge()
                .fill(Color.accentColor.opacity(0.08))
                .frame(height: 6)
                .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
        }
    }

    private var zigzagLine: some View {
        GeometryReader { geo in
            ZigzagLine(amplitude: 3, wavelength: 8)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 6)
    }
}

private struct ZigzagEdge: Shape {
    func path(in rect: CGRect) -> Path {
        let amplitude: CGFloat = rect.height
        let wavelength: CGFloat = 12
        var path = Path()
        path.move(to: .zero)
        var x: CGFloat = 0
        var goingDown = true
        while x < rect.width {
            let nextX = min(x + wavelength / 2, rect.width)
            path.addLine(to: CGPoint(x: nextX, y: goingDown ? amplitude : 0))
            goingDown.toggle()
            x = nextX
        }
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct ZigzagLine: Shape {
    let amplitude: CGFloat
    let wavelength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: 0, y: midY))
        var x: CGFloat = 0
        var goingUp = true
        while x < rect.width {
            let nextX = min(x + wavelength / 2, rect.width)
            path.addLine(to: CGPoint(x: nextX, y: midY + (goingUp ? -amplitude : amplitude)))
            goingUp.toggle()
            x = nextX
        }
        return path
    }
}

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
                        ForEach(Array(zip(appState.posts.indices, appState.posts)), id: \.1.post.uri) { index, feedPost in
                            // Skip standalone posts already shown as a thread parent
                            if !appState.feedParentURIs.contains(feedPost.post.uri) || feedPost.reply != nil {
                                if let reply = feedPost.reply,
                                   case .postView(let parent) = reply.parent {
                                    if parent.author.actorDID == feedPost.post.author.actorDID {
                                        // Self-thread: same author replied to their own post
                                        if index > 0, feedPost.post.uri == appState.lastSeenPostURI {
                                            UnreadMarker()
                                        }
                                        PostRowView(post: parent, showThreadLineBelow: true)
                                        PostRowView(feedPost: feedPost, showThreadLineAbove: true)
                                        Divider()
                                    }
                                    // Otherwise skip: reply to someone else's post doesn't belong in feed
                                } else {
                                    if index > 0, feedPost.post.uri == appState.lastSeenPostURI {
                                        UnreadMarker()
                                    }
                                    PostRowView(feedPost: feedPost)
                                    Divider()
                                }
                            }

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
                .refreshable {
                    await appState.loadFeed()
                }
            }
        }
        .navigationTitle(appState.selectedTab.displayName)
    }
}
