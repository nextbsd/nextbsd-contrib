#!/bin/sh
# nextbsd-trim.sh <lz4-1.10.0.tar.gz> <dest>   (dest: src/lz4/dist)
# Verify the upstream release tarball (lz4/lz4's release asset), then copy
# the library tree into dest. Only liblz4 is built. Everything in lib/ is
# BSD-2-Clause; the GPL-2.0 command-line programs, tests and examples outside
# it are left out. Re-run on each update (bump VERSION and SHA256 here and in
# NEXTBSD.md).
set -eu
TARBALL=${1:?usage: nextbsd-trim.sh <lz4-VERSION.tar.gz> <dest>}
DEST=${2:?usage: nextbsd-trim.sh <lz4-VERSION.tar.gz> <dest>}
VERSION=1.10.0
SHA256=537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b

if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for $TARBALL: $got" >&2; exit 1; }

mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xzf "$TARBALL"
SRC="$TMP/lz4-$VERSION"
[ -f "$SRC/lib/Makefile" ] || { echo "no lib/Makefile in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
cd "$SRC"
{
    # The top-level LICENSE (which says lib/ is BSD-2-Clause), README.md, NEWS,
    # Makefile.inc (lib/Makefile includes it for the platform settings), then
    # lib/ in full minus the Windows dll/ directory.
    printf '%s\n' LICENSE README.md NEWS Makefile.inc
    find lib -type f ! -path 'lib/dll/*'
} | sort | while IFS= read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$f" "$DEST/$f"
done
echo "trimmed lz4 $VERSION into $DEST: $(find "$DEST" -type f | wc -l) files"
