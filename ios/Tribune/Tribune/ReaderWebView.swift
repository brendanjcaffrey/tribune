import SwiftUI
import WebKit

struct ReaderWebView: UIViewRepresentable {
    let newsletter: Newsletter
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

        let url = URL(string: "tribune://host/index.html")!
        webView.load(URLRequest(url: url))
        webView.navigationDelegate = context.coordinator
        context.coordinator.epubId = newsletter.id
        context.coordinator.webView = webView

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var epubId: Int?
        weak var webView: WKWebView?

        // Called when JS posts events
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            //if message.name == "readerEvent" {
                print("Swift got event: \(message.body)")
            //}
        }

        // Once the HTML is loaded, inject the file path
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let id = epubId {
                let js = "openBook('/\(id)')"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }
}
