import SwiftUI

struct ResumeListView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var resumeModel: ResumeViewModel
    @Binding var showImporter: Bool
    @Binding var resumeToDelete: Resume?
    var openChat: () -> Void = {}
    var openPractice: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    GradientIcon(symbol: "person.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Welcome back").font(.subheadline).foregroundStyle(.secondary)
                        Text(model.profile?.email ?? "Your workspace").font(.headline).lineLimit(1)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR CAREER WORKSPACE")
                        .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(CareerStyle.accent)
                    Text("Make your next move.").font(.title.bold())
                    Text("Choose where you’d like to start.").font(.subheadline).foregroundStyle(CareerStyle.muted)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick actions").font(.headline)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { quickActions }
                        VStack(spacing: 10) { quickActions }
                    }
                }

                HStack {
                    Text("Your resumes").font(.title3.bold())
                    Spacer()
                    if resumeModel.loadError == nil {
                        Text("\(resumeModel.resumes.count) \(resumeModel.resumes.count == 1 ? "document" : "documents")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if resumeModel.isLoading && !resumeModel.resumes.isEmpty {
                    ProgressView("Updating resumes")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = resumeModel.loadError, !resumeModel.resumes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Couldn’t refresh resumes", systemImage: "wifi.exclamationmark")
                            .font(.subheadline.weight(.semibold))
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("Try again") { Task { await resumeModel.loadResumes() } }
                            .disabled(resumeModel.isLoading || model.isLoading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).careerCard()
                }

                if resumeModel.isLoading && resumeModel.resumes.isEmpty {
                    ProgressView("Loading resumes").frame(maxWidth: .infinity).padding()
                } else if let error = resumeModel.loadError, resumeModel.resumes.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn’t load resumes", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await resumeModel.loadResumes() } }
                            .careerPrimaryButton()
                    }
                } else if resumeModel.resumes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        GradientIcon(symbol: "doc.text")
                        Text("Add your first resume").font(.headline)
                        Text("Upload a PDF to analyze it, match a job, or practice for an interview.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button { showImporter = true } label: {
                            Label("Upload a resume", systemImage: "arrow.up.doc")
                        }
                        .careerPrimaryButton()
                        .disabled(model.isLoading || resumeModel.isLoading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20).careerCard()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(resumeModel.resumes) { resume in
                            VStack(alignment: .leading, spacing: 14) {
                              HStack(spacing: 12) {
                                NavigationLink {
                                    ResumeDetailView(model: resumeModel, resume: resume)
                                } label: {
                                    HStack(spacing: 12) {
                                        GradientIcon(symbol: "doc.text.fill")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(resume.filename).font(.headline).lineLimit(2).truncationMode(.middle)
                                            Text("Resume · PDF").font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(resumeModel.isLoading || model.isLoading)
                                Menu {
                                    Button("Delete", systemImage: "trash", role: .destructive) { resumeToDelete = resume }
                                } label: {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Options for \(resume.filename)")
                                .disabled(resumeModel.isLoading || model.isLoading)
                              }
                              ViewThatFits(in: .horizontal) {
                                  HStack(spacing: 10) { resumeActions(resume) }
                                  VStack(alignment: .leading, spacing: 8) { resumeActions(resume) }
                              }
                            }
                            .padding(16).careerCard()
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CareerStyle.gradient.ignoresSafeArea())
        .refreshable { await resumeModel.loadResumes() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImporter = true } label: { Image(systemName: "plus") }
                    .disabled(resumeModel.isLoading || model.isLoading)
                    .accessibilityLabel("Upload resume")
            }
        }
    }

    private var quickActions: some View {
        Group {
            quickAction("Upload", subtitle: "Add a PDF", symbol: "arrow.up.doc") { showImporter = true }
                .disabled(resumeModel.isLoading || model.isLoading)
            quickAction("Chat", subtitle: "Ask a question", symbol: "bubble.left.and.bubble.right") { openChat() }
            quickAction("Practice", subtitle: "Mock interview", symbol: "person.wave.2") { openPractice() }
        }
    }

    private func quickAction(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(CareerStyle.accent).font(.title3)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(CareerStyle.muted).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(14)
            .careerCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func resumeActions(_ resume: Resume) -> some View {
        Group {
            NavigationLink {
                if let analysisModel = resumeModel.analysisModel(for: resume.id) {
                    AnalysisView(model: analysisModel)
                } else {
                    ContentUnavailableView("Invalid backend URL", systemImage: "exclamationmark.triangle")
                }
            } label: {
                Label("Analyze", systemImage: "sparkles")
            }
            .accessibilityLabel("Analyze \(resume.filename)")

            NavigationLink {
                if let matchModel = resumeModel.matchModel(for: resume.id) {
                    JobMatchView(model: matchModel)
                } else {
                    ContentUnavailableView("Invalid backend URL", systemImage: "exclamationmark.triangle")
                }
            } label: {
                Label("Match a job", systemImage: "briefcase")
            }
            .accessibilityLabel("Match a job with \(resume.filename)")
        }
        .buttonStyle(.bordered)
        .disabled(resumeModel.isLoading || model.isLoading)
    }

}

#Preview("Resumes") {
    let model = AppViewModel()
    model.profile = Profile(email: "alex@example.com")
    let resumeModel = ResumeViewModel()
    resumeModel.resumes = [Resume(id: UUID(), filename: "Software Engineer Resume.pdf", text: "Synthetic resume text.")]
    return ScreenPreview {
        ResumeListView(model: model, resumeModel: resumeModel, showImporter: .constant(false), resumeToDelete: .constant(nil))
    }
}

#Preview("Empty resumes") {
    let model = AppViewModel()
    model.profile = Profile(email: "alex@example.com")
    let resumeModel = ResumeViewModel()
    return ScreenPreview {
        ResumeListView(model: model, resumeModel: resumeModel, showImporter: .constant(false), resumeToDelete: .constant(nil))
    }
}
