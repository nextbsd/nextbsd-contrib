#!/bin/sh
# nextbsd-trim.sh <zsh-completions-0.36.0.tar.gz> <dest>   (dest: src/zsh-completions/dist)
# Verify the upstream release tarball (GitHub's archive of tag 0.36.0), then
# copy the completion functions and licence into dest. Every src/_* file's
# header was checked when this version was vendored (see NEXTBSD.md); the
# script refuses a release that introduces copyleft licence text so the
# maintainer looks before anything is copied. Re-run on each update (bump
# VERSION and SHA256 here and in NEXTBSD.md).
set -eu
TARBALL=${1:?usage: nextbsd-trim.sh <zsh-completions-VERSION.tar.gz> <dest>}
DEST=${2:?usage: nextbsd-trim.sh <zsh-completions-VERSION.tar.gz> <dest>}
VERSION=0.36.0
SHA256=5aa68be2999a7be2eb56de8e4acff8f3bba4a66b9acbb233752536857408fb2e

if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for $TARBALL: $got" >&2; exit 1; }

mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xzf "$TARBALL"
SRC="$TMP/zsh-completions-$VERSION"
[ -d "$SRC/src" ] || { echo "no src/ in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
cd "$SRC"
# Only licence headers are checked (the first 40 lines), not option strings
# that happen to mention a licence name.
bad=$(for f in src/_*; do
    head -40 "$f" | grep -qE '^#.*(GNU (Lesser |Affero )?General Public|GPLv?[0-9])' && echo "$f"
done || true)
[ -z "$bad" ] || { echo "copyleft licence header in: $bad -- exclude or review" >&2; exit 1; }
{
    printf '%s\n' LICENSE README.md
    find src -type f -name '_*'
} | while IFS= read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$f" "$DEST/$f"
done
echo "trimmed zsh-completions $VERSION into $DEST: $(find "$DEST" -type f | wc -l) files"
