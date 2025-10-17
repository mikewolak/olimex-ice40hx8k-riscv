#!/bin/bash
# Fetch PicoRV32 from GitHub

set -e

if [ ! -f .config ]; then
    echo "ERROR: .config not found"
    exit 1
fi

source .config

DOWNLOADS_DIR="downloads"
PICORV32_DIR="$DOWNLOADS_DIR/picorv32"

REPO_URL="${CONFIG_PICORV32_REPO:-https://github.com/YosysHQ/picorv32.git}"
COMMIT="${CONFIG_PICORV32_COMMIT:-master}"

echo "========================================="
echo "Fetching PicoRV32"
echo "========================================="
echo "Repository: $REPO_URL"
echo "Version:    $COMMIT"
echo ""

mkdir -p "$DOWNLOADS_DIR"

if [ ! -d "$PICORV32_DIR/.git" ]; then
    echo "Cloning PicoRV32..."
    git clone "$REPO_URL" "$PICORV32_DIR"
fi

cd "$PICORV32_DIR"
echo "Updating repository..."
git fetch --all --tags

echo "Checking out: $COMMIT"
git checkout -f "$COMMIT"

CURRENT_COMMIT=$(git rev-parse HEAD)
CURRENT_DATE=$(git log -1 --format=%ci HEAD)

echo ""
echo "PicoRV32 Version Info:"
echo "  Commit: $CURRENT_COMMIT"
echo "  Date:   $CURRENT_DATE"

# Check if this is a tagged release
TAG=$(git describe --exact-match --tags HEAD 2>/dev/null || echo "")
if [ -n "$TAG" ]; then
    echo "  Tag:    $TAG"
fi

echo ""
echo "✓ PicoRV32 ready at downloads/picorv32/picorv32.v"
