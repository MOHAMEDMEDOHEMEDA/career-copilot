import SwiftUI

struct InterviewSessionView: View {
    @ObservedObject var model: InterviewViewModel
    let interview: InterviewSession
    @State private var selected: InterviewQuestion?
    @State private var confirmGeneration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("PRACTICE SESSION").font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(ChatStyle.cyan)
                Text("Let’s get you ready.").font(.largeTitle.bold()).foregroundStyle(.white)
                Text(interview.jobDescription).lineLimit(4).foregroundStyle(ChatStyle.muted)
                if model.questions.isEmpty {
                    Text("Generate three questions tailored to this role and resume.").foregroundStyle(.white)
                    Button("Generate questions") { confirmGeneration = true }.buttonStyle(.borderedProminent).disabled(model.loading)
                }
                if model.loading { ProgressView("Working on your interview…").tint(.white).foregroundStyle(.white) }
                if let error = model.error {
                    Text(error).foregroundStyle(.white)
                    if let job = model.job, job.questionID == nil, job.status == .failed {
                        Button("Retry generation") { confirmGeneration = true }.disabled(model.loading)
                    } else { Button("Refresh") { Task { await model.refresh(interview.id) } } }
                }
                ForEach(model.questions) { question in
                    Button { selected = question } label: {
                        HStack(alignment: .top, spacing: 15) {
                            Text("\(question.sequence)").font(.headline).foregroundStyle(ChatStyle.cyan).frame(width: 40, height: 40).background(.white.opacity(0.07), in: Circle())
                            VStack(alignment: .leading, spacing: 8) {
                                Text(question.prompt).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading)
                                Text(question.feedback != nil ? "Feedback ready" : question.answer != nil ? "Answer saved" : "Ready to answer").font(.caption).foregroundStyle(ChatStyle.muted)
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
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: InterviewViewModel
    let sessionID: UUID
    let questionID: UUID
    @State private var answer = ""
    @State private var confirmFeedback = false
    private var question: InterviewQuestion? { model.questions.first { $0.id == questionID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let question {
                        Text("QUESTION \(question.sequence)").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(ChatStyle.cyan)
                        Text(question.prompt).font(.title2.bold()).foregroundStyle(.white)
                        Text("Your answer").font(.headline).foregroundStyle(.white)
                        TextEditor(text: $answer).scrollContentBackground(.hidden).foregroundStyle(.white).padding(8).frame(minHeight: 180).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 16)).accessibilityLabel("Your answer")
                        Text("\(answer.unicodeScalars.count) / 4,000").font(.caption).foregroundStyle(ChatStyle.muted)
                        Button("Save answer") { Task { _ = await model.save(sessionID: sessionID, questionID: questionID, answer: answer) } }
                            .buttonStyle(.borderedProminent).disabled(model.loading || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || answer.unicodeScalars.count > 4000)
                        if question.answer != nil {
                            Button("Get feedback") { confirmFeedback = true }.buttonStyle(.bordered).disabled(model.loading || answer != question.answer)
                        }
                        if let feedback = question.feedback { InterviewFeedbackView(feedback: feedback) }
                    }
                    if model.loading { ProgressView("Preparing feedback…").tint(.white).foregroundStyle(.white) }
                    if let error = model.error {
                        Text(error).foregroundStyle(.white)
                        if let job = model.job, job.questionID == questionID, job.status == .failed { Button("Retry feedback") { confirmFeedback = true }.disabled(model.loading) }
                    }
                }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
            }.background(ChatStyle.gradient.ignoresSafeArea()).tint(ChatStyle.cyan)
            .navigationTitle("Practice answer").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { answer = question?.answer ?? "" }
            .alert("Get AI feedback?", isPresented: $confirmFeedback) {
                Button("Continue") { Task { await model.request(sessionID: sessionID, questionID: questionID, retry: model.job?.status == .failed && model.job?.questionID == questionID) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your resume, job description, question, and answer are sent to the configured AI providers, including cloud providers if fallback is needed.") }
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
