import Foundation

public struct DecisionRecord: Codable, Sendable, Equatable, Identifiable {
    public enum Outcome: Codable, Sendable, Equatable {
        case classified(Classification, SpamAction)
        case failed(reason: String)
    }

    public let id: UUID
    public let date: Date
    public let from: String
    public let subject: String
    public let outcome: Outcome

    public init(date: Date = .now, from: String, subject: String, outcome: Outcome) {
        id = UUID()
        self.date = date
        self.from = from
        self.subject = subject
        self.outcome = outcome
    }
}

/// The most recent decisions, newest first, persisted as one JSON file.
public actor DecisionLog {
    private let fileURL: URL
    private let limit: Int

    public init(fileURL: URL, limit: Int = 200) {
        self.fileURL = fileURL
        self.limit = limit
    }

    public func append(_ record: DecisionRecord) throws {
        let updated = [record] + records().prefix(limit - 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(updated).write(to: fileURL, options: .atomic)
    }

    /// Re-read on every call, because the Mail extension writes the file while the app displays it.
    public func records() -> [DecisionRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([DecisionRecord].self, from: data)) ?? []
    }
}
