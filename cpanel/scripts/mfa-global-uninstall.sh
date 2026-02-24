#!/usr/bin/env bash
# mfa-global-uninstall.sh — Remove markdown-for-agents global infrastructure.
#
# Removes all userdata includes for all accounts, then removes the global
# config, module loader, and install directory.
#
# Usage:
#   sudo bash mfa-global-uninstall.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/mfa-common.sh"

# --- Root check ---

if [ "$(id -u)" -ne 0 ]; then
    error "Must be run as root (or via sudo)"
    exit 1
fi

log "Removing markdown-for-agents global infrastructure ..."

# --- Remove all per-account userdata includes ---

ACCOUNTS_REMOVED=0
USERDATA_BASE="/etc/apache2/conf.d/userdata"

for proto in std ssl; do
    dir="$USERDATA_BASE/$proto/2_4"
    if [ -d "$dir" ]; then
        for user_dir in "$dir"/*/; do
            conf="$user_dir/markdown-for-agents.conf"
            if [ -f "$conf" ]; then
                rm -f "$conf"
                username="$(basename "$user_dir")"
                log "Removed account config: $username ($proto)"
                ACCOUNTS_REMOVED=$((ACCOUNTS_REMOVED + 1))
            fi
        done
    fi
done

if [ "$ACCOUNTS_REMOVED" -gt 0 ]; then
    log "Removed $ACCOUNTS_REMOVED account config(s)."
fi

# --- Remove Apache configs ---

CONFIGS_REMOVED=0

remove_if_exists() {
    if [ -f "$1" ]; then
        rm -f "$1"
        log "Removed: $1"
        CONFIGS_REMOVED=$((CONFIGS_REMOVED + 1))
    fi
}

# EA4 / cPanel
remove_if_exists "/etc/apache2/conf.d/markdown-for-agents.conf"
remove_if_exists "/etc/apache2/conf.modules.d/850-markdown-for-agents.conf"

# RHEL / CentOS
remove_if_exists "/etc/httpd/conf.d/markdown-for-agents.conf"
remove_if_exists "/etc/httpd/conf.modules.d/850-markdown-for-agents.conf"

# Debian / Ubuntu
remove_if_exists "/etc/apache2/conf-available/markdown-for-agents.conf"
remove_if_exists "/etc/apache2/conf-enabled/markdown-for-agents.conf"
remove_if_exists "/etc/apache2/mods-available/850-markdown-for-agents.conf"

# --- Remove install directory ---

if [ -d "$MFA_INSTALL_DIR" ]; then
    rm -rf "$MFA_INSTALL_DIR"
    log "Removed: $MFA_INSTALL_DIR"
fi

# --- Remove sudoers ---

remove_if_exists "/etc/sudoers.d/markdown-for-agents"

# --- Reload Apache ---

if mfa_detect_apache; then
    if mfa_configtest; then
        mfa_reload_apache
        log "Apache reloaded."
    else
        error "Apache config test failed after removal. Check your Apache configuration."
    fi
else
    log "Apache not detected — skipping reload."
fi

# --- Rebuild httpd if cPanel ---

if [ "$ACCOUNTS_REMOVED" -gt 0 ] && [ -x "/usr/local/cpanel/scripts/rebuildhttpdconf" ]; then
    log "Rebuilding httpd configuration ..."
    mfa_rebuild_httpd
    log "httpd rebuilt."
fi

echo ""
log "=== markdown-for-agents global infrastructure removed ==="
