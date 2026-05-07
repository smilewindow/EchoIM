import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("ContactsViewModel")
struct ContactsViewModelTests {
    final class FakeFriendRepo: FriendRepository {
        var result: Result<[Friend], Error> = .success([])
        private(set) var callCount = 0

        func list(token: String) async throws -> [Friend] {
            callCount += 1
            return try result.get()
        }
    }

    final class FakeRequestRepo: FriendRequestRepository {
        var incomingResult: Result<[FriendRequest], Error> = .success([])
        var sentResult: Result<[FriendRequest], Error> = .success([])
        var historyResult: Result<[FriendRequest], Error> = .success([])
        var sendResult: Result<FriendRequest, Error> = .failure(APIError.invalidResponse)
        var respondResult: Result<FriendRequest, Error> = .failure(APIError.invalidResponse)

        private(set) var sendCalls: [Int] = []
        private(set) var respondCalls: [(Int, Bool)] = []
        private(set) var listCallCounts = (incoming: 0, sent: 0, history: 0)

        func listIncoming(token: String) async throws -> [FriendRequest] {
            listCallCounts.incoming += 1
            return try incomingResult.get()
        }

        func listSent(token: String) async throws -> [FriendRequest] {
            listCallCounts.sent += 1
            return try sentResult.get()
        }

        func listHistory(token: String) async throws -> [FriendRequest] {
            listCallCounts.history += 1
            return try historyResult.get()
        }

        func send(recipientId: Int, token: String) async throws -> FriendRequest {
            sendCalls.append(recipientId)
            return try sendResult.get()
        }

        func respond(id: Int, accept: Bool, token: String) async throws -> FriendRequest {
            respondCalls.append((id, accept))
            return try respondResult.get()
        }
    }

    private func decodeFriendRequest(_ json: String) throws -> FriendRequest {
        try APIClient.jsonDecoder.decode(
            FriendRequest.self,
            from: json.data(using: .utf8)!
        )
    }

    private func makeFriend(id: Int, username: String) -> Friend {
        UserProfile(id: id, username: username, displayName: nil, avatarUrl: nil)
    }

    @Test
    func refreshLoadsFriendsAndIncomingOnly() async throws {
        let friendRepo = FakeFriendRepo()
        friendRepo.result = .success([makeFriend(id: 1, username: "alice")])

        let requestRepo = FakeRequestRepo()
        requestRepo.incomingResult = .success([
            try decodeFriendRequest(
                """
                { "id": 10, "sender_id": 2, "recipient_id": 9, "status": "pending",
                  "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:30:12.345Z",
                  "username": "bob", "display_name": null, "avatar_url": null }
                """
            ),
        ])

        let vm = ContactsViewModel(
            friendRepo: friendRepo,
            requestRepo: requestRepo,
            tokenProvider: { "jwt" }
        )

        await vm.refresh()

        #expect(vm.friends.count == 1)
        #expect(vm.incoming.count == 1)
        #expect(vm.pendingIncomingCount == 1)
        #expect(friendRepo.callCount == 1)
        #expect(requestRepo.listCallCounts.incoming == 1)
        #expect(requestRepo.listCallCounts.sent == 0)
        #expect(requestRepo.listCallCounts.history == 0)
    }

    @Test
    func refreshKeepsFriendsIndependentFromRequestDetailFailure() async {
        let friendRepo = FakeFriendRepo()
        let requestRepo = FakeRequestRepo()
        friendRepo.result = .success([
            makeFriend(id: 1, username: "alice"),
            makeFriend(id: 2, username: "bob"),
        ])
        requestRepo.historyResult = .failure(APIError.invalidResponse)
        let vm = ContactsViewModel(
            friendRepo: friendRepo,
            requestRepo: requestRepo,
            tokenProvider: { "jwt" }
        )

        await vm.refresh()

        #expect(vm.friends.map(\.username) == ["alice", "bob"])
        #expect(requestRepo.listCallCounts.history == 0)
    }

    @Test
    func loadRequestDetailsFetchesIncomingSentAndHistory() async throws {
        let requestRepo = FakeRequestRepo()
        requestRepo.incomingResult = .success([
            try decodeFriendRequest(
                """
                { "id": 10, "sender_id": 2, "recipient_id": 9, "status": "pending",
                  "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:30:12.345Z",
                  "username": "bob", "display_name": null, "avatar_url": null }
                """
            ),
        ])
        requestRepo.sentResult = .success([
            try decodeFriendRequest(
                """
                { "id": 11, "sender_id": 9, "recipient_id": 3, "status": "pending",
                  "created_at": "2026-04-19T08:31:12.345Z", "updated_at": "2026-04-19T08:31:12.345Z",
                  "username": "carol", "display_name": null, "avatar_url": null }
                """
            ),
        ])
        requestRepo.historyResult = .success([
            try decodeFriendRequest(
                """
                { "id": 12, "sender_id": 4, "recipient_id": 9, "status": "accepted",
                  "created_at": "2026-04-19T08:32:12.345Z", "updated_at": "2026-04-19T08:33:12.345Z",
                  "direction": "received", "username": "dave", "display_name": null, "avatar_url": null }
                """
            ),
        ])

        let vm = ContactsViewModel(
            friendRepo: FakeFriendRepo(),
            requestRepo: requestRepo,
            tokenProvider: { "jwt" }
        )

        await vm.loadRequestDetails()

        #expect(vm.incoming.count == 1)
        #expect(vm.sent.count == 1)
        #expect(vm.history.count == 1)
        #expect(requestRepo.listCallCounts.incoming == 1)
        #expect(requestRepo.listCallCounts.sent == 1)
        #expect(requestRepo.listCallCounts.history == 1)
    }

    @Test
    func sendPostsRequestAndRefreshes() async throws {
        let friendRepo = FakeFriendRepo()
        let requestRepo = FakeRequestRepo()
        requestRepo.sendResult = .success(
            try decodeFriendRequest(
                """
                { "id": 20, "sender_id": 9, "recipient_id": 2, "status": "pending",
                  "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:30:12.345Z" }
                """
            )
        )

        let vm = ContactsViewModel(
            friendRepo: friendRepo,
            requestRepo: requestRepo,
            tokenProvider: { "jwt" }
        )

        let result = await vm.send(recipientId: 2)

        if case .failure(let error) = result {
            Issue.record("expected .success, got \(String(describing: error))")
        }
        #expect(requestRepo.sendCalls == [2])
        #expect(requestRepo.listCallCounts.sent == 1)
    }

    @Test
    func sendSurfacesErrorOnFailure() async {
        let requestRepo = FakeRequestRepo()
        requestRepo.sendResult = .failure(APIError.http(status: 409, body: Data()))

        let vm = ContactsViewModel(
            friendRepo: FakeFriendRepo(),
            requestRepo: requestRepo,
            tokenProvider: { "jwt" }
        )

        let result = await vm.send(recipientId: 3)

        if case .success = result {
            Issue.record("expected failure")
        }
        #expect(requestRepo.listCallCounts.sent == 0)
    }

    @Test
    func respondCallsPutAndRefreshes() async throws {
        let requestRepo = FakeRequestRepo()
        requestRepo.respondResult = .success(
            try decodeFriendRequest(
                """
                { "id": 10, "sender_id": 2, "recipient_id": 9, "status": "accepted",
                  "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:31:00.000Z" }
                """
            )
        )

        let vm = ContactsViewModel(
            friendRepo: FakeFriendRepo(),
            requestRepo: requestRepo,
            tokenProvider: { "jwt" }
        )

        await vm.respond(requestId: 10, accept: true)

        #expect(requestRepo.respondCalls.count == 1)
        #expect(requestRepo.respondCalls[0].0 == 10)
        #expect(requestRepo.respondCalls[0].1 == true)
        #expect(requestRepo.listCallCounts.incoming == 1)
    }

    @Test
    func refreshNoOpWithoutToken() async {
        let friendRepo = FakeFriendRepo()
        let requestRepo = FakeRequestRepo()
        let vm = ContactsViewModel(
            friendRepo: friendRepo,
            requestRepo: requestRepo,
            tokenProvider: { nil }
        )

        await vm.refresh()

        #expect(friendRepo.callCount == 0)
        #expect(requestRepo.listCallCounts.incoming == 0)
    }
}
