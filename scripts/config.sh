#!/bin/bash
#
# config.sh - Shared configuration for Willpower release scripts
#
# This file is sourced by other scripts. Do not run directly.
#

# === Release Configuration ===
# Update these values for your project

SIGNING_IDENTITY="Developer ID Application: Ravi Riley (NJ2SQLUU4U)"
NOTARY_PROFILE="willpower-notary"
GITHUB_REPO="raviriley/Willpower"

# === Derived paths ===
# These are computed relative to the script that sources this file

if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
SCRIPTS_DIR="$PROJECT_DIR/scripts"
BUILD_DIR="$PROJECT_DIR/build"
RELEASES_DIR="$PROJECT_DIR/releases"

# === Colors for output ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# === Logging functions ===
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

log_header() {
    echo ""
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  $1${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
    echo ""
}
