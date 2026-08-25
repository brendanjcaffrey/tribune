import Foundation

struct PageImage {
    let src: String
    let mime: String
    let data: Data
}

// what page.js hands back across the extension boundary. the html is the whole
// document, the images are only the ones the page let us fetch; the server
// downloads the rest, so a short list is a slower push rather than a failed one.
struct Page {
    let url: String
    let html: String
    let images: [PageImage]

    // the results arrive as a plist-safe dictionary, so everything is a string
    // and anything unexpected means safari didn't run the preprocessing script
    init?(javaScriptResults results: Any?) {
        guard
            let dict = results as? [String: Any],
            let url = dict["url"] as? String, !url.isEmpty,
            let html = dict["html"] as? String, !html.isEmpty
        else { return nil }

        self.url = url
        self.html = html
        self.images = (dict["images"] as? [[String: Any]] ?? []).compactMap { entry in
            guard
                let src = entry["src"] as? String, !src.isEmpty,
                let mime = entry["mime"] as? String, mime.hasPrefix("image/"),
                let base64 = entry["base64"] as? String,
                let data = Data(base64Encoded: base64), !data.isEmpty
            else { return nil }

            return PageImage(src: src, mime: mime, data: data)
        }
    }
}
