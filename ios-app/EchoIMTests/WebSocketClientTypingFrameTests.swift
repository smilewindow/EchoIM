import Foundation
import Testing
@testable import EchoIM

@Suite
struct WebSocketClientTypingFrameTests {
    @Test
    func typingStartFrameHasFlatShape() throws {
        let data = try WebSocketClient.typingFrameJSON(
            conversationId: 42,
            isStart: true
        )
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["type"] as? String == "typing.start")
        #expect(json["conversation_id"] as? Int == 42)
        #expect(json["payload"] == nil)
    }

    @Test
    func typingStopFrameHasFlatShape() throws {
        let data = try WebSocketClient.typingFrameJSON(
            conversationId: 7,
            isStart: false
        )
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["type"] as? String == "typing.stop")
        #expect(json["conversation_id"] as? Int == 7)
    }
}
