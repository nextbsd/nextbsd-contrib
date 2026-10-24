#!/bin/sh
# nextbsd-trim.sh <squashfuse-0.6.5.tar.gz> <dest>   (dest: src/squashfuse/dist)
# Verify the upstream release tarball (vasi/squashfuse's release asset, which
# carries the generated configure; GitHub's tag archive does not), then copy
# the release into dest in full. Nothing is left out: the tree is small, and
# config.status writes files under tests/ and ci/ that it needs present.
# Re-run on each update (bump VERSION and SHA256 here and in NEXTBSD.md).
set -eu
TARBALL=${1:?usage: nextbsd-trim.sh <squashfuse-VERSION.tar.gz> <dest>}
DEST=${2:?usage: nextbsd-trim.sh <squashfuse-VERSION.tar.gz> <dest>}
VERSION=0.6.5
SHA256=9ec44b8ee6309e09bdcdeba422edc745e876db16136acacb74ecc7e7131e5763

if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for $TARBALL: $got" >&2; exit 1; }

mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xzf "$TARBALL"
SRC="$TMP/squashfuse-$VERSION"
[ -f "$SRC/configure" ] || { echo "no configure in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
(cd "$SRC" && tar -cf - .) | (cd "$DEST" && tar -xf -)
echo "copied squashfuse $VERSION into $DEST: $(find "$DEST" -type f | wc -l) files"
