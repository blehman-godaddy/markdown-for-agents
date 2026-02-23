#!/usr/bin/env bash
# test-headers.sh — Verify token metadata is embedded in converter output.
#
# Note: Full HTTP header tests (Content-Type, Vary, x-markdown-converter) require
# a running Apache instance. This test validates the converter's metadata output.

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PHP_BIN="${PHP_BIN:-php}"
CONVERTER="$PROJECT_DIR/bin/html2markdown.php"

ERRORS=0

# Test 1: Token metadata comment is present
input='<h1>Hello</h1><p>World</p>'
output=$(echo "$input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)

if ! echo "$output" | grep -qE '<!-- mfa-meta:tokens=[0-9]+ html-tokens=[0-9]+ reduction=[0-9]+% -->'; then
    echo "FAIL: Token metadata comment missing from output"
    echo "Output: $output"
    ERRORS=$((ERRORS + 1))
fi

# Test 2: Token count is a positive integer
token_line=$(echo "$output" | grep -oE 'mfa-meta:tokens=[0-9]+' | head -1)
if [ -z "$token_line" ]; then
    echo "FAIL: Could not extract token count"
    ERRORS=$((ERRORS + 1))
else
    token_count=$(echo "$token_line" | grep -oE '[0-9]+' | head -1)
    if [ "$token_count" -le 0 ]; then
        echo "FAIL: Token count should be positive, got: $token_count"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Test 3: Token metadata is on the last line
last_line=$(echo "$output" | tail -1)
if ! echo "$last_line" | grep -qE '<!-- mfa-meta:tokens=[0-9]+ html-tokens=[0-9]+ reduction=[0-9]+% -->'; then
    # Allow empty trailing line — check second-to-last
    second_last=$(echo "$output" | sed -n 'x;$p')
    if ! echo "$second_last" | grep -qE '<!-- mfa-meta:tokens=[0-9]+ html-tokens=[0-9]+ reduction=[0-9]+% -->'; then
        echo "FAIL: Token metadata should be near the end of output"
        echo "Last line: '$last_line'"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Test 4: Larger content produces larger token count
small_input='<p>Hi</p>'
large_input='<p>This is a much longer paragraph that contains significantly more content than the small input so the token count should be higher.</p>'

small_output=$(echo "$small_input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)
large_output=$(echo "$large_input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)

small_tokens=$(echo "$small_output" | grep -oE 'mfa-meta:tokens=[0-9]+' | head -1 | grep -oE '[0-9]+')
large_tokens=$(echo "$large_output" | grep -oE 'mfa-meta:tokens=[0-9]+' | head -1 | grep -oE '[0-9]+')

if [ -n "$small_tokens" ] && [ -n "$large_tokens" ]; then
    if [ "$large_tokens" -le "$small_tokens" ]; then
        echo "FAIL: Larger content should have more tokens. small=$small_tokens, large=$large_tokens"
        ERRORS=$((ERRORS + 1))
    fi
fi

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
exit 0
