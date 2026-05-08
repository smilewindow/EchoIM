import Foundation

enum LogCategory: String, CaseIterable {
    case network    // APIClient HTTP requests/responses
    case ws         // WebSocket lifecycle and events
    case auth       // Login/logout/token
    case app        // AppContainer session lifecycle
}
