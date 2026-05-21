import AppKit
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
    @Published var permissionMode: PermissionMode = .autoReview
    @Published var pendingApprovals: [ApprovalRequest] = []
    @Published var latestDiff: DiffSnapshot?
    @Published var liveChangeSummary: LiveChangeSummary?
    @Published var authStatus: AuthStatus = .unknown
    @Published var gitStatus: GitStatusSnapshot = .empty
    @Published var isInspectorVisible = true
    @Published var isLoading = false
    @Published var searchTerm = ""
    @Published var composerText = ""
    @Published var imageAttachments: [URL] = []
    @Published var presentedError: PresentedError?
    @Published var expandedProjectIDs: Set<String> = []
    @Published var loadingThreadID: String?

    private var client: CodexClient?
    private var eventTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var configuredCodexPath: String?
    private var bookmarkedProjects: [Project] = []
    private var projectOrder: [String] = []
    private var hasStoredExpandedProjects = false
    private let projectOrderKey = "CodexNative.projectOrder"
    private let expandedProjectsKey = "CodexNative.expandedProjects"

    init() {
        loadSidebarState()
    }

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    var visibleThreads: [ThreadSummary] {
        threads.filter { thread in
            guard !thread.isArchived else { return false }
            let projectMatches = selectedProjectID == nil || thread.cwd == selectedProjectID
            let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard projectMatches else { return false }
            guard !term.isEmpty else { return true }
            return thread.title.localizedCaseInsensitiveContains(term)
                || thread.preview.localizedCaseInsensitiveContains(term)
                || thread.cwd.localizedCaseInsensitiveContains(term)
        }
        .sorted(by: sortThreadsByRecentActivity)
    }

    var isSelectedThreadLoading: Bool {
        selectedThreadID != nil && loadingThreadID == selectedThreadID
    }

    var selectedTurnActivityTitle: String? {
        guard loadingThreadID == nil else { return nil }
        if let turn = selectedThread?.turns.last(where: \.isActive) {
            return turn.isWritingAssistantMessage ? "Yanit yaziyor" : "Dusunuyor"
        }
        return nil
    }

    var currentReasoningEfforts: [String] {
        guard let model = models.first(where: { $0.id == selectedModelID || $0.model == selectedModelID }),
              !model.supportedReasoningEfforts.isEmpty else {
            return ["low", "medium", "high", "xhigh"]
        }
        var seen = Set<String>()
        return model.supportedReasoningEfforts.filter { seen.insert($0).inserted }
    }

    private func sortThreadsByRecentActivity(_ lhs: ThreadSummary, _ rhs: ThreadSummary) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
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

    func refreshAuth() {
        Task { await loadAuthStatus() }
    }

    func selectThread(_ id: String?) {
        selectedThreadID = id
        guard let id else {
            selectedThread = nil
            liveChangeSummary = nil
            loadingThreadID = nil
            return
        }

        if let thread = threads.first(where: { $0.id == id }) {
            selectedProjectID = thread.cwd
            expandedProjectIDs.insert(thread.cwd)
            saveExpandedProjects()
            selectedThread = ThreadDetail(id: thread.id, summary: thread, turns: [])
        }
        loadingThreadID = id

        Task { await openThread(id: id) }
    }

    func selectProject(_ id: String?) {
        selectedProjectID = id
        liveChangeSummary = nil
    }

    func toggleProject(_ id: String) {
        selectedProjectID = id
        liveChangeSummary = nil
        if expandedProjectIDs.contains(id) {
            expandedProjectIDs.remove(id)
        } else {
            expandedProjectIDs.insert(id)
        }
        saveExpandedProjects()
    }

    func isProjectExpanded(_ id: String) -> Bool {
        expandedProjectIDs.contains(id)
    }

    func threads(forProject id: String) -> [ThreadSummary] {
        threads.filter { thread in
            guard !thread.isArchived else { return false }
            guard thread.cwd == id else { return false }
            let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return true }
            return thread.title.localizedCaseInsensitiveContains(term)
                || thread.preview.localizedCaseInsensitiveContains(term)
                || thread.cwd.localizedCaseInsensitiveContains(term)
        }
        .sorted(by: sortThreadsByRecentActivity)
    }

    func moveProject(_ draggedID: String, before targetID: String) {
        guard draggedID != targetID,
              let fromIndex = projects.firstIndex(where: { $0.id == draggedID }) else {
            return
        }

        var ordered = projects
        let dragged = ordered.remove(at: fromIndex)
        let targetIndex = ordered.firstIndex(where: { $0.id == targetID }) ?? ordered.endIndex
        ordered.insert(dragged, at: targetIndex)
        projects = ordered
        projectOrder = ordered.map(\.id)
        saveProjectOrder()
    }

    func selectModel(_ id: String) {
        selectedModelID = id
        guard let model = models.first(where: { $0.id == id || $0.model == id }) else { return }
        if !model.supportedReasoningEfforts.isEmpty,
           !model.supportedReasoningEfforts.contains(selectedReasoningEffort) {
            selectedReasoningEffort = model.defaultReasoningEffort
        }
    }

    func selectPermissionMode(_ mode: PermissionMode) {
        permissionMode = mode
        approvalPolicy = mode.approvalPolicy ?? "default"
    }

    func createNewThread() {
        selectedThreadID = nil
        selectedThread = nil
        liveChangeSummary = nil
        composerText = ""
        imageAttachments.removeAll()
    }

    func sendCurrentMessage() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !imageAttachments.isEmpty else { return }
        guard ensureCanStartTurns() else { return }

        let text = composerText
        let attachments = imageAttachments
        let cwd = selectedProject?.path
        let modelID = selectedModelID
        let effort = selectedReasoningEffort
        let mode = permissionMode
        let isNewThread = selectedThreadID == nil
        let pendingThreadID = selectedThreadID ?? "pending-thread-\(UUID().uuidString)"
        composerText = ""
        imageAttachments.removeAll()

        if isNewThread {
            let summary = pendingThreadSummary(id: pendingThreadID, text: text, attachments: attachments, cwd: cwd)
            upsertThread(summary)
            deriveProjects()
            selectedThreadID = pendingThreadID
            selectedThread = ThreadDetail(id: pendingThreadID, summary: summary, turns: [])
        }
        let pending = appendPendingUserTurn(threadID: pendingThreadID, text: text, attachments: attachments)

        Task {
            await perform { [self] in
                let threadID: String
                if isNewThread {
                    let thread = try await requireClient().startThread(
                        cwd: cwd,
                        model: modelID,
                        permissionMode: mode
                    )
                    promotePendingThread(pendingThreadID, to: thread)
                    liveChangeSummary = nil
                    threadID = thread.id
                } else {
                    threadID = pendingThreadID
                }

                var input: [UserInputDTO] = []
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    input.append(.text(text))
                }
                input.append(contentsOf: attachments.map { .localImage(path: $0.path) })

                let turn = try await requireClient().startTurn(
                    threadID: threadID,
                    input: input,
                    cwd: cwd,
                    model: modelID,
                    effort: effort,
                    permissionMode: mode
                )
                liveChangeSummary = nil
                replacePendingTurn(pending.turnID, with: turn, threadID: threadID, fallbackUserItem: pending.userItem)
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

    func startChatGPTLogin() {
        Task {
            await perform { [self] in
                let response = try await requireClient().startChatGPTLogin()
                if let url = response.loginURL {
                    let opened = NSWorkspace.shared.open(url)
                    if !opened {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        presentedError = PresentedError(message: "Giris baglantisi tarayicida acilamadi. URL panoya kopyalandi.")
                    }
                }
                let message: String
                if let code = response.userCode {
                    message = "Kod: \(code)"
                } else {
                    message = "Tarayicida devam et"
                }
                authStatus = .signingIn(message)
            }
        }
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
        permissionMode = PermissionMode(legacyApprovalPolicy: record.approvalPolicy)
        isInspectorVisible = record.inspectorVisible

        if let bookmarks = try? modelContext.fetch(FetchDescriptor<BookmarkRecord>()) {
            bookmarkedProjects = bookmarks.map { Project(path: $0.path, threadCount: 0) }
        }
    }

    private func loadSidebarState() {
        let defaults = UserDefaults.standard
        projectOrder = defaults.stringArray(forKey: projectOrderKey) ?? []
        if let expanded = defaults.array(forKey: expandedProjectsKey) as? [String] {
            expandedProjectIDs = Set(expanded)
            hasStoredExpandedProjects = true
        }
    }

    private func saveProjectOrder() {
        UserDefaults.standard.set(projectOrder, forKey: projectOrderKey)
    }

    private func saveExpandedProjects() {
        UserDefaults.standard.set(Array(expandedProjectIDs), forKey: expandedProjectsKey)
        hasStoredExpandedProjects = true
    }

    private func loadInitialData() async {
        isLoading = true

        await refreshLocalAuthStatus()
        await loadLocalThreadFallback()
        applyFallbackModelsIfNeeded()
        isLoading = false

        Task { await refreshAuthStatus(refreshToken: false, presentError: false) }
        Task { await refreshModelsForBootstrap() }
        Task { await refreshThreadsForBootstrap() }
    }

    private func loadThreads() async {
        await perform { [self] in
            do {
                applyThreadSummaries(try await requireClient().listThreads())
                await restoreThreadSelection()
            } catch {
                await loadLocalThreadFallback()
                if threads.isEmpty {
                    throw error
                }
            }
        }
    }

    private func loadAuthStatus() async {
        await refreshAuthStatus(refreshToken: true, presentError: true)
    }

    private func openThread(id: String) async {
        loadingThreadID = id
        if await loadLocalThreadDetail(id: id) {
            return
        }

        do {
            try await loadThreadDetail(id: id)
        } catch {
            if selectedThreadID == id {
                presentedError = PresentedError(message: "Sohbet acilamadi: \(error.localizedDescription)")
            }
            if loadingThreadID == id {
                loadingThreadID = nil
            }
        }
    }

    private func refreshAuthStatus(refreshToken: Bool, presentError: Bool) async {
        let previousStatus = authStatus
        do {
            let client = try requireClient()
            let status = try await client.getAuthStatus(refreshToken: refreshToken)
            let resolvedStatus: AuthStatus
            if status == .signedOut && !refreshToken {
                resolvedStatus = try await client.getAuthStatus(refreshToken: true)
            } else {
                resolvedStatus = status
            }

            if resolvedStatus == .signedOut,
               let localStatus = await client.localLoginStatus(),
               localStatus.canStartTurns {
                authStatus = localStatus
            } else {
                authStatus = resolvedStatus
            }
        } catch {
            let localStatus = await client?.localLoginStatus()
            if let localStatus, localStatus.canStartTurns {
                authStatus = localStatus
            } else if previousStatus.canStartTurns {
                authStatus = previousStatus
            } else {
                authStatus = .unavailable(error.localizedDescription)
            }
            if presentError {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
    }

    private func refreshLocalAuthStatus() async {
        guard let status = await client?.localLoginStatus() else { return }
        authStatus = status
    }

    private func refreshThreadsForBootstrap() async {
        do {
            applyThreadSummaries(try await requireClient().listThreads())
            await restoreThreadSelection()
        } catch {
            if threads.isEmpty {
                await loadLocalThreadFallback()
            }
            if threads.isEmpty {
                selectedThreadID = nil
                selectedThread = nil
                presentedError = PresentedError(message: "Sohbetler yuklenemedi: \(error.localizedDescription)")
            }
        }
    }

    private func refreshModelsForBootstrap() async {
        applyFallbackModelsIfNeeded()
        do {
            models = try await requireClient().listModels()
            normalizeSelectedModel()
        } catch {
            applyFallbackModelsIfNeeded()
        }
    }

    private func loadLocalThreadFallback() async {
        let localThreads = await LocalCodexHistoryReader.readSummaries()
        guard !localThreads.isEmpty else { return }
        applyThreadSummaries(localThreads)
        restoreLocalThreadSelection()
    }

    private func applyThreadSummaries(_ summaries: [ThreadSummary]) {
        threads = summaries
            .filter { !$0.isArchived }
            .sorted(by: sortThreadsByRecentActivity)
        deriveProjects()
        if let selectedProjectID, !projects.contains(where: { $0.id == selectedProjectID }) {
            self.selectedProjectID = nil
        }
    }

    private func restoreLocalThreadSelection() {
        guard let threadID = selectedThreadID.flatMap({ id in
            visibleThreads.contains(where: { $0.id == id }) ? id : nil
        }) ?? visibleThreads.first?.id,
              let summary = threads.first(where: { $0.id == threadID }) else {
            selectedThreadID = nil
            selectedThread = nil
            liveChangeSummary = nil
            return
        }

        selectedThreadID = threadID
        if selectedThread?.id != threadID {
            selectedThread = ThreadDetail(id: threadID, summary: summary, turns: [])
        }
    }

    private func applyFallbackModelsIfNeeded() {
        guard models.isEmpty else { return }
        models = ModelOption.fallbackOptions
        normalizeSelectedModel()
    }

    private func normalizeSelectedModel() {
        if selectedModelID == nil || !models.contains(where: { $0.id == selectedModelID || $0.model == selectedModelID }) {
            selectedModelID = models.first(where: \.isDefault)?.id ?? models.first?.id
        }
        if let selectedModelID,
           let model = models.first(where: { $0.id == selectedModelID || $0.model == selectedModelID }),
           !model.supportedReasoningEfforts.isEmpty,
           !model.supportedReasoningEfforts.contains(selectedReasoningEffort) {
            selectedReasoningEffort = model.defaultReasoningEffort
        }
    }

    private func restoreThreadSelection() async {
        guard let threadID = selectedThreadID.flatMap({ id in
            visibleThreads.contains(where: { $0.id == id }) ? id : nil
        }) ?? visibleThreads.first?.id else {
            selectedThreadID = nil
            selectedThread = nil
            liveChangeSummary = nil
            loadingThreadID = nil
            return
        }

        if await loadLocalThreadDetail(id: threadID) {
            return
        }

        do {
            try await loadThreadDetail(id: threadID)
        } catch {
            selectedThreadID = nil
            selectedThread = nil
            liveChangeSummary = nil
            loadingThreadID = nil
        }
    }

    private func loadThreadDetail(id: String) async throws {
        let detail = try await requireClient().readThread(id: id)
        applyThreadDetail(detail)
        await refreshGitStatus(cwd: detail.summary.cwd)
    }

    private func loadLocalThreadDetail(id: String) async -> Bool {
        guard let detail = await LocalCodexHistoryReader.readDetail(id: id) else {
            return false
        }
        applyThreadDetail(detail)
        await refreshGitStatus(cwd: detail.summary.cwd)
        return true
    }

    private func applyThreadDetail(_ detail: ThreadDetail) {
        selectedThread = detail
        selectedThreadID = detail.id
        selectedProjectID = detail.summary.cwd
        expandedProjectIDs.insert(detail.summary.cwd)
        saveExpandedProjects()
        liveChangeSummary = nil
        if loadingThreadID == detail.id {
            loadingThreadID = nil
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
                let updated = ThreadSummary(
                    id: existing.id,
                    title: existing.title,
                    preview: existing.preview,
                    cwd: existing.cwd,
                    modelProvider: existing.modelProvider,
                    status: status,
                    createdAt: existing.createdAt,
                    updatedAt: existing.updatedAt
                )
                if updated.isArchived {
                    threads.remove(at: index)
                    deriveProjects()
                } else {
                    threads[index] = updated
                }
            }

        case .turnStarted(let threadID, let turn):
            if selectedThreadID == threadID {
                liveChangeSummary = nil
            }
            appendOrReplaceTurn(turn, threadID: threadID)

        case .turnCompleted(let threadID, let turn):
            appendOrReplaceTurn(turn, threadID: threadID)
            if selectedThreadID == threadID, let cwd = selectedThread?.summary.cwd {
                await refreshGitStatus(cwd: cwd)
            }

        case .itemUpdated(let threadID, let turnID, let item):
            upsertItem(threadID: threadID, turnID: turnID, item: item)

        case .assistantDelta(let threadID, let turnID, let itemID, let delta):
            appendDelta(threadID: threadID, turnID: turnID, itemID: itemID, kind: .assistant, title: "Codex", delta: delta)

        case .commandOutputDelta(let threadID, let turnID, let itemID, let delta):
            appendDelta(threadID: threadID, turnID: turnID, itemID: itemID, kind: .command, title: "Komut output", delta: delta)

        case .diffUpdated(let snapshot):
            latestDiff = snapshot
            if selectedThreadID == snapshot.threadID {
                liveChangeSummary = snapshot.changeSummary
            }

        case .turnError(let threadID, let turnID, let message):
            let item = TranscriptItem(id: "error-\(turnID ?? UUID().uuidString)", kind: .system, title: "Codex hatasi", body: message, detail: nil, timestamp: .now)
            upsertItem(threadID: threadID, turnID: turnID ?? UUID().uuidString, item: item)

        case .accountUpdated:
            await loadAuthStatus()

        case .accountLoginCompleted(_, let success, let error):
            if success {
                await loadAuthStatus()
            } else {
                authStatus = .signedOut
                if let error, !error.isEmpty {
                    presentedError = PresentedError(message: error)
                }
            }

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

    private func appendPendingUserTurn(threadID: String, text: String, attachments: [URL]) -> (turnID: String, userItem: TranscriptItem) {
        let turnID = "pending-turn-\(UUID().uuidString)"
        let userItem = TranscriptItem(
            id: "pending-user-\(UUID().uuidString)",
            kind: .user,
            title: "Sen",
            body: pendingUserBody(text: text, attachments: attachments),
            detail: nil,
            timestamp: .now
        )
        let turn = CodexTurn(id: turnID, status: "pending", items: [userItem], startedAt: .now, completedAt: nil, durationMs: nil)

        if selectedThread == nil || selectedThread?.id != threadID {
            let summary = threads.first(where: { $0.id == threadID })
                ?? pendingThreadSummary(id: threadID, text: text, attachments: attachments, cwd: selectedProject?.path)
            selectedThreadID = threadID
            selectedThread = ThreadDetail(id: threadID, summary: summary, turns: [])
        }

        if var detail = selectedThread {
            detail.turns.append(turn)
            selectedThread = detail
        }
        return (turnID, userItem)
    }

    private func replacePendingTurn(_ pendingTurnID: String, with turn: CodexTurn, threadID: String, fallbackUserItem: TranscriptItem) {
        guard selectedThreadID == threadID else {
            appendOrReplaceTurn(turn, threadID: threadID)
            return
        }
        if selectedThread == nil, let summary = threads.first(where: { $0.id == threadID }) {
            selectedThread = ThreadDetail(id: threadID, summary: summary, turns: [])
        }

        guard var detail = selectedThread else { return }
        var mergedTurn = turn
        detail.turns.removeAll { $0.id == pendingTurnID }
        if let index = detail.turns.firstIndex(where: { $0.id == turn.id }) {
            mergedTurn.items = mergedTranscriptItems(existing: detail.turns[index].items, incoming: turn.items)
            if !mergedTurn.items.contains(where: { $0.kind == .user }) {
                mergedTurn.items.insert(fallbackUserItem, at: 0)
            }
            detail.turns[index] = mergedTurn
        } else {
            if !mergedTurn.items.contains(where: { $0.kind == .user }) {
                mergedTurn.items.insert(fallbackUserItem, at: 0)
            }
            detail.turns.append(mergedTurn)
        }
        selectedThread = detail
    }

    private func mergedTranscriptItems(existing: [TranscriptItem], incoming: [TranscriptItem]) -> [TranscriptItem] {
        var items = existing
        for item in incoming {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item
            } else {
                items.append(item)
            }
        }
        return items
    }

    private func promotePendingThread(_ pendingThreadID: String, to thread: ThreadSummary) {
        threads.removeAll { $0.id == pendingThreadID }
        upsertThread(thread)
        deriveProjects()
        guard selectedThreadID == pendingThreadID else { return }
        let turns = selectedThread?.turns ?? []
        selectedThreadID = thread.id
        selectedThread = ThreadDetail(id: thread.id, summary: thread, turns: turns)
    }

    private func upsertItem(threadID: String, turnID: String, item: TranscriptItem) {
        guard selectedThreadID == threadID else { return }
        if selectedThread == nil, let summary = threads.first(where: { $0.id == threadID }) {
            selectedThread = ThreadDetail(id: threadID, summary: summary, turns: [])
        }

        guard var detail = selectedThread else { return }
        if let turnIndex = detail.turns.firstIndex(where: { $0.id == turnID }) {
            if let itemIndex = detail.turns[turnIndex].items.firstIndex(where: { $0.id == item.id }) {
                detail.turns[turnIndex].items[itemIndex] = item
            } else {
                detail.turns[turnIndex].items.append(item)
            }
        } else {
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
            var mergedTurn = turn
            if mergedTurn.items.isEmpty {
                mergedTurn.items = detail.turns[index].items
            }
            detail.turns[index] = mergedTurn
        } else {
            detail.turns.append(turn)
        }
        selectedThread = detail
    }

    private func upsertThread(_ thread: ThreadSummary) {
        if thread.isArchived {
            threads.removeAll { $0.id == thread.id }
            deriveProjects()
            return
        }

        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.insert(thread, at: 0)
        }
        threads.sort(by: sortThreadsByRecentActivity)
    }

    private func pendingThreadSummary(id: String, text: String, attachments: [URL], cwd: String?) -> ThreadSummary {
        let body = pendingUserBody(text: text, attachments: attachments)
        let title = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let now = Date()
        return ThreadSummary(
            id: id,
            title: title.isEmpty ? "Yeni sohbet" : title,
            preview: body,
            cwd: cwd ?? FileManager.default.homeDirectoryForCurrentUser.path,
            modelProvider: "openai",
            status: "pending",
            createdAt: now,
            updatedAt: now
        )
    }

    private func pendingUserBody(text: String, attachments: [URL]) -> String {
        var lines: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append(trimmed)
        }
        lines.append(contentsOf: attachments.map { "[Gorsel] \($0.path)" })
        return lines.joined(separator: "\n")
    }

    private func deriveProjects() {
        let grouped = Dictionary(grouping: threads.filter { !$0.isArchived }, by: \.cwd)
        var merged = Dictionary(uniqueKeysWithValues: bookmarkedProjects.map { ($0.path, $0) })
        for (path, threads) in grouped {
            merged[path] = Project(path: path, threadCount: threads.count)
        }

        let alphabeticProjects = merged.values
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let ranks = Dictionary(uniqueKeysWithValues: projectOrder.enumerated().map { ($0.element, $0.offset) })
        projects = alphabeticProjects.sorted { lhs, rhs in
            switch (ranks[lhs.id], ranks[rhs.id]) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
        projectOrder = projects.map(\.id)
        saveProjectOrder()

        if !hasStoredExpandedProjects {
            expandedProjectIDs = Set(projects.prefix(3).map(\.id))
            saveExpandedProjects()
        }
    }

    private func requireClient() throws -> CodexClient {
        guard let client else { throw CodexClientError.missingBinary }
        return client
    }

    private func ensureCanStartTurns() -> Bool {
        guard authStatus.canStartTurns else {
            if case .signedOut = authStatus {
                presentedError = PresentedError(message: "Codex hesabi bagli degil. Once giris yap.")
            } else {
                presentedError = PresentedError(message: "Codex auth henuz dogrulanmadi. Hesap durumunu tekrar dene.")
            }
            return false
        }
        return true
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
