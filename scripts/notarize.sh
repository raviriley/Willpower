#!/bin/bash
#
# notarize.sh - Submit the Willpower app to Apple's notarization service
#
# Usage: ./scripts/notarize.sh /path/to/Willpower.app
#
# Prerequisites:
#   - App must be code signed with Developer ID Application certificate
#   - Credentials stored via: xcrun notarytool store-credentials "willpower-notary"
#
# The script will:
#   1. Create a ZIP of the app for upload
#   2. Submit to Apple's notary service
#   3. Wait for completion
#   4. Staple the notarization ticket to the app
#

set -e

# Configuration
NOTARY_PROFILE="willpower-notary"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Validate arguments
APP_PATH="$1"
if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 /path/to/Willpower.app"
    echo ""
    echo "Submits the signed app to Apple's notarization service."
    echo ""
    echo "Prerequisites:"
    echo "  1. App must be code signed (run ./scripts/codesign.sh first)"
    echo "  2. Notary credentials stored in Keychain:"
    echo "     xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "         --key ~/path/to/AuthKey.p8 \\"
    echo "         --key-id YOUR_KEY_ID \\"
    echo "         --issuer YOUR_ISSUER_ID"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    log_error "App not found: $APP_PATH"
    exit 1
fi

# Verify credentials are stored
log_info "Verifying notary credentials..."
if ! xcrun notarytool store-credentials --help >/dev/null 2>&1; then
    log_error "notarytool not available. Ensure Xcode Command Line Tools are installed."
    exit 1
fi

# Verify app is signed
log_info "Verifying app is code signed..."
if ! codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
    log_error "App is not properly signed. Run ./scripts/codesign.sh first."
    exit 1
fi

log_info "=== Notarizing Willpower.app ==="

# Step 1: Create ZIP for upload
ZIP_PATH="${APP_PATH%.app}-notarization.zip"
log_step "Creating ZIP archive for upload..."
log_info "  Output: $ZIP_PATH"

# Remove old zip if exists
rm -f "$ZIP_PATH"

# Create zip preserving resource forks and metadata
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
log_info "  Size: $ZIP_SIZE"

# Step 2: Submit for notarization
log_step "Submitting to Apple notary service..."
log_info "  This may take several minutes..."

SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait 2>&1)

echo "$SUBMIT_OUTPUT"

# Check if notarization succeeded
if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    log_info "Notarization: ACCEPTED"
elif echo "$SUBMIT_OUTPUT" | grep -q "status: Invalid"; then
    log_error "Notarization: REJECTED"
    log_error "Check the log for details:"

    # Extract submission ID and get log
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    if [ -n "$SUBMISSION_ID" ]; then
        log_info "Fetching detailed log..."
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE"
    fi

    rm -f "$ZIP_PATH"
    exit 1
else
    log_warn "Unexpected notarization status. Check output above."
fi

# Step 3: Staple the notarization ticket
log_step "Stapling notarization ticket to app..."
if xcrun stapler staple "$APP_PATH"; then
    log_info "Stapling: SUCCESS"
else
    log_error "Stapling failed"
    rm -f "$ZIP_PATH"
    exit 1
fi

# Step 4: Verify stapling
log_step "Verifying stapled notarization..."
if xcrun stapler validate "$APP_PATH" 2>&1 | grep -q "valid"; then
    log_info "Staple validation: PASSED"
else
    log_warn "Staple validation returned unexpected result"
fi

# Step 5: Final Gatekeeper check
log_step "Final Gatekeeper assessment..."
if spctl --assess --verbose=4 --type execute "$APP_PATH" 2>&1; then
    log_info "Gatekeeper assessment: PASSED"
else
    log_warn "Gatekeeper assessment failed. This is unexpected after notarization."
fi

# Cleanup
rm -f "$ZIP_PATH"

log_info "=== Notarization complete ==="
log_info "The app is now ready for distribution."
log_info "Next step: Run ./scripts/create-dmg.sh $APP_PATH"
