#!/usr/bin/env bash
# mfa-common.sh — Shared functions for markdown-for-agents install scripts.
#
# Source this file:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/mfa-common.sh"

# Prevent double-sourcing
if [ "${_MFA_COMMON_LOADED:-}" = "1" ]; then
    return 0
fi
_MFA_COMMON_LOADED=1

# --- Constants ---

MFA_INSTALL_DIR="/opt/markdown-for-agents"

# --- Colors ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Logging ---

log()   { echo -e "${GREEN}[mfa]${NC} $*"; }
warn()  { echo -e "${YELLOW}[mfa]${NC} $*"; }
error() { echo -e "${RED}[mfa]${NC} $*" >&2; }
info()  { echo -e "${BLUE}[mfa]${NC} $*"; }

# --- Preflight tracking ---

FATAL=0
WARNINGS=0
AUTOFIX_NEEDED=()

preflight_ok()   { log "  ✓ $*"; }
preflight_warn() { warn "  ⚠ $*"; WARNINGS=$((WARNINGS + 1)); }
preflight_fail() { error "  ✗ $*"; FATAL=$((FATAL + 1)); }

# --- Version ---

# mfa_read_version <project_dir>
#   Sets: MFA_VERSION
mfa_read_version() {
    local project_dir="${1:-.}"
    if [ -f "$project_dir/VERSION" ]; then
        MFA_VERSION="$(tr -d '[:space:]' < "$project_dir/VERSION")"
    else
        MFA_VERSION="0.1.0"
    fi
}

# --- PHP detection ---

# mfa_detect_php
#   Sets: MFA_PHP_BIN (empty string if not found)
#   Returns: 0 if found, 1 if not
mfa_detect_php() {
    MFA_PHP_BIN=""
    for candidate in /opt/cpanel/ea-php82/root/usr/bin/php \
                     /opt/cpanel/ea-php81/root/usr/bin/php \
                     /opt/cpanel/ea-php80/root/usr/bin/php \
                     /usr/local/bin/php \
                     /usr/bin/php; do
        if [ -x "$candidate" ]; then
            MFA_PHP_BIN="$candidate"
            return 0
        fi
    done
    return 1
}

# --- Apache detection ---

# mfa_detect_apache
#   Sets: MFA_APACHE_CONF_D, MFA_APACHE_MODULES_D, MFA_APACHECTL
#   Returns: 0 if found, 1 if not
mfa_detect_apache() {
    MFA_APACHE_CONF_D=""
    MFA_APACHE_MODULES_D=""
    MFA_APACHECTL=""

    if [ -d "/etc/apache2/conf.d" ]; then
        MFA_APACHE_CONF_D="/etc/apache2/conf.d"
        MFA_APACHE_MODULES_D="/etc/apache2/conf.modules.d"
        MFA_APACHECTL="/usr/sbin/apachectl"
    elif [ -d "/etc/httpd/conf.d" ]; then
        MFA_APACHE_CONF_D="/etc/httpd/conf.d"
        MFA_APACHE_MODULES_D="/etc/httpd/conf.modules.d"
        MFA_APACHECTL="/usr/sbin/apachectl"
    elif [ -d "/etc/apache2/conf-available" ]; then
        MFA_APACHE_CONF_D="/etc/apache2/conf-available"
        MFA_APACHE_MODULES_D="/etc/apache2/mods-available"
        MFA_APACHECTL="/usr/sbin/apache2ctl"
    fi

    if [ -z "$MFA_APACHE_CONF_D" ]; then
        return 1
    fi
    return 0
}

# --- mod_ext_filter detection ---

# mfa_check_mod_ext_filter
#   Sets: MFA_MOD_EXT_FILTER_LOADED, MFA_MOD_EXT_FILTER_SO_EXISTS,
#         MFA_MOD_EXT_FILTER_RPM_AVAILABLE
mfa_check_mod_ext_filter() {
    MFA_MOD_EXT_FILTER_LOADED=false
    MFA_MOD_EXT_FILTER_SO_EXISTS=false
    MFA_MOD_EXT_FILTER_RPM_AVAILABLE=false

    # Check if already loaded
    if [ -n "${MFA_APACHECTL:-}" ] && [ -x "${MFA_APACHECTL:-}" ]; then
        if "$MFA_APACHECTL" -M 2>/dev/null | grep -qi "ext_filter"; then
            MFA_MOD_EXT_FILTER_LOADED=true
        fi
    fi

    # Check if .so exists on disk
    for so_path in /usr/lib64/apache2/mod_ext_filter.so \
                   /usr/lib/apache2/modules/mod_ext_filter.so \
                   /usr/lib64/httpd/modules/mod_ext_filter.so \
                   /usr/lib/httpd/modules/mod_ext_filter.so; do
        if [ -f "$so_path" ]; then
            MFA_MOD_EXT_FILTER_SO_EXISTS=true
            break
        fi
    done

    # Check if RPM is available (cPanel / RHEL)
    if command -v yum &>/dev/null; then
        if yum list available ea-apache24-mod_ext_filter 2>/dev/null | grep -q ea-apache24-mod_ext_filter; then
            MFA_MOD_EXT_FILTER_RPM_AVAILABLE=true
        fi
    fi
}

# --- Config test ---

# mfa_configtest
#   Runs Apache config test. Returns 0 on success, 1 on failure.
mfa_configtest() {
    if [ -z "${MFA_APACHECTL:-}" ] || [ ! -x "${MFA_APACHECTL:-}" ]; then
        error "Apache control binary not found"
        return 1
    fi
    "$MFA_APACHECTL" configtest 2>&1
}

# --- Apache reload ---

# mfa_reload_apache
#   Reloads Apache gracefully. Returns 0 on success, 1 on failure.
mfa_reload_apache() {
    if [ -z "${MFA_APACHECTL:-}" ] || [ ! -x "${MFA_APACHECTL:-}" ]; then
        error "Apache control binary not found"
        return 1
    fi
    "$MFA_APACHECTL" graceful
}

# --- Smoke test ---

# mfa_smoke_test [php_bin] [converter_path]
#   Returns 0 if converter produces expected output, 1 otherwise.
mfa_smoke_test() {
    local php_bin="${1:-${MFA_PHP_BIN:-php}}"
    local converter="${2:-${MFA_INSTALL_DIR}/bin/html2markdown.php}"
    local result

    result=$(echo '<html><body><h1>Test</h1><p>Hello</p></body></html>' | "$php_bin" "$converter" 2>/dev/null)

    if echo "$result" | grep -q "# Test"; then
        return 0
    fi
    return 1
}

# --- Username validation ---

# mfa_validate_username <username>
#   Validates cPanel username format. Returns 0 if valid, 1 if not.
mfa_validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-z][a-z0-9]{0,15}$ ]]; then
        return 1
    fi
    return 0
}

# mfa_user_exists <username>
#   Checks if cPanel user exists. Returns 0 if exists, 1 if not.
mfa_user_exists() {
    local username="$1"
    if [ -d "/var/cpanel/userdata/$username" ]; then
        return 0
    fi
    return 1
}

# --- Userdata paths ---

# mfa_userdata_paths <username>
#   Sets: MFA_USERDATA_STD, MFA_USERDATA_SSL
mfa_userdata_paths() {
    local username="$1"
    MFA_USERDATA_STD="/etc/apache2/conf.d/userdata/std/2_4/${username}/markdown-for-agents.conf"
    MFA_USERDATA_SSL="/etc/apache2/conf.d/userdata/ssl/2_4/${username}/markdown-for-agents.conf"
}

# --- cPanel httpd rebuild ---

# mfa_rebuild_httpd
#   Rebuilds httpd config and restarts via cPanel scripts.
mfa_rebuild_httpd() {
    if [ -x "/usr/local/cpanel/scripts/rebuildhttpdconf" ]; then
        /usr/local/cpanel/scripts/rebuildhttpdconf >/dev/null 2>&1
    else
        error "rebuildhttpdconf not found"
        return 1
    fi
    if [ -x "/usr/local/cpanel/scripts/restartsrv_httpd" ]; then
        /usr/local/cpanel/scripts/restartsrv_httpd >/dev/null 2>&1
    else
        error "restartsrv_httpd not found"
        return 1
    fi
    return 0
}
