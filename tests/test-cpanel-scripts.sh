#!/usr/bin/env bash
# test-cpanel-scripts.sh — Validate cPanel management scripts.
#
# Tests argument checking, username validation, and JSON output format
# without requiring root or a cPanel server.

set -euo pipefail

PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

ERRORS=0

# --- Test 1: Scripts exist and are executable ---

for script in mfa-global-install.sh mfa-global-uninstall.sh \
              mfa-account-enable.sh mfa-account-disable.sh \
              mfa-account-status.sh; do
    path="$PROJECT_DIR/cpanel/scripts/$script"
    if [ ! -f "$path" ]; then
        echo "FAIL: Missing script: $path"
        ERRORS=$((ERRORS + 1))
    elif [ ! -x "$path" ]; then
        echo "FAIL: Script not executable: $path"
        ERRORS=$((ERRORS + 1))
    fi
done

# --- Test 2: Account scripts require username argument ---

for script in mfa-account-enable.sh mfa-account-disable.sh mfa-account-status.sh; do
    path="$PROJECT_DIR/cpanel/scripts/$script"
    if [ ! -f "$path" ]; then
        continue
    fi

    # Run without arguments — should exit non-zero
    if output=$("$path" 2>&1); then
        echo "FAIL: $script should fail without username argument"
        ERRORS=$((ERRORS + 1))
    fi
done

# --- Test 3: Account status returns JSON ---

STATUS_SCRIPT="$PROJECT_DIR/cpanel/scripts/mfa-account-status.sh"
if [ -f "$STATUS_SCRIPT" ]; then
    # Invalid username should return JSON error
    output=$("$STATUS_SCRIPT" "INVALID-USER!" 2>&1) || true
    if ! echo "$output" | grep -q '"error"'; then
        echo "FAIL: mfa-account-status.sh should return JSON error for invalid username"
        echo "  Got: $output"
        ERRORS=$((ERRORS + 1))
    fi

    # Valid format username (user won't exist on dev machine, but should get JSON)
    output=$("$STATUS_SCRIPT" "testuser" 2>&1) || true
    if ! echo "$output" | grep -q '"username"'; then
        echo "FAIL: mfa-account-status.sh should return JSON with username field"
        echo "  Got: $output"
        ERRORS=$((ERRORS + 1))
    fi

    # Verify JSON has expected fields
    if ! echo "$output" | grep -q '"enabled"'; then
        echo "FAIL: mfa-account-status.sh JSON missing 'enabled' field"
        ERRORS=$((ERRORS + 1))
    fi
    if ! echo "$output" | grep -q '"global_installed"'; then
        echo "FAIL: mfa-account-status.sh JSON missing 'global_installed' field"
        ERRORS=$((ERRORS + 1))
    fi
fi

# --- Test 4: mfa-common.sh is sourceable ---

if [ -f "$PROJECT_DIR/lib/mfa-common.sh" ]; then
    # Source in a subshell to avoid polluting current env
    if ! (source "$PROJECT_DIR/lib/mfa-common.sh" 2>/dev/null); then
        echo "FAIL: lib/mfa-common.sh cannot be sourced"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "FAIL: lib/mfa-common.sh not found"
    ERRORS=$((ERRORS + 1))
fi

# --- Test 5: Username validation (via mfa-common.sh) ---

(
    source "$PROJECT_DIR/lib/mfa-common.sh" 2>/dev/null

    # Valid usernames
    for u in "testuser" "a" "user1234" "ab" "abcdefghijklmnop"; do
        if ! mfa_validate_username "$u"; then
            echo "FAIL: mfa_validate_username should accept '$u'"
            exit 1
        fi
    done

    # Invalid usernames
    for u in "" "1user" "User" "user-name" "user_name" "user.name" \
             "abcdefghijklmnopq" "root" "A" ".hidden"; do
        if mfa_validate_username "$u" 2>/dev/null; then
            # "root" is actually valid format (lowercase + <=16 chars), skip
            if [[ "$u" =~ ^[a-z][a-z0-9]{0,15}$ ]]; then
                continue
            fi
            echo "FAIL: mfa_validate_username should reject '$u'"
            exit 1
        fi
    done
) || ERRORS=$((ERRORS + 1))

# --- Test 6: Config files referenced by scripts exist ---

if [ ! -f "$PROJECT_DIR/conf/markdown-for-agents-global.conf" ]; then
    echo "FAIL: Missing conf/markdown-for-agents-global.conf"
    ERRORS=$((ERRORS + 1))
fi

if [ ! -f "$PROJECT_DIR/conf/markdown-for-agents-account.conf" ]; then
    echo "FAIL: Missing conf/markdown-for-agents-account.conf"
    ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
exit 0
