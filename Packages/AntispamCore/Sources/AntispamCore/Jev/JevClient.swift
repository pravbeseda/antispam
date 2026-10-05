import Foundation

public enum SpamCategory: String, CaseIterable, Codable, Sendable {
    case spam, phishing, promo, legit

    var criterion: String {
        switch self {
        case .spam: "Unsolicited bulk or commercial email the recipient never asked for"
        case .phishing: "Tries to steal credentials, money or personal data by impersonating a trusted sender or using deceptive links"
        case .promo: "Marketing or newsletter email from a sender the recipient subscribed to"
        case .legit: "Personal, work, transactional or service email the recipient expects"
        }
    }
}

public struct Classification: Codable, Sendable, Equatable {
    public let category: SpamCategory
    public let confidence: Double

    public init(category: SpamCategory, confidence: Double) {
        self.category = category
        self.confidence = confidence
    }
}

public enum JevError: Error, Equatable {
    case http(status: Int)
    case invalidResponse
}

public struct JevClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    // Thresholds are calibrated against one model, so the version is pinned.
    static let model = "jev-1.13.0"
    static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let timeout: TimeInterval = 10
    static let bodyLimit = 8000
    static let sentHeaders = ["From", "Reply-To", "Return-Path", "To", "Subject", "Date", "List-Unsubscribe", "Authentication-Results"]

    private let apiKey: String
    private let transport: Transport

    public init(apiKey: String, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.apiKey = apiKey
        self.transport = transport
    }

    public func classify(_ message: ParsedMessage) async throws -> Classification {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Self.requestBody(for: message))

        let (data, response) = try await transport(request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw JevError.invalidResponse }
        guard status == 200 else { throw JevError.http(status: status) }

        guard let answer = try? JSONDecoder().decode(ResponseBody.self, from: data).answers.category,
              let category = SpamCategory(rawValue: answer.choice)
        else { throw JevError.invalidResponse }
        return Classification(category: category, confidence: answer.confidence)
    }

    private static func requestBody(for message: ParsedMessage) -> RequestBody {
        var headers: [String: String] = [:]
        for name in sentHeaders {
            let values = message.values(of: name)
            if !values.isEmpty { headers[name] = values.joined(separator: "\n") }
        }
        return RequestBody(
            state: .init(email: .init(
                headers: headers,
                body: String(message.bodyText.prefix(bodyLimit)),
                link_domains: message.linkDomains
            )),
            model: model,
            questions: ["category": .init(
                instructions: "Classify this email received in a personal mailbox.",
                criteria: Dictionary(uniqueKeysWithValues: SpamCategory.allCases.map { ($0.rawValue, $0.criterion) })
            )]
        )
    }

    private struct RequestBody: Encodable {
        struct State: Encodable { let email: Email }
        struct Email: Encodable {
            let headers: [String: String]
            let body: String
            let link_domains: [String]
        }
        struct Question: Encodable {
            let type = "choice"
            let instructions: String
            let criteria: [String: String]
        }

        let state: State
        let model: String
        let questions: [String: Question]
    }

    private struct ResponseBody: Decodable {
        struct Answers: Decodable { let category: Answer }
        struct Answer: Decodable {
            let choice: String
            let confidence: Double
        }

        let answers: Answers
    }
}
