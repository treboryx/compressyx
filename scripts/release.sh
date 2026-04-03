#!/bin/bash
set -euo pipefail

# Compressy Release Script
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.0.1
#
# Prerequisites:
# 1. Set GITHUB_REPO (e.g., "yourusername/compressy")
# 2. Generate Sparkle EdDSA keys: ./scripts/generate-keys.sh
# 3. gh CLI authenticated

VERSION="${1:?Usage: ./scripts/release.sh <version>}"
GITHUB_REPO="${GITHUB_REPO:?Set GITHUB_REPO env var (e.g., yourusername/compressy)}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Compressy"
DMG_NAME="Compressy-${VERSION}.dmg"

echo "==> Building Compressy v${VERSION}..."

# Update version in project.yml
sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"${VERSION}\"/" "$PROJECT_DIR/project.yml"
sed -i '' "s/CFBundleShortVersionString: .*/CFBundleShortVersionString: \"${VERSION}\"/" "$PROJECT_DIR/project.yml"

# Regenerate Xcode project
cd "$PROJECT_DIR"
xcodegen generate

# Build release
xcodebuild -project "$PROJECT_DIR/Compressy.xcodeproj" \
    -scheme Compressy \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    clean build

APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"

echo "==> Creating DMG..."
mkdir -p "$BUILD_DIR/dmg"
cp -R "$APP_PATH" "$BUILD_DIR/dmg/"
hdiutil create -volname "$APP_NAME" -srcfolder "$BUILD_DIR/dmg" -ov -format UDZO "$BUILD_DIR/$DMG_NAME"

echo "==> Creating GitHub release..."
gh release create "v${VERSION}" "$BUILD_DIR/$DMG_NAME" \
    --repo "$GITHUB_REPO" \
    --title "Compressy v${VERSION}" \
    --generate-notes

DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${DMG_NAME}"
DMG_SIZE=$(stat -f%z "$BUILD_DIR/$DMG_NAME")

echo "==> Updating appcast.xml..."
# Generate EdDSA signature if key exists
SIGNATURE=""
if [ -f "$PROJECT_DIR/scripts/sparkle_private_key" ]; then
    SIGNATURE=$(echo -n "" | /usr/bin/openssl dgst -sha256 -sign "$PROJECT_DIR/scripts/sparkle_private_key" "$BUILD_DIR/$DMG_NAME" | base64)
fi

# Insert new item into appcast
cat > "$PROJECT_DIR/appcast.xml" << EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>Compressy</title>
        <description>Compressy update feed</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <pubDate>$(date -R)</pubDate>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${DMG_SIZE}"
                type="application/octet-stream"
                sparkle:edSignature="${SIGNATURE}" />
        </item>
    </channel>
</rss>
EOF

# Commit and push appcast
git add appcast.xml project.yml
git commit -m "Release v${VERSION}"
git push

echo "==> Done! Release v${VERSION} published."
echo "    DMG: ${DOWNLOAD_URL}"
echo "    Appcast updated and pushed."
