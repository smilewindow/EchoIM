import Testing
@testable import EchoIM

@MainActor
@Suite
struct PresenceStoreTests {
    @Test
    func setOnlineAddsUserId() {
        let store = PresenceStore()
        store.setOnline(42)
        #expect(store.isOnline(42))
        #expect(store.onlineUserIds == [42])
    }

    @Test
    func setOnlineIsIdempotent() {
        let store = PresenceStore()
        store.setOnline(42)
        store.setOnline(42)
        #expect(store.onlineUserIds.count == 1)
    }

    @Test
    func setOfflineRemovesUserId() {
        let store = PresenceStore()
        store.setOnline(42)
        store.setOffline(42)
        #expect(!store.isOnline(42))
        #expect(store.onlineUserIds.isEmpty)
    }

    @Test
    func setOfflineForUnknownUserIsNoOp() {
        let store = PresenceStore()
        store.setOffline(42)
        #expect(store.onlineUserIds.isEmpty)
    }

    @Test
    func clearAllEmptiesSet() {
        let store = PresenceStore()
        store.setOnline(1)
        store.setOnline(2)
        store.setOnline(3)
        store.clearAll()
        #expect(store.onlineUserIds.isEmpty)
        #expect(!store.isOnline(1))
    }
}
