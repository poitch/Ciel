import SwiftUI
import ATProtoKit
import NukeUI

struct ChatsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isLoadingConversations && appState.conversations.isEmpty {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.conversations.isEmpty {
                ContentUnavailableView(
                    "No Conversations",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Your direct messages will appear here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.conversations, id: \.conversationID) { convo in
                            ConversationRow(convo: convo)
                            Divider()
                        }

                        if appState.isLoadingConversations {
                            ProgressView()
                                .padding()
                        }
                    }
                }
                .refreshable {
                    await appState.loadConversations()
                }
            }
        }
        .navigationTitle("Chats")
    }
}

private struct ConversationRow: View {
    @Environment(AppState.self) private var appState
    let convo: ChatBskyLexicon.Conversation.ConversationViewDefinition

    private var other: ChatBskyLexicon.Actor.ProfileViewBasicDefinition? {
        appState.otherMember(in: convo)
    }

    private var lastMessageText: String? {
        if let lastMessage = convo.lastMessage,
           case .messageView(let msg) = lastMessage {
            return msg.text
        }
        return nil
    }

    private var lastMessageDate: Date? {
        if let lastMessage = convo.lastMessage,
           case .messageView(let msg) = lastMessage {
            return msg.sentAt
        }
        return nil
    }

    var body: some View {
        Button {
            appState.openConversation(convo)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                LazyImage(url: other?.avatarImageURL) { state in
                    if let image = state.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Circle().fill(.quaternary)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(other?.displayName ?? other?.actorHandle ?? "Unknown")
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Spacer()

                        if let date = lastMessageDate {
                            Text(relativeTime(date))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let text = lastMessageText {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                if convo.unreadCount > 0 {
                    Text("\(convo.unreadCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
