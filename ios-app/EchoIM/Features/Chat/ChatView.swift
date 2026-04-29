import PhotosUI
import SwiftUI
import UIKit

struct ChatView: View {
    private static let bottomAnchorId = "chatBottomAnchor"

    @State private var vm: ChatViewModel
    @State private var draft = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var lightboxBubble: LocalMessage?
    @FocusState private var isInputFocused: Bool
    private let presenceStore: PresenceStore?

    init(
        route: ChatRoute,
        currentUserId: Int,
        messageRepo: MessageRepository,
        messageStore: MessageStore?,
        metaStore: ConversationMetaStore?,
        wsClient: WebSocketClient?,
        conversationRepository: ConversationRepository?,
        uploadRepo: UploadRepository,
        presenceStore: PresenceStore? = nil,
        typingStore: TypingStore? = nil,
        typingSender: @escaping @MainActor (Int, Bool) -> Void = { _, _ in },
        tokenProvider: @escaping @MainActor () -> String?
    ) {
        _vm = State(
            wrappedValue: ChatViewModel(
                route: route,
                currentUserId: currentUserId,
                messageRepo: messageRepo,
                wsClient: wsClient,
                conversationRepository: conversationRepository,
                messageStore: messageStore,
                metaStore: metaStore,
                uploadRepo: uploadRepo,
                typingStore: typingStore,
                typingSender: typingSender,
                tokenProvider: tokenProvider
            )
        )
        self.presenceStore = presenceStore
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                principalTitle
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    isInputFocused = false
                }
                .accessibilityIdentifier("chatKeyboardDone")
            }
        }
        .task {
            vm.attachWSSubscription()
            await vm.load()
        }
        .onDisappear {
            vm.stopTyping()                  // 不变式 4 触发点 ③
            vm.detachWSSubscription()
        }
        .onChange(of: pickedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await handlePickedItem(newItem)
                pickedItem = nil
            }
        }
        .fullScreenCover(item: $lightboxBubble) { bubble in
            Lightbox(
                localData: bubble.localImageData,
                remoteURL: Endpoints.absolute(bubble.message.mediaUrl),
                onClose: { lightboxBubble = nil }
            )
        }
    }

    private var principalTitle: some View {
        NavigationLink(value: vm.peer) {
            HStack(spacing: 8) {
                AvatarView(profile: vm.peer, size: 28)
                    .accessibilityIdentifier("chatPeerAvatar")

                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text(vm.peer.displayTitle)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        if presenceStore?.isOnline(vm.peer.id) == true {
                            PresenceDot(size: 8)
                                .accessibilityIdentifier("chatPeerOnlineDot")
                        }
                    }
                    if vm.peerIsTyping {
                        Text("正在输入...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("chatPeerTyping")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chatPrincipalTitle")
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if vm.hasMoreOlder {
                        Button {
                            Task {
                                await vm.loadOlder()
                            }
                        } label: {
                            if vm.isLoadingOlder {
                                ProgressView()
                            } else {
                                Text("加载更早消息")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.borderless)
                        .padding(.vertical, 6)
                    }

                    ForEach(vm.messages) { message in
                        MessageBubble(
                            message: message,
                            isSelf: message.message.senderId == vm.currentUserId,
                            onRetry: {
                                Task {
                                    await vm.retry(localId: message.localId)
                                }
                            },
                            onOpenImage: {
                                lightboxBubble = message
                            }
                        )
                        .id(message.localId)
                    }

                    Color.clear
                        .frame(height: 10)
                        .id(Self.bottomAnchorId)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
            .background(Color(uiColor: .systemBackground))
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    isInputFocused = false
                }
            )
            .overlay {
                if vm.phase == .loading, vm.messages.isEmpty {
                    ProgressView()
                }
            }
            .onChange(of: vm.messages.last?.localId) { _, newValue in
                guard newValue != nil else { return }
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            // 锚定列表尾部而不是最后一个气泡，避免底部留白被算丢后看起来差一点。
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .regular))
            }
            .accessibilityLabel(Text("发送图片"))
            .accessibilityIdentifier("chatImagePicker")
            .simultaneousGesture(
                TapGesture().onEnded {
                    isInputFocused = false
                }
            )

            TextField("说点什么...", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onChange(of: draft) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        vm.stopTyping()
                    } else {
                        vm.handleTypingInput()
                    }
                }
                .accessibilityIdentifier("chatInput")

            Button {
                let text = draft
                draft = ""
                Task {
                    await vm.sendText(text)
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSend)
            .accessibilityLabel(Text("发送"))
            .accessibilityIdentifier("chatSend")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        await vm.sendImage(image)
    }
}
