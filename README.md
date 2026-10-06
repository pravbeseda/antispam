# Antispam

An Apple Mail extension for macOS that classifies every newly received message, in every Mail account, with [TypeSafe Jev](https://typesafe.ai) and acts on the result.

| Jev category | Confidence ≥ threshold | Below threshold |
|--------------|------------------------|-----------------|
| `spam`, `phishing` | moved to Junk | yellow background and gray flag, stays in Inbox |
| `promo` | purple flag | no action |
| `legit` | no action | no action |

The threshold defaults to 0.9. On any error — no API key, network failure, unexpected response — the message is left untouched.

## Requirements

- macOS 14 or later
- Xcode with an Apple Development certificate (a free Personal Team is enough)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A TypeSafe Jev API key

## Install

1. Put your team ID into `Config/Local.xcconfig` (git-ignored):

   ```
   DEVELOPMENT_TEAM = <your team id>
   ```

2. Build and install:

   ```sh
   scripts/install.sh
   ```

   It builds a Release copy into `/Applications/Antispam.app`, unregisters other copies of the extension (two registered copies make Mail fail with PlugInKit error 16) and installs the watchdog LaunchAgent.

3. Quit and reopen Mail, then enable Antispam in Mail → Settings → Extensions.
4. Open Antispam, paste the API key, set the threshold, press **Save** and **Test connection**.

The app shows the latest 200 decisions. They also go to the system log:

```sh
log show --last 1h --predicate 'subsystem == "com.kalugaman.antispam"'
```

## Watchdog

`scripts/doctor.sh` checks that filtering works: Mail can reach the extension, the extension has not crashed, the latest Jev check succeeded, and the app is in `/Applications`.

```sh
scripts/doctor.sh --since 6h
```

`install.sh` runs it with `--notify` every 30 minutes and posts a notification when it finds a problem. Output goes to `~/Library/Logs/Antispam/watchdog.log`.

## Development

```sh
xcodegen generate                              # creates Antispam.xcodeproj from project.yml
swift test --package-path Packages/AntispamCore
```

Debug builds use their own bundle ID (`com.kalugaman.antispam.debug`), so they do not compete with the installed extension in Mail.

| Path | Contents |
|------|----------|
| `project.yml` | XcodeGen spec: host app and Mail extension |
| `App/` | SwiftUI host app: API key, threshold, decisions table |
| `MailExtension/` | `MEMessageActionHandler` that turns a Jev answer into a Mail action |
| `Shared/` | settings shared through the App Group |
| `Packages/AntispamCore/` | pure logic: MIME parser, Jev client, spam policy, decision log |
| `scripts/` | install, watchdog, icon rendering |

## Limitations

- Only newly received messages are checked, not existing mail.
- Key headers, up to 8000 characters of plain-text body and link domains of every message are sent to TypeSafe servers.
- The API key is stored in plain text in the App Group container.
- Jev is less accurate on Russian than on English.
- A Personal Team build stops working when the development certificate expires; rerun `scripts/install.sh` after renewing it.
