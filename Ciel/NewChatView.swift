import SwiftUI
import ATProtoKit
import NukeUI

struct NewChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var follows: [AppBskyLexicon.Actor.ProfileViewDefinition] = []
    @State private var disabledDIDs: Set<String> = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var startingChatDID: String?

    private var filteredFollows: [AppBskyLexicon.Actor.ProfileViewDefinition] {
        let base: [AppBskyLexicon.Actor.ProfileViewDefinition]
        if searchText.isEmpty {
            base = follows
        } else {
            let query = searchText.lowercased()
            base = follows.filter {
                ($0.displayName?.lowercased().contains(query) ?? false) ||
                $0.actorHandle.lowercased().contains(query)
            }
        }
        // Messageable people first, disabled at the bottom
        return base.sorted { a, b in
            let aDisabled = disabledDIDs.contains(a.actorDID)
            let bDisabled = disabledDIDs.contains(b.actorDID)
            if aDisabled != bDisabled { return !aDisabled }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            followsList
        }
        .frame(minWidth: 400, minHeight: 500)
        .task {
            follows = await appState.loadFollows()
            // Build disabled set: only users with explicit "all" or "following" are messageable
            var disabled = Set<String>()
            for follow in follows {
                let incoming = follow.associated?.chats?.allowIncoming
                if incoming != "all" && incoming != "following" {
                    disabled.insert(follow.actorDID)
                }
            }
            disabledDIDs = disabled
            isLoading = false
        }
    }

    private var header: some View {
        HStack {
            Text("New Chat")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var searchBar: some View {
        TextField("Search people...", text: $searchText)
            .textFieldStyle(.plain)
            .padding(10)
    }

    @ViewBuilder
    private var followsList: some View {
        if isLoading {
            ProgressView("Loading follows...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredFollows.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "person.slash",
                description: Text(searchText.isEmpty ? "You don't follow anyone yet." : "No matches found.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredFollows, id: \.actorDID) { follow in
                        let disabled = disabledDIDs.contains(follow.actorDID)
                        FollowRow(
                            follow: follow,
                            chatDisabled: disabled,
                            isStarting: startingChatDID == follow.actorDID,
                            onSelect: { startChat(with: follow) }
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private func startChat(with follow: AppBskyLexicon.Actor.ProfileViewDefinition) {
        startingChatDID = follow.actorDID
        Task { @MainActor in
            await appState.startChat(with: follow.actorDID)
            startingChatDID = nil
        }
    }
}

private struct FollowRow: View {
    let follow: AppBskyLexicon.Actor.ProfileViewDefinition
    let chatDisabled: Bool
    let isStarting: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                LazyImage(url: follow.avatarImageURL) { state in
                    if let image = state.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Circle().fill(.quaternary)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    if let name = follow.displayName, !name.isEmpty {
                        Text(name)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                    Text("@\(follow.actorHandle)" + (chatDisabled ? " can't be messaged" : ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isStarting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(chatDisabled || isStarting)
        .opacity(chatDisabled ? 0.4 : 1)
    }
}
