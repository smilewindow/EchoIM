import Foundation
import Nuke
import Observation
import UIKit

enum ChatPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

private struct PendingImageState: Sendable {
    /// prepare 前的原图 owner：供后台压缩和 prepare 失败重试使用。
    var originalData: Data?

    /// prepare 成功后的上传数据；上传成功但消息发送失败时仍需支持重试，
    /// 直到消息 confirmed 后才随 pendingImages 一起清理。
    var uploadData: Data?
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
    /// 本会话收到的对方消息累计数（WS 单条 + 重连补拉批量）。
    /// View 用 onChange 的差值驱动"新消息"角标，批量到达时不欠计数。
    private(set) var incomingMessageCount = 0
    /// key 是 `LocalMessage.localId`（即 `clientTempId`）。confirmed 后移除，避免长期堆积。
    private(set) var imageSendStages: [String: ImageSendStage] = [:]
    /// 图片发送的临时数据只在 pending/failed 生命周期内存在；confirmed 后统一走远程 URL。
    private var pendingImages: [String: PendingImageState] = [:]

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
    private let imagePreparer: @Sendable (Data) async -> PreparedMessageImage?
    /// 上传成功后把刚上传的数据按最终 URL 种进图片缓存，
    /// confirm 后气泡切远程加载时直接命中，发送者不用重新下载自己刚传的图。
    private let uploadedImageCacheSeeder: @MainActor (Data, URL) -> Void
    private let haptics: HapticFeedbackProvider
    private var onError: @MainActor (Error) -> Void

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

    // MARK: - Load guard
    private var isLoadingInitial = false

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
        imagePreparer: (@Sendable (Data) async -> PreparedMessageImage?)? = nil,
        uploadedImageCacheSeeder: (@MainActor (Data, URL) -> Void)? = nil,
        tokenProvider: @escaping @MainActor () -> String?,
        haptics: HapticFeedbackProvider? = nil,
        onError: @escaping @MainActor (Error) -> Void = { _ in }
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
        let defaultImagePreparer: @Sendable (Data) async -> PreparedMessageImage? = { data in
            await ImageCompressor.prepareForMessageImage(data: data)
        }
        self.imagePreparer = imagePreparer ?? defaultImagePreparer
        self.uploadedImageCacheSeeder = uploadedImageCacheSeeder ?? { data, url in
            ImagePipeline.shared.cache.storeCachedData(data, for: ImageRequest(url: url))
        }
        self.tokenProvider = tokenProvider
        self.haptics = haptics ?? UIKitHapticFeedback()
        self.onError = onError
    }

    func setOnErrorHandler(_ handler: @escaping @MainActor (Error) -> Void) {
        onError = handler
    }

    /// 对方是否正在输入。仅当 conversationId 已知且 typingStore 命中时为 true（不变式 8）。
    var peerIsTyping: Bool {
        guard let conversationId, let typingStore else { return false }
        return typingStore.isTyping(conversationId)
    }

    func imageUploadProgress(for localId: String) -> Double? {
        guard let imageSendStage = imageSendStages[localId] else { return nil }
        if case .preparing = imageSendStage {
            return 0
        }
        guard case .uploading(let progress) = imageSendStage else { return nil }
        let clamped = min(max(progress, 0), 1)
        return clamped < 1 ? clamped : nil
    }

    // MARK: - Load

    func load() async {
        guard !isLoadingInitial else { return }
        isLoadingInitial = true
        defer { isLoadingInitial = false }

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
                mergeLoadedMessages(cached.reversed().map(LocalMessage.confirmed))
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
                mergeLoadedMessages(rows.reversed().map(LocalMessage.confirmed))
                hasMoreOlder = rows.count == 50
                phase = .loaded
                await writeThroughAndMeta(rows)
                await markReadIfNeeded()
            } catch {
                phase = .error(String(describing: error))
                onError(error)
            }
        } else {
            await refetchMissedMessages()
            await markReadIfNeeded()
        }
    }

    /// 把批量加载的消息与 await 期间通过 WS 写入 messages 的消息合并，
    /// 避免全量赋值覆盖掉网络等待期间到达的对方消息。
    private func mergeLoadedMessages(_ fetched: [LocalMessage]) {
        let fetchedIds = Set(fetched.map(\.message.id))
        // WS 在等待期间追加的确认消息（正 id、不在 fetched 集合里）
        let wsExtras = messages.filter { $0.message.id > 0 && !fetchedIds.contains($0.message.id) }
        // 仍在发送中或失败的乐观气泡（负 id）始终置于末尾
        let pending = messages.filter { $0.message.id <= 0 }
        if wsExtras.isEmpty {
            messages = fetched + pending
        } else {
            messages = (fetched + wsExtras).sorted { $0.message.id < $1.message.id } + pending
        }
    }

    private func resolveDraftConversationIfNeeded() async {
        guard conversationId == nil else { return }

        if let metaStore,
           let snap = try? await metaStore.loadByPeerUserId(peer.id) {
            conversationId = snap.conversationId
            lastReadMessageId = snap.lastReadMessageId
            return
        }

        hasMoreOlder = false
        if phase == .idle {
            phase = .loaded
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

            // meta 的 oldestCachedMessageId 与展示中的最旧消息可能不一致（如缓存被清），
            // 远端补页按 id 去重，避免 ForEach 出现重复 identifier（未定义行为）。
            let displayedIds = Set(messages.map(\.message.id))
            let older = rows
                .filter { !displayedIds.contains($0.id) }
                .reversed()
                .map(LocalMessage.confirmed)
            messages.insert(contentsOf: older, at: 0)
            hasMoreOlder = rows.count == need
            await writeThroughAndMeta(rows)
        } catch {
            // 上滑分页失败不打断现有聊天内容，下一次触顶时允许自然重试。
            onError(error)
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
        stopTyping()    // 不变式 4 触发点 ②；UIImage 入口仅保留给非 PhotosPicker 调用点。
        guard let data = image.jpegData(compressionQuality: 1.0) ?? image.pngData() else { return }
        await sendImage(originalData: data)
    }

    func sendImage(originalData: Data) async {
        stopTyping()    // 选图后立即停止输入态；后台压缩不应阻塞主线程。
        guard let token = tokenProvider() else { return }
        guard let uploadRepo else { return }

        let tempId = makeTempId()
        let optimistic = Message(
            id: -Int.random(in: 1...Int.max),
            conversationId: conversationId ?? -1,
            senderId: currentUserId,
            body: nil,
            messageType: "image",
            mediaUrl: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            createdAt: Date(),
            clientTempId: tempId
        )
        // 这里短暂重复持有原图是有意取舍：发送后必须马上出现图片气泡，
        // LocalMessage 会派生 UIImage 缓存，避免 SwiftUI 重绘时反复 decode。
        // pendingImages 负责后台 prepare/retry，prepare 成功或 confirmed 后会清理。
        messages.append(
            LocalMessage(
                localId: tempId,
                message: optimistic,
                sendState: .pending,
                localImageData: originalData
            )
        )
        pendingImages[tempId] = PendingImageState(originalData: originalData)
        imageSendStages[tempId] = .preparing

        await prepareAndSendImage(
            tempId: tempId,
            originalData: originalData,
            token: token,
            uploadRepo: uploadRepo
        )
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
        imageSendStages[tempId] = .uploading(progress: 0)
        pendingImages[tempId] = PendingImageState(uploadData: data)

        await uploadAndSendImage(tempId: tempId, data: data, token: token, uploadRepo: uploadRepo)
    }

    func retry(localId: String) async {
        guard let index = messages.firstIndex(where: { $0.localId == localId }) else { return }
        guard case .failed = messages[index].sendState else { return }
        let local = messages[index]

        if local.message.messageType == "image" {
            guard let token = tokenProvider() else { return }

            if case .uploaded(let mediaURL, let mediaWidth, let mediaHeight) = imageSendStages[localId] {
                // 已上传成功的失败消息重试时，直接复用服务端媒体地址。
                let uploaded = UploadedMessageImage(
                    mediaUrl: mediaURL,
                    mediaWidth: mediaWidth,
                    mediaHeight: mediaHeight
                )
                messages[index].sendState = .pending
                await sendUploadedImage(tempId: localId, uploaded: uploaded, token: token)
                return
            }

            guard let uploadRepo else { return }
            messages[index].sendState = .pending
            if let data = pendingImages[localId]?.uploadData {
                imageSendStages[localId] = .uploading(progress: 0)
                await uploadAndSendImage(tempId: localId, data: data, token: token, uploadRepo: uploadRepo)
            } else if let originalData = pendingImages[localId]?.originalData {
                imageSendStages[localId] = .preparing
                await prepareAndSendImage(
                    tempId: localId,
                    originalData: originalData,
                    token: token,
                    uploadRepo: uploadRepo
                )
            } else {
                messages[index].sendState = .failed("missing local image data")
            }
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
            // 不在 REST 响应时触发 haptic，等 WS echo 确认
        } catch {
            markFailed(tempId: tempId, error: error)
        }
    }

    private func prepareAndSendImage(
        tempId: String,
        originalData: Data,
        token: String,
        uploadRepo: UploadRepository
    ) async {
        let prepared = await imagePreparer(originalData)
        guard let prepared else {
            imageSendStages[tempId] = .notStarted
            markFailed(tempId: tempId, error: APIError.invalidResponse)
            return
        }

        guard updatePreparedImage(tempId: tempId, prepared: prepared) else {
            return
        }

        await uploadAndSendImage(
            tempId: tempId,
            data: prepared.upload.data,
            token: token,
            uploadRepo: uploadRepo
        )
    }

    private func applyImagePreviewIfNeeded(tempId: String, previewData: Data?) {
        guard let previewData else { return }
        guard pendingImages[tempId] != nil else { return }
        guard let index = messages.firstIndex(where: { $0.localId == tempId }) else { return }
        guard messages[index].message.messageType == "image" else { return }
        guard messages[index].sendState == .pending || isFailed(messages[index].sendState) else { return }

        messages[index].localImageData = previewData
    }

    private func isFailed(_ sendState: MessageSendState) -> Bool {
        if case .failed = sendState {
            return true
        }
        return false
    }

    private func updatePreparedImage(
        tempId: String,
        prepared: PreparedMessageImage
    ) -> Bool {
        guard let index = messages.firstIndex(where: { $0.localId == tempId }) else { return false }
        guard messages[index].sendState == .pending else { return false }
        applyImagePreviewIfNeeded(tempId: tempId, previewData: prepared.previewData)

        let current = messages[index].message
        messages[index].message = Message(
            id: current.id,
            conversationId: current.conversationId,
            senderId: current.senderId,
            body: current.body,
            messageType: current.messageType,
            mediaUrl: current.mediaUrl,
            mediaWidth: prepared.upload.width,
            mediaHeight: prepared.upload.height,
            createdAt: current.createdAt,
            clientTempId: current.clientTempId
        )
        var state = pendingImages[tempId] ?? PendingImageState()
        // prepare 成功后 UI 若拿到 previewData 会切到小图；重试只需要 uploadData，
        // 所以释放 originalData，缩短大图驻留时间。
        state.uploadData = prepared.upload.data
        state.originalData = nil
        pendingImages[tempId] = state
        return true
    }

    private func uploadAndSendImage(
        tempId: String,
        data: Data,
        token: String,
        uploadRepo: UploadRepository
    ) async {
        do {
            imageSendStages[tempId] = .uploading(progress: 0)
            let uploaded = try await uploadRepo.uploadMessageImage(
                data: data,
                token: token,
                onProgress: { [weak self] progress in
                    self?.updateImageUploadProgress(tempId: tempId, progress: progress)
                }
            )
            imageSendStages[tempId] = .uploaded(
                mediaURL: uploaded.mediaUrl,
                mediaWidth: uploaded.mediaWidth,
                mediaHeight: uploaded.mediaHeight
            )
            if let url = Endpoints.absolute(uploaded.mediaUrl) {
                uploadedImageCacheSeeder(data, url)
            }
            await sendUploadedImage(tempId: tempId, uploaded: uploaded, token: token)
        } catch {
            imageSendStages[tempId] = .notStarted
            markFailed(tempId: tempId, error: error)
        }
    }

    private func sendUploadedImage(
        tempId: String,
        uploaded: UploadedMessageImage,
        token: String
    ) async {
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
            // 不在 REST 响应时触发 haptic，等 WS echo
        } catch {
            markFailed(tempId: tempId, error: error)
        }
    }

    private func updateImageUploadProgress(tempId: String, progress: Double) {
        let clamped = min(max(progress, 0), 1)
        let rounded = (clamped * 100).rounded() / 100

        if case .uploaded = imageSendStages[tempId] {
            return
        }
        guard imageSendStages[tempId] != .uploading(progress: rounded) else { return }
        guard let index = messages.firstIndex(where: { $0.localId == tempId }) else { return }
        guard messages[index].sendState == .pending else { return }

        imageSendStages[tempId] = .uploading(progress: rounded)
    }

    /// REST 201 与后续 WS echo 都按 clientTempId 走同一条合并路径。
    /// 返回 true 表示真正完成了 pending → confirmed 合并（区别于重放、已存在等情况）。
    @discardableResult
    fileprivate func mergeServerResult(_ message: Message, tempId: String) -> Bool {
        if conversationId == nil {
            conversationId = message.conversationId
        }

        var didConfirm = false
        let pendingIndex = messages.firstIndex(where: { $0.localId == tempId })
        if let confirmedIndex = messages.firstIndex(where: { $0.message.id == message.id }) {
            // 首屏 load 已经把这条 confirmed 混进来时，只需要删掉对应 pending，
            // 不再覆盖现有 confirmed，避免误伤本地附带状态（如 localImageData）。
            if let pendingIndex, pendingIndex != confirmedIndex {
                messages.remove(at: pendingIndex)
                clearPendingImageState(tempId)
            }
        } else if let pendingIndex {
            messages[pendingIndex] = LocalMessage(
                localId: "id-\(message.id)",
                message: message,
                sendState: .confirmed,
                localImageData: nil
            )
            clearPendingImageState(tempId)
            didConfirm = true
        } else if !messages.contains(where: { $0.message.id == message.id }) {
            messages.append(LocalMessage.confirmed(message))
        }

        Task { [weak self] in
            await self?.writeThroughAndMeta([message])
        }
        return didConfirm
    }

    private func clearPendingImageState(_ tempId: String) {
        imageSendStages.removeValue(forKey: tempId)
        pendingImages.removeValue(forKey: tempId)
    }

    private func markFailed(tempId: String, error: Error) {
        guard let index = messages.firstIndex(where: { $0.localId == tempId }) else { return }
        let message = ErrorPresenter.message(for: error)
        messages[index].sendState = .failed(message)
        onError(error)
        haptics.warning()
    }

    // MARK: - Mark read

    /// 是否有 mark-read PUT 在途。连收多条消息会各触发一次本方法，
    /// lastReadMessageId 要等 await 返回才推进，没有它会打出多个重复 PUT。
    private var isMarkingRead = false

    /// 用户是否位于消息列表可见底部（由 View 的滚动观察同步进来）。
    /// 对齐 Web 端语义（ChatView.tsx markReadIfVisible）：
    /// 上翻历史时收到的消息不推进已读游标，避免误清未读；回到底部时补报。
    private var isNearBottom = true

    func updateIsNearBottom(_ nearBottom: Bool) {
        let wasNearBottom = isNearBottom
        isNearBottom = nearBottom
        if nearBottom, !wasNearBottom {
            Task { [weak self] in
                await self?.markReadIfNeeded()
            }
        }
    }

    func markReadIfNeeded() async {
        guard !isMarkingRead else { return }
        isMarkingRead = true
        defer { isMarkingRead = false }

        // 循环补游标：PUT 在途期间到达的新消息，完成后重查 latest 再发一轮，
        // 每轮严格推进 lastReadMessageId，否则退出。
        while true {
            guard isNearBottom else { return }
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
                onError(error)
                return
            }
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

    // MARK: - Render helpers

    func isConsecutive(_ msg: LocalMessage, previous: LocalMessage?) -> Bool {
        guard let prev = previous,
              prev.message.senderId == msg.message.senderId else { return false }
        return msg.message.createdAt.timeIntervalSince(prev.message.createdAt) < 60
    }

    func shouldShowTimestamp(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let gap = messages[index].message.createdAt
            .timeIntervalSince(messages[index - 1].message.createdAt)
        return gap > 300
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
            haptics.success()   // WS echo 是 delivery 确认，无论 REST 是否先到
            return
        }

        guard !messages.contains(where: { $0.message.id == incoming.id }) else { return }
        messages.append(.confirmed(incoming))

        Task { [weak self] in
            await self?.writeThroughAndMeta([incoming])
        }

        if incoming.senderId != currentUserId {
            incomingMessageCount += 1
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
                onError(error)
            }
        } else {
            await catchUpAfterReconnect()
        }
    }

    /// 重连补拉后必须尝试推进已读游标（受 near-bottom 闸门控制），
    /// 否则在底部收到补拉消息时服务端 unread_count 不清零。
    private func catchUpAfterReconnect() async {
        await refetchMissedMessages()
        await markReadIfNeeded()
    }

    // MARK: - Reconnect hook

    /// connection.ready 后，如果草稿态的 peer 已经有会话，回填 conversationId 并补拉最新。
    func reconcileAfterReconnect(conversations: [Conversation]) async {
        guard conversationId == nil else {
            await catchUpAfterReconnect()
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
                    if message.senderId != currentUserId {
                        incomingMessageCount += 1
                    }
                }
                await writeThroughAndMeta(rows)

                cursor = rows.reduce(cursor) { result, message in
                    max(result, message.id)
                }
                guard rows.count == pageSize else { return }
            } catch {
                // 补拉失败保持现有消息；下一次 reconnect 或重进页面会再尝试。
                onError(error)
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

    func _pendingImageCountForTesting() -> Int {
        pendingImages.count
    }

    func _pendingImageOriginalDataCountForTesting() -> Int {
        pendingImages.values.filter { $0.originalData != nil }.count
    }

    func _pendingImageUploadDataCountForTesting() -> Int {
        pendingImages.values.filter { $0.uploadData != nil }.count
    }
}
#endif
