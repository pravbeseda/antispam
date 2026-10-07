#!/bin/zsh
# Checks that the installed Antispam extension is actually filtering mail.
# Usage: doctor.sh [--notify] [--since <log interval, e.g. 35m or 6h>]
# Exit status 1 means at least one problem was found.
set -uo pipefail

notify=false
since=35m
while (( $# )); do
  case $1 in
    --notify) notify=true ;;
    --since) since=$2; shift ;;
    *) print -u2 "Unknown argument: $1"; exit 2 ;;
  esac
  shift
done

extension_id=com.kalugaman.antispam.mail-extension
problems=()

report() {
  problems+=("$1")
  print -- "PROBLEM: $1"
  # Passed as an argument: error texts contain quotes that would break an AppleScript literal.
  $notify && osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Antispam"' -e 'end run' "$1"
}

latest() {
  /usr/bin/log show --last "$since" --style compact --predicate "$1" | grep -E '^[0-9]{4}-' | tail -1
}

# Failures that a later successful decision has already superseded are not reported.
latest_action=$(latest 'subsystem == "com.kalugaman.antispam" AND category == "actions"')

# 1. Mail could not reach the extension (stale registration, PlugInKit error 16).
mail_failure=$(latest "process == \"Mail\" AND eventMessage CONTAINS \"Extension not found while attempting to find action: $extension_id\"")
if [[ -n $mail_failure && ${mail_failure[1,23]} > ${latest_action[1,23]} ]]; then
  report "Mail cannot reach the extension. Quit and reopen Mail."
fi

# 2. The extension crashed.
minutes=${since%[mh]}
[[ $since == *h ]] && minutes=$(( minutes * 60 ))
crash=$(find ~/Library/Logs/DiagnosticReports -name 'AntispamMailExtension-*.ips' -mmin -"$minutes" 2>/dev/null | head -1)
[[ -n $crash ]] && report "The extension crashed: ${crash:t}"

# 3. The latest decision failed (Jev error, missing API key).
if [[ $latest_action == *"Left untouched: "* ]]; then
  failure=${latest_action#*Left untouched: }
  report "Jev check failed: ${failure%% |*}"
fi

# 4. The app is installed.
installed=/Applications/Antispam.app
[[ -d $installed ]] || report "Antispam is not installed in /Applications. Run scripts/install.sh."

# 5. Mail runs the installed version: it keeps the old extension loaded after a reinstall until it is reopened.
appex_info=$installed/Contents/PlugIns/AntispamMailExtension.appex/Contents/Info.plist
if [[ -n $latest_action && -f $appex_info ]]; then
  installed_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$appex_info")
  # Versions before 0.1.0 did not log theirs.
  running_version="an older version"
  [[ $latest_action =~ '\| v([^ |]+)$' ]] && running_version=v$match[1]
  [[ $running_version != v$installed_version ]] && report "Mail runs Antispam $running_version, but v$installed_version is installed. Quit and reopen Mail."
fi

(( ${#problems} == 0 )) && print "OK: no problems in the last $since."
(( ${#problems} == 0 ))
