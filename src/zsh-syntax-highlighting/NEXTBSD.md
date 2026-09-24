# zsh-syntax-highlighting on NextBSD

**Source:** https://github.com/zsh-users/zsh-syntax-highlighting, release tag
`0.8.0`, as GitHub's archive
`https://github.com/zsh-users/zsh-syntax-highlighting/archive/refs/tags/0.8.0.tar.gz`.

| | |
|---|---|
| Version | 0.8.0 |
| Tag commit | `db085e4661f6aafd24e5acb5b2e17e4dd5dddf3e` (matches the `.revision-hash` the tag ships) |
| SHA-256 | `5981c19ebaab027e356fe1ee5284f7a021b89d4405cc53dc84b476c3aee9cc32` (of the archive as downloaded; GitHub archives are stable for a given tag) |
| Licence | BSD 3-Clause (`dist/COPYING.md`, and the header of every `.zsh` file) |

**Why this one and not `fast-syntax-highlighting`,** which GhostBSD uses: we
already vendor `zsh-autosuggestions` and `zsh-completions` from zsh-users, so
all three plugins sit under one upstream with one release cadence and one
licence to track. `fast-syntax-highlighting` has already changed organisations
once, from `zdharma` to `zdharma-continuum`, after the original disappeared.
For something shipped in base a stable upstream matters more than being
marginally faster.

**What is vendored**, in `dist/`, 17 of the tag's 348 files.
`nextbsd-trim.sh` produces it after verifying the SHA-256:

- `zsh-syntax-highlighting.zsh`, the entry point that `/etc/zshrc` sources.
- `.version` and `.revision-hash`. These are **required at run time**, not
  documentation: the entry point reads both unconditionally when it loads, to
  set `ZSH_HIGHLIGHT_VERSION` and `ZSH_HIGHLIGHT_REVISION`.
- `highlighters/`, all seven (`main`, `brackets`, `cursor`, `line`, `pattern`,
  `regexp`, `root`), so a user can select any of them. The entry point loads
  them from a directory beside itself.
- `zsh-syntax-highlighting.plugin.zsh`, the loader stub plugin managers use.
- `COPYING.md`, `README.md`, `changelog.md`, `Makefile`,
  `docs/highlighters.md`, `highlighters/README.md` for provenance and
  reference.

**Left out:** the `highlighters/*/test-data/` corpora, which are the bulk of
the tag, the `tests/` harness, `.github/`, the `images/` screenshots, and the
editor and release scaffolding (`.editorconfig`, `.gitattributes`,
`.gitignore`, `HACKING.md`, `INSTALL.md`, `release.md`).

**One detail worth recording:** the per-highlighter `README.md` files are
symlinks upstream, not regular files, so the trim script's `-type f` excludes
them deliberately. Copying them would leave dangling links in the package.

## Install

`build_zsh_syntax_highlighting` in `build-contrib.sh` installs the tree, mode
0444, into `/usr/share/zsh/plugins/zsh-syntax-highlighting/`, alongside where
`zsh-autosuggestions` goes. There is no build step; nothing is compiled, so the
result is identical for both architectures.

NextBSD's `/etc/zshrc` (nextbsd/nextbsd-overlays#11, E18 U8) sources the entry
point from there and selects the `main` and `brackets` highlighters. Nothing is
enabled by this package on its own, and `NEXTBSD_ZSH_PLUGINS=no` in
`~/.zshenv` turns it off.

**Updating:**
1. Check the new tag on GitHub and fetch its archive.
2. Set `VERSION` and `SHA256` in `nextbsd-trim.sh` and here (with the tag
   commit), and re-run
   `nextbsd-trim.sh <tarball> src/zsh-syntax-highlighting/dist`.
3. Confirm `dist/COPYING.md` is still BSD 3-Clause and that the `.zsh` headers
   agree.
4. Check whether upstream added a highlighter, and whether `.version` and
   `.revision-hash` are still read at load time.
5. Update `NOTICE.md`.
