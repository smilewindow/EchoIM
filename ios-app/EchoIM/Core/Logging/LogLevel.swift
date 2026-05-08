import OSLog

enum LogLevel {
    case debug
    case info
    case warning
    case error

    var osLogType: OSLogType {
        switch self {
        case .debug:   return .debug
        case .info:    return .info
        case .warning: return .default
        case .error:   return .error
        }
    }
}
