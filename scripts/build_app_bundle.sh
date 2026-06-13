#!/bin/sh
set -eu
# Build a RUNNABLE Bipbox.app via xcodebuild.
#
# Why not `swift build`: a plain SwiftPM binary does NOT bundle MLX's Metal
# library (.metallib), so the app crashes the moment the embedding model loads
# (e.g. when you press Download). Only an Xcode-built .app embeds the metallib.
#
# Usage:
#   scripts/build_app_bundle.sh           # build Debug, print the .app path
#   CONFIGURATION=Release scripts/build_app_bundle.sh
#
# Requirements: full Xcode (not just Command Line Tools) + xcodegen (brew install xcodegen).

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-Debug}
DERIVED=${DERIVED_DATA:-"$ROOT_DIR/.build/xcode"}
cd "$ROOT_DIR"

if command -v xcodegen >/dev/null 2>&1; then
    echo "==> xcodegen generate" >&2
    xcodegen generate >&2
elif [ ! -d "Bipbox.xcodeproj" ]; then
    echo "error: Bipbox.xcodeproj missing and xcodegen not installed (brew install xcodegen)" >&2
    exit 1
fi

echo "==> xcodebuild build ($CONFIGURATION)" >&2
xcodebuild build \
    -project Bipbox.xcodeproj \
    -scheme Bipbox \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    -skipMacroValidation \
    >&2

APP_DIR="$DERIVED/Build/Products/$CONFIGURATION/Bipbox.app"
[ -d "$APP_DIR" ] || { echo "error: $APP_DIR not produced" >&2; exit 1; }

# Guard against silent regressions: the embedder crashes without its metallib.
if ! find "$APP_DIR" -name "*.metallib" 2>/dev/null | grep -q .; then
    echo "warning: no .metallib in the bundle — the app will crash on model load" >&2
fi

echo "$APP_DIR"
