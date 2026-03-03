#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="XrayGUI"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"

echo "Building $APP_NAME in release mode..."
swift build -c release

echo "Build complete: $BUILD_DIR/$APP_NAME"

# Launch or install
case "${1:-run}" in
    run)
        echo "Launching $APP_NAME..."
        exec "$BUILD_DIR/$APP_NAME"
        ;;
    install)
        echo "Installing to $INSTALL_DIR..."
        # Kill running instance if any
        pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
        if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
            rm -rf "$INSTALL_DIR/$APP_NAME.app"
        fi
        # SwiftPM executable targets don't produce .app bundles,
        # so copy the binary and resources into a minimal wrapper
        mkdir -p "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS"
        mkdir -p "$INSTALL_DIR/$APP_NAME.app/Contents/Resources"
        cp "$BUILD_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/"
        # Copy xray-core resources into the app bundle
        XRAY_SRC="$PROJECT_ROOT/Resources/xray-core"
        if [ -d "$XRAY_SRC" ]; then
            cp -R "$XRAY_SRC" "$INSTALL_DIR/$APP_NAME.app/Contents/Resources/"
            echo "Bundled xray-core resources."
        else
            echo "WARNING: xray-core not found at $XRAY_SRC — app will not work without it."
        fi
        # Copy app icon into the bundle
        ICON_SRC="$PROJECT_ROOT/Resources/AppIcon.icns"
        if [ -f "$ICON_SRC" ]; then
            cp "$ICON_SRC" "$INSTALL_DIR/$APP_NAME.app/Contents/Resources/"
            echo "Bundled app icon."
        else
            echo "WARNING: AppIcon.icns not found — run: swift tools/generate-app-icon.swift"
        fi
        cat > "$INSTALL_DIR/$APP_NAME.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>XrayGUI</string>
    <key>CFBundleIdentifier</key>
    <string>com.xraygui.app</string>
    <key>CFBundleName</key>
    <string>Xray GUI</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST
        echo "Installed to $INSTALL_DIR/$APP_NAME.app"
        echo "Opening..."
        open "$INSTALL_DIR/$APP_NAME.app"
        ;;
    *)
        echo "Usage: $0 [run|install]"
        exit 1
        ;;
esac
