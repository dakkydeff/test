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
RESOURCES_DIR="${ROOT_DIR}/Sources/${APP_NAME}/Resources"
INFO_PLIST="${RESOURCES_DIR}/Info.plist"
ICON_PNG="${RESOURCES_DIR}/AppIcon-1024.png"
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

# App icon: build AppIcon.icns from the 1024px PNG with sips + iconutil.
if [[ -f "${ICON_PNG}" ]] && command -v iconutil >/dev/null 2>&1; then
    echo "==> Generating AppIcon.icns"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "${ICONSET}"
    for size in 16 32 128 256 512; do
        sips -z "${size}" "${size}" "${ICON_PNG}" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "${double}" "${double}" "${ICON_PNG}" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "${ICONSET}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "${ICONSET}")"
else
    echo "warning: icon not generated (missing ${ICON_PNG} or iconutil)" >&2
fi

echo "==> codesign (identity: ${IDENTITY})"
if [[ "${IDENTITY}" != "-" ]] && ! security find-identity -v -p codesigning | grep -q "${IDENTITY}"; then
    echo "error: code-signing identity \"${IDENTITY}\" not found in the keychain." >&2
    echo "       security find-identity -v -p codesigning で名前を確認してください。" >&2
    exit 1
fi
codesign --force --deep --sign "${IDENTITY}" "${APP_DIR}"
codesign --verify --verbose=1 "${APP_DIR}"

echo "Built: ${APP_DIR}"
