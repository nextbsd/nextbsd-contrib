# libevent on NextBSD

**Source:** the libevent 2.1.13-stable release tarball from
https://github.com/libevent/libevent/releases (tag `release-2.1.13-stable`).

| | |
|---|---|
| Tarball | `libevent-2.1.13-stable.tar.gz` |
| SHA-256 | `f7e9383b8c0baa81b687e5b5eecc01beefaf1b19b64151d95ed61647fe7a315c` |
| Verified | the release's `libevent-2.1.13-stable.tar.gz.asc` is a good RSA/SHA-512 signature by subkey `7A02 B352 1DC7 5C54 2BA0 1545 6AFE E6D4 9E92 B601` of Nick Mathewson's key `2133 BC60 0AB1 33E1 D826 D173 FE43 009C 4607 B1FB` (keys.openpgp.org); the SHA-256 matches GitHub's asset digest and FreeBSD ports' `devel/libevent/distinfo` |
| Licence | BSD 3-Clause (`dist/LICENSE`, which also names the files under other terms) |

**Why it is here.** tmux needs libevent 2. The FreeBSD base has only a private
libevent 1.4 (`libprivateevent1`, for its own tools), which tmux cannot use. So
libevent is built here, for tmux alone: static, linked into `/usr/bin/tmux`,
and **nothing of it is installed**. NextBSD-contrib ships no libevent library,
header or `.pc`; `build_tmux` fails if any is staged.

**What is vendored**, in `dist/`: 112 of the release's 221 files.
`nextbsd-trim.sh` downloads the tarball, checks the SHA-256 and produces it.
Nothing in `dist/` is modified. It keeps:

- `configure` and its inputs: `configure.ac`, `aclocal.m4`, `m4/`,
  `build-aux/`, `config.h.in`, `evconfig-private.h.in`,
  `make-event-config.sed` and the five `*.pc.in` templates `config.status`
  writes;
- `Makefile.in` and every file its regeneration rule names (`Makefile.am`,
  `doxygen.am`, `include/include.am`, `sample/include.am`,
  `test/include.am`), so make sees an up-to-date tree and never reruns the
  autotools;
- the libevent_core sources for FreeBSD: `buffer.c`, `bufferevent*.c` (sock,
  filter, pair, ratelim), `event.c`, `evmap.c`, `evthread.c`, `evutil.c`,
  `evutil_rand.c` with the `arc4random.c` it `#include`s when libc has no
  `arc4random`, `evutil_time.c`, `listener.c`, `log.c`, and the backends and
  helpers configure selects there: `kqueue.c`, `poll.c`, `select.c`,
  `signal.c`, `strlcpy.c`;
- every header: the private `*.h`, `include/` in full, `compat/sys/queue.h`;
- `LICENSE`, `README.md`.

**Left out:** `test/` (regress, benchmarks) and `sample/` apart from their
`include.am`; the libevent_extra sources (`evdns.c`, `evrpc.c`, `http.c`,
`event_tagging.c`) and `event_rpcgen.py`; `bufferevent_openssl.c`;
`evthread_pthread.c` (libevent_pthreads); the backends for other systems
(`epoll.c`, `epoll_sub.c`, `devpoll.c`, `evport.c`); the Windows sources
(`win32select.c`, `buffer_iocp.c`, `bufferevent_async.c`, `event_iocp.c`,
`evthread_win32.c`, `WIN32-Code/`, `Makefile.nmake`); the CMake build
(`CMakeLists.txt`, `cmake/`, `*.cmake`); `Doxyfile`, `autogen.sh`,
`ChangeLog*`, `whatsnew-*.txt`. Most of 2.1.13's security fixes are in
evdns, evhttp, evtag and evrpc, which are not compiled here at all.

## Build

`build_libevent` in `build-contrib.sh`, run before `build_tmux` (and by it, if
needed). The tree is copied to `.build/libevent-<arch>/src` and every file
given the same mtime (`touch_tree`): a git checkout stamps files in checkout
order, which can make `Makefile.am` look newer than `Makefile.in` and send make
into automake. Then `configure` runs out of tree in cross mode
(`--host=<triple>`, the cross clang with `--sysroot`) with:

`--disable-shared --enable-static --with-pic --disable-openssl
--disable-samples --disable-libevent-regress --disable-libevent-install
--disable-dependency-tracking`, `--prefix=/usr` (unused: nothing is
installed). libevent 2.1 has no mbedtls option (that arrives in 2.2). Thread
support and debug mode keep their defaults, as in FreeBSD's port; tmux does
not use threads, and libevent_pthreads is not built.

Only `include/event2/event-config.h` and `libevent_core.la` are made. The
result is `.build/libevent-<arch>/obj/.libs/libevent_core.a`; `build_tmux`
compiles against `dist/include` and the generated `obj/include`, and links that
archive by path.

**Cross fallbacks.** configure's only test programs are "working kqueue" and
"epoll system call". The epoll one is moot (no `sys/epoll.h` in the base). The
kqueue one answers no in a cross build, so the archive's backends are poll and
select. That is also what a native FreeBSD tmux gets: tmux's
`osdep-freebsd.c` sets `EVENT_NOKQUEUE` around `event_init()`, so libevent
never picks kqueue for tmux on FreeBSD. Neither check has a cache variable;
none is set.

**Installed:** nothing.

**Updating:**
1. Check the new 2.1.x-stable release on GitHub: verify its `.asc` against
   Nick Mathewson's or Azat Khuzhin's key, and compare the SHA-256 with GitHub's
   asset digest and FreeBSD ports' `devel/libevent/distinfo`.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and run
   `sh src/libevent/nextbsd-trim.sh src/libevent/dist`. It stops if a file it
   lists is missing from the release.
3. Re-check `CORE_SRC` and `SYS_SRC` in `dist/Makefile.am` against the trim
   list, and the cross fallbacks (`grep -n 'cross_compiling" = yes' dist/configure`).
4. Update the version and SHA-256 above, `NOTICE.md` and `README.md`.
