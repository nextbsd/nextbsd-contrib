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
   rule is applied in all three. The repository name is fixed. A dropped
   candidate is logged at debug level 1 (`pkg -d upgrade`).

   **Package files** (added by the maintainer after the design): installing or
   replacing `pkg`/`pkg-devel` from a local package file (`pkg add`,
   `pkg install ./file.pkg`) is refused unless the package is a NextBSD
   package, i.e. its manifest carries the annotation
   **`org.nextbsd.origin=NextBSD`** (nextbsd-pkg stamps it on every package it
   builds). The check is `nextbsd_check_install()` in the new
   `libpkg/nextbsd_policy.c`, and it runs in two places, both before anything
   is extracted:

   | Where | What it covers |
   |---|---|
   | `pkg_jobs_execute()` → `nextbsd_check_jobs()`, for install and upgrade jobs, after the dry-run return and before the database lock | every package of `pkg install`/`pkg upgrade` (repository packages and `./file.pkg` items alike), all checked before the first is extracted, so a refusal stops the whole transaction |
   | `pkg_add_common()`, right after the package is opened and validated, before its dependencies are added | `pkg add` (and its dependency adds), and every job install as a backstop |

   A package counts as coming from a repository when its source is a remote
   package (`PKG_REMOTE`; its repository name decides); otherwise it is a
   package file and the annotation decides. Error:
   `NextBSD: refusing to install pkg-<version> from a package file that is not a NextBSD package (no org.nextbsd.origin=NextBSD annotation): pkg comes only from NextBSD`
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
3. **`0003-MACHINE-config-variable.patch`**, also added by the maintainer
   after the design: a **`${MACHINE}`** variable for pkg.conf and repository
   files, next to `${ABI}`, `${ARCH}` and the others. `${ARCH}` is FreeBSD's
   MACHINE_ARCH (`amd64`, `aarch64`); the NextBSD repository is published per
   MACHINE (`continuous-amd64`, `continuous-arm64`), so one arch-neutral
   `/private/etc/pkg/NextBSD.conf` can say
   `url: "https://github.com/nextbsd/nextbsd-pkg/releases/download/continuous-${MACHINE}"`.
   It is derived from pkg's computed ABI arch, the same string as `${ARCH}`,
   not from uname(2), so `pkg -r <rootfs>`, `-o ABI=...` and an `ABI` in
   pkg.conf stay consistent. Mapping (FreeBSD's MACHINE_ARCH → MACHINE):
   `amd64`→`amd64`, `aarch64`→`arm64`, `armv6`/`armv7`→`arm`, `i386`→`i386`,
   `powerpc`/`powerpc64`/`powerpc64le`/`powerpcspe`→`powerpc`,
   `riscv64`→`riscv`, anything else → the same as `${ARCH}`. ABI matching and
   `${ARCH}` are unchanged. The mapping is `nextbsd_machine()` in a new
   self-contained header, `libpkg/private/nextbsd_machine.h`, so the build can
   test it on the build host. pkg.conf(5) documents it.
4. **`0004-foreign-packages-only-under-usr-local-and-var.patch`**, added by the
   maintainer after the design: a SIP-style rule. A package **not from the
   repository named `NextBSD`**, or a **package file without
   `org.nextbsd.origin=NextBSD`**, may only install files and directories
   under **`/usr/local/`** and **`/var/`**. If any of its files or directories
   lies outside (or has a `..` component), the whole install or upgrade is
   refused, naming the package and the first offending path: FreeBSD pkgbase
   `FreeBSD-*` packages (`/usr`, `/etc`, `/boot`), kmods for `/boot/modules`,
   and so on. pkg's metadata (`+MANIFEST`, ...) and scripts are not files of
   the package and are not affected. NextBSD packages are not affected, and
   nothing else is restricted. The allowed prefixes are one table,
   `nextbsd_sip_allowed[]` in the new self-contained
   `libpkg/private/nextbsd_sip.h` (add `/compat/` there if Linux compatibility
   ever needs it). The check is part of `nextbsd_check_install()`, so it runs
   in the same two places as 0001's package-file rule. Errors:
   - `NextBSD: refusing to install <name>-<version> from repository <repo>: it installs <path>; packages not from the NextBSD repository may only install under /usr/local/ and /var/`
   - `NextBSD: refusing to install <name>-<version> from a package file: it installs <path>; package files without the org.nextbsd.origin=NextBSD annotation may only install under /usr/local/ and /var/`

   Paths are checked as the package's manifest lists them; `pkg add -p`
   relocation is not taken into account.

Nothing else in pkg changes.

## Build

`build_pkg` in `build-contrib.sh`:

- pkg's own POSIX-sh `configure` (bapt's bbuild) and makefiles, run out of tree
  with GNU make, as `ports-mgmt/pkg` builds it. `configure` has no `--host` and
  takes the host triple from `$srcdir/config.guess`, falling back to the build
  machine's `uname`. The build copy gets a one-line `config.guess` that prints
  the target triple, so its `*-freebsd*` branches apply (libmd, libjail, base
  libelf, `pkg-static`) instead of the Linux ones (libbsd). `CC` is the cross
  clang with `--sysroot`; pkgconf searches only the sysroot.
- `--prefix=/usr/local` with base install directories: `--sbindir=/usr/sbin
  --libdir=/usr/lib --includedir=/usr/include --mandir=/usr/share/man
  --pkgconfigdir=/usr/libdata/pkgconfig`. pkg compiles its `PREFIX` into
  libpkg as the root of the *local administrator's* directories: user-added
  repositories (`/usr/local/etc/pkg/repos/`, the second `REPOS_DIR` entry),
  `PKG_PLUGINS_DIR` and `PLUGINS_CONF_DIR`, local triggers
  (`/usr/local/share/pkg/triggers`, after the base's `/usr/share/pkg/triggers/`)
  and `BACKUP_LIBRARY_PATH` (`/usr/local/lib/compat/pkg`, created on demand).
  Those stay in `/usr/local`, as for a ports-built pkg; only where pkg itself is
  installed is base. `--prefix=/usr` would have moved them to `/usr/etc/pkg/...`.
- Only `src`, `libpkg` and `docs` are installed, not the top level: that would
  add the periodic scripts and the bash completion under `/usr/local/etc`.
  NextBSD runs no periodic(8) (launchd; no `/etc/periodic`, no periodic job) and
  has no bash in base, so neither ships. `libpkg.a` is removed: nothing in
  NextBSD links libpkg statically.
- `pkg.pc.in` derives `libdir` and `includedir` from `prefix`, so the installed
  `pkg.pc` gets `prefix=/usr`.
- The zsh completion is made by upstream's own rule with `PREFIX=/usr` (it runs
  `%prefix%/sbin/pkg`) and installed in `/usr/share/zsh/site-functions`, first
  in NextBSD zsh's `fpath` (where zsh-completions goes).
- **OS major.** pkg compiles `__FreeBSD__` in as `OSMAJOR`
  (`libpkg/pkg.h.in:69`) and on every command compares it with the running
  system's ABI major (`pkg_compiled_for_same_os_major()`,
  `libpkg/pkg_config.c:999`); if they differ, `src/main.c:695` prints
  `Warning: Major OS version upgrade detected`. clang takes `__FreeBSD__` from
  the target triple's OS version and falls back to 8 when there is none, so the
  triple must carry the sysroot's FreeBSD release (`x86_64-unknown-freebsd15.1`,
  from its `__FreeBSD_version`). `build-contrib.sh` derives it from the sysroot
  for every component. A NextBSD sysroot at 27xxxxx (releng/15.1 API) keeps
  `freebsd15.1`, so `OSMAJOR` stays 15 and matches the `FreeBSD:15:<arch>` ABI
  that the image's pkg.conf pins.
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
`/` with everything under `/usr`, which nextbsd-pkg packages as `pkg`
(nextbsd/nextbsd-pkg#19). pkg is part of base:

| Path | What |
|---|---|
| `/usr/sbin/pkg`, `/usr/sbin/pkg-static` | the programs |
| `/usr/lib/libpkg.so.4`, `/usr/lib/libpkg.so` → `libpkg.so.4` | libpkg |
| `/usr/include/pkg.h`, `/usr/include/pkg/{audit,checksum,vec}.h` | headers |
| `/usr/libdata/pkgconfig/pkg.pc` | pkgconf file (`prefix=/usr`; `Version:` is the pkg version) |
| `/usr/share/man/man{3,5,8}/` | man pages (`pkg.8`, `pkg.conf.5`, `pkg-*.8`, ...) |
| `/usr/share/zsh/site-functions/_pkg` | zsh completion |
| `/usr/share/examples/pkg/pkg.conf.sample` | sample configuration (the port puts it in `${PREFIX}/etc/`; pkg reads `/private/etc/pkg.conf` now) |

**It replaces FreeBSD's bootstrap shim.** The compat base ships FreeBSD's
`/usr/sbin/pkg` (the shim that fetches pkg from pkg.FreeBSD.org),
`/usr/share/man/man7/pkg.7.gz` and the shim's key
`/usr/share/keys/pkg/trusted/pkg.freebsd.org.2013102301`.
nextbsd-freebsd-compat drops them in `scripts/superseded`, in the same swap.
Until its `continuous` base is rebuilt, the build's base-collision check
accepts exactly `/usr/sbin/pkg` (`PKG_BASE_SUPERSEDED`), says so in the log, and
fails on any other clash. Drop the exception once the base no longer ships the
shim. `/usr/share/pkg/triggers/mandoc.ucl` stays in the base: it is mandoc's
trigger, which this pkg runs.

No configuration is shipped here: `/private/etc/pkg.conf` and
`/private/etc/pkg/NextBSD.conf` come from `nextbsd-overlays`.

## Checks the build enforces

- every expected file is staged; everything under `/usr`, nothing under
  `/usr/local`, no static archive; nothing over a base file except the
  transitional `/usr/sbin/pkg`;
- **the compiled-in OS major is the sysroot's**: `pkg`, `pkg-static` and
  `libpkg.so.4` hold exactly one `INDEX-<n>` string (upstream's default
  `INDEXFILE`, `"INDEX-" OSMAJOR`), and `<n>` is the triple's FreeBSD major
  for the sysroot's `__FreeBSD_version` (15, for 1501000 and for NextBSD's
  2700000 alike); before every component, the cross compiler's `__FreeBSD__`
  must equal that major too;
- `libpkg.so.4` has SONAME `libpkg.so.4`; `pkg` links the base libarchive,
  libssl, libcrypto and libelf and does not link libpkg.so; `pkg-static` has no
  interpreter and no `DT_NEEDED`;
- no repository, build or sysroot path in any staged file; `pkg.pc` has
  `prefix=/usr`, no `/usr/local`, and `Version: 2.8.4`; the zsh completion runs
  `/usr/sbin/pkg`;
- **both patches are compiled in**, in `pkg`, `pkg-static` and `libpkg.so.4`:
  the filter's message string
  (`NextBSD: ignoring %s-%s from repository %s: pkg comes only from the NextBSD repository`),
  `/private/etc/pkg.conf` and `/private/etc/pkg/,/usr/local/etc/pkg/repos/`
  are present, and upstream's `/usr/local/etc/pkg.conf` and
  `/etc/pkg/,/usr/local/etc/pkg/repos/` are not; the patched `pkg_config.c`
  registers `MACHINE` from the ABI arch and the binaries hold the mapping;
- 0001's package-file rule and 0004's rule are compiled in: their three error
  strings are in `pkg`, `pkg-static` and `libpkg.so.4`, and the patched
  `pkg_jobs.c` and `pkg_add.c` call the checks where described above;
- **0004's path rule gives the right answers**: `src/pkg/nextbsd-check-sip.c`,
  built with the host `cc` against the patch's header, checks allowed paths
  (`/usr/local/bin/git`, `/var/db/git`, `/usr/local`, `/var`) and refused ones
  (`/usr/bin/uname`, `/etc/rc.conf`, `/boot/kernel/kernel`,
  `/boot/modules/i915kms.ko`, `/usr/localx/...`, `/usr/local/../../etc/passwd`,
  `/compat/linux/...`, a relative path);
- **`${MACHINE}` expands correctly**: the target pkg cannot run on the
  runner, so `src/pkg/nextbsd-check-machine.c` is built with the host `cc`
  against the build copy's libucl and the patch's header, registers `ARCH` and
  `MACHINE` as patched libpkg does, parses the NextBSD.conf url above and
  checks it gives `continuous-amd64` for ABI `FreeBSD:15:amd64` and
  `continuous-arm64` for `FreeBSD:15:aarch64`.

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
