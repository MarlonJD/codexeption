import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Inspector", systemImage: "sidebar.right")
                    .font(.headline)
                Spacer()
                Button {
                    store.toggleInspector()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Kapat")
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GitStatusPanel(status: store.gitStatus)
                    ResourcesPanel(thread: store.selectedThread)
                    DiffPanel(snapshot: store.latestDiff)
                }
                .padding(14)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct GitStatusPanel: View {
    let status: GitStatusSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Git", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            if let branch = status.branch {
                HStack {
                    Text("Branch")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(branch)
                        .font(.system(.caption, design: .monospaced))
                }
            }

            if status.changedFiles.isEmpty {
                Text("Degisiklik yok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(status.changedFiles, id: \.self) { file in
                    Text(file)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                }
            }
        }
    }
}

struct ResourcesPanel: View {
    let thread: ThreadDetail?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Kaynaklar", systemImage: "tray.full")
                .font(.headline)

            if let thread {
                Text(thread.summary.cwd)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                HStack {
                    Text("Turn")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(thread.turns.count)")
                }
                .font(.caption)
            } else {
                Text("Sohbet secilmedi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DiffPanel: View {
    let snapshot: DiffSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Son diff", systemImage: "doc.text.magnifyingglass")
                .font(.headline)

            if let snapshot, !snapshot.unifiedDiff.isEmpty {
                if !snapshot.filePaths.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(snapshot.filePaths, id: \.self) { file in
                            Label(file, systemImage: "doc")
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }

                DiffLinesView(diff: snapshot.unifiedDiff)
                    .frame(maxHeight: 360)
            } else {
                Text("Diff yok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DiffLinesView: View {
    let diff: String

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(line.foreground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(line.background)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var lines: [DiffLine] {
        diff.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in DiffLine(index: index, text: String(line)) }
    }
}

struct DiffLine: Identifiable {
    let index: Int
    let text: String

    var id: Int { index }

    var foreground: Color {
        if text.hasPrefix("+") { return .green }
        if text.hasPrefix("-") { return .red }
        if text.hasPrefix("@@") { return .blue }
        return .primary
    }

    var background: Color {
        if text.hasPrefix("+") { return Color.green.opacity(0.08) }
        if text.hasPrefix("-") { return Color.red.opacity(0.08) }
        if text.hasPrefix("@@") { return Color.blue.opacity(0.08) }
        return .clear
    }
}
