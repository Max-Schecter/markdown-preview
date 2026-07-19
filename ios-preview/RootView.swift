//
//  RootView.swift
//  Markdown Preview iOS
//

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    private static let collapsedRecentsDetent = PresentationDetent.height(92)

    private enum Route: Hashable {
        case document(URL)
    }

    private enum PresentedSheet: Identifiable {
        case recents
        case inspector(MarkdownDocument)

        var id: String {
            switch self {
            case .recents: "recents"
            case .inspector: "inspector"
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var documentStore: DocumentStore
    @StateObject private var webViewModel = MarkdownWebViewModel()
    @State private var isRecentsImporterPresented = false
    @State private var isDocumentImporterPresented = false
    @State private var presentedSheet: PresentedSheet? = .recents
    @State private var selectedRecentsDetent = collapsedRecentsDetent
    @State private var navigationPath: [Route] = []

    var body: some View {
        content
        .fileImporter(
            isPresented: $isDocumentImporterPresented,
            allowedContentTypes: UTType.markdownPreviewMarkdownTypes,
            onCompletion: handleDocumentImport
        )
        .onOpenURL { url in
            if documentStore.open(url) {
                dismissRecentsSheet()
            }
        }
        .onChange(of: documentStore.state.isLoaded) { _, isLoaded in
            if isLoaded, case .loaded(let document) = documentStore.state {
                navigationPath = [.document(document.url)]
                dismissRecentsSheet()
            } else if case .empty = documentStore.state {
                navigationPath.removeAll()
                presentRecentsSheetIfNeeded()
            }
        }
        .onChange(of: navigationPath) { _, path in
            guard path.isEmpty, documentStore.state.isLoaded else { return }
            documentStore.clear()
            webViewModel.clearError()
        }
        .sheet(item: $presentedSheet, onDismiss: restoreRecentsSheetIfNeeded) { sheet in
            switch sheet {
            case .recents:
                NavigationStack {
                    RecentDocumentsView(
                        didOpenDocument: dismissRecentsSheet
                    )
                }
                .presentationDetents(
                    [Self.collapsedRecentsDetent, .medium, .large],
                    selection: $selectedRecentsDetent
                )
                .presentationBackgroundInteraction(
                    .enabled(upThrough: Self.collapsedRecentsDetent)
                )
                .presentationContentInteraction(.resizes)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .fileImporter(
                    isPresented: $isRecentsImporterPresented,
                    allowedContentTypes: UTType.markdownPreviewMarkdownTypes,
                    onCompletion: handleDocumentImport
                )
            case .inspector(let document):
                NavigationStack {
                    InspectorView(metadata: document.metadata)
                        .navigationTitle("Inspector")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    presentedSheet = nil
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if horizontalSizeClass == .compact {
            NavigationStack(path: $navigationPath) {
                navigationRoot
            }
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                NavigationStack(path: $navigationPath) {
                    navigationRoot
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    private var navigationRoot: some View {
        rootDetail
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .document(let url):
                    documentDestination(url: url)
                }
            }
    }

    @ViewBuilder
    private var sidebar: some View {
        switch documentStore.state {
        case .loaded(let document):
            OutlineListView(items: document.outline) { heading in
                webViewModel.scrollToHeading(index: heading.id)
            }
            .navigationTitle(document.title)
        case .loading:
            ProgressView()
                .navigationTitle("Markdown Preview")
        default:
            ContentUnavailableView("No Document", systemImage: "doc.text.magnifyingglass")
                .navigationTitle("Markdown Preview")
        }
    }

    @ViewBuilder
    private var rootDetail: some View {
        switch documentStore.state {
        case .empty:
            WelcomeView(openAction: presentDocumentImporter)
        case .loading:
            ProgressView("Opening Document")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Unable to Open Document", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Open Another Document") {
                    presentDocumentImporter()
                }
            }
        case .loaded(let document):
            ProgressView("Opening \(document.title)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func documentDestination(url: URL) -> some View {
        if case .loaded(let document) = documentStore.state, document.url == url {
            MarkdownDocumentView(
                document: document,
                webViewModel: webViewModel,
                openDocument: presentDocumentImporter,
                showInspector: { presentedSheet = .inspector(document) }
            )
        } else {
            ProgressView("Opening Document")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func presentDocumentImporter() {
        if case .recents = presentedSheet {
            isRecentsImporterPresented = true
        } else {
            isDocumentImporterPresented = true
        }
    }

    private func handleDocumentImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            if documentStore.open(url) {
                dismissRecentsSheet()
            }
        case .failure(let error):
            documentStore.clear()
            webViewModel.report(error.localizedDescription)
        }
    }

    private func dismissRecentsSheet() {
        guard case .recents = presentedSheet else { return }
        presentedSheet = nil
    }

    private func presentRecentsSheetIfNeeded() {
        guard presentedSheet == nil else { return }
        selectedRecentsDetent = Self.collapsedRecentsDetent
        presentedSheet = .recents
    }

    private func restoreRecentsSheetIfNeeded() {
        guard !documentStore.state.isLoaded else { return }
        Task { @MainActor in
            await Task.yield()
            presentRecentsSheetIfNeeded()
        }
    }
}
