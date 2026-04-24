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
    /// 服务端已确认的 last_read_message_id；P3 只同步游标，不在消息列表里计算未读。
    private(set) var lastReadMessageId: Int?

    // MARK: - Identity
    /// 当前会话 id；从联系人进入未聊过的好友时先保持 nil，首条消息成功后再回填。
    private(set) var conversationId: Int?
    let peer: UserProfile
    let currentUserId: Int

    // MARK: - Dependencies
    private let messageRepo: MessageRepository
    private let conversationRepository: ConversationRepository?
    weak var wsClient: WebSocketClient?
    private let tokenProvider: @MainActor () -> String?

    // MARK: - WS subscriptions

    private var subscription: WSSubscription?
    private var readySubscription: WSSubscription?

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
            self.lastReadMessageId = conversation.lastReadMessageId
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
                limit: nil,
                token: token
            )
            // 服务端最新在前；聊天窗口内部统一保存为从旧到新的时间序。
            messages = rows.reversed().map(LocalMessage.confirmed)
            hasMoreOlder = rows.count == 50
            phase = .loaded
            await markReadIfNeeded()
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
                limit: nil,
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

    // MARK: - Mark read

    func markReadIfNeeded() async {
        guard let conversationId else { return }
        guard let token = tokenProvider() else { return }

        let latest = messages.reduce(into: 0) { result, localMessage in
            if case .confirmed = localMessage.sendState {
                result = max(result, localMessage.message.id)
            }
        }
        guard latest > 0 else { return }
        guard latest > (lastReadMessageId ?? 0) else { return }

        do {
            try await messageRepo.markRead(
                conversationId: conversationId,
                lastReadMessageId: latest,
                token: token
            )
            // 服务端也会通过 conversation.updated 推进；本地先乐观推进，避免重复 PUT。
            lastReadMessageId = latest
        } catch {
            // 静默失败；下一次进入页面或收到新消息时重试。
        }
    }

    // MARK: - WS

    func attachWSSubscription() {
        guard subscription == nil, let wsClient else { return }
        subscription = wsClient.subscribe { [weak self] event in
            self?.handleWSEvent(event)
        }
        readySubscription = wsClient.onReady { [weak self] in
            Task { await self?.handleWSReady() }
        }
    }

    func detachWSSubscription() {
        subscription?.cancel()
        subscription = nil
        readySubscription?.cancel()
        readySubscription = nil
    }

    func handleWSEvent(_ event: WSEvent) {
        switch event {
        case .messageNew(let message):
            handleIncomingMessage(message)
        case .conversationUpdated(let payload):
            handleConversationUpdated(payload)
        default:
            return
        }
    }

    private func handleIncomingMessage(_ incoming: Message) {
        if conversationId == nil {
            if incoming.senderId == peer.id {
                conversationId = incoming.conversationId
            } else {
                // 草稿态只认当前 peer 激活的会话；其他会话或自己别处发出的 echo 先忽略。
                return
            }
        }

        guard incoming.conversationId == conversationId else { return }

        if let tempId = incoming.clientTempId, incoming.senderId == currentUserId {
            mergeServerResult(incoming, tempId: tempId)
            return
        }

        guard !messages.contains(where: { $0.message.id == incoming.id }) else { return }
        messages.append(.confirmed(incoming))

        if incoming.senderId != currentUserId {
            Task { [weak self] in
                await self?.markReadIfNeeded()
            }
        }
    }

    private func handleConversationUpdated(_ payload: ConversationUpdatedPayload) {
        guard payload.conversationId == conversationId else { return }
        let current = lastReadMessageId ?? 0
        if payload.lastReadMessageId > current {
            lastReadMessageId = payload.lastReadMessageId
        }
    }

    private func handleWSReady() async {
        if conversationId == nil {
            guard let token = tokenProvider(), let conversationRepository else { return }
            do {
                let conversations = try await conversationRepository.list(token: token)
                await reconcileAfterReconnect(conversations: conversations)
            } catch {
                // 草稿 promote 失败不影响当前聊天页，下一次 ready / 重进页面会再补。
            }
        } else {
            await refetchMissedMessages()
        }
    }

    // MARK: - Reconnect hook

    /// connection.ready 后，如果草稿态的 peer 已经有会话，回填 conversationId 并补拉最新。
    func reconcileAfterReconnect(conversations: [Conversation]) async {
        guard conversationId == nil else {
            await refetchMissedMessages()
            return
        }

        if let match = conversations.first(where: { $0.peer.id == peer.id }) {
            conversationId = match.id
            await load()
        }
    }

    /// §5.3 场景 C 的 P3 精简版：从当前最大 confirmed id 之后补拉一次。
    func refetchMissedMessages() async {
        guard let conversationId else { return }
        guard let token = tokenProvider() else { return }

        let newest = messages.reduce(into: 0) { result, localMessage in
            if case .confirmed = localMessage.sendState {
                result = max(result, localMessage.message.id)
            }
        }
        guard newest > 0 else {
            await load()
            return
        }

        do {
            let rows = try await messageRepo.list(
                conversationId: conversationId,
                cursor: .after(newest),
                limit: nil,
                token: token
            )
            for message in rows where !messages.contains(where: { $0.message.id == message.id }) {
                messages.append(.confirmed(message))
            }
        } catch {
            // 补拉失败保持现有消息；下一次 reconnect 或重进页面会再尝试。
        }
    }

    // MARK: - Tempid helper（Task 9/10 会用）

    fileprivate func makeTempId() -> String {
        tempSeq += 1
        return "pending-\(Int(Date().timeIntervalSince1970))-\(tempSeq)"
    }
}
