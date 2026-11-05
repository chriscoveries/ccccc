#!/usr/bin/env bash
# Build web/dist from the official cccc tag v0.4.46 with node, install it
# into the ccccc data directory, and print sha256 of what was produced.
set -euo pipefail

TAG=v0.4.46
REPO=https://github.com/ChesterRa/cccc.git
KIT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SRC_DIR=${1:-"$KIT_DIR/cccc-src"}
DATA_DIR=${CCCC_DATA_DIR:-"${XDG_DATA_HOME:-$HOME/.local/share}/ccccc"}
OUT_TAR="$KIT_DIR/web46-dist.tar.gz"

log() { printf '== %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() { # <file>, or "-" for stdin
	if command -v sha256sum >/dev/null 2>&1; then
		if [ "$1" = "-" ]; then sha256sum; else sha256sum "$1"; fi
	else
		if [ "$1" = "-" ]; then shasum -a 256; else shasum -a 256 "$1"; fi
	fi
}

command -v git >/dev/null 2>&1 || die "git is required"
command -v node >/dev/null 2>&1 || die "node is required"
command -v npm >/dev/null 2>&1 || die "npm is required"

node - <<'NODE' || die "node version check failed"
const [M, m] = process.versions.node.split(".").map(Number);
const ok = (M === 22 && m >= 18) || M > 24 || (M === 24 && m >= 11);
if (!ok) {
	console.error(`node ${process.versions.node} does not satisfy ^22.18.0 || >=24.11.0`);
	process.exit(1);
}
NODE

if [ ! -d "$SRC_DIR/.git" ]; then
	log "cloning cccc tag $TAG"
	git clone --depth 1 --branch "$TAG" "$REPO" "$SRC_DIR"
else
	current=$(git -C "$SRC_DIR" describe --tags --exact-match 2>/dev/null || true)
	[ "$current" = "$TAG" ] ||
		die "$SRC_DIR exists but is not at $TAG (found: ${current:-none}); remove it or pass another path"
fi

log "building web/dist"
(
	cd "$SRC_DIR/web"
	npm ci
	npm run build
)
[ -f "$SRC_DIR/web/dist/index.html" ] ||
	die "the build produced no web/dist/index.html"
for name in LICENSE.cccc NOTICE.cccc; do
	[ -f "$KIT_DIR/$name" ] || die "missing distribution file $name"
	if [ -e "$SRC_DIR/web/dist/$name" ] || [ -L "$SRC_DIR/web/dist/$name" ]; then
		die "bundle conflicts with reserved distribution file $name"
	fi
done

log "creating $OUT_TAR"
tar -czf "$OUT_TAR" -C "$SRC_DIR/web/dist" . -C "$KIT_DIR" LICENSE.cccc NOTICE.cccc
printf 'archive sha256 (%s): ' "$(basename "$OUT_TAR")"
sha256_of "$OUT_TAR" | awk '{ print $1 }'
manifest=$(
	{
		(cd "$SRC_DIR/web/dist" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do sha256_of "$f"; done)
		(cd "$KIT_DIR" && sha256_of LICENSE.cccc && sha256_of NOTICE.cccc)
	} | LC_ALL=C sort | sha256_of - | awk '{ print $1 }'
)
printf 'manifest sha256 (paths + file hashes): %s\n' "$manifest"

log "installing bundle into $DATA_DIR/web46"
mkdir -p "$DATA_DIR" || die "cannot create data directory"
mkdir "$DATA_DIR/web46" || die "$DATA_DIR/web46 already exists; choose a fresh CCCC_DATA_DIR"
cp -R "$SRC_DIR/web/dist/." "$DATA_DIR/web46/"
cp "$KIT_DIR/LICENSE.cccc" "$KIT_DIR/NOTICE.cccc" "$DATA_DIR/web46/"
[ -f "$DATA_DIR/web46/index.html" ] || die "bundle copy failed"
log "done: run ./install-linux.sh or ./install-macos.sh next"
