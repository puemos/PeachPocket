#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="$PWD/build/PeachPocket.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/module-cache
arch="$(uname -m)"
rm -f "$app/Contents/Resources/"*.svg
cp Assets/Icon/*.svg "$app/Contents/Resources/"
/usr/bin/swiftc -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" -target "$arch-apple-macosx14.0" Sources/Shared.swift Sources/SessionPolicy.swift Helper/main.swift -o "$app/Contents/Resources/PeachPocketHelper" -framework Foundation -framework IOKit -framework Security
/usr/bin/codesign --force --options runtime --sign - "$app/Contents/Resources/PeachPocketHelper"
/usr/bin/shasum -a 256 "$app/Contents/Resources/PeachPocketHelper" | /usr/bin/awk '{print $1}' > "$app/Contents/Resources/HelperSHA256.txt"
/usr/bin/clang -Wall -Wextra -Werror -mmacosx-version-min=14.0 -O2 Native/Haptic.c -o "$app/Contents/Resources/PeachPocketHaptic" -framework CoreFoundation -framework IOKit
/usr/bin/codesign --force --options runtime --sign - "$app/Contents/Resources/PeachPocketHaptic"
bridge_digest=$(/usr/bin/shasum -a 256 Bridge/main.swift Sources/Shared.swift | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
if [ ! -f build/bridge-cache ] || [ "$(cat build/bridge-cache.sha256 2>/dev/null || true)" != "$bridge_digest" ]; then
    /usr/bin/swiftc -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" -target "$arch-apple-macosx14.0" Sources/Shared.swift Bridge/main.swift -o build/bridge-cache -framework Foundation -framework IOKit
    /usr/bin/codesign --force --options runtime --sign - build/bridge-cache
    printf '%s\n' "$bridge_digest" > build/bridge-cache.sha256
fi
cp build/bridge-cache "$app/Contents/Resources/PeachPocketBridge"
/usr/bin/swiftc -swift-version 5 -O -parse-as-library -module-cache-path "$PWD/build/module-cache" -target "$arch-apple-macosx14.0" Sources/*.swift -o "$app/Contents/MacOS/PeachPocket" -framework AppKit -framework SwiftUI -framework Carbon -framework IOKit -framework CoreAudio -framework Security
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.lidlight.app</string>
<key>CFBundleName</key><string>PeachPocket</string>
<key>CFBundleDisplayName</key><string>PeachPocket</string>
<key>CFBundleExecutable</key><string>PeachPocket</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>PeachPocket</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --options runtime --sign - "$app"
"$app/Contents/MacOS/PeachPocket" --export-icon "$PWD/build"
iconset="$PWD/build/PeachPocket.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" build/icon-master.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    /usr/bin/sips -z "$double" "$double" build/icon-master.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/PeachPocket.icns"
/usr/bin/codesign --force --options runtime --sign - "$app"
printf '\nBuilt %s\n' "$app"
