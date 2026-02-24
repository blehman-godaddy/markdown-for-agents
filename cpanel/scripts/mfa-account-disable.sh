#!/usr/bin/env bash
# mfa-account-disable.sh — Disable markdown-for-agents for a cPanel account.
#
# Removes userdata includes for std + ssl, rebuilds httpd config, restarts Apache.
#
# Usage:
#   sudo bash mfa-account-disable.sh <username>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/mfa-common.sh"

# --- Argument check ---

if [ $# -lt 1 ]; then
    error "Usage: mfa-account-disable.sh <username>"
    exit 1
fi

USERNAME="$1"

# --- Root check ---

if [ "$(id -u)" -ne 0 ]; then
    error "Must be run as root (or via sudo)"
    exit 1
fi

# --- Validate username ---

if ! mfa_validate_username "$USERNAME"; then
    error "Invalid username format: $USERNAME"
    error "Username must match: ^[a-z][a-z0-9]{0,15}$"
    exit 1
fi

# --- Check if enabled ---

mfa_userdata_paths "$USERNAME"

if [ ! -f "$MFA_USERDATA_STD" ] && [ ! -f "$MFA_USERDATA_SSL" ]; then
    log "Already disabled for $USERNAME"
    exit 0
fi

# --- Remove userdata includes ---

log "Disabling markdown-for-agents for $USERNAME ..."

REMOVED=0
for conf_path in "$MFA_USERDATA_STD" "$MFA_USERDATA_SSL"; do
    if [ -f "$conf_path" ]; then
        rm -f "$conf_path"
        log "Removed: $conf_path"
        REMOVED=$((REMOVED + 1))
    fi
done

if [ "$REMOVED" -eq 0 ]; then
    log "No configs found for $USERNAME"
    exit 0
fi

# --- Rebuild httpd ---

log "Rebuilding httpd configuration ..."
if mfa_rebuild_httpd; then
    log "httpd rebuilt and restarted."
else
    error "Failed to rebuild httpd. Check Apache configuration."
    exit 1
fi

echo ""
log "=== markdown-for-agents disabled for $USERNAME ==="
