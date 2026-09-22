#!/bin/sh
# nextbsd-trim.sh <dest>   (dest: src/pico/dist)
#
# Download the pinned Alpine release, verify it, and copy into <dest> only what
# building pico needs. Re-run on each Alpine update, after changing VERSION and
# SHA256 below to the values published at https://alpineapp.email/alpine/release/.
# Set ALPINE_TARBALL to a local copy of the tarball to skip the download.
#
# Kept (none of it modified):
#   - configure and its inputs: config.guess, config.sub, install-sh,
#     mkinstalldirs, missing, depcomp, config.rpath, ltmain.sh, VERSION, and the
#     Makefile.in of every directory config.status writes a Makefile for (the
#     ones for alpine/, web/ and m4/ are kept only so config.status succeeds;
#     nothing in them is built);
#   - include/config.h.in, general.h, system.h;
#   - pico/ and pico/osdep/ (sources and Makefile.in; no Windows files);
#   - pith/osdep/ and pith/charconv/, the two pith libraries pico links, the
#     pith/*.h headers they include (headers only; no pith sources), and
#     pith/help_h_gen.c with pith/pine.hlp, from which build-contrib.sh
#     generates pith/helptext.h with a host-built tool, as pith/Makefile does;
#   - from imap/: every c-client header, utf8.c and the charset tables it
#     includes, and the three FreeBSD osdep headers (os_bsf.h, env_unix.h,
#     tcp_unix.h). pico links exactly one c-client object, utf8.o, which
#     build-contrib.sh compiles by hand; the c-client library is never built;
#   - po/: the three files config.status's po-directories command reads
#     (Makefile.in.in, POTFILES.in, Makevars); no message catalogues;
#   - doc/man1/pico.1;
#   - LICENSE, NOTICE, README, and imap/LICENSE, imap/NOTICE.
# Left out: alpine/ (the mail client), web/ (Web Alpine), imap/ apart from the
# above (the c-client library, servers and tools), ldap/, libressl/, openssl/,
# mapi/, regex/ (FreeBSD's libc regex is used), packages/, scripts/, po/
# catalogues, m4/*.m4, the autotools inputs (configure.ac, Makefile.am,
# aclocal.m4), pilot and its man page, and every Windows and DOS file.
set -eu
VERSION=2.26
SHA256=c0779c2be6c47d30554854a3e14ef5e36539502b331068851329275898a9baba
URL="https://alpineapp.email/alpine/release/src/alpine-$VERSION.tar.xz"

DEST=${1:?usage: nextbsd-trim.sh <dest>}
mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/alpine-trim.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

TARBALL="$WORK/alpine-$VERSION.tar.xz"
if [ -n "${ALPINE_TARBALL:-}" ] && [ -f "$ALPINE_TARBALL" ]; then
    cp "$ALPINE_TARBALL" "$TARBALL"
else
    curl -fsSL -o "$TARBALL" "$URL"
fi
got=$( (sha256sum "$TARBALL" 2>/dev/null || shasum -a 256 "$TARBALL") | awk '{print $1}')
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for alpine-$VERSION.tar.xz: $got" >&2; exit 1; }
tar -C "$WORK" -xJf "$TARBALL"
SRC="$WORK/alpine-$VERSION"

find "$DEST" -mindepth 1 -delete
cd "$SRC"
{
    printf '%s\n' LICENSE NOTICE README VERSION \
        configure config.guess config.sub install-sh mkinstalldirs missing depcomp \
        config.rpath ltmain.sh Makefile.in \
        include/config.h.in include/general.h include/system.h \
        m4/Makefile.in po/Makefile.in.in po/POTFILES.in po/Makevars \
        pith/Makefile.in pith/help_h_gen.c pith/pine.hlp \
        alpine/Makefile.in alpine/osdep/Makefile.in \
        web/src/Makefile.in web/src/pubcookie/Makefile.in web/src/alpined.d/Makefile.in \
        doc/man1/pico.1 \
        imap/LICENSE imap/NOTICE \
        imap/src/c-client/utf8.c \
        imap/src/osdep/unix/os_bsf.h imap/src/osdep/unix/env_unix.h imap/src/osdep/unix/tcp_unix.h
    find imap/src/c-client -name '*.h'
    find imap/src/charset -name '*.c'
    find pith -maxdepth 1 -name '*.h'
    find pith/osdep pith/charconv -type f \( -name '*.c' -o -name '*.h' -o -name 'Makefile.in' \)
    find pico -maxdepth 1 -type f \( -name '*.c' -o -name '*.h' -o -name 'Makefile.in' \) \
        ! -name 'pilot.c' ! -name 'mswin*'
    find pico/osdep -type f \( -name '*.c' -o -name '*.h' -o -name 'Makefile.in' \) \
        ! -name 'mswin*' ! -name 'msdlg.c' ! -name 'msmenu.h' ! -name 'os-w*' ! -name 'resource.h'
} | sort -u | while IFS= read -r f; do
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$f" "$DEST/$f"
done
echo "alpine-$VERSION trimmed into $DEST: $(find "$DEST" -type f | wc -l | tr -d ' ') files"
