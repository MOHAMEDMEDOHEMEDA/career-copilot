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

struct AdaptiveSession: Decodable, Identifiable, Hashable {
    let id: UUID
    let role, seniority, status: String
    let interviewType: String
    let resumeID: UUID?
    let currentDifficulty: Int
    let stateVersion: Int
    enum CodingKeys: String, CodingKey {
        case id, role, seniority, status
        case interviewType = "interview_type", resumeID = "resume_id", currentDifficulty = "current_difficulty", stateVersion = "state_version"
    }
}

struct AdaptiveEvaluation: Decodable {
    struct Criterion: Decodable { let score: Int?; let explanation: String }
    let classification: String
    let overallScore: Int?
    let correctness, completeness, reasoning, communication: Criterion
    let demonstratedConcepts, missingConcepts, inaccuracies, evidence: [String]
    let feedback: String
    let exampleAnswer: String?
    let references: [ChatCitation]
    enum CodingKeys: String, CodingKey {
        case classification, correctness, completeness, reasoning, communication, inaccuracies, evidence, feedback, references
        case overallScore = "overall_score", demonstratedConcepts = "demonstrated_concepts", missingConcepts = "missing_concepts"
        case exampleAnswer = "example_answer"
    }
}

struct AdaptiveTurn: Decodable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let sequence, difficulty: Int
    let topic, prompt: String
    let answer: String?
    let evaluation: AdaptiveEvaluation?
    enum CodingKeys: String, CodingKey {
        case id, sequence, difficulty, topic, prompt, answer, evaluation
        case sessionID = "session_id"
    }
}

struct AdaptiveJob: Decodable {
    enum Status: String, Decodable { case queued, running, completed, failed }
    let id, sessionID: UUID
    let turnID: UUID?
    let kind: String
    let status: Status
    let errorCode: String?
    let stateVersion: Int
    enum CodingKeys: String, CodingKey {
        case id, kind, status
        case sessionID = "session_id", turnID = "turn_id", errorCode = "error_code", stateVersion = "state_version"
    }
}

struct AdaptiveTopicProgress: Decodable, Identifiable {
    var id: String { topic }
    let topic: String
    let averageScore: Double
    let evidenceCount: Int
    enum CodingKeys: String, CodingKey { case topic; case averageScore = "average_score", evidenceCount = "evidence_count" }
}

struct AdaptiveReport: Decodable {
    let evaluatedAnswers: Int
    let averageScore: Double?
    let topicProgress: [AdaptiveTopicProgress]
    let missingConcepts, strongestTopics, studyTopics, suggestedQuestions: [String]
    let previousAverageScore, scoreChange: Double?
    let coachingNote: String
    enum CodingKeys: String, CodingKey {
        case evaluatedAnswers = "evaluated_answers", averageScore = "average_score", topicProgress = "topic_progress", missingConcepts = "missing_concepts", strongestTopics = "strongest_topics", studyTopics = "study_topics", suggestedQuestions = "suggested_questions", previousAverageScore = "previous_average_score", scoreChange = "score_change", coachingNote = "coaching_note"
    }
}
