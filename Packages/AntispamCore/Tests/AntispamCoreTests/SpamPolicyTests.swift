import Testing
@testable import AntispamCore

@Suite struct SpamPolicyTests {
    private let policy = SpamPolicy()

    @Test(arguments: [
        (SpamCategory.spam, 0.95, SpamAction.moveToJunk),
        (.phishing, 0.9, .moveToJunk),
        (.spam, 0.5, .highlight),
        (.phishing, 0.89, .highlight),
        (.promo, 0.99, .none),
        (.legit, 0.2, .none),
    ])
    func action(category: SpamCategory, confidence: Double, expected: SpamAction) {
        #expect(policy.action(for: Classification(category: category, confidence: confidence)) == expected)
    }

    @Test func customThreshold() {
        let lenient = SpamPolicy(threshold: 0.6)
        #expect(lenient.action(for: Classification(category: .spam, confidence: 0.7)) == .moveToJunk)
    }
}
