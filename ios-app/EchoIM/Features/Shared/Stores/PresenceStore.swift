import Foundation
import Observation

/// 设计 §2.1。在线好友 id 的 @Observable 容器。
/// 不订阅 WebSocketClient——事件路由由 UserSession 完成（不变式 1）。
@Observable
@MainActor
final class PresenceStore {
    private(set) var onlineUserIds: Set<Int> = []

    func setOnline(_ userId: Int) {
        onlineUserIds.insert(userId)
    }

    func setOffline(_ userId: Int) {
        onlineUserIds.remove(userId)
    }

    func isOnline(_ userId: Int) -> Bool {
        onlineUserIds.contains(userId)
    }

    /// 设计 §7.5 step 5：重连收到 connection.ready 后调用，由 UserSession 触发。
    /// 服务端会在 connection.ready 之后顺序 send 当前在线好友的 presence.online，
    /// 我们靠后续事件重建集合。
    func clearAll() {
        onlineUserIds.removeAll()
    }
}
