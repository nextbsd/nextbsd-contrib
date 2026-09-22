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

Planned, not yet vendored: `zsh` (zsh licence, MIT-like; a few GPL files under
`Functions/` are left out), `zsh-autosuggestions` (MIT), `zsh-completions` (zsh
licence, per-file provisions checked when vendoring), `pico` from Alpine
(Apache-2.0).
