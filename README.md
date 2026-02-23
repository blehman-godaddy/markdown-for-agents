# markdown-for-agents

Apache output filter that enables `Accept: text/markdown` content negotiation server-wide on cPanel/WHM hosting via EasyApache 4. When an AI agent (or any client) sends `Accept: text/markdown`, HTML responses are automatically converted to clean Markdown — zero changes required at the origin (WordPress, PHP, static sites).

## How It Works

```
Client                         Apache                        Origin
  |                              |                              |
  |  GET / HTTP/1.1              |                              |
  |  Accept: text/markdown       |                              |
  |----------------------------->|                              |
  |                              |  GET / HTTP/1.1              |
  |                              |----------------------------->|
  |                              |                              |
  |                              |  200 OK                      |
  |                              |  Content-Type: text/html     |
  |                              |  <html>...</html>            |
  |                              |<-----------------------------|
  |                              |                              |
  |                              |  [html2md filter runs]       |
  |                              |  HTML → strip nav/sidebar →  |
  |                              |  convert to Markdown          |
  |                              |                              |
  |  200 OK                      |                              |
  |  Content-Type: text/markdown |                              |
  |  # Page Title                |                              |
  |  Content here...             |                              |
  |<-----------------------------|                              |
```

### Key design decisions

- **Zero overhead for normal requests**: The filter is only inserted into the chain when `Accept: text/markdown` is detected via `SetEnvIf`
- **Content stripping**: Non-content elements (nav, sidebar, footer, ads, skip-links, scroll-to-top) are removed via XPath before conversion
- **Safe fallback**: On any error, the original HTML is returned unchanged
- **Token metadata**: `<!-- mfa-meta:tokens=N html-tokens=N reduction=N% -->` embedded in the response body

## Quick Start

### Prerequisites

- Apache 2.4 with `mod_ext_filter`, `mod_setenvif`, `mod_headers`
- PHP 8.0+ with `dom` and `xml` extensions

### Install from release tarball (recommended)

Download and extract the latest release, then run the installer:

```bash
VERSION=0.1.4
curl -sL https://github.com/blehman-godaddy/markdown-for-agents/releases/download/v${VERSION}/markdown-for-agents-${VERSION}.tar.gz | tar xz
cd markdown-for-agents-${VERSION}
sudo bash install/install.sh
```

The tarball is self-contained — it includes all PHP dependencies, so Composer is not needed on the server.

### Preflight check (dry run)

Before installing, you can verify that all prerequisites are met without modifying anything:

```bash
sudo bash install/install.sh --check
```

This runs all preflight checks (root, PHP, Apache, vendor/, mod_ext_filter) and reports what's ready, what's missing, and what can be auto-fixed. No files are created or modified.

### Build from source

If you're developing or want to build the tarball yourself:

```bash
git clone https://github.com/blehman-godaddy/markdown-for-agents.git
cd markdown-for-agents
make dist
# produces dist/markdown-for-agents-${VERSION}.tar.gz
```

Then copy the tarball to your server and install:

```bash
scp dist/markdown-for-agents-*.tar.gz root@server:/tmp/
ssh root@server 'cd /tmp && tar xzf markdown-for-agents-*.tar.gz && cd markdown-for-agents-*/ && bash install/install.sh'
```

### Install directly from git (alternative)

```bash
git clone https://github.com/blehman-godaddy/markdown-for-agents.git /tmp/markdown-for-agents
cd /tmp/markdown-for-agents
composer install --no-dev
sudo bash install/install.sh
```

### What the installer does

The installer runs in three phases:

1. **Preflight** — checks root, PHP version/extensions, Apache paths, vendor/, mod_ext_filter (read-only, stops on failure)
2. **Auto-fix** — installs missing dependencies like `ea-apache24-mod_ext_filter` via yum if available
3. **Install** — copies files to `/opt/markdown-for-agents/`, deploys Apache configs, runs configtest, reloads Apache, smoke tests the converter

### Test

```bash
# Normal request — unchanged HTML:
curl -sI http://localhost/ | grep Content-Type
# → Content-Type: text/html

# Markdown request — converted:
curl -s -H "Accept: text/markdown" http://localhost/

# Check response headers:
curl -sI -H "Accept: text/markdown" http://localhost/
# → Content-Type: text/markdown; charset=utf-8
# → Vary: Accept
# → x-markdown-converter: markdown-for-agents/0.1.4
# → x-markdown-tokens: body-embedded
```

### Standalone converter test (no Apache)

```bash
composer install
echo '<html><body><nav>Menu</nav><h1>Title</h1><p>Content here.</p><footer>Footer</footer></body></html>' \
  | php bin/html2markdown.php
# Output:
# # Title
#
# Content here.
#
# <!-- mfa-meta:tokens=7 html-tokens=28 reduction=75% -->
```

### Run test suite

```bash
./tests/run-tests.sh
```

### Uninstall

```bash
sudo bash install/uninstall.sh
```

## Project Structure

```
markdown-for-agents/
├── VERSION                           # Version string (used by Makefile + installer)
├── Makefile                          # make dist / make clean
├── composer.json                     # league/html-to-markdown dependency
├── bin/
│   ├── html2markdown.php             # Core PHP converter (stdin → stdout)
│   └── html2markdown-wrapper.sh      # Bash wrapper for mod_ext_filter
├── conf/
│   ├── markdown-for-agents.conf      # Apache config
│   └── 850-markdown-for-agents.conf  # Module loader
├── install/
│   ├── install.sh                    # System installer (--check for dry run)
│   └── uninstall.sh                  # Clean removal
└── tests/
    ├── run-tests.sh                  # Test orchestrator
    ├── test-passthrough.sh           # Passthrough / edge cases
    ├── test-markdown-response.sh     # Conversion correctness
    ├── test-headers.sh               # Token metadata validation
    ├── test-content-quality.sh       # Fixture diff comparison
    ├── test-edge-cases.sh            # Malformed, empty, oversized
    └── fixtures/                     # Test HTML and expected MD
```

## Content Stripping

The following elements are removed before conversion:

| Type | Stripped |
|---|---|
| Tags | `nav`, `header`, `footer`, `aside`, `script`, `style`, `noscript`, `iframe` |
| Classes | `sidebar`, `widget`, `ad`, `advertisement`, `navigation`, `menu`, `breadcrumb` |
| ARIA roles | `navigation`, `banner`, `contentinfo`, `complementary` |
| UI elements | skip-links (`skip-link`, `screen-reader-text`), scroll-to-top (`scroll-to-top`, `back-to-top`) |

Class matching uses word-boundary logic (space-bounded + hyphen-prefix) to avoid false positives like `"ad"` matching `"has-global-padding"`.

## Response Headers

When `Accept: text/markdown` is present:

| Header | Value |
|---|---|
| `Content-Type` | `text/markdown; charset=utf-8` |
| `Vary` | `Accept` |
| `x-markdown-converter` | `markdown-for-agents/0.1.4` |
| `x-markdown-tokens` | `body-embedded` |

The token metadata is embedded as the last line of the body:

```
<!-- mfa-meta:tokens=74 html-tokens=16596 reduction=100% -->
```

- `tokens` — estimated token count of the Markdown output (~4 chars/token)
- `html-tokens` — estimated token count of the original HTML
- `reduction` — percentage reduction from HTML to Markdown

## Architecture

Uses `mod_ext_filter` to pipe HTML through a PHP-CLI converter:

1. `SetEnvIfNoCase` detects `Accept: text/markdown` → sets `WANTS_MARKDOWN` env var
2. `ExtFilterDefine` registers the filter with `enableenv=WANTS_MARKDOWN` + `intype=text/html`
3. `AddOutputFilter` applies to static files; `<If>` with `SetOutputFilter` handles proxied PHP (php-fpm)
4. The filter pipes HTML through `html2markdown-wrapper.sh` → `html2markdown.php`
5. PHP strips non-content elements via XPath, converts to Markdown via `league/html-to-markdown`, appends token metadata
6. Response headers are set via `Header` directives conditioned on `WANTS_MARKDOWN`

## License

MIT
