#!/bin/zsh
# Builds Photo Picker.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Photo Picker.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/PhotoPicker" Sources/*.swift

# App icon (drawn by tools/make-icon.swift)
ICONSET=build/AppIcon.iconset && mkdir -p $ICONSET
xcrun swift tools/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Photo Picker</string>
  <key>CFBundleDisplayName</key><string>Photo Picker</string>
  <key>CFBundleIdentifier</key><string>org.jakedev.photopicker</string>
  <key>CFBundleExecutable</key><string>PhotoPicker</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Made by Jake Davis.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Photo Picker reads photos from your camera card.</string>
  <key>NSPhotoLibraryUsageDescription</key><string>Photo Picker shows your Photos library so you can copy the shots you pick into a folder.</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Folder</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array>
  </dict></array>
</dict></plist>
PLIST
# Sign with your Apple Development certificate if you have one (so macOS remembers the
# Photos permission across rebuilds); otherwise ad-hoc.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Signed with: ${SIGN_ID:-ad-hoc}"
mkdir -p ~/Applications
rm -rf ~/Applications/"Photo Picker.app"
cp -R "$APP" ~/Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/"Photo Picker.app"
echo "Installed ~/Applications/Photo Picker.app"
