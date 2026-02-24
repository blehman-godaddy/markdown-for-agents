#!/usr/bin/env bash
# mfa-global-install.sh — Install markdown-for-agents global infrastructure.
#
# Installs binaries, vendor deps, and the global ExtFilterDefine config.
# Must be run as root. Does NOT enable for any accounts — use mfa-account-enable.sh.
#
# Usage:
#   sudo bash mfa-global-install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/lib/mfa-common.sh"

mfa_read_version "$PROJECT_DIR"

# --- Root check ---

if [ "$(id -u)" -ne 0 ]; then
    error "Must be run as root (or via sudo)"
    exit 1
fi

log "Installing markdown-for-agents v${MFA_VERSION} global infrastructure ..."

# --- Detect PHP ---

if ! mfa_detect_php; then
    error "No PHP binary found"
    exit 1
fi
log "PHP: $MFA_PHP_BIN"

# --- Detect Apache ---

if ! mfa_detect_apache; then
    error "Cannot detect Apache config directory"
    exit 1
fi
log "Apache config: $MFA_APACHE_CONF_D"

# --- Check vendor ---

if [ ! -d "$PROJECT_DIR/vendor" ] || [ ! -f "$PROJECT_DIR/vendor/autoload.php" ]; then
    error "vendor/ directory missing — run 'composer install --no-dev' or use 'make dist'"
    exit 1
fi

# --- Install binaries ---

log "Installing to $MFA_INSTALL_DIR ..."
mkdir -p "$MFA_INSTALL_DIR"/{bin,vendor,conf}

cp "$PROJECT_DIR/bin/html2markdown.php" "$MFA_INSTALL_DIR/bin/"
cp "$PROJECT_DIR/bin/html2markdown-wrapper.sh" "$MFA_INSTALL_DIR/bin/"

# Inject PHP path into wrapper
sed -i "s|__PHP_BIN__|${MFA_PHP_BIN}|g" "$MFA_INSTALL_DIR/bin/html2markdown-wrapper.sh"

chmod 755 "$MFA_INSTALL_DIR/bin/html2markdown-wrapper.sh"
chmod 644 "$MFA_INSTALL_DIR/bin/html2markdown.php"

# --- Install vendor ---

log "Copying vendor dependencies ..."
cp -r "$PROJECT_DIR/vendor" "$MFA_INSTALL_DIR/"

# --- Install configs ---

# Copy all conf for reference
cp "$PROJECT_DIR/conf/"*.conf "$MFA_INSTALL_DIR/conf/"

# Module loader
if [ -n "$MFA_APACHE_MODULES_D" ] && [ -d "$MFA_APACHE_MODULES_D" ]; then
    cp "$PROJECT_DIR/conf/850-markdown-for-agents.conf" "$MFA_APACHE_MODULES_D/"
    chmod 644 "$MFA_APACHE_MODULES_D/850-markdown-for-agents.conf"
    log "Module loader: $MFA_APACHE_MODULES_D/850-markdown-for-agents.conf"
fi

# Global config — ExtFilterDefine ONLY (not the per-account activation)
cp "$PROJECT_DIR/conf/markdown-for-agents-global.conf" "$MFA_APACHE_CONF_D/markdown-for-agents.conf"
chmod 644 "$MFA_APACHE_CONF_D/markdown-for-agents.conf"
log "Global config: $MFA_APACHE_CONF_D/markdown-for-agents.conf"

# Store the account template for later use
cp "$PROJECT_DIR/conf/markdown-for-agents-account.conf" "$MFA_INSTALL_DIR/conf/"
# Replace __VERSION__ placeholder in stored template
sed -i "s|__VERSION__|${MFA_VERSION}|g" "$MFA_INSTALL_DIR/conf/markdown-for-agents-account.conf"

# --- Validate and reload Apache ---

log "Testing Apache configuration ..."
if mfa_configtest; then
    log "Config test passed. Reloading Apache ..."
    mfa_reload_apache
    log "Apache reloaded."
else
    error "Apache config test FAILED. Rolling back ..."
    rm -f "$MFA_APACHE_CONF_D/markdown-for-agents.conf"
    [ -d "$MFA_APACHE_MODULES_D" ] && rm -f "$MFA_APACHE_MODULES_D/850-markdown-for-agents.conf"
    rm -rf "$MFA_INSTALL_DIR"
    error "Global install removed. Fix the issue and re-run."
    exit 1
fi

# --- Smoke test ---

log "Running smoke test ..."
if mfa_smoke_test "$MFA_PHP_BIN" "$MFA_INSTALL_DIR/bin/html2markdown.php"; then
    log "Smoke test passed."
else
    warn "Smoke test: converter output unexpected. Check manually."
fi

# --- Write marker ---

echo "$MFA_VERSION" > "$MFA_INSTALL_DIR/.installed"
chmod 644 "$MFA_INSTALL_DIR/.installed"

echo ""
log "=== Global infrastructure installed (v${MFA_VERSION}) ==="
log "Use mfa-account-enable.sh <username> to enable for accounts."
