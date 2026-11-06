import Combine
import Foundation

protocol ChatServicing {
    func conversations(offset: Int) async throws -> ChatPage<ChatConversation>
    func createConversation(title: String) async throws -> ChatConversation
    func deleteConversation(id: UUID) async throws
    func chatMessages(conversationID: UUID, offset: Int) async throws -> ChatPage<ChatMessage>
    func saveChatMessage(conversationID: UUID, content: String) async throws -> ChatMessage
}
extension APIClient: ChatServicing {}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var conversations: [ChatConversation] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var hasMoreConversations = false
    @Published private(set) var hasMoreMessages = false
    @Published private(set) var needsRefreshBeforeSending = false
    @Published private(set) var hasLoadedMessages = false
    @Published var error: String?
    @Published var draft = ""
    var baseURL: String
    private let clientFactory: (String) throws -> any ChatServicing
    private var generation = UUID()
    private var activeConversationID: UUID?
    private var drafts: [UUID: String] = [:]

    init(baseURL: String = UserDefaults.standard.string(forKey: "baseURL") ?? "http://localhost:8000", clientFactory: @escaping (String) throws -> any ChatServicing = { try APIClient.configured(baseURL: $0) }) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
    }

    func reset() {
        generation = UUID()
        conversations = []
        messages = []
        draft = ""
        error = nil
        activeConversationID = nil
        drafts.removeAll()
        isLoading = false
        isSending = false
        hasMoreConversations = false
        hasMoreMessages = false
        needsRefreshBeforeSending = false
        hasLoadedMessages = false
    }

    func loadConversations(reset: Bool = true) async {
        guard !isLoading else { return }
        let operation = generation
        isLoading = true
        defer { if operation == generation { isLoading = false } }
        do {
            let page = try await clientFactory(baseURL).conversations(offset: reset ? 0 : conversations.count)
            guard operation == generation, !Task.isCancelled else { return }
            conversations = reset ? page.items : conversations + page.items
            hasMoreConversations = page.items.count == page.limit
            error = nil
        } catch { if operation == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func createConversation(title: String) async -> ChatConversation? {
        guard !isLoading else { return nil }
        let operation = generation
        isLoading = true
        defer { if operation == generation { isLoading = false } }
        do {
            let conversation = try await clientFactory(baseURL).createConversation(title: title)
            guard operation == generation, !Task.isCancelled else { return nil }
            conversations.insert(conversation, at: 0)
            error = nil
            return conversation
        } catch {
            if operation == generation && !Task.isCancelled { self.error = "Couldn’t create chat: \(error.localizedDescription). It may have been created; refresh before trying again." }
            return nil
        }
    }

    func delete(_ conversation: ChatConversation) async {
        guard !isLoading else { return }
        let operation = generation
        isLoading = true
        defer { if operation == generation { isLoading = false } }
        do {
            try await clientFactory(baseURL).deleteConversation(id: conversation.id)
            guard operation == generation, !Task.isCancelled else { return }
            conversations.removeAll { $0.id == conversation.id }
            drafts[conversation.id] = nil
            error = nil
        } catch { if operation == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func open(_ conversation: ChatConversation) async {
        activeConversationID = conversation.id
        messages = []
        draft = drafts[conversation.id] ?? ""
        error = nil
        hasMoreMessages = false
        needsRefreshBeforeSending = false
        hasLoadedMessages = false
        await loadMessages(conversationID: conversation.id)
    }

    func close(conversationID: UUID) {
        guard activeConversationID == conversationID else { return }
        drafts[conversationID] = draft
        generation = UUID()
        activeConversationID = nil
        messages = []
        draft = ""
        error = nil
        isLoading = false
        isSending = false
        hasMoreMessages = false
        needsRefreshBeforeSending = false
        hasLoadedMessages = false
    }

    func loadMessages(conversationID: UUID, reset: Bool = true) async {
        guard !isLoading, activeConversationID == conversationID else { return }
        let operation = generation
        isLoading = true
        defer { if operation == generation { isLoading = false } }
        do {
            let page = try await clientFactory(baseURL).chatMessages(conversationID: conversationID, offset: reset ? 0 : messages.count)
            guard operation == generation, activeConversationID == conversationID, !Task.isCancelled else { return }
            guard page.items.allSatisfy({ $0.conversationID == conversationID }) else { throw URLError(.badServerResponse) }
            messages = reset ? page.items : messages + page.items
            hasMoreMessages = page.items.count == page.limit
            hasLoadedMessages = true
            needsRefreshBeforeSending = false
            error = nil
        } catch { if operation == generation && activeConversationID == conversationID && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func send(conversationID: UUID) async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.count <= 4000, !isSending, !isLoading, !hasMoreMessages, hasLoadedMessages, !needsRefreshBeforeSending, activeConversationID == conversationID else { return }
        let operation = generation
        isSending = true
        defer { if operation == generation { isSending = false } }
        do {
            let message = try await clientFactory(baseURL).saveChatMessage(conversationID: conversationID, content: content)
            guard operation == generation, activeConversationID == conversationID, !Task.isCancelled else { return }
            guard message.conversationID == conversationID, message.role == .user else { throw URLError(.badServerResponse) }
            messages.append(message)
            if draft.trimmingCharacters(in: .whitespacesAndNewlines) == content { draft = "" }
            error = nil
        } catch {
            if operation == generation && activeConversationID == conversationID && !Task.isCancelled {
                needsRefreshBeforeSending = true
                self.error = "Couldn’t save the message: \(error.localizedDescription). It may have been saved; refresh before sending again."
            }
        }
    }
}
