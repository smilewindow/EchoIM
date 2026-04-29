import Foundation
import Observation

@Observable
@MainActor
final class ContactsViewModel {
    private(set) var friends: [Friend] = []
    private(set) var incoming: [FriendRequest] = []
    private(set) var sent: [FriendRequest] = []
    private(set) var history: [FriendRequest] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let friendRepo: FriendRepository
    private let requestRepo: FriendRequestRepository
    private let tokenProvider: () -> String?
    private let haptics: HapticFeedbackProvider

    init(
        friendRepo: FriendRepository,
        requestRepo: FriendRequestRepository,
        tokenProvider: @escaping () -> String?,
        haptics: HapticFeedbackProvider? = nil
    ) {
        self.friendRepo = friendRepo
        self.requestRepo = requestRepo
        self.tokenProvider = tokenProvider
        self.haptics = haptics ?? UIKitHapticFeedback()
    }

    var pendingIncomingCount: Int {
        incoming.count
    }

    func refresh() async {
        guard let token = tokenProvider() else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        async let friendsTask = friendRepo.list(token: token)
        async let incomingTask = requestRepo.listIncoming(token: token)
        async let sentTask = requestRepo.listSent(token: token)
        async let historyTask = requestRepo.listHistory(token: token)

        do {
            // 只有四份数据都成功时才整体提交，避免页面出现部分新、部分旧的混合态。
            let (friends, incoming, sent, history) = try await (
                friendsTask,
                incomingTask,
                sentTask,
                historyTask
            )
            self.friends = friends
            self.incoming = incoming
            self.sent = sent
            self.history = history
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
            _ = try? await (friendsTask, incomingTask, sentTask, historyTask)
        }
    }

    func respond(requestId: Int, accept: Bool) async {
        guard let token = tokenProvider() else {
            return
        }

        do {
            _ = try await requestRepo.respond(id: requestId, accept: accept, token: token)
            if accept {
                haptics.success()
            } else {
                haptics.warning()
            }
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func send(recipientId: Int) async -> Result<Void, Error> {
        guard let token = tokenProvider() else {
            return .failure(APIError.unauthorized)
        }

        do {
            _ = try await requestRepo.send(recipientId: recipientId, token: token)
            await refresh()
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
