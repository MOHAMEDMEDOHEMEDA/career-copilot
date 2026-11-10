import SwiftUI

struct AnalysisView: View {
    @StateObject private var model: AnalysisViewModel
    @State private var confirmSubmission = false
    @State private var submissionTask: Task<Void, Never>?

    init(model: AnalysisViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch model.state {
                case .idle:
                    intro
                case .submitting:
                    ProgressView("Starting analysis")
                        .frame(maxWidth: .infinity).padding()
                case .waiting(let status):
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView(LocalizedStringKey(status == .running ? "Analyzing your resume" : "Waiting for analysis"))
                        Text("You can leave this screen and return while the app stays open. The job continues on the server.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        jobReference
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20).careerCard()
                case .completed(let analysis):
                    results(analysis)
                    Button("Start a new analysis") { confirmSubmission = true }.buttonStyle(.bordered)
                case .failed(let message):
                    statusCard(title: "Analysis couldn’t finish", message: message)
                    jobReference
                    Button("Start a new analysis") { confirmSubmission = true }
                        .careerPrimaryButton()
                case .paused(let message):
                    statusCard(title: "Status unavailable", message: message)
                    jobReference
                    Button("Check status") { model.checkStatus() }
                        .careerPrimaryButton()
                }
                historySection
            }
            .padding(20)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CareerStyle.gradient.ignoresSafeArea())
        .navigationTitle("Resume analysis")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Send this resume for analysis?", isPresented: $confirmSubmission, titleVisibility: .visible) {
            Button("Send for analysis") { submissionTask = Task { await model.start() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your resume may be sent to OpenRouter and Google Gemini, or processed by local Ollama if another provider fails. Google’s free tier may use content to improve its products. Use synthetic resumes until privacy and retention have been reviewed.")
        }
        .task { await model.loadHistory() }
        .task(id: model.pollingToken) {
            await model.poll()
            if !Task.isCancelled { await model.loadHistory() }
        }
        .onDisappear { submissionTask?.cancel() }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Previous analyses").font(.headline)
            Text("Results reflect the resume as it was when analyzed.").font(.footnote).foregroundStyle(.secondary)
            if model.loadingHistory { ProgressView("Loading history") }
            if let error = model.historyError {
                Text("Couldn’t load history: \(error)").font(.footnote)
                Button("Try again") { Task { await model.loadHistory() } }
            } else if model.history.isEmpty && !model.loadingHistory {
                Text("No previous analyses.").foregroundStyle(.secondary)
            }
            ForEach(model.history) { job in
                Button { model.select(job) } label: {
                    VStack(alignment: .leading) {
                        Text(job.status.rawValue.capitalized)
                        if let date = job.createdAt { Text(displayDate(date)).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered)
            }
            if model.hasMoreHistory {
                Button("Load more") { Task { await model.loadHistory(reset: false) } }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).careerCard()
    }

    private func displayDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: value)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? formatter.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            GradientIcon(symbol: "sparkles")
            Text("Review your resume").font(.title2.bold())
            Text("Get a structured summary and suggestions based on your resume. Review every suggestion before using it.")
                .foregroundStyle(.secondary)
            Text("Your resume may be sent to OpenRouter and Google Gemini, or processed locally with Ollama. For now, use synthetic resumes only.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Start analysis") { confirmSubmission = true }
                .careerPrimaryButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).careerCard()
    }

    @ViewBuilder
    private var jobReference: some View {
        if let jobID = model.jobID {
            Text("Job ID: \(jobID.uuidString)")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private func statusCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.circle").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).careerCard()
    }

    private func results(_ analysis: ResumeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review before you use it")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("AI suggestions can be incorrect. Keep only details supported by your resume.")
                .font(.footnote).foregroundStyle(.secondary)
            section("Summary", items: [analysis.summary])
            section("Technical skills", items: analysis.technicalSkills)
            section("Soft skills", items: analysis.softSkills)
            section("Experience", items: analysis.experience.map { "\($0.role) · \($0.organization)\n\($0.details)" })
            section("Education", items: analysis.education.map { "\($0.qualification) · \($0.institution)" })
            section("Strengths", items: analysis.strengths)
            section("Suggestions", items: analysis.improvementSuggestions)
            section("Missing or unclear", items: analysis.missingOrUnclearInformation)
            if !analysis.bulletRewrites.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggested rewrites").font(.headline)
                    ForEach(Array(analysis.bulletRewrites.enumerated()), id: \.offset) { _, bullet in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Original").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(bullet.original)
                            Text("Suggestion").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(bullet.rewrite)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20).careerCard()
            }
        }
    }

    private func section(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("Not provided").foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).careerCard()
    }
}

#Preview {
    NavigationStack {
        AnalysisView(model: AnalysisViewModel(resumeID: UUID(), service: PreviewAnalysisService()))
    }
    .preferredColorScheme(.dark)
}

private struct PreviewAnalysisService: AnalysisServicing {
    func startAnalysis(resumeID: UUID) async throws -> AnalysisJob { throw CancellationError() }
    func analysisJob(id: UUID) async throws -> AnalysisJob { throw CancellationError() }
    func analysisHistory(resumeID: UUID, offset: Int) async throws -> [AnalysisJob] { [] }
}
