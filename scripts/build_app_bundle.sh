#!/bin/sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
CONFIGURATION=${CONFIGURATION:-debug}
PRODUCT_NAME=BipboxApp
APP_NAME=Bipbox

cd "$ROOT_DIR"
swift build --product "$PRODUCT_NAME" -c "$CONFIGURATION"

BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/$CONFIGURATION"
if [ ! -x "$BUILD_DIR/$PRODUCT_NAME" ]; then
    BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
fi

APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS_DIR/$PRODUCT_NAME"
cp "$ROOT_DIR/Sources/BipboxApp/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/$PRODUCT_NAME"

echo "$APP_DIR"
