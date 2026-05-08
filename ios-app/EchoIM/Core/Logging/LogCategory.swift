import Foundation

enum LogCategory: String, CaseIterable {
    case network    // APIClient HTTP requests/responses
    case ws         // WebSocket lifecycle and events
    case auth       // Login/logout/token
    case cache      // SwiftData read/write
    case ui         // Page navigation
    case app        // AppContainer session lifecycle
}
