#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-"$(cd flutter_app && grep '^version: ' pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')"}"
APP_NAME="chinese-classical-rec-sys"
ARCH="x86_64"

BUILD_DIR="build/appimage"
APPDIR="${BUILD_DIR}/AppDir"

echo "=== Packaging ${APP_NAME} v${VERSION} ==="

# 1. Build Flutter
(cd flutter_app && flutter build linux --release)

# 2. Create AppDir layout
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/lib"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

# 3. Copy bundle
cp -r flutter_app/build/linux/x64/release/bundle/* "${APPDIR}/usr/bin/"

# 4. Copy .desktop
cp packaging/linux/${APP_NAME}.desktop "${APPDIR}/usr/share/applications/"

# 5. Copy icon
cp assets/icon/icon.png "${APPDIR}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"

# 6. Ensure chinese_core.so is in bundle (safety net)
cp build/libchinese_core.so flutter_app/build/linux/x64/release/bundle/lib/

# 7. Download linuxdeploy (no .AppImage suffix to avoid glob pollution)
LINUXDEPLOY="${BUILD_DIR}/linuxdeploy-${ARCH}"
if [ ! -f "${LINUXDEPLOY}" ]; then
  mkdir -p "${BUILD_DIR}"
  wget -q "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${ARCH}.AppImage" -O "${LINUXDEPLOY}"
  chmod +x "${LINUXDEPLOY}"
fi

# 8. Run linuxdeploy
${LINUXDEPLOY} --appdir "${APPDIR}" --output appimage
rm -f "${LINUXDEPLOY}"

# 9. Rename output
OUTPUT="chinese-classical-rec-sys-${VERSION}-linux.AppImage"
APPIMAGE_FILE=$(ls *.AppImage 2>/dev/null | head -1)
if [ -n "$APPIMAGE_FILE" ]; then
  mv "$APPIMAGE_FILE" "${OUTPUT}"
fi

echo "=== Done: ${OUTPUT} ==="
