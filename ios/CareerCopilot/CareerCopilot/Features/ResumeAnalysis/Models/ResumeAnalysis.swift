import Foundation

struct ResumeAnalysis: Decodable {
    struct Experience: Decodable, Identifiable {
        var id: String { "\(role)|\(organization)|\(details)" }
        let role: String
        let organization: String
        let details: String
    }

    struct Education: Decodable, Identifiable {
        var id: String { "\(institution)|\(qualification)" }
        let institution: String
        let qualification: String
    }

    struct BulletRewrite: Decodable, Identifiable {
        var id: String { "\(original)|\(rewrite)" }
        let original: String
        let rewrite: String
    }

    let summary: String
    let technicalSkills: [String]
    let softSkills: [String]
    let experience: [Experience]
    let education: [Education]
    let strengths: [String]
    let improvementSuggestions: [String]
    let missingOrUnclearInformation: [String]
    let bulletRewrites: [BulletRewrite]

    enum CodingKeys: String, CodingKey {
        case summary, experience, education, strengths
        case technicalSkills = "technical_skills"
        case softSkills = "soft_skills"
        case improvementSuggestions = "improvement_suggestions"
        case missingOrUnclearInformation = "missing_or_unclear_information"
        case bulletRewrites = "bullet_rewrites"
    }
}

struct AnalysisJob: Decodable, Identifiable {
    enum Status: String, Decodable {
        case queued, running, completed, failed
    }

    let id: UUID
    let resumeID: UUID
    let status: Status
    let result: ResumeAnalysis?
    var errorCode: String? = nil
    var createdAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, status, result
        case resumeID = "resume_id"
        case errorCode = "error_code"
        case createdAt = "created_at"
    }
}

struct AnalysisJobPage: Decodable {
    let items: [AnalysisJob]
}
