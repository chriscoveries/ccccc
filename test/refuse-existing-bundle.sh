#!/usr/bin/env bash
# Regression: build-bundle.sh must refuse to overwrite an existing bundle
# directory and leave the installed files byte-identical. The clone and npm
# phases are stubbed so this runs without a real build; the install block
# runs for real against a copy of the captured v0.4.46 bundle in
# test/fixtures/web46.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
KIT=$(cd -- "$HERE/.." && pwd)
FIXTURE=$HERE/fixtures/web46

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -f "$FIXTURE/index.html" ] || fail "missing captured bundle fixture at $FIXTURE"

sha() { # stdin
	if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
}
manifest() { # <dir> -> hash of every file's hash, paths sorted
	cd "$1" || exit 1
	find . -type f | LC_ALL=C sort | while IFS= read -r f; do sha <"$f"; done | sha
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Stub git/node/npm: reach the install block without cloning or building.
mkdir "$TMP/bin"
cat > "$TMP/bin/git" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = clone ]; then
	dst=""
	for arg in "$@"; do dst=$arg; done
	mkdir -p "$dst/.git" "$dst/web/dist"
	printf '<!doctype html><title>stub</title>\n' > "$dst/web/dist/index.html"
fi
exit 0
STUB
cat > "$TMP/bin/node" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null || true
exit 0
STUB
cat > "$TMP/bin/npm" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$TMP/bin/git" "$TMP/bin/node" "$TMP/bin/npm"

# Seed an existing installation: a copy of the real captured bundle.
DATA=$TMP/data
mkdir -p "$DATA"
cp -R "$FIXTURE" "$DATA/web46"
[ -f "$DATA/web46/index.html" ] || fail "could not seed the existing bundle"

before=$(manifest "$DATA/web46")

set +e
out=$(PATH="$TMP/bin:$PATH" CCCC_DATA_DIR="$DATA" "$KIT/build-bundle.sh" "$TMP/cccc-src" 2>&1)
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "builder succeeded against an existing bundle"
case "$out" in
	*"already exists; choose a fresh CCCC_DATA_DIR"*) ;;
	*) fail "builder did not report the refusal: $out" ;;
esac

after=$(manifest "$DATA/web46")
[ "$before" = "$after" ] || fail "existing bundle was modified"

printf 'OK: builder refused the existing bundle and left it unchanged\n'
