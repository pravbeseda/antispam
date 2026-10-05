import AntispamCore
import SwiftUI

struct DecisionsView: View {
    let log: DecisionLog

    @State private var records: [DecisionRecord] = []

    var body: some View {
        VStack(alignment: .leading) {
            Text("Recent decisions").font(.headline)
            Table(records) {
                TableColumn("Time") { Text($0.date, format: .dateTime.day().month().hour().minute()).foregroundStyle(Self.tint($0.outcome)) }
                    .width(110)
                TableColumn("From") { Text($0.from).foregroundStyle(Self.tint($0.outcome)) }
                TableColumn("Subject") { Text($0.subject).foregroundStyle(Self.tint($0.outcome)) }
                TableColumn("Result") { Text(Self.describe($0.outcome)).foregroundStyle(Self.tint($0.outcome)) }
            }
        }
        .padding()
        .task {
            // The Mail extension appends to the log in the background; poll to show new rows.
            while !Task.isCancelled {
                records = await log.records()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private static func tint(_ outcome: DecisionRecord.Outcome) -> Color {
        switch outcome {
        case .failed: .red
        case .classified(_, .moveToJunk): .purple
        case .classified(_, .highlight): .yellow
        case .classified(_, .none): .primary
        }
    }

    private static func describe(_ outcome: DecisionRecord.Outcome) -> String {
        switch outcome {
        case let .classified(classification, action):
            "\(classification.category.rawValue) \(classification.confidence.formatted(.number.precision(.fractionLength(2)))) → \(action.rawValue)"
        case let .failed(reason):
            "error: \(reason)"
        }
    }
}
