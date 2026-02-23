#!/usr/bin/env bash
# install.sh — Install markdown-for-agents to /opt/markdown-for-agents + Apache config
#
# Must be run as root. Supports EasyApache 4 (cPanel) and standard Apache installs.

set -euo pipefail

VERSION="0.1.0"
INSTALL_DIR="/opt/markdown-for-agents"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[mfa]${NC} $*"; }
warn()  { echo -e "${YELLOW}[mfa]${NC} $*"; }
error() { echo -e "${RED}[mfa]${NC} $*" >&2; }

# --- Preflight checks ---

if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (or via sudo)."
    exit 1
fi

# --- Detect PHP binary ---

PHP_BIN=""
for candidate in /opt/cpanel/ea-php82/root/usr/bin/php \
                 /opt/cpanel/ea-php81/root/usr/bin/php \
                 /opt/cpanel/ea-php80/root/usr/bin/php \
                 /usr/local/bin/php \
                 /usr/bin/php; do
    if [ -x "$candidate" ]; then
        PHP_BIN="$candidate"
        break
    fi
done

if [ -z "$PHP_BIN" ]; then
    error "No PHP 8.0+ binary found. Install PHP or EasyApache 4 PHP."
    exit 1
fi

PHP_VERSION=$("$PHP_BIN" -r 'echo PHP_MAJOR_VERSION;')
if [ "$PHP_VERSION" -lt 8 ]; then
    error "PHP 8.0+ required. Found: $("$PHP_BIN" -v | head -1)"
    exit 1
fi

log "Using PHP: $PHP_BIN ($("$PHP_BIN" -v | head -1))"

# --- Check required PHP extensions ---

for ext in dom xml; do
    if ! "$PHP_BIN" -m 2>/dev/null | grep -qi "^${ext}$"; then
        error "Required PHP extension missing: $ext"
        exit 1
    fi
done

# --- Detect Apache config paths ---

APACHE_CONF_D=""
APACHE_MODULES_D=""
APACHECTL=""

if [ -d "/etc/apache2/conf.d" ]; then
    # EasyApache 4 / cPanel
    APACHE_CONF_D="/etc/apache2/conf.d"
    APACHE_MODULES_D="/etc/apache2/conf.modules.d"
    APACHECTL="/usr/sbin/apachectl"
elif [ -d "/etc/httpd/conf.d" ]; then
    # Standard RHEL/CentOS
    APACHE_CONF_D="/etc/httpd/conf.d"
    APACHE_MODULES_D="/etc/httpd/conf.modules.d"
    APACHECTL="/usr/sbin/apachectl"
elif [ -d "/etc/apache2/conf-available" ]; then
    # Debian/Ubuntu
    APACHE_CONF_D="/etc/apache2/conf-available"
    APACHE_MODULES_D="/etc/apache2/mods-available"
    APACHECTL="/usr/sbin/apache2ctl"
else
    error "Cannot detect Apache config directory. Supported: EA4, RHEL, Debian."
    exit 1
fi

log "Apache config dir: $APACHE_CONF_D"

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

# Install vendor dependencies
if [ -d "$PROJECT_DIR/vendor" ]; then
    log "Copying vendor dependencies ..."
    cp -r "$PROJECT_DIR/vendor" "$INSTALL_DIR/"
elif command -v composer &>/dev/null; then
    log "Installing composer dependencies ..."
    cd "$PROJECT_DIR"
    composer install --no-dev --optimize-autoloader --no-interaction
    cp -r "$PROJECT_DIR/vendor" "$INSTALL_DIR/"
else
    error "No vendor/ directory and composer not found."
    error "Run 'composer install' locally and include vendor/ in the upload."
    exit 1
fi

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

if "$APACHECTL" configtest 2>&1; then
    log "Config test passed. Reloading Apache ..."
    "$APACHECTL" graceful
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

SMOKE_RESULT=$(echo '<html><body><h1>Test</h1><p>Hello</p></body></html>' | "$PHP_BIN" "$INSTALL_DIR/bin/html2markdown.php" 2>/dev/null)

if echo "$SMOKE_RESULT" | grep -q "# Test"; then
    log "Smoke test passed."
else
    warn "Smoke test: converter output unexpected. Check manually."
    warn "Output: $SMOKE_RESULT"
fi

log ""
log "=== markdown-for-agents v${VERSION} installed ==="
log "Install dir: $INSTALL_DIR"
log "Apache conf: $APACHE_CONF_D/markdown-for-agents.conf"
log ""
log "Test with:"
log "  curl -s -H 'Accept: text/markdown' http://localhost/"
log ""
log "Uninstall with:"
log "  $PROJECT_DIR/install/uninstall.sh"
