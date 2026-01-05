#!/bin/bash
#
# generate-sparkle-keys.sh - Generate EdDSA signing keys for Sparkle updates
#
# Usage: ./scripts/generate-sparkle-keys.sh
#
# This script uses Sparkle's generate_keys tool to create EdDSA (Ed25519) keys
# for signing app updates. The private key is stored securely in macOS Keychain.
#
# IMPORTANT:
#   - The PRIVATE key is stored in your macOS Keychain
#   - The PUBLIC key goes in your app's Info.plist (SUPublicEDKey)
#   - Back up your Keychain - you cannot regenerate the private key!
#   - If you lose the private key, existing users cannot verify updates
#
# Prerequisites:
#   - Sparkle added to your Xcode project (via SPM or manually)
#   - Build the project once so Sparkle tools are available
#

set -e

# Load shared configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/scripts/config.sh"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Sparkle EdDSA Key Generator${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Find Sparkle's generate_keys tool
SPARKLE_GENERATE_KEYS=""

# Check common locations for Sparkle's generate_keys
POSSIBLE_PATHS=(
    "$HOME/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
    "/usr/local/bin/generate_keys"
    "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
)

for pattern in "${POSSIBLE_PATHS[@]}"; do
    found=$(find $pattern 2>/dev/null | head -1)
    if [ -n "$found" ] && [ -x "$found" ]; then
        SPARKLE_GENERATE_KEYS="$found"
        break
    fi
done

if [ -z "$SPARKLE_GENERATE_KEYS" ]; then
    log_error "Sparkle's generate_keys tool not found"
    echo ""
    echo "This tool is included with Sparkle. To use it:"
    echo ""
    echo "  1. Add Sparkle to your Xcode project:"
    echo "     File → Add Package Dependencies → https://github.com/sparkle-project/Sparkle"
    echo ""
    echo "  2. Build the project once (Cmd+B)"
    echo "     This downloads Sparkle and its tools"
    echo ""
    echo "  3. Run this script again"
    echo ""
    exit 1
fi

log_info "Found Sparkle generate_keys: $SPARKLE_GENERATE_KEYS"
log_info "Generating EdDSA signing key..."

# Sparkle's generate_keys stores the private key in Keychain
# and prints the public key to stdout
KEY_OUTPUT=$("$SPARKLE_GENERATE_KEYS" 2>&1)

# Extract public key from output
# Look for the base64 key in <string>...</string> tags
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -o '<string>[^<]*</string>' | sed 's/<string>//;s/<\/string>//' | tr -d '[:space:]')

if [ -z "$PUBLIC_KEY" ]; then
    log_error "Could not extract public key from generate_keys output"
    echo ""
    echo "Output was:"
    echo "$KEY_OUTPUT"
    exit 1
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Key Generation Complete${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Public Key (add to Info.plist as SUPublicEDKey):"
echo ""
echo -e "${BLUE}$PUBLIC_KEY${NC}"
echo ""
log_warn "IMPORTANT: The private key is stored in your macOS Keychain"
echo "  Service: https://sparkle-project.org"
echo "  Account: ed25519"
echo ""
log_warn "To back up your private key:"
echo "  1. Open Keychain Access"
echo "  2. Find 'Private key for signing Sparkle updates'"
echo "  3. Export it to a secure location"
echo ""
echo "Next steps:"
echo "  1. Copy the public key above"
echo "  2. Paste it into Willpower/Info.plist as SUPublicEDKey value"
echo ""
