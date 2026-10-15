#!/bin/zsh
# Builds build/GitGardener.app; with --install, copies it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

# Command Line Tools installed in a custom folder; otherwise the toolchain selected by `xcode-select` is used.
if [[ -z "${DEVELOPER_DIR:-}" && -d "$HOME/Developer/CommandLineTools" ]]; then
    export DEVELOPER_DIR="$HOME/Developer/CommandLineTools"
fi

swift build -c release

app=build/GitGardener.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/GitGardener" "$app/Contents/MacOS/GitGardener"
# Regenerate with: swift Scripts/make-icon.swift Resources/AppIcon.icns
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>app.gitgardener</string>
    <key>CFBundleName</key><string>GitGardener</string>
    <key>CFBundleExecutable</key><string>GitGardener</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/GitGardener.app
    cp -R "$app" /Applications/GitGardener.app
    echo "Installed /Applications/GitGardener.app"
fi
