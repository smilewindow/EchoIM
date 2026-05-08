import Foundation
import Network
import Observation

/// WS 生命周期状态机。设计文档 §7.4。
/// .handshaking → .ready 的切换由服务端 "connection.ready" 文本帧触发；
/// 此帧不分发给业务订阅者。
enum WSState: Equatable, Sendable {
    case disconnected
    case connecting
    case handshaking
    case ready
    case reconnecting(in: TimeInterval)
}

enum WSDisconnectReason: Equatable, Sendable {
    case userInitiated      // logout / app backgrounded
    case unauthorized       // HTTP 401 on upgrade
    case transport          // TCP / pong timeout / unknown failure
    case networkLost        // NWPathMonitor unsatisfied
}

/// 订阅令牌。ViewModel 在 onDisappear / deinit 前调 `cancel()`。
final class WSSubscription {
    fileprivate let id: UUID
    fileprivate weak var client: WebSocketClient?

    fileprivate init(id: UUID, client: WebSocketClient) {
        self.id = id
        self.client = client
    }

    @MainActor
    func cancel() {
        client?.unsubscribe(id)
    }
}

@MainActor
@Observable
final class WebSocketClient: NSObject {
    // MARK: - Public observable state

    private(set) var state: WSState = .disconnected

    // MARK: - Dependencies

    private let tokenProvider: @MainActor () -> String?
    /// 401 时触发；由 AppContainer 注入 `handleUnauthorized`（Task 6）。
    private let onUnauthorized: @MainActor () -> Void
    private let reconnectPolicy: ReconnectPolicy

    // MARK: - URLSession / task

    private var urlSession: URLSession?
    private var task: URLSessionWebSocketTask?

    // MARK: - Subscribers

    private var handlers: [UUID: (WSEvent) -> Void] = [:]
    private var readyHandlers: [UUID: @MainActor () -> Void] = [:]

    // MARK: - Reconnect

    private var reconnectTimer: Task<Void, Never>?

    // MARK: - Heartbeat

    private var heartbeatTask: Task<Void, Never>?
    private var pendingPongContinuation: CheckedContinuation<Void, Error>?
    private var pendingPongID: UUID?
    private let heartbeatInterval: TimeInterval = 30.0
    private let pongTimeout: TimeInterval = 10.0

    // MARK: - Network monitor

    private let pathMonitor = NWPathMonitor()
    private var networkMonitorStarted = false

    private var shouldReconnect = false

    init(
        tokenProvider: @escaping @MainActor () -> String?,
        onUnauthorized: @escaping @MainActor () -> Void
    ) {
        self.tokenProvider = tokenProvider
        self.onUnauthorized = onUnauthorized
        self.reconnectPolicy = ReconnectPolicy()
        super.init()
        startNetworkMonitorIfNeeded()
    }

    init(
        tokenProvider: @escaping @MainActor () -> String?,
        onUnauthorized: @escaping @MainActor () -> Void,
        reconnectPolicy: ReconnectPolicy
    ) {
        self.tokenProvider = tokenProvider
        self.onUnauthorized = onUnauthorized
        self.reconnectPolicy = reconnectPolicy
        super.init()
        startNetworkMonitorIfNeeded()
    }

    // MARK: - Public lifecycle

    /// 空闲或重连定时器等待中都能调。如果已连上则直接 no-op。
    func connectIfNeeded() {
        shouldReconnect = true
        switch state {
        case .connecting, .handshaking, .ready:
            return
        case .disconnected, .reconnecting:
            reconnectTimer?.cancel()
            reconnectTimer = nil
            reconnectPolicy.reset()
            openSocket()
        }
    }

    /// 外部主动断开（登出 / 进后台）；不触发重连。
    func disconnect(reason: WSDisconnectReason) {
        shouldReconnect = false
        reconnectTimer?.cancel()
        reconnectTimer = nil
        closeTaskLocally()
        state = .disconnected
        Log.info(.ws, "disconnected (\(reason))")
    }

    // MARK: - Subscription

    func subscribe(_ handler: @escaping (WSEvent) -> Void) -> WSSubscription {
        let id = UUID()
        handlers[id] = handler
        return WSSubscription(id: id, client: self)
    }

    func onReady(_ handler: @escaping @MainActor () -> Void) -> WSSubscription {
        let id = UUID()
        readyHandlers[id] = handler
        return WSSubscription(id: id, client: self)
    }

    fileprivate func unsubscribe(_ id: UUID) {
        handlers.removeValue(forKey: id)
        readyHandlers.removeValue(forKey: id)
    }

    // MARK: - Internal

    private func openSocket() {
        guard let token = tokenProvider() else {
            // 没 token 直接进 disconnected；调用方负责在登录后重新 connect。
            state = .disconnected
            return
        }
        guard let url = Endpoints.webSocketURL(token: token) else {
            state = .disconnected
            return
        }

        // URLSession delegate 绑定自己，后续可在 didComplete 里分辨 statusCode。
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        urlSession = session

        state = .connecting
        // Release: hide query (token); DEBUG: full URL
        #if DEBUG
        Log.info(.ws, "connecting to \(url.absoluteString)")
        #else
        Log.info(.ws, "connecting to \(url.scheme ?? "ws")://\(url.host ?? "")\(url.path)")
        #endif

        let newTask = session.webSocketTask(with: url)
        task = newTask
        newTask.resume()
        startReceiveLoop()
    }

    private func closeTaskLocally() {
        stopHeartbeat()
        if let continuation = pendingPongContinuation {
            pendingPongContinuation = nil
            pendingPongID = nil
            continuation.resume(throwing: CancellationError())
        }
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.heartbeatInterval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.sendPingWithTimeout()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func sendPingWithTimeout() async {
        guard let task, case .ready = state, pendingPongContinuation == nil else { return }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let pongID = UUID()
                self.pendingPongContinuation = continuation
                self.pendingPongID = pongID

                DispatchQueue.main.asyncAfter(deadline: .now() + self.pongTimeout) { [weak self] in
                    Task { @MainActor in
                        guard let self,
                              self.pendingPongID == pongID,
                              let continuation = self.pendingPongContinuation else { return }
                        self.pendingPongContinuation = nil
                        self.pendingPongID = nil
                        continuation.resume(throwing: URLError(.timedOut))
                        Log.warning(.ws, "pong timeout")
                    }
                }

                task.sendPing { [weak self] error in
                    Task { @MainActor in
                        guard let self,
                              self.pendingPongID == pongID,
                              let continuation = self.pendingPongContinuation else { return }
                        self.pendingPongContinuation = nil
                        self.pendingPongID = nil
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
        } catch {
            scheduleReconnect()
        }
    }

    private func startNetworkMonitorIfNeeded() {
        guard !networkMonitorStarted else { return }
        networkMonitorStarted = true

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                if path.status == .satisfied {
                    // 网络恢复时只唤醒重连态；主动断开的状态不能被偷偷拉起。
                    switch self.state {
                    case .reconnecting where self.shouldReconnect:
                        self.reconnectTimer?.cancel()
                        self.reconnectTimer = nil
                        self.reconnectPolicy.reset()
                        self.openSocket()
                    default:
                        break
                    }
                }
                // 网络断开交给 URLSession delegate 收敛，避免主动 close 制造重复状态变化。
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "WebSocketClient.path"))
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        switch state {
        case .ready, .connecting, .handshaking:
            break
        case .disconnected, .reconnecting:
            return
        }
        closeTaskLocally()
        let delay = reconnectPolicy.nextDelay()
        state = .reconnecting(in: delay)
        Log.warning(.ws, "reconnecting in \(Int(delay))s")
        reconnectTimer?.cancel()
        reconnectTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.openSocket()
        }
    }

    // MARK: - Receive loop

    private func startReceiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleReceivedMessage(message)
                    // receive() 只消费一帧，成功后继续下一轮。
                    self.startReceiveLoop()
                case .failure:
                    // 交给 delegate.didCompleteWithError 统一处理，避免双路径重连。
                    break
                }
            }
        }
    }

    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let string):
            text = string
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }
        guard let data = text.data(using: .utf8) else { return }

        // connection.ready 是握手信号，不进入业务事件解码。
        if let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           frame["type"] as? String == "connection.ready" {
            if case .handshaking = state {
                state = .ready
                Log.info(.ws, "connection ready")
                reconnectPolicy.reset()
                startHeartbeat()
                for handler in Array(readyHandlers.values) {
                    handler()
                }
            }
            return
        }

        do {
            let event = try APIClient.jsonDecoder.decode(WSEvent.self, from: data)
            // .unknown 也 dispatch，业务侧可以选择忽略。
            for handler in handlers.values {
                handler(event)
            }
            Log.debug(.ws, "event \(event)")
        } catch {
            // 单帧解码失败不拖垮整条连接。
            Log.warning(.ws, "decode error: \(error.localizedDescription)")
        }
    }
}

extension WebSocketClient {
    /// 客户端唯一会主动发的两类帧：typing.start / typing.stop。设计 §7.8。
    /// 服务端 `server/src/plugins/ws.ts:253-277` 期望平铺 JSON，**不**嵌套 payload。
    ///
    /// **`nonisolated`**：WebSocketClient 整体是 `@MainActor`，但本函数不读写 actor 状态，
    /// 显式 nonisolated 让任何 actor 上下文（包括无 `@MainActor` 的测试）都能直接调用。
    nonisolated static func typingFrameJSON(conversationId: Int, isStart: Bool) throws -> Data {
        let payload: [String: Any] = [
            "type": isStart ? "typing.start" : "typing.stop",
            "conversation_id": conversationId,
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    /// 仅 .ready 状态下发送；其它状态静默丢弃（与 Web `sendWsMessage` 一致）。
    func sendTyping(conversationId: Int, isStart: Bool) {
        guard case .ready = state, let task else { return }
        guard let data = try? Self.typingFrameJSON(
            conversationId: conversationId,
            isStart: isStart
        ),
        let text = String(data: data, encoding: .utf8) else { return }

        task.send(.string(text)) { _ in }
    }
}

#if DEBUG
extension WebSocketClient {
    /// 仅测试用：直接 dispatch 一条 WSEvent 给所有订阅者，不走真实 receive 路径。
    func _dispatchForTesting(_ event: WSEvent) {
        for handler in handlers.values {
            handler(event)
        }
    }

    /// 仅测试用：直接触发 onReady 回调（不切 state 也不 startHeartbeat，只跑 readyHandlers）。
    func _fireReadyForTesting() {
        for handler in Array(readyHandlers.values) {
            handler()
        }
    }
}
#endif

extension WebSocketClient: URLSessionWebSocketDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        // TCP + WS upgrade 成功，等服务端 connection.ready。
        Task { @MainActor in
            if case .connecting = self.state {
                self.state = .handshaking
                Log.info(.ws, "TCP upgraded, waiting connection.ready")
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            self.scheduleReconnect()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let httpStatus = (task.response as? HTTPURLResponse)?.statusCode
        Task { @MainActor in
            if httpStatus == 401 {
                // WS upgrade 401 能在 didComplete 里拿到；此时 token 已失效，不再重连。
                self.shouldReconnect = false
                self.stopHeartbeat()
                self.reconnectTimer?.cancel()
                self.reconnectTimer = nil
                self.closeTaskLocally()
                self.state = .disconnected
                self.onUnauthorized()
                Log.error(.ws, "401 unauthorized, stop reconnect")
                return
            }

            switch self.state {
            case .disconnected, .reconnecting:
                return
            default:
                self.scheduleReconnect()
            }
        }
    }
}
