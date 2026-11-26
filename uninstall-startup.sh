#!/usr/bin/env bash
set -e

echo "==> Removing HapticNotifications from macOS Login Items..."
osascript -e '
tell application "System Events"
    if exists (login item "HapticNotifications") then
        delete login item "HapticNotifications"
        log "Removed HapticNotifications from Login Items."
    end if
end tell
'

echo "==> To remove the application bundle, run:"
echo "    rm -rf \"$HOME/Applications/HapticNotifications.app\""
echo "==> Done!"
