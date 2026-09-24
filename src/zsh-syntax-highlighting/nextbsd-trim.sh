#!/bin/sh
# nextbsd-trim.sh <zsh-syntax-highlighting-0.8.0.tar.gz> <dest>   (dest: src/zsh-syntax-highlighting/dist)
# Verify the upstream release tarball (GitHub's archive of tag 0.8.0), then
# copy the plugin, its highlighters and licence into dest. Re-run on each
# update (bump VERSION and SHA256 here and in NEXTBSD.md).
set -eu
TARBALL=${1:?usage: nextbsd-trim.sh <zsh-syntax-highlighting-VERSION.tar.gz> <dest>}
DEST=${2:?usage: nextbsd-trim.sh <zsh-syntax-highlighting-VERSION.tar.gz> <dest>}
VERSION=0.8.0
SHA256=5981c19ebaab027e356fe1ee5284f7a021b89d4405cc53dc84b476c3aee9cc32

if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for $TARBALL: $got" >&2; exit 1; }

mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xzf "$TARBALL"
SRC="$TMP/zsh-syntax-highlighting-$VERSION"
[ -f "$SRC/zsh-syntax-highlighting.zsh" ] || { echo "no zsh-syntax-highlighting.zsh in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
cd "$SRC"
{
    # The entry point, the two dot files it reads at load time for its version
    # strings, the loader stub, the licence and the docs. Then every
    # highlighter, minus their test-data, which is the bulk of the tag.
    printf '%s\n' COPYING.md README.md changelog.md Makefile \
        .version .revision-hash \
        zsh-syntax-highlighting.zsh zsh-syntax-highlighting.plugin.zsh \
        docs/highlighters.md highlighters/README.md
    find highlighters -type f -name '*.zsh' -not -path '*/test-data/*'
    find highlighters -type f -name 'README.md'
} | sort -u | while IFS= read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$f" "$DEST/$f"
done
echo "trimmed zsh-syntax-highlighting $VERSION into $DEST: $(find "$DEST" -type f | wc -l) files"
