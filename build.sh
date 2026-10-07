#!/bin/bash
# Builds WeatherMenuBar.app into ./build. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/WeatherMenuBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Some Command Line Tools upgrades leave a stale usr/include/swift/module.modulemap that
# clashes with bridging.modulemap ("redefinition of module 'SwiftBridging'") and breaks
# every Foundation import. Hide it with a VFS overlay instead of editing system files.
OVERLAY_FLAGS=()
STALE="$(xcode-select -p)/usr/include/swift/module.modulemap"
if [[ -f "$STALE" && -f "$(dirname "$STALE")/bridging.modulemap" ]] && grep -q SwiftBridging "$STALE"; then
    : > build/empty.modulemap
    cat > build/overlay.yaml <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory",
  "name": "$(dirname "$STALE")", "contents": [ { "type": "file",
  "name": "module.modulemap", "external-contents": "$PWD/build/empty.modulemap" } ] } ] }
YAML
    OVERLAY_FLAGS=(-vfsoverlay build/overlay.yaml -Xcc -ivfsoverlay -Xcc "$PWD/build/overlay.yaml")
fi

swiftc -O -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-macos13.0" \
    ${OVERLAY_FLAGS[@]+"${OVERLAY_FLAGS[@]}"} \
    -o "$APP/Contents/MacOS/WeatherMenuBar" \
    Sources/WeatherMenuBar/*.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>WeatherMenuBar</string>
    <key>CFBundleDisplayName</key><string>Weather Menu Bar</string>
    <key>CFBundleIdentifier</key><string>local.weathermenubar</string>
    <key>CFBundleExecutable</key><string>WeatherMenuBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocationUsageDescription</key><string>Your location is used to show local weather in the menu bar.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>Your location is used to show local weather in the menu bar.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Location Services and Launch at Login work.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    pkill -x WeatherMenuBar 2>/dev/null || true
    rm -rf ~/Applications/WeatherMenuBar.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/WeatherMenuBar.app
    echo "Installed to ~/Applications/WeatherMenuBar.app and launched"
fi
