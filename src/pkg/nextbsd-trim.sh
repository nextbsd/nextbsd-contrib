#!/bin/sh
# nextbsd-trim.sh <pkg-2.8.4.tar.gz> <dest>   (dest: src/pkg/dist)
# Verify the upstream release archive (GitHub's archive of freebsd/pkg tag
# 2.8.4, the same file FreeBSD's ports-mgmt/pkg fetches), then copy the tree
# into dest minus libecc's test vectors and upstream's CI scaffolding. Nothing
# copied is modified; the NextBSD patches live in src/pkg/patches/ and are
# applied at build time. scripts/sync-pkg.sh rewrites VERSION, COMMIT and
# SHA256 here on a deliberate upgrade.
set -eu
TARBALL=${1:?usage: nextbsd-trim.sh <pkg-VERSION.tar.gz> <dest>}
DEST=${2:?usage: nextbsd-trim.sh <pkg-VERSION.tar.gz> <dest>}
VERSION=2.8.4
COMMIT=e1d90eb706cbb4588bbd71bf205843b751c0be51
SHA256=b7b71b1d11c8c021bab41e064778c0f8184c41eb4ced91b0951acfdc0538da47

if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
[ "$got" = "$SHA256" ] || { echo "SHA-256 mismatch for $TARBALL: $got" >&2; exit 1; }

mkdir -p "$DEST"; DEST=$(cd "$DEST" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xzf "$TARBALL"
SRC="$TMP/pkg-$VERSION"
[ -f "$SRC/configure.def" ] || { echo "no configure.def in $SRC" >&2; exit 1; }
grep -q "^_min_ver=${VERSION##*.}\$" "$SRC/configure.def" \
    || { echo "configure.def does not say $VERSION" >&2; exit 1; }

find "$DEST" -mindepth 1 -delete
(
    cd "$SRC"
    # Left out:
    #   external/libecc/src/{examples,tests,wycheproof_tests}: libecc's own
    #     test programs and test vectors (68 MB of the archive's 103 MB,
    #     including a 49 MB header). external/libecc/Makefile.in builds none
    #     of them and nothing pkg compiles includes them.
    #   .builds/ .github/ .gitlab-ci.yml: upstream CI.
    #   .gitignore: it would hide upstream files from this repo's git.
    find . -type f \
        ! -path './external/libecc/src/examples/*' \
        ! -path './external/libecc/src/tests/*' \
        ! -path './external/libecc/src/wycheproof_tests/*' \
        ! -path './.builds/*' \
        ! -path './.github/*' \
        ! -name '.gitlab-ci.yml' \
        ! -path './.gitignore'
) | sort | while IFS= read -r f; do
    f=${f#./}
    mkdir -p "$DEST/$(dirname "$f")"
    cp -p "$SRC/$f" "$DEST/$f"
done
echo "trimmed pkg $VERSION ($COMMIT) into $DEST: $(find "$DEST" -type f | wc -l) files"
