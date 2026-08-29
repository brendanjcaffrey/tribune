import Foundation

struct WebViewMessage: Decodable {
    let type: MessageType

    enum MessageType: Decodable {
        case atEnd
        case progress(progress: String)

        enum CodingKeys: String, CodingKey {
            case type, progress
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let typeString = try container.decode(String.self, forKey: .type)

            switch typeString {
            case "at end":
                self = .atEnd
            case "progress":
                let progress = try container.decode(String.self, forKey: .progress)
                self = .progress(progress: progress)
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
