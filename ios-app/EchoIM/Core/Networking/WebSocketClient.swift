import Foundation
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
    private var shouldReconnect = false

    init(
        tokenProvider: @escaping @MainActor () -> String?,
        onUnauthorized: @escaping @MainActor () -> Void
    ) {
        self.tokenProvider = tokenProvider
        self.onUnauthorized = onUnauthorized
        self.reconnectPolicy = ReconnectPolicy()
        super.init()
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

        let newTask = session.webSocketTask(with: url)
        task = newTask
        newTask.resume()
        startReceiveLoop()
    }

    private func closeTaskLocally() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
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
                reconnectPolicy.reset()
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
        } catch {
            // 单帧解码失败不拖垮整条连接；后续接日志系统时记录 warning。
        }
    }
}

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
        // Task 6 会在这里加 401 分支；本 Task 只走通用重连。
        Task { @MainActor in
            switch self.state {
            case .disconnected, .reconnecting:
                return
            default:
                self.scheduleReconnect()
            }
        }
    }
}
