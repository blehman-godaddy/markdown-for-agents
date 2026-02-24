#!/usr/bin/env bash
# uninstall-plugin.sh — Remove markdown-for-agents cPanel plugin.
#
# Removes WHM plugin, cPanel plugin, sudoers, and global infrastructure.
# Must be run as root.
#
# Usage:
#   sudo bash uninstall-plugin.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/lib/mfa-common.sh"

# --- Root check ---

if [ "$(id -u)" -ne 0 ]; then
    error "Must be run as root (or via sudo)"
    exit 1
fi

log "Removing markdown-for-agents cPanel plugin ..."

# ============================================================================
# 1. cPanel plugin
# ============================================================================

log "Phase 1: Removing cPanel plugin ..."

rm -rf "/usr/local/cpanel/base/frontend/jupiter/markdown_for_agents"
rm -f "/usr/local/cpanel/base/frontend/jupiter/dynamicui/markdown_for_agents.json"
log "cPanel plugin removed."

# ============================================================================
# 2. WHM plugin
# ============================================================================

log "Phase 2: Removing WHM plugin ..."

# Unregister AppConfig
APPCONFIG="/var/cpanel/apps/markdown_for_agents.conf"
if [ -f "$APPCONFIG" ]; then
    if [ -x "/usr/local/cpanel/bin/unregister_appconfig" ]; then
        /usr/local/cpanel/bin/unregister_appconfig "$APPCONFIG" 2>/dev/null || true
    fi
    rm -f "$APPCONFIG"
fi

rm -rf "/usr/local/cpanel/whostmgr/cgi/addons/markdown_for_agents"
log "WHM plugin removed."

# ============================================================================
# 3. Sudoers
# ============================================================================

log "Phase 3: Removing sudoers ..."

rm -f "/etc/sudoers.d/markdown-for-agents"
log "Sudoers removed."

# ============================================================================
# 4. Global infrastructure
# ============================================================================

log "Phase 4: Removing global infrastructure ..."

# Use global uninstall if scripts still exist
if [ -x "$SCRIPT_DIR/scripts/mfa-global-uninstall.sh" ]; then
    bash "$SCRIPT_DIR/scripts/mfa-global-uninstall.sh"
elif [ -x "$MFA_INSTALL_DIR/cpanel/scripts/mfa-global-uninstall.sh" ]; then
    bash "$MFA_INSTALL_DIR/cpanel/scripts/mfa-global-uninstall.sh"
else
    # Manual cleanup if scripts are gone
    warn "Global uninstall script not found — cleaning up manually"

    # Remove userdata includes
    for proto in std ssl; do
        dir="/etc/apache2/conf.d/userdata/$proto/2_4"
        if [ -d "$dir" ]; then
            find "$dir" -name "markdown-for-agents.conf" -delete 2>/dev/null || true
        fi
    done

    # Remove Apache configs
    rm -f "/etc/apache2/conf.d/markdown-for-agents.conf"
    rm -f "/etc/apache2/conf.modules.d/850-markdown-for-agents.conf"

    # Remove install dir
    rm -rf "$MFA_INSTALL_DIR"

    # Reload Apache
    if mfa_detect_apache; then
        mfa_configtest && mfa_reload_apache
    fi
fi

echo ""
log "=== markdown-for-agents cPanel plugin removed ==="
