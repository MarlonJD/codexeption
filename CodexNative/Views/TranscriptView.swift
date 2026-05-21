import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let items = store.selectedThread?.transcriptItems, !items.isEmpty {
                        ForEach(items) { item in
                            TranscriptCell(item: item)
                                .id(item.id)
                        }
                    } else {
                        EmptyTranscriptView()
                    }
                }
                .padding(18)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: store.selectedThread?.transcriptItems.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }
}

struct EmptyTranscriptView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Sohbet sec veya yeni bir mesaj yaz")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

struct TranscriptCell: View {
    let item: TranscriptItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 22)

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
            .padding(12)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
        }
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

    private var backgroundColor: Color {
        switch item.kind {
        case .user:
            Color(nsColor: .controlBackgroundColor)
        case .command:
            Color(nsColor: .windowBackgroundColor)
        default:
            Color(nsColor: .textBackgroundColor)
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
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
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
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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
