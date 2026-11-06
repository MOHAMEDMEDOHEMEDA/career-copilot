import SwiftUI

struct ChatThreadView: View {
    @ObservedObject var model: ChatViewModel
    let conversation: ChatConversation
    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles").foregroundStyle(ChatStyle.cyan)
                            .frame(width: 40, height: 40).background(ChatStyle.surface, in: Circle())
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your career chat").font(.headline).foregroundStyle(.white)
                            Text("Save your questions here. AI replies and cited sources are coming soon.").font(.subheadline).foregroundStyle(ChatStyle.muted)
                        }
                        .padding(16).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if model.isLoading { ProgressView("Loading messages").tint(.white).foregroundStyle(ChatStyle.muted) }
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.white)
                            Button("Refresh messages") { Task { await model.loadMessages(conversationID: conversation.id) } }.foregroundStyle(ChatStyle.cyan)
                        }.padding(14).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    ForEach(model.messages) { message in
                        HStack(alignment: .bottom) {
                            if message.role == .user { Spacer(minLength: 40) }
                            Text(message.content)
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                                .padding(15)
                                .background(message.role == .user ? Color(red: 0.04, green: 0.32, blue: 0.46) : ChatStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                            if message.role == .assistant { Spacer(minLength: 40) }
                        }.id(message.id)
                    }
                    if model.hasMoreMessages {
                        Button("Load more messages") { Task { await model.loadMessages(conversationID: conversation.id, reset: false) } }
                            .foregroundStyle(ChatStyle.cyan)
                        Text("Load all messages before adding a new one.").font(.caption).foregroundStyle(ChatStyle.muted)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
            }
            .onChange(of: model.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .background(ChatStyle.gradient.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(ChatStyle.cyan)
        .task { await model.open(conversation) }
        .onDisappear { model.close(conversationID: conversation.id) }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Write a career question", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .foregroundStyle(.white)
                    .tint(ChatStyle.cyan)
                    .accessibilityLabel("Career question")
                    .padding(14)
                    .background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                Button {
                    Task { await model.send(conversationID: conversation.id) }
                } label: {
                    if model.isSending { ProgressView().tint(.black).frame(width: 48, height: 48) }
                    else { Image(systemName: "arrow.up").font(.headline).frame(width: 48, height: 48) }
                }
                .accessibilityLabel("Save message")
                .foregroundStyle(.black)
                .background(ChatStyle.cyan, in: Circle())
                .disabled(model.isSending || model.isLoading || !model.hasLoadedMessages || model.hasMoreMessages || model.needsRefreshBeforeSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.count > 4000)
                .opacity(model.isSending || model.isLoading ? 0.6 : 1)
            }
            Text("Messages are saved. AI replies are coming soon. \(model.draft.count)/4000")
                .font(.caption).foregroundStyle(ChatStyle.muted)
        }
        .frame(maxWidth: 700).frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(ChatStyle.background)
    }
}

#Preview("Conversation") {
    NavigationStack {
        ChatThreadView(model: ChatViewModel(clientFactory: { _ in ChatPreviewService() }), conversation: ChatConversation(id: UUID(), title: "Career goals", createdAt: "", updatedAt: ""))
    }
}
