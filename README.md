# markdown-for-agents

Apache output filter that converts HTML to Markdown via `Accept: text/markdown` content negotiation. When an AI agent (or any client) sends `Accept: text/markdown`, HTML responses are automatically converted to clean Markdown — zero changes to the origin site.

**Try it now:**

```bash
curl -s -H 'Accept: text/markdown' https://littleluz.net/wordpress/
```

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

- **Zero overhead for normal requests** — the filter only activates when `Accept: text/markdown` is present
- **Semantic content extraction** — prefers `<article>` / `<main>` / `[role="main"]`, falls back to tag/class/ARIA stripping
- **Safe fallback** — on any error, original HTML is returned unchanged
- **Token metadata** — `<!-- mfa-meta:tokens=N html-tokens=N reduction=N% extraction=METHOD -->` appended to every response

## Installation

There are two installation modes: **cPanel/WHM plugin** (for hosting providers) and **standalone** (for any Apache server).

### cPanel/WHM Plugin (recommended for shared hosting)

The plugin gives WHM admins a management page and cPanel customers a toggle to enable/disable markdown conversion for their sites.

```bash
VERSION=0.2.0
curl -sL https://github.com/blehman-godaddy/markdown-for-agents/releases/download/v${VERSION}/markdown-for-agents-${VERSION}-cpanel-plugin.tar.gz | tar xz
cd markdown-for-agents-${VERSION}
sudo bash cpanel/install-plugin.sh
```

**What the plugin installs:**

| Component | Location |
|---|---|
| Converter + PHP deps | `/opt/markdown-for-agents/` |
| Global Apache config (ExtFilterDefine) | `/etc/apache2/conf.d/markdown-for-agents.conf` |
| WHM admin page | WHM > Plugins > Markdown for Agents |
| cPanel customer toggle | cPanel > Advanced > Markdown for Agents |

**How it works:**

- The **WHM admin page** shows global install status and a table of all accounts with enable/disable controls
- The **cPanel toggle** lets customers enable markdown conversion for their own account
- When enabled, per-account Apache directives are written to `/etc/apache2/conf.d/userdata/{std,ssl}/2_4/<username>/markdown-for-agents.conf`
- WHM Feature Manager controls which hosting packages have access to the toggle

**Uninstall:**

```bash
sudo bash cpanel/uninstall-plugin.sh
```

### Standalone Install (any Apache server)

For non-cPanel servers or single-site setups:

```bash
VERSION=0.2.0
curl -sL https://github.com/blehman-godaddy/markdown-for-agents/releases/download/v${VERSION}/markdown-for-agents-${VERSION}.tar.gz | tar xz
cd markdown-for-agents-${VERSION}
sudo bash install/install.sh
```

The standalone installer runs in three phases:

1. **Preflight** — checks root, PHP version/extensions, Apache paths, vendor/, mod_ext_filter
2. **Auto-fix** — installs missing dependencies (e.g. `ea-apache24-mod_ext_filter`) via yum
3. **Install** — deploys files, configures Apache, runs configtest, reloads, smoke tests

**Preflight check (dry run):**

```bash
sudo bash install/install.sh --check
```

**Uninstall:**

```bash
sudo bash install/uninstall.sh
```

### Build from source

```bash
git clone https://github.com/blehman-godaddy/markdown-for-agents.git
cd markdown-for-agents
make dist            # standalone tarball
make cpanel-plugin   # cPanel plugin tarball
```

### Prerequisites

- Apache 2.4 with `mod_ext_filter`, `mod_setenvif`, `mod_headers`
- PHP 8.0+ with `dom` and `xml` extensions

## Test

```bash
# Normal request — unchanged HTML:
curl -sI http://localhost/ | grep Content-Type
# Content-Type: text/html

# Markdown request — converted:
curl -s -H "Accept: text/markdown" http://localhost/

# Response headers:
curl -sI -H "Accept: text/markdown" http://localhost/
# Content-Type: text/markdown; charset=utf-8
# Vary: Accept
# x-markdown-converter: markdown-for-agents/0.2.0
# x-markdown-tokens: body-embedded
```

### Standalone converter test (no Apache)

```bash
composer install
echo '<html><body><nav>Menu</nav><h1>Title</h1><p>Content here.</p><footer>Footer</footer></body></html>' \
  | php bin/html2markdown.php
# # Title
#
# Content here.
#
# <!-- mfa-meta:tokens=6 html-tokens=25 reduction=76% extraction=fallback -->
```

### Run test suite

```bash
./tests/run-tests.sh
```

## Content Extraction

The converter uses a priority chain to find the main content:

1. **`<article>`** (single) — most specific content container (blog posts, articles)
2. **`<main>`** — page primary content area
3. **`[role="main"]`** — ARIA landmark
4. **Fallback** — strips non-content elements from the full page body

The `extraction=` field in the metadata shows which method was used.

### Fallback stripping rules

When no semantic container is found, these elements are removed:

| Type | Stripped |
|---|---|
| Tags | `nav`, `header`, `footer`, `aside`, `script`, `style`, `noscript`, `iframe` |
| Classes | `sidebar`, `widget`, `ad`, `advertisement`, `navigation`, `menu`, `breadcrumb` |
| ARIA roles | `navigation`, `banner`, `contentinfo`, `complementary` |
| UI elements | skip-links (`skip-link`, `screen-reader-text`), scroll-to-top (`scroll-to-top`, `back-to-top`) |

Class matching uses word-boundary logic to avoid false positives like `"ad"` matching `"has-global-padding"`.

## Response Headers

When `Accept: text/markdown` is present:

| Header | Value |
|---|---|
| `Content-Type` | `text/markdown; charset=utf-8` |
| `Vary` | `Accept` |
| `x-markdown-converter` | `markdown-for-agents/0.2.0` |
| `x-markdown-tokens` | `body-embedded` |

Token metadata is the last line of the response body:

```
<!-- mfa-meta:tokens=74 html-tokens=16596 reduction=100% extraction=article -->
```

## Architecture

### Standalone mode

All Apache directives in a single config. `mod_ext_filter` pipes HTML through `html2markdown-wrapper.sh` → `html2markdown.php`.

### cPanel plugin mode

The Apache config is split into two parts:

**Global** (installed once, server-wide):
- Module loader (`mod_ext_filter`, `mod_setenvif`, `mod_headers`)
- `ExtFilterDefine html2md` — defines the filter (server config context, cannot be per-virtualhost)

**Per-account** (toggled by customer via cPanel):
- `SetEnvIfNoCase Accept "text/markdown" WANTS_MARKDOWN`
- `AddOutputFilter` for static files + `SetOutputFilter` in `<If>` for proxied PHP
- Response `Header` directives

This split is required because `ExtFilterDefine` is a server-config-only directive — it cannot go inside `<VirtualHost>` blocks. The per-account directives are managed via cPanel's userdata include system.

## Project Structure

```
markdown-for-agents/
├── VERSION
├── Makefile                              # make dist / make cpanel-plugin
├── bin/
│   ├── html2markdown.php                 # Core converter (stdin → stdout)
│   └── html2markdown-wrapper.sh          # Bash wrapper for mod_ext_filter
├── conf/
│   ├── 850-markdown-for-agents.conf      # Module loader
│   ├── markdown-for-agents.conf          # Standalone combined config
│   ├── markdown-for-agents-global.conf   # cPanel: server-wide ExtFilterDefine
│   └── markdown-for-agents-account.conf  # cPanel: per-account template
├── lib/
│   └── mfa-common.sh                     # Shared shell functions
├── install/
│   ├── install.sh                        # Standalone installer (--check for dry run)
│   └── uninstall.sh                      # Standalone removal
├── cpanel/
│   ├── install-plugin.sh                 # cPanel plugin installer
│   ├── uninstall-plugin.sh               # cPanel plugin removal
│   ├── scripts/                          # Account management scripts
│   │   ├── mfa-global-install.sh
│   │   ├── mfa-global-uninstall.sh
│   │   ├── mfa-account-enable.sh
│   │   ├── mfa-account-disable.sh
│   │   └── mfa-account-status.sh
│   ├── whm/                              # WHM admin plugin
│   │   ├── markdown_for_agents.conf      # AppConfig registration
│   │   └── cgi/addon_markdown_for_agents.cgi
│   └── cpanel/                           # cPanel customer plugin
│       ├── install.json                  # dynamicui registration
│       └── markdown_for_agents/index.live.php
└── tests/
    ├── run-tests.sh
    ├── test-passthrough.sh
    ├── test-markdown-response.sh
    ├── test-headers.sh
    ├── test-content-quality.sh
    ├── test-edge-cases.sh
    ├── test-config-split.sh
    ├── test-cpanel-scripts.sh
    └── fixtures/
```

## License

MIT
