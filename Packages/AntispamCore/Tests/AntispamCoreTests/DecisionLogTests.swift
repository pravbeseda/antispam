import Foundation
import Testing
@testable import AntispamCore

@Suite struct DecisionLogTests {
    private let fileURL = FileManager.default.temporaryDirectory.appending(path: "decisions-\(UUID()).json")

    private func record(_ subject: String, outcome: DecisionRecord.Outcome = .failed(reason: "test")) -> DecisionRecord {
        DecisionRecord(date: Date(timeIntervalSince1970: 1_000), from: "a@example.com", subject: subject, outcome: outcome)
    }

    @Test func missingFileMeansNoRecords() async {
        #expect(await DecisionLog(fileURL: fileURL).records().isEmpty)
    }

    @Test func recordsSurviveAcrossInstancesNewestFirst() async throws {
        let classified = record("one", outcome: .classified(Classification(category: .spam, confidence: 0.94), .moveToJunk))
        try await DecisionLog(fileURL: fileURL).append(classified)
        let failed = record("two")
        try await DecisionLog(fileURL: fileURL).append(failed)

        #expect(await DecisionLog(fileURL: fileURL).records() == [failed, classified])
    }

    @Test func keepsOnlyTheNewestRecords() async throws {
        let log = DecisionLog(fileURL: fileURL, limit: 2)
        for subject in ["one", "two", "three"] {
            try await log.append(record(subject))
        }
        #expect(await log.records().map(\.subject) == ["three", "two"])
    }
}
