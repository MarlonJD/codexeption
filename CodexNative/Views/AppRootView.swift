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
                .background(GlassPaneBackground(material: .regularMaterial))

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

            GlassDivider(.vertical)

            VStack(spacing: 0) {
                ThreadHeaderView()
                GlassDivider(.horizontal)
                TranscriptView()
                GlassDivider(.horizontal)
                ComposerView()
            }
            .frame(minWidth: 520)
            .background(GlassPaneBackground(material: .ultraThinMaterial, tintOpacity: 0.1))

            if store.isInspectorVisible {
                GlassDivider(.vertical)
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
        .background(GlassPaneBackground(material: .regularMaterial, tintOpacity: 0.08))
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

            if store.isLoading || store.isSelectedThreadLoading {
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
        .background(GlassPaneBackground(material: .bar, tintOpacity: 0.06))
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
        .glassCapsule(material: .thinMaterial, fallback: Color(nsColor: .controlBackgroundColor), shadowOpacity: 0.02)
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

struct GlassPaneBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let material: Material
    let fallback: Color
    let tintOpacity: Double

    init(
        material: Material = .regularMaterial,
        fallback: Color = Color(nsColor: .windowBackgroundColor),
        tintOpacity: Double = 0.16
    ) {
        self.material = material
        self.fallback = fallback
        self.tintOpacity = tintOpacity
    }

    var body: some View {
        ZStack {
            fallback.opacity(reduceTransparency ? 1 : fallbackOpacity)

            if !reduceTransparency {
                Rectangle()
                    .fill(material)
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.015 : tintOpacity))
            }
        }
    }

    private var fallbackOpacity: Double {
        colorScheme == .dark ? 0.66 : 0.42
    }
}

struct GlassDivider: View {
    enum Orientation {
        case horizontal
        case vertical
    }

    @Environment(\.colorScheme) private var colorScheme
    let orientation: Orientation

    init(_ orientation: Orientation) {
        self.orientation = orientation
    }

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .frame(
                width: orientation == .vertical ? 1 : nil,
                height: orientation == .horizontal ? 1 : nil
            )
    }
}

struct GlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let material: Material
    let fallback: Color
    let strokeOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let tintOpacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fallback.opacity(reduceTransparency ? 1 : fallbackOpacity))

                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(material)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.02 : tintOpacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 0.7)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.24), lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
    }

    private var fallbackOpacity: Double {
        colorScheme == .dark ? 0.62 : 0.36
    }
}

struct GlassCapsuleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let material: Material
    let fallback: Color
    let strokeOpacity: Double
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                Capsule()
                    .fill(fallback.opacity(reduceTransparency ? 1 : fallbackOpacity))

                if !reduceTransparency {
                    Capsule()
                        .fill(material)
                    Capsule()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.02 : 0.14))
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 8, x: 0, y: 3)
    }

    private var fallbackOpacity: Double {
        colorScheme == .dark ? 0.62 : 0.36
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat = 12,
        material: Material = .regularMaterial,
        fallback: Color = Color(nsColor: .controlBackgroundColor),
        strokeOpacity: Double = 0.08,
        shadowOpacity: Double = 0.06,
        shadowRadius: CGFloat = 16,
        shadowY: CGFloat = 6,
        tintOpacity: Double = 0.12
    ) -> some View {
        modifier(
            GlassSurfaceModifier(
                cornerRadius: cornerRadius,
                material: material,
                fallback: fallback,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY,
                tintOpacity: tintOpacity
            )
        )
    }

    func glassCapsule(
        material: Material = .thinMaterial,
        fallback: Color = Color(nsColor: .controlBackgroundColor),
        strokeOpacity: Double = 0.08,
        shadowOpacity: Double = 0.04
    ) -> some View {
        modifier(
            GlassCapsuleModifier(
                material: material,
                fallback: fallback,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity
            )
        )
    }
}
