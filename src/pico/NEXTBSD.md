# pico on NextBSD

**Source:** Alpine 2.26, the release tarball from
https://alpineapp.email/alpine/release/ (Eduardo Chappa's continuation of UW
Alpine), which is what FreeBSD's `editors/pico-alpine` port and Darwin's
`/usr/bin/pico` are built from. Apple publishes no pico source of its own.

| | |
|---|---|
| Tarball | `alpine-2.26.tar.xz` |
| SHA-256 | `c0779c2be6c47d30554854a3e14ef5e36539502b331068851329275898a9baba` (as published on the release page) |
| Licence | Apache-2.0 (`dist/LICENSE`; the c-client parts under `dist/imap/LICENSE`, also Apache-2.0). `dist/NOTICE` carries the Pine, Elm and MicroEMACS notices. |
| pico version | 5.09 (`pico -version`) |

**Only what building pico needs is vendored**, in `dist/`: 278 of Alpine's
2,379 files, 6.9 MB of 44 MB. `nextbsd-trim.sh` downloads the tarball, checks
the SHA-256 and produces `dist/`. Nothing in `dist/` is modified. It keeps:

- `configure` and its inputs (`config.guess`, `config.sub`, `install-sh`,
  `mkinstalldirs`, `missing`, `depcomp`, `config.rpath`, `ltmain.sh`,
  `VERSION`) and the `Makefile.in` of every directory `config.status` writes a
  Makefile for. The ones for `alpine/`, `web/` and `m4/` are kept only so
  `config.status` succeeds; nothing in them is built. `po/` keeps the three
  files the `po-directories` command reads and no catalogues.
- `include/config.h.in`, `general.h`, `system.h`.
- `pico/` and `pico/osdep/`: sources and `Makefile.in`, without the Windows
  files and without `pilot.c`.
- `pith/osdep/` and `pith/charconv/`, the two pith libraries pico links; the
  `pith/*.h` headers they and pico include (headers only, no pith sources);
  and `pith/help_h_gen.c` with `pith/pine.hlp`, from which `pith/helptext.h`
  is generated at build time.
- From `imap/`: every c-client header, `utf8.c` and the `charset/` tables it
  `#include`s, and the three FreeBSD osdep headers (`os_bsf.h`, `env_unix.h`,
  `tcp_unix.h`).
- `doc/man1/pico.1`, `LICENSE`, `NOTICE`, `README`.

Left out: `alpine/` (the mail client), `web/`, the rest of `imap/` (the
c-client library, servers and tools), `ldap/`, `libressl/`, `openssl/`,
`mapi/`, `regex/` (FreeBSD's libc regex is used), `packages/`, `scripts/`,
the message catalogues, `m4/*.m4`, the autotools inputs (`configure.ac`,
`Makefile.am`, `aclocal.m4`), pilot and its man page, and every Windows and
DOS file.

**Build:** `build_pico` in `build-contrib.sh`. Alpine's sources include the
c-client and pith headers by relative path from the source tree
(`../c-client/mail.h`, `../../pith/filttype.h`), so the build runs on a copy
of `dist/`, never on `src/` itself.

pico links exactly one c-client object, `utf8.o` (the charset conversion
tables), and never the c-client library. The imap build would have populated
a `c-client/` directory with links to the sources, chosen `os_bsf.h` as
`osdep.h` for FreeBSD and generated `linkage.h`, the list of mail drivers and
authenticators linked into a c-client program. `build_pico` does the same by
hand: links for the headers, `utf8.c`, the charset tables and the FreeBSD
osdep headers, `osdep.h -> os_bsf.h`, and an empty `linkage.h`, since pico
links no drivers. `utf8.o` is compiled with the flags the c-client build
uses (`-O2 -pipe -Wno-pointer-sign -DCHUNKSIZE=65536`).

`configure` runs in cross mode (`--host=<triple>`, the cross clang with
`--sysroot`). Three of its checks run a test program, which cannot be done
when cross compiling, so their FreeBSD answers are supplied as cache
variables: `ac_cv_func_strcoll_works=yes` (configure would otherwise assume
`no` and pico would sort file names with `strcmp`), `ac_cv_func_fork_works=yes`
and `ac_cv_func_vfork_works=yes` (configure's own guess, made explicit). The
remaining cross fallbacks in `configure` are compile-only checks.

Options: `--without-ssl --without-krb5 --without-ldap --without-tcl
--disable-nls --disable-dependency-tracking`, with `--prefix=/usr` and
`--mandir=/usr/share/man`. `CFLAGS` adds
`-Wno-error=incompatible-function-pointer-types`: `browse.c` passes a
`(const char *, const char *)` comparator to `qsort()`, an error by default
since clang 16, and FreeBSD's ports build it the same way.

`pith/helptext.h` is generated from `pith/pine.hlp` by `help_h_gen`, a host
tool built with the runner's `cc`, as `pith/Makefile` does; its output is
arch-neutral. Then only the pieces pico links are built:
`pith/osdep/libpithosd.a`, `pith/charconv/libpithcc.a`,
`pico/osdep/libpicoosd.a` and `pico/pico`. Upstream's `make all` is not used.

configure picks the terminal library by probing `-ltinfo` first; in the base
that is a symlink to `libtinfow`, the terminfo half of ncursesw, and pico uses
only the terminfo/termcap API, so `libtinfow.so.9` is its one library beyond
libc. It is stripped with `llvm-strip`.

**Shipped, as on Darwin:**

| Path | What | Mode |
|---|---|---|
| `/usr/bin/pico` | the editor | 0555 |
| `/usr/bin/nano` | symlink to `pico`, so `nano` opens pico as on Darwin since 12.3 | |
| `/usr/share/man/man1/pico.1` | man page | 0444 |
| `/usr/share/man/man1/nano.1` | symlink to `pico.1`, so `man nano` works | |

pilot (Alpine's file browser) is not built; Darwin does not ship it. No
`/etc` is shipped. `EDITOR` defaults belong to the zsh profile
(nextbsd/nextbsd-userland#254).

**Updating:**
1. Check the new release's tarball name and SHA-256 on the release page.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and run
   `sh src/pico/nextbsd-trim.sh src/pico/dist`.
3. Re-check that pico still links only `utf8.o` from the c-client
   (`pico/Makefile.in`, `LDADD`) and that the pith header set it includes has
   not grown beyond `pith/*.h`; adjust the trim script if it has.
4. Update the version and SHA-256 above and the `NOTICE.md` row.
