import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var store: CodexStore
    @State private var expandedActivityIDs: Set<String> = []
    @State private var isPinnedToBottom = true

    private let bottomID = "transcript-bottom"

    var body: some View {
        let items = store.selectedThread?.transcriptItems ?? []
        let entries = TranscriptRenderEntry.make(from: items)
        let liveSummary = store.liveChangeSummary
        let hasLiveSummary = liveSummary?.files.isEmpty == false
        let turnActivityTitle = store.selectedTurnActivityTitle
        let hasTurnActivity = turnActivityTitle != nil
        let autoScrollSignature = TranscriptAutoScrollSignature.make(
            items: items,
            liveSummary: liveSummary,
            turnActivityTitle: turnActivityTitle
        )

        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if entries.isEmpty && !hasLiveSummary && !hasTurnActivity {
                            if store.isSelectedThreadLoading {
                                LoadingTranscriptView()
                            } else {
                                EmptyTranscriptView()
                            }
                        } else {
                            ForEach(entries) { entry in
                                switch entry {
                                case .item(let item):
                                    TranscriptCell(item: item)
                                        .id(item.id)
                                case .activity(let group):
                                    ToolActivityGroupView(
                                        group: group,
                                        isExpanded: expansionBinding(for: group.id)
                                    )
                                    .id(group.id)
                                }
                            }

                            if let liveSummary, !liveSummary.files.isEmpty {
                                LiveChangeSummaryView(summary: liveSummary)
                                    .id("live-file-changes")
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            if let turnActivityTitle {
                                TurnActivityView(title: turnActivityTitle)
                                    .id("turn-activity")
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                            .background(
                                GeometryReader { marker in
                                    Color.clear.preference(
                                        key: TranscriptBottomPreferenceKey.self,
                                        value: marker.frame(in: .named("transcript-scroll")).maxY
                                    )
                                }
                            )
                    }
                    .frame(maxWidth: 920, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "transcript-scroll")
                .background(GlassPaneBackground(material: .ultraThinMaterial, tintOpacity: 0.05))
                .onPreferenceChange(TranscriptBottomPreferenceKey.self) { bottomY in
                    isPinnedToBottom = bottomY <= viewport.size.height + 96
                }
                .onChange(of: autoScrollSignature) { _, _ in
                    scrollToBottomIfPinned(proxy)
                }
                .onChange(of: store.selectedThreadID) { _, _ in
                    isPinnedToBottom = true
                    Task { @MainActor in
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding {
            expandedActivityIDs.contains(id)
        } set: { isExpanded in
            if isExpanded {
                expandedActivityIDs.insert(id)
            } else {
                expandedActivityIDs.remove(id)
            }
        }
    }

    private func scrollToBottomIfPinned(_ proxy: ScrollViewProxy) {
        guard isPinnedToBottom else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }
}

private struct TranscriptBottomPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum TranscriptRenderEntry: Identifiable, Equatable {
    case item(TranscriptItem)
    case activity(ToolActivityGroup)

    var id: String {
        switch self {
        case .item(let item):
            item.id
        case .activity(let group):
            group.id
        }
    }

    static func make(from items: [TranscriptItem]) -> [TranscriptRenderEntry] {
        var entries: [TranscriptRenderEntry] = []
        var activityItems: [TranscriptItem] = []
        var groupIndex = 0

        func flushActivityItems() {
            guard !activityItems.isEmpty else { return }
            entries.append(.activity(ToolActivityGroup(index: groupIndex, items: activityItems)))
            groupIndex += 1
            activityItems.removeAll(keepingCapacity: true)
        }

        for item in items {
            if item.isOperationalActivity {
                activityItems.append(item)
            } else {
                flushActivityItems()
                entries.append(.item(item))
            }
        }

        flushActivityItems()
        return entries
    }
}

private struct TranscriptAutoScrollSignature {
    static func make(items: [TranscriptItem], liveSummary: LiveChangeSummary?, turnActivityTitle: String?) -> String {
        let last = items.last
        let liveCount = liveSummary?.totalChangeCount ?? 0
        return [
            last?.id ?? "none",
            String(last?.body.count ?? 0),
            String(items.count),
            String(liveCount),
            turnActivityTitle ?? "idle"
        ].joined(separator: ":")
    }
}

struct LoadingTranscriptView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Sohbet yukleniyor")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

struct EmptyTranscriptView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 76, height: 64)
            .glassSurface(
                cornerRadius: 20,
                material: .thinMaterial,
                fallback: Color(nsColor: .controlBackgroundColor),
                strokeOpacity: 0.06,
                shadowOpacity: 0.04,
                shadowRadius: 14,
                shadowY: 6,
                tintOpacity: 0.08
            )

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

private struct ToolActivityGroup: Identifiable, Equatable {
    let id: String
    let items: [TranscriptItem]

    init(index: Int, items: [TranscriptItem]) {
        self.id = "activity-\(index)-\(items.first?.id ?? "empty")"
        self.items = items
    }

    var visibleItems: [TranscriptItem] {
        items.filter { !$0.isLowSignalActivity }
    }

    var hiddenLowSignalCount: Int {
        items.count - visibleItems.count
    }

    var commandInvocationCount: Int {
        items.filter(\.isCommandInvocation).count
    }

    var outputCount: Int {
        visibleItems.filter { $0.kind == .command }.count
    }

    var fileChangeCount: Int {
        visibleItems.filter { $0.kind == .fileChange }.count
    }

    var reasoningCount: Int {
        visibleItems.filter { $0.kind == .reasoning }.count
    }

    var otherToolCount: Int {
        visibleItems.filter { $0.kind == .tool && !$0.isCommandInvocation }.count
    }

    var summary: String {
        var parts: [String] = []
        if commandInvocationCount > 0 { parts.append("\(commandInvocationCount) komut") }
        if outputCount > 0 { parts.append("\(outputCount) output") }
        if fileChangeCount > 0 { parts.append("\(fileChangeCount) dosya") }
        if reasoningCount > 0 { parts.append("\(reasoningCount) dusunce") }
        if otherToolCount > 0 { parts.append("\(otherToolCount) arac") }
        if hiddenLowSignalCount > 0 { parts.append("\(hiddenLowSignalCount) bos kontrol gizli") }
        return parts.isEmpty ? "\(items.count) kayit" : parts.joined(separator: " · ")
    }
}

private struct ToolActivityGroupView: View {
    let group: ToolActivityGroup
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 26, height: 26)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Arac etkinligi")
                            .font(.subheadline.weight(.semibold))
                        Text(group.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(isExpanded ? "Gizle" : "Goster")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(group.visibleItems) { item in
                        ToolActivityDetailRow(item: item)
                    }

                    if group.hiddenLowSignalCount > 0 {
                        Label("\(group.hiddenLowSignalCount) bos polling/output kaydi gizlendi", systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .glassSurface(
            cornerRadius: 12,
            material: .thinMaterial,
            fallback: Color(nsColor: .controlBackgroundColor),
            strokeOpacity: 0.06,
            shadowOpacity: 0.03,
            shadowRadius: 10,
            shadowY: 4,
            tintOpacity: 0.08
        )
    }
}

private struct ToolActivityDetailRow: View {
    let item: TranscriptItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.activityIconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.activityTitle)
                        .font(.caption.weight(.semibold))
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                switch item.kind {
                case .command:
                    ActivityMonospaceBlock(text: item.activityDisplayBody)
                case .fileChange:
                    FileChangeSummaryView(content: item.body)
                case .reasoning:
                    ActivityMonospaceBlock(text: item.activityDisplayBody)
                default:
                    ActivityMonospaceBlock(text: item.activityDisplayBody)
                }
            }
        }
    }
}

private struct ActivityMonospaceBlock: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .glassSurface(
                    cornerRadius: 8,
                    material: .thinMaterial,
                    fallback: Color.black.opacity(0.05),
                    strokeOpacity: 0.04,
                    shadowOpacity: 0,
                    shadowRadius: 0,
                    shadowY: 0,
                    tintOpacity: 0.04
                )
        }
    }
}

private struct TurnActivityView: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassSurface(
            cornerRadius: 12,
            material: .thinMaterial,
            fallback: Color(nsColor: .controlBackgroundColor),
            strokeOpacity: 0.05,
            shadowOpacity: 0.02,
            shadowRadius: 8,
            shadowY: 3,
            tintOpacity: 0.06
        )
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

private extension TranscriptItem {
    var isOperationalActivity: Bool {
        switch kind {
        case .command, .fileChange, .reasoning, .tool:
            true
        case .assistant, .user, .system:
            false
        }
    }

    var isCommandInvocation: Bool {
        guard kind == .tool else { return false }
        let normalized = (title ?? "").lowercased()
        return normalized == "exec_command"
            || normalized == "write_stdin"
            || normalized == "apply_patch"
            || normalized == "multi_tool_use.parallel"
    }

    var isLowSignalActivity: Bool {
        let normalizedTitle = (title ?? "").lowercased()
        if kind == .tool, normalizedTitle == "write_stdin", body.contains("\"chars\":\"\"") {
            return true
        }
        if kind == .command {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return true }
            if trimmed.contains("Process running with session ID"),
               let outputRange = trimmed.range(of: "Output:") {
                let outputTail = trimmed[outputRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                return outputTail.isEmpty
            }
        }
        return false
    }

    var activityIconName: String {
        switch kind {
        case .command: "terminal"
        case .fileChange: "doc.text.magnifyingglass"
        case .reasoning: "brain.head.profile"
        case .tool: isCommandInvocation ? "wrench.and.screwdriver" : "square.stack.3d.up"
        default: "info.circle"
        }
    }

    var activityTitle: String {
        let fallback: String
        switch kind {
        case .command: fallback = "Komut output"
        case .fileChange: fallback = "Dosya degisikligi"
        case .reasoning: fallback = "Akil yurutme"
        case .tool: fallback = "Tool"
        default: fallback = "Kayit"
        }
        return title?.isEmpty == false ? title! : fallback
    }

    var activityDisplayBody: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12_000 else { return trimmed }
        let prefix = String(trimmed.prefix(12_000))
        return "\(prefix)\n\n... \(trimmed.count - 12_000) karakter daha gizlendi"
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
                        .glassSurface(
                            cornerRadius: 9,
                            material: .thinMaterial,
                            fallback: Color(nsColor: .controlBackgroundColor),
                            strokeOpacity: 0.05,
                            shadowOpacity: 0,
                            shadowRadius: 0,
                            shadowY: 0,
                            tintOpacity: 0.06
                        )
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
                    .glassSurface(
                        cornerRadius: 9,
                        material: .thinMaterial,
                        fallback: Color.black.opacity(0.06),
                        strokeOpacity: 0.05,
                        shadowOpacity: 0,
                        shadowRadius: 0,
                        shadowY: 0,
                        tintOpacity: 0.04
                    )
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
            .glassSurface(
                cornerRadius: 12,
                material: .thinMaterial,
                fallback: Color(nsColor: .controlBackgroundColor),
                strokeOpacity: 0.06,
                shadowOpacity: 0.03,
                shadowRadius: 10,
                shadowY: 4,
                tintOpacity: 0.08
            )
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
