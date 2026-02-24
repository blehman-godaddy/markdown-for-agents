#!/usr/bin/env bash
# install.sh — Install markdown-for-agents to /opt/markdown-for-agents + Apache config
#
# Must be run as root. Supports EasyApache 4 (cPanel) and standard Apache installs.
#
# Usage:
#   sudo ./install.sh            # full install
#   sudo ./install.sh --check    # dry-run: preflight checks only, no changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared functions
source "$PROJECT_DIR/lib/mfa-common.sh"

INSTALL_DIR="$MFA_INSTALL_DIR"

# Read version from VERSION file, fall back to hardcoded
mfa_read_version "$PROJECT_DIR"
VERSION="$MFA_VERSION"

# --- Parse flags ---

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
fi

# ============================================================================
# PHASE 1 — PREFLIGHT (read-only, checks everything before touching system)
# ============================================================================

echo ""
echo -e "${BOLD}markdown-for-agents v${VERSION} — Preflight Checks${NC}"
echo -e "${BOLD}$(printf '=%.0s' {1..50})${NC}"
echo ""

# --- 1. Root check ---

info "Checking permissions ..."
if [ "$(id -u)" -ne 0 ]; then
    preflight_fail "Must be run as root (or via sudo)"
else
    preflight_ok "Running as root"
fi

# --- 2. PHP binary detection + version + extensions ---

info "Checking PHP ..."

if mfa_detect_php; then
    PHP_BIN="$MFA_PHP_BIN"
    PHP_VERSION_FULL=$("$PHP_BIN" -v 2>/dev/null | head -1 || echo "unknown")
    PHP_MAJOR=$("$PHP_BIN" -r 'echo PHP_MAJOR_VERSION;' 2>/dev/null || echo "0")
    if [ "$PHP_MAJOR" -lt 8 ]; then
        preflight_fail "PHP 8.0+ required. Found: $PHP_VERSION_FULL"
    else
        preflight_ok "PHP: $PHP_BIN ($PHP_VERSION_FULL)"
    fi

    # Check extensions
    for ext in dom xml; do
        if "$PHP_BIN" -m 2>/dev/null | grep -qi "^${ext}$"; then
            preflight_ok "PHP extension: $ext"
        else
            preflight_fail "PHP extension missing: $ext"
        fi
    done
else
    PHP_BIN=""
    preflight_fail "No PHP binary found"
fi

# --- 3. Apache config directory detection ---

info "Checking Apache ..."

if mfa_detect_apache; then
    APACHE_CONF_D="$MFA_APACHE_CONF_D"
    APACHE_MODULES_D="$MFA_APACHE_MODULES_D"
    APACHECTL="$MFA_APACHECTL"

    preflight_ok "Apache config: $APACHE_CONF_D"
    if [ -n "$APACHE_MODULES_D" ] && [ -d "$APACHE_MODULES_D" ]; then
        preflight_ok "Apache modules: $APACHE_MODULES_D"
    fi
else
    APACHE_CONF_D=""
    APACHE_MODULES_D=""
    APACHECTL=""
    preflight_fail "Cannot detect Apache config directory (checked EA4, RHEL, Debian)"
fi

# --- 4. vendor/ directory present ---

info "Checking dependencies ..."

if [ -d "$PROJECT_DIR/vendor" ] && [ -f "$PROJECT_DIR/vendor/autoload.php" ]; then
    preflight_ok "vendor/ directory present"
else
    preflight_fail "vendor/ directory missing — run 'composer install --no-dev' or use 'make dist'"
fi

# --- 5. mod_ext_filter availability ---

info "Checking mod_ext_filter ..."

mfa_check_mod_ext_filter

if $MFA_MOD_EXT_FILTER_LOADED; then
    preflight_ok "mod_ext_filter is loaded"
elif $MFA_MOD_EXT_FILTER_SO_EXISTS; then
    preflight_ok "mod_ext_filter .so found (will be loaded by config)"
elif $MFA_MOD_EXT_FILTER_RPM_AVAILABLE; then
    preflight_warn "mod_ext_filter not installed — RPM ea-apache24-mod_ext_filter is available"
    AUTOFIX_NEEDED+=("mod_ext_filter")
else
    # On systems without yum, the module loader config (850-*.conf) may handle it
    if [ -f "$PROJECT_DIR/conf/850-markdown-for-agents.conf" ]; then
        preflight_warn "mod_ext_filter not detected — the module loader config will attempt to load it"
    else
        preflight_fail "mod_ext_filter not available and no RPM found to install it"
        error "         Install it manually: yum install ea-apache24-mod_ext_filter"
        error "         Or: a2enmod ext_filter (Debian/Ubuntu)"
    fi
fi

# --- Preflight summary ---

echo ""
echo -e "${BOLD}Preflight Summary${NC}"
echo -e "${BOLD}$(printf -- '-%.0s' {1..50})${NC}"

if [ $FATAL -gt 0 ]; then
    error "$FATAL fatal issue(s) found. Cannot proceed with install."
    if [ ${#AUTOFIX_NEEDED[@]} -gt 0 ]; then
        warn "${#AUTOFIX_NEEDED[@]} issue(s) could be auto-fixed (but fatal issues must be resolved first)."
    fi
    echo ""
    exit 1
fi

if [ ${#AUTOFIX_NEEDED[@]} -gt 0 ]; then
    warn "${#AUTOFIX_NEEDED[@]} issue(s) can be auto-fixed:"
    for fix in "${AUTOFIX_NEEDED[@]}"; do
        warn "  → $fix"
    done
fi

if [ $WARNINGS -eq 0 ] && [ ${#AUTOFIX_NEEDED[@]} -eq 0 ]; then
    log "All checks passed."
fi

# --- --check mode exits here ---

if $CHECK_ONLY; then
    echo ""
    if [ ${#AUTOFIX_NEEDED[@]} -gt 0 ]; then
        info "Dry run complete. Re-run without --check to install (auto-fixes will be applied)."
    else
        info "Dry run complete. Re-run without --check to install."
    fi
    exit 0
fi

# ============================================================================
# PHASE 2 — AUTO-FIX (install missing dependencies with confirmation)
# ============================================================================

if [ ${#AUTOFIX_NEEDED[@]} -gt 0 ]; then
    echo ""
    echo -e "${BOLD}Auto-fixing missing dependencies ...${NC}"

    for fix in "${AUTOFIX_NEEDED[@]}"; do
        case "$fix" in
            mod_ext_filter)
                if $MFA_MOD_EXT_FILTER_RPM_AVAILABLE; then
                    log "Installing ea-apache24-mod_ext_filter via yum ..."
                    if yum install -y ea-apache24-mod_ext_filter; then
                        preflight_ok "ea-apache24-mod_ext_filter installed"
                    else
                        error "Failed to install ea-apache24-mod_ext_filter"
                        error "Install manually: yum install ea-apache24-mod_ext_filter"
                        exit 1
                    fi
                fi
                ;;
        esac
    done
fi

# ============================================================================
# PHASE 3 — INSTALL (only runs after preflight fully passes)
# ============================================================================

echo ""
echo -e "${BOLD}Installing markdown-for-agents v${VERSION} ...${NC}"
echo -e "${BOLD}$(printf '=%.0s' {1..50})${NC}"
echo ""

# --- Install files ---

log "Installing to $INSTALL_DIR ..."

mkdir -p "$INSTALL_DIR"/{bin,vendor,conf}

# Copy converter and wrapper
cp "$PROJECT_DIR/bin/html2markdown.php" "$INSTALL_DIR/bin/"
cp "$PROJECT_DIR/bin/html2markdown-wrapper.sh" "$INSTALL_DIR/bin/"

# Inject PHP path into wrapper
sed -i "s|__PHP_BIN__|${PHP_BIN}|g" "$INSTALL_DIR/bin/html2markdown-wrapper.sh"

# Set permissions
chmod 755 "$INSTALL_DIR/bin/html2markdown-wrapper.sh"
chmod 644 "$INSTALL_DIR/bin/html2markdown.php"

# Copy vendor dependencies
log "Copying vendor dependencies ..."
cp -r "$PROJECT_DIR/vendor" "$INSTALL_DIR/"

# Copy conf for reference
cp "$PROJECT_DIR/conf/"*.conf "$INSTALL_DIR/conf/"

# --- Install Apache configs ---

log "Installing Apache configuration ..."

# Module loader
if [ -d "$APACHE_MODULES_D" ]; then
    cp "$PROJECT_DIR/conf/850-markdown-for-agents.conf" "$APACHE_MODULES_D/"
    chmod 644 "$APACHE_MODULES_D/850-markdown-for-agents.conf"
fi

# Main config
cp "$PROJECT_DIR/conf/markdown-for-agents.conf" "$APACHE_CONF_D/"
chmod 644 "$APACHE_CONF_D/markdown-for-agents.conf"

# Debian/Ubuntu: enable the config
if [ -d "/etc/apache2/conf-enabled" ] && [ -f "/etc/apache2/conf-available/markdown-for-agents.conf" ]; then
    ln -sf "/etc/apache2/conf-available/markdown-for-agents.conf" "/etc/apache2/conf-enabled/"
fi

# --- Validate and reload Apache ---

log "Testing Apache configuration ..."

if mfa_configtest; then
    log "Config test passed. Reloading Apache ..."
    mfa_reload_apache
    log "Apache reloaded."
else
    error "Apache config test FAILED. Rolling back ..."
    rm -f "$APACHE_CONF_D/markdown-for-agents.conf"
    [ -d "$APACHE_MODULES_D" ] && rm -f "$APACHE_MODULES_D/850-markdown-for-agents.conf"
    error "Apache configs removed. Fix the issue and re-run install."
    exit 1
fi

# --- Smoke test ---

log "Running smoke test ..."

if mfa_smoke_test "$PHP_BIN" "$INSTALL_DIR/bin/html2markdown.php"; then
    log "Smoke test passed."
else
    warn "Smoke test: converter output unexpected. Check manually."
fi

# --- Done ---

echo ""
log "=== markdown-for-agents v${VERSION} installed ==="
log "Install dir:  $INSTALL_DIR"
log "Apache conf:  $APACHE_CONF_D/markdown-for-agents.conf"
echo ""
log "Test with:"
log "  curl -s -H 'Accept: text/markdown' http://localhost/"
echo ""
log "Uninstall with:"
log "  sudo $INSTALL_DIR/../install/uninstall.sh"
log "  # or: sudo $PROJECT_DIR/install/uninstall.sh"
