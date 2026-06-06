#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="DocumentTabsShowcase"
BUNDLE="$APP.app"
TARGET="arm64-apple-macos15.0"
LIB="../../Sources/Tabberwocky/Tabberwocky.swift"   # the Tabberwocky library source

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleDisplayName</key><string>Tabberwocky Showcase</string>
  <key>CFBundleIdentifier</key><string>com.tabberwocky.$APP</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Plain Text</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.plain-text</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Source Code</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.source-code</string><string>public.swift-source</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Markdown</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>net.daringfireball.markdown</string><string>public.markdown</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Bundle the sample docs, the skill .md, the library source, and this example's source —
# so the running app can open them all as tabs.
cp Resources/*.txt "$BUNDLE/Contents/Resources/"
cp Resources/*.md  "$BUNDLE/Contents/Resources/"
cp Sources/*.swift "$BUNDLE/Contents/Resources/"
cp "$LIB"          "$BUNDLE/Contents/Resources/"

echo "Compiling…"
swiftc -O -target "$TARGET" \
  -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers \
  -o "$BUNDLE/Contents/MacOS/$APP" \
  "$LIB" Sources/*.swift

codesign --force --sign - "$BUNDLE" 2>/dev/null || true
echo "Built $BUNDLE"
