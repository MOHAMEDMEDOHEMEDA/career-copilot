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

    enum CodingKeys: String, CodingKey {
        case id, sequence, role, content
        case conversationID = "conversation_id"
        case createdAt = "created_at"
    }
}

struct ChatPage<Item: Decodable>: Decodable {
    let items: [Item]
    let limit: Int
    let offset: Int
}
