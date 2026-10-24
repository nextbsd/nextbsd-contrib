# squashfuse on NextBSD

**Source:** the squashfuse 0.6.5 release asset `squashfuse-0.6.5.tar.gz` from
https://github.com/vasi/squashfuse/releases/tag/0.6.5.

| | |
|---|---|
| Version | 0.6.5 |
| SHA-256 | `9ec44b8ee6309e09bdcdeba422edc745e876db16136acacb74ecc7e7131e5763` |
| Licence | BSD-2-Clause (`dist/LICENSE`); `squashfs_fs.h` is Phillip Lougher's, used under the same terms with his permission, as `LICENSE` records |

**Why it is here.** Gershwin mounts squashfs images with it: Workspace's
`VolumeManager` when a `.squashfs` file is opened, and gershwin-system's
`MountSystemImage.sh` (`squashfuse -o allow_other <image> /System`) (E24 audit
4, §3; nextbsd/nextbsd-contrib#9). AppImages themselves carry their own
squashfuse in their runtime; this is desktop integration, not a requirement for
running them.

**What is vendored:** the release tarball in full, in `dist/`. It is small
(107 files), and `config.status` writes files under `tests/` and `ci/` that
must exist. `nextbsd-trim.sh` verifies the SHA-256 and copies it. Nothing is
modified.

**Build:** `build_squashfuse` in `build-contrib.sh`. Upstream `configure` in
cross mode on a copy of `dist/` whose files are given one mtime (no
`AM_MAINTAINER_MODE`; see squashfs-tools-ng). No configure check runs a test
program. Options: `--prefix=/usr --mandir=/usr/share/man --enable-shared
--disable-static --disable-demo --without-lzo`.

FUSE is libfuse3 from this repo. Its flags are passed as
`pkgconfig_fuse3_CFLAGS`/`pkgconfig_fuse3_LIBS`, the override configure
documents for its pkg-config lookup; found that way, configure selects the
FUSE 3.2 API (`FUSE_USE_VERSION=32`). The decompressors are passed the same
way: zlib and xz from the base, lz4 and zstd from this repo. LZO is left out,
as for squashfs-tools-ng. Then upstream `make`, and only the two drivers and
their man pages are installed.

**Shipped:**

| Path | What | Mode |
|---|---|---|
| `/usr/bin/squashfuse` | high-level FUSE driver | 0555 |
| `/usr/bin/squashfuse_ll` | low-level, multithreaded FUSE driver | 0555 |
| `/usr/share/man/man1/squashfuse.1`, `squashfuse_ll.1` | | 0444 |

Both link squashfuse's own code statically (upstream's convenience
libraries), so `libsquashfuse`, `libsquashfuse_ll`, their headers and `.pc`
files are not shipped; nothing in NextBSD or Gershwin links them. The demo
programs (`squashfuse_ls`, `squashfuse_extract`) are not built.

**At run time** mounting goes through libfuse, which runs base's
`/sbin/mount_fusefs`; see `src/libfuse/NEXTBSD.md`.

**Updating:**
1. Take the new release's tarball and its SHA-256.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and run
   `sh src/squashfuse/nextbsd-trim.sh squashfuse-VERSION.tar.gz src/squashfuse/dist`.
3. Update the version and SHA-256 above and the `NOTICE.md` and `README.md` rows.
