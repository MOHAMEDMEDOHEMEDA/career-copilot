import SwiftUI

struct ResumeListView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var resumeModel: ResumeViewModel
    @Binding var showImporter: Bool
    @Binding var resumeToDelete: Resume?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    GradientIcon(symbol: "person.fill", colors: [CareerStyle.accent, .purple])
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Welcome back").font(.subheadline).foregroundStyle(.secondary)
                        Text(model.profile?.email ?? "Your workspace").font(.headline).lineLimit(1)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("YOUR CAREER WORKSPACE", systemImage: "sparkles")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    Text("Make your next\nmove a great one.")
                        .font(.title.bold()).foregroundStyle(.white)
                    Text("Keep your resume ready for what's next.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    Button { showImporter = true } label: {
                        HStack {
                            Text("Upload a resume").fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.up.doc")
                        }
                        .padding(14)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(resumeModel.isLoading || model.isLoading)
                }
                .padding(22)
                .background(LinearGradient(colors: [.init(white: 0.25), .black], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))

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
                            .buttonStyle(.borderedProminent)
                    }
                } else if resumeModel.resumes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        GradientIcon(symbol: "doc.text", colors: [CareerStyle.coral, .pink])
                        Text("A fresh start").font(.headline)
                        Text("Upload a PDF to keep your resume close at hand.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20).careerCard()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(resumeModel.resumes) { resume in
                            HStack(spacing: 12) {
                                NavigationLink {
                                    ResumeDetailView(model: resumeModel, resume: resume)
                                } label: {
                                    HStack(spacing: 12) {
                                        GradientIcon(symbol: "doc.text.fill")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(resume.filename).font(.headline).lineLimit(1)
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
        .refreshable { await resumeModel.loadResumes() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Sign out") { Task { await model.signOut() } }.disabled(resumeModel.isLoading || model.isLoading)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImporter = true } label: { Image(systemName: "plus") }
                    .disabled(resumeModel.isLoading || model.isLoading)
                    .accessibilityLabel("Upload resume")
            }
        }
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
