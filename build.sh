#!/bin/zsh
set -eu
cd "${0:A:h}"
bundle="$PWD/build/Mac Auto Unlock.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp assets/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.mads.MacSessionHelper</string>
<key>CFBundleName</key><string>Mac Auto Unlock</string>
<key>CFBundleDisplayName</key><string>Mac Auto Unlock</string>
<key>CFBundleExecutable</key><string>MacSessionHelper</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.6</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
swiftc -O Sources/Policy.swift Sources/Protocol.swift Sources/TrustedLoginwindow.swift Sources/MainRunLoop.swift Sources/DisplayWake.swift Sources/main.swift -o "$bundle/Contents/MacOS/MacSessionHelper" -framework AppKit -framework Security -framework OpenDirectory -framework ApplicationServices -framework IOKit
codesign --force --sign "${SIGNING_IDENTITY:--}" "$bundle"
codesign --verify --strict "$bundle"
echo "Built $bundle"
