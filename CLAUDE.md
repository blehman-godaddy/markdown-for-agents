# Project: markdown-for-agents

Apache output filter that converts HTML to Markdown via `Accept: text/markdown` content negotiation on cPanel/WHM with EasyApache 4.

## Architecture

- `mod_ext_filter` pipes HTML through `bin/html2markdown-wrapper.sh` → `bin/html2markdown.php`
- PHP uses `league/html-to-markdown` for conversion
- XPath strips non-content elements (nav, sidebar, ads, etc.) before conversion
- Token metadata embedded as HTML comment: `<!-- mfa-meta:tokens=N html-tokens=N reduction=N% -->`

## Key files

- `VERSION` — single source of version string
- `Makefile` — `make dist` builds self-contained tarball, `make clean` removes dist/
- `bin/html2markdown.php` — core converter (stdin → stdout)
- `bin/html2markdown-wrapper.sh` — bash wrapper for mod_ext_filter, `__PHP_BIN__` placeholder replaced by installer
- `conf/markdown-for-agents.conf` — Apache config (SetEnvIf + ExtFilterDefine + filter insertion + headers)
- `conf/850-markdown-for-agents.conf` — module loader (mod_ext_filter, mod_setenvif, mod_headers)
- `install/install.sh` — three-phase installer: preflight → auto-fix → install. Supports `--check` dry-run
- `install/uninstall.sh` — clean removal
- `.github/workflows/release.yml` — builds tarball on `v*` tags

## Deployment target

- Server: WHM/cPanel with EasyApache 4, Apache 2.4.66
- PHP: ea-php82 at `/opt/cpanel/ea-php82/root/usr/bin/php`
- PHP handled via php-fpm proxy (ProxyPassMatch), NOT mod_php
- Install dir: `/opt/markdown-for-agents/`
- Apache config: `/etc/apache2/conf.d/markdown-for-agents.conf`
- Test site: https://littleluz.net/wordpress/

## Critical cPanel/EA4 gotchas (learned the hard way)

1. **AddOutputFilterByType is broken with mod_ext_filter on cPanel** — creates `BYTYPE:html2md` filter name that mod_ext_filter can't resolve. Error: `AH01459: couldn't find definition of filter 'BYTYPE:html2md'`

2. **AddOutputFilter with extensions misses proxied PHP** — cPanel uses php-fpm via ProxyPassMatch, so `.php` extension matching doesn't apply to the response. WordPress URLs like `/wordpress/` have no extension at all.

3. **SetOutputFilter replaces the entire filter chain** — breaks proxied PHP responses (empty content). Only safe inside `<If>` where it only affects markdown requests.

4. **FilterProvider/FilterChain doesn't bridge to mod_ext_filter** — despite Apache docs claiming it works. Error: `couldn't find definition of filter 'markdown'`

5. **Current working approach**: `AddOutputFilter` for static files + `<If "%{HTTP:Accept} =~ m|text/markdown|"> SetOutputFilter html2md </If>` for proxied PHP. The `m|...|` pipe-delimiter regex avoids backslash escaping issues in heredocs.

6. **Scripts lose execute bits on upload/extraction** — some servers strip permissions on `tar xz`. README uses `sudo bash install/install.sh` instead of `sudo ./install/install.sh`.

7. **Private repo tarball downloads need auth** — `curl -sL` to GitHub releases may get HTML redirect instead of the file. Use `gh` CLI or add auth header.

## XPath class stripping

Uses word-boundary matching, NOT substring matching. The XPath checks for:
- Standalone class: `" keyword "` (space-bounded)
- Hyphenated prefix: `" keyword-"` (catches `ad-banner`)
- Hyphenated suffix: `"-keyword-"` (catches `sidebar-widget`)

This prevents false positives like `"ad"` matching `"has-global-padding"` which stripped all WordPress content.

Keywords: sidebar, widget, ad, advertisement, navigation, menu, breadcrumb

## Testing

- `./tests/run-tests.sh` — runs 5 test scripts against the PHP converter (no Apache needed)
- Test fixtures in `tests/fixtures/` with expected output in `tests/fixtures/expected/`
- `install/install.sh --check` — dry-run preflight on server

## Release process

1. Update `VERSION` file
2. `git commit && git push`
3. `git tag v{VERSION} && git push origin v{VERSION}`
4. GitHub Actions builds tarball automatically
5. Deploy: `curl -sL .../releases/download/v{VERSION}/markdown-for-agents-{VERSION}.tar.gz | tar xz && cd markdown-for-agents-{VERSION} && sudo bash install/install.sh`

## Current version: v0.1.4
