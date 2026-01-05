#!/bin/bash
#
# generate-appcast.sh - Generate Sparkle appcast.xml for updates
#
# Usage: ./scripts/generate-appcast.sh
#
# This script:
#   1. Finds all DMG releases in the releases/ folder
#   2. Signs them with your EdDSA private key (from Keychain)
#   3. Generates appcast.xml with update information
#   4. Creates delta updates for faster downloads
#
# Prerequisites:
#   - Sparkle added to project (for generate_appcast tool)
#   - EdDSA key in Keychain (run generate-sparkle-keys.sh first)
#   - At least one release DMG in releases/ folder
#

set -e

# Load shared configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/scripts/config.sh"

# Script-specific paths
OUTPUT_DIR="$BUILD_DIR/appcast"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Sparkle Appcast Generator${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check for releases
if [ ! -d "$RELEASES_DIR" ]; then
    log_error "Releases directory not found: $RELEASES_DIR"
    log_error "Run ./scripts/release.sh first to create a release"
    exit 1
fi

# Find DMG files
DMG_COUNT=$(find "$RELEASES_DIR" -name "*.dmg" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$DMG_COUNT" -eq 0 ]; then
    log_error "No DMG files found in $RELEASES_DIR"
    log_error "Run ./scripts/release.sh first to create a release"
    exit 1
fi

log_info "Found $DMG_COUNT release(s)"

# Find Sparkle's generate_appcast tool
GENERATE_APPCAST=""

# Check DerivedData first (most common location after building)
DERIVED_DATA_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "generate_appcast" -type f 2>/dev/null | head -1)
if [ -n "$DERIVED_DATA_PATH" ] && [ -x "$DERIVED_DATA_PATH" ]; then
    GENERATE_APPCAST="$DERIVED_DATA_PATH"
fi

# Check other common locations
if [ -z "$GENERATE_APPCAST" ]; then
    POSSIBLE_PATHS=(
        "/usr/local/bin/generate_appcast"
        "$HOME/.local/bin/generate_appcast"
        "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
    )

    for path in "${POSSIBLE_PATHS[@]}"; do
        if [ -x "$path" ]; then
            GENERATE_APPCAST="$path"
            break
        fi
    done
fi

if [ -z "$GENERATE_APPCAST" ]; then
    log_error "Sparkle's generate_appcast tool not found"
    echo ""
    echo "This tool is included with Sparkle. To use it:"
    echo ""
    echo "  1. Add Sparkle to your Xcode project (if not already done)"
    echo "  2. Build the project once (Cmd+B)"
    echo "  3. Run this script again"
    echo ""
    exit 1
fi

log_info "Using generate_appcast: $GENERATE_APPCAST"

# Check for EdDSA signing key in Keychain
if ! security find-generic-password -s "https://sparkle-project.org" -a "ed25519" &>/dev/null; then
    log_error "No EdDSA signing key found in Keychain"
    echo ""
    echo "Run ./scripts/generate-sparkle-keys.sh first to create a signing key."
    echo ""
    exit 1
fi

log_info "Found EdDSA signing key in Keychain"

# Prepare output directory
mkdir -p "$OUTPUT_DIR"

# Copy all release DMGs to a staging area
STAGING_DIR="$OUTPUT_DIR/staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

log_step "Collecting release DMGs..."
find "$RELEASES_DIR" -name "*.dmg" -type f | while read dmg; do
    VERSION_DIR=$(dirname "$dmg")
    VERSION=$(basename "$VERSION_DIR")
    TARGET_NAME="Willpower-${VERSION}.dmg"

    log_info "  $VERSION: $(basename "$dmg")"
    cp "$dmg" "$STAGING_DIR/$TARGET_NAME"
done

# Generate appcast
log_step "Generating appcast.xml..."

GENERATE_ARGS=()

# Sparkle's generate_appcast automatically uses key from Keychain
log_info "Signing with EdDSA key from Keychain"

# Add download URL prefix if configured
DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL:-}"
if [ -n "$DOWNLOAD_URL_PREFIX" ]; then
    log_info "Using download URL prefix: $DOWNLOAD_URL_PREFIX"
    GENERATE_ARGS+=(--download-url-prefix "$DOWNLOAD_URL_PREFIX")
fi

# Run generate_appcast
"$GENERATE_APPCAST" "${GENERATE_ARGS[@]}" "$STAGING_DIR" || {
    log_error "generate_appcast failed"
    log_error "This may happen if:"
    log_error "  - DMG files are not properly signed"
    log_error "  - App bundle is missing CFBundleVersion"
    echo ""
    log_info "Try running manually:"
    log_info "  $GENERATE_APPCAST $STAGING_DIR"
    exit 1
}

# Move generated files to output
if [ -f "$STAGING_DIR/appcast.xml" ]; then
    mv "$STAGING_DIR/appcast.xml" "$OUTPUT_DIR/"
    log_info "Generated: $OUTPUT_DIR/appcast.xml"
fi

# Move delta updates if generated
DELTA_COUNT=$(find "$STAGING_DIR" -name "*.delta" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$DELTA_COUNT" -gt 0 ]; then
    log_info "Generated $DELTA_COUNT delta update(s)"
    mv "$STAGING_DIR"/*.delta "$OUTPUT_DIR/" 2>/dev/null || true
fi

# Clean up staging
rm -rf "$STAGING_DIR"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Appcast Generation Complete${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Generated files:"
ls -la "$OUTPUT_DIR/"
echo ""
echo "Next steps:"
echo "  1. Review appcast.xml and verify version info"
echo "  2. Upload appcast.xml to your web server"
echo "  3. Upload DMG files to your download server"
echo "  4. Upload delta files (if any) alongside DMGs"
echo ""
echo "Update your Info.plist SUFeedURL to point to:"
echo "  https://YOUR_DOMAIN.com/appcast.xml"
echo ""

# Show appcast contents
if [ -f "$OUTPUT_DIR/appcast.xml" ]; then
    echo "Appcast preview:"
    echo "────────────────────────────────────────"
    head -50 "$OUTPUT_DIR/appcast.xml"
    echo ""
    echo "────────────────────────────────────────"
fi
