# nextbsd-contrib

Third-party programs that NextBSD ships in base, built from their own upstream
sources. This is the third of the three source halves of the system:

| Repo | What it holds | Package |
|---|---|---|
| `nextbsd-freebsd-compat` | FreeBSD sources: libc, PAM, the POSIX command suites | `NextBSD-freebsd-compat` |
| `nextbsd-userland` | Darwin sources: Mach, launchd, CoreFoundation, configd, IOKit, the daemons, and NextBSD's own system code | `NextBSD-userland` |
| **`nextbsd-contrib`** | **Upstream projects from neither, vendored unmodified: sudo, zsh, pico** | **`NextBSD-contrib`** |

The name follows FreeBSD's `/usr/src/contrib`, which holds exactly this kind of
thing: upstream code that is part of base but is not the project's own. tcsh
lives there and is `/bin/csh`; if zsh ever becomes `/bin/sh` here, it is still
contrib.

## Why a separate repo

- These trees are large and change only on a version bump. Keeping them out of
  `nextbsd-userland` keeps that repo's diffs, clones and reviews about the code
  that is actively worked on.
- They depend on the FreeBSD base only (PAM, ncurses, libz), never on anything
  from `nextbsd-userland`. So they build straight from the compat sysroot, in
  parallel with userland, and a launchd change never rebuilds sudo.
- They share one build shape: upstream `configure` run in cross mode, then only
  the pieces NextBSD ships. One driver handles all of them.

## The rule for what goes here

A component belongs in this repo when all of these hold:

1. **Upstream is neither Apple nor FreeBSD.** Darwin sources go to
   `nextbsd-userland`; FreeBSD sources go to `nextbsd-freebsd-compat`. (A
   project may still be *taken from* Apple's tree, as sudo is, when Apple's copy
   is upstream plus `__APPLE__` patches that compile out here.)
2. **It is vendored unmodified**, under `src/<name>/dist/`, with a trim script
   that reproduces the tree from an upstream checkout and a `NEXTBSD.md` that
   records the version, what was left out, and how to update.
3. **It links only against the compat sysroot.** Nothing here may link a
   library from `nextbsd-userland`. That is what keeps this repo out of the
   userland build chain.
4. **It ships no `/etc`.** Configuration is seeded once from
   `nextbsd-overlays` (`/etc/sudoers`, `/etc/pam.d/sudo`, `/etc/shells`, the
   zsh startup files).

NextBSD's own code is not contrib, even when it is small and account-related:
`nss_directory_services`, `dscli` and the `passwd`/`chpass`/`pw` wrappers
(nextbsd/nextbsd#495) belong in `nextbsd-userland`. `dscli` links `libdns_sd`
from there, and the wrappers collide with base paths, which compat's collision
check derives from userland's file list.

## Components

| Component | Upstream | Installs | Ticket |
|---|---|---|---|
| `sudo` | apple-oss-distributions/sudo `sudo-114.100.11` (upstream 1.9.17p2), trimmed to sudo + visudo | `/usr/bin/sudo` (4511), `/usr/sbin/visudo`, man pages | nextbsd/nextbsd-userland#247 |
| `zsh` | zsh 5.9, zsh-autosuggestions, zsh-completions | `/bin/zsh`, `/usr/share/zsh/…` | nextbsd/nextbsd-userland#248 (planned) |
| `pico` | Alpine 2.26 | `/usr/bin/pico`, `/usr/bin/nano` → `pico`, man pages | nextbsd/nextbsd-userland#261 (planned) |

Licences are per component; see `NOTICE.md`. The top-level `LICENSE` (BSD-2)
covers only the harness in this repo.

## Layout

```
build-contrib.sh          cross-build driver: every component, or one by name
src/<name>/dist/          the upstream tree, unmodified (collapsed in diffs)
src/<name>/nextbsd-trim.sh  reproduces dist/ from an upstream checkout
src/<name>/NEXTBSD.md     version, what is left out, build notes, update steps
.github/workflows/build.yml  CI: build both arches, publish `continuous`
NOTICE.md                 per-component provenance and licence
```

## Build model

`build-contrib.sh` runs inside the `nextbsd-kernel-toolchain` container with the
compat `continuous` base staged as the cross sysroot, the same setup
`nextbsd-userland` uses. It needs:

| Variable | Meaning |
|---|---|
| `T` | target: `amd64` or `arm64` |
| `TA` | FreeBSD `TARGET_ARCH`: `amd64` or `aarch64` |
| `SYSROOT` | the staged compat base |
| `CROSS_BINDIR` | the toolchain's clang and lld (set by the container image) |
| `DESTDIR` | where to stage; default `/stage` |

Each component runs its upstream `configure` with `--host=<triple>`, the cross
clang and `--sysroot`, out of tree under `.build/`, then builds and installs
only what NextBSD ships. Configure checks that would execute a test program get
their FreeBSD answers as cache variables; each component's `NEXTBSD.md` lists
them.

```
./build-contrib.sh          # every component
./build-contrib.sh sudo     # one component
```

## CI, artifact, package

The workflow builds both arches on every pull request and on `base-updated`
from `nextbsd-freebsd-compat`. On `main` it publishes
`nextbsd-contrib-<arch>.tar.gz` to the `continuous` release, rooted at `/`, and
dispatches `contrib-updated` to `nextbsd-pkg`.

`nextbsd-pkg` repackages the tarball verbatim as `NextBSD-contrib`, depending
on `NextBSD-freebsd-compat`, and adds it to `NextBSD-everything`.

**setuid.** The cross install runs unprivileged, so `build_sudo` itself
sets `4511` on `/usr/bin/sudo` after staging (the owner may set the bit). `pkg create` takes
modes from the staged tree, and a FreeBSD `chown` keeps setuid on files that
are already `0:0`, so the bit survives into the package. Anything that assembles
an image with a Linux `chown` has to re-apply it; Linux clears setuid on chown
even as root.

**Testing.** This repo has no boot lane. On-image checks for its programs live
with the harness that boots images: `nextbsd-userland`'s
`overlay/usr/tests/freebsd-launchd-mach/run.sh` and `tests/boot-test.sh`, whose
image assembly fetches this repo's `continuous` artifact.

## Adding a component

1. `src/<name>/nextbsd-trim.sh`: copies only what the shipped programs need
   from an upstream checkout into `src/<name>/dist/`. Re-run it on every update;
   never hand-edit `dist/`.
2. `src/<name>/NEXTBSD.md`: upstream, tag or tarball and its SHA-256, licence,
   what was left out and why, configure cache variables, what is installed with
   modes, update steps.
3. A section in `build-contrib.sh`, registered in `COMPONENTS`.
4. A row in `NOTICE.md` and in the table above. `.gitattributes` already
   collapses every `src/*/dist/**`.
5. Configuration, if any, goes to `nextbsd-overlays`, not here.
6. If the programs replace FreeBSD tools at the same path, add those paths to
   `nextbsd-freebsd-compat`'s `scripts/collisions` (and teach its derivation to
   read this repo's file list) or `scripts/superseded`.
