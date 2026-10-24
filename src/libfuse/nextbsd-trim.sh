#!/bin/sh
# nextbsd-trim.sh <fuse-3.18.3.tar.gz> <dest>   (dest: src/libfuse/dist)
# Verify the upstream release tarball (libfuse/libfuse's release asset), then
# copy the library and its meson build into dest. Only libfuse3 is built:
# on FreeBSD the helper programs are never built (meson.build skips util/ on
# *bsd; the kernel side mounts through base's /sbin/mount_fusefs), and the
# examples and tests are switched off. Re-run on each update (bump VERSION and
# SHA256 here and in NEXTBSD.md).
set -eu
TARBALL=${1:?usage: nextbsd-trim.sh <fuse-VERSION.tar.gz> <dest>}
DEST=${2:?usage: nextbsd-trim.sh <fuse-VERSION.tar.gz> <dest>}
VERSION=3.18.3
SHA256=bcd19582c5e30f7fe45dd86a5540e998590aa01903afc7ebcbeea6c8ac5421ee

if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for $TARBALL: $got" >&2; exit 1; }

mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xzf "$TARBALL"
SRC="$TMP/fuse-$VERSION"
[ -f "$SRC/meson.build" ] || { echo "no meson.build in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
cd "$SRC"
{
    # The top-level meson build and its options, the licences (LICENSE says
    # lib/ and include/ are LGPL-2.1, the rest GPL-2.0), README.md, AUTHORS,
    # ChangeLog.rst, then lib/ and include/ in full.
    printf '%s\n' meson.build meson_options.txt LICENSE LGPL2.txt GPL2.txt \
        README.md AUTHORS ChangeLog.rst
    find lib include -type f
} | sort | while IFS= read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$f" "$DEST/$f"
done
echo "trimmed libfuse $VERSION into $DEST: $(find "$DEST" -type f | wc -l) files"
