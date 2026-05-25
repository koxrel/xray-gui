#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SH="$PROJECT_ROOT/build.sh"

assert_contains() {
    local pattern="$1"
    if ! grep -Fq "$pattern" "$BUILD_SH"; then
        echo "expected build.sh to contain: $pattern" >&2
        exit 1
    fi
}

assert_not_contains() {
    local pattern="$1"
    if grep -Fq "$pattern" "$BUILD_SH"; then
        echo "expected build.sh to not contain: $pattern" >&2
        exit 1
    fi
}

assert_contains "osascript"
assert_contains "mktemp -d"
assert_contains "rsync -a --delete"
assert_contains "graceful_quit_app"
assert_contains "wait_for_process_exit"
assert_contains 'open "$INSTALL_DIR/$APP_NAME.app"'

assert_not_contains 'pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true'
assert_not_contains 'rm -rf "$INSTALL_DIR/$APP_NAME.app"'

echo "build.sh install safety checks passed"
