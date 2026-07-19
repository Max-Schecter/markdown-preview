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
    @Published private(set) var recentDocuments: [RecentDocument]

    private var securityScopedURL: URL?
    private var renderedEditHistory = RenderedEditHistory()

    init() {
        recentDocuments = Self.loadRecentDocuments()
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        open(url, replacingRecentDocumentID: nil)
    }

    private func open(_ url: URL, replacingRecentDocumentID: UUID?) -> Bool {
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
            recordRecentDocument(url, replacingRecentDocumentID: replacingRecentDocumentID)
            return true
        } catch {
            if didStartAccess {
                securityScopedURL?.stopAccessingSecurityScopedResource()
                securityScopedURL = nil
            }
            state = .failed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func open(_ recentDocument: RecentDocument) -> Bool {
        do {
            var bookmarkIsStale = false
            let url = try URL(
                resolvingBookmarkData: recentDocument.bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &bookmarkIsStale
            )
            return open(url, replacingRecentDocumentID: recentDocument.id)
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    func removeRecentDocument(_ recentDocument: RecentDocument) {
        recentDocuments.removeAll { $0.id == recentDocument.id }
        persistRecentDocuments()
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

    private func recordRecentDocument(_ url: URL, replacingRecentDocumentID: UUID?) {
        guard let bookmarkData = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: [.nameKey],
            relativeTo: nil
        ) else { return }

        let standardizedPath = url.standardizedFileURL.path
        let existingID = replacingRecentDocumentID ??
            recentDocuments.first { $0.path == standardizedPath }?.id
        recentDocuments.removeAll {
            $0.path == standardizedPath || $0.id == replacingRecentDocumentID
        }
        recentDocuments.insert(
            RecentDocument(
                id: existingID ?? UUID(),
                name: url.lastPathComponent,
                path: standardizedPath,
                lastOpenedAt: Date(),
                bookmarkData: bookmarkData
            ),
            at: 0
        )
        if recentDocuments.count > Self.maximumRecentDocumentCount {
            recentDocuments.removeLast(recentDocuments.count - Self.maximumRecentDocumentCount)
        }
        persistRecentDocuments()
    }

    private static let maximumRecentDocumentCount = 500

    private static var recentDocumentsFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Markdown Preview", isDirectory: true)
            .appendingPathComponent("RecentDocuments.json", isDirectory: false)
    }

    private static func loadRecentDocuments() -> [RecentDocument] {
        guard let fileURL = recentDocumentsFileURL,
              let data = try? Data(contentsOf: fileURL),
              let documents = try? JSONDecoder().decode([RecentDocument].self, from: data)
        else { return [] }

        return Array(
            documents
                .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
                .prefix(maximumRecentDocumentCount)
        )
    }

    private func persistRecentDocuments() {
        guard let fileURL = Self.recentDocumentsFileURL,
              let data = try? JSONEncoder().encode(recentDocuments)
        else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Recents are a convenience. A persistence failure must not block opening a file.
        }
    }
}

struct RecentDocument: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let path: String
    let lastOpenedAt: Date
    let bookmarkData: Data

    var location: String {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        return parent.lastPathComponent.isEmpty ? parent.path : parent.lastPathComponent
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty ||
            name.localizedCaseInsensitiveContains(query) ||
            path.localizedCaseInsensitiveContains(query)
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
