#!/usr/bin/env bash
# install-plugin.sh — Install markdown-for-agents as a WHM/cPanel plugin.
#
# Installs global infrastructure, registers WHM admin plugin, registers cPanel
# customer plugin, and configures sudoers for the account management scripts.
#
# Must be run as root on a WHM/cPanel server.
#
# Usage:
#   sudo bash install-plugin.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/lib/mfa-common.sh"

mfa_read_version "$PROJECT_DIR"

# --- Root check ---

if [ "$(id -u)" -ne 0 ]; then
    error "Must be run as root (or via sudo)"
    exit 1
fi

# --- cPanel check ---

if [ ! -d "/usr/local/cpanel" ]; then
    error "cPanel/WHM not detected (/usr/local/cpanel not found)"
    error "For standalone Apache installs, use install/install.sh instead."
    exit 1
fi

log "Installing markdown-for-agents cPanel plugin v${MFA_VERSION} ..."

# ============================================================================
# 1. Global infrastructure (binaries, vendor, ExtFilterDefine)
# ============================================================================

log "Phase 1: Installing global infrastructure ..."
bash "$SCRIPT_DIR/scripts/mfa-global-install.sh"

# Copy cpanel scripts to install dir for runtime use
cp -r "$SCRIPT_DIR/scripts" "$MFA_INSTALL_DIR/cpanel/"
mkdir -p "$MFA_INSTALL_DIR/cpanel/scripts"
cp "$SCRIPT_DIR"/scripts/*.sh "$MFA_INSTALL_DIR/cpanel/scripts/"
chmod 755 "$MFA_INSTALL_DIR/cpanel/scripts/"*.sh

# Copy lib for runtime use by installed scripts
cp -r "$PROJECT_DIR/lib" "$MFA_INSTALL_DIR/"
chmod 755 "$MFA_INSTALL_DIR/lib/mfa-common.sh"

# ============================================================================
# 2. WHM plugin registration
# ============================================================================

log "Phase 2: Registering WHM plugin ..."

WHM_CGI_DIR="/usr/local/cpanel/whostmgr/docroot/cgi"

# Copy CGI to standard WHM CGI directory
cp "$SCRIPT_DIR/whm/cgi/addon_markdown_for_agents.cgi" "$WHM_CGI_DIR/"
chmod 755 "$WHM_CGI_DIR/addon_markdown_for_agents.cgi"

# Copy icon to addon_plugins directory
WHM_ICON_DIR="/usr/local/cpanel/whostmgr/docroot/addon_plugins"
if [ -d "$SCRIPT_DIR/whm/icons" ]; then
    cp "$SCRIPT_DIR/whm/icons/"* "$WHM_ICON_DIR/" 2>/dev/null || true
fi

# Register AppConfig
APPCONFIG_DIR="/var/cpanel/apps"
mkdir -p "$APPCONFIG_DIR"
cp "$SCRIPT_DIR/whm/markdown_for_agents.conf" "$APPCONFIG_DIR/"
chmod 644 "$APPCONFIG_DIR/markdown_for_agents.conf"

# Register via WHM API if available
if [ -x "/usr/local/cpanel/bin/register_appconfig" ]; then
    /usr/local/cpanel/bin/register_appconfig "$APPCONFIG_DIR/markdown_for_agents.conf" 2>/dev/null || true
    log "WHM AppConfig registered."
else
    log "WHM AppConfig file installed (register_appconfig not found)."
fi

# ============================================================================
# 3. cPanel plugin registration
# ============================================================================

log "Phase 3: Registering cPanel plugin ..."

CPANEL_PLUGIN_DIR="/usr/local/cpanel/base/frontend/jupiter/markdown_for_agents"
CPANEL_DYNAMICUI_DIR="/usr/local/cpanel/base/frontend/jupiter/dynamicui"

# Copy plugin files
mkdir -p "$CPANEL_PLUGIN_DIR"
cp "$SCRIPT_DIR/cpanel/markdown_for_agents/index.live.php" "$CPANEL_PLUGIN_DIR/"
chmod 644 "$CPANEL_PLUGIN_DIR/index.live.php"

# Copy icon
mkdir -p "$CPANEL_PLUGIN_DIR/icons"
if [ -f "$SCRIPT_DIR/cpanel/icons/markdown-for-agents.svg" ]; then
    cp "$SCRIPT_DIR/cpanel/icons/markdown-for-agents.svg" "$CPANEL_PLUGIN_DIR/icons/"
fi

# Register dynamicui
mkdir -p "$CPANEL_DYNAMICUI_DIR"
cp "$SCRIPT_DIR/cpanel/install.json" "$CPANEL_DYNAMICUI_DIR/markdown_for_agents.json"
chmod 644 "$CPANEL_DYNAMICUI_DIR/markdown_for_agents.json"

log "cPanel plugin registered."

# ============================================================================
# 4. Sudoers configuration
# ============================================================================

log "Phase 4: Configuring sudoers ..."

SUDOERS_FILE="/etc/sudoers.d/markdown-for-agents"
cat > "$SUDOERS_FILE" <<'SUDOERS'
# markdown-for-agents — Allow cPanel/WHM to run account management scripts
# Installed by install-plugin.sh — DO NOT EDIT

# WHM admin (root CGI runs as nobody on some setups)
nobody ALL=(root) NOPASSWD: /opt/markdown-for-agents/cpanel/scripts/mfa-account-enable.sh
nobody ALL=(root) NOPASSWD: /opt/markdown-for-agents/cpanel/scripts/mfa-account-disable.sh
nobody ALL=(root) NOPASSWD: /opt/markdown-for-agents/cpanel/scripts/mfa-global-install.sh

# cPanel users (cpanelphp / lsapi run .live.php as the cPanel user)
ALL ALL=(root) NOPASSWD: /opt/markdown-for-agents/cpanel/scripts/mfa-account-enable.sh
ALL ALL=(root) NOPASSWD: /opt/markdown-for-agents/cpanel/scripts/mfa-account-disable.sh
SUDOERS
chmod 440 "$SUDOERS_FILE"

# Validate sudoers
if visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
    log "Sudoers configured: $SUDOERS_FILE"
else
    error "Sudoers syntax error — removing file"
    rm -f "$SUDOERS_FILE"
    exit 1
fi

# ============================================================================
# Done
# ============================================================================

echo ""
log "=== markdown-for-agents cPanel plugin v${MFA_VERSION} installed ==="
log ""
log "WHM:    Go to WHM > Plugins > Markdown for Agents"
log "cPanel: Customers will see it under Advanced > Markdown for Agents"
log ""
log "Uninstall with:"
log "  sudo bash $SCRIPT_DIR/uninstall-plugin.sh"
