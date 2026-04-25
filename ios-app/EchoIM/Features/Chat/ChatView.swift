import SwiftUI

struct ChatView: View {
    @State private var vm: ChatViewModel
    @State private var draft = ""

    init(
        route: ChatRoute,
        currentUserId: Int,
        messageRepo: MessageRepository,
        messageStore: MessageStore?,
        metaStore: ConversationMetaStore?,
        wsClient: WebSocketClient?,
        conversationRepository: ConversationRepository?,
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
                tokenProvider: tokenProvider
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            inputBar
        }
        .navigationTitle(vm.peer.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            vm.attachWSSubscription()
            await vm.load()
        }
        .onDisappear {
            vm.detachWSSubscription()
        }
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
                            isSelf: message.message.senderId == vm.currentUserId
                        ) {
                            Task {
                                await vm.retry(localId: message.localId)
                            }
                        }
                        .id(message.localId)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color(uiColor: .systemBackground))
            .overlay {
                if vm.phase == .loading, vm.messages.isEmpty {
                    ProgressView()
                }
            }
            .onChange(of: vm.messages.last?.localId) { _, newValue in
                guard let newValue else { return }

                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("说点什么...", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .submitLabel(.send)
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
            .accessibilityLabel("发送")
            .accessibilityIdentifier("chatSend")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
