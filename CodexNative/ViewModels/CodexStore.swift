import Foundation
import SwiftData
import SwiftUI

enum SetupState: Equatable {
    case checking
    case missing(CodexBinaryDiscovery)
    case ready(URL)
}

struct PresentedError: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

@MainActor
final class CodexStore: ObservableObject {
    @Published var setupState: SetupState = .checking
    @Published var projects: [Project] = []
    @Published var threads: [ThreadSummary] = []
    @Published var selectedProjectID: String?
    @Published var selectedThreadID: String?
    @Published var selectedThread: ThreadDetail?
    @Published var models: [ModelOption] = []
    @Published var selectedModelID: String?
    @Published var selectedReasoningEffort: String = "medium"
    @Published var approvalPolicy: String = "on-request"
    @Published var pendingApprovals: [ApprovalRequest] = []
    @Published var latestDiff: DiffSnapshot?
    @Published var gitStatus: GitStatusSnapshot = .empty
    @Published var isInspectorVisible = true
    @Published var isLoading = false
    @Published var searchTerm = ""
    @Published var composerText = ""
    @Published var imageAttachments: [URL] = []
    @Published var presentedError: PresentedError?

    private var client: CodexClient?
    private var eventTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var configuredCodexPath: String?
    private var bookmarkedProjects: [Project] = []

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    var currentReasoningEfforts: [String] {
        guard let model = models.first(where: { $0.id == selectedModelID || $0.model == selectedModelID }),
              !model.supportedReasoningEfforts.isEmpty else {
            return ["minimal", "low", "medium", "high", "xhigh"]
        }
        return model.supportedReasoningEfforts
    }

    func start(modelContext: ModelContext) {
        guard bootstrapTask == nil else { return }
        bootstrapTask = Task { [weak self] in
            await self?.bootstrap(modelContext: modelContext)
        }
    }

    func reload() {
        Task { await loadInitialData() }
    }

    func selectThread(_ id: String?) {
        selectedThreadID = id
        guard let id else {
            selectedThread = nil
            return
        }

        Task { await openThread(id: id) }
    }

    func selectProject(_ id: String?) {
        selectedProjectID = id
        Task { await loadThreads() }
    }

    func createNewThread() {
        Task {
            await perform { [self] in
                let thread = try await requireClient().startThread(
                    cwd: selectedProject?.path,
                    model: selectedModelID,
                    approvalPolicy: approvalPolicy
                )
                upsertThread(thread)
                selectedThreadID = thread.id
                selectedThread = ThreadDetail(id: thread.id, summary: thread, turns: [])
                await refreshGitStatus(cwd: thread.cwd)
            }
        }
    }

    func sendCurrentMessage() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !imageAttachments.isEmpty else { return }

        let text = composerText
        let attachments = imageAttachments
        composerText = ""
        imageAttachments.removeAll()

        Task {
            await perform { [self] in
                let threadID: String
                if let selectedThreadID {
                    threadID = selectedThreadID
                } else {
                    let thread = try await requireClient().startThread(
                        cwd: selectedProject?.path,
                        model: selectedModelID,
                        approvalPolicy: approvalPolicy
                    )
                    upsertThread(thread)
                    selectedThreadID = thread.id
                    selectedThread = ThreadDetail(id: thread.id, summary: thread, turns: [])
                    threadID = thread.id
                }

                var input: [UserInputDTO] = []
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    input.append(.text(text))
                }
                input.append(contentsOf: attachments.map { .localImage(path: $0.path) })

                let turn = try await requireClient().startTurn(
                    threadID: threadID,
                    input: input,
                    cwd: selectedProject?.path,
                    model: selectedModelID,
                    effort: selectedReasoningEffort,
                    approvalPolicy: approvalPolicy
                )
                appendOrReplaceTurn(turn, threadID: threadID)
            }
        }
    }

    func interruptActiveTurn() {
        guard let threadID = selectedThreadID,
              let turnID = selectedThread?.turns.last(where: { $0.status != "completed" })?.id else {
            return
        }

        Task {
            await perform { [self] in
                try await requireClient().interruptTurn(threadID: threadID, turnID: turnID)
            }
        }
    }

    func respond(to approval: ApprovalRequest, decision: ApprovalDecision) {
        pendingApprovals.removeAll { $0.id == approval.id }
        Task {
            await perform { [self] in
                try await requireClient().respondToApproval(approval, decision: decision)
            }
        }
    }

    func addImageAttachment(_ url: URL) {
        guard !imageAttachments.contains(url) else { return }
        imageAttachments.append(url)
    }

    func removeImageAttachment(_ url: URL) {
        imageAttachments.removeAll { $0 == url }
    }

    func toggleInspector() {
        isInspectorVisible.toggle()
    }

    private func bootstrap(modelContext: ModelContext) async {
        setupState = .checking
        loadPersistedSettings(modelContext: modelContext)

        let discovery = CodexBinaryLocator.discover(userConfiguredPath: configuredCodexPath)
        guard let binaryURL = discovery.url else {
            setupState = .missing(discovery)
            return
        }

        setupState = .ready(binaryURL)
        let client = CodexClient(binaryURL: binaryURL)
        self.client = client
        observeEvents(from: client)
        await loadInitialData()
    }

    private func loadPersistedSettings(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<AppSettingsRecord>()
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        configuredCodexPath = record.codexBinaryPath
        selectedProjectID = record.selectedProjectPath
        selectedThreadID = record.selectedThreadID
        selectedModelID = record.selectedModel
        selectedReasoningEffort = record.selectedReasoningEffort
        approvalPolicy = record.approvalPolicy
        isInspectorVisible = record.inspectorVisible

        if let bookmarks = try? modelContext.fetch(FetchDescriptor<BookmarkRecord>()) {
            bookmarkedProjects = bookmarks.map { Project(path: $0.path, threadCount: 0) }
        }
    }

    private func loadInitialData() async {
        await perform { [self] in
            async let modelsTask = requireClient().listModels()
            async let threadsTask = requireClient().listThreads()
            models = try await modelsTask
            threads = try await threadsTask

            if selectedModelID == nil {
                selectedModelID = models.first(where: \.isDefault)?.id ?? models.first?.id
            }

            deriveProjects()
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }

            if let selectedThreadID {
                await openThread(id: selectedThreadID)
            }
        }
    }

    private func loadThreads() async {
        await perform { [self] in
            threads = try await requireClient().listThreads(cwd: selectedProject?.path, searchTerm: searchTerm.isEmpty ? nil : searchTerm)
            deriveProjects()
        }
    }

    private func openThread(id: String) async {
        await perform { [self] in
            let detail = try await requireClient().readThread(id: id)
            selectedThread = detail
            selectedThreadID = id
            await refreshGitStatus(cwd: detail.summary.cwd)
        }
    }

    private func refreshGitStatus(cwd: String) async {
        gitStatus = await GitInspector.readStatus(cwd: cwd)
    }

    private func observeEvents(from client: CodexClient) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in client.events {
                await self?.apply(event)
            }
        }
    }

    private func apply(_ event: CodexEvent) async {
        switch event {
        case .approvalRequested(let approval):
            if !pendingApprovals.contains(where: { $0.id == approval.id }) {
                pendingApprovals.append(approval)
            }

        case .threadStarted(let thread):
            upsertThread(thread)
            deriveProjects()

        case .threadStatusChanged(let threadID, let status):
            if let index = threads.firstIndex(where: { $0.id == threadID }) {
                let existing = threads[index]
                threads[index] = ThreadSummary(
                    id: existing.id,
                    title: existing.title,
                    preview: existing.preview,
                    cwd: existing.cwd,
                    modelProvider: existing.modelProvider,
                    status: status,
                    createdAt: existing.createdAt,
                    updatedAt: existing.updatedAt
                )
            }

        case .turnStarted(let threadID, let turn):
            appendOrReplaceTurn(turn, threadID: threadID)

        case .turnCompleted(let threadID, let turn):
            appendOrReplaceTurn(turn, threadID: threadID)
            if selectedThreadID == threadID, let cwd = selectedThread?.summary.cwd {
                await refreshGitStatus(cwd: cwd)
            }

        case .assistantDelta(let threadID, let turnID, let itemID, let delta):
            appendDelta(threadID: threadID, turnID: turnID, itemID: itemID, kind: .assistant, title: "Codex", delta: delta)

        case .commandOutputDelta(let threadID, let turnID, let itemID, let delta):
            appendDelta(threadID: threadID, turnID: turnID, itemID: itemID, kind: .command, title: "Komut output", delta: delta)

        case .diffUpdated(let snapshot):
            latestDiff = snapshot

        case .terminated:
            break

        case .notification, .unknown:
            break
        }
    }

    private func appendDelta(threadID: String, turnID: String, itemID: String, kind: TranscriptKind, title: String, delta: String) {
        guard selectedThreadID == threadID else { return }
        if selectedThread == nil, let summary = threads.first(where: { $0.id == threadID }) {
            selectedThread = ThreadDetail(id: threadID, summary: summary, turns: [])
        }

        guard var detail = selectedThread else { return }
        if let turnIndex = detail.turns.firstIndex(where: { $0.id == turnID }) {
            if let itemIndex = detail.turns[turnIndex].items.firstIndex(where: { $0.id == itemID }) {
                detail.turns[turnIndex].items[itemIndex].body += delta
            } else {
                detail.turns[turnIndex].items.append(TranscriptItem(id: itemID, kind: kind, title: title, body: delta, detail: nil, timestamp: .now))
            }
        } else {
            let item = TranscriptItem(id: itemID, kind: kind, title: title, body: delta, detail: nil, timestamp: .now)
            detail.turns.append(CodexTurn(id: turnID, status: "running", items: [item], startedAt: .now, completedAt: nil, durationMs: nil))
        }
        selectedThread = detail
    }

    private func appendOrReplaceTurn(_ turn: CodexTurn, threadID: String) {
        guard selectedThreadID == threadID else { return }
        if selectedThread == nil, let summary = threads.first(where: { $0.id == threadID }) {
            selectedThread = ThreadDetail(id: threadID, summary: summary, turns: [])
        }
        guard var detail = selectedThread else { return }
        if let index = detail.turns.firstIndex(where: { $0.id == turn.id }) {
            detail.turns[index] = turn
        } else {
            detail.turns.append(turn)
        }
        selectedThread = detail
    }

    private func upsertThread(_ thread: ThreadSummary) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.insert(thread, at: 0)
        }
    }

    private func deriveProjects() {
        let grouped = Dictionary(grouping: threads, by: \.cwd)
        var merged = Dictionary(uniqueKeysWithValues: bookmarkedProjects.map { ($0.path, $0) })
        for (path, threads) in grouped {
            merged[path] = Project(path: path, threadCount: threads.count)
        }

        projects = merged.values
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func requireClient() throws -> CodexClient {
        guard let client else { throw CodexClientError.missingBinary }
        return client
    }

    private func perform(_ operation: @MainActor @escaping () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await operation()
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}
