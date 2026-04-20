import Foundation

enum MainTab: Hashable, CaseIterable {
    case chats
    case contacts
    case me

    var titleKey: String {
        switch self {
        case .chats:
            "tab.chats"
        case .contacts:
            "tab.contacts"
        case .me:
            "tab.me"
        }
    }

    var systemImage: String {
        switch self {
        case .chats:
            "bubble.left.and.bubble.right"
        case .contacts:
            "person.2"
        case .me:
            "person.crop.circle"
        }
    }
}
