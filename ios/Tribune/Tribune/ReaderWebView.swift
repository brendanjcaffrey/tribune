import SwiftUI
import WebKit

struct ReaderWebView: UIViewRepresentable {
    let newsletter: Newsletter
    let library: Library
    let dismiss: () -> Void
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
        webView.isInspectable = true
        webView.scrollView.isScrollEnabled = false

        let url = URL(string: "tribune://host/index.html")!
        webView.load(URLRequest(url: url))
        webView.navigationDelegate = context.coordinator
        context.coordinator.newsletter = newsletter
        context.coordinator.library = library
        context.coordinator.dismiss = dismiss
        context.coordinator.webView = webView

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var newsletter: Newsletter?
        var library: Library?
        var dismiss: () -> Void = { }
        weak var webView: WKWebView?

        // Called when JS posts events
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let n = newsletter, let l = library else { return }
            if message.name == "readerEvent", let obj = message.body as? NSDictionary, let type = obj["type"] as? String {
                if type == "dismiss" {
                    dismiss()
                } else if type == "progress", let cfi = obj["cfi"] as? String {
                    Task { try? await l.updateNewsletterProgress(n, progress: cfi) }
                } else if type == "at end" && !n.read {
                    Task { try? await l.markNewsletterRead(n) }
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
