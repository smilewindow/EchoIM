import Foundation
import Observation

enum ConversationsPhase: Equatable, CustomStringConvertible {
    case idle
    case loading
    case loaded
    case unauthenticated
    case error(String)

    var description: String {
        switch self {
        case .idle:
            "idle"
        case .loading:
            "loading"
        case .loaded:
            "loaded"
        case .unauthenticated:
            "unauthenticated"
        case .error(let message):
            "error(\(message))"
        }
    }
}

@Observable
@MainActor
final class ConversationsListViewModel {
    private(set) var conversations: [Conversation] = []
    private(set) var phase: ConversationsPhase = .idle

    private let repository: ConversationRepository
    private let tokenProvider: @MainActor () -> String?
    private let currentUserId: @MainActor () -> Int?
    private weak var wsClient: WebSocketClient?
    private var wsSubscription: WSSubscription?
    private var readySubscription: WSSubscription?

    init(
        repository: ConversationRepository,
        tokenProvider: @escaping @MainActor () -> String?,
        currentUserId: @escaping @MainActor () -> Int? = { nil },
        wsClient: WebSocketClient? = nil
    ) {
        self.repository = repository
        self.tokenProvider = tokenProvider
        self.currentUserId = currentUserId
        self.wsClient = wsClient
    }

    // MARK: - Load

    func load() async {
        if phase == .loading {
            return
        }

        guard let token = tokenProvider() else {
            phase = .unauthenticated
            return
        }

        phase = .loading

        do {
            conversations = try await repository.list(token: token)
            phase = .loaded
        } catch {
            phase = .error(String(describing: error))
        }
    }

    func refresh() async {
        guard let token = tokenProvider() else {
            phase = .unauthenticated
            return
        }

        do {
            conversations = try await repository.list(token: token)
            phase = .loaded
        } catch {
            phase = .error(String(describing: error))
        }
    }

    // MARK: - WS subscription

    func attachWSSubscription() {
        guard wsSubscription == nil, let wsClient else { return }

        wsSubscription = wsClient.subscribe { [weak self] event in
            self?.handleWSEvent(event)
        }
        readySubscription = wsClient.onReady { [weak self] in
            // §7.5 step 1：重连成功先刷会话列表，再让行数据回到服务端真相。
            Task {
                await self?.refresh()
            }
        }
    }

    func detachWSSubscription() {
        wsSubscription?.cancel()
        wsSubscription = nil
        readySubscription?.cancel()
        readySubscription = nil
    }

    func handleWSEvent(_ event: WSEvent) {
        switch event {
        case .messageNew(let message):
            applyIncomingMessage(message)
        case .conversationUpdated(let payload):
            applyConversationUpdated(payload)
        default:
            return
        }
    }

    private func applyIncomingMessage(_ message: Message) {
        let selfId = currentUserId() ?? 0

        guard let index = conversations.firstIndex(where: { $0.id == message.conversationId }) else {
            // 新会话需要 peer 信息，局部事件不够，直接全量刷新。
            Task {
                await refresh()
            }
            return
        }

        let old = conversations[index]
        let shouldIncrementUnread =
            message.senderId != selfId && message.id > (old.lastReadMessageId ?? 0)
        let updated = Conversation.updatedCopy(
            of: old,
            lastMessageBody: message.body,
            lastMessageType: message.messageType,
            lastMessageSenderId: message.senderId,
            lastMessageAt: message.createdAt,
            unreadCount: old.unreadCount + (shouldIncrementUnread ? 1 : 0)
        )

        var next = conversations
        next.remove(at: index)
        // WS 到达的新消息就是该会话最新预览，P3 直接置顶即可。
        next.insert(updated, at: 0)
        conversations = next
    }

    private func applyConversationUpdated(_ payload: ConversationUpdatedPayload) {
        guard let index = conversations.firstIndex(where: { $0.id == payload.conversationId }) else {
            return
        }

        let old = conversations[index]
        guard payload.lastReadMessageId > (old.lastReadMessageId ?? 0) else { return }

        // P3 没有在列表页保存完整消息集合，精确重算成本太高；服务端只给本人推已读推进，
        // 因此这里乐观清零未读数，后续 refresh 会兜回服务端真相。
        conversations[index] = Conversation.updatedCopy(
            of: old,
            lastReadMessageId: payload.lastReadMessageId,
            unreadCount: 0
        )
    }
}

// MARK: - Conversation 局部更新辅助

extension Conversation {
    /// Conversation 是 let-only struct；WS 到达时只替换被事件触达的少量字段。
    static func updatedCopy(
        of conversation: Conversation,
        lastMessageBody: String? = nil,
        lastMessageType: String? = nil,
        lastMessageSenderId: Int? = nil,
        lastMessageAt: Date? = nil,
        lastReadMessageId: Int? = nil,
        unreadCount: Int? = nil
    ) -> Conversation {
        Conversation(
            id: conversation.id,
            createdAt: conversation.createdAt,
            peer: conversation.peer,
            lastMessageBody: lastMessageBody ?? conversation.lastMessageBody,
            lastMessageType: lastMessageType ?? conversation.lastMessageType,
            lastMessageSenderId: lastMessageSenderId ?? conversation.lastMessageSenderId,
            lastMessageAt: lastMessageAt ?? conversation.lastMessageAt,
            lastReadMessageId: lastReadMessageId ?? conversation.lastReadMessageId,
            unreadCount: unreadCount ?? conversation.unreadCount
        )
    }
}
