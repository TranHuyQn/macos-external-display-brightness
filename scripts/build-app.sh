#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_DIR="${BUILD_DIR}/DisplayControl.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

echo "==> Building release binary..."
swift build -c release

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "==> Copying binary & stripping..."
cp "${PROJECT_DIR}/.build/release/DisplayControl" "${MACOS_DIR}/DisplayControl"
strip "${MACOS_DIR}/DisplayControl"

echo "==> Copying Info.plist..."
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

echo "==> Copying AppIcon.icns..."
mkdir -p "${RESOURCES_DIR}"
if [ -f "${PROJECT_DIR}/Resources/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo "==> Code signing..."
if security find-identity -v -p codesigning 2>/dev/null | grep -q "DisplayControl Dev"; then
    echo "Using certificate 'DisplayControl Dev'"
    codesign --force --sign "DisplayControl Dev" "${APP_DIR}"
else
    echo "Using ad-hoc signature (-)"
    codesign --force --sign - "${APP_DIR}"
fi

echo "==> Verifying signature..."
codesign --verify --strict "${APP_DIR}"
echo "Successfully built and signed ${APP_DIR}"
