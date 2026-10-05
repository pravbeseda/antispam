# MailKit anti-spam extension powered by Jev

Apple Mail extension (macOS) that classifies every incoming message in all Mail accounts with TypeSafe Jev and moves confident spam to Junk.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Signing | Personal use, free Apple ID (Personal Team), Apple Development certificate |
| 2 | Action | `spam`/`phishing` with confidence ≥ threshold (default 0.9) → Junk; below threshold → yellow background, stays in Inbox |
| 3 | Categories | One Jev `choice`: `spam` / `phishing` / `promo` / `legit`; `promo` and `legit` → no action |
| 4 | Payload | Key headers (`From`, `Reply-To`, `Return-Path`, `To`, `Subject`, `Date`, `List-Unsubscribe`, `Authentication-Results`) + plain-text body truncated to 8000 chars + link domains; no attachments |
| 5 | Project | XcodeGen `project.yml` (`.xcodeproj` not committed) + local Swift package `AntispamCore` |

Routine defaults: deployment target macOS 14; model pinned to `jev-1.13.0` (thresholds are calibrated per model); request timeout 10 s; on any error the message is left untouched (fail open).

## Layout

```
project.yml                 # XcodeGen: host app + Mail extension
App/                        # SwiftUI host app: API key, threshold, "Test connection"
MailExtension/              # MEExtension + MEMessageActionHandler
Packages/AntispamCore/      # pure logic, tested with `swift test`
  MIME/                     # header + multipart parser, decoders
  Jev/                      # request builder, HTTP client, response model
  Policy/                   # (category, confidence, threshold) -> action
  Log/                      # last 200 decisions as JSON in the App Group
```

## Steps

1. **Scaffold** — `git init`, `.gitignore`, `brew install xcodegen`, `project.yml` with both targets; `DEVELOPMENT_TEAM` goes into git-ignored `Config/Local.xcconfig`.
   Verify: `xcodegen generate && xcodebuild build` succeeds; the extension shows up in Mail → Settings → Extensions.
2. **Spike: shared storage under Personal Team** — team-prefixed App Group for settings; the API key lives in a keychain access group with the same ID (`Shared/SharedSettings.swift`). The `keychain-access-groups` entitlement is required: it makes Xcode embed a provisioning profile, without which the data-protection keychain returns `-34018`. Personal Team profiles expire after 7 days, so rebuild weekly.
   Verify: value written by the app is read by the extension (os_log). If Personal Team blocks it, stop and choose a fallback.
3. **MIME parser (TDD)** — header unfolding, RFC 2047 encoded words, multipart walk, base64 / quoted-printable, charsets `utf-8`, `windows-1251`, `koi8-r`, HTML → text, link domains. Inline message fixtures.
   Verify: `swift test` green.
4. **Jev client (TDD)** — state builder (headers + body ≤ 8000 chars + domains), `choice` question with 4 options, `POST https://api.typesafe.ai/v1/systemone` with Bearer key, parse answer + confidence, non-200 → `JevError.http(status:)`.
   Verify: `swift test` green with an injected transport closure.
5. **Decision policy (TDD)** — `spam|phishing` & confidence ≥ threshold → `moveToJunk`; `spam|phishing` below threshold → yellow background; otherwise / on error → no action.
   Verify: `swift test` green.
6. **MailKit handler** — `decideAction(for:)`: `rawData == nil` → `.invokeAgainWithBody`; otherwise parse → Jev → policy → `MEMessageActionDecision`; log category and confidence.
   Verify: build succeeds; handler logs a decision for a test message.
7. **Host app UI** — API key field (Keychain), threshold slider (default 0.9), "Test connection" button.
   Verify: key saved and connection test passes against the real API.
7a. **Decision log** — every decision goes to the system log at `notice` level with sender and subject, and to `decisions.json` in the App Group (newest 200); the app shows them in a table refreshed every 5 s.
   Verify: `swift test` green; a received message appears in the table and in `log show --predicate 'subsystem == "com.kalugaman.antispam"'`.
8. **End-to-end check** — send obvious spam, phishing, a newsletter and a normal email to a real account; then review ~20 real Russian messages.
   Verify: spam lands in Junk, newsletter and normal mail untouched; note Russian accuracy.

9. **Install** — `scripts/install.sh` builds Release, unregisters development builds (two registered copies make Mail fail with PlugInKit error 16), installs `/Applications/Antispam.app`. App icon source: `Design/AppIcon.svg`, rendered by `scripts/render-icon.swift`.
   Verify: `pluginkit -m -v -i com.kalugaman.antispam.mail-extension` lists only the `/Applications` copy; after restarting Mail a new message appears in the decisions table.

10. **Watchdog** — `scripts/doctor.sh` reports: Mail cannot reach the extension, extension crash reports, a failed latest decision (Jev error, missing key), signing profile expiring within 2 days. Failures superseded by a later successful decision are ignored. `install.sh` installs a LaunchAgent that runs it with `--notify` at load and every 30 minutes (output in `~/Library/Logs/Antispam/watchdog.log`).
   Verify: `scripts/doctor.sh --since 3h` finds the 10:24 crash; the agent's first run exits 0.

## Risks

- Personal Team provisioning profiles expire after 7 days; the extension stops loading until the project is rebuilt.
- Jev accuracy on Russian is lower than on English (vendor docs); step 8 measures it.
- Every incoming message leaves the Mac for TypeSafe servers; zero data retention is enterprise-only.
- `MEMessageActionHandler` runs on newly received messages only, not on existing mail.

## Out of scope

Sender allow/block lists, learning from user corrections, distribution (Developer ID / App Store), IMAP daemon.
