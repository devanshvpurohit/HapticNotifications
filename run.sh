#!/usr/bin/env bash
set -e

# Compile Swift package
echo "==> Building HapticNotifications..."
swift build -c release

# Assemble .app bundle
APP_DIR="HapticNotifications.app"
echo "==> Packaging into ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp ".build/release/HapticNotifications" "${APP_DIR}/Contents/MacOS/"
cp "Resources/Info.plist" "${APP_DIR}/Contents/"

# Optional ad-hoc code sign so macOS handles notifications without bundle mismatch
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true

echo "==> Successfully created ${APP_DIR}"

if [ "$1" = "--open" ] || [ "$1" = "-o" ]; then
    echo "==> Launching ${APP_DIR}..."
    open "${APP_DIR}"
fi
