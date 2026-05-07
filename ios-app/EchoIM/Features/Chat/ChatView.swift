import PhotosUI
import SwiftUI
import UIKit

struct ChatView: View {
    private static let bottomAnchorId = "chatBottomAnchor"

    @State private var vm: ChatViewModel
    @State private var draft = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var lightboxBubble: LocalMessage?
    @State private var initialScrollPolicy = ChatInitialScrollPolicy()
    @State private var initialCatchUpScrollTrigger = 0
    @FocusState private var isInputFocused: Bool
    private let presenceStore: PresenceStore?
    private let onNavigateToPeer: ((UserProfile) -> Void)?

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
        tokenProvider: @escaping @MainActor () -> String?,
        onNavigateToPeer: ((UserProfile) -> Void)? = nil
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
        self.onNavigateToPeer = onNavigateToPeer
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
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
        .toolbarBackground(Color.echoInteractive, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            vm.attachWSSubscription()
            await vm.load()
            if initialScrollPolicy.markInitialLoadFinished() {
                initialCatchUpScrollTrigger += 1
            }
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
        Button {
            onNavigateToPeer?(vm.peer)
        } label: {
            HStack(spacing: 8) {
                AvatarView(profile: vm.peer, size: 28)
                    .accessibilityIdentifier("chatPeerAvatar")

                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text(vm.peer.displayTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        if presenceStore?.isOnline(vm.peer.id) == true {
                            PresenceDot(size: 8)
                                .accessibilityIdentifier("chatPeerOnlineDot")
                        }
                    }
                    if vm.peerIsTyping {
                        Text("正在输入...")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.7))
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
                            Task { await vm.loadOlder() }
                        } label: {
                            if vm.isLoadingOlder {
                                ProgressView()
                            } else {
                                Text("加载更早消息")
                                    .font(.caption)
                                    .foregroundStyle(Color.echoBlue)
                            }
                        }
                        .buttonStyle(.borderless)
                        .padding(.vertical, 6)
                    }

                    ForEach(Array(vm.messages.enumerated()), id: \.element.localId) { index, message in
                        if vm.shouldShowTimestamp(at: index) {
                            TimestampPill(date: message.message.createdAt)
                        }
                        MessageBubble(
                            message: message,
                            isSelf: message.message.senderId == vm.currentUserId,
                            isConsecutive: vm.isConsecutive(
                                message,
                                previous: index > 0 ? vm.messages[index - 1] : nil
                            ),
                            onRetry: {
                                Task { await vm.retry(localId: message.localId) }
                            },
                            onOpenImage: {
                                lightboxBubble = message
                            }
                        )
                        .id(message.localId)
                    }

                    Color.clear.frame(height: 10).id(Self.bottomAnchorId)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
            .modifier(ChatDefaultScrollAnchor())
            .background(Color(uiColor: .systemBackground))
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { isInputFocused = false })
            .overlay {
                if vm.phase == .loading, vm.messages.isEmpty {
                    ChatSkeletonView()
                        .transition(.opacity)
                }
            }
            .onChange(of: vm.messages.last?.localId) { _, newValue in
                guard newValue != nil else { return }
                guard initialScrollPolicy.consumeMessageChangeForScroll() else { return }
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: initialCatchUpScrollTrigger) { _, _ in
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            // 锚定列表尾部而不是最后一个气泡，避免底部留白被算丢后看起来差一点。
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            } else {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                ZStack {
                    Circle()
                        .fill(Color.echoSurface)
                        .frame(width: 34, height: 34)
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.echoBlue)
                }
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel(Text("发送图片"))
            .accessibilityIdentifier("chatImagePicker")
            .simultaneousGesture(TapGesture().onEnded { isInputFocused = false })

            TextField("说点什么...", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .submitLabel(.send)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.echoSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.echoBlue.opacity(0.2), lineWidth: 1)
                        )
                )
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
                Task { await vm.sendText(text) }
            } label: {
                ZStack {
                    Circle()
                        .fill(canSend ? Color.echoInteractive : Color.echoSurface)
                        .frame(width: 34, height: 34)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
            .disabled(!canSend)
            .accessibilityLabel(Text("发送消息"))
            .accessibilityIdentifier("chatSend")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.echoBlue.opacity(0.12))
                .frame(height: 0.5)
        }
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

private struct ChatDefaultScrollAnchor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
        } else {
            content.defaultScrollAnchor(.bottom)
        }
    }
}

private struct TimestampPill: View {
    let date: Date

    private var text: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.echoMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.echoBlue.opacity(0.07))
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}
