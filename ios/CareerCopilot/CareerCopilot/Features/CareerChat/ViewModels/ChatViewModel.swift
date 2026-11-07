import Combine
import Foundation

protocol ChatServicing {
    func conversations(offset: Int) async throws -> ChatPage<ChatConversation>
    func createConversation(title: String) async throws -> ChatConversation
    func deleteConversation(id: UUID) async throws
    func chatMessages(conversationID: UUID, offset: Int) async throws -> ChatPage<ChatMessage>
    func saveChatMessage(conversationID: UUID, content: String) async throws -> ChatMessage
    func requestChatAnswer(conversationID: UUID, questionID: UUID) async throws -> ChatAnswerJob
    func chatAnswerJob(conversationID: UUID, jobID: UUID) async throws -> ChatAnswerJob
    func retryChatAnswer(conversationID: UUID, jobID: UUID) async throws -> ChatAnswerJob
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
    @Published private(set) var answerJob: ChatAnswerJob?
    @Published private(set) var answerError: String?
    @Published private(set) var isRequestingAnswer = false
    @Published private(set) var answerPollingToken: UUID?
    @Published private(set) var answerPollingPaused = false
    var baseURL: String
    private let clientFactory: (String) throws -> any ChatServicing
    private var generation = UUID()
    private var activeConversationID: UUID?
    private var drafts: [UUID: String] = [:]
    private var answerJobs: [UUID: ChatAnswerJob] = [:]

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
        answerJobs.removeAll()
        isLoading = false
        isSending = false
        hasMoreConversations = false
        hasMoreMessages = false
        needsRefreshBeforeSending = false
        hasLoadedMessages = false
        clearAnswerState()
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
            answerJobs[conversation.id] = nil
            error = nil
        } catch { if operation == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func open(_ conversation: ChatConversation) async {
        let previousJob = answerJobs[conversation.id]
        activeConversationID = conversation.id
        messages = []
        draft = drafts[conversation.id] ?? ""
        error = nil
        hasMoreMessages = false
        needsRefreshBeforeSending = false
        hasLoadedMessages = false
        clearAnswerState()
        await loadMessages(conversationID: conversation.id)
        guard activeConversationID == conversation.id, !Task.isCancelled else { return }
        if let previousJob, previousJob.status != .completed {
            await applyAnswerJob(previousJob)
        }
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
        clearAnswerState()
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

    @discardableResult
    func send(conversationID: UUID) async -> ChatMessage? {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.unicodeScalars.count <= 4000, !isSending, !isLoading, !hasMoreMessages, hasLoadedMessages, !needsRefreshBeforeSending, activeConversationID == conversationID else { return nil }
        let operation = generation
        isSending = true
        defer { if operation == generation { isSending = false } }
        do {
            let message = try await clientFactory(baseURL).saveChatMessage(conversationID: conversationID, content: content)
            guard operation == generation, activeConversationID == conversationID, !Task.isCancelled else { return nil }
            guard message.conversationID == conversationID, message.role == .user else { throw URLError(.badServerResponse) }
            messages.append(message)
            if draft.trimmingCharacters(in: .whitespacesAndNewlines) == content { draft = "" }
            error = nil
            return message
        } catch {
            if operation == generation && activeConversationID == conversationID && !Task.isCancelled {
                needsRefreshBeforeSending = true
                self.error = "Couldn’t save the message: \(error.localizedDescription). It may have been saved; refresh before sending again."
            }
            return nil
        }
    }

    func hasAnswer(for questionID: UUID) -> Bool {
        messages.contains { $0.replyToID == questionID && $0.role == .assistant }
    }

    func requestAnswer(conversationID: UUID, questionID: UUID) async {
        guard !isRequestingAnswer, activeConversationID == conversationID else { return }
        let operation = generation
        isRequestingAnswer = true
        answerError = nil
        defer { if operation == generation { isRequestingAnswer = false } }
        do {
            let job = try await clientFactory(baseURL).requestChatAnswer(conversationID: conversationID, questionID: questionID)
            guard operation == generation, activeConversationID == conversationID, !Task.isCancelled else { return }
            guard job.conversationID == conversationID, job.questionID == questionID else { throw URLError(.badServerResponse) }
            await applyAnswerJob(job)
        } catch {
            if operation == generation && !Task.isCancelled { answerError = "Couldn’t request an answer: \(error.localizedDescription). You can ask again to check the existing job." }
        }
    }

    func retryAnswer(conversationID: UUID) async {
        guard let current = answerJob, current.status == .failed, !isRequestingAnswer, activeConversationID == conversationID else { return }
        let operation = generation
        isRequestingAnswer = true
        answerError = nil
        defer { if operation == generation { isRequestingAnswer = false } }
        do {
            let job = try await clientFactory(baseURL).retryChatAnswer(conversationID: conversationID, jobID: current.id)
            guard operation == generation, activeConversationID == conversationID, !Task.isCancelled else { return }
            guard job.id == current.id, job.conversationID == conversationID, job.questionID == current.questionID else { throw URLError(.badServerResponse) }
            await applyAnswerJob(job)
        } catch { if operation == generation && !Task.isCancelled { answerError = error.localizedDescription } }
    }

    func checkAnswerStatus() {
        guard let answerJob, answerJob.status == .queued || answerJob.status == .running else { return }
        answerPollingPaused = false
        answerError = nil
        answerPollingToken = UUID()
    }

    func pollAnswer(conversationID: UUID) async {
        guard let current = answerJob, current.conversationID == conversationID, current.status == .queued || current.status == .running else { return }
        let operation = generation
        do {
            for _ in 0..<90 {
                try Task.checkCancellation()
                let job = try await clientFactory(baseURL).chatAnswerJob(conversationID: conversationID, jobID: current.id)
                guard operation == generation, activeConversationID == conversationID, !Task.isCancelled else { return }
                guard job.id == current.id, job.conversationID == conversationID, job.questionID == current.questionID else { throw URLError(.badServerResponse) }
                await applyAnswerJob(job, startPolling: false)
                if job.status == .completed || job.status == .failed { return }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            if operation == generation && !Task.isCancelled { answerPollingPaused = true; answerError = "The answer is taking longer than expected." }
        } catch is CancellationError {
            return
        } catch {
            if operation == generation && !Task.isCancelled { answerPollingPaused = true; answerError = "Couldn’t check answer status: \(error.localizedDescription)" }
        }
    }

    private func applyAnswerJob(_ job: ChatAnswerJob, startPolling: Bool = true) async {
        answerJob = job
        answerJobs[job.conversationID] = job
        answerPollingPaused = false
        switch job.status {
        case .queued, .running:
            if startPolling { answerPollingToken = UUID() }
        case .completed:
            answerError = nil
            await loadMessages(conversationID: job.conversationID)
        case .failed:
            switch job.errorCode {
            case "rate_limited": answerError = "The AI provider is rate-limited. You can retry later."
            case "invalid_output": answerError = "The answer or its citations could not be verified."
            case "timeout": answerError = "The answer timed out. You can retry."
            case "provider_unavailable": answerError = "An AI provider or local knowledge search is unavailable. Check the backend and Ollama, then retry."
            case "provider_auth": answerError = "An AI provider rejected the request. Check the backend provider settings."
            case "invalid_input": answerError = "The question is empty or too long. Review it and try again."
            case "output_limit": answerError = "The AI response was too long. Try a shorter question."
            default: answerError = "The answer couldn’t be completed. You can retry."
            }
        }
    }

    private func clearAnswerState() {
        answerJob = nil
        answerError = nil
        isRequestingAnswer = false
        answerPollingToken = nil
        answerPollingPaused = false
    }
}
