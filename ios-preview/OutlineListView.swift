//
//  OutlineListView.swift
//  Markdown Preview iOS
//

import SwiftUI

struct OutlineListView: View {
    let items: [TOCItem]
    let onSelect: (TOCItem) -> Void

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView("No Headings", systemImage: "list.bullet.indent")
        } else {
            List {
                Section("Contents") {
                    ForEach(items) { item in
                        OutlineRow(item: item, onSelect: onSelect)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct OutlineRow: View {
    let item: TOCItem
    let onSelect: (TOCItem) -> Void

    var body: some View {
        if item.children.isEmpty {
            Button {
                onSelect(item)
            } label: {
                Label(item.title, systemImage: "textformat")
            }
        } else {
            DisclosureGroup {
                ForEach(item.children) { child in
                    OutlineRow(item: child, onSelect: onSelect)
                }
            } label: {
                Button {
                    onSelect(item)
                } label: {
                    Label(item.title, systemImage: "textformat")
                }
            }
        }
    }
}
