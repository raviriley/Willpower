#!/bin/bash
#
# create-dmg.sh - Create a signed and notarized DMG for distribution
#
# Usage: ./scripts/create-dmg.sh /path/to/Willpower.app [version]
#
# Prerequisites:
#   - brew install create-dmg
#   - App must be notarized (run ./scripts/notarize.sh first)
#
# The script will:
#   1. Create a DMG with Applications symlink
#   2. Sign the DMG with Developer ID
#   3. Notarize the DMG
#   4. Staple the notarization ticket
#

set -e

# Load shared configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/scripts/config.sh"

# Validate arguments
APP_PATH="$1"
VERSION="${2:-}"

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 /path/to/Willpower.app [version]"
    echo ""
    echo "Creates a signed and notarized DMG for distribution."
    echo ""
    echo "Arguments:"
    echo "  app_path    Path to the notarized Willpower.app"
    echo "  version     Optional version string (e.g., 1.0.0)"
    echo "              If not provided, extracted from app's Info.plist"
    echo ""
    echo "Prerequisites:"
    echo "  brew install create-dmg"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    log_error "App not found: $APP_PATH"
    exit 1
fi

# Check for create-dmg
if ! command -v create-dmg &> /dev/null; then
    log_error "create-dmg not found. Install with: brew install create-dmg"
    exit 1
fi

# Get version from app if not provided
if [ -z "$VERSION" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")
    log_info "Detected version: $VERSION"
fi

# Output paths
DMG_NAME="Willpower-${VERSION}.dmg"
DMG_PATH="$PROJECT_DIR/build/$DMG_NAME"
TEMP_DMG_PATH="$PROJECT_DIR/build/Willpower-temp.dmg"

# Create build directory
mkdir -p "$PROJECT_DIR/build"

# Remove old DMG if exists
rm -f "$DMG_PATH" "$TEMP_DMG_PATH"

log_info "=== Creating Distribution DMG ==="
log_info "App: $APP_PATH"
log_info "Version: $VERSION"
log_info "Output: $DMG_PATH"

# Step 1: Create DMG
log_step "Creating DMG with create-dmg..."

# Find app icon (if exists)
ICON_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"
if [ ! -f "$ICON_PATH" ]; then
    # Try alternative icon locations
    ICON_PATH=$(find "$APP_PATH/Contents/Resources" -name "*.icns" -type f | head -1)
fi

# Build create-dmg command
CREATE_DMG_ARGS=(
    --volname "Willpower"
    --window-pos 200 120
    --window-size 600 400
    --icon-size 100
    --icon "Willpower.app" 150 190
    --hide-extension "Willpower.app"
    --app-drop-link 450 185
)

# Add volume icon if available
if [ -n "$ICON_PATH" ] && [ -f "$ICON_PATH" ]; then
    CREATE_DMG_ARGS+=(--volicon "$ICON_PATH")
    log_info "Using volume icon: $ICON_PATH"
fi

# Add background image if exists
BACKGROUND_PATH="$PROJECT_DIR/assets/dmg-background.png"
if [ -f "$BACKGROUND_PATH" ]; then
    CREATE_DMG_ARGS+=(--background "$BACKGROUND_PATH")
    log_info "Using background: $BACKGROUND_PATH"
fi

# Note: We DON'T use --codesign here because we sign separately after
# This gives us more control over the signing process

create-dmg "${CREATE_DMG_ARGS[@]}" "$TEMP_DMG_PATH" "$APP_PATH" || {
    # create-dmg returns non-zero even on success sometimes
    if [ -f "$TEMP_DMG_PATH" ]; then
        log_warn "create-dmg returned non-zero but DMG was created"
    else
        log_error "Failed to create DMG"
        exit 1
    fi
}

# Step 2: Sign the DMG
log_step "Signing DMG with Developer ID..."
codesign --force --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$TEMP_DMG_PATH"

# Verify DMG signature
if codesign --verify "$TEMP_DMG_PATH" 2>&1; then
    log_info "DMG signature: VALID"
else
    log_error "DMG signature verification failed"
    exit 1
fi

# Rename to final name
mv "$TEMP_DMG_PATH" "$DMG_PATH"

# Step 3: Notarize the DMG
log_step "Submitting DMG for notarization..."
log_info "This may take several minutes..."

SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait 2>&1)

echo "$SUBMIT_OUTPUT"

# Check if notarization succeeded
if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    log_info "DMG notarization: ACCEPTED"
elif echo "$SUBMIT_OUTPUT" | grep -q "status: Invalid"; then
    log_error "DMG notarization: REJECTED"

    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    if [ -n "$SUBMISSION_ID" ]; then
        log_info "Fetching detailed log..."
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE"
    fi
    exit 1
fi

# Step 4: Staple the DMG
log_step "Stapling notarization ticket to DMG..."
if xcrun stapler staple "$DMG_PATH"; then
    log_info "DMG stapling: SUCCESS"
else
    log_error "DMG stapling failed"
    exit 1
fi

# Step 5: Verify final DMG
log_step "Verifying final DMG..."
if spctl --assess --verbose=4 --type open --context context:primary-signature "$DMG_PATH" 2>&1; then
    log_info "Gatekeeper assessment: PASSED"
fi

# Get final file size
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

log_info "=== DMG Creation Complete ==="
log_info "Output: $DMG_PATH"
log_info "Size: $DMG_SIZE"
log_info ""
log_info "The DMG is ready for distribution!"
log_info "Users can download, mount, and drag Willpower to Applications."
