#!/usr/bin/env bash
# test-config-split.sh — Validate Apache config separation into global + account.
#
# Ensures the split configs are correct:
# - Global config contains only ExtFilterDefine (server context)
# - Account config contains only activation directives (no ExtFilterDefine)
# - Both files together cover the same directives as the combined config

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

GLOBAL="$PROJECT_DIR/conf/markdown-for-agents-global.conf"
ACCOUNT="$PROJECT_DIR/conf/markdown-for-agents-account.conf"
COMBINED="$PROJECT_DIR/conf/markdown-for-agents.conf"

ERRORS=0

# --- Test 1: Files exist ---

for f in "$GLOBAL" "$ACCOUNT" "$COMBINED"; do
    if [ ! -f "$f" ]; then
        echo "FAIL: Missing file: $f"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi

# --- Test 2: Global config contains ExtFilterDefine ---

if ! grep -q "ExtFilterDefine" "$GLOBAL"; then
    echo "FAIL: Global config missing ExtFilterDefine"
    ERRORS=$((ERRORS + 1))
fi

# --- Test 3: Global config does NOT contain per-account directives ---

for directive in "SetEnvIf" "AddOutputFilter" "SetOutputFilter" "Header"; do
    if grep -q "^${directive}" "$GLOBAL"; then
        echo "FAIL: Global config should not contain $directive"
        ERRORS=$((ERRORS + 1))
    fi
done

# --- Test 4: Account config does NOT contain ExtFilterDefine ---

if grep -q "ExtFilterDefine" "$ACCOUNT"; then
    echo "FAIL: Account config should not contain ExtFilterDefine"
    ERRORS=$((ERRORS + 1))
fi

# --- Test 5: Account config contains activation directives ---

for directive in "SetEnvIfNoCase" "AddOutputFilter" "SetOutputFilter" "Header"; do
    if ! grep -q "$directive" "$ACCOUNT"; then
        echo "FAIL: Account config missing $directive"
        ERRORS=$((ERRORS + 1))
    fi
done

# --- Test 6: Account config contains version placeholder ---

if ! grep -q "__VERSION__" "$ACCOUNT"; then
    echo "FAIL: Account config missing __VERSION__ placeholder"
    ERRORS=$((ERRORS + 1))
fi

# --- Test 7: Combined config still contains both (backward compat) ---

if ! grep -q "ExtFilterDefine" "$COMBINED"; then
    echo "FAIL: Combined config missing ExtFilterDefine"
    ERRORS=$((ERRORS + 1))
fi

if ! grep -q "SetEnvIfNoCase" "$COMBINED"; then
    echo "FAIL: Combined config missing SetEnvIfNoCase"
    ERRORS=$((ERRORS + 1))
fi

# --- Test 8: Global config uses enableenv=WANTS_MARKDOWN ---

if ! grep -q "enableenv=WANTS_MARKDOWN" "$GLOBAL"; then
    echo "FAIL: Global config missing enableenv=WANTS_MARKDOWN"
    ERRORS=$((ERRORS + 1))
fi

# --- Test 9: Account config uses WANTS_MARKDOWN env ---

if ! grep -q "WANTS_MARKDOWN" "$ACCOUNT"; then
    echo "FAIL: Account config missing WANTS_MARKDOWN env reference"
    ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
exit 0
