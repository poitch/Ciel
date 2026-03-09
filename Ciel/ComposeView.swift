import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ATProtoKit

struct ComposeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: NSImage?
    @State private var altText = ""
    @State private var isPosting = false
    @State private var postError: String?

    private var charCount: Int { text.count }
    private var isValid: Bool { !text.isEmpty && charCount <= 300 && !isPosting }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Text("\(charCount)/300")
                    .font(.caption)
                    .foregroundStyle(charCount > 300 ? .red : .secondary)

                Spacer()

                Button("Post") {
                    Task { await post() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if let context = appState.replyContext {
                replyContext(context.target)
                Divider()
            }

            TextEditor(text: $text)
                .font(.body)
                .padding(8)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)

            if let previewImage {
                imagePreview(previewImage)
            }

            Divider()

            HStack {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Photos", systemImage: "photo")
                }
                .buttonStyle(.plain)

                Button {
                    pickImageFromFilesystem()
                } label: {
                    Label("Browse", systemImage: "folder")
                }
                .buttonStyle(.plain)

                if imageData != nil {
                    TextField("Alt text", text: $altText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }

                Spacer()

                if let postError {
                    Text(postError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if isPosting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 320)
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                    loadImage(data: data)
                }
            }
        }
    }

    private func replyContext(_ target: AppBskyLexicon.Feed.PostViewDefinition) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left")
                .foregroundStyle(.secondary)
            Text("Replying to @\(target.author.actorHandle)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.3))
    }

    @ViewBuilder
    private func imagePreview(_ image: NSImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: {
                imageData = nil
                previewImage = nil
                selectedPhoto = nil
                altText = ""
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .padding(4)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func loadImage(data: Data) {
        imageData = data
        previewImage = NSImage(data: data)
    }

    private func pickImageFromFilesystem() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            loadImage(data: data)
            selectedPhoto = nil
        }
    }

    private func post() async {
        isPosting = true
        postError = nil

        do {
            try await appState.createPost(
                text: text,
                imageData: imageData,
                altText: altText.isEmpty ? nil : altText
            )
            dismiss()
        } catch {
            postError = error.localizedDescription
        }

        isPosting = false
    }
}
