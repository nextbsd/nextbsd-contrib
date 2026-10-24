#!/bin/sh
# nextbsd-trim.sh <zstd-1.5.7.tar.gz> <dest>   (dest: src/zstd/dist)
# Verify the upstream release tarball (facebook/zstd's release asset, not
# GitHub's tag archive), then copy the library tree and the licences into
# dest. Only libzstd is built; the zstd programs are left out (base already
# has /usr/bin/zstd). Re-run on each update (bump VERSION and SHA256 here and
# in NEXTBSD.md).
set -eu
TARBALL=${1:?usage: nextbsd-trim.sh <zstd-VERSION.tar.gz> <dest>}
DEST=${2:?usage: nextbsd-trim.sh <zstd-VERSION.tar.gz> <dest>}
VERSION=1.5.7
SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3

if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for $TARBALL: $got" >&2; exit 1; }

mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xzf "$TARBALL"
SRC="$TMP/zstd-$VERSION"
[ -f "$SRC/lib/Makefile" ] || { echo "no lib/Makefile in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
cd "$SRC"
{
    # The licences (BSD and GPLv2; NextBSD takes the BSD one), the readme and
    # changelog, then lib/ in full: its Makefile and libzstd.mk, the sources,
    # the public headers and libzstd.pc.in. The Windows dll/ directory and the
    # Buck build file are left out.
    printf '%s\n' LICENSE COPYING README.md CHANGELOG
    find lib -type f ! -path 'lib/dll/*' ! -name BUCK
} | sort | while IFS= read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$f" "$DEST/$f"
done
echo "trimmed zstd $VERSION into $DEST: $(find "$DEST" -type f | wc -l) files"
