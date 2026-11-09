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
                NavigationLink {
                    AdaptiveHomeView(resumeModel: resumeModel)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Adaptive interview", systemImage: "sparkles").font(.headline)
                        Text("Practice one question at a time with follow-ups tailored to your answers.").font(.subheadline).foregroundStyle(ChatStyle.muted)
                        Label("Explore adaptive practice", systemImage: "arrow.right").font(.subheadline.weight(.semibold)).foregroundStyle(ChatStyle.cyan)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(.plain).foregroundStyle(.white)
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
                .listRowBackground(CareerStyle.card)
                Section("Job description") {
                    TextEditor(text: $description).scrollContentBackground(.hidden).frame(minHeight: 180).accessibilityLabel("Job description")
                    Text("\(description.unicodeScalars.count) / 20,000").font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(CareerStyle.card)
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden)
            .background(CareerStyle.gradient.ignoresSafeArea())
            .listRowBackground(CareerStyle.card)
            .navigationTitle("New interview").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { if let resumeID { Task { if let item = await model.create(resumeID: resumeID, description: description) { onCreate(item) } } } }
                        .disabled(resumeID == nil || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || description.unicodeScalars.count > 20000 || model.loading)
                }
            }
        }
        .tint(CareerStyle.accent)
        .preferredColorScheme(.dark)
    }
}

#Preview("Interview home") {
    NavigationStack { InterviewHomeView(model: InterviewViewModel(), resumeModel: ResumeViewModel()) }
}

#Preview("New interview") {
    NewInterviewView(model: InterviewViewModel(), resumes: []) { _ in }
}

struct AdaptiveHomeView: View {
    @ObservedObject var resumeModel: ResumeViewModel
    @StateObject private var model: AdaptiveInterviewViewModel
    @State private var selected: AdaptiveSession?
    @State private var showingSetup = false
    @State private var deleteTarget: AdaptiveSession?

    init(resumeModel: ResumeViewModel) {
        self.resumeModel = resumeModel
        _model = StateObject(wrappedValue: AdaptiveInterviewViewModel(baseURL: resumeModel.baseURL))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("ADAPTIVE PRACTICE").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(ChatStyle.cyan)
                Text("Practice your next answer.").font(.largeTitle.bold()).foregroundStyle(.white)
                Text("Get one question at a time, with follow-ups based on your answers.").foregroundStyle(ChatStyle.muted)
                Button { showingSetup = true } label: { Label("Start adaptive interview", systemImage: "plus").frame(maxWidth: .infinity).padding(8) }.careerPrimaryButton().disabled(model.loading)
                NavigationLink { AdaptiveProgressView(model: model) } label: { Label("View skill progress", systemImage: "chart.bar.xaxis").frame(minHeight: 44) }
                HStack { Text("Your adaptive sessions").font(.title3.bold()).foregroundStyle(.white); Spacer(); Button { Task { await model.loadSessions() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Refresh adaptive interviews") }
                if model.loading { ProgressView("Loading sessions").tint(.white).foregroundStyle(ChatStyle.muted) }
                if let error = model.error { Text(error).foregroundStyle(.white); Button("Refresh") { Task { await model.loadSessions() } } }
                if model.sessions.isEmpty && !model.loading && model.error == nil { Text("No adaptive sessions yet.").foregroundStyle(ChatStyle.muted) }
                ForEach(model.sessions) { item in
                    HStack {
                        Button { selected = item } label: {
                            HStack { VStack(alignment: .leading, spacing: 6) { Text(item.role).font(.headline).foregroundStyle(.white); Text("\(item.seniority.capitalized) · \(item.status.capitalized)").font(.caption).foregroundStyle(ChatStyle.muted) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(ChatStyle.muted) }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Menu { Button("Delete session", role: .destructive) { deleteTarget = item } } label: { Image(systemName: "ellipsis").foregroundStyle(.white).frame(width: 44, height: 44) }.accessibilityLabel("Options for \(item.role) interview")
                    }.padding(16).background(ChatStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                if model.hasMoreSessions { Button("Load more") { Task { await model.loadSessions(more: true) } }.frame(minHeight: 44) }
            }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }.background(ChatStyle.gradient.ignoresSafeArea()).tint(ChatStyle.cyan)
        .navigationTitle("Adaptive interview").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(item: $selected) { item in AdaptiveSessionView(model: model, sessionID: item.id) }
        .sheet(isPresented: $showingSetup) { AdaptiveSetupView(model: model, resumes: resumeModel.resumes) { item in showingSetup = false; selected = item } }
        .confirmationDialog("Delete this interview?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            if let item = deleteTarget { Button("Delete", role: .destructive) { Task { await model.delete(item) }; deleteTarget = nil } }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { Text("Its questions, answers, and report will be deleted.") }
        .task { await model.loadSessions() }
    }
}

struct AdaptiveSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AdaptiveInterviewViewModel
    let resumes: [Resume]
    let onCreate: (AdaptiveSession) -> Void
    @State private var role = ""
    @State private var seniority = "junior"
    @State private var type = "technical"
    @State private var resumeID: UUID?
    @State private var description = ""
    @State private var skills = ""
    private var skillList: [String] { skills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    private var valid: Bool {
        let cleanedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = skillList.map { $0.lowercased() }
        return !cleanedRole.isEmpty && role.unicodeScalars.count <= 200 && description.unicodeScalars.count <= 20000 && skillList.count <= 20 && skillList.allSatisfy { $0.unicodeScalars.count <= 100 } && Set(normalized).count == normalized.count
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Target role") {
                    TextField("e.g. iOS developer", text: $role)
                    Picker("Seniority", selection: $seniority) { Text("Junior").tag("junior"); Text("Mid-level").tag("mid"); Text("Senior").tag("senior") }
                    Picker("Interview type", selection: $type) { Text("Technical").tag("technical"); Text("Behavioral").tag("behavioral"); Text("Mixed").tag("mixed") }
                }.listRowBackground(CareerStyle.card)
                Section("Experience context") {
                    Picker("Resume (optional)", selection: $resumeID) { Text("No resume").tag(UUID?.none); ForEach(resumes) { Text($0.filename).tag(Optional($0.id)) } }
                    TextField("Skills, separated by commas", text: $skills, axis: .vertical)
                    Text("Your selected skills are treated as claims, not verified experience.").font(.caption).foregroundStyle(.secondary)
                }.listRowBackground(CareerStyle.card)
                Section("Job description (optional)") {
                    TextEditor(text: $description).scrollContentBackground(.hidden).frame(minHeight: 120).accessibilityLabel("Job description")
                    Text("\(description.unicodeScalars.count) / 20,000").font(.caption).foregroundStyle(.secondary)
                }.listRowBackground(CareerStyle.card)
                if !valid && (!role.isEmpty || !skills.isEmpty || !description.isEmpty) { Text("Enter a role and up to 20 unique skills. Check the text limits.").font(.footnote).foregroundStyle(.secondary) }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).background(CareerStyle.gradient.ignoresSafeArea())
            .navigationTitle("Interview setup").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") { Task { if let item = await model.create(role: role, seniority: seniority, interviewType: type, resumeID: resumeID, description: description, skills: skillList) { onCreate(item) } } }.disabled(!valid || model.loading) }
            }
        }.tint(ChatStyle.cyan).preferredColorScheme(.dark)
    }
}

struct AdaptiveProgressView: View {
    @ObservedObject var model: AdaptiveInterviewViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Skill progress").font(.largeTitle.bold()).foregroundStyle(.white)
                Text("Approximate coaching feedback from completed interviews. A topic appears after at least two scored answers; it is not a verified skill measurement.").font(.subheadline).foregroundStyle(ChatStyle.muted)
                if model.loading { ProgressView("Loading progress").tint(.white) }
                if let error = model.error { Text(error).foregroundStyle(.white); Button("Try again") { Task { await model.loadProgress() } } }
                if model.progress.isEmpty && !model.loading && model.error == nil { Text("Complete more practice on a topic to see progress.").foregroundStyle(ChatStyle.muted) }
                ForEach(model.progress) { item in
                    VStack(alignment: .leading, spacing: 8) { Text(item.topic).font(.headline); ProgressView(value: item.averageScore, total: 4).tint(ChatStyle.cyan); Text("\(item.averageScore, specifier: "%.1f") / 4 · \(item.evidenceCount) answers").font(.caption).foregroundStyle(ChatStyle.muted) }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(16).careerCard()
                }
                if model.hasMoreProgress { Button("Load more") { Task { await model.loadProgress(more: true) } }.frame(minHeight: 44).disabled(model.loading) }
            }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }.background(ChatStyle.gradient.ignoresSafeArea()).tint(ChatStyle.cyan).navigationTitle("Progress").navigationBarTitleDisplayMode(.inline).task { await model.loadProgress() }
    }
}

#Preview("Adaptive setup") { AdaptiveSetupView(model: AdaptiveInterviewViewModel(), resumes: []) { _ in } }
#Preview("Adaptive progress") { NavigationStack { AdaptiveProgressView(model: AdaptiveInterviewViewModel()) }.preferredColorScheme(.dark) }
#Preview("Adaptive home") { NavigationStack { AdaptiveHomeView(resumeModel: ResumeViewModel()) }.preferredColorScheme(.dark) }
