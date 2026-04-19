import Foundation
import KeychainAccess

struct StoredToken: Equatable {
    let token: String
    let userId: Int
}

final class KeychainTokenStore {
    private let keychain: Keychain
    private let tokenKey = "jwt"
    private let userIdKey = "userId"

    init(service: String = "com.echoim.app") {
        self.keychain = Keychain(service: service)
    }

    func save(token: String, userId: Int) throws {
        try keychain.set(token, key: tokenKey)
        try keychain.set(String(userId), key: userIdKey)
    }

    func load() throws -> StoredToken? {
        guard let token = try keychain.get(tokenKey),
              let userIdString = try keychain.get(userIdKey),
              let userId = Int(userIdString) else {
            return nil
        }

        return StoredToken(token: token, userId: userId)
    }

    func clear() throws {
        try keychain.remove(tokenKey)
        try keychain.remove(userIdKey)
    }
}
