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

protocol AdaptiveInterviewServicing {
    func adaptiveSessions(offset: Int) async throws -> ChatPage<AdaptiveSession>
    func createAdaptiveSession(role: String, seniority: String, interviewType: String, resumeID: UUID?, description: String, skills: [String]) async throws -> AdaptiveSession
    func adaptiveSession(id: UUID) async throws -> AdaptiveSession
    func deleteAdaptiveSession(id: UUID) async throws
    func adaptiveTurns(sessionID: UUID) async throws -> ChatPage<AdaptiveTurn>
    func adaptiveJobs(sessionID: UUID) async throws -> ChatPage<AdaptiveJob>
    func saveAdaptiveAnswer(sessionID: UUID, turnID: UUID, answer: String) async throws -> AdaptiveTurn
    func requestAdaptiveJob(sessionID: UUID, turnID: UUID?) async throws -> AdaptiveJob
    func adaptiveJob(sessionID: UUID, jobID: UUID) async throws -> AdaptiveJob
    func retryAdaptiveJob(sessionID: UUID, jobID: UUID) async throws -> AdaptiveJob
    func completeAdaptiveSession(sessionID: UUID) async throws -> AdaptiveSession
    func adaptiveReport(sessionID: UUID) async throws -> AdaptiveReport
    func adaptiveProgress(offset: Int) async throws -> ChatPage<AdaptiveTopicProgress>
}
extension APIClient: AdaptiveInterviewServicing {}

@MainActor
final class AdaptiveInterviewViewModel: ObservableObject {
    @Published private(set) var sessions: [AdaptiveSession] = []
    @Published private(set) var session: AdaptiveSession?
    @Published private(set) var turns: [AdaptiveTurn] = []
    @Published private(set) var job: AdaptiveJob?
    @Published private(set) var report: AdaptiveReport?
    @Published private(set) var progress: [AdaptiveTopicProgress] = []
    @Published private(set) var loading = false
    @Published private(set) var hasMoreSessions = false
    @Published private(set) var hasMoreProgress = false
    @Published var error: String?
    var baseURL: String
    private let factory: (String) throws -> any AdaptiveInterviewServicing
    private var generation = UUID()

    init(baseURL: String = UserDefaults.standard.string(forKey: "baseURL") ?? "http://localhost:8000", factory: @escaping (String) throws -> any AdaptiveInterviewServicing = { try APIClient.configured(baseURL: $0) }) {
        self.baseURL = baseURL; self.factory = factory
    }
    func reset() { generation = UUID(); sessions = []; session = nil; turns = []; job = nil; report = nil; progress = []; loading = false; error = nil; hasMoreSessions = false; hasMoreProgress = false }

    func loadSessions(more: Bool = false) async {
        guard !loading else { return }; let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            let page = try await factory(baseURL).adaptiveSessions(offset: more ? sessions.count : 0)
            guard token == generation, !Task.isCancelled else { return }
            sessions = more ? sessions + page.items : page.items; hasMoreSessions = page.items.count == page.limit; error = nil
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func create(role: String, seniority: String, interviewType: String, resumeID: UUID?, description: String, skills: [String]) async -> AdaptiveSession? {
        guard !loading else { return nil }; let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            let item = try await factory(baseURL).createAdaptiveSession(role: role, seniority: seniority, interviewType: interviewType, resumeID: resumeID, description: description, skills: skills)
            guard token == generation, !Task.isCancelled else { return nil }
            sessions.insert(item, at: 0); error = nil; return item
        } catch { if token == generation && !Task.isCancelled { self.error = "Couldn’t create the session: \(error.localizedDescription). Refresh before trying again." }; return nil }
    }

    func delete(_ item: AdaptiveSession) async {
        guard !loading else { return }; let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            try await factory(baseURL).deleteAdaptiveSession(id: item.id)
            guard token == generation, !Task.isCancelled else { return }
            sessions.removeAll { $0.id == item.id }; error = nil
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func open(_ id: UUID) async {
        generation = UUID(); let token = generation; loading = true; session = nil; turns = []; job = nil; report = nil; error = nil
        defer { if token == generation { loading = false } }
        do {
            let client = try factory(baseURL)
            let loaded = try await client.adaptiveSession(id: id)
            let page = try await client.adaptiveTurns(sessionID: id)
            let jobs = try await client.adaptiveJobs(sessionID: id)
            guard token == generation, !Task.isCancelled, loaded.id == id, page.items.allSatisfy({ $0.sessionID == id }) else { return }
            session = loaded; turns = page.items
            if loaded.status == "completed" { report = try await client.adaptiveReport(sessionID: id); return }
            if let active = jobs.items.first(where: { $0.stateVersion == loaded.stateVersion && ($0.status == .queued || $0.status == .running) }) {
                job = active; try await poll(active, client: client, token: token)
            } else if let failed = jobs.items.first(where: { $0.stateVersion == loaded.stateVersion && $0.status == .failed && $0.errorCode != "stale_state" && $0.errorCode != "stale_answer" }) {
                job = failed; error = adaptiveJobError(failed.errorCode)
            }
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func save(_ answer: String) async -> Bool {
        guard !loading, let session, let turn = turns.last else { return false }; let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            let saved = try await factory(baseURL).saveAdaptiveAnswer(sessionID: session.id, turnID: turn.id, answer: answer)
            guard token == generation, !Task.isCancelled, saved.sessionID == session.id, saved.id == turn.id else { return false }
            turns[turns.count - 1] = saved; job = nil; error = nil; return true
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription }; return false }
    }

    func request(turnID: UUID?, retry: Bool = false) async {
        guard !loading, let session else { return }; let token = generation; loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let client = try factory(baseURL)
            let current: AdaptiveJob
            if retry, let job { current = try await client.retryAdaptiveJob(sessionID: session.id, jobID: job.id) }
            else { current = try await client.requestAdaptiveJob(sessionID: session.id, turnID: turnID) }
            guard token == generation, !Task.isCancelled, current.sessionID == session.id, current.turnID == turnID else { return }
            try await poll(current, client: client, token: token)
        } catch { if token == generation && !Task.isCancelled { self.error = "Couldn’t check the request: \(error.localizedDescription). Reopen this session to check its status." } }
    }

    private func poll(_ initial: AdaptiveJob, client: any AdaptiveInterviewServicing, token: UUID) async throws {
        var current = initial
        for _ in 0..<90 {
            guard token == generation, !Task.isCancelled, current.id == initial.id, current.sessionID == initial.sessionID, current.turnID == initial.turnID else { return }
            job = current
            if current.status == .failed { error = adaptiveJobError(current.errorCode); return }
            if current.status == .completed {
                let page = try await client.adaptiveTurns(sessionID: initial.sessionID)
                guard token == generation, !Task.isCancelled, page.items.allSatisfy({ $0.sessionID == initial.sessionID }) else { return }
                turns = page.items; error = nil; return
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
            current = try await client.adaptiveJob(sessionID: initial.sessionID, jobID: initial.id)
        }
        if token == generation && !Task.isCancelled { error = "This is taking longer than expected. Reopen the session to check its status." }
    }

    private func adaptiveJobError(_ code: String?) -> String {
        if code == "invalid_output" {
            return "The AI couldn't produce feedback supported by your answer. Your answer is saved; please try again."
        }
        return "Interview request failed (\(code ?? "unknown error")). Your answer is saved; you can retry."
    }

    func complete() async {
        guard !loading, let session else { return }; let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            let client = try factory(baseURL)
            let completed = try await client.completeAdaptiveSession(sessionID: session.id)
            let loaded = try await client.adaptiveReport(sessionID: session.id)
            guard token == generation, !Task.isCancelled, completed.id == session.id else { return }
            self.session = completed; report = loaded; error = nil
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func loadProgress(more: Bool = false) async {
        guard !loading else { return }; let token = generation; loading = true
        defer { if token == generation { loading = false } }
        do {
            let page = try await factory(baseURL).adaptiveProgress(offset: more ? progress.count : 0)
            guard token == generation, !Task.isCancelled else { return }
            progress = more ? progress + page.items : page.items; hasMoreProgress = page.items.count == page.limit; error = nil
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
extension APIClient: InterviewServicing {}

@MainActor
final class InterviewViewModel: ObservableObject {
    @Published private(set) var sessions: [InterviewSession] = []
    @Published private(set) var questions: [InterviewQuestion] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingQuestions = false
    @Published private(set) var hasLoadedQuestions = false
    @Published private(set) var hasMore = false
    @Published private(set) var job: InterviewJob?
    @Published var error: String?
    var baseURL: String
    private var generation = UUID()
    private var accountGeneration = UUID()
    private var activeSessionID: UUID?
    private var jobsBySession: [UUID: InterviewJob] = [:]
    private let clientFactory: (String) throws -> any InterviewServicing

    init(baseURL: String = UserDefaults.standard.string(forKey: "baseURL") ?? "http://localhost:8000", clientFactory: @escaping (String) throws -> any InterviewServicing = { try APIClient.configured(baseURL: $0) }) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
    }

    func reset() {
        generation = UUID(); accountGeneration = UUID(); jobsBySession.removeAll(); sessions = []; questions = []; job = nil; error = nil; loading = false; loadingQuestions = false; hasLoadedQuestions = false; hasMore = false; activeSessionID = nil
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
            sessions.removeAll { $0.id == item.id }; jobsBySession[item.id] = nil; error = nil
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func open(_ sessionID: UUID) async {
        generation = UUID(); activeSessionID = sessionID; loading = false
        let token = generation
        questions = []; job = jobsBySession[sessionID]; error = nil; hasLoadedQuestions = false; loadingQuestions = false
        await refresh(sessionID)
        guard token == generation, activeSessionID == sessionID, hasLoadedQuestions, !Task.isCancelled, let job else { return }
        if job.status == .queued || job.status == .running {
            await checkStatus(sessionID: sessionID)
        } else if job.status == .failed {
            error = "Interview request failed (\(job.errorCode ?? "unknown error")). You can retry."
        }
    }

    func refresh(_ sessionID: UUID) async {
        guard !loadingQuestions else { return }
        let token = generation
        loadingQuestions = true
        defer { if token == generation { loadingQuestions = false } }
        do {
            let page = try await clientFactory(baseURL).interviewQuestions(sessionID: sessionID)
            guard token == generation, activeSessionID == sessionID, !Task.isCancelled else { return }
            guard page.items.allSatisfy({ $0.sessionID == sessionID }) else { throw URLError(.badServerResponse) }
            questions = page.items; hasLoadedQuestions = true; error = nil
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
            if job?.questionID == questionID { job = nil; jobsBySession[sessionID] = nil }
            error = nil; return true
        } catch { if token == generation && !Task.isCancelled { self.error = error.localizedDescription }; return false }
    }

    func request(sessionID: UUID, questionID: UUID?, retry: Bool = false) async {
        guard !loading else { return }
        let token = generation; let accountToken = accountGeneration; loading = true
        defer { if token == generation { loading = false } }
        do {
            let client = try clientFactory(baseURL)
            var current: InterviewJob
            if retry, let old = job { current = try await client.retryInterviewJob(sessionID: sessionID, jobID: old.id) }
            else { current = try await client.requestInterviewJob(sessionID: sessionID, questionID: questionID) }
            guard accountToken == accountGeneration, current.sessionID == sessionID, current.questionID == questionID else { return }
            jobsBySession[sessionID] = current
            if token != generation, activeSessionID == sessionID, job == nil, !loading {
                job = current
                if hasLoadedQuestions && error == nil && (current.status == .queued || current.status == .running) {
                    await checkStatus(sessionID: sessionID)
                } else if hasLoadedQuestions && error == nil && current.status == .failed {
                    error = "Interview request failed (\(current.errorCode ?? "unknown error")). You can retry."
                }
                return
            }
            guard token == generation, activeSessionID == sessionID, !Task.isCancelled else { return }
            error = nil
            try await poll(current: &current, client: client, sessionID: sessionID, questionID: questionID, token: token)
        } catch is CancellationError { return }
        catch { if token == generation && !Task.isCancelled { self.error = "Couldn’t check the interview: \(error.localizedDescription). You can check again." } }
    }

    func checkStatus(sessionID: UUID) async {
        guard !loading, var current = job, current.sessionID == sessionID,
              current.status == .queued || current.status == .running else { return }
        let token = generation; loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let client = try clientFactory(baseURL)
            current = try await client.interviewJob(sessionID: sessionID, jobID: current.id)
            let questionID = current.questionID
            try await poll(current: &current, client: client, sessionID: sessionID, questionID: questionID, token: token)
        } catch is CancellationError { return }
        catch { if token == generation && !Task.isCancelled { self.error = "Couldn’t check the interview: \(error.localizedDescription). You can check again." } }
    }

    private func poll(current: inout InterviewJob, client: any InterviewServicing, sessionID: UUID, questionID: UUID?, token: UUID) async throws {
            for _ in 0..<90 {
                guard token == generation, !Task.isCancelled, current.sessionID == sessionID, current.questionID == questionID else { return }
                job = current; jobsBySession[sessionID] = current
                if current.status == .completed { await refresh(sessionID); return }
                if current.status == .failed { error = "Interview request failed (\(current.errorCode ?? "unknown error")). You can retry."; return }
                try await Task.sleep(nanoseconds: 2_000_000_000)
                current = try await client.interviewJob(sessionID: sessionID, jobID: current.id)
            }
            if token == generation && activeSessionID == sessionID && !Task.isCancelled {
                error = "This is taking longer than expected. Check the status again."
            }
    }
}
