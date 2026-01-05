#!/bin/bash
#
# generate-sparkle-keys.sh - Generate EdDSA signing keys for Sparkle updates
#
# Usage: ./scripts/generate-sparkle-keys.sh
#
# This script generates EdDSA (Ed25519) keys used by Sparkle to verify
# that updates are authentically signed by you.
#
# IMPORTANT:
#   - The PRIVATE key must be kept SECRET and secure
#   - The PUBLIC key goes in your app's Info.plist (SUPublicEDKey)
#   - Back up your private key - you cannot regenerate it!
#   - If you lose the private key, existing users cannot update
#

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYS_DIR="$PROJECT_DIR/.sparkle-keys"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Sparkle EdDSA Key Generator${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if keys already exist
if [ -f "$KEYS_DIR/eddsa_private.key" ]; then
    log_warn "Keys already exist in $KEYS_DIR"
    log_warn "To regenerate, delete the .sparkle-keys folder first"
    echo ""
    echo "Existing public key (for Info.plist SUPublicEDKey):"
    echo ""
    cat "$KEYS_DIR/eddsa_public.key"
    echo ""
    exit 0
fi

# Create keys directory
mkdir -p "$KEYS_DIR"

# Method 1: Try using Sparkle's generate_keys if available
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

if [ -n "$SPARKLE_GENERATE_KEYS" ]; then
    log_info "Found Sparkle generate_keys: $SPARKLE_GENERATE_KEYS"
    log_info "Generating keys using Sparkle's tool..."

    # Sparkle's generate_keys outputs to stdout
    # It stores the private key in Keychain and prints the public key
    KEY_OUTPUT=$("$SPARKLE_GENERATE_KEYS" 2>&1)

    # Extract public key from output (handles both new key and existing key messages)
    # Look for the base64 key in <string>...</string> tags
    PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -o '<string>[^<]*</string>' | sed 's/<string>//;s/<\/string>//' | tr -d '[:space:]')

    if [ -n "$PUBLIC_KEY" ]; then
        # Save public key to file for reference
        mkdir -p "$KEYS_DIR"
        echo "$PUBLIC_KEY" > "$KEYS_DIR/eddsa_public.key"

        log_info "Keys generated successfully!"
        log_warn "IMPORTANT: The private key is stored in your macOS Keychain"
        log_warn "  Service: https://sparkle-project.org"
        log_warn "  Account: ed25519"
        echo ""
        log_info "To back up your private key, export your login keychain"
    else
        log_error "Could not extract public key from generate_keys output"
        echo ""
        echo "Output was:"
        echo "$KEY_OUTPUT"
        exit 1
    fi

else
    log_warn "Sparkle's generate_keys not found"
    log_info "Generating keys using OpenSSL..."

    # Generate Ed25519 key pair using OpenSSL
    # Note: This requires OpenSSL 1.1.1+ for Ed25519 support

    if ! openssl version | grep -qE "OpenSSL (1\.1\.[1-9]|[3-9]\.)"; then
        log_warn "OpenSSL 1.1.1+ required for Ed25519. Checking for alternative..."

        # Try LibreSSL (macOS default)
        if openssl genpkey -algorithm ED25519 -out /dev/null 2>/dev/null; then
            log_info "Using system OpenSSL/LibreSSL"
        else
            log_error "Ed25519 not supported by your OpenSSL version"
            log_error ""
            log_error "Options:"
            log_error "  1. Install OpenSSL 3.x: brew install openssl@3"
            log_error "  2. Add Sparkle to Xcode first, then re-run this script"
            log_error "     (Sparkle includes its own generate_keys tool)"
            exit 1
        fi
    fi

    # Generate private key
    openssl genpkey -algorithm ED25519 -out "$KEYS_DIR/eddsa_private.pem"

    # Extract public key in raw format and base64 encode
    openssl pkey -in "$KEYS_DIR/eddsa_private.pem" -pubout -outform DER | \
        tail -c 32 | base64 > "$KEYS_DIR/eddsa_public.key"

    # Also save private key in base64 for Sparkle compatibility
    openssl pkey -in "$KEYS_DIR/eddsa_private.pem" -outform DER | \
        tail -c 64 | base64 > "$KEYS_DIR/eddsa_private.key"

    log_info "Keys generated successfully!"
fi

# Add to .gitignore
GITIGNORE="$PROJECT_DIR/.gitignore"
if [ -f "$GITIGNORE" ]; then
    if ! grep -q ".sparkle-keys" "$GITIGNORE"; then
        echo "" >> "$GITIGNORE"
        echo "# Sparkle signing keys (KEEP PRIVATE!)" >> "$GITIGNORE"
        echo ".sparkle-keys/" >> "$GITIGNORE"
        log_info "Added .sparkle-keys to .gitignore"
    fi
else
    echo "# Sparkle signing keys (KEEP PRIVATE!)" > "$GITIGNORE"
    echo ".sparkle-keys/" >> "$GITIGNORE"
    log_info "Created .gitignore with .sparkle-keys exclusion"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Key Generation Complete${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Public Key (add to Info.plist as SUPublicEDKey):"
echo ""
echo -e "${BLUE}$(cat "$KEYS_DIR/eddsa_public.key")${NC}"
echo ""
echo -e "${YELLOW}CRITICAL: Back up your private key!${NC}"
echo "  Location: $KEYS_DIR/"
echo ""
echo "Next steps:"
echo "  1. Copy the public key above"
echo "  2. Paste it into Willpower/Info.plist as SUPublicEDKey value"
echo "  3. Back up the .sparkle-keys folder to a secure location"
echo "  4. NEVER commit .sparkle-keys to git"
echo ""
