public enum SpamAction: String, Codable, Sendable {
    case moveToJunk, highlight, flagPromo, none
}

public struct SpamPolicy: Sendable {
    public static let defaultThreshold = 0.9

    public let threshold: Double

    public init(threshold: Double = defaultThreshold) {
        self.threshold = threshold
    }

    public func action(for classification: Classification) -> SpamAction {
        switch classification.category {
        case .spam, .phishing: classification.confidence >= threshold ? .moveToJunk : .highlight
        case .promo: classification.confidence >= threshold ? .flagPromo : .none
        case .legit: .none
        }
    }
}
