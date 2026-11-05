#!/usr/bin/env bash
# ccccc — install the classic-web proxy as a user systemd unit (Linux).
# The loopback refusal check runs BEFORE the first start; the rollback is
# printed at the end whether the install succeeded or not.
set -euo pipefail

CADDY_VERSION=2.11.2
LISTEN_PORT=8851
KIT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DATA_DIR=${CCCC_DATA_DIR:-"${XDG_DATA_HOME:-$HOME/.local/share}/ccccc"}
UNIT_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
UNIT_NAME=ccccc.service
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
	ip -4 route get 1.1.1.1 2>/dev/null |
		awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }' || true
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

Rollback (nothing else was changed; your cccc server was not touched):
  systemctl --user disable --now $UNIT_NAME
  rm -f '$UNIT_DIR/$UNIT_NAME'
  systemctl --user daemon-reload
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
x86_64) platform=linux_amd64 ;;
aarch64 | arm64) platform=linux_arm64 ;;
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
fi

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
		die "port $LISTEN_PORT is already reachable at $ext_ip before start — stop that listener first; nothing was installed"
	fi
	log "refused at $ext_ip:$LISTEN_PORT (good)"
else
	log "no non-loopback IPv4 address on this host; external probe skipped"
fi

# First start.
mkdir -p "$UNIT_DIR"
cat >"$UNIT_DIR/$UNIT_NAME" <<EOF
[Unit]
Description=ccccc classic web proxy (loopback only)

[Service]
Type=simple
ExecStart="$DATA_DIR/bin/caddy" run --config "$DATA_DIR/Caddyfile" --adapter caddyfile
Environment="CCCC_UPSTREAM_PORT=$UPSTREAM_PORT"
Environment="CCCC_WEB_ROOT=$DATA_DIR/web46"
Restart=on-failure
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=default.target
EOF

log "starting $UNIT_NAME"
systemctl --user daemon-reload
if ! systemctl --user enable --now "$UNIT_NAME"; then
	print_rollback
	die "failed to start $UNIT_NAME; see: journalctl --user -u $UNIT_NAME"
fi
for _ in 1 2 3 4 5; do
	systemctl --user is-active --quiet "$UNIT_NAME" && break
	sleep 1
done
if ! systemctl --user is-active --quiet "$UNIT_NAME"; then
	print_rollback
	die "$UNIT_NAME did not become active; see: journalctl --user -u $UNIT_NAME"
fi

log "post-start verification"
if ! port_reachable 127.0.0.1 "$LISTEN_PORT"; then
	print_rollback
	die "nothing is listening on 127.0.0.1:$LISTEN_PORT after start"
fi
if [ -n "$ext_ip" ] && port_reachable "$ext_ip" "$LISTEN_PORT"; then
	print_rollback
	die "port $LISTEN_PORT became reachable at $ext_ip after start — stopped for safety"
fi
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
