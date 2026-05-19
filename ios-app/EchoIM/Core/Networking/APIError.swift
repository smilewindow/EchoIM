import Foundation

struct ServerAPIError: Decodable, Equatable, Sendable {
    let code: String
    let message: String

    var knownCode: KnownServerErrorCode? {
        KnownServerErrorCode(rawValue: code)
    }
}

private struct ServerAPIErrorEnvelope: Decodable {
    let error: ServerAPIError
}

enum APIError: Error, Equatable {
    case network(URLError)
    case unauthorized
    case http(status: Int, body: Data)
    case decoding(String)
    case invalidResponse

    var serverError: ServerAPIError? {
        guard case .http(_, let body) = self else { return nil }
        return Self.decodeServerError(from: body)
    }

    static func decodeServerError(from body: Data) -> ServerAPIError? {
        guard !body.isEmpty else { return nil }
        return try? APIClient.jsonDecoder.decode(ServerAPIErrorEnvelope.self, from: body).error
    }

    static func fromStatus(_ status: Int, body: Data) -> APIError {
        if status == 401 {
            return .unauthorized
        }

        return .http(status: status, body: body)
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        // URLError 的 userInfo 不稳定，比较 code 更符合网络层语义，也便于测试。
        case (.network(let lhsError), .network(let rhsError)):
            return lhsError.code == rhsError.code
        case (.unauthorized, .unauthorized):
            return true
        case (.http(let lhsStatus, let lhsBody), .http(let rhsStatus, let rhsBody)):
            return lhsStatus == rhsStatus && lhsBody == rhsBody
        case (.decoding(let lhsMessage), .decoding(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.invalidResponse, .invalidResponse):
            return true
        default:
            return false
        }
    }
}
