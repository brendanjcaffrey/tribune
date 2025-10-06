import WebKit
import UniformTypeIdentifiers

final class TribuneSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "tribune" else {
            urlSchemeTask.didFailWithError(NSError(domain: "Tribune", code: 400, userInfo: [NSLocalizedDescriptionKey: "Bad scheme"]))
            return
        }

        let fileID = url.pathComponents[1]
        var data: Data?
        var contentType: String?
        do {
            if fileID == "index.html" {
                data = try Data(contentsOf: Bundle.main.url(forResource: "index", withExtension: "html")!)
                contentType = "text/html"
            } else if fileID == "epubjs.min.js" {
                data = try Data(contentsOf: Bundle.main.url(forResource: "epubjs.min", withExtension: "js")!)
                contentType = "text/javascript"
            } else if fileID == "jszip.min.js" {
                data = try Data(contentsOf: Bundle.main.url(forResource: "jszip.min", withExtension: "js")!)
                contentType = "text/javascript"
            } else if let id = Int(fileID), Files.fileExists(type: .epub, id: id) {
                data = try Data(contentsOf: Files.getFile(type: .epub, id: id), options: .mappedIfSafe)
                contentType = "application/epub+zip"
            } else {
                urlSchemeTask.didFailWithError(NSError(domain: "Tribune", code: 404, userInfo: [NSLocalizedDescriptionKey: "Unknown file id"]))
                return
            }
        } catch {
            print("error: \(error)")
            urlSchemeTask.didFailWithError(error)
            return
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: [
                                        "Content-Type": contentType!,
                                        "Content-Length": "\(data!.count)"
                                       ])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data!)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // No-op for simple cases
    }
}
