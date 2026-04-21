import Testing
import Foundation
@testable import EchoIM

@Suite("ReconnectPolicy")
struct ReconnectPolicyTests {
    @Test func firstDelayIsOneSecondPlusJitter() {
        let policy = ReconnectPolicy()
        let d = policy.nextDelay()
        // exp = 1s；jitter 上限 0.3s → 区间 [1.0, 1.3]
        #expect(d >= 1.0)
        #expect(d <= 1.3)
    }

    @Test func exponentialUpToThirtyCap() {
        let policy = ReconnectPolicy()
        // 不考虑 jitter，期望 exp 序列：1, 2, 4, 8, 16, 30, 30, 30, ...
        let expExpected: [Double] = [1, 2, 4, 8, 16, 30, 30, 30, 30, 30]
        for (i, expected) in expExpected.enumerated() {
            let d = policy.nextDelay()
            let upperBound = expected + expected * 0.3 + 0.0001
            #expect(d >= expected)
            #expect(d <= upperBound, "attempt \(i): got \(d), expected ≤ \(upperBound)")
        }
    }

    @Test func resetReturnsToBase() {
        let policy = ReconnectPolicy()
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        policy.reset()
        let d = policy.nextDelay()
        #expect(d <= 1.3)   // 回到 base 档
    }
}
