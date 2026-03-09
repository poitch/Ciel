import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var handle = ""
    @State private var appPassword = ""
    @State private var server = "https://bsky.social"

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)

                Text("Ciel")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Sign in to Bluesky")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
                .frame(height: 32)

            VStack(spacing: 16) {
                TextField("Server", text: $server)
                    .textFieldStyle(.roundedBorder)

                TextField("Handle (e.g. user.bsky.social)", text: $handle)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)

                SecureField("App Password", text: $appPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)

                if let error = appState.loginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: {
                    Task {
                        await appState.login(
                            handle: handle,
                            appPassword: appPassword,
                            server: server
                        )
                    }
                }) {
                    if appState.isLoggingIn {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(handle.isEmpty || appPassword.isEmpty || appState.isLoggingIn)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 320)

            Spacer()

            Text("Use an App Password from Settings > Privacy & Security")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 500)
    }
}
