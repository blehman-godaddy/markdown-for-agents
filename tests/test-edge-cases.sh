#!/usr/bin/env bash
# test-edge-cases.sh — Test edge cases: empty, binary, malformed, oversized.

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PHP_BIN="${PHP_BIN:-php}"
CONVERTER="$PROJECT_DIR/bin/html2markdown.php"
FIXTURES_DIR="$PROJECT_DIR/tests/fixtures"

ERRORS=0

# Test 1: Empty body HTML
input='<html><body></body></html>'
output=$(echo "$input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)
# Should not crash; empty or minimal output is fine
if [ $? -ne 0 ]; then
    echo "FAIL: Empty body HTML caused converter to crash"
    ERRORS=$((ERRORS + 1))
fi

# Test 2: Malformed HTML fixture doesn't crash
output=$("$PHP_BIN" "$CONVERTER" < "$FIXTURES_DIR/malformed.html" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "FAIL: Malformed HTML caused converter to crash"
    ERRORS=$((ERRORS + 1))
fi

# Malformed HTML should still produce some content
if [ -z "$output" ]; then
    echo "FAIL: Malformed HTML produced no output at all"
    ERRORS=$((ERRORS + 1))
fi

# Test 3: HTML with only stripped elements returns something (doesn't crash)
input='<html><body><nav>Nav only</nav><footer>Footer only</footer></body></html>'
output=$(echo "$input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "FAIL: All-stripped-elements HTML caused converter to crash"
    ERRORS=$((ERRORS + 1))
fi

# Test 4: Very large repeated HTML doesn't crash (under 10MB limit)
large_input="<html><body>"
for i in $(seq 1 500); do
    large_input+="<p>Paragraph number $i with some content.</p>"
done
large_input+="</body></html>"

output=$(echo "$large_input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "FAIL: Large HTML (under 10MB) caused converter to crash"
    ERRORS=$((ERRORS + 1))
fi

# Verify it produced markdown (has paragraph text)
if ! echo "$output" | grep -q "Paragraph number 1"; then
    echo "FAIL: Large HTML content not preserved in output"
    ERRORS=$((ERRORS + 1))
fi

# Test 5: ARIA roles are stripped
input='<html><body><div role="navigation">Skip this</div><div role="banner">Skip banner</div><p>Keep this</p><div role="contentinfo">Skip info</div></body></html>'
output=$(echo "$input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)

if echo "$output" | grep -qi "Skip this"; then
    echo "FAIL: role=navigation content should be stripped"
    ERRORS=$((ERRORS + 1))
fi

if echo "$output" | grep -qi "Skip banner"; then
    echo "FAIL: role=banner content should be stripped"
    ERRORS=$((ERRORS + 1))
fi

if ! echo "$output" | grep -q "Keep this"; then
    echo "FAIL: Non-role content should be preserved"
    ERRORS=$((ERRORS + 1))
fi

# Test 6: Class-based stripping
input='<html><body><div class="sidebar-widget">Skip sidebar</div><div class="advertisement">Skip ad</div><div class="main-content"><p>Keep content</p></div></body></html>'
output=$(echo "$input" | "$PHP_BIN" "$CONVERTER" 2>/dev/null)

if echo "$output" | grep -qi "Skip sidebar"; then
    echo "FAIL: sidebar class content should be stripped"
    ERRORS=$((ERRORS + 1))
fi

if echo "$output" | grep -qi "Skip ad"; then
    echo "FAIL: advertisement class content should be stripped"
    ERRORS=$((ERRORS + 1))
fi

if ! echo "$output" | grep -q "Keep content"; then
    echo "FAIL: Main content should be preserved"
    ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
exit 0
