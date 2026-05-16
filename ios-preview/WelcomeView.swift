//
//  WelcomeView.swift
//  Markdown Preview iOS
//

import SwiftUI

struct WelcomeView: View {
    let openAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Markdown Preview")
                    .font(.title2.weight(.semibold))
                Text("Open a Markdown document from Files.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: openAction) {
                Label("Open Document", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
