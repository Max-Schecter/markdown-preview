//
//  MarkdownDocumentView.swift
//  Markdown Preview iOS
//

import SwiftUI

struct MarkdownDocumentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var documentStore: DocumentStore

    let document: MarkdownDocument
    @ObservedObject var webViewModel: MarkdownWebViewModel
    let openDocument: () -> Void
    let showInspector: () -> Void

    var body: some View {
        MarkdownPreviewWebView(
            markdown: document.markdown,
            assetBaseURL: document.assetBaseURL,
            onMarkdownChange: saveMarkdown,
            onUndoCommand: undoMarkdown,
            onRedoCommand: redoMarkdown,
            model: webViewModel
        )
        .documentTopChromeTransition()
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if horizontalSizeClass == .compact {
                    compactActions
                } else {
                    regularActions
                }
            }
        }
        .task(id: document.id) {
            webViewModel.clearError()
        }
    }

    private func saveMarkdown(_ markdown: String, actionName: String) -> Bool {
        do {
            try documentStore.save(markdown: markdown,
                                   actionName: actionName)
            return true
        } catch {
            webViewModel.report(error.localizedDescription)
            return false
        }
    }

    private func undoMarkdown() {
        do {
            try documentStore.undoRenderedEdit()
        } catch {
            webViewModel.report(error.localizedDescription)
        }
    }

    private func redoMarkdown() {
        do {
            try documentStore.redoRenderedEdit()
        } catch {
            webViewModel.report(error.localizedDescription)
        }
    }

    private var compactActions: some View {
        Menu {
            ShareLink(item: document.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button(action: showInspector) {
                Label("Inspector", systemImage: "info.circle")
            }

            Button(action: openDocument) {
                Label("Open Document", systemImage: "folder")
            }
        } label: {
            Label("Document Actions", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("document-actions")
    }

    private var regularActions: some View {
        HStack(spacing: 18) {
            ShareLink(item: document.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
            .accessibilityIdentifier("share-document")

            Button(action: showInspector) {
                Label("Inspector", systemImage: "info.circle")
            }
            .accessibilityLabel("Inspector")
            .accessibilityIdentifier("show-inspector")

            Button(action: openDocument) {
                Label("Open", systemImage: "folder")
            }
            .accessibilityLabel("Open Document")
            .accessibilityIdentifier("open-document")
        }
    }
}

private extension View {
    @ViewBuilder
    func documentTopChromeTransition() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
