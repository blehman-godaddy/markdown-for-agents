#!/usr/bin/env bash
# test-markdown-response.sh — Verify HTML is converted to Markdown correctly.

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PHP_BIN="${PHP_BIN:-php}"
CONVERTER="$PROJECT_DIR/bin/html2markdown.php"

ERRORS=0

# Test 1: Basic HTML converts to Markdown
input='<h1>Hello</h1><p>World</p>'
output=$(echo "$input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)

if ! echo "$output" | grep -q "# Hello"; then
    echo "FAIL: Expected '# Hello' in output, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

if ! echo "$output" | grep -q "World"; then
    echo "FAIL: Expected 'World' in output, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

# Test 2: Output should not contain common HTML tags
if echo "$output" | grep -qE '<(h[1-6]|p|div|span)[ >]'; then
    echo "FAIL: Output still contains HTML tags: '$output'"
    ERRORS=$((ERRORS + 1))
fi

# Test 3: Nav elements are stripped
input='<html><body><nav>Menu stuff</nav><h1>Title</h1><p>Content here.</p><footer>Footer stuff</footer></body></html>'
output=$(echo "$input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)

if echo "$output" | grep -qi "Menu stuff"; then
    echo "FAIL: Nav content should be stripped, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

if echo "$output" | grep -qi "Footer stuff"; then
    echo "FAIL: Footer content should be stripped, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

if ! echo "$output" | grep -q "# Title"; then
    echo "FAIL: Main content '# Title' missing after stripping, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

if ! echo "$output" | grep -q "Content here."; then
    echo "FAIL: Main content 'Content here.' missing after stripping, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

# Test 4: Links convert to Markdown format
input='<p>Visit <a href="https://example.com">Example</a> for more.</p>'
output=$(echo "$input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)

if ! echo "$output" | grep -q '\[Example\](https://example.com)'; then
    echo "FAIL: Link not converted to Markdown format, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

# Test 5: Bold and italic convert
input='<p>This is <strong>bold</strong> and <em>italic</em>.</p>'
output=$(echo "$input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)

if ! echo "$output" | grep -q '\*\*bold\*\*'; then
    echo "FAIL: Bold not converted, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

if ! echo "$output" | grep -q '\*italic\*'; then
    echo "FAIL: Italic not converted, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

# Test 6: Lists convert properly
input='<ul><li>One</li><li>Two</li><li>Three</li></ul>'
output=$(echo "$input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)

if ! echo "$output" | grep -qF -- '- One'; then
    echo "FAIL: Unordered list not converted, got: '$output'"
    ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
exit 0
