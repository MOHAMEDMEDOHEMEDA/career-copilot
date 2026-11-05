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
                    .padding(.horizontal)
                    .accessibilityLabel("Resume text")
            } else {
                ScrollView {
                    Text(draft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
        }
        .navigationTitle(resume.filename)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Save") {
                        Task {
                            if await model.update(resume, text: draft) { isEditing = false }
                        }
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
}
