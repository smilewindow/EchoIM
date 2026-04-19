import Foundation

enum APIError: Error, Equatable {
    case network(URLError)
    case unauthorized
    case http(status: Int, body: Data)
    case decoding(String)
    case invalidResponse

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
