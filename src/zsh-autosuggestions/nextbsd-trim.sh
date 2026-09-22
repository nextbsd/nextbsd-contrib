#!/bin/sh
# nextbsd-trim.sh <zsh-autosuggestions-0.7.1.tar.gz> <dest>   (dest: src/zsh-autosuggestions/dist)
# Verify the upstream release tarball (GitHub's archive of tag v0.7.1), then
# copy the plugin, its sources and licence into dest. Re-run on each update
# (bump VERSION and SHA256 here and in NEXTBSD.md).
set -eu
TARBALL=${1:?usage: nextbsd-trim.sh <zsh-autosuggestions-VERSION.tar.gz> <dest>}
DEST=${2:?usage: nextbsd-trim.sh <zsh-autosuggestions-VERSION.tar.gz> <dest>}
VERSION=0.7.1
SHA256=0df7affff21cd87ed298e6a3970ed08a1dd66a6efa676454ee5b091ad503badf

if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for $TARBALL: $got" >&2; exit 1; }

mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xzf "$TARBALL"
SRC="$TMP/zsh-autosuggestions-$VERSION"
[ -f "$SRC/zsh-autosuggestions.zsh" ] || { echo "no zsh-autosuggestions.zsh in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
cd "$SRC"
{
    # the built plugin (what is installed), the loader stub, the sources it is
    # assembled from and the licence; not the spec suite or its Docker/Gem files
    printf '%s\n' LICENSE README.md VERSION ZSH_VERSIONS Makefile \
        zsh-autosuggestions.zsh zsh-autosuggestions.plugin.zsh
    find src -type f
} | while IFS= read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$f" "$DEST/$f"
done
echo "trimmed zsh-autosuggestions $VERSION into $DEST: $(find "$DEST" -type f | wc -l) files"
