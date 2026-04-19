import Foundation
import Testing
@testable import EchoIM

@Suite("KeychainTokenStore", .serialized)
struct KeychainTokenStoreTests {
    @Test
    func saveLoadDelete() throws {
        let store = KeychainTokenStore(service: "com.echoim.test.\(UUID().uuidString)")
        try store.clear()
        #expect(try store.load() == nil)

        try store.save(token: "tok-1", userId: 42)
        let loaded = try store.load()
        #expect(loaded?.token == "tok-1")
        #expect(loaded?.userId == 42)

        try store.clear()
        #expect(try store.load() == nil)
    }
}
