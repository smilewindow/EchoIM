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

        async let friendsRefresh: Void = refreshFriends(token: token)
        async let incomingRefresh: Void = refreshIncoming(token: token)
        _ = await (friendsRefresh, incomingRefresh)
    }

    func loadRequestDetails() async {
        guard let token = tokenProvider() else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        await loadRequestDetails(token: token)
    }

    func loadSentRequests() async {
        guard let token = tokenProvider() else {
            return
        }

        do {
            sent = try await requestRepo.listSent(token: token)
        } catch {
            // silently ignored
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
            async let friendsRefresh: Void = refreshFriends(token: token)
            async let requestRefresh: Void = loadRequestDetails(token: token)
            _ = await (friendsRefresh, requestRefresh)
        } catch {
            // silently ignored
        }
    }

    func send(recipientId: Int) async -> Result<Void, Error> {
        guard let token = tokenProvider() else {
            return .failure(APIError.unauthorized)
        }

        do {
            _ = try await requestRepo.send(recipientId: recipientId, token: token)
            await loadSentRequests()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func refreshFriends(token: String) async {
        do {
            friends = try await friendRepo.list(token: token)
        } catch {
            // silently ignored
        }
    }

    private func refreshIncoming(token: String) async {
        do {
            incoming = try await requestRepo.listIncoming(token: token)
        } catch {
            // silently ignored
        }
    }

    private func loadRequestDetails(token: String) async {
        async let incomingTask = requestRepo.listIncoming(token: token)
        async let sentTask = requestRepo.listSent(token: token)
        async let historyTask = requestRepo.listHistory(token: token)

        do {
            // 好友申请页保持三块申请数据同批更新，避免 sheet 内出现新旧混合态。
            let (incoming, sent, history) = try await (incomingTask, sentTask, historyTask)
            self.incoming = incoming
            self.sent = sent
            self.history = history
        } catch {
            // silently ignored
        }
    }
}
