# ccccc

A standalone, loopback-only proxy kit that puts the classic v0.4.46 cccc Web
look in front of a newer cccc server. Caddy serves the pinned bundle and
reverse-proxies `/api/`, including server-sent events and terminal WebSockets,
to the running cccc web listener without rewriting its forwarded headers.

This kit is not affiliated with, endorsed by, or supported by the upstream
cccc project or its maintainers.

## Security

- **cccc trusts loopback.** A request arriving from 127.0.0.1 may be
  authenticated as the local administrator, so this proxy must bind
  `127.0.0.1` and only `127.0.0.1`. Never bind `0.0.0.0`, a LAN address or a
  tailnet address.
- The Caddyfile's site address is `http://:8851` (empty host, so any Host
  matches a front end that forwards its own hostname) with an explicit
  `bind 127.0.0.1`. A site address alone does not constrain the listening
  interface — the bind is what keeps the socket on loopback. Never remove it.
- The global `servers { trusted_proxies static 127.0.0.1/32 ::1/128 }` lets a
  trusted loopback front end's `X-Forwarded-*` headers pass through to cccc
  unchanged; the live event stream and WebSockets compare the browser's
  Origin against them. There are no `X-Forwarded-For`/`X-Real-IP` overrides.
- Before starting Caddy, each installer validates that the adapted configuration has only `127.0.0.1:8851` and, when a non-loopback IPv4 address is available, checks that port 8851 refuses connections there. It repeats the probe after start when such an address is available. Successful completion and failures after a service start attempt print rollback commands. Earlier pre-start failures exit with an error and no rollback output; Caddy files may already have been written in the data directory.
- Expose the proxy only through an authenticated path (an SSH tunnel, or a
  `tailscale serve` entry) after those checks pass.

## Tested

- A recorded Linux stage trial exercised the classic bundle through the Caddy proxy on cccc v0.4.47: group list/open, live messaging, inbox, actor terminal WebSocket, settings, and the task/context panel. It used a transient Caddy unit, not this kit's `install-linux.sh`.

## Not verified

- The kit's Linux installer, the macOS launchd installer, and macOS runtime behavior have not been verified by the available evidence.

## Limits

- The bundle is old. The v0.4.46 UI against a newer API drifts: screens and
  response shapes are not guaranteed to match, and some views may render
  stale or incomplete data.
- `/api/v1/groups/:id/delegate_contact` was removed upstream after v0.4.46;
  the classic UI's reference to it fails against current servers.
- Only the flows listed under Tested were exercised. Login paths beyond the
  local session were not verified.

## Contents

| File | Purpose |
| --- | --- |
| `Caddyfile` | Proxy config. `{$CCCC_UPSTREAM_PORT}` (your cccc web port) and `{$CCCC_WEB_ROOT}` (bundle directory) are set by the installers. |
| `install-linux.sh` | User systemd unit `ccccc.service`; pre-start loopback refusal check; prints the rollback. |
| `install-macos.sh` | launchd agent `sh.ccccc.web`; same checks; prints the rollback. |
| `build-bundle.sh` | Builds `web/dist` from the official `ChesterRa/cccc` tag `v0.4.46` with node, installs it into the data directory, and prints sha256. |
| `caddy.sha256` | Pinned Caddy 2.11.2 release hashes, one per platform. |
| `LICENSE.cccc`, `LICENSE.caddy` | Verbatim upstream Apache-2.0 license texts at the pinned tags. |
| `NOTICE.cccc`, `NOTICE.caddy` | Kit-supplied attribution and distribution limits for each upstream component. |
| `LICENSE` | This kit's attribution and distribution note. |

Data and logs live in `~/.local/share/ccccc/` (override with
`CCCC_DATA_DIR`); the macOS agent also writes `caddy.log` there.

## Quick start

1. Build the bundle (node `^22.18.0 || >=24.11.0`): `./build-bundle.sh` —
   it prints the sha256 of the archive and of the file manifest it produced.
2. Linux: `CCCC_UPSTREAM_PORT=<your cccc web port> ./install-linux.sh`
   macOS: `CCCC_UPSTREAM_PORT=<your cccc web port> ./install-macos.sh`

   The default port is 8848; confirm your server's listener first
   (`ss -ltn` on Linux, `lsof -nP -iTCP:LISTEN` on macOS).
3. Open `http://127.0.0.1:8851/` directly, or serve it over an authenticated
   tunnel only after the installer's checks pass.

Each installer downloads Caddy 2.11.2 for the host platform, verifies it
against `caddy.sha256`, and prints the rollback commands at the end:

- Linux: `systemctl --user disable --now ccccc.service`, remove
  `~/.config/systemd/user/ccccc.service`, then `systemctl --user daemon-reload`.
- macOS: `launchctl bootout gui/$(id -u)/sh.ccccc.web`, remove
  `~/Library/LaunchAgents/sh.ccccc.web.plist`.

Removing `~/.local/share/ccccc/` completes either rollback; your cccc server
is never modified.

## License

The builder includes `LICENSE.cccc` and `NOTICE.cccc` in the web archive and
installed web directory. The installers put `LICENSE.caddy` and
`NOTICE.caddy` alongside the downloaded Caddy binary. The `NOTICE` files are
kit-supplied attribution: neither pinned upstream tag has a root `NOTICE`.
The captured web ZIP in the regression fixture must accompany the cccc license
and notice if the kit is shared; do not distribute the ZIP by itself.

The web and Caddy binaries include third-party dependencies whose license and
notice requirements have not been inventoried here. Do not distribute the kit
or bundles externally until that inventory and any required notices are complete.
