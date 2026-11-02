#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP=build/BreakBuddy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.breakbuddy</string>
    <key>CFBundleName</key><string>BreakBuddy</string>
    <key>CFBundleExecutable</key><string>BreakBuddy</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 Sources/main.swift -o "$APP/Contents/MacOS/BreakBuddy"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "install" ]]; then
    mkdir -p ~/Applications
    pkill -x BreakBuddy || true
    rm -rf ~/Applications/BreakBuddy.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/BreakBuddy.app
    echo "Installed to ~/Applications/BreakBuddy.app"
else
    echo "Built $APP"
fi
