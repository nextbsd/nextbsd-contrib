# pkg on NextBSD

**Source:** https://github.com/freebsd/pkg, release tag `2.8.4`, as GitHub's
archive `https://github.com/freebsd/pkg/archive/refs/tags/2.8.4.tar.gz`. That
is the same file FreeBSD's `ports-mgmt/pkg` port fetches.

| | |
|---|---|
| Version | 2.8.4 (`PKG_API` 2008004) |
| Tag commit | `e1d90eb706cbb4588bbd71bf205843b751c0be51` (a lightweight tag) |
| SHA-256 | `b7b71b1d11c8c021bab41e064778c0f8184c41eb4ced91b0951acfdc0538da47`, matching `ports-mgmt/pkg/distinfo` (size 12294039) |
| Licence | BSD 2-Clause (`dist/COPYING`); the bundled libraries under `dist/external/` keep their own licences (see below) |
| libpkg soname | `libpkg.so.4` (`define LIBVERSION 4` in `configure.def`) |

Design: [pkg comes only from the NextBSD repo](https://github.com/nextbsd/nextbsd-pkg/wiki/NextBSD-pkg-only-from-NextBSD).
NextBSD ships its own pkg(8), built from this frozen copy, so pkg is never
installed or upgraded from a FreeBSD (or any other) repository.

## What is vendored

`dist/` is the archive, unmodified: 1,100 files. `nextbsd-trim.sh` produces it
after verifying the SHA-256. Left out:

- `external/libecc/src/examples/`, `external/libecc/src/tests/` and
  `external/libecc/src/wycheproof_tests/`: libecc's own test programs and test
  vectors, 68 MB of the archive's 103 MB (one header alone is 49 MB).
  `external/libecc/Makefile.in` builds none of them and nothing pkg compiles
  includes them.
- `.builds/`, `.github/`, `.gitlab-ci.yml`: upstream CI.
- the top-level `.gitignore`.

pkg's own test suite (`tests/`) stays: `configure` writes Makefiles there. It is
not built: it needs `kyua` on the build host.

## The NextBSD patches

`patches/series` lists them; `build_pkg` applies them to a copy of `dist/`.
Each carries a DEP-3 header with `Origin: NextBSD`.

1. **`0001-pkg-only-from-NextBSD-repo.patch`** (design section 1). For `pkg`
   and `pkg-devel`, a remote candidate whose repository is not named `NextBSD`
   is dropped. The helper `nextbsd_foreign_pkg()` in
   `libpkg/pkg_jobs_universe.c` is called in each loop that collects remote
   candidates into the job universe:

   | Function | Paths it serves |
   |---|---|
   | `pkg_jobs_universe_get_remote()` | dependency resolution |
   | `pkg_jobs_universe_get_upgrade_candidates()` | the self-upgrade check (`new_pkg_version()` → `pkg_jobs_find_upgrade()` → `pkg_jobs_process_remote_pkg()`), `pkg install`, `pkg install -r <repo>`, `pkg upgrade` |
   | `pkg_jobs_universe_handle_provide()` | shlib and provide lookups |

   The design names only the first, as the place every lookup goes through. In
   2.8.4 it serves dependencies only; the self-upgrade path collects its
   candidates in the second. A filter in the first alone would leave the
   self-upgrade check able to replace pkg from another repository, so the same
   rule is applied in all three. Local packages and `pkg add` of a file are not
   affected, and the repository name is fixed. A dropped candidate is logged at
   debug level 1 (`pkg -d upgrade`).
2. **`0002-config-in-private-etc.patch`**, added by the maintainer after the
   design. NextBSD keeps base configuration in Darwin's real location:
   - `pkg.conf` is **`/private/etc/pkg.conf`** (upstream: `${PREFIX}/etc/pkg.conf`);
   - the default `REPOS_DIR` is **`/private/etc/pkg/`, `/usr/local/etc/pkg/repos/`**
     (upstream: `/etc/pkg/`, `${PREFIX}/etc/pkg/repos/`).

   `NextBSD.conf` lives in `/private/etc/pkg/` (from `nextbsd-overlays`); a user
   adds other repositories in `/usr/local/etc/pkg/repos/`. `PLUGINS_CONF_DIR`
   stays `/usr/local/etc/pkg/`: it is not repository configuration, and in
   `/private/etc/pkg/` its `*.conf` files would be read as repositories.
   Fingerprint directories have no compiled-in default. The sample and the
   pkg.conf(5) and pkg-repositories(8) lines that state these defaults are
   updated to match.

Nothing else in pkg changes.

## Build

`build_pkg` in `build-contrib.sh`, the way `ports-mgmt/pkg` builds it:

- pkg's own POSIX-sh `configure` (bapt's bbuild) and makefiles, run out of tree
  with GNU make. `configure` has no `--host` and takes the host triple from
  `$srcdir/config.guess`, falling back to the build machine's `uname`. The
  build copy gets a one-line `config.guess` that prints the target triple, so
  its `*-freebsd*` branches apply (libmd, libjail, base libelf, `pkg-static`)
  instead of the Linux ones (libbsd). `CC` is the cross clang with
  `--sysroot`; pkgconf searches only the sysroot.
- `--prefix=/usr/local --mandir=/usr/local/share/man`, the port's arguments.
- `-ffile-prefix-map` keeps the build tree out of `assert()` strings.
- One host-side probe is not cross-aware: configure checks the build machine's
  `/proc/self/fd` and so sets `HAVE_PROC_PID`. It is read only by
  `compat/closefrom.c`'s fallback, which is not used on FreeBSD's libc (it has
  `closefrom`).

**Libraries.** pkg bundles and links statically: sqlite, libucl, lua, picosat,
linenoise, yxml, blake2, libder, libecc and its own libfetch (`external/`;
base's libfetch is not used). From the compat base it links libarchive,
libssl/libcrypto, libmd, libutil, libelf, libjail, libm and libthr. `pkg` embeds
libpkg (`libpkg_flat.a`) as upstream does; `libpkg.so.4` is for other programs.
`pkg-static` is fully static and additionally takes libz, libbz2, liblzma and
libprivatezstd (base's private zstd, which is what libarchive uses) for
libarchive.

## Installed

pkg goes into its own tarball, `nextbsd-contrib-pkg-<arch>.tar.gz`, rooted at
`/`, which nextbsd-pkg packages as `pkg` (nextbsd/nextbsd-pkg#19). Paths are the
port's (`ports-mgmt/pkg/pkg-plist`), under `/usr/local`:

| Path | What |
|---|---|
| `/usr/local/sbin/pkg`, `/usr/local/sbin/pkg-static` | the programs |
| `/usr/local/lib/libpkg.so.4`, `libpkg.so`, `libpkg.a` | libpkg |
| `/usr/local/include/pkg.h`, `/usr/local/include/pkg/{audit,checksum,vec}.h` | headers |
| `/usr/local/libdata/pkgconfig/pkg.pc` | pkgconf file (`Version:` is the pkg version) |
| `/usr/local/share/man/man{3,5,8}/` | man pages |
| `/usr/local/etc/periodic/{daily,weekly,security}/` | periodic scripts |
| `/usr/local/etc/bash_completion.d/_pkg.bash`, `/usr/local/share/zsh/site-functions/_pkg` | completions |
| `/usr/local/share/examples/pkg/pkg.conf.sample` | sample configuration (the port puts it in `/usr/local/etc/`; pkg no longer reads that directory's `pkg.conf`) |
| `/usr/local/lib/compat/pkg/` | empty, as the port creates it (pkg's backup directory for replaced shared libraries) |

**Why `/usr/local` and not `/usr/sbin`.** The compat base already ships
`/usr/sbin/pkg`, FreeBSD's bootstrap shim, and `/usr/share/man/man7/pkg.7`.
The shim runs `/usr/local/sbin/pkg` when it exists, so `pkg` works from either
`PATH` entry. Installing where the FreeBSD `pkg` package does also means the
NextBSD `pkg` package replaces the FreeBSD one file for file, and ports and
packages that expect `${LOCALBASE}/sbin/pkg` find it. The build fails if any
staged file would replace a file in the base sysroot.

No configuration is shipped here: `/private/etc/pkg.conf` and
`/private/etc/pkg/NextBSD.conf` come from `nextbsd-overlays`.

## Checks the build enforces

- every expected file is staged; nothing outside `/usr/local`; nothing over a
  base file;
- `libpkg.so.4` has SONAME `libpkg.so.4`; `pkg` links the base libarchive,
  libssl, libcrypto and libelf and does not link libpkg.so; `pkg-static` has no
  interpreter and no `DT_NEEDED`;
- no repository, build or sysroot path in any staged file; `pkg.pc` has
  `prefix=/usr/local` and `Version: 2.8.4`;
- **both patches are compiled in**, in `pkg`, `pkg-static` and `libpkg.so.4`:
  the filter's message string
  (`NextBSD: ignoring %s-%s from repository %s: pkg comes only from the NextBSD repository`),
  `/private/etc/pkg.conf` and `/private/etc/pkg/,/usr/local/etc/pkg/repos/`
  are present as whole C strings, and upstream's `/usr/local/etc/pkg.conf` and
  `/etc/pkg/,/usr/local/etc/pkg/repos/` are not.

## Bundled libraries' licences

All permissive, none copyleft: sqlite (public domain), libucl (BSD 2-Clause),
lua (MIT), picosat (MIT), linenoise (BSD 2-Clause), yxml (MIT), blake2 (CC0 /
Apache-2.0 / OpenSSL licence, at the user's choice), uthash (BSD 1-Clause),
libder (BSD 2-Clause), libecc (BSD 2-Clause or GPL-2.0, dual-licensed; used
under BSD), libelf from elftoolchain (BSD 2-Clause, not built: base libelf is
used) and libfetch (BSD 3-Clause). Each directory under `dist/external/` holds
its own licence text or headers.

## Updating

Deliberately, never on a schedule: `scripts/sync-pkg.sh <version>`, then the
`sync-pkg` skill (`.claude/skills/sync-pkg/SKILL.md`) for refreshing the
patches, the soname and installed-file checks, docs and the PR.
