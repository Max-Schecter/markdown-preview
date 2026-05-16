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
        state = .empty
    }
}

struct MarkdownDocument: Equatable, Identifiable {
    let id = UUID()
    let url: URL
    let markdown: String

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
