---
name: sync-pkg
description: Deliberately upgrade the vendored freebsd/pkg in nextbsd-contrib (src/pkg) to a newer upstream release. Use only when someone asks for a specific pkg version (or "the latest pkg release"); never as a routine or scheduled follow. Runs scripts/sync-pkg.sh, refreshes the NextBSD patches, checks what the upgrade changes for nextbsd-pkg and the images, and opens a PR. Agents never merge.
---

# Upgrading pkg(8) in nextbsd-contrib

pkg is **frozen**: `src/pkg/dist/` is freebsd/pkg at one release tag, unmodified
(trimmed by `src/pkg/nextbsd-trim.sh`), and the NextBSD changes are the patches
in `src/pkg/patches/`, applied at build time. It moves only when a person
decides to take a newer release. This is the first use of the per-repo sync
pattern from E22 (nextbsd-userland wiki, *E22 Source Split Direction*,
"Upstream path ownership and syncing"): a plain script does the import, this
skill does the judgement.

Design: <https://github.com/nextbsd/nextbsd-pkg/wiki/NextBSD-pkg-only-from-NextBSD>.

## Before you start

- Pick a **release** tag of <https://github.com/freebsd/pkg> (`2.8.5`, `2.9.0`,
  ...), not a `-devel`/`.99` snapshot. Prefer the version FreeBSD's
  `ports-mgmt/pkg` is at: FreeBSD packages are built against it, and the NextBSD
  repo must not fall far behind it or a FreeBSD package needing a newer pkg will
  not install.
- Work on a clean checkout of `main`.

## 1. Run the script

```
scripts/sync-pkg.sh <version>
```

It creates the local branch `sync/pkg-<version>`, commits the vendor import
(`src/pkg/dist/` and the VERSION/COMMIT/SHA256 lines of `nextbsd-trim.sh`),
then tries the patch series in a scratch copy and prints what changed upstream
that the build and the patches depend on. It does not push. Exit status 2 means
a patch no longer applies.

Check the SHA-256 it prints against `ports-mgmt/pkg/distinfo` in freebsd-ports
once the port is at the same version (both fetch GitHub's archive of the tag).

## 2. Refresh the patches (separate commit, after the import)

There are three, all `Origin: NextBSD`, listed in `src/pkg/patches/series`:

- **0001-pkg-only-from-NextBSD-repo.patch**: for `pkg` and `pkg-devel`, any
  remote candidate whose repository is not `NextBSD` is dropped. The rule is the
  helper `nextbsd_foreign_pkg()` in `libpkg/pkg_jobs_universe.c`, called in
  **every loop that collects remote candidates** into the job universe:
  `pkg_jobs_universe_get_remote()` (dependencies),
  `pkg_jobs_universe_get_upgrade_candidates()` (self-upgrade via
  `new_pkg_version()`, install, upgrade) and
  `pkg_jobs_universe_handle_provide()` (shlib and provide lookups).
  After an upgrade, look at the script's "repo query" lines and read every
  `pkgdb_repo_query*`/`pkgdb_repo_*provide` caller in `pkg_jobs*.c`: if upstream
  added a new path that puts remote packages into the universe, it needs the
  filter too. The goal is the one rule; the call sites follow from it.
- **0002-config-in-private-etc.patch**: `/private/etc/pkg.conf` instead of
  `${PREFIX}/etc/pkg.conf`, default `REPOS_DIR` `/private/etc/pkg/,
  ${PREFIX}/etc/pkg/repos/`, plus the sample and the pkg.conf(5) and
  pkg-repositories(8) lines that state those defaults. Check the script's
  "config path" lines for any new compiled-in `/etc` or `${PREFIX}/etc` path for
  pkg's own configuration. `PLUGINS_CONF_DIR` deliberately stays in
  `${PREFIX}/etc/pkg/`.
- **0003-MACHINE-config-variable.patch**: registers `${MACHINE}` next to
  `${ARCH}` in `config_parser_vars_register()` (`libpkg/pkg_config.c`), from
  the same `pkg_arch_to_string()` of the computed ABI, through
  `nextbsd_machine()` in the new `libpkg/private/nextbsd_machine.h`. If
  upstream adds an architecture to `pkg_abi.c`, add its FreeBSD MACHINE to the
  map. If upstream ever adds its own `MACHINE` variable, drop this patch and
  check the meaning matches (NextBSD.conf in nextbsd-overlays relies on
  `continuous-${MACHINE}`). The build checks the expansion on the host with
  `src/pkg/nextbsd-check-machine.c`, which uses libucl's API; keep it building.

To refresh: copy `src/pkg/dist/` to two scratch trees, apply the series to one,
fix it by hand, and regenerate each patch with
`diff -u --label a/<file> --label b/<file>`, keeping its DEP-3 header. Never
edit `src/pkg/dist/`. Do not add a fourth patch without the maintainer's
agreement; "nothing else in pkg changes" is part of the design.

## 3. Check what the upgrade changes downstream

- **libpkg soname**: `define LIBVERSION` in `configure.def`. If it moved, update
  the `libpkg.so.<N>` paths and the SONAME check in `build_pkg`
  (`build-contrib.sh`), and say so in the PR: nextbsd-pkg's `pkg` package and
  anything linking libpkg change.
- **Build inputs**: `configure.def` (new required libraries, new options),
  `libpkg/Makefile.in`, `src/Makefile.in`, `external/Makefile.in` (bundled
  libraries), `docs/Makefile.in` and `scripts/Makefile.in` (installed files).
  The libraries must still come from the compat base; nothing may be fetched
  from FreeBSD packages or ports.
- **Installed files**: compare the new `nextbsd-contrib-pkg-<arch>.tar.gz`
  listing (the CI log prints it) with the previous one. nextbsd-pkg packages
  that tarball as-is.
- **Trim**: if upstream added large test data, extend the exclusions in
  `nextbsd-trim.sh` (and say why there).
- **Licence**: `COPYING` is still BSD-2-Clause.

## 4. Docs, then a PR

- Update `src/pkg/NEXTBSD.md` (version, commit, SHA-256, file count, anything
  learnt), the `NOTICE.md` row and the README components table.
- Push the branch and open a PR against `main` with: the version change and
  upstream's NEWS highlights for the range, whether the patches applied as-is
  or how they were refreshed, any soname or installed-file change, and the
  downstream follow-ups (nextbsd-pkg repackaging, which the maintainer runs by
  hand).
- CI as-is is the only gate: both arches must build and every `build_pkg` check
  must pass (including the checks that both patches are compiled in). Do not add
  tests. **Never merge**, and never dispatch nextbsd-pkg or the image builds.
