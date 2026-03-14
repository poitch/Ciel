import SwiftUI
import ATProtoKit
import NukeUI

struct ConversationView: View {
    @Environment(AppState.self) private var appState
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool

    private var other: ChatBskyLexicon.Actor.ProfileViewBasicDefinition? {
        appState.currentConversation.flatMap { appState.otherMember(in: $0) }
    }

    private var conversationID: String? {
        appState.currentConversation?.conversationID
    }

    var body: some View {
        VStack(spacing: 0) {
            conversationHeader
            Divider()
            messageList
            Divider()
            composeBar
        }
        .navigationTitle(other?.displayName ?? other?.actorHandle ?? "Chat")
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

    private var conversationHeader: some View {
        HStack(spacing: 12) {
            Button { if let did = other?.actorDID { appState.viewProfile(did: did) } } label: {
                LazyImage(url: other?.avatarImageURL) { state in
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

            VStack(alignment: .leading, spacing: 1) {
                if let name = other?.displayName, !name.isEmpty {
                    Text(name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                if let handle = other?.actorHandle {
                    Text("@\(handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var messageList: some View {
        if appState.isLoadingMessages && appState.messages.isEmpty {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.messages.isEmpty {
            Spacer()
            Text("No messages yet")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            ScrollView {
                let members = appState.currentConversation?.members ?? []
                let sessionDID = appState.sessionDID
                LazyVStack(spacing: 4) {
                    ForEach(appState.messages.reversed(), id: \.messageID) { message in
                        MessageBubble(
                            message: message,
                            isFromMe: message.sender.authorDID == sessionDID,
                            members: members
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    private var composeBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }

            let canSend = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canSend || appState.isSendingMessage)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let id = conversationID else { return }
        messageText = ""
        Task {
            await appState.sendMessage(text: text, conversationID: id)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatBskyLexicon.Conversation.MessageViewDefinition
    let isFromMe: Bool
    let members: [ChatBskyLexicon.Actor.ProfileViewBasicDefinition]

    var body: some View {
        HStack {
            if isFromMe { Spacer(minLength: 60) }

            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isFromMe ? Color.accentColor : Color.primary.opacity(0.08))
                    .foregroundStyle(isFromMe ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(relativeTime(message.sentAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }

            if !isFromMe { Spacer(minLength: 60) }
        }
    }
}
