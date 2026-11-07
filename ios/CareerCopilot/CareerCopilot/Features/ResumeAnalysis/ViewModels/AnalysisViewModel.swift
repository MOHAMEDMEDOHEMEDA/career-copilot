import Combine
import Foundation

protocol AnalysisServicing {
    func startAnalysis(resumeID: UUID) async throws -> AnalysisJob
    func analysisJob(id: UUID) async throws -> AnalysisJob
    func analysisHistory(resumeID: UUID, offset: Int) async throws -> [AnalysisJob]
}

extension APIClient: AnalysisServicing {}

@MainActor
final class AnalysisViewModel: ObservableObject {
    enum State {
        case idle
        case submitting
        case waiting(AnalysisJob.Status)
        case completed(ResumeAnalysis)
        case failed(String)
        case paused(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var pollingToken: UUID?
    @Published private(set) var history: [AnalysisJob] = []
    @Published private(set) var historyError: String?
    @Published private(set) var loadingHistory = false
    @Published private(set) var hasMoreHistory = false
    private(set) var jobID: UUID?
    private let resumeID: UUID
    private let service: any AnalysisServicing
    private let maxPolls: Int
    private let wait: () async throws -> Void

    init(
        resumeID: UUID,
        service: any AnalysisServicing,
        maxPolls: Int = 90,
        wait: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 2_000_000_000) }
    ) {
        self.resumeID = resumeID
        self.service = service
        self.maxPolls = maxPolls
        self.wait = wait
    }

    func start() async {
        if case .submitting = state { return }
        pollingToken = nil
        jobID = nil
        state = .submitting
        do {
            let job = try await service.startAnalysis(resumeID: resumeID)
            guard !Task.isCancelled else {
                state = .failed("The request was interrupted and may have reached the server. Check before starting another analysis.")
                return
            }
            guard job.resumeID == resumeID else {
                state = .failed("The server returned an unexpected job.")
                return
            }
            jobID = job.id
            apply(job)
            if case .waiting = state { pollingToken = UUID() }
        } catch {
            if Task.isCancelled {
                state = .failed("The request was interrupted and may have reached the server. Check before starting another analysis.")
                return
            }
            state = .failed("Couldn’t start analysis: \(error.localizedDescription) The request may have reached the server; check before starting another analysis.")
        }
    }

    func checkStatus() {
        guard jobID != nil else { return }
        state = .waiting(.queued)
        pollingToken = UUID()
    }

    func loadHistory(reset: Bool = true) async {
        guard !loadingHistory else { return }
        loadingHistory = true
        defer { loadingHistory = false }
        do {
            let jobs = try await service.analysisHistory(resumeID: resumeID, offset: reset ? 0 : history.count)
            guard jobs.allSatisfy({ $0.resumeID == resumeID }) else { throw URLError(.badServerResponse) }
            history = reset ? jobs : history + jobs
            hasMoreHistory = jobs.count == 20
            historyError = nil
        } catch {
            guard !Task.isCancelled else { return }
            historyError = error.localizedDescription
        }
    }

    func select(_ job: AnalysisJob) {
        guard job.resumeID == resumeID else { return }
        pollingToken = nil
        jobID = job.id
        apply(job)
        if case .waiting = state { pollingToken = UUID() }
    }

    func poll() async {
        guard let jobID, case .waiting = state else { return }
        do {
            for _ in 0..<maxPolls {
                try Task.checkCancellation()
                let job = try await service.analysisJob(id: jobID)
                try Task.checkCancellation()
                guard job.id == jobID, job.resumeID == resumeID else {
                    state = .paused("The server returned an unexpected job. Check its status again.")
                    return
                }
                apply(job)
                guard case .waiting = state else { return }
                try await wait()
            }
            guard !Task.isCancelled else { return }
            state = .paused("Analysis is taking longer than expected. Check its status again later.")
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .paused("Couldn’t check analysis status: \(error.localizedDescription)")
        }
    }

    private func apply(_ job: AnalysisJob) {
        switch job.status {
        case .queued, .running:
            state = .waiting(job.status)
        case .completed:
            if let result = job.result { state = .completed(result) }
            else { state = .failed("The analysis finished without a result.") }
        case .failed:
            switch job.errorCode {
            case "rate_limited": state = .failed("An AI provider is rate-limited. Check its limits and try again later.")
            case "timeout": state = .failed("The analysis timed out. You can start a new analysis when you’re ready.")
            case "provider_error", "provider_unavailable": state = .failed("An AI provider is unavailable. Check your connection and try again later.")
            case "provider_auth": state = .failed("An AI provider rejected the request. Check the backend provider settings.")
            case "invalid_output": state = .failed("The AI response could not be validated. You can start a new analysis when you’re ready.")
            case "output_limit": state = .failed("The AI response was too long. Try a shorter resume.")
            case "invalid_input": state = .failed("The resume is empty or too long to analyze. Review its text and try again.")
            default: state = .failed("Analysis failed. You can start a new analysis when you’re ready.")
            }
        }
    }
}
