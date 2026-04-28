import Foundation
import Observation

enum ProfileEditUploadStatus: Equatable {
    case idle
    case uploading
}

enum ProfileEditSaveStatus: Equatable {
    case idle
    case saving
}

@Observable
@MainActor
final class ProfileEditViewModel {
    // 表单稿
    var displayNameDraft: String = ""

    // 网络飞行状态
    private(set) var saveStatus: ProfileEditSaveStatus = .idle
    private(set) var uploadStatus: ProfileEditUploadStatus = .idle
    private(set) var uploadError: String?

    // 依赖（全部通过闭包/协议注入，便于单测）
    private let currentUser: @MainActor () -> AuthenticatedUser?
    private let currentUserSetter: @MainActor (AuthenticatedUser) -> Void
    private let tokenProvider: @MainActor () -> String?
    private let userRepo: UserRepository
    private let uploadRepo: UploadRepository
    private let refreshCurrentUser: @MainActor () async -> Void
    private let onUnauthorized: @MainActor () async -> Void

    init(
        currentUser: @escaping @MainActor () -> AuthenticatedUser?,
        currentUserSetter: @escaping @MainActor (AuthenticatedUser) -> Void,
        tokenProvider: @escaping @MainActor () -> String?,
        userRepo: UserRepository,
        uploadRepo: UploadRepository,
        refreshCurrentUser: @escaping @MainActor () async -> Void,
        onUnauthorized: @escaping @MainActor () async -> Void
    ) {
        self.currentUser = currentUser
        self.currentUserSetter = currentUserSetter
        self.tokenProvider = tokenProvider
        self.userRepo = userRepo
        self.uploadRepo = uploadRepo
        self.refreshCurrentUser = refreshCurrentUser
        self.onUnauthorized = onUnauthorized
    }

    /// View 出现时调用一次，把 currentUser.displayName 拷进 draft。
    func load() {
        let raw = currentUser()?.displayName ?? ""
        displayNameDraft = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 已有 displayName（去 trim）== 当前 currentUser.displayName 时，保存按钮禁用。
    /// 任一网络飞行中也禁用（不变式 3）。
    /// **关键归一化**：currentUser.displayName 是 String?，draft 是 String。如果直接
    /// `trimmedDraft != currentUser()?.displayName` 比较，nil 会被 Swift 当成与 "" 不等
    /// （Optional.none ≠ Optional.some("")），导致 displayName 为 nil 时 canSave 永远 true。
    /// 必须先把当前值归一化成"trim 过的 String"再比。
    var canSave: Bool {
        guard saveStatus == .idle, uploadStatus == .idle else { return false }
        return trimmedDraft != normalizedCurrentDisplayName
    }

    /// 头像加载预览：currentUser.avatarUrl（上传成功后由 refreshCurrentUser 刷新；本端不缓存 URL）。
    var avatarUrl: String? { currentUser()?.avatarUrl }

    /// 提交 displayName 修改。draft 与现值（归一化后）一致时静默返回（不变式 2）。
    func save() async throws {
        guard saveStatus == .idle else { return }
        let trimmed = trimmedDraft
        guard trimmed != normalizedCurrentDisplayName else { return }
        guard let token = tokenProvider() else { return }

        saveStatus = .saving
        defer { saveStatus = .idle }

        do {
            let updated = try await userRepo.updateProfile(displayName: trimmed, token: token)
            currentUserSetter(updated)
        } catch APIError.unauthorized {
            await onUnauthorized()
            throw APIError.unauthorized
        }
    }

    /// 上传头像：成功后调 refreshCurrentUser 拉一次 GET /me 同步 currentUser（不变式 4）。
    func uploadAvatar(data: Data) async throws {
        guard uploadStatus == .idle else { return }
        guard let token = tokenProvider() else { return }

        uploadStatus = .uploading
        uploadError = nil
        defer { uploadStatus = .idle }

        do {
            _ = try await uploadRepo.uploadAvatar(data: data, token: token)
            await refreshCurrentUser()
        } catch APIError.unauthorized {
            await onUnauthorized()
            throw APIError.unauthorized
        } catch {
            uploadError = String(describing: error)
            throw error
        }
    }

    private var trimmedDraft: String {
        displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 把 currentUser.displayName（Optional<String>）归一化成 trim 过的 String，
    /// 让 canSave / save 用同一基准比较 draft（也是 String）。nil 与空字符串都映射到 ""。
    private var normalizedCurrentDisplayName: String {
        currentUser()?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
