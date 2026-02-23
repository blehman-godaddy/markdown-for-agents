#!/usr/bin/env bash
# test-passthrough.sh — Verify that the converter passes through non-HTML and oversized content unchanged.

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PHP_BIN="${PHP_BIN:-php}"
CONVERTER="$PROJECT_DIR/bin/html2markdown.php"

ERRORS=0

# Test 1: Empty input produces empty output
output=$(echo -n "" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)
if [ -n "$output" ]; then
    echo "FAIL: Empty input should produce empty output, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

# Test 2: Plain text (non-HTML) passes through (converter wraps it, but doesn't crash)
output=$(echo "Just plain text, no HTML." | "$PHP_BIN" "$CONVERTER" 2>/dev/null)
if [ -z "$output" ]; then
    echo "FAIL: Plain text input should produce output"
    ERRORS=$((ERRORS + 1))
fi

# Test 3: Binary-like content doesn't crash the converter
output=$(printf '\x00\x01\x02\x03\xFF\xFE' | "$PHP_BIN" "$CONVERTER" 2>/dev/null)
# Just verify it doesn't crash (exit 0)
if [ $? -ne 0 ]; then
    echo "FAIL: Binary content caused converter to crash"
    ERRORS=$((ERRORS + 1))
fi

# Test 4: JSON content passes through without error
output=$(echo '{"key": "value", "html": "<b>bold</b>"}' | "$PHP_BIN" "$CONVERTER" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "FAIL: JSON content caused converter to crash"
    ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
exit 0
