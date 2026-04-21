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

    // MARK: - Send

    func sendText(_ body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let token = tokenProvider() else { return }

        let tempId = makeTempId()
        let optimistic = Message(
            id: -Int.random(in: 1...Int.max),
            conversationId: conversationId ?? -1,
            senderId: currentUserId,
            body: trimmed,
            messageType: "text",
            mediaUrl: nil,
            createdAt: Date(),
            clientTempId: tempId
        )
        messages.append(
            LocalMessage(
                localId: tempId,
                message: optimistic,
                sendState: .pending,
                localImageData: nil
            )
        )

        await performSend(body: trimmed, tempId: tempId, token: token)
    }

    func retry(localId: String) async {
        guard let index = messages.firstIndex(where: { $0.localId == localId }) else { return }
        guard case .failed = messages[index].sendState else { return }
        guard let body = messages[index].message.body else { return }
        guard let token = tokenProvider() else { return }

        messages[index].sendState = .pending
        await performSend(body: body, tempId: localId, token: token)
    }

    private func performSend(body: String, tempId: String, token: String) async {
        do {
            let result = try await messageRepo.sendText(
                recipientId: peer.id,
                body: body,
                clientTempId: tempId,
                token: token
            )
            mergeServerResult(result, tempId: tempId)
        } catch {
            markFailed(tempId: tempId, error: error)
        }
    }

    /// REST 201 与后续 WS echo 都按 clientTempId 走同一条合并路径。
    fileprivate func mergeServerResult(_ message: Message, tempId: String) {
        if conversationId == nil {
            conversationId = message.conversationId
        }

        if let index = messages.firstIndex(where: { $0.localId == tempId }) {
            messages[index] = LocalMessage(
                localId: "id-\(message.id)",
                message: message,
                sendState: .confirmed,
                localImageData: messages[index].localImageData
            )
        } else if !messages.contains(where: { $0.message.id == message.id }) {
            messages.append(LocalMessage.confirmed(message))
        }
    }

    private func markFailed(tempId: String, error: Error) {
        guard let index = messages.firstIndex(where: { $0.localId == tempId }) else { return }
        messages[index].sendState = .failed(String(describing: error))
    }

    // MARK: - Tempid helper（Task 9/10 会用）

    fileprivate func makeTempId() -> String {
        tempSeq += 1
        return "pending-\(Int(Date().timeIntervalSince1970))-\(tempSeq)"
    }
}
