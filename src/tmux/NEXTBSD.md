# tmux on NextBSD

**Source:** the tmux 3.8 release tarball from
https://github.com/tmux/tmux/releases (tag `3.8`, September 9, 2026).

| | |
|---|---|
| Tarball | `tmux-3.8.tar.gz` |
| SHA-256 | `e79c699c7e949dccd0a4a125e17b8d1261e311b16979dbc8eb34542f3966d82e` |
| Verified | tmux publishes no signature. The SHA-256 matches GitHub's digest for the release asset and FreeBSD ports' `sysutils/tmux/distinfo` (3.8) |
| Licence | ISC (`dist/COPYING`); individual files carry their own notices |
| libevent | 2.1.13-stable, linked statically (`src/libevent`) |

**What is vendored**, in `dist/`: 202 of the release's 228 files.
`nextbsd-trim.sh` downloads the tarball, checks the SHA-256 and produces it.
Nothing in `dist/` is modified. It is the whole release except:

- `fuzz/` (the oss-fuzz harnesses, built only with `--enable-fuzzing`);
- `CHANGES` and `example_tmux.conf` (nothing installs them);
- `osdep-*.c` for every system but FreeBSD (configure builds exactly
  `osdep-<platform>.c`);
- `image.c` and `image-sixel.c` (`--enable-sixel` only; it is off);
- `compat/utf8proc.c`, `compat/systemd.c` (`--enable-utf8proc`,
  `--enable-systemd`, both off), `compat/forkpty-*.c` (AIX, Haiku, HP-UX,
  SunOS; FreeBSD's libutil has `forkpty`) and `compat/daemon-darwin.c`.

Kept: `configure` and its inputs (`configure.ac`, `aclocal.m4`, `Makefile.am`,
`Makefile.in`, `etc/`), every source and header, the pre-generated
`cmd-parse.c`, the rest of `compat/`, `tmux.1`, `mdoc2man.awk`, `COPYING`,
`README`.

## Build

`build_tmux` in `build-contrib.sh`, after `build_libevent` (it runs that first
if the archive is missing). The tree is copied to `.build/tmux-<arch>/src` and
built there, in tree: tmux's install hook writes the man page into the source
directory, and with automake's `subdir-objects` and no dependency tracking an
out-of-tree build has no `compat/` object directory. Every file of the copy is
given the same mtime (`touch_tree`), so a git checkout's order cannot make make
rerun automake or remake `cmd-parse.c` from `cmd-parse.y`. The build fails if
`cmd-parse.c` differs from the release's.

`configure` runs in cross mode (`--host=<triple>`, the cross clang with
`--sysroot`):

`--prefix=/usr --sysconfdir=/etc --mandir=/usr/share/man
--with-TERM=tmux-256color --disable-utf8proc --disable-systemd
--disable-utempter --disable-sixel --disable-dependency-tracking`.

utf8proc, systemd, utempter and sixel are all off by default on a FreeBSD host
anyway; they are spelled out. FreeBSD's port enables utempter (the base has
`libutempter`); NextBSD leaves it off, as tmux does by default, so panes get no
utmpx entries.

- **libevent** is given as `LIBEVENT_CORE_CFLAGS` (`dist/include` and the
  generated `include` of the libevent build) and `LIBEVENT_CORE_LIBS` (the
  path of `libevent_core.a`). configure's `PKG_CHECK_MODULES` takes preset
  variables as found, so pkg-config is never asked about libevent and the
  archive is linked by path: tmux has no `DT_NEEDED` on any libevent, and the
  base's `libprivateevent1` is never seen.
- **terminfo** is base ncurses: pkg-config searches only the sysroot
  (`PKG_CONFIG_LIBDIR=$SYSROOT/usr/libdata/pkgconfig`,
  `PKG_CONFIG_SYSROOT_DIR=$SYSROOT`) and finds `tinfow.pc`, so tmux links
  `libtinfow` (`-ltinfow`). `libutil` supplies `forkpty`.

**Cross fallbacks.** configure's test programs and what is done about them:

| Check | Cross answer | Handling |
|---|---|---|
| `--with-TERM` probe (`setupterm` of `screen-256color`, `tmux`, `tmux-256color`) | `screen` | `--with-TERM=tmux-256color`: the base's termcap has all three, so a native FreeBSD build picks `tmux-256color` |
| working `strtonum`, `reallocarray`, `recallocarray` | no | none; not cache variables. tmux compiles its own copies from `compat/`, which behave the same |
| working `strnlen` (`ac_cv_func_strnlen_working`) | yes | none needed |
| `/proc/$$` (looks at the build host) | yes, on the Linux runner | `-UHAVE_PROC_PID` in `CPPFLAGS`; NextBSD has no `/proc`, so `getdtablecount()` returns 0 as on FreeBSD |
| `yacc` present (`ac_cv_prog_found_yacc`) | depends on the runner | `yes`: the release ships `cmd-parse.c`, so yacc is never run |

**Defaults compiled in:** configuration `/etc/tmux.conf`, then
`~/.tmux.conf`, `$XDG_CONFIG_HOME/tmux/tmux.conf`, `~/.config/tmux/tmux.conf`;
`default-terminal` `tmux-256color`; lock command `lock -np`; sockets under
`$TMUX_TMPDIR` or `/tmp`. No `/etc/tmux.conf` is shipped (configuration goes
to nextbsd-overlays if ever wanted).

**Shipped:**

| Path | Mode | What |
|---|---|---|
| `/usr/bin/tmux` | 0555 | the terminal multiplexer, stripped, libevent_core inside |
| `/usr/share/man/man1/tmux.1` | 0444 | man page (mdoc, `@SYSCONFDIR@` set to `/etc` by tmux's install hook) |

`build_tmux` fails if the tmux install produced anything else, if either path
is a file of the base, if any libevent library, header or `.pc` is staged, or
if tmux has a `DT_NEEDED` on a libevent. It checks `DT_NEEDED` on `libtinfow`
and `libutil`, the compiled-in `/etc/tmux.conf` and `tmux-256color`, and that
no build path is in the binary.

**Updating:**
1. Fetch the new `tmux-<ver>.tar.gz` and compare its SHA-256 with GitHub's
   asset digest and FreeBSD ports' `sysutils/tmux/distinfo`.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and run
   `sh src/tmux/nextbsd-trim.sh src/tmux/dist`.
3. Re-check `dist/configure.ac` for new optional dependencies or test
   programs (`grep -n 'cross_compiling" = yes' dist/configure`), and
   `Makefile.am` for sources that moved in or out of conditionals.
4. Check that tmux still builds against libevent 2.1 (`src/libevent`).
5. Update the version and SHA-256 above, `NOTICE.md` and `README.md`.
