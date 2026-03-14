import SwiftUI
import ATProtoKit
import NukeUI

struct NotificationsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isLoadingNotifications && appState.notifications.isEmpty {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.notifications.isEmpty {
                ContentUnavailableView(
                    "No Notifications",
                    systemImage: "bell",
                    description: Text("Nothing yet.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(zip(appState.notifications.indices, appState.notifications)), id: \.1.uri) { index, notification in
                            NotificationRow(notification: notification)

                            Divider()

                            if index == appState.notifications.count - 5 {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        Task { await appState.loadNotifications(loadMore: true) }
                                    }
                            }
                        }

                        if appState.isLoadingNotifications {
                            ProgressView()
                                .padding()
                        }
                    }
                }
                .refreshable {
                    await appState.loadNotifications()
                }
            }
        }
        .navigationTitle("Notifications")
    }
}

struct NotificationRow: View {
    @Environment(AppState.self) private var appState
    let notification: AppBskyLexicon.Notification.Notification

    private var icon: (name: String, color: Color) {
        switch notification.reason {
        case .like:
            return ("heart.fill", .red)
        case .repost:
            return ("arrow.2.squarepath", .green)
        case .follow:
            return ("person.badge.plus", .blue)
        case .reply:
            return ("arrowshape.turn.up.left.fill", .blue)
        case .mention:
            return ("at", .blue)
        case .quote:
            return ("quote.opening", .blue)
        default:
            return ("bell.fill", .secondary)
        }
    }

    private var reasonText: String {
        switch notification.reason {
        case .like: return "liked your post"
        case .repost: return "reposted your post"
        case .follow: return "followed you"
        case .reply: return "replied to your post"
        case .mention: return "mentioned you"
        case .quote: return "quoted your post"
        default: return "interacted with you"
        }
    }

    private var recordText: String? {
        if case .reply = notification.reason,
           let record = notification.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self) {
            return record.text
        }
        if case .mention = notification.reason,
           let record = notification.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self) {
            return record.text
        }
        if case .quote = notification.reason,
           let record = notification.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self) {
            return record.text
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { appState.viewProfile(did: notification.author.actorDID) } label: {
                LazyImage(url: notification.author.avatarImageURL) { state in
                    if let image = state.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Circle().fill(.quaternary)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon.name)
                        .foregroundStyle(icon.color)
                        .font(.caption)

                    Text(notification.author.displayName ?? notification.author.actorHandle)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(reasonText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(relativeTime(notification.indexedAt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let text = recordText {
                    Text(text)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .font(.callout)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if let subjectURI = notification.reasonSubjectURI {
                appState.viewThread(uri: subjectURI)
            } else if notification.reason == .follow {
                appState.viewProfile(did: notification.author.actorDID)
            }
        }
        .opacity(notification.isRead ? 0.8 : 1.0)
    }

}
