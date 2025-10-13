#!/bin/bash
#===============================================================================
# Binary to Word-Format Hex Converter
# Converts RISC-V firmware binary to 32-bit word hex format for simulation
#
# Usage: bin2wordhex.sh <input.bin> <output_words.hex>
#
# Output format: One 32-bit word per line, little-endian
# Example: 05c0006f (corresponds to 'j 5c' instruction at address 0)
#===============================================================================

if [ $# -ne 2 ]; then
    echo "Usage: $0 <input.bin> <output_words.hex>"
    echo "  Converts binary firmware to 32-bit word hex format for testbench"
    exit 1
fi

INPUT="$1"
OUTPUT="$2"

if [ ! -f "$INPUT" ]; then
    echo "Error: Input file '$INPUT' not found"
    exit 1
fi

# Convert binary to 32-bit little-endian words, one per line
# hexdump format:
#   -v          = don't suppress duplicate lines
#   -e '"%08x\n"' = format as 8 hex digits + newline
#   /4          = group into 4-byte (32-bit) words
#   "%08x"      = print as 8-digit hex (zero-padded)
hexdump -v -e '/4 "%08x\n"' "$INPUT" > "$OUTPUT"

WORDS=$(wc -l < "$OUTPUT")
echo "✓ Converted $INPUT to $OUTPUT ($WORDS words)"
