# zsh-completions on NextBSD

**Source:** https://github.com/zsh-users/zsh-completions, release tag
`0.36.0`, as GitHub's archive
`https://github.com/zsh-users/zsh-completions/archive/refs/tags/0.36.0.tar.gz`.

| | |
|---|---|
| Version | 0.36.0 (the latest release) |
| Tag commit | `28c5bdcaf81bb89e56d0df8267d822c3b8aed9e0` |
| SHA-256 | `5aa68be2999a7be2eb56de8e4acff8f3bba4a66b9acbb233752536857408fb2e` (of the archive as downloaded; GitHub archives are stable for a given tag) |
| Licence | the zsh licence (`dist/LICENSE`), with per-file provisions taking precedence |

**What is vendored**, in `dist/`: `LICENSE`, `README.md` and all 180
completion functions under `src/`. `nextbsd-trim.sh` produces it after
verifying the SHA-256. Left out: `CONTRIBUTING.md`, the how-to document and
the plugin-manager stub `zsh-completions.plugin.zsh`.

**Per-file licences.** The repository licence says provisions in individual
files take precedence, so every `src/_*` header was read when this version was
vendored. None is copyleft, so nothing is excluded:

| Header | Files |
|---|---|
| BSD 3-clause (zsh-users template) | 85 |
| MIT | 60 |
| none (the repository's zsh licence applies) | 31 |
| Apache-2.0 (`_cf`, `_hledger`) | 2 |
| ISC | 1 |
| zsh licence, stated in the file | 1 |

The trim script refuses a future release whose headers mention the GPL, so a
newly copyleft file cannot arrive unnoticed; exclude it there and record it
here.

## Install

`build_zsh_completions` in `build-contrib.sh` installs `src/_*`, mode 0444,
into `/usr/share/zsh/site-functions/`, which zsh puts first in the default
`fpath`. A file whose name zsh itself ships under `Completion/` is skipped at
install time, so the copy maintained with the shell is the one that loads; at
0.36.0 against zsh 5.9.2 that is `_age`, `_blkid` and `_nano`. The check is
by name against `src/zsh/dist/Completion`, so it tracks both trees on update.

There is no build step. `compinit` (from `/etc/zshrc`, U8) picks the files up
with no further configuration.

**Updating:**
1. Check the new release on GitHub and fetch its archive.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and here (with the tag
   commit), and re-run `nextbsd-trim.sh <tarball> src/zsh-completions/dist`.
   It stops if any header mentions the GPL.
3. Re-count the licence table above (headers are in the first 40 lines).
4. Update `NOTICE.md`.
