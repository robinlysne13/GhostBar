#!/bin/zsh
# Builds GhostBar.app next to this script.
set -e
cd "$(dirname "$0")"
APP=GhostBar.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
swiftc -O -swift-version 5 GhostBar.swift -o $APP/Contents/MacOS/GhostBar
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>GhostBar</string>
  <key>CFBundleIdentifier</key><string>com.robin.ghostbar</string>
  <key>CFBundleExecutable</key><string>GhostBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "Built $PWD/$APP"
