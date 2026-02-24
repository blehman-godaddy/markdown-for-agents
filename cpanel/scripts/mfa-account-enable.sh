#!/usr/bin/env bash
# mfa-account-enable.sh — Enable markdown-for-agents for a cPanel account.
#
# Writes userdata includes for std + ssl, rebuilds httpd config, restarts Apache.
#
# Usage:
#   sudo bash mfa-account-enable.sh <username>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/mfa-common.sh"

# --- Argument check ---

if [ $# -lt 1 ]; then
    error "Usage: mfa-account-enable.sh <username>"
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

if ! mfa_user_exists "$USERNAME"; then
    error "cPanel user does not exist: $USERNAME"
    error "No directory at /var/cpanel/userdata/$USERNAME"
    exit 1
fi

# --- Check global install ---

if [ ! -f "$MFA_INSTALL_DIR/.installed" ]; then
    error "Global infrastructure not installed."
    error "Run mfa-global-install.sh first."
    exit 1
fi

# --- Check if already enabled ---

mfa_userdata_paths "$USERNAME"

if [ -f "$MFA_USERDATA_STD" ] && [ -f "$MFA_USERDATA_SSL" ]; then
    log "Already enabled for $USERNAME"
    exit 0
fi

# --- Read version ---

mfa_read_version "$PROJECT_DIR"

# --- Write userdata includes ---

ACCOUNT_TEMPLATE="$MFA_INSTALL_DIR/conf/markdown-for-agents-account.conf"

if [ ! -f "$ACCOUNT_TEMPLATE" ]; then
    # Fall back to project conf
    ACCOUNT_TEMPLATE="$PROJECT_DIR/conf/markdown-for-agents-account.conf"
fi

log "Enabling markdown-for-agents for $USERNAME ..."

for conf_path in "$MFA_USERDATA_STD" "$MFA_USERDATA_SSL"; do
    mkdir -p "$(dirname "$conf_path")"
    # Copy template and replace version placeholder
    sed "s|__VERSION__|${MFA_VERSION}|g" "$ACCOUNT_TEMPLATE" > "$conf_path"
    chmod 644 "$conf_path"
    log "Wrote: $conf_path"
done

# --- Rebuild httpd ---

log "Rebuilding httpd configuration ..."
if mfa_rebuild_httpd; then
    log "httpd rebuilt and restarted."
else
    error "Failed to rebuild httpd. Removing account configs ..."
    rm -f "$MFA_USERDATA_STD" "$MFA_USERDATA_SSL"
    error "Account configs removed. Check Apache configuration."
    exit 1
fi

echo ""
log "=== markdown-for-agents enabled for $USERNAME ==="
log "Test with:"
log "  curl -s -H 'Accept: text/markdown' http://<domain>/"
