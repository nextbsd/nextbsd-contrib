#!/bin/sh
# nextbsd-trim.sh <dest>   (dest: src/netdumpd/dist)
#
# Download the pinned netdumpd commit, verify it, and copy into <dest> what
# building netdumpd for NextBSD needs. Re-run on each update, after changing
# COMMIT and SHA256 below (see NEXTBSD.md, "Updating"). Set NETDUMPD_TARBALL
# to a local copy of the archive to skip the download.
#
# netdumpd has no release tarballs on GitHub; FreeBSD's port (ftp/netdumpd)
# uses a dated snapshot made by upstream's mktar. This takes GitHub's archive
# of one commit instead.
#
# Kept (none of it modified): netdumpd.c, netdumpd.h, cap_dns.c, cap_dns.h,
# cap_handler.c, cap_herald.c, kerneldump_compat.h, netdumpd.8, and upstream's
# Makefile (bsd.prog.mk; not used by build-contrib.sh, kept as the record of
# upstream's sources and flags).
# Left out:
#   - etc/ (an rc.d script and its Makefiles; NextBSD starts netdumpd from a
#     launchd job in nextbsd-userland's overlay instead);
#   - client/ (netdump-client, a test tool that sends a fake dump; not shipped);
#   - mktar (upstream's script for making its snapshot tarballs);
#   - .gitignore.
set -eu
COMMIT=99dd0da99be7612b1feb52e4f71db308415e0259
SHA256=666c54fb3ae171639ec7fa3738d11f52a97169b847ef9008fdc0d459e4dac6f4
URL="https://github.com/markjdb/netdumpd/archive/$COMMIT.tar.gz"

DEST=${1:?usage: nextbsd-trim.sh <dest>}
mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/netdumpd-trim.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

TARBALL="$WORK/netdumpd-$COMMIT.tar.gz"
if [ -n "${NETDUMPD_TARBALL:-}" ] && [ -f "$NETDUMPD_TARBALL" ]; then
    cp "$NETDUMPD_TARBALL" "$TARBALL"
else
    curl -fsSL -o "$TARBALL" "$URL"
fi
got=$( (sha256sum "$TARBALL" 2>/dev/null || shasum -a 256 "$TARBALL") | awk '{print $1}')
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for netdumpd-$COMMIT.tar.gz: $got" >&2; exit 1; }
tar -C "$WORK" -xzf "$TARBALL"
SRC="$WORK/netdumpd-$COMMIT"
[ -f "$SRC/netdumpd.c" ] && [ -f "$SRC/netdumpd.8" ] || { echo "no netdumpd.c or netdumpd.8 in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
for f in Makefile netdumpd.c netdumpd.h cap_dns.c cap_dns.h cap_handler.c \
         cap_herald.c kerneldump_compat.h netdumpd.8; do
    cp -p "$SRC/$f" "$DEST/$f"
done
echo "netdumpd $COMMIT trimmed into $DEST: $(find "$DEST" -type f | wc -l | tr -d ' ') files"
