import SwiftUI

struct InterviewHomeView: View {
    @ObservedObject var model: InterviewViewModel
    @ObservedObject var resumeModel: ResumeViewModel
    @State private var selected: InterviewSession?
    @State private var showingCreate = false
    @State private var deleteTarget: InterviewSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("INTERVIEW PRACTICE").font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(ChatStyle.cyan)
                Text("Practice with\npurpose.").font(.largeTitle.bold()).foregroundStyle(.white)
                Text("Prepare for a role with tailored questions and thoughtful feedback.").foregroundStyle(ChatStyle.muted)
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "person.wave.2.fill").font(.title2).foregroundStyle(ChatStyle.cyan)
                    Text("Your next interview starts here").font(.title3.bold()).foregroundStyle(.white)
                    Text("Choose a resume and add a job description to begin.").font(.subheadline).foregroundStyle(ChatStyle.muted)
                    Button { showingCreate = true } label: {
                        Label("Start practicing", systemImage: "plus").fontWeight(.semibold).frame(maxWidth: .infinity).padding(14)
                    }.foregroundStyle(.black).background(ChatStyle.cyan, in: Capsule())
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                HStack {
                    Text("Your sessions").font(.title3.bold()).foregroundStyle(.white)
                    Spacer()
                    Button { Task { await model.loadSessions() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Refresh interviews")
                }
                if model.loading { ProgressView("Loading").tint(.white).foregroundStyle(.white) }
                if let error = model.error { Text(error).foregroundStyle(.white); Button("Refresh") { Task { await model.loadSessions() } } }
                if model.sessions.isEmpty && !model.loading && model.error == nil { Text("No sessions yet. Start when you’re ready.").foregroundStyle(ChatStyle.muted) }
                ForEach(model.sessions) { item in
                    HStack {
                        Button { selected = item } label: {
                            HStack {
                                Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(ChatStyle.cyan)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.jobDescription).lineLimit(2).font(.headline).foregroundStyle(.white)
                                    Text(item.status == "ready" ? "Ready to practice" : "Questions not generated yet").font(.caption).foregroundStyle(ChatStyle.muted)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(ChatStyle.muted)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Menu { Button("Delete session", role: .destructive) { deleteTarget = item } } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).foregroundStyle(.white) }.accessibilityLabel("Session options")
                    }.padding(14).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                if model.hasMore { Button("Load more") { Task { await model.loadSessions(more: true) } }.frame(minHeight: 44) }
            }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }
        .background(ChatStyle.gradient.ignoresSafeArea()).tint(ChatStyle.cyan)
        .navigationTitle("Mock interview").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(item: $selected) { InterviewSessionView(model: model, interview: $0) }
        .sheet(isPresented: $showingCreate) { NewInterviewView(model: model, resumes: resumeModel.resumes) { item in showingCreate = false; selected = item } }
        .confirmationDialog("Delete this interview?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            if let item = deleteTarget { Button("Delete", role: .destructive) { Task { await model.delete(item) }; deleteTarget = nil } }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { Text("Its questions, answers, and feedback will be deleted.") }
        .task { await model.loadSessions() }
    }
}

struct NewInterviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: InterviewViewModel
    let resumes: [Resume]
    let onCreate: (InterviewSession) -> Void
    @State private var resumeID: UUID?
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Resume") {
                    if resumes.isEmpty { Text("Upload a resume in Workspace first.") }
                    else { Picker("Choose resume", selection: $resumeID) { Text("Select a resume").tag(UUID?.none); ForEach(resumes) { Text($0.filename).tag(Optional($0.id)) } } }
                }
                Section("Job description") {
                    TextEditor(text: $description).frame(minHeight: 180).accessibilityLabel("Job description")
                    Text("\(description.unicodeScalars.count) / 20,000").font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("New interview").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { if let resumeID { Task { if let item = await model.create(resumeID: resumeID, description: description) { onCreate(item) } } } }
                        .disabled(resumeID == nil || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || description.unicodeScalars.count > 20000 || model.loading)
                }
            }
        }
    }
}

#Preview("Interview home") {
    NavigationStack { InterviewHomeView(model: InterviewViewModel(), resumeModel: ResumeViewModel()) }
}

#Preview("New interview") {
    NewInterviewView(model: InterviewViewModel(), resumes: []) { _ in }
}
