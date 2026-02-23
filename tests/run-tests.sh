#!/usr/bin/env bash
# run-tests.sh — Test orchestrator for markdown-for-agents.
#
# Runs all test scripts and reports results.
# Exit code 0 = all pass, 1 = any failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

run_test() {
    local test_file="$1"
    local test_name
    test_name="$(basename "$test_file" .sh)"

    if [ ! -x "$test_file" ]; then
        chmod +x "$test_file"
    fi

    echo -n "  ${test_name} ... "

    local output
    if output=$("$test_file" "$PROJECT_DIR" 2>&1); then
        echo -e "${GREEN}PASS${NC}"
        PASS=$((PASS + 1))
    else
        local exit_code=$?
        if [ "$exit_code" -eq 2 ]; then
            echo -e "${YELLOW}SKIP${NC}"
            SKIP=$((SKIP + 1))
            [ -n "$output" ] && echo "    $output"
        else
            echo -e "${RED}FAIL${NC}"
            FAIL=$((FAIL + 1))
            [ -n "$output" ] && echo "    $output"
        fi
    fi
}

echo "========================================"
echo " markdown-for-agents test suite"
echo "========================================"
echo ""

# Standalone converter tests (no Apache required)
echo "Standalone converter tests:"
for test_file in "$SCRIPT_DIR"/test-*.sh; do
    [ -f "$test_file" ] && run_test "$test_file"
done

echo ""
echo "========================================"
echo -e " Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC}"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
