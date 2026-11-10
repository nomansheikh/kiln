import Foundation

/// A saved conversation: a titled list of prompts and what each produced.
public struct Chat: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isArchived: Bool
    public var turns: [ChatTurn]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        turns: [ChatTurn] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.turns = turns
    }

    /// A short title taken from a chat's first prompt.
    public static func defaultTitle(for prompt: String, limit: Int = 48) -> String {
        let singleLine = prompt
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !singleLine.isEmpty else { return "New chat" }
        guard singleLine.count > limit else { return singleLine }
        // Cut at a word boundary when one is close enough to the limit.
        let prefix = singleLine.prefix(limit)
        let cut = prefix.lastIndex(of: " ").map { prefix[..<$0] } ?? prefix
        return (cut.count >= limit / 2 ? cut : prefix).trimmingCharacters(in: .whitespaces) + "…"
    }
}

public struct ChatTurn: Codable, Sendable, Identifiable, Equatable {
    public enum Outcome: Codable, Sendable, Equatable {
        /// The image's file name inside the gallery folder.
        case image(fileName: String)
        case failed(message: String)
        case cancelled
    }

    public var id: UUID
    public var prompt: String
    public var width: Int
    public var height: Int
    public var outcome: Outcome
    /// File name of the image attached to the prompt, inside the attachments folder.
    public var attachmentFileName: String?

    public init(
        id: UUID = UUID(),
        prompt: String,
        width: Int,
        height: Int,
        outcome: Outcome,
        attachmentFileName: String? = nil
    ) {
        self.attachmentFileName = attachmentFileName
        self.id = id
        self.prompt = prompt
        self.width = width
        self.height = height
        self.outcome = outcome
    }
}
