#!/bin/bash
# Compare different Yosys builds
# Usage: ./compare_builds.sh <json_file>

JSON_FILE=${1:-build/ice40_picorv32.json}

if [ ! -f "$JSON_FILE" ]; then
    echo "Error: $JSON_FILE not found"
    exit 1
fi

echo "========================================="
echo "Build Analysis: $JSON_FILE"
echo "========================================="
echo ""

# Yosys version
echo "Yosys Version:"
head -2 "$JSON_FILE" | grep creator | cut -d'"' -f4
echo ""

# File size
echo "JSON Size:"
ls -lh "$JSON_FILE" | awk '{print $5}'
echo ""

# Cell count
CELL_COUNT=$(grep -c '"type"' "$JSON_FILE")
echo "Cell Count: $CELL_COUNT"
echo ""

# Key cell types
echo "Cell Type Breakdown:"
echo "  SB_LUT4:  $(grep '"type": "SB_LUT4"' "$JSON_FILE" | wc -l)"
echo "  SB_DFF:   $(grep '"type": "SB_DFF' "$JSON_FILE" | wc -l)"
echo "  SB_CARRY: $(grep '"type": "SB_CARRY"' "$JSON_FILE" | wc -l)"
echo "  SB_RAM:   $(grep '"type": "SB_RAM' "$JSON_FILE" | wc -l)"
echo ""

# Expected vs actual
echo "Comparison to Working Build:"
WORKING_CELLS=9613
DIFF=$((CELL_COUNT - WORKING_CELLS))
if [ $DIFF -eq 0 ]; then
    echo "  ✓ MATCH: $CELL_COUNT cells (same as working build)"
elif [ $DIFF -gt 0 ]; then
    echo "  ⚠ MORE: $CELL_COUNT cells (+$DIFF from working)"
else
    echo "  ✗ LESS: $CELL_COUNT cells ($DIFF from working) - LIKELY BROKEN"
fi
echo ""
