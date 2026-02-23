#!/usr/bin/env bash
# test-content-quality.sh — Compare converter output against expected fixture files.

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PHP_BIN="${PHP_BIN:-php}"
CONVERTER="$PROJECT_DIR/bin/html2markdown.php"
FIXTURES_DIR="$PROJECT_DIR/tests/fixtures"
EXPECTED_DIR="$FIXTURES_DIR/expected"

ERRORS=0

test_fixture() {
    local name="$1"
    local input_file="$FIXTURES_DIR/${name}.html"
    local expected_file="$EXPECTED_DIR/${name}.md"

    if [ ! -f "$input_file" ]; then
        echo "SKIP: Input fixture not found: $input_file"
        return
    fi

    if [ ! -f "$expected_file" ]; then
        echo "SKIP: Expected fixture not found: $expected_file"
        return
    fi

    local actual
    actual=$("$PHP_BIN" "$CONVERTER" < "$input_file" 2>/dev/null)

    local expected
    expected=$(cat "$expected_file")

    if [ "$actual" != "$expected" ]; then
        echo "FAIL: Fixture '$name' output differs from expected"
        echo "--- diff (expected vs actual) ---"
        diff <(echo "$expected") <(echo "$actual") || true
        echo "--- end diff ---"
        ERRORS=$((ERRORS + 1))
    fi
}

# Test each fixture
test_fixture "simple"
test_fixture "wordpress-post"
test_fixture "complex-layout"

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
exit 0
