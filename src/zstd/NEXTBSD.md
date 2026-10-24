# zstd on NextBSD

**Source:** the Zstandard 1.5.7 release asset `zstd-1.5.7.tar.gz` from
https://github.com/facebook/zstd/releases/tag/v1.5.7.

| | |
|---|---|
| Version | 1.5.7 |
| SHA-256 | `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3` (matches the `.sha256` file published with the release) |
| Licence | dual BSD-3-Clause (`dist/LICENSE`) or GPL-2.0 (`dist/COPYING`), at the user's choice; NextBSD uses it under the BSD licence |

**Why it is here.** squashfs-tools-ng and squashfuse (nextbsd/nextbsd-contrib#9)
need a public `libzstd`. The compat base builds zstd only as a private library
(`libprivatezstd`, headers under `/usr/include/private/zstd`), which other
software must not link. This is the public library, with the soname
(`libzstd.so.1`) every other system uses.

**What is vendored**, in `dist/`: `lib/` in full except the Windows `dll/`
directory and the Buck build file, plus `LICENSE`, `COPYING`, `README.md` and
`CHANGELOG`. `nextbsd-trim.sh` produces it from the tarball after verifying the
SHA-256. Nothing is modified.

**Left out:** the `zstd` programs (`programs/`; base already has `/usr/bin/zstd`
and friends), `contrib/`, `tests/`, `examples/`, `doc/`, `zlibWrapper/` and the
alternative build systems under `build/`.

**Build:** `build_zstd` in `build-contrib.sh`, with upstream's `lib/Makefile`
(no configure). It builds inside its own tree, so it runs on a copy of `dist/`.
The Makefile picks the platform from `uname`, which on the runner is Linux, so
`UNAME=FreeBSD` is passed: that selects the ELF soname flags and
`PKGCONFIGDIR=/usr/libdata/pkgconfig`, as on FreeBSD. Targets:
`libzstd-release libzstd.pc`, then `install-shared install-includes
install-pc` with `PREFIX=/usr`. The shared library is multithreaded, as
upstream builds it (`-DZSTD_MULTITHREAD`, `-pthread`, so it links `libthr`).
No static library.

**Shipped:**

| Path | Mode |
|---|---|
| `/usr/lib/libzstd.so.1.5.7`, `libzstd.so.1` and `libzstd.so` links | 0444 |
| `/usr/include/zstd.h`, `zstd_errors.h`, `zdict.h` | 0444 |
| `/usr/libdata/pkgconfig/libzstd.pc` | 0444 |

**Updating:**
1. Take the new release's `.tar.gz` and its published `.sha256`.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and run
   `sh src/zstd/nextbsd-trim.sh zstd-VERSION.tar.gz src/zstd/dist`.
3. Update the version, SHA-256 and shipped file names above and the
   `NOTICE.md` and `README.md` rows.
