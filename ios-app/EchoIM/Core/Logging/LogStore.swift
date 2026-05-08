import Foundation
import Observation

@Observable
@MainActor
final class LogStore {
    static let shared = LogStore()

    private(set) var entries: [LogEntry] = []
    private let capacity = 500

    private init() {}

    func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }
}
