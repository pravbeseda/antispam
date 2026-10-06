import AntispamCore
import MailKit
import os

final class MessageActionHandler: NSObject, MEMessageActionHandler, Sendable {
    static let shared = MessageActionHandler()

    private let logger = Logger(subsystem: "com.kalugaman.antispam", category: "actions")
    private let decisionLog = SharedSettings().map { DecisionLog(fileURL: $0.decisionLogURL) }

    func decideAction(for message: MEMessage) async -> MEMessageActionDecision? {
        guard let data = message.rawData else { return .invokeAgainWithBody }
        let outcome = await outcome(for: data)
        await record(outcome, from: message.fromAddress.rawString, subject: message.subject)
        return Self.decision(for: outcome)
    }

    private func outcome(for data: Data) async -> DecisionRecord.Outcome {
        guard let settings = SharedSettings(), let apiKey = settings.apiKey, !apiKey.isEmpty else {
            return .failed(reason: "No API key in shared settings")
        }
        do {
            let classification = try await JevClient(apiKey: apiKey).classify(MIMEParser.parse(data))
            return .classified(classification, SpamPolicy(threshold: settings.threshold).action(for: classification))
        } catch {
            return .failed(reason: String(describing: error))
        }
    }

    private func record(_ outcome: DecisionRecord.Outcome, from: String, subject: String) async {
        switch outcome {
        case let .classified(classification, action):
            logger.notice("\(classification.category.rawValue, privacy: .public) \(classification.confidence, format: .fixed(precision: 2), privacy: .public) -> \(action.rawValue, privacy: .public) | \(from, privacy: .public) | \(subject, privacy: .public)")
        case let .failed(reason):
            logger.error("Left untouched: \(reason, privacy: .public) | \(from, privacy: .public) | \(subject, privacy: .public)")
        }
        do {
            try await decisionLog?.append(DecisionRecord(from: from, subject: subject, outcome: outcome))
        } catch {
            logger.error("Could not write the decision log: \(String(describing: error), privacy: .public)")
        }
    }

    private static func decision(for outcome: DecisionRecord.Outcome) -> MEMessageActionDecision? {
        guard case let .classified(_, action) = outcome else { return nil }
        switch action {
        case .moveToJunk: return .action(.moveToJunk)
        case .highlight: return .actions([.setBackgroundColor(.yellow), .flag(.gray)])
        case .flagPromo: return .action(.flag(.purple))
        case .none: return nil
        }
    }
}
