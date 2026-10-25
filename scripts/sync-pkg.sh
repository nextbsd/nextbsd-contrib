#!/bin/sh
# =============================================================================
# scripts/sync-pkg.sh <version> — deliberate upgrade of the vendored pkg(8)
# =============================================================================
#
# The plain-script half of the per-repo sync pattern (E22, "Upstream path
# ownership and syncing"); the .claude/skills/sync-pkg skill is the other half.
# pkg is frozen in src/pkg/dist/ and changes only when someone runs this for a
# chosen upstream release. Nothing runs it on a schedule or follows upstream.
#
# What it does, on a new local branch sync/pkg-<version> cut from HEAD:
#   1. resolves freebsd/pkg tag <version> to its commit;
#   2. downloads GitHub's archive of the tag and takes its SHA-256;
#   3. writes VERSION, COMMIT and SHA256 into src/pkg/nextbsd-trim.sh and
#      re-runs it into src/pkg/dist/ (the trim script checks the SHA-256);
#   4. commits that as the vendor import, dist/ and the trim script only;
#   5. tries src/pkg/patches/series against the new tree (in a scratch copy;
#      dist/ is never patched) and reports what upstream changed that the
#      build or the patches depend on.
# It never edits a patch, never pushes and never opens a PR. Exit status is
# non-zero if a patch no longer applies; the import commit is kept, so the
# patches can be refreshed on top of it.
#
# Needs: git, curl, tar, patch, sha256sum or shasum. Run from anywhere in a
# clean checkout of nextbsd-contrib.
# =============================================================================
set -eu

NEW=${1:?usage: scripts/sync-pkg.sh <version>   (a freebsd/pkg release tag, e.g. 2.8.5)}
UPSTREAM=https://github.com/freebsd/pkg
ROOT=$(git rev-parse --show-toplevel)
TRIM="$ROOT/src/pkg/nextbsd-trim.sh"
DIST="$ROOT/src/pkg/dist"
PATCHES="$ROOT/src/pkg/patches"

die() { echo "sync-pkg: $*" >&2; exit 1; }
say() { echo "sync-pkg: $*"; }

cd "$ROOT"
[ -z "$(git status --porcelain)" ] || die "the working tree is not clean"
OLD=$(sed -n 's/^VERSION=//p' "$TRIM")
OLD_COMMIT=$(sed -n 's/^COMMIT=//p' "$TRIM")
[ "$NEW" != "$OLD" ] || die "pkg is already at $OLD"
case "$NEW" in *[!0-9.]*) die "'$NEW' is not a release version (development tags are not vendored)" ;; esac

# 1. The tag's commit (peeled if the tag is annotated; 2.8.4 is lightweight).
refs=$(git ls-remote "$UPSTREAM.git" "refs/tags/$NEW" "refs/tags/$NEW^{}")
[ -n "$refs" ] || die "no tag $NEW in $UPSTREAM"
COMMIT=$(printf '%s\n' "$refs" | awk '/\^\{\}$/ {print $1}')
[ -n "$COMMIT" ] || COMMIT=$(printf '%s\n' "$refs" | awk '{print $1; exit}')
say "tag $NEW is commit $COMMIT"

# 2. The archive and its SHA-256.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TARBALL="$TMP/pkg-$NEW.tar.gz"
curl -fsSL -o "$TARBALL" "$UPSTREAM/archive/refs/tags/$NEW.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then
    SHA256=$(sha256sum "$TARBALL" | cut -d' ' -f1)
else
    SHA256=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
fi
say "archive SHA-256 $SHA256 (compare with ports-mgmt/pkg/distinfo once the port has $NEW)"

# 3. + 4. The vendor import, on its own branch and in its own commit.
git checkout -q -b "sync/pkg-$NEW"
sed -i.bak -e "s/^VERSION=.*/VERSION=$NEW/" -e "s/^COMMIT=.*/COMMIT=$COMMIT/" \
    -e "s/^SHA256=.*/SHA256=$SHA256/" "$TRIM"
rm -f "$TRIM.bak"
sh "$TRIM" "$TARBALL" "$DIST"
git add -A src/pkg/dist src/pkg/nextbsd-trim.sh
git commit -q -m "pkg: vendor import freebsd/pkg $NEW (${COMMIT%"${COMMIT#???????}"})

Upstream freebsd/pkg, tag $NEW, commit $COMMIT, from
$UPSTREAM/archive/refs/tags/$NEW.tar.gz
SHA-256 $SHA256

Previous: $OLD ($OLD_COMMIT). Produced by scripts/sync-pkg.sh $NEW;
src/pkg/dist/ is unmodified upstream, trimmed by src/pkg/nextbsd-trim.sh."
say "committed the vendor import on branch sync/pkg-$NEW"

# 5. Do the NextBSD patches still apply? And what changed that matters?
WORK="$TMP/tree"; mkdir -p "$WORK"; cp -R "$DIST/." "$WORK/"
failed=""
while read -r p; do
    case "$p" in ''|'#'*) continue ;; esac
    if patch -d "$WORK" -p1 --forward --batch --quiet < "$PATCHES/$p" > "$TMP/patch.log" 2>&1; then
        say "patch $p applies"
    else
        say "patch $p DOES NOT APPLY:"; sed 's/^/    /' "$TMP/patch.log"
        failed="$failed $p"
    fi
done < "$PATCHES/series"

old_tree="$TMP/old"; mkdir -p "$old_tree"
git archive HEAD~1 src/pkg/dist | tar -C "$old_tree" -xf -
o="$old_tree/src/pkg/dist"
echo
say "upstream changes the build and the patches depend on ($OLD -> $NEW):"
for f in configure configure.def mk/defs.mk.in mk/lib.mk mk/prog.mk mk/common.mk \
         libpkg/Makefile.in libpkg/libpkg.ver src/Makefile.in docs/Makefile.in \
         scripts/Makefile.in external/Makefile.in libpkg/pkg.pc.in; do
    if ! cmp -s "$o/$f" "$DIST/$f" 2>/dev/null; then echo "    changed: $f"; fi
done
grep -h '^define LIBVERSION' "$o/configure.def" "$DIST/configure.def" | uniq | sed 's/^/    /'
for f in libpkg/pkg_jobs_universe.c libpkg/pkg_jobs.c libpkg/pkg_config.c; do
    if ! cmp -s "$o/$f" "$DIST/$f"; then echo "    changed (patched or patch-relevant): $f"; fi
done
grep -n 'pkgdb_repo_query\|pkgdb_repo_shlib_provide\|pkgdb_repo_provide' \
    "$DIST/libpkg/pkg_jobs_universe.c" "$DIST/libpkg/pkg_jobs.c" | sed "s#$DIST/##; s/^/    repo query: /"
grep -n '/etc/pkg' "$DIST/libpkg/"*.c | sed "s#$DIST/##; s/^/    config path: /"

echo
if [ -n "$failed" ]; then
    say "refresh these patches on top of the import commit:$failed"
    exit 2
fi
say "done. Next: build both arches (CI), update NEXTBSD.md, NOTICE.md and README.md, open a PR."
