import Foundation

struct LogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let file: String      // filename without path and .swift extension
    let line: Int

    init(level: LogLevel, category: LogCategory, message: String, file: String, line: Int) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.category = category
        self.message = message
        self.file = file
        self.line = line
    }
}
