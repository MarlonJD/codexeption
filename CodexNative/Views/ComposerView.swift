import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @EnvironmentObject private var store: CodexStore
    @State private var isImportingImage = false

    private var canSend: Bool {
        store.authStatus.canStartTurns
            && (!store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.imageAttachments.isEmpty)
    }

    var body: some View {
        VStack(spacing: 10) {
            if !store.pendingApprovals.isEmpty {
                ApprovalBanner(approval: store.pendingApprovals[0])
            }

            VStack(spacing: 0) {
                if !store.imageAttachments.isEmpty {
                    AttachmentStrip()
                    Divider()
                }

                ZStack(alignment: .topLeading) {
                    if store.composerText.isEmpty {
                        Text("Codex'e mesaj yaz")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 13)
                    }

                    TextEditor(text: $store.composerText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 72, maxHeight: 150)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }

                Divider()

                HStack(spacing: 8) {
                    Button {
                        isImportingImage = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                    }
                    .help("Gorsel ekle")

                    ComposerMenu(
                        title: selectedModelTitle,
                        systemImage: "cpu",
                        width: 150
                    ) {
                        ForEach(store.models) { model in
                            Button(model.displayName) {
                                store.selectedModelID = model.id
                            }
                        }
                    }

                    ComposerMenu(
                        title: store.selectedReasoningEffort,
                        systemImage: "bolt",
                        width: 120
                    ) {
                        ForEach(store.currentReasoningEfforts, id: \.self) { effort in
                            Button(effort) {
                                store.selectedReasoningEffort = effort
                            }
                        }
                    }

                    ComposerMenu(
                        title: store.approvalPolicy,
                        systemImage: "shield",
                        width: 132
                    ) {
                        Button("on-request") { store.approvalPolicy = "on-request" }
                        Button("untrusted") { store.approvalPolicy = "untrusted" }
                        Button("never") { store.approvalPolicy = "never" }
                    }

                    Spacer()

                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        store.sendCurrentMessage()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .frame(width: 18, height: 18)
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
                    .help("Gonder")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .glassSurface(
                cornerRadius: 16,
                material: .regularMaterial,
                fallback: Color(nsColor: .textBackgroundColor),
                strokeOpacity: 0.1,
                shadowOpacity: 0.09,
                shadowRadius: 24,
                shadowY: 10,
                tintOpacity: 0.16
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(GlassPaneBackground(material: .ultraThinMaterial, tintOpacity: 0.08))
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

    private var selectedModelTitle: String {
        guard let selected = store.selectedModelID,
              let model = store.models.first(where: { $0.id == selected }) else {
            return "Model"
        }
        return model.displayName
    }
}

struct ComposerMenu<Content: View>: View {
    let title: String
    let systemImage: String
    let width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 9)
            .frame(width: width, height: 28)
            .glassSurface(
                cornerRadius: 8,
                material: .thinMaterial,
                fallback: Color(nsColor: .controlBackgroundColor),
                strokeOpacity: 0.05,
                shadowOpacity: 0,
                shadowRadius: 0,
                shadowY: 0,
                tintOpacity: 0.08
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct AttachmentStrip: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.imageAttachments, id: \.self) { url in
                    AttachmentChip(url: url) {
                        store.removeImageAttachment(url)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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
        .frame(height: 26)
        .glassCapsule(
            material: .thinMaterial,
            fallback: Color.accentColor.opacity(0.11),
            strokeOpacity: 0.08,
            shadowOpacity: 0.01
        )
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
        .glassSurface(
            cornerRadius: 12,
            material: .thinMaterial,
            fallback: Color.orange.opacity(0.12),
            strokeOpacity: 0.08,
            shadowOpacity: 0.04,
            shadowRadius: 12,
            shadowY: 4,
            tintOpacity: 0.08
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.18))
        }
    }
}
