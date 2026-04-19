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
        baseURL.appendingPathComponent(path)
    }

    enum Auth {
        static let login = "api/auth/login"
        static let register = "api/auth/register"
    }
}
