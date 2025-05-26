//
//  paster_barApp.swift
//  paster_bar
//
//  Created by ph on 2024/12/26.
//

import SwiftUI
import SwiftData

@main
struct paster_barApp: App {
    var clipboardManager: ClipboardManager

    init() {
        clipboardManager = ClipboardManager() // 启动剪切板管理器
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([]) // 如果不需要 Item，保持为空
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
