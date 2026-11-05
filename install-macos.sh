#!/usr/bin/env bash
# ccccc — install the classic-web proxy as a launchd agent (macOS).
# The adapted config is checked before the first start. The non-loopback
# refusal probe runs when an IPv4 address is available. Rollback commands are
# printed after a service start attempt and on success; earlier pre-start
# failures exit with an error and no rollback output.
set -euo pipefail

CADDY_VERSION=2.11.2
LISTEN_PORT=8851
KIT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DATA_DIR=${CCCC_DATA_DIR:-"$HOME/.local/share/ccccc"}
AGENTS_DIR="$HOME/Library/LaunchAgents"
LABEL=sh.ccccc.web
PLIST="$AGENTS_DIR/$LABEL.plist"
UPSTREAM_PORT=${CCCC_UPSTREAM_PORT:-8848}

log() { printf '== %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

sha256_verify() { # <file> <expected-hash>
	if command -v sha256sum >/dev/null 2>&1; then
		printf '%s  %s\n' "$2" "$1" | sha256sum -c - >/dev/null
	else
		printf '%s  %s\n' "$2" "$1" | shasum -a 256 -c - >/dev/null
	fi
}

port_reachable() { # <host> <port>: succeeds when a TCP connection is accepted
	(exec 3<>"/dev/tcp/$1/$2") 2>/dev/null
}

non_loopback_ip() {
	ifconfig 2>/dev/null |
		awk '/inet / && $2 != "127.0.0.1" { print $2; exit }' || true
}

assert_listeners() { # <adapted.json>: every listener must be 127.0.0.1:8851
	local matches match
	matches=$(tr -d '[:space:]' <"$1" | grep -o '"listen":\[[^]]*\]' || true)
	[ -n "$matches" ] || die "caddy adapt produced no listeners"
	while IFS= read -r match; do
		[ "$match" = '"listen":["127.0.0.1:8851"]' ] ||
			die "unexpected listener in adapted config: $match"
	done <<<"$matches"
	log "adapted config: every listener is 127.0.0.1:8851"
}

print_rollback() {
	cat <<EOF

Rollback the ccccc service integration (the cccc server itself was not changed). This does not restore Caddy files that existed before the installer ran.
  launchctl bootout gui/$(id -u)/$LABEL
  rm -f '$PLIST'
  rm -f '$DATA_DIR/Caddyfile'
  # optional full removal:
  # rm -rf '$DATA_DIR'
EOF
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

log "installing ccccc into $DATA_DIR (upstream port $UPSTREAM_PORT)"

[ -f "$DATA_DIR/web46/index.html" ] ||
	die "bundle missing at $DATA_DIR/web46 — run ./build-bundle.sh first, then re-run this script"

# Caddy: download the pinned release for this platform and verify it.
case $(uname -m) in
x86_64) platform=mac_amd64 ;;
arm64) platform=mac_arm64 ;;
*) die "unsupported architecture: $(uname -m)" ;;
esac
asset="caddy_${CADDY_VERSION}_${platform}.tar.gz"
expected=$(awk -v a="$asset" '$2 == a { print $1 }' "$KIT_DIR/caddy.sha256")
[ -n "$expected" ] || die "no pinned hash for $asset in caddy.sha256"
if [ ! -x "$DATA_DIR/bin/caddy" ] ||
	! "$DATA_DIR/bin/caddy" version 2>/dev/null | grep -q "v${CADDY_VERSION}"; then
	log "downloading Caddy v${CADDY_VERSION} ($platform)"
	curl -fsSL -o "$tmp/$asset" \
		"https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/$asset"
	sha256_verify "$tmp/$asset" "$expected"
	mkdir -p "$DATA_DIR/bin"
	tar -xzf "$tmp/$asset" -C "$tmp" caddy
	install -m 0755 "$tmp/caddy" "$DATA_DIR/bin/caddy"
	xattr -dr com.apple.quarantine "$DATA_DIR/bin/caddy" 2>/dev/null || true
fi

cp "$KIT_DIR/LICENSE.caddy" "$KIT_DIR/NOTICE.caddy" "$DATA_DIR/bin/"
cp "$KIT_DIR/Caddyfile" "$DATA_DIR/Caddyfile"
export CCCC_UPSTREAM_PORT=$UPSTREAM_PORT
export CCCC_WEB_ROOT=$DATA_DIR/web46

# Pre-start check 1/2: adapt the config and assert the listeners.
log "pre-start check 1/2: adapted config listeners"
"$DATA_DIR/bin/caddy" adapt --config "$DATA_DIR/Caddyfile" --adapter caddyfile \
	>"$tmp/adapted.json"
assert_listeners "$tmp/adapted.json"

# Pre-start check 2/2: port 8851 must be refused on a non-loopback address.
ext_ip=$(non_loopback_ip)
log "pre-start check 2/2: non-loopback refusal on port $LISTEN_PORT"
if [ -n "$ext_ip" ]; then
	if port_reachable "$ext_ip" "$LISTEN_PORT"; then
		die "port $LISTEN_PORT is already reachable at $ext_ip before start — stop that listener first; service start was not attempted"
	fi
	log "refused at $ext_ip:$LISTEN_PORT (good)"
else
	log "no non-loopback IPv4 address on this host; external probe skipped"
fi

# First start.
mkdir -p "$AGENTS_DIR"
cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$DATA_DIR/bin/caddy</string>
		<string>run</string>
		<string>--config</string>
		<string>$DATA_DIR/Caddyfile</string>
		<string>--adapter</string>
		<string>caddyfile</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>CCCC_UPSTREAM_PORT</key>
		<string>$UPSTREAM_PORT</string>
		<key>CCCC_WEB_ROOT</key>
		<string>$DATA_DIR/web46</string>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$DATA_DIR/caddy.log</string>
	<key>StandardErrorPath</key>
	<string>$DATA_DIR/caddy.log</string>
</dict>
</plist>
EOF

log "starting $LABEL"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST"; then
	print_rollback
	die "launchctl bootstrap failed; see $DATA_DIR/caddy.log"
fi
for _ in 1 2 3 4 5; do
	lsof -nP -iTCP:"$LISTEN_PORT" -sTCP:LISTEN >/dev/null 2>&1 && break
	sleep 1
done

log "post-start verification"
if ! port_reachable 127.0.0.1 "$LISTEN_PORT"; then
	print_rollback
	die "nothing is listening on 127.0.0.1:$LISTEN_PORT after start"
fi
if [ -n "$ext_ip" ] && port_reachable "$ext_ip" "$LISTEN_PORT"; then
	print_rollback
	die "port $LISTEN_PORT became reachable at $ext_ip after start — stop the service using the rollback commands above"
fi
listeners=$(lsof -nP -iTCP:"$LISTEN_PORT" -sTCP:LISTEN 2>/dev/null |
	awk 'NR > 1 { print $9 }' | sort -u || true)
log "listeners: ${listeners:-none reported}"
if command -v curl >/dev/null 2>&1; then
	code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 \
		"http://127.0.0.1:$LISTEN_PORT/" || true)
	[ "$code" = 200 ] || log "warning: loopback HTTP returned '$code' instead of 200"
fi
if [ -n "$ext_ip" ]; then
	log "refused at $ext_ip:$LISTEN_PORT after start (good)"
fi

print_rollback
log "done: open http://127.0.0.1:$LISTEN_PORT/ (share it only through an authenticated tunnel)"
