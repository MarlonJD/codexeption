import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        Group {
            switch store.setupState {
            case .checking:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Codex hazirlaniyor")
                        .font(.headline)
                }
                .frame(minWidth: 960, minHeight: 640)

            case .missing(let discovery):
                SetupView(discovery: discovery)
                    .frame(minWidth: 760, minHeight: 520)

            case .ready:
                WorkbenchView()
                    .frame(minWidth: 1180, minHeight: 760)
            }
        }
        .task {
            store.start(modelContext: modelContext)
        }
        .alert(item: $store.presentedError) { error in
            Alert(title: Text("Codex hatasi"), message: Text(error.message), dismissButton: .default(Text("Tamam")))
        }
    }
}

struct SetupView: View {
    let discovery: CodexBinaryDiscovery

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "terminal")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Codex ikilisi bulunamadi")
                .font(.largeTitle.bold())

            Text("Uygulama mevcut `codex login` ve `~/.codex` ayarlarini kullanir. Devam etmek icin `codex` komutunun PATH icinde oldugundan veya Codex.app'in Applications altinda kurulu oldugundan emin olun.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Kontrol edilen yollar")
                    .font(.headline)
                ForEach(discovery.checkedPaths, id: \.self) { path in
                    Text(path)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)

            Spacer()
        }
        .padding(36)
    }
}

struct WorkbenchView: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 300)

            Divider()

            VStack(spacing: 0) {
                ThreadHeaderView()
                Divider()
                TranscriptView()
                Divider()
                ComposerView()
            }
            .frame(minWidth: 520)
            .background(Color(nsColor: .windowBackgroundColor))

            if store.isInspectorVisible {
                Divider()
                InspectorView()
                    .frame(width: 340)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Yenile")

                Button {
                    store.toggleInspector()
                } label: {
                    Image(systemName: store.isInspectorVisible ? "sidebar.right" : "sidebar.right")
                }
                .help("Inspector")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ThreadHeaderView: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.selectedThread?.summary.title ?? "Yeni sohbet")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(pathTitle, systemImage: "folder")
                        .lineLimit(1)

                    if let thread = store.selectedThread {
                        Label(thread.summary.updatedAt.shortCodexString, systemImage: "clock")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            AuthPill(status: store.authStatus)

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                store.interruptActiveTurn()
            } label: {
                Image(systemName: "stop.circle")
            }
            .help("Aktif turn'u durdur")
            .disabled(store.selectedThread == nil)
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(.bar)
    }

    private var pathTitle: String {
        if let cwd = store.selectedThread?.summary.cwd ?? store.selectedProject?.path {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return "Tum projeler"
    }
}

struct AuthPill: View {
    let status: AuthStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
    }

    private var label: String {
        switch status {
        case .signedIn(let method):
            method.uppercased()
        case .signingIn:
            "Giris"
        case .signedOut:
            "Giris yok"
        case .unknown:
            "Kontrol"
        case .unavailable:
            "Auth hata"
        }
    }

    private var color: Color {
        switch status {
        case .signedIn:
            .green
        case .signingIn:
            .orange
        case .signedOut:
            .red
        case .unknown:
            .secondary
        case .unavailable:
            .orange
        }
    }
}
