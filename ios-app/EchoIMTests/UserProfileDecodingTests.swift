import Foundation
import Testing
@testable import EchoIM

@Suite("UserProfile decoding")
struct UserProfileDecodingTests {
    @Test
    func decodesMinimalPayload() throws {
        let json = """
        { "id": 7, "username": "alice", "display_name": "Alice", "avatar_url": null }
        """.data(using: .utf8)!

        let user = try APIClient.jsonDecoder.decode(UserProfile.self, from: json)

        #expect(user.id == 7)
        #expect(user.username == "alice")
        #expect(user.displayName == "Alice")
        #expect(user.avatarUrl == nil)
    }

    @Test
    func missingOptionalsAreNil() throws {
        let json = """
        { "id": 8, "username": "bob" }
        """.data(using: .utf8)!

        let user = try APIClient.jsonDecoder.decode(UserProfile.self, from: json)

        #expect(user.displayName == nil)
        #expect(user.avatarUrl == nil)
    }
}
