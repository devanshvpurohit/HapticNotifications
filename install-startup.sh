#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$HOME/Applications/HapticNotifications.app"

echo "==> Building and bundling HapticNotifications..."
"$DIR/run.sh"

echo "==> Installing to $HOME/Applications..."
mkdir -p "$HOME/Applications"
rm -rf "$APP_PATH"
cp -R "$DIR/HapticNotifications.app" "$APP_PATH"

echo "==> Registering with macOS Login Items..."
osascript -e "
tell application \"System Events\"
    if exists (login item \"HapticNotifications\") then
        delete login item \"HapticNotifications\"
    end if
    make login item at end with properties {name:\"HapticNotifications\", path:\"$APP_PATH\", hidden:false}
end tell
"

echo "==> Done! HapticNotifications will now launch automatically whenever you log in."
echo "    You can also see and manage it in System Settings > General > Login Items."
