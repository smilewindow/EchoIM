import Foundation

/// 指数退避 + 抖动 + 无限重试（capped）。线程安全靠外部 @MainActor 持有保证。
/// 设计文档 §7.3。移动网络下“悄悄停止重连”比“持续慢速重试”危险得多（高铁、电梯、长隧道），
/// 故不提供 maxRetries。
final class ReconnectPolicy {
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let jitterRatio: Double
    private var retryCount = 0

    init(baseDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 30.0, jitterRatio: Double = 0.3) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterRatio = jitterRatio
    }

    func nextDelay() -> TimeInterval {
        let exp = min(baseDelay * pow(2.0, Double(retryCount)), maxDelay)
        let jitter = Double.random(in: 0...(exp * jitterRatio))
        retryCount += 1
        return exp + jitter
    }

    func reset() {
        retryCount = 0
    }
}
