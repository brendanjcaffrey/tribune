import WebKit
import UniformTypeIdentifiers

struct LocalFile {
    let name: String
    let ext: String
    let mimeType: String

    func fileID() -> String {
        return "\(name).\(ext)"
    }

    func getContents() throws -> Data {
        // uncomment this to make development easier, run a server with rake ios:dev_server
        //let url = URL(string: "http://192.168.1.92:5173/\(name).\(ext)")!
        //return try Data(contentsOf: url)

        return try Data(contentsOf: Bundle.main.url(forResource: self.name, withExtension: self.ext)!)
    }
}

final class TribuneSchemeHandler: NSObject, WKURLSchemeHandler {
    static let localFiles = [
        LocalFile(name: "index", ext: "html", mimeType: "text/html"),
        LocalFile(name: "bundle", ext: "js", mimeType: "text/javascript"),
        LocalFile(name: "reader", ext: "js", mimeType: "text/javascript"),
    ]

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
            if let localFile = Self.localFiles.first(where: { $0.fileID() == fileID }) {
                data = try localFile.getContents()
                contentType = localFile.mimeType
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
