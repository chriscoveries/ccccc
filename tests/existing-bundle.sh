#!/usr/bin/env bash
# The fixture archive is a copy of the classic v0.4.46 web bundle.
# Stub only build commands so this exercises the builder's real install block.
set -euo pipefail

kit=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/kit" "$tmp/bin" "$tmp/src/.git" "$tmp/src/web/dist" "$tmp/data/web46"
mkdir "$tmp/captured"
unzip -q "$kit/tests/fixtures/web46.zip" -d "$tmp/captured"
cmp "$kit/tests/fixtures/web46/index.html" "$tmp/captured/index.html"
cmp "$kit/tests/fixtures/web46/logo.svg" "$tmp/captured/logo.svg"
cp "$kit/build-bundle.sh" "$tmp/kit/build-bundle.sh"
cp "$kit/LICENSE.cccc" "$kit/NOTICE.cccc" "$tmp/kit/"
cp -R "$tmp/captured/." "$tmp/src/web/dist/"
cp -R "$tmp/captured/." "$tmp/data/web46/"
printf '#!/usr/bin/env bash\nprintf "v0.4.46\\n"\n' >"$tmp/bin/git"
printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/bin/node"
printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/bin/npm"
chmod +x "$tmp/bin/git" "$tmp/bin/node" "$tmp/bin/npm"

if PATH="$tmp/bin:$PATH" CCCC_DATA_DIR="$tmp/data" \
	bash "$tmp/kit/build-bundle.sh" "$tmp/src" >"$tmp/output" 2>&1; then
	printf 'builder unexpectedly replaced the existing bundle\n' >&2
	exit 1
fi
grep -F 'already exists; choose a fresh CCCC_DATA_DIR' "$tmp/output" >/dev/null
diff -r "$tmp/captured" "$tmp/data/web46"
printf 'Existing bundle refused and unchanged.\n'

# The successful path must carry the exact license and notice in both outputs.
PATH="$tmp/bin:$PATH" CCCC_DATA_DIR="$tmp/fresh" \
	bash "$tmp/kit/build-bundle.sh" "$tmp/src" >"$tmp/output" 2>&1
for name in LICENSE.cccc NOTICE.cccc; do
	cmp "$kit/$name" "$tmp/fresh/web46/$name"
	tar -xOzf "$tmp/kit/web46-dist.tar.gz" "$name" | cmp - "$kit/$name"
done
printf 'Bundle archive and installed copy contain both attribution files.\n'
