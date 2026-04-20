import Foundation

struct Message: Codable, Identifiable, Equatable {
    let id: Int
    let conversationId: Int
    let senderId: Int
    let body: String?
    let messageType: String
    let mediaUrl: String?
    let createdAt: Date
    let clientTempId: String?
}

struct AuthenticatedUser: Codable, Equatable {
    let id: Int
    let username: String
    let email: String
    let displayName: String?
    let avatarUrl: String?
}

struct AuthResponse: Codable, Equatable {
    let token: String
    let user: AuthenticatedUser
}

struct EmptyResponse: Decodable, Equatable {}

@MainActor
final class APIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let rawValue = try container.decode(String.self)

            if let date = decodeISO8601Date(rawValue) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "invalid ISO 8601: \(rawValue)"
            )
        }

        return decoder
    }()

    nonisolated static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // 请求体默认保留 Swift 字段名；需要 snake_case 时由具体模型自己声明 CodingKeys。
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func request<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        token: String? = nil,
        body: Encodable? = nil
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: Endpoints.baseURL)?.absoluteURL else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.jsonEncoder.encode(AnyEncodable(body))
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.fromStatus(httpResponse.statusCode, body: data)
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        do {
            return try Self.jsonDecoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

private struct AnyEncodable: Encodable {
    let base: Encodable

    init(_ base: Encodable) {
        self.base = base
    }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
    }
}

private func decodeISO8601Date(_ rawValue: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = fractionalFormatter.date(from: rawValue) {
        return date
    }

    let plainFormatter = ISO8601DateFormatter()
    plainFormatter.formatOptions = [.withInternetDateTime]
    return plainFormatter.date(from: rawValue)
}
