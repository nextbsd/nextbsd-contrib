# squashfs-tools-ng on NextBSD

**Source:** the squashfs-tools-ng 1.3.2 release tarball
`squashfs-tools-ng-1.3.2.tar.xz` from https://infraroot.at/pub/squashfs/
(upstream's release site; the GitHub mirror at AgentD/squashfs-tools-ng has
the tag but no release asset with a generated `configure`).

| | |
|---|---|
| Version | 1.3.2 (`libsquashfs.so.1`) |
| SHA-256 | `0d907ac3e735c351e47c867fb51d94bffa3b05fb95bec01f31e848b7c44215a9` (matches FreeBSD ports' `filesystems/squashfs-tools-ng/distinfo`; upstream also publishes a GPG signature) |
| Licence | `dist/COPYING.md`: **libsquashfs** (`lib/sqfs`, `lib/util`, `include/sqfs`) is **LGPL-3.0-or-later**, with an embedded xxhash32 (BSD-2-Clause) and Mesa hash table (MIT). The **tools** are **GPL-3.0-or-later**. Licence texts in `dist/licenses/` |

**Why it is here.** Gershwin reads AppImage payloads through libsquashfs
without mounting them: Workspace's `AppImageIconProvider` for icons, and
`make_services`' `AppImageReader` to register AppImages as applications (E24
audit 4, §3; nextbsd/nextbsd-contrib#9). Both find it with
`pkg-config libsquashfs` or `sqfs/predef.h` + `-lsquashfs`.

**What is vendored:** the release tarball in full, in `dist/`. It is small
(368 files), and `config.status` writes files under `tests/` that must exist.
`nextbsd-trim.sh` verifies the SHA-256 and copies it. Nothing is modified.

**Build:** `build_squashfs_tools_ng` in `build-contrib.sh`. Upstream
`configure` in cross mode on a copy of `dist/` whose files are given one mtime
(the release has no `AM_MAINTAINER_MODE`, so automake's rebuild rules would
otherwise fire on checkout order). No configure check runs a test program.
Options: `--prefix=/usr --mandir=/usr/share/man
--with-pkgconfigdir=/usr/libdata/pkgconfig --enable-shared --disable-static
--with-gzip --with-xz --with-lz4 --with-zstd --with-bzip2 --without-lzo
--without-selinux --disable-doxygen-doc`.

Compressors: gzip (`libz`), xz (`liblzma`) and bzip2 (`libbz2`, for tarballs in
`tar2sqfs`/`sqfs2tar`) from the base; lz4 and zstd from this repo, built just
before. LZO is left out: it is GPL-2.0, rare in squashfs images, and AppImages
do not use it. The libraries' flags are passed as `ZLIB_CFLAGS`/`ZLIB_LIBS` and
so on, which configure takes in place of a pkg-config lookup; `PKG_CONFIG_LIBDIR`
points at the sysroot so a host pkg-config cannot leak host paths in.
Then upstream `make` and `make install`.

**Shipped:**

| Path | What | Mode |
|---|---|---|
| `/usr/bin/gensquashfs`, `rdsquashfs`, `sqfs2tar`, `sqfsdiff`, `tar2sqfs` | the tools (GPL-3.0-or-later) | 0555 |
| `/usr/lib/libsquashfs.so.1.*`, `libsquashfs.so.1` and `libsquashfs.so` links | libsquashfs (LGPL-3.0-or-later) | 0444 |
| `/usr/include/sqfs/*.h` | its headers | 0444 |
| `/usr/libdata/pkgconfig/libsquashfs1.pc` | | 0444 |
| `/usr/share/man/man1/` the five tools' pages | | 0444 |

No static library, no libtool archive.

**Updating:**
1. Check the new release's tarball, SHA-256 and signature on
   https://infraroot.at/pub/squashfs/.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and run
   `sh src/squashfs-tools-ng/nextbsd-trim.sh squashfs-tools-ng-VERSION.tar.xz src/squashfs-tools-ng/dist`.
3. Re-check `COPYING.md` for licence changes and the configure options above.
4. Update the version and SHA-256 above and the `NOTICE.md` and `README.md` rows.
