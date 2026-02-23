#!/usr/bin/env bash
# html2markdown-wrapper.sh — Thin wrapper for mod_ext_filter.
#
# Pipes stdin HTML through the PHP converter with a 10MB size limit.
# Resolves the PHP binary (EA4 ea-php82/81/80 or system php).
# Suppresses stderr so Apache doesn't log noise unless ExtFilterOptions LogStderr is on.

set -euo pipefail

MAX_SIZE=$((10 * 1024 * 1024))  # 10MB

# Resolve PHP binary — prefer EA4 paths, fall back to system
# The install script will replace __PHP_BIN__ with the detected path.
PHP_BIN="__PHP_BIN__"

if [ "$PHP_BIN" = "__PHP_BIN__" ]; then
    # Not injected by installer; detect at runtime
    for candidate in /opt/cpanel/ea-php82/root/usr/bin/php \
                     /opt/cpanel/ea-php81/root/usr/bin/php \
                     /opt/cpanel/ea-php80/root/usr/bin/php \
                     /usr/local/bin/php \
                     /usr/bin/php \
                     php; do
        if command -v "$candidate" &>/dev/null; then
            PHP_BIN="$candidate"
            break
        fi
    done
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERTER="${SCRIPT_DIR}/html2markdown.php"

# Enforce size limit via head -c, then pipe to converter
head -c "$MAX_SIZE" | "$PHP_BIN" "$CONVERTER" 2>/dev/null
