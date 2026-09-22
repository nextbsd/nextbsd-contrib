# zsh-autosuggestions on NextBSD

**Source:** https://github.com/zsh-users/zsh-autosuggestions, release tag
`v0.7.1`, as GitHub's archive
`https://github.com/zsh-users/zsh-autosuggestions/archive/refs/tags/v0.7.1.tar.gz`.

| | |
|---|---|
| Version | 0.7.1 (the latest tag; the project publishes tags, not releases) |
| Tag commit | `e52ee8ca55bcc56a17c828767a3f98f22a68d4eb` |
| SHA-256 | `0df7affff21cd87ed298e6a3970ed08a1dd66a6efa676454ee5b091ad503badf` (of the archive as downloaded; GitHub archives are stable for a given tag) |
| Licence | MIT (`dist/LICENSE`, and the header of `zsh-autosuggestions.zsh`) |

**What is vendored**, in `dist/`, 18 of the tag's 61 files. `nextbsd-trim.sh`
produces it after verifying the SHA-256:

- `zsh-autosuggestions.zsh`, the assembled plugin that is installed. Upstream
  builds it from `src/` with `make` and commits the result; the release
  contains it, so nothing is generated here.
- `zsh-autosuggestions.plugin.zsh`, the one-line loader plugin managers use.
- `src/`, `Makefile`, `VERSION`, `ZSH_VERSIONS`, `LICENSE`, `README.md`, so
  the shipped file can be reproduced and its provenance read.

**Left out:** the `spec/` test suite and its Ruby, Docker and install-test
scaffolding, `CHANGELOG.md`, `INSTALL.md`, `DESCRIPTION`, `URL`.

## Install

`build_zsh_autosuggestions` in `build-contrib.sh` installs the two `.zsh`
files, mode 0444, into `/usr/share/zsh/plugins/zsh-autosuggestions/`. There is
no build step. NextBSD's `/etc/zshrc` (nextbsd/nextbsd-userland#254, U8)
sources `zsh-autosuggestions.zsh` from there; nothing is enabled by this
package on its own.

**Updating:**
1. Check the new tag on GitHub and fetch its archive.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and here (with the tag
   commit), and re-run `nextbsd-trim.sh <tarball> src/zsh-autosuggestions/dist`.
3. Confirm `dist/zsh-autosuggestions.zsh` still carries the MIT header.
4. Update `NOTICE.md`.
