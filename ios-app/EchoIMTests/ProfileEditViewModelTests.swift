import Foundation
import Testing
@testable import EchoIM

// MARK: - Stub repositories

@MainActor
private final class StubUserRepository: UserRepository {
    var fetchMeStub: ((String) async throws -> AuthenticatedUser)?
    var searchStub: ((String, String) async throws -> [UserProfile])?
    var updateProfileStub: ((String, String) async throws -> AuthenticatedUser)?

    func fetchMe(token: String) async throws -> AuthenticatedUser {
        try await (fetchMeStub ?? { _ in throw APIError.invalidResponse })(token)
    }

    func searchUsers(query: String, token: String) async throws -> [UserProfile] {
        try await (searchStub ?? { _, _ in [] })(query, token)
    }

    func updateProfile(displayName: String, token: String) async throws -> AuthenticatedUser {
        try await (updateProfileStub ?? { _, _ in throw APIError.invalidResponse })(displayName, token)
    }
}

@MainActor
private final class StubUploadRepository: UploadRepository {
    var uploadMessageImageStub: ((Data, String) async throws -> UploadedMessageImage)?
    var uploadAvatarStub: ((Data, String) async throws -> String)?

    func uploadMessageImage(data: Data, token: String) async throws -> UploadedMessageImage {
        try await (uploadMessageImageStub ?? { _, _ in throw APIError.invalidResponse })(data, token)
    }

    func uploadAvatar(data: Data, token: String) async throws -> String {
        try await (uploadAvatarStub ?? { _, _ in throw APIError.invalidResponse })(data, token)
    }
}

// MARK: - Tests

@MainActor
@Suite("ProfileEditViewModel")
struct ProfileEditViewModelTests {
    private static let baseUser = AuthenticatedUser(
        id: 7,
        username: "alice",
        email: "a@x.com",
        displayName: "Alice",
        avatarUrl: "/uploads/avatars/7-old.jpg"
    )

    private func makeVM(
        currentUser: AuthenticatedUser = baseUser,
        userRepo: StubUserRepository? = nil,
        uploadRepo: StubUploadRepository? = nil,
        token: String? = "tok",
        currentUserSetter: @escaping @MainActor (AuthenticatedUser) -> Void = { _ in },
        refreshCurrentUser: @escaping @MainActor () async -> Void = {},
        onUnauthorized: @escaping @MainActor () async -> Void = {}
    ) -> ProfileEditViewModel {
        ProfileEditViewModel(
            currentUser: { currentUser },
            currentUserSetter: currentUserSetter,
            tokenProvider: { token },
            userRepo: userRepo ?? StubUserRepository(),
            uploadRepo: uploadRepo ?? StubUploadRepository(),
            refreshCurrentUser: refreshCurrentUser,
            onUnauthorized: onUnauthorized
        )
    }

    @Test
    func loadCopiesDisplayNameFromCurrentUser() {
        let vm = makeVM()
        vm.load()
        #expect(vm.displayNameDraft == "Alice")
        #expect(vm.canSave == false, "未改动且无飞行任务，保存不可点（与现值相同）")
    }

    @Test
    func loadFallsBackToUsernameWhenDisplayNameNil() {
        let user = AuthenticatedUser(
            id: 8, username: "bob", email: "b@x.com",
            displayName: nil, avatarUrl: nil
        )
        let vm = makeVM(currentUser: user)
        vm.load()
        // 当 displayName 是 nil/空，draft 也是空字符串；UI placeholder 才能显示 username。
        #expect(vm.displayNameDraft == "")
    }

    @Test
    func canSaveIsFalseForNilDisplayNameWithEmptyDraft() {
        let user = AuthenticatedUser(
            id: 8, username: "bob", email: "b@x.com",
            displayName: nil, avatarUrl: nil
        )
        let vm = makeVM(currentUser: user)
        vm.load()
        #expect(vm.displayNameDraft == "")
        #expect(vm.canSave == false)
    }

    @Test
    func canSaveIsTrueOnceDraftDiffersFromCurrent() {
        let vm = makeVM()
        vm.load()
        vm.displayNameDraft = "Alice 2"
        #expect(vm.canSave == true)
    }

    @Test
    func saveSendsTrimmedDraftAndUpdatesCurrentUser() async throws {
        let userRepo = StubUserRepository()
        let updatedUser = AuthenticatedUser(
            id: 7, username: "alice", email: "a@x.com",
            displayName: "Alice 2", avatarUrl: "/uploads/avatars/7-old.jpg"
        )
        var captured: (displayName: String, token: String)?
        userRepo.updateProfileStub = { name, token in
            captured = (name, token)
            return updatedUser
        }
        var setterCalled: AuthenticatedUser?
        let vm = makeVM(
            userRepo: userRepo,
            currentUserSetter: { setterCalled = $0 }
        )
        vm.load()
        vm.displayNameDraft = "  Alice 2  "      // 前后空格

        try await vm.save()

        #expect(captured?.displayName == "Alice 2", "VM 应在发请求前 trim")
        #expect(captured?.token == "tok")
        #expect(setterCalled?.displayName == "Alice 2")
        #expect(vm.saveStatus == .idle)
    }

    @Test
    func saveSkipsRequestWhenDraftEqualsCurrentDisplayName() async throws {
        let userRepo = StubUserRepository()
        var called = false
        userRepo.updateProfileStub = { _, _ in
            called = true
            throw APIError.invalidResponse        // 不应触发
        }
        let vm = makeVM(userRepo: userRepo)
        vm.load()
        // draft 没动；canSave 也是 false，但即使外部强行调 save，也应静默返回（不变式 2）。
        try await vm.save()
        #expect(called == false)
    }

    @Test
    func saveSkipsRequestForNilDisplayNameWithEmptyDraft() async throws {
        let user = AuthenticatedUser(
            id: 8, username: "bob", email: "b@x.com",
            displayName: nil, avatarUrl: nil
        )
        let userRepo = StubUserRepository()
        var called = false
        userRepo.updateProfileStub = { _, _ in
            called = true
            throw APIError.invalidResponse
        }
        let vm = makeVM(currentUser: user, userRepo: userRepo)
        vm.load()
        try await vm.save()
        #expect(called == false)
    }

    @Test
    func save401TriggersOnUnauthorized() async throws {
        let userRepo = StubUserRepository()
        userRepo.updateProfileStub = { _, _ in throw APIError.unauthorized }
        var unauthorizedCalled = false
        let vm = makeVM(
            userRepo: userRepo,
            onUnauthorized: { unauthorizedCalled = true }
        )
        vm.load()
        vm.displayNameDraft = "X"

        do {
            try await vm.save()
            Issue.record("expected APIError.unauthorized to bubble")
        } catch APIError.unauthorized {
            // expected
        }
        #expect(unauthorizedCalled == true)
        #expect(vm.saveStatus == .idle)
    }

    @Test
    func uploadAvatarCallsRefreshOnSuccess() async throws {
        let uploadRepo = StubUploadRepository()
        uploadRepo.uploadAvatarStub = { _, _ in "/uploads/avatars/7-new.jpg" }
        var refreshCalled = false
        let vm = makeVM(
            uploadRepo: uploadRepo,
            refreshCurrentUser: { refreshCalled = true }
        )
        vm.load()

        try await vm.uploadAvatar(data: Data([0xFF, 0xD8]))
        #expect(refreshCalled == true)
        #expect(vm.uploadStatus == .idle)
        #expect(vm.uploadError == nil)
    }

    @Test
    func uploadAvatar401TriggersOnUnauthorized() async throws {
        let uploadRepo = StubUploadRepository()
        uploadRepo.uploadAvatarStub = { _, _ in throw APIError.unauthorized }
        var unauthorizedCalled = false
        let vm = makeVM(
            uploadRepo: uploadRepo,
            onUnauthorized: { unauthorizedCalled = true }
        )
        vm.load()

        do {
            try await vm.uploadAvatar(data: Data([0xFF]))
            Issue.record("expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        }
        #expect(unauthorizedCalled == true)
        #expect(vm.uploadStatus == .idle)
    }

    @Test
    func uploadAvatarFailureLeavesRecoverableState() async throws {
        let uploadRepo = StubUploadRepository()
        uploadRepo.uploadAvatarStub = { _, _ in throw APIError.http(status: 500, body: Data()) }
        let vm = makeVM(uploadRepo: uploadRepo)
        vm.load()

        do {
            try await vm.uploadAvatar(data: Data([0xFF]))
            Issue.record("expected APIError.http")
        } catch APIError.http {
            // expected
        }
        #expect(vm.uploadStatus == .idle, "失败后必须复位状态，UI 才能再次允许选图")
        #expect(vm.uploadError != nil, "失败后应保留错误以供 UI 展示")
    }

    @Test
    func canSaveIsFalseWhileUploading() async throws {
        // 用 signal stream 明确等 stub 开始后再断言；避免依赖 Task.yield() 个数的 flaky 问题。
        let uploadRepo = StubUploadRepository()
        let (signalStream, signalCont) = AsyncStream<Void>.makeStream(of: Void.self)
        let (resumeStream, resumeCont) = AsyncStream<String>.makeStream(of: String.self)
        uploadRepo.uploadAvatarStub = { _, _ in
            signalCont.yield(())          // 通知：uploadStatus 已设为 .uploading，stub 即将挂起
            for await value in resumeStream { return value }
            throw APIError.invalidResponse
        }
        let vm = makeVM(uploadRepo: uploadRepo)
        vm.load()
        vm.displayNameDraft = "Alice 2"
        #expect(vm.canSave == true)

        async let upload: Void = vm.uploadAvatar(data: Data([0xFF]))
        // 等 stub 发出信号（等价于"uploadStatus == .uploading 已写入，stub 已挂起"）
        for await _ in signalStream { break }

        #expect(vm.uploadStatus == .uploading)
        #expect(vm.canSave == false, "上传中保存按钮必须禁用（不变式 3）")

        resumeCont.yield("/uploads/avatars/7-new.jpg")
        resumeCont.finish()
        try await upload
        #expect(vm.uploadStatus == .idle)
        #expect(vm.canSave == true)
    }
}
