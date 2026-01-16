#!/bin/bash
set -e

APP_NAME="2020Rule"
BUILD_DIR="build"
VERSION=${VERSION:-"1.0.0"}

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building ${APP_NAME}...${NC}"

# Create build directory
mkdir -p "${BUILD_DIR}"

# Build Go binary
echo -e "${BLUE}Compiling Go binary...${NC}"
go build -o "${BUILD_DIR}/${APP_NAME}" \
    -ldflags="-X main.version=${VERSION}" \
    cmd/2020rule/main.go

echo -e "${GREEN}✓ Binary compiled${NC}"

# Create app bundle structure
echo -e "${BLUE}Creating app bundle...${NC}"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy binary
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/"

# Copy resources (icons)
if [ -d "resources/icon.iconset" ]; then
    cp resources/icon.iconset/*.png "${APP_DIR}/Contents/Resources/" 2>/dev/null || true
fi

# Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << EOF
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

    <key>CFBundleVersion</key>
    <string>${VERSION}</string>

    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>

    <key>LSUIElement</key>
    <true/>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
</dict>
</plist>
EOF

echo -e "${GREEN}✓ Info.plist created${NC}"

# Make binary executable
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

echo -e "${GREEN}✓ Build complete: ${APP_DIR}${NC}"
echo -e "${BLUE}To install: cp -r ${APP_DIR} /Applications/${NC}"
