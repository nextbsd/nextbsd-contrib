# zsh on NextBSD

**Source:** the zsh 5.9.2 release, `zsh-5.9.2.tar.xz` from
https://www.zsh.org/pub/ (also on SourceForge).

| | |
|---|---|
| Version | 5.9.2 (released July 12, 2026; Darwin ships 5.9, of which this is the maintenance release) |
| SHA-256 | `36fa734374b44783582cec09bcd67822e2f992c779ec1624ab5596df078d2f81` (matches FreeBSD ports' `shells/zsh/distinfo`) |
| Licence | the zsh licence, MIT-like (`dist/LICENCE`); per-file provisions take precedence |

**What is vendored**, in `dist/`, 1601 of the release's 1847 files.
`nextbsd-trim.sh` produces it from the tarball after verifying the SHA-256:

- `configure`, `config.h.in`, `config.guess`, `config.sub`, `install-sh`,
  `mkinstalldirs`, `stamp-h.in`, `Makefile.in`, `LICENCE`, `README`;
- `Config/`, `Src/`, `Completion/`, `Functions/` in full, except the four
  GPL-licensed completions below;
- from `Doc/`, the pre-generated man pages (`*.1`), the run-help files
  (`help/`, `help.txt`) and `Makefile.in`;
- `Etc/Makefile.in` and `Test/Makefile.in`, because `config.status` writes
  `Etc/Makefile` and `Test/Makefile` and would fail without the templates.
  Nothing is built or installed from either directory.

**Left out:** the `Test/` suite, `Etc/` (FAQ and contributor docs), `Misc/`,
`Util/`, `StartupFiles/` (example dotfiles; NextBSD's are U8 in
nextbsd-overlays), `Scripts/newuser` (Darwin deletes it after install; without
it the `zsh/newuser` module is inert), the yodl and texinfo sources under
`Doc/`, `ChangeLog`, `NEWS`, `configure.ac` and the m4 files.

**GPL files omitted.** `LICENCE` says some shell functions are GPL-licensed and
"may simply be omitted". A search of the tree for licence headers finds four,
all completion functions for software NextBSD does not ship; they are
excluded by the trim script:

| File | Header |
|---|---|
| `Completion/openSUSE/Command/_zypper` | "released under the GPLv2" |
| `Completion/openSUSE/Command/_osc` | "released under the GPLv2" |
| `Completion/Linux/Command/_qdbus` | "released under the GPLv2" |
| `Completion/Unix/Command/_darcs` | GNU General Public License |

(`_composer` and `_luarocks` mention the GPL only in option strings, and
`VCS_INFO_get_data_hg` only sets `HGPLAIN`; they are kept.)

**No source patches.** FreeBSD's port carries two: an `rlimits.c` addition
naming `RLIMIT_PIPEBUF` and `RLIMIT_VMM` so `ulimit -a` labels them, and a
`signals.c` change restoring the terminal on `TMOUT`. Neither is needed to
build, and the tree is kept as released. The corresponding limits show up
unlabelled in `ulimit -a`.

## Build

`build_zsh` in `build-contrib.sh` runs `dist/configure` in cross mode
(`--host=<triple>`, the toolchain clang, `--sysroot`), out of tree, then
`make -C Src`. Upstream's top-level `make` is not used: its `Doc` pass would
try to regenerate the man pages with yodl. The build is single-job, as
upstream marks it jobs-unsafe.

**Configure flags.** Darwin's (`apple-oss-distributions/zsh`, `Makefile`):
`--with-tcsetpgrp --enable-multibyte --enable-unicode9
--enable-max-function-depth=700`, with `bindir=/bin`. Darwin also enables pcre
on macOS; the FreeBSD base has no pcre or gdbm, so both are off. Modules are
dynamic, against `ncursesw` from base.

**Cache variables.** zsh's configure runs 30-odd test programs, which cannot
happen when cross compiling, and for most of them the cross fallback is wrong
for FreeBSD. Their answers are given as cache variables. The dynamic-loading
set follows Apple's own cross cache (`configure.cache-embedded`) where Darwin
and FreeBSD agree; the rest are FreeBSD facts:

| Variable | Value | Why |
|---|---|---|
| `zsh_cv_long_is_64_bit`, `zsh_cv_off_t_is_64_bit`, `zsh_cv_ino_t_is_64_bit`, `zsh_cv_printf_has_lld` | yes | LP64 on both arches; 64-bit `ino_t` since FreeBSD 12 |
| `zsh_cv_rlim_t_is_longer`, `zsh_cv_rlim_t_is_quad_t`, `zsh_cv_type_rlim_t_is_unsigned` | no | `rlim_t` is `__int64_t`: the same size as `long`, and signed (Darwin's is unsigned) |
| `zsh_cv_getcwd_malloc`, `zsh_cv_func_realpath_accepts_null` | yes | libc allocates when given a NULL buffer |
| `zsh_cv_func_tgetent_accepts_null` = yes, `zsh_cv_func_tgetent_zero_success` = no | | ncurses' `tgetent` takes a NULL buffer and returns 1 on success |
| `zsh_cv_sys_fifo`, `zsh_cv_sys_lseek`, `zsh_cv_sys_link` | yes | |
| `zsh_cv_c_broken_wcwidth`, `zsh_cv_c_broken_isprint` | no | libc's C locale treats bytes above 127 as non-printing; `--enable-unicode9` uses zsh's own width table anyway |
| `zsh_cv_sys_elf`, `zsh_cv_shared_environ`, `zsh_cv_shared_tgetent`, `zsh_cv_shared_tigetstr`, `zsh_cv_sys_dynamic_{clash_ok,rtld_global,execsyms,strip_exe,strip_lib}` | yes; `zsh_cv_func_dlsym_needs_underscore` = no | ELF with `-rdynamic` and `RTLD_GLOBAL`; the same answers FreeBSD's native configure produces |
| `ac_cv_func_strcoll_works`, `ac_cv_func_mmap_fixed_mapped` | yes | |
| `ac_cv_c_stack_direction` | -1 | unused with clang's builtin `alloca`; both stacks grow down |
| `ac_cv_header_sys_capability_h` | no | FreeBSD's is `sys/capsicum.h`; the port sets the same |
| `zsh_cv_sys_path_dev_fd` | no | `/dev/fd` holds only 0-2 without fdescfs; the port sets the same |
| `zsh_cv_path_utmpx` = `/var/run/utx.active`; `zsh_cv_path_utmp`, `_wtmp`, `_wtmpx` = no | | configure looks for these files on the build host; these are FreeBSD's |
| `zsh_cv_path_rlimit_h` | `$SYSROOT/usr/include/sys/resource.h` | configure greps a fixed list of host paths for `RLIMIT_*`; `rlimits.awk` builds the `ulimit` table from this file, so it must be the target's |

The signal, errno and curses-key headers are found by preprocessing with the
cross compiler and reading the line markers, so they resolve to the sysroot
without help.

**Install.** `make -C Src install.bin install.modules` and the top-level
`make install.fns` (which runs `Config/installfns.sh` with the host `sh`). The
top-level Makefile would first try to remake itself through `config.status`,
whose rule reruns `autoconf` from `configure.ac` and `aclocal.m4`; those are
not vendored, so `make -o dist/configure` marks `configure` as old and the
chain is never followed. Then
the man pages and run-help files are installed by hand from `dist/Doc`. The
versioned `/bin/zsh-5.9.2` that `/bin/zsh` is hard-linked to is removed, as
Darwin does. The shell and modules are stripped with `llvm-strip`.

**Shipped:**

| Path | Mode | What |
|---|---|---|
| `/bin/zsh` | 0755 | the shell |
| `/usr/lib/zsh/5.9.2/zsh/*.so`, `net/*.so` | 0755 | dynamic modules |
| `/usr/share/zsh/5.9.2/functions/` | 0644 | completions and functions, one flat directory as on Darwin |
| `/usr/share/zsh/5.9.2/help/` | 0444 | run-help pages |
| `/usr/share/zsh/site-functions/` | | zsh-completions (its own component) |
| `/usr/share/man/man1/zsh*.1` | 0444 | man pages |

Not shipped: `/etc/z*` (nextbsd-overlays, U8), the info manual, HTML docs,
`Scripts/newuser`, the `zsh/db/gdbm` and `zsh/pcre` modules.

**Updating:**
1. Fetch the new `zsh-<ver>.tar.xz` and check its SHA-256 against an
   independent source (FreeBSD ports' `shells/zsh/distinfo`, or the zsh-workers
   announcement).
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and here, and re-run
   `nextbsd-trim.sh <tarball> src/zsh/dist`.
3. Search the tree again for GPL headers (`grep -rlE 'GPLv|General Public' Completion Functions`)
   and update the exclusion list if it changed.
4. Re-check the cross fallbacks: `grep -n 'cross_compiling" = yes' dist/configure`.
   A new run test needs a new cache variable above.
5. Update `NOTICE.md`.
