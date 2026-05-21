import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Button {
                    store.createNewThread()
                } label: {
                    Label("Yeni sohbet", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Arama", text: $store.searchTerm)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            store.reload()
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Button {
                } label: {
                    Label("Eklentiler", systemImage: "puzzlepiece.extension")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(true)
            }
            .padding(14)

            Divider()

            List {
                Section("Projeler") {
                    ForEach(store.projects) { project in
                        ProjectRow(project: project)
                            .listRowBackground(store.selectedProjectID == project.id ? Color.accentColor.opacity(0.14) : Color.clear)
                            .onTapGesture {
                                store.selectProject(project.id)
                            }
                    }
                }

                Section("Sohbetler") {
                    ForEach(store.threads) { thread in
                        ThreadRow(thread: thread)
                            .listRowBackground(store.selectedThreadID == thread.id ? Color.accentColor.opacity(0.14) : Color.clear)
                            .onTapGesture {
                                store.selectThread(thread.id)
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            SettingsStrip()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .lineLimit(1)
                Text("\(project.threadCount) sohbet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(thread.title)
                    .lineLimit(1)
            }
            Text(thread.updatedAt.shortCodexString)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch thread.status {
        case "running":
            .accentColor
        case "failed":
            .red
        default:
            .secondary
        }
    }
}

struct SettingsStrip: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ayarlar", systemImage: "gearshape")
                .font(.headline)

            Picker("Model", selection: Binding(
                get: { store.selectedModelID ?? "" },
                set: { store.selectedModelID = $0.isEmpty ? nil : $0 }
            )) {
                ForEach(store.models) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .labelsHidden()

            Picker("Effort", selection: $store.selectedReasoningEffort) {
                ForEach(store.currentReasoningEfforts, id: \.self) { effort in
                    Text(effort).tag(effort)
                }
            }
            .pickerStyle(.segmented)

            Picker("Approval", selection: $store.approvalPolicy) {
                Text("on-request").tag("on-request")
                Text("untrusted").tag("untrusted")
                Text("never").tag("never")
            }
            .labelsHidden()
        }
        .padding(14)
    }
}
