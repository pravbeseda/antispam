import SwiftUI

/// Shows whether Mail runs the extension of the installed version; Mail keeps an old one until it is reopened.
struct VersionStatusView: View {
    let settings: SharedSettings

    private let appVersion = Bundle.main.shortVersion

    var body: some View {
        // The Mail extension records its version in the background; re-read it to keep the line current.
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            if let check = settings.extensionCheck {
                let lastCheck = check.date.formatted(.dateTime.day().month().hour().minute())
                if check.version == appVersion {
                    Text("Antispam v\(appVersion) · Mail extension v\(check.version), last check \(lastCheck)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Mail ran extension v\(check.version) at \(lastCheck), but Antispam is v\(appVersion). Quit and reopen Mail, then wait for a new message.")
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Antispam v\(appVersion) · Mail extension has not checked any message yet")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
    }
}
