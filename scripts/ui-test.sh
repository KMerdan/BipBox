#!/bin/sh
# ui-test.sh — generate the Xcode project and run the rendered-UI test suite.
#
# Requirements:
#   - Xcode (full) + xcodebuild
#   - XcodeGen:  brew install xcodegen
#   - A logged-in GUI session (UI tests drive the real window).
#
# Usage:
#   scripts/ui-test.sh            # generate + run all UI tests
#   scripts/ui-test.sh generate   # just (re)generate Bipbox.xcodeproj
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
fi

echo "==> Generating Bipbox.xcodeproj"
xcodegen generate

if [ "${1:-}" = "generate" ]; then
    echo "Generated Bipbox.xcodeproj"
    exit 0
fi

echo "==> Running UI tests (xcodebuild)"
# -skipMacroValidation: the MLX embedder (BipboxMLX) uses Swift macros, which
# Xcode otherwise blocks pending interactive "Trust & Enable" approval.
xcodebuild test \
    -project Bipbox.xcodeproj \
    -scheme Bipbox \
    -destination 'platform=macOS' \
    -only-testing:BipboxUITests \
    -derivedDataPath .build/xcode \
    -skipMacroValidation
