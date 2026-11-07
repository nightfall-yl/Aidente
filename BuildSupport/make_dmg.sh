#!/bin/zsh
# Build a distributable DMG from Dist/Aidente.app (hdiutil, no third-party deps).
#
# Usage:
#   zsh BuildSupport/make_dmg.sh                 # -> Dist/Aidente-<version>.dmg
#   zsh BuildSupport/make_dmg.sh /path/foo.dmg  # custom output path
#
# The version is read from the built app's Info.plist — no version is decided
# here. Run BuildSupport/build_app.sh first.
#
# Note: a regular build is ad-hoc signed. For distribution outside your own
# machines, rebuild with a Developer ID and notarize separately:
#   AIDENTE_RELEASE_BUILD=1 \
#   AIDENTE_SIGNING_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" \
#   zsh BuildSupport/build_app.sh
#   xcrun notarytool submit "<dmg>" --apple-id ... --team-id ... --password ... --wait
#   xcrun stapler staple "<dmg>"
set -euo pipefail

project_dir=${0:A:h:h}
dist_dir="$project_dir/Dist"
app_dir="$dist_dir/Aidente.app"

if [[ ! -d "$app_dir" ]]; then
    print -u2 "error: $app_dir not found. Run BuildSupport/build_app.sh first."
    exit 1
fi

info_plist="$app_dir/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info_plist")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist")
output="${1:-$dist_dir/Aidente-$version.dmg}"

if codesign -dv --verbose=2 "$app_dir" 2>&1 | grep -q "Signature=adhoc"; then
    print -u2 "warning: app is ad-hoc signed — this DMG is for local / trusted distribution only (Gatekeeper will block it elsewhere)."
fi

stage=$(mktemp -d /tmp/aidente-dmg.XXXXXX)
trap 'rm -rf "$stage"' EXIT

cp -R "$app_dir" "$stage/"
ln -s /Applications "$stage/Applications"
# Keep Finder metadata out of the image (no .DS_Store / AppleDouble files).
find "$stage" -name '.DS_Store' -delete
find "$stage" -name '._*' -delete

hdiutil create \
    -volname "Aidente $version" \
    -srcfolder "$stage" \
    -ov \
    -format UDZO \
    "$output"

hdiutil verify "$output"

print "Aidente $version (build $build)"
ls -lh "$output"
print "Done: $output"
