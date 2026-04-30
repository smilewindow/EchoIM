import Foundation
import Observation
import UIKit

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
    /// key 是 `LocalMessage.localId`（即 `clientTempId`）。confirmed 后移除，避免长期堆积。
    private(set) var imageSendStages: [String: ImageSendStage] = [:]

    // MARK: - Identity
    /// 当前会话 id；从联系人进入未聊过的好友时先保持 nil，首条消息成功后再回填。
    private(set) var conversationId: Int?
    let peer: UserProfile
    let currentUserId: Int

    // MARK: - Dependencies
    private let messageRepo: MessageRepository
    private let uploadRepo: UploadRepository?
    private let conversationRepository: ConversationRepository?
    private let messageStore: MessageStore?
    private let metaStore: ConversationMetaStore?
    weak var wsClient: WebSocketClient?
    private let tokenProvider: @MainActor () -> String?
    private let haptics: HapticFeedbackProvider

    // P6：只读 typingStore（不变式 8：VM 不路由 typing 事件，UserSession 是唯一写入方）
    private let typingStore: TypingStore?

    // P6 typing debounce
    private let typingSender: @MainActor (Int, Bool) -> Void
    private let idleTypingDuration: TimeInterval
    private var typingSendActive = false
    private var idleTypingTimer: Task<Void, Never>?

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
        messageStore: MessageStore? = nil,
        metaStore: ConversationMetaStore? = nil,
        uploadRepo: UploadRepository? = nil,
        typingStore: TypingStore? = nil,
        typingSender: @escaping @MainActor (Int, Bool) -> Void = { _, _ in },
        idleTypingDuration: TimeInterval = 3.0,
        tokenProvider: @escaping @MainActor () -> String?,
        haptics: HapticFeedbackProvider? = nil
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
        self.uploadRepo = uploadRepo
        self.conversationRepository = conversationRepository
        self.messageStore = messageStore
        self.metaStore = metaStore
        self.wsClient = wsClient
        self.typingStore = typingStore
        self.typingSender = typingSender
        self.idleTypingDuration = idleTypingDuration
        self.tokenProvider = tokenProvider
        self.haptics = haptics ?? UIKitHapticFeedback()
    }

    /// 对方是否正在输入。仅当 conversationId 已知且 typingStore 命中时为 true（不变式 8）。
    var peerIsTyping: Bool {
        guard let conversationId, let typingStore else { return false }
        return typingStore.isTyping(conversationId)
    }

    // MARK: - Load

    func load() async {
        if conversationId == nil {
            await resolveDraftConversationIfNeeded()
        }

        guard let conversationId else {
            hasMoreOlder = false
            if phase == .idle {
                phase = .loaded
            }
            return
        }

        guard let token = tokenProvider() else {
            phase = .error("unauthenticated")
            return
        }

        if messages.isEmpty, let messageStore {
            if let cached = try? await messageStore.loadLatest(conversationId: conversationId, limit: 50),
               !cached.isEmpty {
                messages = cached.reversed().map(LocalMessage.confirmed)
                phase = .loaded
            }
        }

        if messages.isEmpty {
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
                await writeThroughAndMeta(rows)
                await markReadIfNeeded()
            } catch {
                phase = .error(String(describing: error))
            }
        } else {
            await refetchMissedMessages()
            await markReadIfNeeded()
        }
    }

    private func resolveDraftConversationIfNeeded() async {
        guard conversationId == nil else { return }
        guard let conversationRepository else {
            phase = .loaded
            hasMoreOlder = false
            return
        }

        guard let token = tokenProvider() else {
            phase = .error("unauthenticated")
            return
        }

        do {
            let conversations = try await conversationRepository.list(token: token)
            if let match = conversations.first(where: { $0.peer.id == peer.id }) {
                adoptConversation(match)
            } else {
                phase = .loaded
                hasMoreOlder = false
            }
        } catch {
            // 会话发现失败不阻塞草稿输入；发送成功后仍会从 REST 响应回填 conversationId。
            phase = .loaded
            hasMoreOlder = false
        }
    }

    func loadOlder() async {
        guard let conversationId, !isLoadingOlder, hasMoreOlder else { return }
        guard let oldestDisplayed = messages.first?.message.id else { return }
        guard let token = tokenProvider() else { return }

        isLoadingOlder = true
        defer { isLoadingOlder = false }

        let pageSize = 50
        var localBatch: [Message] = []

        if let messageStore {
            localBatch = (try? await messageStore.loadOlder(
                conversationId: conversationId,
                before: oldestDisplayed,
                limit: pageSize
            )) ?? []

            if !localBatch.isEmpty {
                // 本地查询保持 DESC；UI 数组统一按时间 ASC 展示。
                messages.insert(contentsOf: localBatch.reversed().map(LocalMessage.confirmed), at: 0)
            }
        }

        if localBatch.count == pageSize {
            return
        }

        let need = pageSize - localBatch.count
        var oldestCached = messages.first?.message.id ?? oldestDisplayed
        if let metaStore,
           let meta = try? await metaStore.load(conversationId: conversationId),
           let oldest = meta.oldestCachedMessageId {
            // 远端补缺从缓存连续后缀的下边界往前要，避免重复拉本地已有段。
            oldestCached = oldest
        }

        do {
            let rows = try await messageRepo.list(
                conversationId: conversationId,
                cursor: .before(oldestCached),
                limit: need,
                token: token
            )
            if rows.isEmpty {
                hasMoreOlder = false
                return
            }

            let older = rows.reversed().map(LocalMessage.confirmed)
            messages.insert(contentsOf: older, at: 0)
            hasMoreOlder = rows.count == need
            await writeThroughAndMeta(rows)
        } catch {
            // 上滑分页失败不打断现有聊天内容，下一次触顶时允许自然重试。
        }
    }

    // MARK: - Send

    func sendText(_ body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stopTyping()    // 不变式 4 触发点 ②；在 token guard 之前执行，避免 401 早退漏发 stop
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

    func sendImage(_ image: UIImage) async {
        stopTyping()    // 不变式 4 触发点 ②；在 compressForUpload 之前执行
        guard let compressed = ImageCompressor.compressForUpload(image) else {
            // 编码失败极少发生；P5 先静默放弃，P8 接日志/提示体系时再补用户反馈。
            return
        }
        await sendCompressedImage(data: compressed.data, width: compressed.width, height: compressed.height)
    }

    func sendCompressedImage(data: Data, width: Int, height: Int) async {
        stopTyping()    // sendCompressedImage 被直接调用时（如测试）也保证幂等
        guard let token = tokenProvider() else { return }
        guard let uploadRepo else { return }

        let tempId = makeTempId()
        // 乐观气泡先用本地压缩尺寸占位；REST 201 回来后会替换为服务端尺寸（一般等同）。
        let optimistic = Message(
            id: -Int.random(in: 1...Int.max),
            conversationId: conversationId ?? -1,
            senderId: currentUserId,
            body: nil,
            messageType: "image",
            mediaUrl: nil,
            mediaWidth: width,
            mediaHeight: height,
            createdAt: Date(),
            clientTempId: tempId
        )
        messages.append(
            LocalMessage(
                localId: tempId,
                message: optimistic,
                sendState: .pending,
                localImageData: data
            )
        )
        imageSendStages[tempId] = .notStarted

        await executeImageSend(tempId: tempId, data: data, token: token, uploadRepo: uploadRepo)
    }

    func retry(localId: String) async {
        guard let index = messages.firstIndex(where: { $0.localId == localId }) else { return }
        guard case .failed = messages[index].sendState else { return }
        let local = messages[index]

        if local.message.messageType == "image" {
            guard let token = tokenProvider() else { return }
            guard let uploadRepo else { return }
            // VM 重建后会丢 localImageData（已知妥协）；此时 no-op，等待用户重选图。
            guard let data = local.localImageData else { return }

            messages[index].sendState = .pending
            await executeImageSend(tempId: localId, data: data, token: token, uploadRepo: uploadRepo)
            return
        }

        guard let body = local.message.body else { return }
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
            haptics.lightImpact()
        } catch {
            markFailed(tempId: tempId, error: error)
        }
    }

    private func executeImageSend(
        tempId: String,
        data: Data,
        token: String,
        uploadRepo: UploadRepository
    ) async {
        let uploaded: UploadedMessageImage
        if case .uploaded(let url, let width, let height) = imageSendStages[tempId] {
            uploaded = UploadedMessageImage(mediaUrl: url, mediaWidth: width, mediaHeight: height)
        } else {
            do {
                uploaded = try await uploadRepo.uploadMessageImage(data: data, token: token)
                imageSendStages[tempId] = .uploaded(
                    mediaURL: uploaded.mediaUrl,
                    mediaWidth: uploaded.mediaWidth,
                    mediaHeight: uploaded.mediaHeight
                )
            } catch {
                markFailed(tempId: tempId, error: error)
                return
            }
        }

        do {
            let result = try await messageRepo.sendImage(
                recipientId: peer.id,
                mediaUrl: uploaded.mediaUrl,
                mediaWidth: uploaded.mediaWidth,
                mediaHeight: uploaded.mediaHeight,
                clientTempId: tempId,
                token: token
            )
            mergeServerResult(result, tempId: tempId)
            imageSendStages.removeValue(forKey: tempId)
            haptics.lightImpact()
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

        Task { [weak self] in
            await self?.writeThroughAndMeta([message])
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
            await writeReadProgress(latest)
        } catch {
            // 静默失败；下一次进入页面或收到新消息时重试。
        }
    }

    // MARK: - Typing

    /// 输入框 onChange 时调用：第一次发 start，重置 idle 兜底定时器（不变式 5）。
    func handleTypingInput() {
        guard let conversationId else { return }

        if !typingSendActive {
            typingSendActive = true
            typingSender(conversationId, true)
        }

        idleTypingTimer?.cancel()
        let nanos = UInt64(idleTypingDuration * 1_000_000_000)
        idleTypingTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self else { return }
            self.stopTyping()
        }
    }

    /// 三种触发点（不变式 4）：① idle 到期 ② sendText/sendImage ③ onDisappear。
    func stopTyping() {
        idleTypingTimer?.cancel()
        idleTypingTimer = nil

        guard typingSendActive, let conversationId else { return }
        typingSendActive = false
        typingSender(conversationId, false)
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

        Task { [weak self] in
            await self?.writeThroughAndMeta([incoming])
        }

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
            adoptConversation(match)
            await load()
        }
    }

    private func adoptConversation(_ conversation: Conversation) {
        // 联系人入口与会话入口最终收敛到同一个 conversationId，避免打开一间“空的新聊天室”。
        conversationId = conversation.id
        lastReadMessageId = conversation.lastReadMessageId
    }

    /// §5.3 场景 C：重连后按页追赶缺失消息，避免长离线时一次请求过大。
    func refetchMissedMessages() async {
        guard let conversationId else { return }
        guard let token = tokenProvider() else { return }

        var cursor = 0
        if let metaStore, let meta = try? await metaStore.load(conversationId: conversationId) {
            cursor = meta.newestCachedMessageId ?? 0
        }
        if cursor == 0 {
            cursor = messages.reduce(into: 0) { result, localMessage in
                if case .confirmed = localMessage.sendState {
                    result = max(result, localMessage.message.id)
                }
            }
        }
        guard cursor > 0 else {
            await load()
            return
        }

        let pageSize = 50
        let maxPages = 20
        var pages = 0

        while pages < maxPages {
            pages += 1

            do {
                let rows = try await messageRepo.list(
                    conversationId: conversationId,
                    cursor: .after(cursor),
                    limit: pageSize,
                    token: token
                )
                guard !rows.isEmpty else { return }

                for message in rows where !messages.contains(where: { $0.message.id == message.id }) {
                    messages.append(.confirmed(message))
                }
                await writeThroughAndMeta(rows)

                cursor = rows.reduce(cursor) { result, message in
                    max(result, message.id)
                }
                guard rows.count == pageSize else { return }
            } catch {
                // 补拉失败保持现有消息；下一次 reconnect 或重进页面会再尝试。
                return
            }
        }
    }

    private func writeThroughAndMeta(_ rows: [Message]) async {
        guard let messageStore, let metaStore else { return }
        guard let conversationId, !rows.isEmpty else { return }

        try? await messageStore.append(rows)

        let newestInBatch = rows.max { $0.id < $1.id }
        guard let minNew = rows.map(\.id).min(), let maxNew = newestInBatch?.id else { return }
        let existing = try? await metaStore.load(conversationId: conversationId)
        let shouldReplacePreview = maxNew > (existing?.newestCachedMessageId ?? 0)

        let merged = ConversationMetaSnapshot(
            conversationId: conversationId,
            peerUserId: existing?.peerUserId ?? peer.id,
            peerUsername: existing?.peerUsername ?? peer.username,
            peerDisplayName: existing?.peerDisplayName ?? peer.displayName,
            peerAvatarUrl: existing?.peerAvatarUrl ?? peer.avatarUrl,
            // 服务端消息 id 全局单调，边界按 id 合并，不依赖接口返回顺序。
            oldestCachedMessageId: min(existing?.oldestCachedMessageId ?? .max, minNew),
            newestCachedMessageId: max(existing?.newestCachedMessageId ?? .min, maxNew),
            lastReadMessageId: existing?.lastReadMessageId ?? lastReadMessageId,
            unreadCount: existing?.unreadCount ?? 0,
            lastMessageBody: shouldReplacePreview ? newestInBatch?.body : existing?.lastMessageBody,
            lastMessageType: shouldReplacePreview ? newestInBatch?.messageType : existing?.lastMessageType,
            lastMessageAt: shouldReplacePreview ? newestInBatch?.createdAt : existing?.lastMessageAt
        )
        try? await metaStore.upsert(merged)
    }

    private func writeReadProgress(_ latest: Int) async {
        guard let conversationId, let metaStore else { return }
        guard let existing = try? await metaStore.load(conversationId: conversationId) else { return }

        try? await metaStore.upsert(
            ConversationMetaSnapshot(
                conversationId: existing.conversationId,
                peerUserId: existing.peerUserId,
                peerUsername: existing.peerUsername,
                peerDisplayName: existing.peerDisplayName,
                peerAvatarUrl: existing.peerAvatarUrl,
                oldestCachedMessageId: existing.oldestCachedMessageId,
                newestCachedMessageId: existing.newestCachedMessageId,
                lastReadMessageId: latest,
                unreadCount: 0,
                lastMessageBody: existing.lastMessageBody,
                lastMessageType: existing.lastMessageType,
                lastMessageAt: existing.lastMessageAt
            )
        )
    }

    // MARK: - Tempid helper（Task 9/10 会用）

    fileprivate func makeTempId() -> String {
        tempSeq += 1
        return "pending-\(Int(Date().timeIntervalSince1970))-\(tempSeq)"
    }
}

#if DEBUG
extension ChatViewModel {
    /// 仅 P5 图片发送测试用：注入丢失 localImageData 的 failed bubble 边界。
    func _injectFailedImageBubbleForTesting(
        tempId: String,
        message: Message,
        stage: ImageSendStage,
        localData: Data?
    ) {
        messages.append(
            LocalMessage(
                localId: tempId,
                message: message,
                sendState: .failed("injected"),
                localImageData: localData
            )
        )
        imageSendStages[tempId] = stage
    }
}
#endif
