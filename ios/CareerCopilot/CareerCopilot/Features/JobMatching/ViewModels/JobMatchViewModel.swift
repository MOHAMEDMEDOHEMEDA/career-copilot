import Combine
import Foundation

protocol JobMatchServicing {
    func startMatch(resumeID: UUID, description: String) async throws -> MatchJob
    func matchJob(id: UUID) async throws -> MatchJob
}
extension APIClient: JobMatchServicing {}

@MainActor
final class JobMatchViewModel: ObservableObject {
    enum State {
        case idle, submitting
        case waiting(AnalysisJob.Status)
        case completed(JobMatch)
        case failed(String)
        case paused(String)
    }
    @Published var description = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var pollingToken: UUID?
    private(set) var jobID: UUID?
    private let resumeID: UUID
    private let service: any JobMatchServicing
    private let maxPolls: Int
    private let wait: () async throws -> Void

    init(resumeID: UUID, service: any JobMatchServicing, maxPolls: Int = 90, wait: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 2_000_000_000) }) {
        self.resumeID = resumeID
        self.service = service
        self.maxPolls = maxPolls
        self.wait = wait
    }

    func start() async {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, description.count <= 20_000 else {
            state = .failed("Enter a job description of up to 20,000 characters.")
            return
        }
        if case .submitting = state { return }
        pollingToken = nil
        jobID = nil
        state = .submitting
        do {
            let job = try await service.startMatch(resumeID: resumeID, description: description)
            guard !Task.isCancelled else { state = .failed("The request may have reached the server. Check before starting again."); return }
            guard job.resumeID == resumeID else { state = .failed("The server returned an unexpected job."); return }
            jobID = job.id
            apply(job)
            if case .waiting = state { pollingToken = UUID() }
        } catch {
            state = .failed("Couldn’t start matching: \(error.localizedDescription). The request may have reached the server; check before starting again.")
        }
    }

    func checkStatus() {
        guard jobID != nil else { return }
        state = .waiting(.queued)
        pollingToken = UUID()
    }

    func edit() { pollingToken = nil; state = .idle }

    func poll() async {
        guard let jobID, case .waiting = state else { return }
        do {
            for _ in 0..<maxPolls {
                try Task.checkCancellation()
                let job = try await service.matchJob(id: jobID)
                try Task.checkCancellation()
                guard job.id == jobID, job.resumeID == resumeID else { state = .paused("The server returned an unexpected job."); return }
                apply(job)
                guard case .waiting = state else { return }
                try await wait()
            }
            guard !Task.isCancelled else { return }
            state = .paused("Matching is taking longer than expected. Check the status again later.")
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .paused("Couldn’t check status: \(error.localizedDescription)")
        }
    }

    private func apply(_ job: MatchJob) {
        switch job.status {
        case .queued, .running: state = .waiting(job.status)
        case .completed:
            if let result = job.result { state = .completed(result) }
            else { state = .failed("Matching finished without a result.") }
        case .failed:
            switch job.errorCode {
            case "rate_limited": state = .failed("The available AI providers are rate-limited. Check their limits and try again later.")
            case "timeout": state = .failed("Matching timed out. You can try again later.")
            case "unsupported_evidence": state = .failed("The AI returned a quote that could not be verified in your resume, so the result was rejected. You can try again.")
            case "invalid_output": state = .failed("The AI returned an invalid result, so it was not shown. You can try again.")
            case "output_limit": state = .failed("The AI response was too long to complete. Try a shorter job description.")
            case "invalid_input": state = .failed("The resume or job description is empty or too long. Check both and try again.")
            case "provider_auth": state = .failed("An AI provider rejected the request. Check your backend provider credentials and account settings.")
            case "provider_unavailable": state = .failed("The AI provider is unavailable right now. Please try again later.")
            case "provider_error": state = .failed("The AI provider could not complete the request. Please try again later.")
            default: state = .failed("Matching couldn’t finish. You can try again later.")
            }
        }
    }
}
