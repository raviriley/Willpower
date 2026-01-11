#!/bin/bash
#
# github-release.sh - Create a GitHub Release with DMG and appcast
#
# Usage: ./scripts/github-release.sh <version>
#
# This script:
#   1. Runs the full release build (sign, notarize, DMG)
#   2. Generates appcast.xml for Sparkle updates
#   3. Creates a GitHub Release with all assets
#
# Prerequisites:
#   - gh CLI installed and authenticated: brew install gh && gh auth login
#   - Release scripts working (codesign.sh, notarize.sh, etc.)
#

set -e

# Load shared configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/scripts/config.sh"

VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo ""
    echo "Creates a GitHub Release with signed, notarized DMG and appcast."
    echo ""
    echo "Example: $0 1.0.0"
    echo ""
    echo "Prerequisites:"
    echo "  - gh CLI: brew install gh && gh auth login"
    exit 1
fi

# Check gh CLI
if ! command -v gh &>/dev/null; then
    log_error "gh CLI not found. Install with: brew install gh"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    log_error "gh CLI not authenticated. Run: gh auth login"
    exit 1
fi

log_header "GitHub Release: v$VERSION"

# Step 1: Build release
log_step "Building release..."
"$SCRIPTS_DIR/release.sh" "$VERSION"

# Commit version changes made by release.sh
log_step "Committing version changes..."
git add "$PROJECT_DIR/Willpower.xcodeproj/project.pbxproj"
git commit -m "Bump version to $VERSION"
git push origin main

# Paths
RELEASE_DIR="$RELEASES_DIR/$VERSION"
DMG_PATH="$RELEASE_DIR/Willpower-${VERSION}.dmg"
APPCAST_DIR="$BUILD_DIR/appcast"

if [ ! -f "$DMG_PATH" ]; then
    log_error "DMG not found: $DMG_PATH"
    exit 1
fi

# Step 2: Generate appcast
log_step "Generating appcast.xml..."

# Set download URL prefix for GitHub Releases
export SPARKLE_DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/"

"$SCRIPTS_DIR/generate-appcast.sh" || {
    log_warn "Appcast generation had issues, creating manually..."
}

# If appcast wasn't generated, create a basic one
APPCAST_PATH="$APPCAST_DIR/appcast.xml"
if [ ! -f "$APPCAST_PATH" ]; then
    log_info "Creating appcast.xml manually..."
    mkdir -p "$APPCAST_DIR"

    # Get DMG info
    DMG_SIZE=$(stat -f%z "$DMG_PATH")
    DMG_DATE=$(date -R)

    # Sign the DMG for Sparkle (get EdDSA signature)
    SPARKLE_SIGN=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -type f 2>/dev/null | head -1)
    SIGNATURE=""
    if [ -n "$SPARKLE_SIGN" ] && [ -x "$SPARKLE_SIGN" ]; then
        SIGNATURE=$("$SPARKLE_SIGN" "$DMG_PATH" 2>/dev/null | grep "sparkle:edSignature" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')
    fi

    cat > "$APPCAST_PATH" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Willpower Updates</title>
    <description>Most recent updates to Willpower</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$DMG_DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>What's New in $VERSION</h2>
        <ul>
          <li>See release notes on GitHub</li>
        </ul>
      ]]></description>
      <enclosure url="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/Willpower-$VERSION.dmg"
                 type="application/octet-stream"
                 length="$DMG_SIZE"
                 sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
EOF
    log_info "Created basic appcast.xml"
fi

# Step 3: Create GitHub Release
log_step "Creating GitHub Release v$VERSION..."

# Create release notes
RELEASE_NOTES=$(cat << EOF
## Willpower v$VERSION

### Installation
1. Download \`Willpower-$VERSION.dmg\`
2. Open the DMG
3. Drag Willpower to Applications
4. Launch and follow the setup wizard

### Requirements
- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

### Checksums
\`\`\`
$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')  Willpower-$VERSION.dmg
\`\`\`
EOF
)

# Check if release already exists
if gh release view "v$VERSION" --repo "$GITHUB_REPO" &>/dev/null; then
    log_warn "Release v$VERSION already exists"
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        gh release delete "v$VERSION" --repo "$GITHUB_REPO" --yes
    else
        log_error "Aborted"
        exit 1
    fi
fi

# Create release
gh release create "v$VERSION" \
    --repo "$GITHUB_REPO" \
    --title "Willpower v$VERSION" \
    --notes "$RELEASE_NOTES" \
    "$DMG_PATH" \
    "$APPCAST_PATH"

log_header "Release Complete!"

log_info "GitHub Release: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
log_info ""
log_info "Downloads:"
log_info "  DMG: https://github.com/$GITHUB_REPO/releases/download/v$VERSION/Willpower-$VERSION.dmg"
log_info "  Appcast: https://github.com/$GITHUB_REPO/releases/download/v$VERSION/appcast.xml"
log_info ""
log_info "Users with existing installations will be notified of the update!"

# Sync the release tag locally
git fetch --tags
log_info "Tag v$VERSION synced locally"
