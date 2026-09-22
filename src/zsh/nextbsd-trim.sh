#!/bin/sh
# nextbsd-trim.sh <zsh-5.9.2.tar.xz> <dest>   (dest: src/zsh/dist)
# Verify the upstream release tarball, then copy only what building and
# installing zsh needs into dest, leaving out the GPL-licensed completion
# files that zsh's LICENCE says may simply be omitted. Re-run on each update
# (bump VERSION and SHA256 here and in NEXTBSD.md).
set -eu
TARBALL=${1:?usage: nextbsd-trim.sh <zsh-VERSION.tar.xz> <dest>}
DEST=${2:?usage: nextbsd-trim.sh <zsh-VERSION.tar.xz> <dest>}
VERSION=5.9.2
SHA256=36fa734374b44783582cec09bcd67822e2f992c779ec1624ab5596df078d2f81

if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for $TARBALL: $got" >&2; exit 1; }

mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xf "$TARBALL"
SRC="$TMP/zsh-$VERSION"
[ -f "$SRC/configure" ] || { echo "no configure in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
cd "$SRC"
{
    # configure, its inputs and helpers, and the Makefile templates config.status
    # writes (Etc/Makefile.in and Test/Makefile.in only so it does not fail;
    # nothing is built there)
    printf '%s\n' LICENCE README configure config.h.in config.guess config.sub \
        install-sh mkinstalldirs stamp-h.in Makefile.in \
        Etc/Makefile.in Test/Makefile.in Doc/Makefile.in
    # the shell, its modules, and the functions and completions it installs
    find Config Src Completion Functions -type f
    # man pages and run-help files, pre-generated in the release
    ls Doc/*.1
    printf '%s\n' Doc/help.txt
    find Doc/help -type f
} | grep -v -x -F -e Completion/openSUSE/Command/_zypper \
                   -e Completion/openSUSE/Command/_osc \
                   -e Completion/Unix/Command/_darcs \
                   -e Completion/Linux/Command/_qdbus \
  | while IFS= read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$f" "$DEST/$f"
done
echo "trimmed zsh $VERSION into $DEST: $(find "$DEST" -type f | wc -l) files"
