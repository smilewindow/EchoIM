import PhotosUI
import SwiftUI
import UIKit

struct ProfileEditView: View {
    @State private var vm: ProfileEditViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var saveErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let username: String

    init(
        username: String,
        viewModel: ProfileEditViewModel
    ) {
        self.username = username
        self._vm = State(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                avatarRow
            } header: {
                Text("头像")
            } footer: {
                if let error = vm.uploadError {
                    Text("上传失败：\(error)")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("profileEditUploadError")
                } else {
                    Text("从相册选择一张图片，自动裁剪为 400×400 头像。")
                }
            }

            Section {
                TextField(username, text: $vm.displayNameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profileEditDisplayName")
            } header: {
                Text("显示名称")
            } footer: {
                Text("好友看到的名字。留空将显示用户名 @\(username)。")
            }
        }
        .navigationTitle("编辑资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: handleSaveTapped) {
                    if vm.saveStatus == .saving {
                        ProgressView()
                    } else {
                        Text("保存")
                    }
                }
                .disabled(!vm.canSave)
                .accessibilityIdentifier("profileEditSaveButton")
            }
        }
        .task { vm.load() }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                await handlePickedItem(newItem)
                pickerItem = nil
            }
        }
        .alert(
            "保存失败",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    // MARK: - Avatar row

    @ViewBuilder
    private var avatarRow: some View {
        HStack(spacing: 16) {
            avatarPreview
                .frame(width: 72, height: 72)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        vm.uploadStatus == .uploading ? "上传中…" : "更换头像",
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
                .disabled(vm.uploadStatus == .uploading)
                .accessibilityIdentifier("profileEditPickAvatar")

                Text("JPEG / PNG / HEIC，自动压缩为 400×400")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let urlString = vm.avatarUrl, let url = Endpoints.absolute(urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    Color(uiColor: .secondarySystemBackground)
                @unknown default:
                    Color(uiColor: .secondarySystemBackground)
                }
            }
        } else {
            Color(uiColor: .secondarySystemBackground)
                .overlay {
                    Text(initials)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var initials: String {
        let trimmed = vm.displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? username : trimmed
        return String(base.prefix(2)).uppercased()
    }

    // MARK: - Actions

    private func handleSaveTapped() {
        Task { @MainActor in
            do {
                try await vm.save()
                dismiss()
            } catch APIError.unauthorized {
                // VM 已触发 onUnauthorized，外层 RootView 会切回 Login；不再展示 alert。
            } catch {
                saveErrorMessage = String(describing: error)
            }
        }
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: raw),
              let compressed = AvatarImageCompressor.compressForUpload(image) else {
            return
        }
        do {
            try await vm.uploadAvatar(data: compressed)
        } catch {
            // VM 已经把错误存进 vm.uploadError；UI 在 footer 上展示。
        }
    }
}
