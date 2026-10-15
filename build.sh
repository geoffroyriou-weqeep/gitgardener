#!/bin/zsh
# Builds build/GitGardener.app; with --install, copies it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

export DEVELOPER_DIR="${DEVELOPER_DIR:-$HOME/Developer/CommandLineTools}"

swift build -c release

app=build/GitGardener.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/GitGardener" "$app/Contents/MacOS/GitGardener"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.geoffroyriou.gitgardener</string>
    <key>CFBundleName</key><string>GitGardener</string>
    <key>CFBundleExecutable</key><string>GitGardener</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/GitGardener.app
    cp -R "$app" /Applications/GitGardener.app
    echo "Installed /Applications/GitGardener.app"
fi
