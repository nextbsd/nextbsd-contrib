# libfuse on NextBSD

**Source:** the libfuse 3.18.3 release asset `fuse-3.18.3.tar.gz` from
https://github.com/libfuse/libfuse/releases/tag/fuse-3.18.3.

| | |
|---|---|
| Version | 3.18.3 (soname `libfuse3.so.4`) |
| SHA-256 | `bcd19582c5e30f7fe45dd86a5540e998590aa01903afc7ebcbeea6c8ac5421ee` (matches FreeBSD ports' `filesystems/fusefs-libs3/distinfo`) |
| Licence | LGPL-2.1 for `lib/` and `include/` (`dist/LICENSE`, `dist/LGPL2.txt`); everything vendored is under it, except `include/fuse_kernel.h` (GPL-2.0 or BSD-2-Clause, not installed) and `lib/usdt.h` (BSD-2-Clause). `dist/GPL2.txt` is kept because `LICENSE` refers to it; the GPL-2.0 parts upstream (`util/`, `example/`, `test/`) are not vendored |

**Why it is here.** squashfuse (nextbsd/nextbsd-contrib#9) is a FUSE file
system. The kernel side of FUSE is compiled into the NextBSD kernel
(nextbsd/nextbsd-kernel#60) and the base has `/sbin/mount_fusefs`, but there is
no userland library: that is this.

**What is vendored**, in `dist/`: `meson.build`, `meson_options.txt`, `lib/`,
`include/`, `LICENSE`, `LGPL2.txt`, `GPL2.txt`, `README.md`, `AUTHORS`,
`ChangeLog.rst`. `nextbsd-trim.sh` produces it from the tarball after verifying
the SHA-256. Nothing is modified.

**Left out:** `util/` (fusermount3 and mount.fuse3, which `meson.build` never
builds on a BSD; libfuse there mounts by running `mount_fusefs`), `example/`,
`test/`, `doc/`, `dev-docs/`, `xfstests/`, `signify/` and the release scripts.

**Build:** `build_libfuse` in `build-contrib.sh`, with upstream's meson build,
cross: a cross file names the toolchain clang with `--target` and `--sysroot`,
lld as its linker (`c_ld = 'lld'`, not `--ld-path` in the compiler command:
meson runs its compile-only checks with `-Werror=unused-command-line-argument`,
and a linker flag would fail all of them), `llvm-ar`/`llvm-strip`, and
`host_machine.system = 'freebsd'`.
meson and ninja are host tools CI installs from the runner image's apt sources.
Options: `--prefix=/usr --libdir=lib --buildtype=release -Dutils=false
-Dexamples=false -Dtests=false -Denable-io-uring=false`. meson chooses the
pkg-config directory from the build host, so `stage_root` moves `fuse3.pc` from
`/usr/lib/pkgconfig` to `/usr/libdata/pkgconfig`, where FreeBSD's meson would
have put it.

**Shipped:**

| Path | Mode |
|---|---|
| `/usr/lib/libfuse3.so.3.18.3`, `libfuse3.so.4` and `libfuse3.so` links | 0444 |
| `/usr/include/fuse3/` (`fuse.h`, `fuse_common.h`, `fuse_lowlevel.h`, `fuse_opt.h`, `fuse_log.h`, `cuse_lowlevel.h`, `libfuse_config.h`) | 0444 |
| `/usr/libdata/pkgconfig/fuse3.pc` | 0444 |

**At run time** libfuse runs `mount_fusefs` through `PATH`, so `/sbin` must be
on it. Mounting as a user other than root needs the `vfs.usermount` sysctl;
NextBSD does not change its default here.

**Updating:**
1. Check the new release's tarball and its signature on the release page.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and run
   `sh src/libfuse/nextbsd-trim.sh fuse-VERSION.tar.gz src/libfuse/dist`.
3. Check `meson.build` still keeps `util/` off on BSD and that `lib/` needs
   nothing outside the vendored set.
4. Update the version, SHA-256 and soname above and the `NOTICE.md` and
   `README.md` rows.
