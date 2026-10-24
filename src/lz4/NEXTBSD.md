# lz4 on NextBSD

**Source:** the LZ4 1.10.0 release asset `lz4-1.10.0.tar.gz` from
https://github.com/lz4/lz4/releases/tag/v1.10.0.

| | |
|---|---|
| Version | 1.10.0 |
| SHA-256 | `537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b` (matches the `.sha256` file published with the release) |
| Licence | BSD-2-Clause for everything in `lib/` (`dist/lib/LICENSE`). The rest of the upstream tree (the `lz4` program, tests, examples) is GPL-2.0-or-later and is not vendored |

**Why it is here.** squashfs-tools-ng and squashfuse (nextbsd/nextbsd-contrib#9)
read and write LZ4-compressed squashfs images. The compat base has no
userland lz4 library at all (lz4 in the FreeBSD tree is kernel-only).

**What is vendored**, in `dist/`: `lib/` in full except the Windows `dll/`
directory, plus `Makefile.inc` (which `lib/Makefile` includes for the platform
settings), `LICENSE`, `README.md` and `NEWS`. `nextbsd-trim.sh` produces it
from the tarball after verifying the SHA-256. Nothing is modified.

**Left out:** `programs/` (the GPL `lz4` command), `tests/`, `examples/`,
`contrib/`, `ossfuzz/`, `doc/`, the alternative build systems under `build/`,
and the top-level `Makefile`.

**Build:** `build_lz4` in `build-contrib.sh`, with upstream's `lib/Makefile`
on a copy of `dist/`. The platform comes from `uname` (Linux on the runner),
so `TARGET_OS=FreeBSD` is passed for the ELF soname and
`/usr/libdata/pkgconfig`. `BUILD_STATIC=no`, so no `liblz4.a`. Targets:
`lib-release`, then `install` with `PREFIX=/usr`.

**Shipped:**

| Path | Mode |
|---|---|
| `/usr/lib/liblz4.so.1.10.0`, `liblz4.so.1` and `liblz4.so` links | 0444 |
| `/usr/include/lz4.h`, `lz4hc.h`, `lz4frame.h` | 0444 |
| `/usr/libdata/pkgconfig/liblz4.pc` | 0444 |

(`lz4frame_static.h` and `lz4file.h` are installed by upstream only alongside
the static library, so they are not shipped.)

**Updating:**
1. Take the new release's `.tar.gz` and its published `.sha256`.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and run
   `sh src/lz4/nextbsd-trim.sh lz4-VERSION.tar.gz src/lz4/dist`.
3. Update the version, SHA-256 and shipped file names above and the
   `NOTICE.md` and `README.md` rows.
