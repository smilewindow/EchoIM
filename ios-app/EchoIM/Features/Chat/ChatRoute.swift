import Foundation

/// 从会话列表 / 联系人进入 ChatView 的两种来源。Hashable 用于 NavigationStack.navigationDestination。
enum ChatRoute: Hashable {
    case conversation(Conversation)
    case peer(UserProfile)
}
