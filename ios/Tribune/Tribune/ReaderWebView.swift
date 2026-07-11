import SwiftUI
import WebKit

struct ReaderWebView: UIViewRepresentable {
    let newsletter: Newsletter
    let library: Library
    let coordinator = Coordinator()

    func makeCoordinator() -> Coordinator {
        return coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(coordinator, name: "readerEvent")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.setURLSchemeHandler(TribuneSchemeHandler(), forURLScheme: "tribune")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isInspectable = true

        // draw a themed backing instead of the default white. an opaque webview
        // flashes white while document.write() rewrites the reader document,
        // before any of our css exists to cover it. systembackground adapts to
        // light/dark, so the gap shows black in dark mode instead of white.
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground

        let url = URL(string: "tribune://host/index.html")!
        webView.load(URLRequest(url: url))
        webView.navigationDelegate = context.coordinator
        context.coordinator.newsletter = newsletter
        context.coordinator.library = library
        context.coordinator.webView = webView

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var newsletter: Newsletter?
        var library: Library?
        weak var webView: WKWebView?

        // Called when JS posts events
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let n = newsletter, let l = library else { return }
            if message.name == "readerEvent", let obj = message.body as? NSDictionary, let type = obj["type"] as? String {
                if type == "progress", let cfi = obj["cfi"] as? String {
                    Task { try? await l.updateNewsletterProgress(n, progress: cfi) }
                } else if type == "at end" && !n.read {
                    Task { try? await l.markNewsletterRead(n) }
                } else if type == "footnote", let href = obj["href"] as? String {
                    webView?.evaluateJavaScript("scrollToHref('\(href)')", completionHandler: nil)
                } else if type == "external link", let href = obj["href"] as? String, let url = URL(string: href) {
                    UIApplication.shared.open(url)
                }
            }
        }

        // Once the HTML is loaded, inject the file path
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let newsletter = newsletter {
                let js = "openBook('/\(newsletter.id)', '\(newsletter.progress)')"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }
}
