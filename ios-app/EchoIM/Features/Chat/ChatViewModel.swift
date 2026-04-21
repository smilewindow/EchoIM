import Foundation
import Observation

enum ChatPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable
@MainActor
final class ChatViewModel {
    // MARK: - State
    private(set) var messages: [LocalMessage] = []
    private(set) var phase: ChatPhase = .idle
    private(set) var isLoadingOlder = false
    private(set) var hasMoreOlder = true

    // MARK: - Identity
    /// 当前会话 id；从联系人进入未聊过的好友时先保持 nil，首条消息成功后再回填。
    private(set) var conversationId: Int?
    let peer: UserProfile
    private let currentUserId: Int

    // MARK: - Dependencies
    private let messageRepo: MessageRepository
    private let conversationRepository: ConversationRepository?
    weak var wsClient: WebSocketClient?
    private let tokenProvider: @MainActor () -> String?

    // MARK: - Tempid seq
    private var tempSeq = 0

    init(
        route: ChatRoute,
        currentUserId: Int,
        messageRepo: MessageRepository,
        wsClient: WebSocketClient?,
        conversationRepository: ConversationRepository? = nil,
        tokenProvider: @escaping @MainActor () -> String?
    ) {
        switch route {
        case .conversation(let conversation):
            self.conversationId = conversation.id
            self.peer = conversation.peer
        case .peer(let peer):
            self.conversationId = nil
            self.peer = peer
        }

        self.currentUserId = currentUserId
        self.messageRepo = messageRepo
        self.conversationRepository = conversationRepository
        self.wsClient = wsClient
        self.tokenProvider = tokenProvider
    }

    // MARK: - Load

    func load() async {
        guard let conversationId else {
            phase = .loaded
            hasMoreOlder = false
            return
        }

        guard let token = tokenProvider() else {
            phase = .error("unauthenticated")
            return
        }

        phase = .loading

        do {
            let rows = try await messageRepo.list(
                conversationId: conversationId,
                cursor: nil,
                token: token
            )
            // 服务端最新在前；聊天窗口内部统一保存为从旧到新的时间序。
            messages = rows.reversed().map(LocalMessage.confirmed)
            hasMoreOlder = rows.count == 50
            phase = .loaded
        } catch {
            phase = .error(String(describing: error))
        }
    }

    func loadOlder() async {
        guard let conversationId, !isLoadingOlder, hasMoreOlder else { return }
        guard let oldestMessageId = messages.first?.message.id else { return }
        guard let token = tokenProvider() else { return }

        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let rows = try await messageRepo.list(
                conversationId: conversationId,
                cursor: .before(oldestMessageId),
                token: token
            )
            let older = rows.reversed().map(LocalMessage.confirmed)
            messages.insert(contentsOf: older, at: 0)
            hasMoreOlder = rows.count == 50
        } catch {
            // 上滑分页失败不打断现有聊天内容，下一次触顶时允许自然重试。
        }
    }

    // MARK: - Tempid helper（Task 9/10 会用）

    fileprivate func makeTempId() -> String {
        tempSeq += 1
        return "pending-\(Int(Date().timeIntervalSince1970))-\(tempSeq)"
    }
}
