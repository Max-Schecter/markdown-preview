//
//  MarkdownPreviewWebView.swift
//  Markdown Preview iOS
//

import Combine
import SwiftUI
import UIKit
import WebKit
import os

@MainActor
final class MarkdownWebViewModel: ObservableObject {
    @Published private(set) var errorMessage: String?

    fileprivate weak var webView: WKWebView?
    private var pendingHeadingIndex: Int?

    func scrollToHeading(index: Int) {
        guard let webView else {
            pendingHeadingIndex = index
            return
        }

        let script = """
        (() => {
            const el = document.getElementById('md-heading-\(index)');
            if (!el) return false;
            el.scrollIntoView({ behavior: 'smooth', block: 'start' });
            return true;
        })();
        """
        webView.evaluateJavaScript(script) { _, _ in }
    }

    fileprivate func bind(_ webView: WKWebView) {
        self.webView = webView
        if let pendingHeadingIndex {
            self.pendingHeadingIndex = nil
            scrollToHeading(index: pendingHeadingIndex)
        }
    }

    func report(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }
}

struct MarkdownPreviewWebView: UIViewRepresentable {
    let markdown: String
    let assetBaseURL: URL
    let onMarkdownChange: (String) -> Void
    @ObservedObject var model: MarkdownWebViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, onMarkdownChange: onMarkdownChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator.assetScheme, forURLScheme: MarkdownAssetScheme.scheme)
        config.userContentController.add(context.coordinator, name: Coordinator.messageName)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.backgroundColor = .systemBackground
        webView.isOpaque = false
        if #available(iOS 26.0, *) {
            webView.scrollView.topEdgeEffect.style = .soft
        }
        let tableEditMenuInteraction = UIEditMenuInteraction(delegate: context.coordinator)
        webView.addInteraction(tableEditMenuInteraction)
        context.coordinator.tableEditMenuInteraction = tableEditMenuInteraction
        context.coordinator.webView = webView
        model.bind(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.display(markdown: markdown, assetBaseURL: assetBaseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageName = "mdPreviewHost"

        let assetScheme = MarkdownAssetScheme()
        private weak var model: MarkdownWebViewModel?
        private let onMarkdownChange: (String) -> Void
        weak var webView: WKWebView?

        private var currentMarkdown: String?
        private var currentAssetBaseURL: URL?
        private var tableMenuContext: TableMenuContext?
        fileprivate weak var tableEditMenuInteraction: UIEditMenuInteraction?
        private var renderGeneration: UInt64 = 0

        private struct TableMenuContext {
            let tableIndex: Int
            let rowIndex: Int
            let columnIndex: Int
            let clientX: CGFloat
            let clientY: CGFloat
        }

        init(model: MarkdownWebViewModel, onMarkdownChange: @escaping (String) -> Void) {
            self.model = model
            self.onMarkdownChange = onMarkdownChange
            super.init()
        }

        func display(markdown: String, assetBaseURL: URL) {
            guard markdown != currentMarkdown || assetBaseURL != currentAssetBaseURL else { return }
            currentMarkdown = markdown
            currentAssetBaseURL = assetBaseURL
            assetScheme.setBaseURL(assetBaseURL)
            renderGeneration &+= 1
            let generation = renderGeneration

            Task.detached(priority: .userInitiated) {
                let rendered = MarkdownHTML.render(
                    markdown: markdown,
                    allowsScroll: true,
                    assetBaseHref: "\(MarkdownAssetScheme.scheme):///",
                    vendorLoading: .lazy
                )
                await MainActor.run {
                    guard generation == self.renderGeneration else { return }
                    self.webView?.loadHTMLString(rendered.html, baseURL: nil)
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == Self.messageName,
                  let dict = message.body as? [String: Any],
                  let kind = dict["kind"] as? String else { return }

            switch kind {
            case "tableEdit":
                handleTableEditMessage(dict)
            case "tableContextMenu":
                handleTableContextMenuMessage(dict)
            default:
                break
            }
        }

        private func handleTableEditMessage(_ dict: [String: Any]) {
            guard let tableIndex = (dict["tableIndex"] as? NSNumber)?.intValue,
                  let rawRows = dict["rows"] as? [[Any]]
            else { return }

            let rows = rawRows.map { row in
                row.map { cell in
                    if let string = cell as? String { return string }
                    return String(describing: cell)
                }
            }
            let dirtyRows = (dict["dirtyRows"] as? [[Any]])?.map { row in
                row.map { cell in
                    if let bool = cell as? Bool { return bool }
                    if let number = cell as? NSNumber { return number.boolValue }
                    return true
                }
            }

            let snapshot = MarkdownTableEditor.Snapshot(
                tableIndex: tableIndex,
                rows: rows,
                dirtyRows: dirtyRows
            )
            guard let markdown = currentMarkdown,
                  let updated = MarkdownTableEditor.replacingTable(in: markdown, with: snapshot),
                  updated != markdown
            else { return }

            currentMarkdown = updated
            onMarkdownChange(updated)
        }

        private func handleTableContextMenuMessage(_ dict: [String: Any]) {
            guard let tableIndex = (dict["tableIndex"] as? NSNumber)?.intValue,
                  let rowIndex = (dict["rowIndex"] as? NSNumber)?.intValue,
                  let columnIndex = (dict["columnIndex"] as? NSNumber)?.intValue,
                  let clientX = dict["clientX"] as? NSNumber,
                  let clientY = dict["clientY"] as? NSNumber
            else { return }

            tableMenuContext = TableMenuContext(
                tableIndex: tableIndex,
                rowIndex: rowIndex,
                columnIndex: columnIndex,
                clientX: CGFloat(truncating: clientX),
                clientY: CGFloat(truncating: clientY)
            )
            showTableActions()
        }

        private func showTableActions() {
            guard let tableEditMenuInteraction else { return }
            tableEditMenuInteraction.dismissMenu()
            tableEditMenuInteraction.presentEditMenu(
                with: UIEditMenuConfiguration(identifier: nil, sourcePoint: tableMenuSourcePoint())
            )
        }

        private func tableMenuSourcePoint() -> CGPoint {
            guard let webView else { return .zero }
            return CGPoint(
                x: min(max(tableMenuContext?.clientX ?? webView.bounds.midX, 0), webView.bounds.width),
                y: min(max(tableMenuContext?.clientY ?? webView.bounds.midY, 0), webView.bounds.height)
            )
        }

        private func performTableCommand(_ command: String) {
            guard let context = tableMenuContext else { return }
            let script = """
            window.MdPreviewTables && window.MdPreviewTables.perform(
                \(javaScriptStringLiteral(command)),
                \(context.tableIndex),
                \(context.rowIndex),
                \(context.columnIndex)
            );
            """
            webView?.evaluateJavaScript(script) { [weak self] _, error in
                self?.tableMenuContext = nil
                if let error {
                    self?.model?.report(error.localizedDescription)
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if let fragment = sameDocumentFragmentID(from: url) {
                let script = """
                (() => {
                    const el = document.getElementById(\(javaScriptStringLiteral(fragment)));
                    if (!el) return false;
                    el.scrollIntoView({ behavior: 'smooth', block: 'start' });
                    return true;
                })();
                """
                webView.evaluateJavaScript(script) { _, _ in }
            } else if url.scheme == MarkdownAssetScheme.scheme,
                      let base = currentAssetBaseURL,
                      let resolved = MarkdownAssetScheme.resolve(url, against: base) {
                UIApplication.shared.open(resolved)
            } else if url.scheme != MarkdownAssetScheme.scheme {
                UIApplication.shared.open(url)
            }

            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model?.report(error.localizedDescription)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            model?.report(error.localizedDescription)
        }

        private func sameDocumentFragmentID(from url: URL) -> String? {
            guard let fragment = url.fragment?.removingPercentEncoding,
                  !fragment.isEmpty,
                  url.query == nil else { return nil }

            if url.scheme == nil {
                return fragment
            }
            if url.scheme == "about", url.absoluteString.hasPrefix("about:blank#") {
                return fragment
            }
            if url.scheme == MarkdownAssetScheme.scheme,
               (url.host == nil || url.host == ""),
               (url.path.isEmpty || url.path == "/") {
                return fragment
            }
            return nil
        }

        private func javaScriptStringLiteral(_ string: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [string]),
                  let json = String(data: data, encoding: .utf8),
                  json.count >= 2 else { return "\"\"" }
            return String(json.dropFirst().dropLast())
        }
    }
}

extension MarkdownPreviewWebView.Coordinator: UIEditMenuInteractionDelegate {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        UIMenu(children: [
            UIAction(title: "Insert Row Above") { [weak self] _ in
                self?.performTableCommand("insertRowAbove")
            },
            UIAction(title: "Insert Row Below") { [weak self] _ in
                self?.performTableCommand("insertRowBelow")
            },
            UIAction(title: "Delete Row", attributes: .destructive) { [weak self] _ in
                self?.performTableCommand("deleteRow")
            },
            UIAction(title: "Insert Column Before") { [weak self] _ in
                self?.performTableCommand("insertColumnBefore")
            },
            UIAction(title: "Insert Column After") { [weak self] _ in
                self?.performTableCommand("insertColumnAfter")
            },
            UIAction(title: "Delete Column", attributes: .destructive) { [weak self] _ in
                self?.performTableCommand("deleteColumn")
            }
        ])
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             targetRectFor configuration: UIEditMenuConfiguration,
                             defaultTargetRect: CGRect) -> CGRect {
        CGRect(origin: tableMenuSourcePoint(), size: CGSize(width: 1, height: 1))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                             willDismissMenuFor configuration: UIEditMenuConfiguration,
                             animator: UIEditMenuInteractionAnimating) {
        tableMenuContext = nil
    }
}
