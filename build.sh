#!/bin/zsh
set -eu
cd "${0:A:h}"
app_dir="${OUTPUT_DIR:-$HOME/Applications}/网络优先级.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" .build
swift make-icon.swift "$PWD/assets"
iconutil -c icns assets/AppIcon.iconset -o "$app_dir/Contents/Resources/AppIcon.icns"
swiftc main.swift -target arm64-apple-macos13.0 -o .build/NetworkPriority-arm64 -framework AppKit
swiftc main.swift -target x86_64-apple-macos13.0 -o .build/NetworkPriority-x86_64 -framework AppKit
lipo -create .build/NetworkPriority-arm64 .build/NetworkPriority-x86_64 -output "$app_dir/Contents/MacOS/NetworkPriority"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NetworkPriority</string>
<key>CFBundleIdentifier</key><string>local.jeremy.networkpriority</string>
<key>CFBundleName</key><string>网络优先级</string>
<key>CFBundleDisplayName</key><string>网络优先级</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app_dir"
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"
