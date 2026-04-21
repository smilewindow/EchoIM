import Foundation

enum Endpoints {
    static let baseURL: URL = {
        // P1 默认连本机后端；后续可通过 Info 配置切到测试或正式环境。
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: "EchoIMBaseURL") as? String,
           let url = URL(string: rawValue) {
            return url
        }

        return URL(string: "http://localhost:3000")!
    }()

    static func url(_ path: String) -> URL {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            preconditionFailure("invalid endpoint path: \(path) relative to \(baseURL)")
        }

        return url
    }

    /// 服务端返回的头像/媒体地址通常是 `/uploads/...` 这种相对根路径，
    /// 这里统一补齐成绝对 URL，避免视图层重复处理。
    static func absolute(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else {
            return nil
        }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }

        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    /// 把 baseURL 的 http/https scheme 换成 ws/wss，拼出带 token 的 /ws url。
    static func webSocketURL(token: String) -> URL? {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // baseURL 的 path 通常是 "/"；WS 走固定 /ws。
        comps.path = "/ws"
        switch comps.scheme?.lowercased() {
        case "https":
            comps.scheme = "wss"
        case "http":
            comps.scheme = "ws"
        default:
            return nil
        }
        comps.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps.url
    }

    enum Auth {
        static let login = "api/auth/login"
        static let register = "api/auth/register"
    }

    enum Users {
        static let me = "api/users/me"
        static let search = "api/users/search"
    }

    enum Friends {
        static let list = "api/friends"
    }

    enum FriendRequests {
        static let base = "api/friend-requests"
        static let sent = "api/friend-requests/sent"
        static let history = "api/friend-requests/history"

        static func respond(id: Int) -> String {
            "api/friend-requests/\(id)"
        }
    }

    enum Conversations {
        static let list = "api/conversations"

        /// GET /api/conversations/:id/messages?before|after=...
        static func messages(conversationId: Int) -> String {
            "api/conversations/\(conversationId)/messages"
        }

        /// PUT /api/conversations/:id/read
        static func read(conversationId: Int) -> String {
            "api/conversations/\(conversationId)/read"
        }
    }

    enum Messages {
        static let base = "api/messages"
    }
}
