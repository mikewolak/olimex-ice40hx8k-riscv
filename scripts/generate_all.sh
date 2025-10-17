#!/bin/bash
# Generate all platform files from .config

set -e

echo "========================================="
echo "Generating platform files from .config"
echo "========================================="

./scripts/gen_start.sh
./scripts/gen_linker.sh
./scripts/gen_platform_h.sh
./scripts/gen_config_vh.sh

echo ""
echo "✓ All platform files generated"
echo ""
echo "Generated files:"
echo "  build/generated/start.S"
echo "  build/generated/linker.ld"
echo "  build/generated/platform.h"
echo "  build/generated/config.vh"
