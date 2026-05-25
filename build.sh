#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="XrayGUI"
BUILD_DIR=".build/release"
INSTALL_DIR="/Applications"
APP_BUNDLE_ID="com.xraygui.app"

wait_for_process_exit() {
    local process_name="$1"
    local timeout_seconds="${2:-10}"
    local attempts=$((timeout_seconds * 2))

    while pgrep -x "$process_name" >/dev/null 2>&1; do
        if [ "$attempts" -le 0 ]; then
            return 1
        fi
        sleep 0.5
        attempts=$((attempts - 1))
    done
}

graceful_quit_app() {
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        return 0
    fi

    echo "Requesting $APP_NAME to quit..."
    osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

    if wait_for_process_exit "$APP_NAME" 10; then
        return 0
    fi

    echo "ERROR: $APP_NAME did not exit cleanly within 10 seconds. Aborting install to avoid state loss." >&2
    return 1
}

create_app_bundle() {
    local destination="$1"

    mkdir -p "$destination/Contents/MacOS"
    mkdir -p "$destination/Contents/Resources"
    cp "$BUILD_DIR/$APP_NAME" "$destination/Contents/MacOS/"

    local xray_src="$PROJECT_ROOT/Resources/xray-core"
    if [ -d "$xray_src" ]; then
        cp -R "$xray_src" "$destination/Contents/Resources/"
        echo "Bundled xray-core resources."
    else
        echo "WARNING: xray-core not found at $xray_src — app will not work without it."
    fi

    local icon_src="$PROJECT_ROOT/Resources/AppIcon.icns"
    if [ -f "$icon_src" ]; then
        cp "$icon_src" "$destination/Contents/Resources/"
        echo "Bundled app icon."
    else
        echo "WARNING: AppIcon.icns not found — run: swift tools/generate-app-icon.swift"
    fi

    cat > "$destination/Contents/Info.plist" <<'PLIST'
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
}

sync_app_bundle() {
    local source="$1"
    local destination="$2"

    mkdir -p "$destination"
    rsync -a --delete "$source/" "$destination/"
}

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
        graceful_quit_app

        temp_dir="$(mktemp -d)"
        cleanup_temp_dir() {
            rm -rf "$temp_dir"
        }
        trap cleanup_temp_dir EXIT

        temp_bundle="$temp_dir/$APP_NAME.app"
        create_app_bundle "$temp_bundle"
        sync_app_bundle "$temp_bundle" "$INSTALL_DIR/$APP_NAME.app"

        trap - EXIT
        cleanup_temp_dir
        echo "Installed to $INSTALL_DIR/$APP_NAME.app"
        echo "Opening..."
        open "$INSTALL_DIR/$APP_NAME.app"
        ;;
    *)
        echo "Usage: $0 [run|install]"
        exit 1
        ;;
esac
