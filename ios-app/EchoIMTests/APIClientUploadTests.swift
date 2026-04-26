import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("APIClient — Upload")
struct APIClientUploadTests {
    @Test
    func uploadSendsMultipartWithFileFieldAndBearer() async throws {
        var capturedRequest: URLRequest?
        let (config, _) = MockURLProtocol.configure { request in
            capturedRequest = request
            let body = """
            {"media_url":"/uploads/messages/42-1234567890.jpg"}
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                body
            )
        }
        let api = APIClient(session: URLSession(configuration: config))

        let body = Self.makeBody(boundary: "TestBoundary", payload: Data([0xFF, 0xD8, 0xFF]))
        let response: APIClientUploadProbe = try await api.upload(
            "api/upload/message-image",
            boundary: "TestBoundary",
            body: body,
            token: "abc"
        )

        #expect(response.mediaUrl == "/uploads/messages/42-1234567890.jpg")

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType == "multipart/form-data; boundary=TestBoundary")

        let captured = try #require(Self.bodyData(from: request))
        let bodyString = String(decoding: captured, as: UTF8.self)
        #expect(bodyString.contains("name=\"file\""))
        #expect(bodyString.contains("filename=\"image.jpg\""))
        #expect(bodyString.contains("Content-Type: image/jpeg"))
    }

    @Test
    func uploadMaps401ToUnauthorized() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                "{\"error\":\"Unauthorized\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))

        do {
            let _: APIClientUploadProbe = try await api.upload(
                "api/upload/message-image",
                boundary: "X",
                body: Self.makeBody(boundary: "X", payload: Data([0xFF, 0xD8])),
                token: "stale"
            )
            Issue.record("expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        }
    }

    @Test
    func uploadMapsNon2xxToHTTPStatus() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                "{\"error\":\"Invalid image file\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))

        do {
            let _: APIClientUploadProbe = try await api.upload(
                "api/upload/message-image",
                boundary: "X",
                body: Self.makeBody(boundary: "X", payload: Data([0x00])),
                token: "tok"
            )
            Issue.record("expected APIError.http")
        } catch APIError.http(let status, _) {
            #expect(status == 400)
        }
    }

    private static func makeBody(boundary: String, payload: Data) -> Data {
        var data = Data()
        let crlf = "\r\n"
        data.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        data.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\(crlf)"
                .data(using: .utf8)!
        )
        data.append("Content-Type: image/jpeg\(crlf)\(crlf)".data(using: .utf8)!)
        data.append(payload)
        data.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return data
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                return nil
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private struct APIClientUploadProbe: Decodable {
    let mediaUrl: String
}
