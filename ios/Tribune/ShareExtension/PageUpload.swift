import Foundation

// posts a page to POST /newsletters/raw, the same endpoint and the same
// multipart shape the firefox extension uses: the document as a file, one part
// per image, and a json blob pairing each part back up with the src it replaces.
enum PageUpload {
    private static let rawPath = "/newsletters/raw"
    // uploads are bigger and slower than the app's json calls, and the share
    // sheet is already on screen waiting, so this is far longer than APIClient's
    private static let timeoutInterval = 60.0

    static func push(_ page: Page) async throws -> Int {
        // a keychain error and a missing item both mean the same thing here:
        // there is no token to push with
        let stored = (try? AuthToken.read()) ?? nil
        guard let token = stored, !token.isEmpty else { throw ShareError.notSignedIn }

        let boundary = "tribune.\(UUID().uuidString)"
        var body = MultipartBody(boundary: boundary)
        body.appendFile(name: "raw_source_file", filename: "source.html",
                        type: "text/html", data: Data(page.html.utf8))

        // the field names are how the server pairs each upload back up with the
        // src it should replace in the html
        let imageMetadata = page.images.enumerated().map { index, image -> [String: String] in
            let field = "image_\(index)"
            body.appendFile(name: field, filename: field, type: image.mime, data: image.data)
            return ["field": field, "src": image.src]
        }

        let metadata: [String: Any] = ["url": page.url, "images": imageMetadata]
        let json = try JSONSerialization.data(withJSONObject: metadata)
        body.appendFile(name: "metadata", filename: "metadata", type: "application/json", data: json)

        var req = URLRequest(url: AppConfig.baseURL.appending(path: rawPath),
                             timeoutInterval: timeoutInterval)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.upload(for: req, from: body.finished())
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            if code == 401 || code == 403 { throw ShareError.notSignedIn }
            throw ShareError.badStatus(code, String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return decoded?["id"] as? Int ?? 0
    }
}

private struct MultipartBody {
    let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func appendFile(name: String, filename: String, type: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        // rack hands the server this header verbatim, and it checks the source
        // and metadata parts against exact mime types, so no charset here
        append("Content-Type: \(type)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    mutating func finished() -> Data {
        append("--\(boundary)--\r\n")
        return data
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}
