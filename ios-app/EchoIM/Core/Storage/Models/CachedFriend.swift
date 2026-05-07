import Foundation
import SwiftData

@Model
final class CachedFriend {
    @Attribute(.unique) var userId: Int
    var username: String
    var displayName: String?
    var avatarUrl: String?

    init(userId: Int, username: String, displayName: String? = nil, avatarUrl: String? = nil) {
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }

    func toUserProfile() -> UserProfile {
        UserProfile(
            id: userId,
            username: username,
            displayName: displayName,
            avatarUrl: avatarUrl
        )
    }
}
