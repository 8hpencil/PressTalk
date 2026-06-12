#!/bin/bash
set -e

# Define directories
APP_NAME="PressTalk"
BUNDLE_ID="com.kenny.presstalk"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

# Version comes from the current git tag when present (vX.Y.Z), else 0.0.0-dev (U14)
VERSION="${VERSION:-$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0-dev}"

# Binary location: Universal Binary builds (CI release) land in
# .build/apple/Products/Release/, single-arch local builds in .build/release/
if [ "${UNIVERSAL:-0}" = "1" ]; then
    echo "Building Universal Binary (arm64 + x86_64) in release mode..."
    swift build -c release --arch arm64 --arch x86_64
    BINARY_PATH=".build/apple/Products/Release/${APP_NAME}"
    BUNDLE_GLOB=".build/apple/Products/Release"
else
    echo "Building Swift project in release mode..."
    swift build -c release
    BINARY_PATH=".build/release/${APP_NAME}"
    BUNDLE_GLOB=".build/release"
fi

echo "Creating App Bundle structure..."
mkdir -p "${MACOS_DIR}"

echo "Copying binary..."
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"

# Copy app icon if it exists
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
mkdir -p "${RESOURCES_DIR}"
if [ -f "AppIcon.icns" ]; then
    echo "Copying AppIcon.icns to Resources..."
    cp "AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Copy SPM resource bundles (localized strings) so Bundle.module resolves
# inside the app bundle (U10)
for bundle in "${BUNDLE_GLOB}"/*.bundle; do
    if [ -d "${bundle}" ]; then
        echo "Copying resource bundle $(basename "${bundle}")..."
        cp -R "${bundle}" "${RESOURCES_DIR}/"
    fi
done

echo "Creating Info.plist (version ${VERSION})..."
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>PressTalk needs microphone access to record your speech for dictation.</string>
</dict>
</plist>
EOF

echo "Cleaning extended attributes..."
xattr -cr "${APP_DIR}"

echo "Applying ad-hoc code signature to App Bundle..."
# On macOS (especially Apple Silicon), code signing the bundle is required for
# system service permissions (microphone, accessibility, notifications).
# Ad-hoc signing is the open-source-phase tradeoff (KTD8): first launch needs
# right-click -> Open; Developer ID + notarization is a commercial-phase item.
codesign -s - --force --deep "${APP_DIR}"

echo "App Bundle built successfully at ${APP_DIR} (version ${VERSION})"
