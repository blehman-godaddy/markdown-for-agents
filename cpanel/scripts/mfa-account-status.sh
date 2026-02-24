#!/usr/bin/env bash
# mfa-account-status.sh — Check markdown-for-agents status for a cPanel account.
#
# Returns JSON with enable status, global install status, and version info.
#
# Usage:
#   mfa-account-status.sh <username>
#
# Output (JSON):
#   {"username":"testuser","enabled":true,"global_installed":true,"version":"0.1.7"}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/mfa-common.sh"

# --- Argument check ---

if [ $# -lt 1 ]; then
    echo '{"error":"Usage: mfa-account-status.sh <username>"}'
    exit 1
fi

USERNAME="$1"

# --- Validate username ---

if ! mfa_validate_username "$USERNAME"; then
    echo "{\"error\":\"Invalid username format: $USERNAME\"}"
    exit 1
fi

# --- Check global install ---

GLOBAL_INSTALLED=false
GLOBAL_VERSION=""

if [ -f "$MFA_INSTALL_DIR/.installed" ]; then
    GLOBAL_INSTALLED=true
    GLOBAL_VERSION="$(cat "$MFA_INSTALL_DIR/.installed" 2>/dev/null || echo "")"
fi

# --- Check account status ---

mfa_userdata_paths "$USERNAME"

ENABLED=false
if [ -f "$MFA_USERDATA_STD" ] && [ -f "$MFA_USERDATA_SSL" ]; then
    ENABLED=true
elif [ -f "$MFA_USERDATA_STD" ] || [ -f "$MFA_USERDATA_SSL" ]; then
    # Partial — one of std/ssl is missing
    ENABLED=false
fi

# --- Check user exists ---

USER_EXISTS=false
if mfa_user_exists "$USERNAME"; then
    USER_EXISTS=true
fi

# --- Output JSON ---

cat <<EOF
{"username":"$USERNAME","enabled":$ENABLED,"user_exists":$USER_EXISTS,"global_installed":$GLOBAL_INSTALLED,"version":"$GLOBAL_VERSION"}
EOF
