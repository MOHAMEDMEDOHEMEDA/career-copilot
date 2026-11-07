import Foundation

struct InterviewSession: Decodable, Identifiable, Hashable {
    let id: UUID
    let resumeID: UUID
    let jobDescription: String
    let status: String
    enum CodingKeys: String, CodingKey {
        case id, status
        case resumeID = "resume_id"
        case jobDescription = "job_description"
    }
}

struct InterviewQuestion: Decodable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let sequence: Int
    let prompt: String
    let answer: String?
    let feedback: InterviewFeedback?
    enum CodingKeys: String, CodingKey {
        case id, sequence, prompt, answer, feedback
        case sessionID = "session_id"
    }
}

struct InterviewFeedback: Decodable {
    struct Criterion: Decodable {
        let rating: String
        let explanation: String
    }
    let correctness, completeness, relevance, clarity: Criterion
    let strengths, improvements: [String]
    let exampleAnswer: String
    enum CodingKeys: String, CodingKey {
        case correctness, completeness, relevance, clarity, strengths, improvements
        case exampleAnswer = "example_answer"
    }
}

struct InterviewJob: Decodable {
    enum Status: String, Decodable { case queued, running, completed, failed }
    let id: UUID
    let sessionID: UUID
    let questionID: UUID?
    let status: Status
    let errorCode: String?
    enum CodingKeys: String, CodingKey {
        case id, status
        case sessionID = "session_id"
        case questionID = "question_id"
        case errorCode = "error_code"
    }
}
