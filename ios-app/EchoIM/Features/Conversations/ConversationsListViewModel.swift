import Foundation
import Observation

enum ConversationsPhase: Equatable, CustomStringConvertible {
    case idle
    case loading
    case loaded
    case unauthenticated
    case error(String)

    var description: String {
        switch self {
        case .idle:
            "idle"
        case .loading:
            "loading"
        case .loaded:
            "loaded"
        case .unauthenticated:
            "unauthenticated"
        case .error(let message):
            "error(\(message))"
        }
    }
}

@Observable
@MainActor
final class ConversationsListViewModel {
    private(set) var conversations: [Conversation] = []
    private(set) var phase: ConversationsPhase = .idle

    private let repository: ConversationRepository
    private let tokenProvider: () -> String?

    init(
        repository: ConversationRepository,
        tokenProvider: @escaping () -> String?
    ) {
        self.repository = repository
        self.tokenProvider = tokenProvider
    }

    func load() async {
        if phase == .loading {
            return
        }

        guard let token = tokenProvider() else {
            phase = .unauthenticated
            return
        }

        phase = .loading

        do {
            conversations = try await repository.list(token: token)
            phase = .loaded
        } catch {
            phase = .error(String(describing: error))
        }
    }

    func refresh() async {
        guard let token = tokenProvider() else {
            phase = .unauthenticated
            return
        }

        do {
            conversations = try await repository.list(token: token)
            phase = .loaded
        } catch {
            phase = .error(String(describing: error))
        }
    }
}
