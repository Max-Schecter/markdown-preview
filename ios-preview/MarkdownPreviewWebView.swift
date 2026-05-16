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
    @ObservedObject var model: MarkdownWebViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator.assetScheme, forURLScheme: MarkdownAssetScheme.scheme)
        config.userContentController.add(context.coordinator, name: Coordinator.messageName)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.backgroundColor = .systemBackground
        webView.isOpaque = false
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
        weak var webView: WKWebView?

        private var currentMarkdown: String?
        private var currentAssetBaseURL: URL?
        private var renderGeneration: UInt64 = 0

        init(model: MarkdownWebViewModel) {
            self.model = model
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
            guard message.name == Self.messageName else { return }
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
