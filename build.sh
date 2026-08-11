#!/bin/bash
#
# Builds FolderForge.app — a self-contained, double-clickable macOS app.
#
#   ./build.sh              build into ./dist/FolderForge.app
#   ./build.sh --install    also copy it into /Applications
#   ./build.sh --run        build, then launch it
#   ./build.sh --zip        also produce a distributable zip
#   ./build.sh --dmg        also produce a distributable dmg
#   ./build.sh --notarize   sign with Developer ID, build a dmg, notarize + staple it
#
# --notarize requires:
#   DEVELOPER_ID_APPLICATION  "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE            keychain profile from `xcrun notarytool store-credentials`
#                             (defaults to "notarytool-profile")
#   NOTARY_TIMEOUT            max time to wait for Apple before returning
#                             (defaults to "20m"; the submission keeps processing)
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="FolderForge"
BUNDLE_ID="com.folderforge.app"
VERSION="1.0.7"
BUILD="8"

DIST="dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
DMG="$DIST/$APP_NAME.dmg"
ENTITLEMENTS="Resources/$APP_NAME.entitlements"

NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-20m}"

DO_INSTALL=false
DO_RUN=false
DO_ZIP=false
DO_DMG=false
DO_NOTARIZE=false
for arg in "$@"; do
  case "$arg" in
    --install)  DO_INSTALL=true ;;
    --run)      DO_RUN=true ;;
    --zip)      DO_ZIP=true ;;
    --dmg)      DO_DMG=true ;;
    --notarize) DO_NOTARIZE=true; DO_DMG=true ;;
    --help|-h)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

step() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

# ---------------------------------------------------------------- compile

step "Compiling (release)"
swift build -c release
BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

[ -x "$BINARY" ] || { echo "Build produced no binary at $BINARY" >&2; exit 1; }

# ---------------------------------------------------------------- bundle

step "Assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>           <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>            <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundleVersion</key>               <string>$BUILD</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>LSApplicationCategoryType</key>     <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSSupportsAutomaticTermination</key><true/>
    <key>NSHumanReadableCopyright</key>      <string>FolderForge</string>

    <!-- Reading the current Finder selection goes through Apple Events. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>FolderForge reads the folders you have selected in Finder so it can customize them.</string>

    <!-- Writing a custom icon means writing inside the folder. -->
    <key>NSDesktopFolderUsageDescription</key>
    <string>FolderForge needs access to set custom icons on folders on your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>FolderForge needs access to set custom icons on folders in Documents.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>FolderForge needs access to set custom icons on folders in Downloads.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>FolderForge needs access to set custom icons on folders on external drives.</string>

    <key>NSServices</key>
    <array>
        <dict><key>NSMenuItem</key><dict><key>default</key><string>FolderForge: Choose Style…</string></dict><key>NSMessage</key><string>chooseFolderStyle</string><key>NSSendFileTypes</key><array><string>public.folder</string></array></dict>
        <dict><key>NSMenuItem</key><dict><key>default</key><string>FolderForge: Restore Original Icon</string></dict><key>NSMessage</key><string>restoreFolderIcons</string><key>NSSendFileTypes</key><array><string>public.folder</string></array></dict>
    </array>

    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>     <string>FolderForge Style</string>
            <key>CFBundleTypeRole</key>     <string>Editor</string>
            <key>LSHandlerRank</key>        <string>Owner</string>
            <key>CFBundleTypeExtensions</key><array><string>folderstyle</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>     <string>FolderForge Rule Set</string>
            <key>CFBundleTypeRole</key>     <string>Editor</string>
            <key>LSHandlerRank</key>        <string>Owner</string>
            <key>CFBundleTypeExtensions</key><array><string>folderrules</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>     <string>Icon Artwork</string>
            <key>CFBundleTypeRole</key>     <string>Editor</string>
            <key>LSHandlerRank</key>        <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>icns</string>
                <string>png</string>
                <string>jpg</string>
                <string>jpeg</string>
                <string>heic</string>
                <string>tiff</string>
                <string>webp</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

# ---------------------------------------------------------------- app icon
# Rendered from Resources/AppIcon.svg at every size the iconset needs, straight from the
# vector rather than downsampled from one master, so the small sizes stay crisp.

step "Rendering app icon"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() { swift Scripts/svg2png.swift Resources/AppIcon.svg "$ICONSET/icon_$2.png" "$1"; }
render 16    16x16
render 32    16x16@2x
render 32    32x32
render 64    32x32@2x
render 128   128x128
render 256   128x128@2x
render 256   256x256
render 512   256x256@2x
render 512   512x512
render 1024  512x512@2x

iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
rm -rf "$ICONSET"

# ---------------------------------------------------------------- sign

if $DO_NOTARIZE; then
  : "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your \"Developer ID Application: ...\" identity}"
  step "Signing (Developer ID, hardened runtime)"
  SIGN_ARGS=(--force --deep --options runtime --sign "$DEVELOPER_ID_APPLICATION")
  [ -f "$ENTITLEMENTS" ] && SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
  codesign "${SIGN_ARGS[@]}" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  step "Signing (ad-hoc)"
  # Ad-hoc signing is enough to run locally and keeps macOS from re-prompting for
  # permissions every launch. Use --notarize to sign with a Developer ID instead.
  codesign --force --deep --sign - "$APP" 2>/dev/null || \
      echo "  (codesign unavailable — the app will still run)"
fi

# ---------------------------------------------------------------- dmg

if $DO_DMG; then
  step "Building $DMG"
  rm -f "$DMG"
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DMG"
  if $DO_NOTARIZE; then
    codesign --force --sign "$DEVELOPER_ID_APPLICATION" "$DMG"
  fi
fi

# ---------------------------------------------------------------- notarize

if $DO_NOTARIZE; then
  step "Submitting for notarization (timeout: $NOTARY_TIMEOUT)"
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --timeout "$NOTARY_TIMEOUT"

  step "Stapling ticket"
  xcrun stapler staple "$DMG"

  step "Verifying"
  spctl -a -t open --context context:primary-signature -v "$DMG"
fi

# ---------------------------------------------------------------- finish

if $DO_ZIP; then
  step "Zipping"
  (cd "$DIST" && rm -f "$APP_NAME.zip" && zip -qry "$APP_NAME.zip" "$APP_NAME.app")
  echo "  $DIST/$APP_NAME.zip"
fi

if $DO_INSTALL; then
  step "Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  echo "  /Applications/$APP_NAME.app"
fi

step "Done"
echo "  $APP"
$DO_DMG && echo "  $DMG"
echo
echo "  Open it:      open '$APP'"
echo "  Command line: '$MACOS/$APP_NAME' --help"

if $DO_RUN; then
  step "Launching"
  open "$APP"
fi
