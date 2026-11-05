import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppViewModel()
    @StateObject private var resumeModel = ResumeViewModel()
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var resumeToDelete: Resume?

    var body: some View {
        NavigationStack {
            Group {
                if model.profile == nil {
                    AuthenticationView(model: model)
                } else {
                    ResumeListView(model: model, resumeModel: resumeModel, showImporter: $showImporter, resumeToDelete: $resumeToDelete)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CareerStyle.canvas)
            .tint(CareerStyle.accent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
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
                guard model.profile != nil else { resumeModel.reset(); return }
                resumeModel.baseURL = model.baseURL
                await resumeModel.loadResumes()
            }
        }
    }
}

#Preview("App") {
    ContentView()
}
