import SwiftUI
import ATProtoKit

struct ProfileView: View {
    @Environment(AppState.self) private var appState

    private var isOtherProfile: Bool {
        guard let viewing = appState.viewingProfileDID else { return false }
        return viewing != appState.sessionDID
    }

    var body: some View {
        Group {
            if appState.profile == nil && appState.isLoadingProfile {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let profile = appState.profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        bannerView(profile)
                        profileHeader(profile)

                        Divider()

                        LazyVStack(spacing: 0) {
                            ForEach(Array(zip(appState.profilePosts.indices, appState.profilePosts)), id: \.1.post.uri) { index, feedPost in
                                PostRowView(feedPost: feedPost)

                                Divider()

                                if index == appState.profilePosts.count - 5 {
                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear {
                                            Task { await appState.loadProfile(loadMore: true) }
                                        }
                                }
                            }

                            if appState.isLoadingProfile {
                                ProgressView()
                                    .padding()
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Profile Unavailable",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Could not load profile.")
                )
            }
        }
        .navigationTitle("Profile")
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

    @ViewBuilder
    private func bannerView(_ profile: AppBskyLexicon.Actor.ProfileViewDetailedDefinition) -> some View {
        if let bannerURL = profile.bannerImageURL {
            AsyncImage(url: bannerURL) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(height: 150)
            .clipped()
        } else {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 150)
        }
    }

    private func profileHeader(_ profile: AppBskyLexicon.Actor.ProfileViewDetailedDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: profile.avatarImageURL) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().stroke(.background, lineWidth: 3))

                VStack(alignment: .leading, spacing: 2) {
                    if let displayName = profile.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text("@\(profile.actorHandle)")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isOtherProfile {
                    let isFollowing = profile.viewer?.followingURI != nil
                    Button {
                        Task { await appState.toggleFollow(did: profile.actorDID) }
                    } label: {
                        Text(isFollowing ? "Unfollow" : "Follow")
                            .font(.callout)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(isFollowing ? Color.secondary.opacity(0.2) : Color.accentColor)
                            .foregroundStyle(isFollowing ? Color.primary : Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let description = profile.description, !description.isEmpty {
                Text(description)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                if let following = profile.followCount {
                    HStack(spacing: 4) {
                        Text("\(following)").fontWeight(.semibold)
                        Text("following").foregroundStyle(.secondary)
                    }
                }
                if let followers = profile.followerCount {
                    HStack(spacing: 4) {
                        Text("\(followers)").fontWeight(.semibold)
                        Text("followers").foregroundStyle(.secondary)
                    }
                }
                if let posts = profile.postCount {
                    HStack(spacing: 4) {
                        Text("\(posts)").fontWeight(.semibold)
                        Text("posts").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
        }
        .padding(16)
    }
}
