import PhotosUI
import SwiftUI
import UIKit

struct ChatView: View {
    @State private var vm: ChatViewModel
    @State private var draft = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var lightboxBubble: LocalMessage?
    @State private var scrollState = ChatScrollState()
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollContentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var isScrolling = false
    @State private var scrollIdleTimer: Task<Void, Never>?
    @State private var didInitialScroll = false
    @State private var keyboardHeight: CGFloat = 0
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
        chatContent
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                principalTitle
            }
        }
        .echoNavigationBarStyle()
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
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification
        )) { notification in
            handleKeyboardFrameChange(notification)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        )) { notification in
            handleKeyboardWillHide(notification)
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            messagesList
            inputBar
        }
        .offset(y: -keyboardHeight)
    }

    private func handleKeyboardFrameChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let bottomInset = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?.safeAreaInsets.bottom ?? 0
        let screenBounds = UIScreen.main.bounds
        let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveRaw = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? 0
        let nextHeight = ChatKeyboardAvoidance.height(
            screenSize: screenBounds.size,
            keyboardFrame: endFrame,
            bottomSafeAreaInset: bottomInset
        )

        applyKeyboardHeight(
            nextHeight,
            animation: keyboardAnimation(duration: duration, curveRaw: curveRaw)
        )
    }

    private func handleKeyboardWillHide(_ notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        applyKeyboardHeight(0, animation: .easeIn(duration: duration))
    }

    private func applyKeyboardHeight(_ nextHeight: CGFloat, animation: Animation) {
        guard ChatKeyboardAvoidance.shouldUpdateHeight(from: keyboardHeight, to: nextHeight) else {
            return
        }

        withAnimation(animation) { keyboardHeight = nextHeight }
    }

    private func keyboardAnimation(duration: Double, curveRaw: Int) -> Animation {
        guard let curve = UIView.AnimationCurve(rawValue: curveRaw) else {
            // 键盘通知可能给出 UIKit 私有曲线值；SwiftUI 无等价枚举，退回系统感接近的曲线。
            return .easeInOut(duration: duration)
        }

        switch curve {
        case .easeInOut: return .easeInOut(duration: duration)
        case .easeIn: return .easeIn(duration: duration)
        case .easeOut: return .easeOut(duration: duration)
        case .linear: return .linear(duration: duration)
        @unknown default: return .easeInOut(duration: duration)
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

    private var reversedMessages: [LocalMessage] {
        Array(vm.messages.reversed())
    }

    private var messagesList: some View {
        GeometryReader { viewportGeo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Color.clear.frame(height: 10)
                            .id("chatBottomAnchor")

                        ForEach(
                            Array(reversedMessages.enumerated()),
                            id: \.element.localId
                        ) { revIndex, message in
                            let originalIndex = vm.messages.count - 1 - revIndex
                            VStack(spacing: 0) {
                                if vm.shouldShowTimestamp(at: originalIndex) {
                                    TimestampPill(date: message.message.createdAt)
                                }
                                MessageBubble(
                                    message: message,
                                    isSelf: message.message.senderId == vm.currentUserId,
                                    isConsecutive: vm.isConsecutive(
                                        message,
                                        previous: originalIndex > 0
                                            ? vm.messages[originalIndex - 1]
                                            : nil
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
                            .scaleEffect(x: 1, y: -1)
                        }

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
                            .scaleEffect(x: 1, y: -1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: viewportGeo.size.height, alignment: .bottom)
                    .background(
                        GeometryReader { contentGeo in
                            let frame = contentGeo.frame(in: .named("chatScroll"))
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: -frame.minY
                                )
                                .preference(
                                    key: ContentHeightPreferenceKey.self,
                                    value: contentGeo.size.height
                                )
                        }
                    )
                }
                .coordinateSpace(name: "chatScroll")
                .scaleEffect(x: 1, y: -1)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { isInputFocused = false }
                )
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    scrollOffset = offset
                    scrollState.updateOffset(offset)
                    handleScrollActivity()
                }
                .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                    scrollContentHeight = height
                }
                .overlay(alignment: .trailing) {
                    ChatScrollIndicator(
                        metrics: ScrollIndicatorMetrics(
                            contentHeight: scrollContentHeight,
                            viewportHeight: viewportHeight,
                            offset: scrollOffset
                        ),
                        isVisible: isScrolling
                    )
                }
                .overlay(alignment: .bottom) {
                    newMessagesButton(proxy: proxy)
                }
                .overlay {
                    if vm.phase == .loading, vm.messages.isEmpty {
                        ChatSkeletonView()
                            .transition(.opacity)
                    }
                }
                .onChange(of: vm.messages.last?.localId) { _, _ in
                    handleNewMessage(proxy: proxy)
                }
                .onAppear {
                    viewportHeight = viewportGeo.size.height
                }
                .onChange(of: viewportGeo.size.height) { _, newHeight in
                    viewportHeight = newHeight
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("chatBottomAnchor", anchor: .top)
                }
            } else {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo("chatBottomAnchor", anchor: .top)
                }
            }
        }
    }

    private func handleScrollActivity() {
        isScrolling = true
        scrollIdleTimer?.cancel()
        scrollIdleTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                isScrolling = false
            }
        }
    }

    private func handleNewMessage(proxy: ScrollViewProxy) {
        guard let last = vm.messages.last else { return }

        let animated = didInitialScroll
        if !didInitialScroll { didInitialScroll = true }

        if last.message.senderId == vm.currentUserId {
            scrollToBottom(proxy, animated: animated)
        } else if scrollState.isNearBottom {
            scrollToBottom(proxy, animated: animated)
        } else {
            scrollState.recordIncomingMessage()
        }
    }

    @ViewBuilder
    private func newMessagesButton(proxy: ScrollViewProxy) -> some View {
        if scrollState.newMessageCount > 0 {
            Button {
                scrollToBottom(proxy, animated: true)
                scrollState.reset()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                    Text("\(scrollState.newMessageCount) 条新消息")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.echoInteractive))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            }
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: scrollState.newMessageCount)
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
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
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
        .padding(.vertical, 12)
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
