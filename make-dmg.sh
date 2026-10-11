#!/bin/zsh
# Builds the app (unless it already exists) and packages it into a DMG with an Applications shortcut.
set -e
cd "$(dirname "$0")"
NAME="System Monitor"
APP="$NAME.app"
[[ "$1" == "--rebuild" || ! -d "$APP" ]] && ./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$NAME $VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Created $DMG"
