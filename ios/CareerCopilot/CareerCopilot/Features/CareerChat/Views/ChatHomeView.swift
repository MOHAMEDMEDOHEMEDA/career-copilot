import SwiftUI

enum ChatStyle {
    static let background = Color(red: 0.015, green: 0.035, blue: 0.07)
    static let surface = Color(red: 0.08, green: 0.13, blue: 0.19)
    static let cyan = Color(red: 0.08, green: 0.69, blue: 0.94)
    static let muted = Color.white.opacity(0.72)
    static let gradient = LinearGradient(colors: [Color(red: 0.025, green: 0.14, blue: 0.21), background, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct ChatHomeView: View {
    @ObservedObject var model: ChatViewModel
    @State private var selected: ChatConversation?
    @State private var showNewChat = false
    @State private var newTitle = ""
    @State private var deleteTarget: ChatConversation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("YOUR CAREER COMPANION").font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(ChatStyle.cyan)
                Text("Let’s make your\nnext move.").font(.largeTitle.bold()).foregroundStyle(.white)
                Text("Keep your career questions in one place.").font(.subheadline).foregroundStyle(ChatStyle.muted)

                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.title2).foregroundStyle(ChatStyle.cyan)
                    Text("Your space to think ahead").font(.title3.bold()).foregroundStyle(.white)
                    Text("Ask career questions and explore answers with sources.").font(.subheadline).foregroundStyle(ChatStyle.muted)
                    Button { newTitle = ""; showNewChat = true } label: {
                        Label("Start a chat", systemImage: "plus").fontWeight(.semibold).frame(maxWidth: .infinity).padding(14)
                    }
                    .foregroundStyle(.black)
                    .background(ChatStyle.cyan, in: Capsule())
                    .disabled(model.isLoading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(LinearGradient(colors: [ChatStyle.surface, Color(red: 0.015, green: 0.22, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))

                HStack {
                    Text("Your conversations").font(.title3.bold()).foregroundStyle(.white)
                    Spacer()
                    Button { Task { await model.loadConversations() } } label: {
                        Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44)
                    }
                        .accessibilityLabel("Refresh conversations")
                        .disabled(model.isLoading)
                }
                if model.isLoading { ProgressView().tint(.white).accessibilityLabel("Loading conversations") }
                if let error = model.error {
                    Text(error).font(.subheadline).foregroundStyle(.white)
                    Button("Refresh") { Task { await model.loadConversations() } }.foregroundStyle(ChatStyle.cyan).frame(minHeight: 44)
                }
                if model.conversations.isEmpty && !model.isLoading && model.error == nil {
                    Text("No conversations yet. Start one when you’re ready.").foregroundStyle(ChatStyle.muted)
                }
                LazyVStack(spacing: 10) {
                    ForEach(model.conversations) { conversation in
                        HStack {
                            Button { selected = conversation } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(ChatStyle.cyan)
                                        .frame(width: 42, height: 42).background(.white.opacity(0.07), in: Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(conversation.title).font(.headline).foregroundStyle(.white).lineLimit(2)
                                        Text("Conversation").font(.caption).foregroundStyle(ChatStyle.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(ChatStyle.muted)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Menu {
                                Button("Delete conversation", systemImage: "trash", role: .destructive) { deleteTarget = conversation }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).foregroundStyle(.white) }
                                .accessibilityLabel("Options for \(conversation.title)")
                        }.padding(14).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                if model.hasMoreConversations {
                    Button("Load more") { Task { await model.loadConversations(reset: false) } }.foregroundStyle(ChatStyle.cyan).frame(minHeight: 44)
                }
            }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }
        .background(ChatStyle.gradient.ignoresSafeArea())
        .tint(ChatStyle.cyan)
        .navigationTitle("Career chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(item: $selected) { conversation in ChatThreadView(model: model, conversation: conversation) }
        .alert("New conversation", isPresented: $showNewChat) {
            TextField("Conversation name", text: $newTitle)
            Button("Create") {
                let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { selected = await model.createConversation(title: title.isEmpty ? "Career chat" : String(title.prefix(100))) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Choose a name so you can find this conversation later.") }
        .confirmationDialog("Delete this conversation?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            if let target = deleteTarget { Button("Delete", role: .destructive) { Task { await model.delete(target) }; deleteTarget = nil } }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { Text("This permanently deletes its messages.") }
        .task { await model.loadConversations() }
    }
}

#Preview("Career chat") {
    NavigationStack { ChatHomeView(model: ChatViewModel(clientFactory: { _ in ChatPreviewService() })) }
}

struct ChatPreviewService: ChatServicing {
    func conversations(offset: Int) async throws -> ChatPage<ChatConversation> { ChatPage(items: [], limit: 20, offset: offset) }
    func createConversation(title: String) async throws -> ChatConversation { ChatConversation(id: UUID(), title: title, createdAt: "", updatedAt: "") }
    func deleteConversation(id: UUID) async throws {}
    func chatMessages(conversationID: UUID, offset: Int) async throws -> ChatPage<ChatMessage> { ChatPage(items: [], limit: 100, offset: offset) }
    func saveChatMessage(conversationID: UUID, content: String) async throws -> ChatMessage { ChatMessage(id: UUID(), conversationID: conversationID, sequence: 1, role: .user, content: content, createdAt: "") }
    func requestChatAnswer(conversationID: UUID, questionID: UUID) async throws -> ChatAnswerJob { throw CancellationError() }
    func chatAnswerJob(conversationID: UUID, jobID: UUID) async throws -> ChatAnswerJob { throw CancellationError() }
    func retryChatAnswer(conversationID: UUID, jobID: UUID) async throws -> ChatAnswerJob { throw CancellationError() }
}
