//
//  RecentDocumentsView.swift
//  Markdown Preview iOS
//

import SwiftUI

struct RecentDocumentsView: View {
    @EnvironmentObject private var documentStore: DocumentStore
    let didOpenDocument: () -> Void

    @State private var searchText = ""
    @State private var isShowingOpenError = false
    @State private var openErrorMessage = ""

    private var filteredDocuments: [RecentDocument] {
        documentStore.recentDocuments.filter { $0.matches(searchText) }
    }

    var body: some View {
        Group {
            if documentStore.recentDocuments.isEmpty {
                ContentUnavailableView(
                    "No Recent Documents",
                    systemImage: "clock",
                    description: Text("Documents you open will appear here.")
                )
            } else if filteredDocuments.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(filteredDocuments) { document in
                        Button {
                            if documentStore.open(document) {
                                didOpenDocument()
                            } else if case .failed(let message) = documentStore.state {
                                openErrorMessage = message
                                isShowingOpenError = true
                            }
                        } label: {
                            RecentDocumentRow(document: document)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                documentStore.removeRecentDocument(document)
                            }
                        }
                        .contextMenu {
                            Button("Remove from Recents", systemImage: "trash", role: .destructive) {
                                documentStore.removeRecentDocument(document)
                            }
                        }
                        .accessibilityIdentifier("recent-document-\(document.id.uuidString)")
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Recent Documents")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Recents"
        )
        .alert("Unable to Open Document", isPresented: $isShowingOpenError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openErrorMessage)
        }
    }
}

private struct RecentDocumentRow: View {
    let document: RecentDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(document.location)
                    Text("•")
                    Text(document.lastOpenedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this document")
    }
}
