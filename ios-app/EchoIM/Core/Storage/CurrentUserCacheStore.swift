import Foundation

/// 当前登录用户资料缓存。只存一条 JSON，避免为 Me 页读启动资料引入 SwiftData schema 迁移。
struct CurrentUserCacheStore {
    private let fileManager: FileManager
    private let baseDirectory: URL

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL = URL.applicationSupportDirectory.appendingPathComponent("EchoIM/users")
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    func load(userId: Int) -> AuthenticatedUser? {
        let url = cacheURL(userId: userId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? APIClient.jsonDecoder.decode(AuthenticatedUser.self, from: data)
    }

    func save(_ user: AuthenticatedUser) {
        let url = cacheURL(userId: user.id)
        let directory = url.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.excludeFromBackup(directory)
            let data = try APIClient.jsonEncoder.encode(user)
            try data.write(to: url, options: .atomic)
        } catch {
            // 缓存失败不应影响登录态；下次联网刷新仍能恢复。
        }
    }

    func delete(userId: Int) {
        try? fileManager.removeItem(at: cacheURL(userId: userId))
    }

    private func cacheURL(userId: Int) -> URL {
        baseDirectory
            .appendingPathComponent("\(userId)")
            .appendingPathComponent("current-user.json")
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
