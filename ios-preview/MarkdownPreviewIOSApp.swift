//
//  MarkdownPreviewIOSApp.swift
//  Markdown Preview iOS
//

import SwiftUI

@main
struct MarkdownPreviewIOSApp: App {
    @StateObject private var documentStore = DocumentStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(documentStore)
        }
    }
}
