import Foundation

struct JobMatch: Decodable {
    struct SkillEvidence: Decodable {
        let skill: String
        let resumeEvidence: String
        enum CodingKeys: String, CodingKey { case skill; case resumeEvidence = "resume_evidence" }
    }
    let requiredSkillsFound: [SkillEvidence]
    let requiredSkillsNotDemonstrated: [String]
    let experienceAlignment: String
    let recommendations: [String]
    let interviewTopics: [String]
    enum CodingKeys: String, CodingKey {
        case requiredSkillsFound = "required_skills_found"
        case requiredSkillsNotDemonstrated = "required_skills_not_demonstrated"
        case experienceAlignment = "experience_alignment"
        case recommendations
        case interviewTopics = "interview_topics"
    }
}

struct MatchJob: Decodable {
    let id: UUID
    let resumeID: UUID
    let status: AnalysisJob.Status
    let result: JobMatch?
    let errorCode: String?
    enum CodingKeys: String, CodingKey {
        case id, status, result
        case resumeID = "resume_id"
        case errorCode = "error_code"
    }
}
