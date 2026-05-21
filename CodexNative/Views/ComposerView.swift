import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @EnvironmentObject private var store: CodexStore
    @State private var isImportingImage = false

    var body: some View {
        VStack(spacing: 8) {
            if !store.pendingApprovals.isEmpty {
                ApprovalBanner(approval: store.pendingApprovals[0])
            }

            if !store.imageAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.imageAttachments, id: \.self) { url in
                            AttachmentChip(url: url) {
                                store.removeImageAttachment(url)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    isImportingImage = true
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .help("Gorsel ekle")

                TextEditor(text: $store.composerText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 54, maxHeight: 130)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    store.sendCurrentMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.imageAttachments.isEmpty)
                .help("Gonder")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .background(.bar)
        .fileImporter(
            isPresented: $isImportingImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                urls.forEach(store.addImageAttachment)
            }
        }
    }
}

struct AttachmentChip: View {
    let url: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
            Text(url.lastPathComponent)
                .lineLimit(1)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Kaldir")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }
}

struct ApprovalBanner: View {
    @EnvironmentObject private var store: CodexStore
    let approval: ApprovalRequest

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: approval.kind == .commandExecution ? "terminal" : "lock.shield")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(approval.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(approval.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Reddet") {
                store.respond(to: approval, decision: .decline)
            }

            Button("Oturumda kabul") {
                store.respond(to: approval, decision: .acceptForSession)
            }

            Button("Kabul") {
                store.respond(to: approval, decision: .accept)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 14)
    }
}
