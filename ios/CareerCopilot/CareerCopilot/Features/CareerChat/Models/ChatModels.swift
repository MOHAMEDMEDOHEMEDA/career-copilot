import Foundation

struct ChatConversation: Decodable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChatMessage: Decodable, Identifiable {
    enum Role: String, Decodable { case user, assistant }
    let id: UUID
    let conversationID: UUID
    let sequence: Int
    let role: Role
    let content: String
    let createdAt: String
    var citations: [ChatCitation]? = nil
    var insufficientInformation: Bool? = nil
    var replyToID: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id, sequence, role, content
        case conversationID = "conversation_id"
        case createdAt = "created_at"
        case citations
        case insufficientInformation = "insufficient_information"
        case replyToID = "reply_to_id"
    }
}

struct ChatCitation: Decodable, Identifiable {
    let chunkID: String
    let sourceID: String
    let title: String
    let origin: String
    let excerpt: String
    var id: String { chunkID }
    enum CodingKeys: String, CodingKey {
        case chunkID = "chunk_id"
        case sourceID = "source_id"
        case title, origin, excerpt
    }
}

struct ChatAnswerJob: Decodable {
    enum Status: String, Decodable { case queued, running, completed, failed }
    let id: UUID
    let conversationID: UUID
    let questionID: UUID
    let status: Status
    let answerMessageID: UUID?
    let errorCode: String?
    enum CodingKeys: String, CodingKey {
        case id, status
        case conversationID = "conversation_id"
        case questionID = "question_id"
        case answerMessageID = "answer_message_id"
        case errorCode = "error_code"
    }
}

struct ChatPage<Item: Decodable>: Decodable {
    let items: [Item]
    let limit: Int
    let offset: Int
}
