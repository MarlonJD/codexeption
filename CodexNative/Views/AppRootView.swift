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
                    .frame(minWidth: 1120, minHeight: 720)
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
                .frame(width: 280)

            Divider()

            VStack(spacing: 0) {
                ThreadHeaderView()
                Divider()
                TranscriptView()
                Divider()
                ComposerView()
            }
            .frame(minWidth: 520)

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
    }
}

struct ThreadHeaderView: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.selectedThread?.summary.title ?? "Yeni sohbet")
                    .font(.headline)
                    .lineLimit(1)
                Text(store.selectedThread?.summary.cwd ?? store.selectedProject?.path ?? "Proje secilmedi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
