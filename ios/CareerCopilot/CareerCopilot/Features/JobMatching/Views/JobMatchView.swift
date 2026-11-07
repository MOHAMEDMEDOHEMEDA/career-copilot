import SwiftUI

struct JobMatchView: View {
    @StateObject private var model: JobMatchViewModel
    @State private var confirm = false
    @State private var submission: Task<Void, Never>?

    init(model: JobMatchViewModel) { _model = StateObject(wrappedValue: model) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch model.state {
                case .idle:
                    Text("Paste a job description").font(.title2.bold())
                    Text("Compare its requirements with your resume. Use synthetic data until privacy and retention have been reviewed.").foregroundStyle(.secondary)
                    TextEditor(text: $model.description).frame(minHeight: 200).padding(8).careerCard().accessibilityLabel("Job description")
                    Text("\(model.description.unicodeScalars.count) / 20,000 characters").font(.caption).foregroundStyle(.secondary)
                    Button("Compare with resume") { confirm = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.description.unicodeScalars.count > 20_000)
                case .submitting:
                    ProgressView("Starting comparison")
                case .waiting(let status):
                    ProgressView(status == .running ? "Comparing your resume" : "Waiting for comparison")
                    Text("The job continues on the server if you leave this screen.").font(.subheadline).foregroundStyle(.secondary)
                    jobReference
                case .paused(let message):
                    Label(message, systemImage: "exclamationmark.circle")
                    jobReference
                    Button("Check status") { model.checkStatus() }.buttonStyle(.borderedProminent)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.circle")
                    jobReference
                    Button("Edit and try again") { model.edit() }.buttonStyle(.bordered)
                case .completed(let result):
                    Text("Review before you use it").font(.headline)
                    Text("AI can make mistakes. A requirement not demonstrated in your resume does not mean you lack it.").font(.subheadline).foregroundStyle(.secondary)
                    section("Skills with resume evidence", items: result.requiredSkillsFound.map { "\($0.skill)\n“\($0.resumeEvidence)”" })
                    section("Not demonstrated in resume", items: result.requiredSkillsNotDemonstrated)
                    section("Experience alignment", items: [result.experienceAlignment])
                    section("Recommendations", items: result.recommendations)
                    section("Interview topics", items: result.interviewTopics)
                    Button("Compare another job") { model.edit() }.buttonStyle(.bordered)
                }
            }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CareerStyle.canvas)
        .navigationTitle("Job matching")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Send this comparison for analysis?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Send for comparison") { submission = Task { await model.start() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your resume and job description may be sent to OpenRouter and Google Gemini, or processed by local Ollama if another provider fails. Google’s free tier may use content to improve its products. Use synthetic data until privacy and retention are reviewed.")
        }
        .task(id: model.pollingToken) { await model.poll() }
        .onDisappear { submission?.cancel() }
    }

    @ViewBuilder private var jobReference: some View {
        if let id = model.jobID { Text("Job ID: \(id.uuidString)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
    }

    private func section(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if items.isEmpty { Text("None identified").foregroundStyle(.secondary) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in Text(item).frame(maxWidth: .infinity, alignment: .leading) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).careerCard()
    }
}

#Preview {
    NavigationStack { JobMatchView(model: JobMatchViewModel(resumeID: UUID(), service: PreviewMatchService())) }
}

private struct PreviewMatchService: JobMatchServicing {
    func startMatch(resumeID: UUID, description: String) async throws -> MatchJob { throw CancellationError() }
    func matchJob(id: UUID) async throws -> MatchJob { throw CancellationError() }
}
