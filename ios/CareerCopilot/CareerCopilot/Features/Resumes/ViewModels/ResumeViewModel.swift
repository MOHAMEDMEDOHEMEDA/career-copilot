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
    private var generation = UUID()

    init(
        baseURL: String = UserDefaults.standard.string(forKey: "baseURL") ?? "http://localhost:8000",
        clientFactory: @escaping (String) throws -> any ResumeServicing = { try APIClient.configured(baseURL: $0) }
    ) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
    }

    func loadResumes() async {
        guard let operation = beginOperation() else { return }
        defer { endOperation(operation) }
        do {
            let loaded = try await clientFactory(baseURL).resumes()
            guard isCurrent(operation) else { return }
            resumes = loaded
            loadError = nil
        } catch {
            if isCurrent(operation) { loadError = error.localizedDescription }
        }
    }

    func upload(_ url: URL) async {
        guard let operation = beginOperation() else { return }
        defer { endOperation(operation) }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 10 * 1024 * 1024 else { throw APIClient.APIError.fileTooLarge }
                return try Data(contentsOf: url)
            }.value
            guard isCurrent(operation) else { return }
            let resume = try await clientFactory(baseURL).uploadPDF(data: data, filename: url.lastPathComponent)
            guard isCurrent(operation) else { return }
            resumes.append(resume)
        } catch {
            if isCurrent(operation) { message = error.localizedDescription }
        }
    }

    func delete(_ resume: Resume) async {
        guard let operation = beginOperation() else { return }
        defer { endOperation(operation) }
        do {
            try await clientFactory(baseURL).deleteResume(id: resume.id)
            guard isCurrent(operation) else { return }
            resumes.removeAll { $0.id == resume.id }
        } catch {
            if isCurrent(operation) { message = error.localizedDescription }
        }
    }

    func update(_ resume: Resume, text: String) async -> Bool {
        guard let operation = beginOperation() else { return false }
        defer { endOperation(operation) }
        do {
            let updated = try await clientFactory(baseURL).updateResume(id: resume.id, text: text)
            guard isCurrent(operation) else { return false }
            if let index = resumes.firstIndex(where: { $0.id == resume.id }) { resumes[index] = updated }
            return true
        } catch {
            if isCurrent(operation) { message = error.localizedDescription }
            return false
        }
    }

    func reset() {
        generation = UUID()
        isLoading = false
        resumes = []
        message = nil
        loadError = nil
    }

    private func beginOperation() -> UUID? {
        guard !isLoading else { return nil }
        isLoading = true
        return generation
    }

    private func endOperation(_ operation: UUID) {
        if operation == generation { isLoading = false }
    }

    private func isCurrent(_ operation: UUID) -> Bool {
        operation == generation && !Task.isCancelled
    }
}
