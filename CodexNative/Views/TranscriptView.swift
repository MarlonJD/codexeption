import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        let items = store.selectedThread?.transcriptItems ?? []

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !items.isEmpty {
                        ForEach(items) { item in
                            TranscriptCell(item: item)
                                .id(item.id)
                        }
                        if let summary = store.liveChangeSummary, !summary.files.isEmpty {
                            LiveChangeSummaryView(summary: summary)
                                .id("live-file-changes")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    } else if let summary = store.liveChangeSummary, !summary.files.isEmpty {
                        LiveChangeSummaryView(summary: summary)
                            .id("live-file-changes")
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        EmptyTranscriptView()
                    }
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: store.selectedThread?.transcriptItems.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .onChange(of: store.liveChangeSummary?.totalChangeCount) { _, _ in
                guard store.liveChangeSummary?.files.isEmpty == false else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("live-file-changes", anchor: .bottom)
                }
            }
        }
    }
}

struct EmptyTranscriptView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 76, height: 64)

            VStack(spacing: 5) {
                Text("Sohbet sec veya yeni bir mesaj yaz")
                    .font(.title3.weight(.semibold))
                Text("Yerel Codex gecmisi yuklenince solda gorunur.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

struct TranscriptCell: View {
    let item: TranscriptItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
                .background(iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.title ?? defaultTitle)
                        .font(.subheadline.weight(.semibold))
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                switch item.kind {
                case .assistant, .user, .reasoning, .system:
                    MarkdownBlocksView(text: item.body)

                case .command:
                    CommandOutputView(command: item.title, output: item.body)

                case .fileChange:
                    FileChangeSummaryView(content: item.body)

                case .tool:
                    Text(item.body)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.vertical, 6)
    }

    private var defaultTitle: String {
        switch item.kind {
        case .user: "Sen"
        case .assistant: "Codex"
        case .reasoning: "Akil yurutme"
        case .command: "Komut"
        case .fileChange: "Diff"
        case .tool: "Tool"
        case .system: "Sistem"
        }
    }

    private var iconName: String {
        switch item.kind {
        case .user: "person.crop.circle"
        case .assistant: "sparkles"
        case .reasoning: "brain.head.profile"
        case .command: "terminal"
        case .fileChange: "doc.text.magnifyingglass"
        case .tool: "wrench.and.screwdriver"
        case .system: "info.circle"
        }
    }

    private var iconColor: Color {
        switch item.kind {
        case .command: .orange
        case .fileChange: .blue
        case .assistant: .accentColor
        default: .secondary
        }
    }

}

struct MarkdownBlocksView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                if block.isCode {
                    Text(block.content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Text(block.content)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var blocks: [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        let parts = text.components(separatedBy: "```")
        for index in parts.indices {
            let content = parts[index].trimmingCharacters(in: .newlines)
            guard !content.isEmpty else { continue }
            result.append(MarkdownBlock(isCode: index % 2 == 1, content: content))
        }
        return result.isEmpty ? [MarkdownBlock(isCode: false, content: text)] : result
    }
}

struct MarkdownBlock: Identifiable {
    let id = UUID()
    let isCode: Bool
    let content: String
}

struct CommandOutputView: View {
    let command: String?
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let command, !command.isEmpty {
                Text(command)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
            }

            if !output.isEmpty {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

struct FileChangeSummaryView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(content.split(separator: "\n").map(String.init), id: \.self) { file in
                Label(file, systemImage: "doc")
                    .font(.caption)
            }
        }
    }
}

struct LiveChangeSummaryView: View {
    let summary: LiveChangeSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("\(summary.fileCount) dosya degistirildi")
                        .foregroundStyle(.secondary)
                    AnimatedSignedNumber(value: summary.additions, sign: "+", color: .green)
                    AnimatedSignedNumber(value: summary.deletions, sign: "-", color: .red)
                    Spacer()
                }
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(summary.files) { change in
                        LiveFileChangeRow(change: change)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .animation(.snappy(duration: 0.28), value: summary)
    }
}

struct LiveFileChangeRow: View {
    let change: LiveFileChange

    var body: some View {
        HStack(spacing: 6) {
            Text(change.displayName)
                .foregroundStyle(.blue)
                .lineLimit(1)
            AnimatedSignedNumber(value: change.additions, sign: "+", color: .green)
            AnimatedSignedNumber(value: change.deletions, sign: "-", color: .red)
            Text(change.statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.body)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct AnimatedSignedNumber: View {
    let value: Int
    let sign: String
    let color: Color

    var body: some View {
        Text("\(sign)\(value)")
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(value)))
            .animation(.snappy(duration: 0.25), value: value)
    }
}
