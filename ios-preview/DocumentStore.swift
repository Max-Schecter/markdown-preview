//
//  DocumentStore.swift
//  Markdown Preview iOS
//

import Foundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    enum LoadState: Equatable {
        case empty
        case loading
        case loaded(MarkdownDocument)
        case failed(String)

        var isLoaded: Bool {
            if case .loaded = self {
                return true
            }
            return false
        }
    }

    @Published private(set) var state: LoadState = .empty

    private var securityScopedURL: URL?
    private var renderedEditHistory = RenderedEditHistory()

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    func open(_ url: URL) {
        state = .loading

        if securityScopedURL != url {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        if didStartAccess {
            securityScopedURL = url
        }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            renderedEditHistory.clear()
            state = .loaded(MarkdownDocument(url: url, markdown: text))
        } catch {
            if didStartAccess {
                securityScopedURL?.stopAccessingSecurityScopedResource()
                securityScopedURL = nil
            }
            state = .failed(error.localizedDescription)
        }
    }

    func clear() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        renderedEditHistory.clear()
        state = .empty
    }

    func save(markdown: String,
              actionName: String = "Edit Markdown") throws {
        guard case .loaded(let document) = state else { return }
        guard markdown != document.markdown else { return }
        let previousMarkdown = document.markdown
        try markdown.write(to: document.url, atomically: true, encoding: .utf8)
        renderedEditHistory.record(before: previousMarkdown, after: markdown, actionName: actionName)
        state = .loaded(MarkdownDocument(url: document.url, markdown: markdown))
    }

    func undoRenderedEdit() throws {
        let historyBeforeUndo = renderedEditHistory
        guard let edit = renderedEditHistory.undo() else { return }
        do {
            try applyHistoryState(edit.before)
        } catch {
            renderedEditHistory = historyBeforeUndo
            throw error
        }
    }

    func redoRenderedEdit() throws {
        let historyBeforeRedo = renderedEditHistory
        guard let edit = renderedEditHistory.redo() else { return }
        do {
            try applyHistoryState(edit.after)
        } catch {
            renderedEditHistory = historyBeforeRedo
            throw error
        }
    }

    private func applyHistoryState(_ markdown: String) throws {
        guard case .loaded(let document) = state else { return }
        try markdown.write(to: document.url, atomically: true, encoding: .utf8)
        state = .loaded(MarkdownDocument(url: document.url, markdown: markdown))
    }
}

struct MarkdownDocument: Equatable, Identifiable {
    let url: URL
    let markdown: String

    var id: URL { url }
    var title: String { url.lastPathComponent }
    var assetBaseURL: URL { url.deletingLastPathComponent() }
    var metadata: DocumentMetadata {
        DocumentMetadata.make(url: url, markdown: markdown)
    }
    var outline: [TOCItem] {
        MarkdownTOC.parse(markdown)
    }
}

extension UTType {
    static let markdownPreviewMarkdownTypes: [UTType] = [
        UTType("net.daringfireball.markdown"),
        UTType("public.markdown"),
        UTType("net.ia.markdown"),
        UTType("com.unknown.md"),
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
        UTType(filenameExtension: "mdown"),
        UTType(filenameExtension: "mkd"),
        UTType(filenameExtension: "mkdn"),
        UTType(filenameExtension: "mdwn"),
        UTType(filenameExtension: "mdtxt"),
        UTType(filenameExtension: "mdtext"),
        .plainText
    ].compactMap { $0 }
}
