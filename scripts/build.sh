#!/bin/bash
set -e

APP_NAME="2020Rule"
BUILD_DIR="build"
VERSION=${VERSION:-"1.0.0"}

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Building ${APP_NAME} (Swift)...${NC}"

mkdir -p "${BUILD_DIR}"

echo -e "${BLUE}Compiling Swift binary...${NC}"
swift build -c release --product "${APP_NAME}"

BIN_PATH=".build/release/${APP_NAME}"
if [ ! -f "${BIN_PATH}" ]; then
  echo "Binary not found at ${BIN_PATH}"
  exit 1
fi

cp "${BIN_PATH}" "${BUILD_DIR}/${APP_NAME}"

echo -e "${GREEN}✓ Binary compiled${NC}"

echo -e "${BLUE}Creating app bundle...${NC}"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/"

if [ -d "resources/icon.iconset" ]; then
    iconutil -c icns resources/icon.iconset -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP_DIR}/Contents/Info.plist" << EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>

    <key>CFBundleIdentifier</key>
    <string>com.siegfried.2020rule</string>

    <key>CFBundleName</key>
    <string>20-20-20 Rule</string>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <key>CFBundleVersion</key>
    <string>${VERSION}</string>

    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>

    <key>LSUIElement</key>
    <true/>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
EOF2

chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

echo -e "${GREEN}✓ Build complete: ${APP_DIR}${NC}"
echo -e "${BLUE}To install: cp -r ${APP_DIR} /Applications/${NC}"
