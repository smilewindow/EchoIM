import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("ConversationsListViewModel")
struct ConversationsListViewModelTests {
    final class FakeRepo: ConversationRepository {
        var pendingResult: Result<[Conversation], Error>

        init(_ result: Result<[Conversation], Error>) {
            self.pendingResult = result
        }

        func list(token: String) async throws -> [Conversation] {
            try pendingResult.get()
        }
    }

    private func makeConversation(
        id: Int,
        peerName: String,
        unread: Int = 0,
        ts: String = "2026-04-18T13:00:00.000Z"
    ) throws -> Conversation {
        let json = """
        {
          "id": \(id),
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": \(id + 100),
          "peer_username": "\(peerName)",
          "peer_display_name": null,
          "peer_avatar_url": null,
          "last_message_body": "hi",
          "last_message_type": "text",
          "last_message_sender_id": \(id + 100),
          "last_message_at": "\(ts)",
          "last_read_message_id": null,
          "unread_count": \(unread)
        }
        """.data(using: .utf8)!

        return try APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }

    @Test
    func loadPopulatesConversations() async throws {
        let c1 = try makeConversation(id: 1, peerName: "alice", unread: 1)
        let vm = ConversationsListViewModel(
            repository: FakeRepo(.success([c1])),
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        await vm.load()

        #expect(vm.phase == .loaded)
        #expect(vm.conversations.count == 1)
        #expect(vm.conversations[0].peer.username == "alice")
    }

    @Test
    func loadPropagatesErrorPhase() async {
        let vm = ConversationsListViewModel(
            repository: FakeRepo(.failure(APIError.invalidResponse)),
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        await vm.load()

        if case .error = vm.phase {
            return
        }
        Issue.record("expected .error, got \(String(describing: vm.phase))")
    }

    @Test
    func refreshReplacesExisting() async throws {
        let old = try makeConversation(id: 1, peerName: "old")
        let repo = FakeRepo(.success([old]))
        let vm = ConversationsListViewModel(
            repository: repo,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        await vm.load()
        #expect(vm.conversations[0].peer.username == "old")

        let new = try makeConversation(id: 2, peerName: "new")
        repo.pendingResult = .success([new])
        await vm.refresh()

        #expect(vm.conversations.count == 1)
        #expect(vm.conversations[0].peer.username == "new")
    }

    @Test
    func loadNoOpWithoutToken() async {
        let repo = FakeRepo(.success([]))
        let vm = ConversationsListViewModel(
            repository: repo,
            metaStore: nil,
            tokenProvider: { nil }
        )

        await vm.load()

        #expect(vm.phase == .unauthenticated)
    }
}
