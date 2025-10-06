import Foundation

struct WebViewMessage: Decodable {
    let type: MessageType

    enum MessageType: Decodable {
        case atEnd
        case progress(cfi: String)

        enum CodingKeys: String, CodingKey {
            case type, cfi
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let typeString = try container.decode(String.self, forKey: .type)

            switch typeString {
            case "at end":
                self = .atEnd
            case "progress":
                let cfi = try container.decode(String.self, forKey: .cfi)
                self = .progress(cfi: cfi)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown type: \(typeString)"
                )
            }
        }
    }
}
