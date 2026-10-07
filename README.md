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

## Versions

After a merge to `main`, the Release workflow tags the head of `main` with the next patch version (`v0.1.0`, `v0.1.1`, …) and publishes a GitHub release with notes from the pull requests merged since the previous one. Merges that land while a release is running share the next one, so not every merge commit gets its own tag. For a minor or major bump, publish the release by hand before the next merge:

```sh
gh release create v0.2.0 --target main --generate-notes
```

`install.sh` builds the version from `git describe`, so pull before installing. A build off a tag shows its distance from it, e.g. `0.1.3-2-gabc1234`, or `-dirty` with uncommitted changes.

The app shows its own version next to the version of the extension Mail last ran. Mail keeps the old extension loaded after a reinstall until it is reopened; the line turns orange until Mail checks a message with the new one.

## Watchdog

`scripts/doctor.sh` checks that filtering works: Mail can reach the extension, the extension has not crashed, the latest Jev check succeeded, the app is in `/Applications`, and Mail runs the installed version.

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
