import SwiftData
import SwiftUI

@main
struct CodexNativeApp: App {
    @StateObject private var store = CodexStore()

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            BookmarkRecord.self,
            AppSettingsRecord.self,
            ThreadCacheRecord.self
        ])
        let configuration = ModelConfiguration("CodexNative", schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("SwiftData container could not be created: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .modelContainer(modelContainer)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni sohbet") {
                    store.createNewThread()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}
