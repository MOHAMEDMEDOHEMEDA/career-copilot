import Combine
import Foundation

protocol InterviewServicing {
    func interviews(offset: Int) async throws -> ChatPage<InterviewSession>
    func createInterview(resumeID: UUID, description: String) async throws -> InterviewSession
    func deleteInterview(id: UUID) async throws
    func interviewQuestions(sessionID: UUID) async throws -> ChatPage<InterviewQuestion>
    func saveInterviewAnswer(sessionID: UUID, questionID: UUID, answer: String) async throws -> InterviewQuestion
    func requestInterviewJob(sessionID: UUID, questionID: UUID?) async throws -> InterviewJob
    func interviewJob(sessionID: UUID, jobID: UUID) async throws -> InterviewJob
    func retryInterviewJob(sessionID: UUID, jobID: UUID) async throws -> InterviewJob
}
extension APIClient: InterviewServicing {}

@MainActor
final class InterviewViewModel: ObservableObject {
    @Published private(set) var sessions: [InterviewSession] = []
    @Published private(set) var questions: [InterviewQuestion] = []
    @Published private(set) var loading = false
    @Published private(set) var hasMore = false
    @Published private(set) var job: InterviewJob?
    @Published var error: String?
    var baseURL: String
    private var generation = UUID()
    private var activeSessionID: UUID?
    private let clientFactory: (String) throws -> any InterviewServicing

    init(baseURL: String = UserDefaults.standard.string(forKey: "baseURL") ?? "http://localhost:8000", clientFactory: @escaping (String) throws -> any InterviewServicing = { try APIClient.configured(baseURL: $0) }) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
    }

    func reset() {
        generation = UUID(); sessions = []; questions = []; job = nil; error = nil; loading = false; hasMore = false; activeSessionID = nil
    }

    func loadSessions(more: Bool = false) async {
        guard !loading else { return }
        let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            let page = try await clientFactory(baseURL).interviews(offset: more ? sessions.count : 0)
            guard token == generation, !Task.isCancelled else { return }
            sessions = more ? sessions + page.items : page.items
            hasMore = page.items.count == page.limit; error = nil
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func create(resumeID: UUID, description: String) async -> InterviewSession? {
        guard !loading else { return nil }
        let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            let item = try await clientFactory(baseURL).createInterview(resumeID: resumeID, description: description)
            guard token == generation, !Task.isCancelled else { return nil }
            sessions.insert(item, at: 0); error = nil; return item
        } catch {
            if token == generation && !Task.isCancelled { self.error = "Couldn’t create the interview: \(error.localizedDescription). Refresh before trying again." }
            return nil
        }
    }

    func delete(_ item: InterviewSession) async {
        guard !loading else { return }
        let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            try await clientFactory(baseURL).deleteInterview(id: item.id)
            guard token == generation, !Task.isCancelled else { return }
            sessions.removeAll { $0.id == item.id }; error = nil
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func open(_ sessionID: UUID) async {
        generation = UUID(); activeSessionID = sessionID; loading = false
        questions = []; job = nil; error = nil
        await refresh(sessionID)
    }

    func refresh(_ sessionID: UUID) async {
        let token = generation
        do {
            let page = try await clientFactory(baseURL).interviewQuestions(sessionID: sessionID)
            guard token == generation, activeSessionID == sessionID, !Task.isCancelled else { return }
            guard page.items.allSatisfy({ $0.sessionID == sessionID }) else { throw URLError(.badServerResponse) }
            questions = page.items; error = nil
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func save(sessionID: UUID, questionID: UUID, answer: String) async -> Bool {
        guard !loading else { return false }
        let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            let item = try await clientFactory(baseURL).saveInterviewAnswer(sessionID: sessionID, questionID: questionID, answer: answer)
            guard token == generation, !Task.isCancelled, item.sessionID == sessionID, item.id == questionID else { return false }
            if let index = questions.firstIndex(where: { $0.id == questionID }) { questions[index] = item }
            if job?.questionID == questionID { job = nil }
            error = nil; return true
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription }; return false }
    }

    func request(sessionID: UUID, questionID: UUID?, retry: Bool = false) async {
        guard !loading else { return }
        let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            let client = try clientFactory(baseURL)
            var current: InterviewJob
            if retry, let old = job { current = try await client.retryInterviewJob(sessionID: sessionID, jobID: old.id) }
            else { current = try await client.requestInterviewJob(sessionID: sessionID, questionID: questionID) }
            for _ in 0..<90 {
                guard token == generation, !Task.isCancelled, current.sessionID == sessionID, current.questionID == questionID else { return }
                job = current
                if current.status == .completed { await refresh(sessionID); return }
                if current.status == .failed { error = "Interview request failed (\(current.errorCode ?? "unknown error")). You can retry."; return }
                try await Task.sleep(nanoseconds: 2_000_000_000)
                current = try await client.interviewJob(sessionID: sessionID, jobID: current.id)
            }
            error = "This is taking longer than expected. Check the status again."
        } catch is CancellationError { return }
        catch { if token == generation && !Task.isCancelled { self.error = "Couldn’t check the interview: \(error.localizedDescription). You can check again." } }
    }
}
