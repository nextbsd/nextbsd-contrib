# netdumpd on NextBSD

**Source:** markjdb/netdumpd on GitHub (https://github.com/markjdb/netdumpd),
commit `99dd0da99be7612b1feb52e4f71db308415e0259` (October 27, 2023, "Add
SPDX identifiers"), the newest commit. Upstream makes no releases on GitHub.
FreeBSD's port `ftp/netdumpd` uses upstream's dated snapshot 20220406, and
this commit is that code plus SPDX tags and the removal of `$FreeBSD$`
version strings.

| | |
|---|---|
| Archive | GitHub's archive of the commit, `netdumpd-99dd0da99be7612b1feb52e4f71db308415e0259.tar.gz` |
| SHA-256 | `666c54fb3ae171639ec7fa3738d11f52a97169b847ef9008fdc0d459e4dac6f4` |
| Verified | upstream publishes no signature or checksum; the SHA-256 is of GitHub's archive as fetched on 2026-11-28 |
| Licence | BSD 2-Clause, in each file's header (upstream has no separate licence file). Copyright Sandvine Incorporated, Dell EMC, Mark Johnston, and The FreeBSD Foundation (`cap_dns.c`, `cap_dns.h`) |
| Used by | Server.app's crash dumps (E42, nextbsd/nextbsd#654): one computer collects kernel crash dumps that others send with `dumpon -s` |

**What netdumpd is.** It's the server half of netdump. A FreeBSD (and
NextBSD) kernel configured with `dumpon -s <server>` sends its crash dump
over UDP when it panics. netdumpd receives it and writes `info.*` and
`vmcore.*` files under `/var/crash` (or a per-client directory), like
`savecore(8)` does for a local dump. The client half is already in NextBSD:
the kernel's `NETDUMP` and `DEBUGNET` options (from `GENERIC`, which
`config/NEXTBSD` includes) and `dumpon(8)` in the base.

**What is vendored**, in `dist/`: 9 of the archive's 16 files.
`nextbsd-trim.sh` downloads the archive, checks the SHA-256 and produces it.
Nothing in `dist/` is modified.

- Kept: `netdumpd.c`, `netdumpd.h`, `cap_dns.c`, `cap_dns.h`, `cap_handler.c`,
  `cap_herald.c`, `kerneldump_compat.h`, `netdumpd.8`, and upstream's
  `Makefile` (not used here; kept as the record of upstream's sources and
  flags).
- Left out:
  - `etc/`: an rc.d script and its Makefiles. NextBSD starts netdumpd from a
    launchd job instead (see "Starting it");
  - `client/`: `netdump-client`, a test tool that sends a fake dump. It isn't
    shipped;
  - `mktar`: upstream's script for making its snapshot tarballs;
  - `.gitignore`.

## Build

`build_netdumpd` in `build-contrib.sh`. Upstream builds with `bsd.prog.mk`,
which this repo doesn't use, and there is no `configure`. The four sources
are compiled directly with the cross clang, using the flags from upstream's
`Makefile`:

- `-DWITH_CASPER` (netdumpd runs in Capsicum capability mode and does DNS
  lookups, runs its post-dump script and reports in through three Casper
  services of its own: `cap_dns.c`, `cap_handler.c`, `cap_herald.c`);
- linked with `-lcasper -lnv -lutil` from the compat sysroot.

Nothing links against nextbsd-userland. The compat base has `libcasper`,
`libnv`, `libutil`, `capsicum_helpers.h`, `libcasper_service.h`, `sys/nv.h`
and `sys/kerneldump.h`. netdumpd's own `cap_dns.c` is compiled in; the base's
`libcap_dns` isn't used. The build checks that the binary's `DT_NEEDED` names
`libcasper`, `libnv` and `libutil`, and that nothing staged replaces a base
file.

**Installed:**

| Path | Mode |
|---|---|
| `/usr/sbin/netdumpd` | 0555 |
| `/usr/share/man/man8/netdumpd.8` | 0444 |

## Starting it

netdumpd is a daemon, but only on the one computer that collects crash
dumps, and only while collecting is turned on in Server.app. It is started by
`org.nextbsd.netdumpd`, a launchd job in nextbsd-userland's overlay
(`/System/Library/LaunchDaemons`), shipped with `Disabled` set, like
`org.nextbsd.ntpd`.

- The job runs `netdumpd -D` (`-D` keeps it in the foreground with its output
  on stdout, which launchd needs; without it netdumpd calls `daemon(3)`).
- Dumps go to the default `/var/crash`.
- netdumpd does no authentication of clients (netdumpd.8, SECURITY).
  Server.app turns it on only for computers on the same network, and
  `dumpon -s` on each sender names this computer's address.

No `/etc` file is shipped.

## Updating

1. Pick the new commit on github.com/markjdb/netdumpd. Read its log since
   `99dd0da`, and compare it with FreeBSD's `ftp/netdumpd` port.
2. Set `COMMIT` and `SHA256` in `nextbsd-trim.sh`. The SHA-256 is of
   `https://github.com/markjdb/netdumpd/archive/<commit>.tar.gz`.
3. Run `src/netdumpd/nextbsd-trim.sh src/netdumpd/dist` and review the diff.
4. If the sources or `LDADD` in upstream's `Makefile` changed, update
   `build_netdumpd` to match.
5. Update the version in this file, `NOTICE.md` and `README.md`.
