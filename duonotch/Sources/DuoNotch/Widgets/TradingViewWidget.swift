import SwiftUI
import WebKit

/// TradingView's free embeddable "market quotes" widget, showing live
/// prices for the given TradingView symbols straight from TradingView.
struct TradingViewWidget: NSViewRepresentable {
    let symbols: [(String, String)]   // (TradingView symbol, display name)

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        load(view)
        context.coordinator.lastKey = key
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.lastKey != key {
            context.coordinator.lastKey = key
            load(view)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var key: String { symbols.map { $0.0 }.joined(separator: ",") }

    private func load(_ view: WKWebView) {
        let list = symbols.map { ["name": $0.0, "displayName": $0.1] }
        let config: [String: Any] = [
            "width": "100%", "height": "100%",
            "symbolsGroups": [["name": "Watchlist", "symbols": list]],
            "showSymbolLogo": true, "isTransparent": true,
            "colorTheme": "dark", "locale": "en",
        ]
        let json = (try? JSONSerialization.data(withJSONObject: config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;padding:0;background:transparent;overflow:hidden;height:100%}</style></head>
        <body><div class="tradingview-widget-container" style="height:100%">
        <div class="tradingview-widget-container__widget" style="height:100%"></div>
        <script type="text/javascript" src="https://s3.tradingview.com/external-embedding/embed-widget-market-quotes.js" async>
        \(json)
        </script></div></body></html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://www.tradingview.com/"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastKey = ""

        /// Links clicked inside the widget open in the browser, not in the notch.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
