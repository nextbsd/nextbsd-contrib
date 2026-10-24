#!/bin/sh
# nextbsd-trim.sh <squashfs-tools-ng-1.3.2.tar.xz> <dest>   (dest: src/squashfs-tools-ng/dist)
# Verify the upstream release tarball (from https://infraroot.at/pub/squashfs/,
# which carries the generated configure; GitHub's tag archive does not), then
# copy the release into dest in full. Nothing is left out: the tree is small,
# and config.status writes files under tests/ that it needs present. Re-run on
# each update (bump VERSION and SHA256 here and in NEXTBSD.md).
set -eu
TARBALL=${1:?usage: nextbsd-trim.sh <squashfs-tools-ng-VERSION.tar.xz> <dest>}
DEST=${2:?usage: nextbsd-trim.sh <squashfs-tools-ng-VERSION.tar.xz> <dest>}
VERSION=1.3.2
SHA256=0d907ac3e735c351e47c867fb51d94bffa3b05fb95bec01f31e848b7c44215a9

if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for $TARBALL: $got" >&2; exit 1; }

mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xJf "$TARBALL"
SRC="$TMP/squashfs-tools-ng-$VERSION"
[ -f "$SRC/configure" ] || { echo "no configure in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
(cd "$SRC" && tar -cf - .) | (cd "$DEST" && tar -xf -)
echo "copied squashfs-tools-ng $VERSION into $DEST: $(find "$DEST" -type f | wc -l) files"
