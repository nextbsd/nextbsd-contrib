#!/bin/sh
# nextbsd-trim.sh <dest>   (dest: src/tmux/dist)
#
# Download the pinned tmux release, verify it, and copy into <dest> what
# building tmux for NextBSD needs. Re-run on each tmux update, after changing
# VERSION and SHA256 below (see NEXTBSD.md, "Updating"). Set TMUX_TARBALL to a
# local copy of the tarball to skip the download.
#
# Kept (none of it modified): the whole release except the files below, i.e.
# configure and its inputs (configure.ac, aclocal.m4, Makefile.am, Makefile.in,
# etc/), every tmux source and header including the pre-generated cmd-parse.c,
# osdep-freebsd.c, compat/ apart from the files below, tmux.1, mdoc2man.awk,
# COPYING, README.
# Left out:
#   - fuzz/ (the oss-fuzz harnesses, built only with --enable-fuzzing);
#   - CHANGES and example_tmux.conf (documentation and an example; nothing
#     installs them);
#   - osdep-*.c for every system but FreeBSD (configure builds exactly
#     osdep-<platform>.c);
#   - image.c and image-sixel.c (built only with --enable-sixel, which is off);
#   - compat/utf8proc.c and compat/systemd.c (--enable-utf8proc and
#     --enable-systemd, both off), compat/forkpty-*.c (AIX, Haiku, HP-UX and
#     SunOS; FreeBSD's libutil has forkpty) and compat/daemon-darwin.c.
set -eu
VERSION=3.8
SHA256=e79c699c7e949dccd0a4a125e17b8d1261e311b16979dbc8eb34542f3966d82e
URL="https://github.com/tmux/tmux/releases/download/$VERSION/tmux-$VERSION.tar.gz"

DEST=${1:?usage: nextbsd-trim.sh <dest>}
mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tmux-trim.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

TARBALL="$WORK/tmux-$VERSION.tar.gz"
if [ -n "${TMUX_TARBALL:-}" ] && [ -f "$TMUX_TARBALL" ]; then
    cp "$TMUX_TARBALL" "$TARBALL"
else
    curl -fsSL -o "$TARBALL" "$URL"
fi
got=$( (sha256sum "$TARBALL" 2>/dev/null || shasum -a 256 "$TARBALL") | awk '{print $1}')
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for tmux-$VERSION.tar.gz: $got" >&2; exit 1; }
tar -C "$WORK" -xzf "$TARBALL"
SRC="$WORK/tmux-$VERSION"
[ -f "$SRC/configure" ] && [ -f "$SRC/cmd-parse.c" ] || { echo "no configure or cmd-parse.c in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
cd "$SRC"
find . -type f | sed 's#^\./##' \
  | grep -v -E '^fuzz/' \
  | grep -v -x -E 'osdep-[a-z]+\.c' \
  | grep -v -x -F -e CHANGES -e example_tmux.conf \
                  -e image.c -e image-sixel.c \
                  -e compat/utf8proc.c -e compat/systemd.c \
                  -e compat/daemon-darwin.c \
                  -e compat/forkpty-aix.c -e compat/forkpty-haiku.c \
                  -e compat/forkpty-hpux.c -e compat/forkpty-sunos.c \
  | { cat; echo osdep-freebsd.c; } | sort -u | while IFS= read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$f" "$DEST/$f"
done
echo "tmux-$VERSION trimmed into $DEST: $(find "$DEST" -type f | wc -l | tr -d ' ') files"
