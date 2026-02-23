#!/usr/bin/env bash
# uninstall.sh — Remove markdown-for-agents from the system.
#
# Must be run as root. Removes /opt/markdown-for-agents and Apache configs.

set -euo pipefail

INSTALL_DIR="/opt/markdown-for-agents"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log()   { echo -e "${GREEN}[mfa]${NC} $*"; }
error() { echo -e "${RED}[mfa]${NC} $*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (or via sudo)."
    exit 1
fi

# --- Detect Apache config paths ---

APACHECTL=""
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

if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    log "Removed: $INSTALL_DIR"
fi

# --- Reload Apache ---

for ctl in /usr/sbin/apachectl /usr/sbin/apache2ctl; do
    if [ -x "$ctl" ]; then
        APACHECTL="$ctl"
        break
    fi
done

if [ -n "$APACHECTL" ]; then
    if "$APACHECTL" configtest 2>&1; then
        "$APACHECTL" graceful
        log "Apache reloaded."
    else
        error "Apache config test failed after removal. Check your Apache configuration."
    fi
else
    log "Apache control not found — skipping reload."
fi

log ""
log "=== markdown-for-agents uninstalled ==="
