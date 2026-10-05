import AntispamCore
import Foundation
import os
import SwiftUI

struct SettingsView: View {
    private static let logger = Logger(subsystem: "com.kalugaman.antispam", category: "settings")

    let settings: SharedSettings

    @State private var apiKey = ""
    @State private var threshold = SpamPolicy.defaultThreshold
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("Jev API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            Text("Move to Junk at confidence ≥ \(threshold, format: .number.precision(.fractionLength(2)))")
            Slider(value: $threshold, in: 0.5...0.99, step: 0.01)
            HStack {
                Button("Save", action: save)
                Button("Test connection") { Task { await testConnection() } }
            }
            Text(status)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text("Enable the extension in Mail → Settings → Extensions.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear {
            apiKey = settings.apiKey ?? ""
            threshold = settings.threshold
        }
    }

    private func save() {
        settings.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.threshold = threshold
        status = "Saved."
    }

    private func testConnection() async {
        status = "Checking…"
        let sample = MIMEParser.parse(Data("From: Alice <alice@example.com>\nSubject: Lunch\n\nLunch at noon tomorrow?\n".utf8))
        do {
            let result = try await JevClient(apiKey: apiKey).classify(sample)
            status = "Connected: \(result.category.rawValue), confidence \(result.confidence.formatted(.number.precision(.fractionLength(2))))."
        } catch {
            status = "Connection failed: \(error)"
            Self.logger.error("\(status, privacy: .public)")
        }
    }
}
