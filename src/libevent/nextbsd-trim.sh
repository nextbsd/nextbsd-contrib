#!/bin/sh
# nextbsd-trim.sh <dest>   (dest: src/libevent/dist)
#
# Download the pinned libevent release, verify it, and copy into <dest> only
# what building libevent_core (the one libevent library tmux links, statically)
# needs. Re-run on each libevent update, after changing VERSION and SHA256
# below (see NEXTBSD.md, "Updating"). Set LIBEVENT_TARBALL to a local copy of
# the tarball to skip the download.
#
# Kept (none of it modified):
#   - configure and its inputs: configure.ac, aclocal.m4, m4/, build-aux/,
#     config.h.in, evconfig-private.h.in, make-event-config.sed, the five
#     *.pc.in templates config.status writes, Makefile.in and every file its
#     regeneration rule names (Makefile.am, doxygen.am, include/include.am,
#     sample/include.am, test/include.am). They are kept so make sees an
#     up-to-date tree and never reruns the autotools; nothing in sample/ or
#     test/ is built;
#   - the libevent_core sources for FreeBSD: buffer.c, bufferevent.c,
#     bufferevent_filter.c, bufferevent_pair.c, bufferevent_ratelim.c,
#     bufferevent_sock.c, event.c, evmap.c, evthread.c, evutil.c,
#     evutil_rand.c (with arc4random.c, which it #includes when libc has no
#     arc4random), evutil_time.c, listener.c, log.c, and the backends and
#     helpers configure selects there: kqueue.c, poll.c, select.c, signal.c,
#     strlcpy.c;
#   - every header: the private *.h at the top, include/ in full,
#     compat/sys/queue.h;
#   - LICENSE, README.md.
# Left out: test/ (regress and benchmarks) apart from include.am, sample/ apart
# from include.am, the libevent_extra sources (evdns.c, evrpc.c, http.c,
# event_tagging.c) and event_rpcgen.py, bufferevent_openssl.c,
# evthread_pthread.c (libevent_pthreads), the backends for other systems
# (epoll.c, epoll_sub.c, devpoll.c, evport.c), the Windows sources
# (win32select.c, buffer_iocp.c, bufferevent_async.c, event_iocp.c,
# evthread_win32.c, WIN32-Code/, Makefile.nmake), the CMake build
# (CMakeLists.txt, cmake/, *.cmake), Doxyfile, autogen.sh, ChangeLog*,
# whatsnew-*.txt.
set -eu
VERSION=2.1.13-stable
SHA256=f7e9383b8c0baa81b687e5b5eecc01beefaf1b19b64151d95ed61647fe7a315c
URL="https://github.com/libevent/libevent/releases/download/release-$VERSION/libevent-$VERSION.tar.gz"

DEST=${1:?usage: nextbsd-trim.sh <dest>}
mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/libevent-trim.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

TARBALL="$WORK/libevent-$VERSION.tar.gz"
if [ -n "${LIBEVENT_TARBALL:-}" ] && [ -f "$LIBEVENT_TARBALL" ]; then
    cp "$LIBEVENT_TARBALL" "$TARBALL"
else
    curl -fsSL -o "$TARBALL" "$URL"
fi
got=$( (sha256sum "$TARBALL" 2>/dev/null || shasum -a 256 "$TARBALL") | awk '{print $1}')
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for libevent-$VERSION.tar.gz: $got" >&2; exit 1; }
tar -C "$WORK" -xzf "$TARBALL"
SRC="$WORK/libevent-$VERSION"
[ -f "$SRC/configure" ] || { echo "no configure in $SRC" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
cd "$SRC"
{
    printf '%s\n' LICENSE README.md \
        configure configure.ac aclocal.m4 Makefile.am Makefile.in doxygen.am \
        config.h.in evconfig-private.h.in make-event-config.sed \
        libevent.pc.in libevent_core.pc.in libevent_extra.pc.in \
        libevent_openssl.pc.in libevent_pthreads.pc.in \
        sample/include.am test/include.am \
        buffer.c bufferevent.c bufferevent_filter.c bufferevent_pair.c \
        bufferevent_ratelim.c bufferevent_sock.c event.c evmap.c evthread.c \
        evutil.c evutil_rand.c arc4random.c evutil_time.c listener.c log.c \
        kqueue.c poll.c select.c signal.c strlcpy.c \
        compat/sys/queue.h
    find . -maxdepth 1 -type f -name '*.h' | sed 's#^\./##'
    find include build-aux m4 -type f
} | sort -u | while IFS= read -r f; do
    [ -f "$f" ] || { echo "missing in the release: $f" >&2; exit 1; }
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$f" "$DEST/$f"
done
echo "libevent-$VERSION trimmed into $DEST: $(find "$DEST" -type f | wc -l | tr -d ' ') files"
