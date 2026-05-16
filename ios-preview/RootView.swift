//
//  RootView.swift
//  Markdown Preview iOS
//

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var documentStore: DocumentStore
    @StateObject private var webViewModel = MarkdownWebViewModel()
    @State private var isImporterPresented = false
    @State private var inspectorDocument: MarkdownDocument?

    var body: some View {
        content
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: UTType.markdownPreviewMarkdownTypes
        ) { result in
            switch result {
            case .success(let url):
                documentStore.open(url)
            case .failure(let error):
                documentStore.clear()
                webViewModel.report(error.localizedDescription)
            }
        }
        .onOpenURL { url in
            documentStore.open(url)
        }
        .sheet(item: $inspectorDocument) { document in
            NavigationStack {
                InspectorView(metadata: document.metadata)
                    .navigationTitle("Inspector")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                inspectorDocument = nil
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var content: some View {
        if horizontalSizeClass == .compact || !documentStore.state.isLoaded {
            NavigationStack {
                detail
            }
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
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
    private var detail: some View {
        switch documentStore.state {
        case .empty:
            WelcomeView(openAction: { isImporterPresented = true })
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
                    isImporterPresented = true
                }
            }
        case .loaded(let document):
            MarkdownDocumentView(
                document: document,
                webViewModel: webViewModel,
                openDocument: { isImporterPresented = true },
                showInspector: { inspectorDocument = document }
            )
        }
    }
}
