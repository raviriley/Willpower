#!/bin/bash
#
# codesign.sh - Sign the Willpower app bundle for Developer ID distribution
#
# Usage: ./scripts/codesign.sh /path/to/Willpower.app
#
# This script signs all components inside-out as required by Apple.
# Never use --deep flag as it can mess up XPC services and nested components.
#

set -e

# Configuration
SIGNING_IDENTITY="Developer ID Application: Ravi Riley (NJ2SQLUU4U)"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS_APP="$PROJECT_DIR/Willpower/Willpower.entitlements"
ENTITLEMENTS_DAEMON="$PROJECT_DIR/WillpowerDaemon/WillpowerDaemon.entitlements"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Validate arguments
APP_PATH="$1"
if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 /path/to/Willpower.app"
    echo ""
    echo "Signs the Willpower app bundle for Developer ID distribution."
    echo "The app must be built in Release configuration before signing."
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    log_error "App not found: $APP_PATH"
    exit 1
fi

# Verify signing identity exists
if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    log_error "Signing identity not found: $SIGNING_IDENTITY"
    log_error "Run 'security find-identity -v -p codesigning' to see available identities"
    exit 1
fi

log_info "=== Signing Willpower.app ==="
log_info "App path: $APP_PATH"
log_info "Identity: $SIGNING_IDENTITY"

# Step 1: Sign the daemon binary FIRST (inside-out signing)
DAEMON_PATH="$APP_PATH/Contents/MacOS/WillpowerDaemon"
if [ -f "$DAEMON_PATH" ]; then
    log_info "Signing daemon: $DAEMON_PATH"
    codesign --force --timestamp --options runtime \
        --sign "$SIGNING_IDENTITY" \
        --entitlements "$ENTITLEMENTS_DAEMON" \
        "$DAEMON_PATH"
else
    log_warn "Daemon binary not found at expected path: $DAEMON_PATH"
    log_warn "Checking alternative locations..."

    # Check if daemon is in Resources
    ALT_DAEMON_PATH="$APP_PATH/Contents/Resources/WillpowerDaemon"
    if [ -f "$ALT_DAEMON_PATH" ]; then
        log_info "Found daemon at: $ALT_DAEMON_PATH"
        codesign --force --timestamp --options runtime \
            --sign "$SIGNING_IDENTITY" \
            --entitlements "$ENTITLEMENTS_DAEMON" \
            "$ALT_DAEMON_PATH"
    fi
fi

# Step 2: Sign any frameworks (if present)
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
    log_info "Signing frameworks..."

    # Sign dylibs first
    find "$APP_PATH/Contents/Frameworks" -name "*.dylib" -type f 2>/dev/null | while read dylib; do
        log_info "  Signing: $(basename "$dylib")"
        codesign --force --timestamp --options runtime \
            --sign "$SIGNING_IDENTITY" \
            "$dylib"
    done

    # Sign frameworks
    find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d 2>/dev/null | while read framework; do
        log_info "  Signing: $(basename "$framework")"
        codesign --force --timestamp --options runtime \
            --sign "$SIGNING_IDENTITY" \
            "$framework"
    done
fi

# Step 3: Sign any XPC services (if present)
if [ -d "$APP_PATH/Contents/XPCServices" ]; then
    log_info "Signing XPC services..."
    find "$APP_PATH/Contents/XPCServices" -name "*.xpc" -type d | while read xpc; do
        log_info "  Signing: $(basename "$xpc")"
        codesign --force --timestamp --options runtime \
            --sign "$SIGNING_IDENTITY" \
            "$xpc"
    done
fi

# Step 4: Sign the main app bundle LAST
log_info "Signing main app bundle..."
codesign --force --timestamp --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS_APP" \
    "$APP_PATH"

# Step 5: Verify the signature
log_info "Verifying signature..."
if codesign --verify --deep --strict "$APP_PATH" 2>&1; then
    log_info "Signature verification: PASSED"
else
    log_error "Signature verification: FAILED"
    exit 1
fi

# Step 6: Verify with spctl (Gatekeeper assessment)
log_info "Checking Gatekeeper assessment..."
if spctl --assess --verbose=4 --type execute "$APP_PATH" 2>&1; then
    log_info "Gatekeeper assessment: PASSED"
else
    log_warn "Gatekeeper assessment failed (expected before notarization)"
fi

log_info "=== Code signing complete ==="
log_info "Next step: Run ./scripts/notarize.sh $APP_PATH"
