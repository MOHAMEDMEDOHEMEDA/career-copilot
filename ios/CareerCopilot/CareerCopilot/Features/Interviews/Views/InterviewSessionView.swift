import SwiftUI
import AVFoundation
import UIKit

struct InterviewSessionView: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @ObservedObject var model: InterviewViewModel
    let interview: InterviewSession
    @State private var selected: InterviewQuestion?
    @State private var confirmGeneration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("PRACTICE SESSION").font(.caption.weight(.semibold)).tracking(layoutDirection == .rightToLeft ? 0 : 1.3).foregroundStyle(ChatStyle.cyan)
                Text("Let’s get you ready.").font(.largeTitle.bold()).foregroundStyle(.white)
                Text(interview.jobDescription).lineLimit(4).foregroundStyle(ChatStyle.muted)
                if model.loadingQuestions && !model.hasLoadedQuestions {
                    ProgressView("Loading your interview…").tint(.white).foregroundStyle(.white)
                } else if model.hasLoadedQuestions && model.questions.isEmpty && model.error == nil && model.job?.status != .queued && model.job?.status != .running {
                    Text("Generate three questions tailored to this role and resume.").foregroundStyle(.white)
                    Button("Generate questions") { confirmGeneration = true }.careerPrimaryButton().disabled(model.loading)
                }
                if model.loading { ProgressView("Working on your interview…").tint(.white).foregroundStyle(.white); Text("You can return to this session later.").font(.caption).foregroundStyle(ChatStyle.muted) }
                if let error = model.error {
                    Text(error).foregroundStyle(.white)
                    if !model.hasLoadedQuestions {
                        Button("Refresh questions") { Task { await model.open(interview.id) } }.disabled(model.loadingQuestions)
                    } else if let job = model.job, job.questionID == nil, job.status == .failed {
                        Button("Retry generation") { confirmGeneration = true }.disabled(model.loading)
                    } else if let job = model.job, job.questionID == nil, job.status == .queued || job.status == .running {
                        Button("Check status") { Task { await model.checkStatus(sessionID: interview.id) } }.disabled(model.loading)
                    } else { Button("Refresh") { Task { await model.refresh(interview.id) } } }
                }
                if !model.questions.isEmpty {
                    let answered = model.questions.filter { $0.answer != nil }.count
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your progress").font(.headline).foregroundStyle(.white)
                        ProgressView(value: Double(answered), total: Double(model.questions.count)).tint(ChatStyle.cyan)
                        Text("\(answered) of \(model.questions.count) answers saved").font(.caption).foregroundStyle(ChatStyle.muted)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                ForEach(model.questions) { question in
                    Button { selected = question } label: {
                        HStack(alignment: .top, spacing: 15) {
                            Text("\(question.sequence)").font(.headline).foregroundStyle(ChatStyle.cyan).frame(width: 40, height: 40).background(.white.opacity(0.07), in: Circle())
                            VStack(alignment: .leading, spacing: 8) {
                                Text(question.prompt).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading)
                                Text(LocalizedStringKey(question.feedback != nil ? "Feedback ready" : question.answer != nil ? "Answer saved" : "Ready to answer")).font(.caption).foregroundStyle(ChatStyle.muted)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(ChatStyle.muted)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }
        .background(ChatStyle.gradient.ignoresSafeArea()).tint(ChatStyle.cyan)
        .navigationTitle("Your interview").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $selected) { question in InterviewAnswerView(model: model, sessionID: interview.id, questionID: question.id) }
        .alert("Generate interview questions?", isPresented: $confirmGeneration) {
            Button("Continue") { Task { await model.request(sessionID: interview.id, questionID: nil, retry: model.job?.status == .failed && model.job?.questionID == nil) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your resume and job description are sent to the configured AI providers, including cloud providers if fallback is needed.") }
        .task { await model.open(interview.id) }
    }
}

struct InterviewAnswerView: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: InterviewViewModel
    let sessionID: UUID
    let questionID: UUID
    @State private var answer = ""
    @State private var confirmFeedback = false
    @State private var confirmDiscard = false
    private var question: InterviewQuestion? { model.questions.first { $0.id == questionID } }
    private var hasUnsavedChanges: Bool { answer != (question?.answer ?? "") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let question {
                        Text("QUESTION \(question.sequence)").font(.caption.weight(.semibold)).tracking(layoutDirection == .rightToLeft ? 0 : 1).foregroundStyle(ChatStyle.cyan)
                        Text(question.prompt).font(.title2.bold()).foregroundStyle(.white)
                        Text("Your answer").font(.headline).foregroundStyle(.white)
                        TextEditor(text: $answer).scrollContentBackground(.hidden).foregroundStyle(.white).padding(8).frame(minHeight: 180).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 16)).accessibilityLabel("Your answer")
                        Text("\(answer.unicodeScalars.count) / 4,000").font(.caption).foregroundStyle(ChatStyle.muted)
                        if hasUnsavedChanges { Text("Save your changes before requesting feedback.").font(.caption).foregroundStyle(ChatStyle.muted) }
                        Button("Save answer") { Task { _ = await model.save(sessionID: sessionID, questionID: questionID, answer: answer) } }
                            .careerPrimaryButton().disabled(model.loading || !hasUnsavedChanges || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || answer.unicodeScalars.count > 4000)
                        if question.answer != nil {
                            Button("Get feedback") { confirmFeedback = true }.buttonStyle(.bordered).disabled(model.loading || answer != question.answer)
                        }
                        if let feedback = question.feedback, !hasUnsavedChanges { InterviewFeedbackView(feedback: feedback) }
                    }
                    if model.loading { ProgressView("Working on your answer…").tint(.white).foregroundStyle(.white) }
                    if let error = model.error {
                        Text(error).foregroundStyle(.white)
                        if let job = model.job, job.questionID == questionID, job.status == .failed { Button("Retry feedback") { confirmFeedback = true }.disabled(model.loading || hasUnsavedChanges) }
                        else if let job = model.job, job.questionID == questionID, job.status == .queued || job.status == .running { Button("Check status") { Task { await model.checkStatus(sessionID: sessionID) } }.disabled(model.loading) }
                    }
                }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
            }.background(ChatStyle.gradient.ignoresSafeArea()).tint(ChatStyle.cyan)
            .navigationTitle("Practice answer").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if hasUnsavedChanges { confirmDiscard = true } else { dismiss() } } } }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .onAppear { answer = question?.answer ?? "" }
            .alert("Get AI feedback?", isPresented: $confirmFeedback) {
                Button("Continue") { Task { await model.request(sessionID: sessionID, questionID: questionID, retry: model.job?.status == .failed && model.job?.questionID == questionID) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your resume, job description, question, and answer are sent to the configured AI providers, including cloud providers if fallback is needed.") }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your unsaved answer will be lost.") }
        }
    }
}

struct InterviewFeedbackView: View {
    let feedback: InterviewFeedback
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your feedback").font(.title3.bold())
            Text("Practice guidance, not a measure of employability.").font(.caption).foregroundStyle(ChatStyle.muted)
            criterion("Correctness", feedback.correctness)
            criterion("Completeness", feedback.completeness)
            criterion("Relevance", feedback.relevance)
            criterion("Clarity", feedback.clarity)
            if !feedback.strengths.isEmpty { Text("Strengths").font(.headline); ForEach(feedback.strengths, id: \.self) { Text("• \($0)") } }
            if !feedback.improvements.isEmpty { Text("Ways to improve").font(.headline); ForEach(feedback.improvements, id: \.self) { Text("• \($0)") } }
            Text("Illustrative answer").font(.headline)
            Text("Adapt this suggestion using only details that are true for you.").font(.caption).foregroundStyle(ChatStyle.muted)
            Text(feedback.exampleAnswer)
        }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(18).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private func criterion(_ title: String, _ item: InterviewFeedback.Criterion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) · \(item.rating.replacingOccurrences(of: "_", with: " ").capitalized)").font(.headline)
            Text(item.explanation).font(.subheadline).foregroundStyle(ChatStyle.muted)
        }
    }
}

#Preview("Interview session") {
    NavigationStack { InterviewSessionView(model: InterviewViewModel(), interview: InterviewSession(id: UUID(), resumeID: UUID(), jobDescription: "Software engineer", status: "draft")) }
}

#Preview("Answer") {
    InterviewAnswerView(model: InterviewViewModel(), sessionID: UUID(), questionID: UUID())
}

#Preview("Feedback") {
    let item = InterviewFeedback.Criterion(rating: "developing", explanation: "Add a specific example.")
    InterviewFeedbackView(feedback: InterviewFeedback(correctness: item, completeness: item, relevance: item, clarity: item, strengths: ["Clear structure"], improvements: ["Add detail"], exampleAnswer: "Describe your own experience here."))
        .padding().background(ChatStyle.background)
}

struct AdaptiveSessionView: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @ObservedObject var model: AdaptiveInterviewViewModel
    let sessionID: UUID
    @State private var showingAnswer = false
    @State private var confirmRequest = false
    @State private var confirmComplete = false
    @State private var retry = false
    @State private var targetTurn: UUID?
    private var current: AdaptiveTurn? { model.turns.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let session = model.session {
                    Text("\(session.seniority.uppercased()) · \(session.interviewType.uppercased())").font(.caption.weight(.semibold)).tracking(layoutDirection == .rightToLeft ? 0 : 1).foregroundStyle(ChatStyle.cyan)
                    Text(session.role).font(.largeTitle.bold()).foregroundStyle(.white)
                    if let report = model.report { AdaptiveReportView(report: report) }
                    else if session.status == "completed" { Text("Your interview is complete.").foregroundStyle(.white) }
                    else if let current {
                        Text("QUESTION \(current.sequence) · \(current.topic.uppercased()) · LEVEL \(current.difficulty)").font(.caption.weight(.semibold)).foregroundStyle(ChatStyle.cyan)
                        Text(current.prompt).font(.title2.bold()).foregroundStyle(.white)
                        if let answer = current.answer {
                            Text("Saved answer").font(.headline).foregroundStyle(.white)
                            Text(answer).foregroundStyle(ChatStyle.muted).textSelection(.enabled)
                        }
                        Button(LocalizedStringKey(current.answer == nil ? "Write answer" : "Edit answer")) { showingAnswer = true }.buttonStyle(.bordered).disabled(model.loading)
                        if let evaluation = current.evaluation {
                            AdaptiveFeedbackView(evaluation: evaluation)
                            Button("Next question") { targetTurn = nil; retry = false; confirmRequest = true }.careerPrimaryButton().disabled(model.loading)
                            Button("Complete interview") { confirmComplete = true }.buttonStyle(.bordered).disabled(model.loading)
                        } else if current.answer != nil {
                            Button("Get feedback") { targetTurn = current.id; retry = false; confirmRequest = true }.careerPrimaryButton().disabled(model.loading)
                        }
                        if model.turns.count > 1 {
                            DisclosureGroup("Previous questions (\(model.turns.count - 1))") {
                                ForEach(Array(model.turns.dropLast())) { turn in
                                    VStack(alignment: .leading, spacing: 6) { Text(turn.prompt).font(.headline); if let answer = turn.answer { Text(answer).foregroundStyle(ChatStyle.muted) }; if let evaluation = turn.evaluation { Text(evaluation.feedback).font(.subheadline) } }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                                }
                            }.foregroundStyle(.white).tint(ChatStyle.cyan)
                        }
                    } else if !model.loading && model.error == nil {
                        Text("Start with a question tailored to your role and selected context.").foregroundStyle(ChatStyle.muted)
                        Button("Generate first question") { targetTurn = nil; retry = false; confirmRequest = true }.careerPrimaryButton()
                    }
                }
                if model.loading { ProgressView("Working on your interview…").tint(.white).foregroundStyle(.white) }
                if let error = model.error {
                    Text(error).foregroundStyle(.white)
                    if let job = model.job, job.status == .failed {
                        Button("Retry request") { targetTurn = job.turnID; retry = true; confirmRequest = true }.disabled(model.loading)
                    } else { Button("Check session") { Task { await model.open(sessionID) } }.disabled(model.loading) }
                }
            }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }.background(ChatStyle.gradient.ignoresSafeArea()).tint(ChatStyle.cyan)
        .navigationTitle("Adaptive practice").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingAnswer) { AdaptiveAnswerView(model: model) }
        .confirmationDialog("Send this request?", isPresented: $confirmRequest, titleVisibility: .visible) {
            Button("Continue") { Task { await model.request(turnID: targetTurn, retry: retry) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Selected skills, resume skill mentions and short resume excerpts, job details, questions and answers may be sent to OpenRouter and Google Gemini, or processed by local Ollama. Google’s free tier may use content to improve its products. Use synthetic data until privacy is reviewed.") }
        .confirmationDialog("Complete this interview?", isPresented: $confirmComplete, titleVisibility: .visible) { Button("Complete interview") { Task { await model.complete() } }; Button("Cancel", role: .cancel) {} } message: { Text("You can review the report after completing the interview.") }
        .task { await model.open(sessionID) }
    }
}

struct AdaptiveAnswerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: AdaptiveInterviewViewModel
    @StateObject private var dictation = InterviewDictation()
    @State private var draft = ""
    @State private var dictationPrefix = ""
    @State private var discard = false
    @State private var confirmSubmission = false
    @State private var skippedAnswer = false
    private var current: AdaptiveTurn? { model.turns.last }
    private var changed: Bool { draft != (current?.answer ?? "") }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let current { Text(current.prompt).font(.title2.bold()).foregroundStyle(.white) }
                    TextEditor(text: $draft).scrollContentBackground(.hidden).foregroundStyle(.white).padding(8).frame(minHeight: 200).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 16)).accessibilityLabel("Your answer").disabled(dictation.isActive)
                    Text("\(draft.unicodeScalars.count) / 4,000").font(.caption).foregroundStyle(ChatStyle.muted)
                    HStack(spacing: 12) {
                        Button {
                            if dictation.isPreparing { dictation.cancel() }
                            else if dictation.isRecording { dictation.stop() }
                            else {
                                dictationPrefix = draft
                                Task { await dictation.start(locale: locale) }
                            }
                        } label: {
                            Label(LocalizedStringKey(dictation.isPreparing ? "Cancel dictation" : dictation.isRecording ? "Stop dictation" : "Dictate answer"), systemImage: dictation.isRecording ? "stop.circle.fill" : "mic.fill")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.loading || dictation.isFinishing || (!dictation.isActive && draft.unicodeScalars.count >= 4000))
                        if dictation.isPreparing || dictation.isFinishing { ProgressView().tint(.white).accessibilityLabel(dictation.isPreparing ? "Preparing dictation" : "Finishing dictation") }
                    }
                    Text(LocalizedStringKey(dictation.isRecording ? "Listening… Tap Stop when you’re finished." : dictation.isFinishing ? "Finishing transcription…" : "On-device dictation. Review and edit the text before saving."))
                        .font(.caption).foregroundStyle(ChatStyle.muted)
                    if draft.unicodeScalars.count > 4000 { Text("Your answer is over the limit. Edit it before saving.").font(.caption).foregroundStyle(.orange) }
                    if let error = dictation.error {
                        Text(LocalizedStringKey(error)).font(.subheadline).foregroundStyle(.white)
                        if dictation.needsSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                            Button("Open Settings") { openURL(url) }.frame(minHeight: 44)
                        }
                    }
                    if let error = model.error { Text(error).foregroundStyle(.white) }
                    Button("Submit answer for feedback") { skippedAnswer = false; confirmSubmission = true }.careerPrimaryButton().disabled(model.loading || dictation.isActive || !changed || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unicodeScalars.count > 4000)
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("I don't know — show an example answer") { skippedAnswer = true; confirmSubmission = true }
                            .buttonStyle(.bordered).disabled(model.loading || dictation.isActive)
                    }
                }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
            }.background(ChatStyle.gradient.ignoresSafeArea()).tint(ChatStyle.cyan).navigationTitle("Your answer").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { if changed { discard = true } else { dismiss() } }.disabled(dictation.isActive) } }
            .interactiveDismissDisabled(changed || dictation.isActive).onAppear { draft = current?.answer ?? "" }
            .onChange(of: dictation.transcript) { _, transcript in
                draft = DictationDraft.appending(transcript, to: dictationPrefix)
                if draft.unicodeScalars.count > 4000 && dictation.isRecording { dictation.stop() }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .background { dictation.cancel() } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                if let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   AVAudioSession.InterruptionType(rawValue: raw) == .began, dictation.isRecording {
                    dictation.stop()
                }
            }
            .onDisappear { dictation.cancel() }
            .confirmationDialog("Discard your changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} }
            .confirmationDialog("Submit your answer for feedback?", isPresented: $confirmSubmission, titleVisibility: .visible) {
                Button("Submit answer") {
                    guard let turnID = current?.id else { return }
                    Task {
                        if await model.save(skippedAnswer ? "I don't know." : draft) {
                            dismiss()
                            await model.request(turnID: turnID)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your answer, selected skills, resume skill mentions and short resume excerpts, job details and questions may be sent to OpenRouter and Google Gemini, or processed by local Ollama. Google’s free tier may use content to improve its products. Use synthetic data until privacy is reviewed.") }
        }.preferredColorScheme(.dark)
    }
}

struct AdaptiveFeedbackView: View {
    let evaluation: AdaptiveEvaluation
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coaching feedback").font(.title3.bold())
            Text("Approximate feedback, not a measure of employability.").font(.caption).foregroundStyle(ChatStyle.muted)
            if let score = evaluation.overallScore { Text("Practice score: \(score) / 4").font(.headline) }
            Text(evaluation.feedback)
            if let example = evaluation.exampleAnswer, !example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Example answer").font(.headline)
                Text(example)
                Text("AI-generated study guidance; check cited references where available.").font(.caption).foregroundStyle(ChatStyle.muted)
            }
            criterion("Correctness", evaluation.correctness); criterion("Completeness", evaluation.completeness); criterion("Reasoning", evaluation.reasoning); criterion("Communication", evaluation.communication)
            if !evaluation.evidence.isEmpty { Text("From your answer").font(.headline); ForEach(Array(evaluation.evidence.enumerated()), id: \.offset) { _, value in Text("“\(value)”").foregroundStyle(ChatStyle.muted) } }
            if !evaluation.demonstratedConcepts.isEmpty { Text("Concepts demonstrated").font(.headline); ForEach(Array(evaluation.demonstratedConcepts.enumerated()), id: \.offset) { _, value in Text("• \(value)") } }
            if !evaluation.missingConcepts.isEmpty { Text("Topics to review").font(.headline); ForEach(Array(evaluation.missingConcepts.enumerated()), id: \.offset) { _, value in Text("• \(value)") } }
            if !evaluation.inaccuracies.isEmpty { Text("Possible inaccuracies").font(.headline); ForEach(Array(evaluation.inaccuracies.enumerated()), id: \.offset) { _, value in Text("• \(value)") } }
            ForEach(evaluation.references) { source in DisclosureGroup(source.title) { Text(source.excerpt).font(.footnote).foregroundStyle(ChatStyle.muted) }.tint(ChatStyle.cyan) }
        }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(18).careerCard()
    }
    private func criterion(_ title: String, _ value: AdaptiveEvaluation.Criterion) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text("\(title) · \(value.score.map { "\($0) / 4" } ?? "Not assessed")").font(.headline); Text(value.explanation).font(.subheadline).foregroundStyle(ChatStyle.muted) }
    }
}

struct AdaptiveReportView: View {
    let report: AdaptiveReport
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Interview complete").font(.title2.bold())
            Text(report.coachingNote).font(.caption).foregroundStyle(ChatStyle.muted)
            Text("\(report.evaluatedAnswers) answers evaluated").font(.headline)
            if let score = report.averageScore { Text("Average practice score: \(score, specifier: "%.1f") / 4") }
            if let previous = report.previousAverageScore, let change = report.scoreChange {
                Text("Previous same-role session: \(previous, specifier: "%.1f") / 4 · change \(change, specifier: "%+.1f")").font(.subheadline).foregroundStyle(ChatStyle.muted)
                Text("Questions can differ between sessions, so this is only a rough comparison.").font(.caption).foregroundStyle(ChatStyle.muted)
            }
            ForEach(report.topicProgress) { item in Text("\(item.topic): \(item.averageScore, specifier: "%.1f") / 4 · \(item.evidenceCount) answers") }
            if !report.strongestTopics.isEmpty { Text("Strongest observed topics").font(.headline); ForEach(report.strongestTopics, id: \.self) { Text("• \($0)") } }
            if !report.studyTopics.isEmpty { Text("Topics to revisit").font(.headline); ForEach(report.studyTopics, id: \.self) { Text("• \($0)") } }
            if !report.missingConcepts.isEmpty { Text("Concepts to review").font(.headline); ForEach(report.missingConcepts, id: \.self) { Text("• \($0)") } }
            if !report.suggestedQuestions.isEmpty { Text("Practice next").font(.headline); ForEach(report.suggestedQuestions, id: \.self) { Text("• \($0)") } }
        }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(18).careerCard()
    }
}

#Preview("Adaptive session") { NavigationStack { AdaptiveSessionView(model: AdaptiveInterviewViewModel(), sessionID: UUID()) }.preferredColorScheme(.dark) }
#Preview("Adaptive answer") { AdaptiveAnswerView(model: AdaptiveInterviewViewModel()) }
#Preview("Adaptive feedback") {
    let criterion = AdaptiveEvaluation.Criterion(score: 3, explanation: "Give a concrete example.")
    return AdaptiveFeedbackView(evaluation: AdaptiveEvaluation(classification: "correct", overallScore: 3, correctness: criterion, completeness: criterion, reasoning: criterion, communication: criterion, demonstratedConcepts: ["Isolation"], missingConcepts: ["Reentrancy"], inaccuracies: [], evidence: ["prevents races"], feedback: "Explain the trade-offs.", exampleAnswer: nil, references: []))
        .padding().background(ChatStyle.background).preferredColorScheme(.dark)
}
#Preview("Adaptive report") {
    AdaptiveReportView(report: AdaptiveReport(evaluatedAnswers: 2, averageScore: 3, topicProgress: [AdaptiveTopicProgress(topic: "Concurrency", averageScore: 3, evidenceCount: 2)], missingConcepts: ["Reentrancy"], strongestTopics: ["Concurrency"], studyTopics: [], suggestedQuestions: ["How would you explain reentrancy?"], previousAverageScore: nil, scoreChange: nil, coachingNote: "Practice feedback only."))
        .padding().background(ChatStyle.background).preferredColorScheme(.dark)
}
