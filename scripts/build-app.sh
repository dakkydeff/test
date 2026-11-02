#!/usr/bin/env bash
# Builds KindleToPDF.app from the SwiftPM package and ad-hoc signs it.
#
# Usage: scripts/build-app.sh
#   CODESIGN_IDENTITY  signing identity (default "-" = ad-hoc). A stable
#                      certificate keeps TCC permissions across rebuilds.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="KindleToPDF"
APP_DIR="${ROOT_DIR}/build/${APP_NAME}.app"
INFO_PLIST="${ROOT_DIR}/Sources/${APP_NAME}/Resources/Info.plist"
IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: KindleToPDF.app can only be built on macOS." >&2
    exit 1
fi

cd "${ROOT_DIR}"

echo "==> swift build -c release --product ${APP_NAME}"
swift build -c release --product "${APP_NAME}"
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${INFO_PLIST}" "${APP_DIR}/Contents/Info.plist"
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

echo "==> codesign (identity: ${IDENTITY})"
codesign --force --deep --sign "${IDENTITY}" "${APP_DIR}"
codesign --verify --verbose=1 "${APP_DIR}"

echo "Built: ${APP_DIR}"
