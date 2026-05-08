import OSLog
import Foundation

@MainActor
enum Log {
    // One os.Logger per category; subsystem = bundle identifier
    private static let loggers: [LogCategory: Logger] = {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.echoim"
        return Dictionary(uniqueKeysWithValues: LogCategory.allCases.map {
            ($0, Logger(subsystem: subsystem, category: $0.rawValue))
        })
    }()

    static func info(
        _ category: LogCategory,
        _ message: String,
        file: String = #fileID,
        line: Int = #line
    ) {
        write(level: .info, category: category, message: message, file: file, line: line)
    }

    static func debug(
        _ category: LogCategory,
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line
    ) {
        #if DEBUG
        write(level: .debug, category: category, message: message(), file: file, line: line)
        #endif
    }

    static func warning(
        _ category: LogCategory,
        _ message: String,
        file: String = #fileID,
        line: Int = #line
    ) {
        write(level: .warning, category: category, message: message, file: file, line: line)
    }

    static func error(
        _ category: LogCategory,
        _ message: String,
        file: String = #fileID,
        line: Int = #line
    ) {
        write(level: .error, category: category, message: message, file: file, line: line)
    }

    // Used by APIClient: body logging (DEBUG only, redacted)
    static func redactBody(_ body: String) -> String {
        var result = body.replacingOccurrences(
            of: #""password"\s*:\s*"[^"]*""#,
            with: #""password":"***""#,
            options: .regularExpression
        )
        let limit = 1000
        if result.count > limit {
            result = String(result.prefix(limit)) + "…"
        }
        return result
    }

    private static func write(
        level: LogLevel,
        category: LogCategory,
        message: String,
        file: String,
        line: Int
    ) {
        // Extract filename: "EchoIM/Core/Networking/APIClient.swift" → "APIClient"
        let filename = file.split(separator: "/").last.map { String($0) } ?? file
        let shortFile = filename.hasSuffix(".swift")
            ? String(filename.dropLast(6))
            : filename

        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            file: shortFile,
            line: line
        )
        LogStore.shared.append(entry)

        let logger = loggers[category]
        let formatted = "\(shortFile):\(line)  [\(category.rawValue)]  \(message)"
        switch level {
        case .debug:   logger?.debug("\(formatted, privacy: .public)")
        case .info:    logger?.info("\(formatted, privacy: .public)")
        case .warning: logger?.warning("\(formatted, privacy: .public)")
        case .error:   logger?.error("\(formatted, privacy: .public)")
        }
    }
}
