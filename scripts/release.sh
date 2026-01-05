#!/bin/bash
#
# release.sh - Complete release workflow for Willpower
#
# Usage: ./scripts/release.sh <version>
#
# This script automates the entire release process:
#   1. Clean build in Release configuration
#   2. Code sign with Developer ID
#   3. Notarize with Apple
#   4. Create signed and notarized DMG
#
# Prerequisites:
#   - Xcode Command Line Tools
#   - Developer ID Application certificate installed
#   - Notary credentials stored: xcrun notarytool store-credentials "willpower-notary"
#   - brew install create-dmg
#

set -e

# Load shared configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/scripts/config.sh"

# Script-specific config
SCHEME="Willpower"
CONFIGURATION="Release"

# Validate arguments
VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo ""
    echo "Complete release workflow for Willpower."
    echo ""
    echo "Arguments:"
    echo "  version    Version string (e.g., 1.0.0, 1.2.3-beta)"
    echo ""
    echo "Example:"
    echo "  $0 1.0.0"
    echo ""
    echo "Prerequisites:"
    echo "  - Xcode Command Line Tools installed"
    echo "  - Developer ID Application certificate in Keychain"
    echo "  - Notary credentials stored:"
    echo "      xcrun notarytool store-credentials \"willpower-notary\""
    echo "  - create-dmg installed: brew install create-dmg"
    exit 1
fi

# Validate prerequisites
log_header "Checking Prerequisites"

# Check Xcode
if ! xcodebuild -version &>/dev/null; then
    log_error "Xcode Command Line Tools not found"
    exit 1
fi
XCODE_VERSION=$(xcodebuild -version | head -1)
log_info "Xcode: $XCODE_VERSION"

# Check signing identity (from config.sh)
if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    log_error "Signing identity not found: $SIGNING_IDENTITY"
    exit 1
fi
log_info "Signing identity: Found"

# Check notary credentials
if ! xcrun notarytool history --keychain-profile "willpower-notary" &>/dev/null; then
    log_warn "Could not verify notary credentials (this is normal if no prior submissions)"
fi
log_info "Notary profile: willpower-notary"

# Check create-dmg
if ! command -v create-dmg &>/dev/null; then
    log_error "create-dmg not found. Install with: brew install create-dmg"
    exit 1
fi
log_info "create-dmg: Installed"

# Create directories
mkdir -p "$BUILD_DIR"
mkdir -p "$RELEASES_DIR/$VERSION"

RELEASE_OUTPUT_DIR="$RELEASES_DIR/$VERSION"

log_header "Step 1/4: Building Release"

log_step "Cleaning previous builds..."
rm -rf "$BUILD_DIR/Build"
rm -rf "$BUILD_DIR/DerivedData"

log_step "Building $SCHEME in $CONFIGURATION configuration..."
xcodebuild -project "$PROJECT_DIR/Willpower.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | grep -E "(Building|Compiling|Linking|Build succeeded|error:|warning:)" || true

# Find the built app
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "Willpower.app" -type d | head -1)
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    log_error "Build failed - Willpower.app not found"
    log_error "Check Xcode for build errors"
    exit 1
fi

log_info "Build complete: $APP_PATH"

# Copy to release directory for processing
RELEASE_APP_PATH="$RELEASE_OUTPUT_DIR/Willpower.app"
rm -rf "$RELEASE_APP_PATH"
cp -R "$APP_PATH" "$RELEASE_APP_PATH"

log_header "Step 2/4: Code Signing"

"$SCRIPTS_DIR/codesign.sh" "$RELEASE_APP_PATH"

log_header "Step 3/4: Notarization"

"$SCRIPTS_DIR/notarize.sh" "$RELEASE_APP_PATH"

log_header "Step 4/4: Creating DMG"

# Move to release directory for DMG creation
cd "$RELEASE_OUTPUT_DIR"

"$SCRIPTS_DIR/create-dmg.sh" "$RELEASE_APP_PATH" "$VERSION"

# Move DMG to release directory
if [ -f "$BUILD_DIR/Willpower-${VERSION}.dmg" ]; then
    mv "$BUILD_DIR/Willpower-${VERSION}.dmg" "$RELEASE_OUTPUT_DIR/"
fi

DMG_PATH="$RELEASE_OUTPUT_DIR/Willpower-${VERSION}.dmg"

log_header "Release Complete!"

log_info "Version: $VERSION"
log_info "Output directory: $RELEASE_OUTPUT_DIR"
log_info ""
log_info "Release artifacts:"
if [ -d "$RELEASE_APP_PATH" ]; then
    APP_SIZE=$(du -sh "$RELEASE_APP_PATH" | cut -f1)
    log_info "  - Willpower.app ($APP_SIZE)"
fi
if [ -f "$DMG_PATH" ]; then
    DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
    log_info "  - Willpower-${VERSION}.dmg ($DMG_SIZE)"
fi

log_info ""
log_info "Next steps:"
log_info "  1. Test the DMG on a clean Mac (without Xcode)"
log_info "  2. Upload to your distribution server"
log_info "  3. Update appcast.xml (if using Sparkle)"
log_info "  4. Create GitHub release (if applicable)"
