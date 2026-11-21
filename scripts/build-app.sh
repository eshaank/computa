#!/usr/bin/env bash
# Builds the release Computa binary and wraps it into app/.build/Computa.app, ad-hoc signed.
# The version comes from app/VERSION.
#
# Usage: scripts/build-app.sh
set -euo pipefail

fail() {
    echo "build-app: $*" >&2
    exit 1
}
trap 'echo "build-app: failed at line $LINENO: $BASH_COMMAND" >&2' ERR

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package="$root/app"
bundle="$package/.build/Computa.app"
bundle_id="app.computa.Computa"

[[ -f "$package/VERSION" ]] || fail "missing $package/VERSION"
version="$(tr -d '[:space:]' < "$package/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must look like 1.2.3, got '$version'"

echo "build-app: building Computa $version (release)"
swift build --package-path "$package" -c release --product Computa \
    || fail "swift build failed"
bin_dir="$(swift build --package-path "$package" -c release --show-bin-path)" \
    || fail "could not find the release build directory"
[[ -x "$bin_dir/Computa" ]] || fail "no executable at $bin_dir/Computa"

echo "build-app: assembling $bundle"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin_dir/Computa" "$bundle/Contents/MacOS/Computa"

cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Computa</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Computa</string>
    <key>CFBundleDisplayName</key>
    <string>Computa</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
plutil -lint "$bundle/Contents/Info.plist" >/dev/null || fail "Info.plist is not valid"

echo "build-app: signing (ad hoc)"
codesign --force --sign - --timestamp=none "$bundle" || fail "codesign failed"
codesign --verify --strict "$bundle" || fail "the signature does not verify"

echo "build-app: done: $bundle ($version)"
