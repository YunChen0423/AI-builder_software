#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p "build/气间 AirPause.app/Contents/MacOS" "build/气间 AirPause.app/Contents/Resources"
python3 tools/make_music.py
xcrun swiftc -swift-version 5 -O -module-cache-path /tmp/airpause-swift-cache -target arm64-apple-macosx13.0 Sources/*.swift -o "build/气间 AirPause.app/Contents/MacOS/AirPause" -framework AppKit -framework SwiftUI -framework AVFoundation -framework ScreenCaptureKit -framework Network -framework ApplicationServices
cp Resources/Info.plist "build/气间 AirPause.app/Contents/Info.plist"
cp Resources/LittleIntermission.wav "build/气间 AirPause.app/Contents/Resources/"
xcrun swift -module-cache-path /tmp/airpause-swift-cache tools/make_icon.swift build/AirPause.iconset
python3 tools/pack_icon.py
codesign --force --sign - "build/气间 AirPause.app"
print '已构建：build/气间 AirPause.app'
