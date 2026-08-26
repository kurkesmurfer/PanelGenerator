#!/usr/bin/env bash
# Assembles a standalone PanelGenerator.app bundle from the SPM build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/PanelGenerator"
APP="PanelGenerator.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PanelGenerator"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>PanelGenerator</string>
    <key>CFBundleIdentifier</key><string>dev.peet.PanelGenerator</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>PanelGenerator</string>
    <key>CFBundleDisplayName</key><string>PanelGenerator</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# --- Icon -------------------------------------------------------------------
# A panel, drawn by the thing that draws panels. ICON_PANEL may be any
# .panelgen; the default is whichever the repository ships.
ICON_PANEL="${ICON_PANEL:-$HOME/Development/Muse/vcv-nd/panels/Muse_ND.panelgen}"

if [ -f "$ICON_PANEL" ]; then
    ICONSET="$(mktemp -d)/PanelGenerator.iconset"
    mkdir -p "$ICONSET"
    # macOS wants every size rendered, not one scaled down: a panel at 32 px is
    # a silhouette, and letting sips reduce a 1024 px render turns it to mush.
    for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
                "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
                "512 512x512" "1024 512x512@2x"; do
        set -- $pair
        "$BIN" --icon "$ICON_PANEL" "$ICONSET/icon_$2.png" "$1" >/dev/null
    done
    if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/PanelGenerator.icns" 2>/dev/null; then
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string PanelGenerator" \
            "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
        echo "Icon from $(basename "$ICON_PANEL")"
    else
        echo "iconutil failed — bundle built without an icon"
    fi
    rm -rf "$(dirname "$ICONSET")"
else
    echo "No icon panel at $ICON_PANEL — bundle built without an icon"
fi

codesign --force --deep -s - "$APP" 2>/dev/null || true
echo "Built $APP — launch with: open $APP"
