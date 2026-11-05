import Combine
import Foundation

protocol ResumeServicing {
    func resumes() async throws -> [Resume]
    func uploadPDF(data: Data, filename: String) async throws -> Resume
    func deleteResume(id: UUID) async throws
    func updateResume(id: UUID, text: String) async throws -> Resume
}

extension APIClient: ResumeServicing {}

@MainActor
final class ResumeViewModel: ObservableObject {
    @Published var resumes: [Resume] = []
    @Published var message: String?
    @Published var loadError: String?
    @Published var isLoading = false

    var baseURL: String
    private let clientFactory: (String) throws -> any ResumeServicing

    init(
        baseURL: String = UserDefaults.standard.string(forKey: "baseURL") ?? "http://localhost:8000",
        clientFactory: @escaping (String) throws -> any ResumeServicing = { try APIClient.configured(baseURL: $0) }
    ) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
    }

    func loadResumes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            resumes = try await clientFactory(baseURL).resumes()
            loadError = nil
        } catch { loadError = error.localizedDescription }
    }

    func upload(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 10 * 1024 * 1024 else { throw APIClient.APIError.fileTooLarge }
                return try Data(contentsOf: url)
            }.value
            let resume = try await clientFactory(baseURL).uploadPDF(data: data, filename: url.lastPathComponent)
            resumes.append(resume)
        } catch { message = error.localizedDescription }
    }

    func delete(_ resume: Resume) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await clientFactory(baseURL).deleteResume(id: resume.id)
            resumes.removeAll { $0.id == resume.id }
        } catch { message = error.localizedDescription }
    }

    func update(_ resume: Resume, text: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let updated = try await clientFactory(baseURL).updateResume(id: resume.id, text: text)
            if let index = resumes.firstIndex(where: { $0.id == resume.id }) { resumes[index] = updated }
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func reset() {
        resumes = []
        message = nil
        loadError = nil
    }
}
