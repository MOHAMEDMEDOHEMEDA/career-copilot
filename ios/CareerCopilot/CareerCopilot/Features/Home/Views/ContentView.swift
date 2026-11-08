import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppViewModel()
    @StateObject private var resumeModel = ResumeViewModel()
    @StateObject private var chatModel = ChatViewModel()
    @StateObject private var interviewModel = InterviewViewModel()
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var resumeToDelete: Resume?
    @State private var selectedTab: AppTab = .workspace

    private enum AppTab: Hashable {
        case workspace, chat, interview, settings
    }

    var body: some View {
        Group {
            if model.isRestoringSession {
                ProgressView("Restoring your session")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.profile == nil {
                NavigationStack {
                    AuthenticationView(model: model)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                                    .accessibilityLabel("Settings")
                            }
                        }
                }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        ResumeListView(
                            model: model, resumeModel: resumeModel,
                            showImporter: $showImporter, resumeToDelete: $resumeToDelete,
                            openChat: { selectedTab = .chat },
                            openPractice: { selectedTab = .interview }
                        )
                            .navigationTitle("Workspace")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem { Label("Workspace", systemImage: "house") }
                    .tag(AppTab.workspace)

                    NavigationStack {
                        ChatHomeView(model: chatModel)
                    }
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                    .tag(AppTab.chat)

                    NavigationStack {
                        InterviewHomeView(model: interviewModel, resumeModel: resumeModel)
                    }
                    .tabItem { Label("Practice", systemImage: "person.wave.2") }
                    .tag(AppTab.interview)

                    SettingsView(model: model, showsDoneButton: false)
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppTab.settings)
                }
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CareerStyle.gradient.ignoresSafeArea())
            .tint(CareerStyle.accent)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
            .confirmationDialog("Delete this resume?", isPresented: Binding(
                get: { resumeToDelete != nil },
                set: { if !$0 { resumeToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete resume", role: .destructive) {
                    if let resume = resumeToDelete { Task { await resumeModel.delete(resume) } }
                    resumeToDelete = nil
                }
                Button("Cancel", role: .cancel) { resumeToDelete = nil }
            } message: {
                Text("This removes the resume and its associated data.")
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): Task { await resumeModel.upload(url) }
                case .failure(let error): resumeModel.message = error.localizedDescription
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { model.message != nil || resumeModel.message != nil },
                set: { if !$0 { model.message = nil; resumeModel.message = nil } }
            )) {
                Button("OK", role: .cancel) { model.message = nil; resumeModel.message = nil }
            } message: {
                Text(model.message ?? resumeModel.message ?? "")
            }
            .task { await model.restoreSession() }
            .task(id: model.profile?.email) {
                guard model.profile != nil else { resumeModel.reset(); chatModel.reset(); interviewModel.reset(); selectedTab = .workspace; return }
                resumeModel.baseURL = model.baseURL
                chatModel.baseURL = model.baseURL
                interviewModel.baseURL = model.baseURL
                await resumeModel.loadResumes()
            }
    }
}

#Preview("App") {
    ContentView()
}
