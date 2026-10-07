#!/bin/zsh
# Builds a Release copy, installs it into /Applications and makes it the only Antispam extension Mail can see.
set -euo pipefail
cd "${0:A:h}/.."

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
installed=/Applications/Antispam.app

# The Release workflow tags every merge to main; a build off a tag shows how far it is from it, e.g. 0.1.3-2-gabc1234.
version=$(git describe --tags --match 'v[0-9]*' --always --dirty)
version=${version#v}

xcodegen generate --quiet
xcodebuild -project Antispam.xcodeproj -scheme Antispam -configuration Release \
  -derivedDataPath .build/xcode -allowProvisioningUpdates -quiet build \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)"

# Building registers the product; the Release copy here has the installed extension's ID,
# and two registered copies make Mail fail with PlugInKit error 16.
built=.build/xcode/Build/Products/Release/Antispam.app
pluginkit -r "$built/Contents/PlugIns/AntispamMailExtension.appex" 2>/dev/null || true
"$lsregister" -u "$built" 2>/dev/null || true

pkill -x Antispam || true
pkill -f AntispamMailExtension.appex || true
# Opening the app while the old instance is still quitting fails with LaunchServices error -600.
while pgrep -x Antispam >/dev/null; do sleep 0.2; done
rm -rf "$installed"
ditto .build/xcode/Build/Products/Release/Antispam.app "$installed"
"$lsregister" -f "$installed"
pluginkit -a "$installed/Contents/PlugIns/AntispamMailExtension.appex"

# Watchdog: runs doctor.sh every 30 minutes and posts a notification when filtering is broken.
support=~/Library/Application\ Support/Antispam
agent=~/Library/LaunchAgents/com.kalugaman.antispam.watchdog.plist
mkdir -p "$support" ~/Library/Logs/Antispam
cp scripts/doctor.sh "$support/doctor.sh"
cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.kalugaman.antispam.watchdog</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$support/doctor.sh</string><string>--notify</string></array>
  <key>StartInterval</key><integer>1800</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/Antispam/watchdog.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/Antispam/watchdog.log</string>
</dict>
</plist>
PLIST
launchctl bootout gui/$UID/com.kalugaman.antispam.watchdog 2>/dev/null || true
launchctl bootstrap gui/$UID "$agent"

# The first launch re-registers the extension under a new ID; Mail must start after that, not before.
open -g "$installed"
sleep 3

echo "Installed $installed v$version. Quit and reopen Mail now to load the new extension."
