import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        VStack(spacing: 0) {
            SidebarTopBar()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    SidebarSection(title: "Projeler") {
                        ProjectFilterRow(
                            title: "Tum projeler",
                            subtitle: "\(store.threads.count) sohbet",
                            systemImage: "tray.full",
                            isSelected: store.selectedProjectID == nil
                        ) {
                            store.selectProject(nil)
                        }

                        ForEach(store.projects) { project in
                            ProjectFilterRow(
                                title: project.displayName,
                                subtitle: "\(project.threadCount) sohbet",
                                systemImage: "folder",
                                isSelected: store.selectedProjectID == project.id
                            ) {
                                store.selectProject(project.id)
                            }
                        }
                    }

                    SidebarSection(title: "Sohbetler") {
                        if store.visibleThreads.isEmpty {
                            SidebarEmptyRow(text: store.searchTerm.isEmpty ? "Sohbet bulunamadi" : "Arama sonucu yok")
                        } else {
                            ForEach(store.visibleThreads) { thread in
                                ThreadRow(thread: thread, isSelected: store.selectedThreadID == thread.id) {
                                    store.selectThread(thread.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }

            SidebarAccountCard()
                .padding(12)
        }
        .background(GlassPaneBackground(material: .regularMaterial, tintOpacity: 0.18))
    }
}

struct SidebarTopBar: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor)
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Codexeption")
                        .font(.headline.weight(.semibold))
                    Text("Native Codex")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button {
                store.createNewThread()
            } label: {
                Label("Yeni sohbet", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Sohbet ara", text: $store.searchTerm)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .glassSurface(
                cornerRadius: 9,
                material: .thinMaterial,
                fallback: Color(nsColor: .controlBackgroundColor),
                strokeOpacity: 0.06,
                shadowOpacity: 0.02,
                shadowRadius: 8,
                shadowY: 3,
                tintOpacity: 0.08
            )

            Button {
            } label: {
                Label("Eklentiler", systemImage: "puzzlepiece.extension")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(true)
        }
        .padding(14)
        .background(GlassPaneBackground(material: .bar, tintOpacity: 0.08))
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            VStack(spacing: 3) {
                content
            }
        }
    }
}

struct ProjectFilterRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 42)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.16), lineWidth: 0.7)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.12) : Color.clear
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)

                    Text(thread.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                if !thread.preview.isEmpty {
                    Text(thread.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(URL(fileURLWithPath: thread.cwd).lastPathComponent)
                        .lineLimit(1)
                    Text(thread.updatedAt.shortCodexString)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.18))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.12) : Color.clear
    }

    private var statusColor: Color {
        switch thread.status {
        case "running":
            .accentColor
        case "failed":
            .red
        default:
            .secondary.opacity(0.55)
        }
    }
}

struct SidebarEmptyRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 34)
    }
}

struct SidebarAccountCard: View {
    @EnvironmentObject private var store: CodexStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.authStatus.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(store.authStatus.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if case .signedOut = store.authStatus {
                Button {
                    store.startChatGPTLogin()
                } label: {
                    Text("Giris yap")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }

            if case .unavailable = store.authStatus {
                Button {
                    store.refreshAuth()
                } label: {
                    Text("Tekrar dene")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .glassSurface(
            cornerRadius: 12,
            material: .thinMaterial,
            fallback: Color(nsColor: .controlBackgroundColor),
            strokeOpacity: 0.07,
            shadowOpacity: 0.04,
            shadowRadius: 12,
            shadowY: 4,
            tintOpacity: 0.1
        )
    }

    private var iconName: String {
        switch store.authStatus {
        case .signedIn:
            "checkmark.circle.fill"
        case .signingIn:
            "clock.fill"
        case .signedOut:
            "exclamationmark.circle.fill"
        case .unknown:
            "circle.dotted"
        case .unavailable:
            "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch store.authStatus {
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
