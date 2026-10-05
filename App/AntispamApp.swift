import AntispamCore
import SwiftUI

@main
struct AntispamApp: App {
    var body: some Scene {
        WindowGroup {
            if let settings = SharedSettings() {
                VStack(spacing: 0) {
                    SettingsView(settings: settings)
                    Divider()
                    DecisionsView(log: DecisionLog(fileURL: settings.decisionLogURL))
                }
                .frame(minWidth: 760, minHeight: 520)
            } else {
                Text("App Group is unavailable. Build the app signed with your development team.")
                    .padding()
            }
        }
    }
}
