# Vendored sources & licences

`nextbsd-contrib` vendors third-party programs NextBSD ships in base, each
**under its own upstream licence**, preserved in-tree under `src/<name>/dist/`.
Those files and their headers are authoritative; this table records provenance
and does not relicense anything.

The top-level **`LICENSE` (BSD 2-Clause)** covers only what this repo authors:
`build-contrib.sh`, the `nextbsd-trim.sh` scripts, `NEXTBSD.md` notes,
`.github/workflows/`, this `NOTICE.md` and `README.md`.

| Component | Upstream | Version | Licence |
|---|---|---|---|
| `sudo` | apple-oss-distributions/sudo, trimmed to sudo + visudo | `sudo-114.100.11` (upstream 1.9.17p2) | ISC-style "Sudo license" (`src/sudo/dist/LICENSE.md`) |
| `pico` | Alpine (alpineapp.email), trimmed to pico | `alpine-2.26` (pico 5.09) | Apache-2.0 (`src/pico/dist/LICENSE`; c-client parts `src/pico/dist/imap/LICENSE`, Apache-2.0) |
| `zsh` | zsh.org release tarball; four GPL-licensed completion files left out | 5.9.2 | zsh licence, MIT-like (`src/zsh/dist/LICENCE`) |
| `zsh-autosuggestions` | zsh-users/zsh-autosuggestions | v0.7.1 | MIT (`src/zsh-autosuggestions/dist/LICENSE`) |
| `zsh-completions` | zsh-users/zsh-completions; every file header checked, none copyleft | 0.36.0 | zsh licence (`src/zsh-completions/dist/LICENSE`), with BSD, MIT, Apache-2.0 and ISC per-file headers |
