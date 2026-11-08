import SwiftUI

struct ResumeDetailView: View {
    @ObservedObject var model: ResumeViewModel
    let resume: Resume
    @State private var draft: String
    @State private var isEditing = false

    init(model: ResumeViewModel, resume: Resume) {
        self.model = model
        self.resume = resume
        _draft = State(initialValue: resume.text)
    }

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $draft)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal)
                    .accessibilityLabel("Resume text")
                    .disabled(model.isLoading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NavigationLink {
                            if let analysisModel = model.analysisModel(for: resume.id) {
                                AnalysisView(model: analysisModel)
                            } else {
                                ContentUnavailableView("Invalid backend URL", systemImage: "exclamationmark.triangle")
                            }
                        } label: {
                            Label("Analyze resume", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .careerPrimaryButton()
                        NavigationLink {
                            if let matchModel = model.matchModel(for: resume.id) {
                                JobMatchView(model: matchModel)
                            } else {
                                ContentUnavailableView("Invalid backend URL", systemImage: "exclamationmark.triangle")
                            }
                        } label: {
                            Label("Match a job", systemImage: "briefcase")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ContentUnavailableView("No resume text", systemImage: "doc.text", description: Text("Edit this resume to add its text."))
                        } else {
                            Text(draft)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(CareerStyle.gradient.ignoresSafeArea())
        .navigationTitle(resume.filename)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button {
                        Task {
                            if await model.update(resume, text: draft) { isEditing = false }
                        }
                    } label: {
                        if model.isLoading { ProgressView().accessibilityLabel("Saving resume") }
                        else { Text("Save") }
                    }
                    .disabled(model.isLoading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Edit") { isEditing = true }
                }
            }
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        draft = model.resumes.first(where: { $0.id == resume.id })?.text ?? resume.text
                        isEditing = false
                    }
                    .disabled(model.isLoading)
                }
            }
        }
    }
}

#Preview("Resume detail") {
    NavigationStack {
        ResumeDetailView(model: ResumeViewModel(), resume: Resume(id: UUID(), filename: "Example.pdf", text: "Synthetic resume text."))
    }
    .preferredColorScheme(.dark)
}
