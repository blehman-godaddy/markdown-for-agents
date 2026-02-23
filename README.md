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

- **Zero overhead for normal requests**: `enableenv=WANTS_MARKDOWN` removes the filter from the chain entirely when the Accept header doesn't match
- **Content stripping**: Non-content elements (nav, sidebar, footer, ads) are removed via XPath before conversion
- **Safe fallback**: On any error, the original HTML is returned unchanged
- **Token estimation**: `<!-- mfa-meta:tokens=N -->` embedded in body (mod_ext_filter can't set headers from subprocess)

## Quick Start

### Prerequisites

- Apache 2.4 with `mod_ext_filter`, `mod_setenvif`, `mod_headers`
- PHP 8.0+ with `dom` and `xml` extensions
- Composer

### Install (cPanel/WHM with EasyApache 4)

```bash
git clone <repo-url> /tmp/markdown-for-agents
cd /tmp/markdown-for-agents
sudo ./install/install.sh
```

The installer will:
1. Detect your PHP binary (EA4 `ea-php82/81/80` or system `php`)
2. Detect your Apache config directory
3. Install files to `/opt/markdown-for-agents/`
4. Copy Apache configs and reload

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
# → x-markdown-converter: markdown-for-agents/0.1.0
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
# <!-- mfa-meta:tokens=... -->
```

### Run test suite

```bash
./tests/run-tests.sh
```

### Uninstall

```bash
sudo ./install/uninstall.sh
```

## Project Structure

```
markdown-for-agents/
├── composer.json                      # league/html-to-markdown dependency
├── bin/
│   ├── html2markdown.php              # Core PHP converter (stdin → stdout)
│   └── html2markdown-wrapper.sh       # Bash wrapper for mod_ext_filter
├── conf/
│   ├── markdown-for-agents.conf       # Apache config
│   └── 850-markdown-for-agents.conf   # Module loader
├── install/
│   ├── install.sh                     # System installer
│   └── uninstall.sh                   # Clean removal
└── tests/
    ├── run-tests.sh                   # Test orchestrator
    ├── test-passthrough.sh            # Passthrough / edge cases
    ├── test-markdown-response.sh      # Conversion correctness
    ├── test-headers.sh                # Token metadata validation
    ├── test-content-quality.sh        # Fixture diff comparison
    ├── test-edge-cases.sh             # Malformed, empty, oversized
    └── fixtures/                      # Test HTML and expected MD
```

## Content Stripping

The following elements are removed before conversion:

| Type | Stripped |
|---|---|
| Tags | `nav`, `header`, `footer`, `aside`, `script`, `style`, `noscript`, `iframe` |
| Classes | `sidebar`, `widget`, `ad`, `advertisement`, `navigation`, `menu`, `breadcrumb` |
| ARIA roles | `navigation`, `banner`, `contentinfo`, `complementary` |

## Response Headers

When `Accept: text/markdown` is present:

| Header | Value |
|---|---|
| `Content-Type` | `text/markdown; charset=utf-8` |
| `Vary` | `Accept` |
| `x-markdown-converter` | `markdown-for-agents/0.1.0` |
| `x-markdown-tokens` | `body-embedded` |

The actual token count is embedded as the last line of the body: `<!-- mfa-meta:tokens=N -->`

## Architecture (Phase 1)

Uses `mod_ext_filter` + PHP-CLI:

1. `SetEnvIfNoCase` detects `Accept: text/markdown` → sets `WANTS_MARKDOWN` env var
2. `ExtFilterDefine` defines the filter with `enableenv=WANTS_MARKDOWN` + `intype=text/html`
3. `AddOutputFilterByType` inserts the filter for `text/html` responses only
4. The filter pipes HTML through the PHP converter and returns Markdown
5. Response headers are set via `Header` directives conditioned on `WANTS_MARKDOWN`

Phase 2 will replace the PHP converter with a native C Apache module for production performance.

## License

MIT
