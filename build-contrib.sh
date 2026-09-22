#!/usr/bin/env bash
# =============================================================================
# build-contrib.sh — cross-build driver for nextbsd-contrib
# =============================================================================
#
# Builds the third-party programs NextBSD ships in base (sudo, and later zsh and
# pico) for ONE architecture into $DESTDIR, from their unmodified upstream trees
# under src/<name>/dist/.
#
# Every component here has the same shape: upstream `configure` run in cross
# mode (--host=<triple>, the toolchain clang, --sysroot to the staged compat
# base), out of tree under .build/, then only the pieces NextBSD ships are built
# and installed. Configure checks that would run a test program cannot when
# cross compiling; their FreeBSD answers are pre-seeded as cache variables and
# listed in each component's NEXTBSD.md.
#
# Nothing here uses make.py or the FreeBSD buildenv, and nothing links against
# nextbsd-userland: the compat sysroot is the only dependency (README.md, "The
# rule for what goes here").
#
# EXECUTION CONTEXT (set up by CI before this runs)
#   Inside the nextbsd-kernel-toolchain container, with compat's `continuous`
#   base extracted into $SYSROOT and llvm-19 installed for the archiver tools.
#
# USAGE
#   ./build-contrib.sh            every component, in COMPONENTS order
#   ./build-contrib.sh sudo       one component by name
# =============================================================================

set -euo pipefail

# ---- required environment ----------------------------------------------------
: "${T:?set T to the target (amd64 / arm64)}"
: "${TA:?set TA to the target_arch (amd64 / aarch64)}"
: "${SYSROOT:?set SYSROOT to the staged compat base}"
: "${CROSS_BINDIR:?set CROSS_BINDIR to the dir holding the cross clang/lld}"
: "${DESTDIR:=/stage}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/src"
BUILD="$ROOT/.build"

case "$T" in
    amd64) CROSS_TRIPLE=x86_64-unknown-freebsd ;;
    arm64) CROSS_TRIPLE=aarch64-unknown-freebsd ;;
    *)     CROSS_TRIPLE="${TA}-unknown-freebsd" ;;
esac
CROSS_CC="$CROSS_BINDIR/clang --target=$CROSS_TRIPLE --ld-path=$CROSS_BINDIR/ld.lld"
BUILD_TRIPLE="$(uname -m)-pc-linux-gnu"
JOBS=-j"$(nproc 2>/dev/null || echo 2)"

export SYSROOT DESTDIR CROSS_BINDIR

# ---- helpers -----------------------------------------------------------------
comp() { echo; echo "==> [$T/$TA] $*"; }
note() { echo "    - $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# libtool needs a target-aware archiver. The toolchain image ships clang + lld
# only; llvm-ar/llvm-ranlib/llvm-strip come from the llvm-19 package CI installs.
llvm_tool() {
    local t
    for t in "$CROSS_BINDIR/$1" "$(command -v "$1-19" 2>/dev/null)" "$(command -v "$1" 2>/dev/null)"; do
        [ -n "$t" ] && [ -x "$t" ] && { echo "$t"; return 0; }
    done
    fail "$1 not found (install llvm-19; looked in $CROSS_BINDIR and PATH)"
}

# Assert a staged binary links a given library (a cross `readelf -d` check; we
# cannot exec target binaries on the runner).
needed_check() {
    local obj="$1" want="$2"
    local readelf="$CROSS_BINDIR/readelf"
    [ -x "$readelf" ] || readelf="$CROSS_BINDIR/llvm-readelf"
    [ -x "$readelf" ] || readelf="$(command -v llvm-readelf-19 2>/dev/null || true)"
    if [ ! -x "$readelf" ]; then
        note "skip DT_NEEDED check ($want): no readelf found"
        return 0
    fi
    "$readelf" -d "$obj" 2>/dev/null | grep -q "NEEDED.*$want" \
        || fail "$obj missing DT_NEEDED $want"
    note "DT_NEEDED ok: $(basename "$obj") -> $want"
}

# Fresh out-of-tree build and install-root directories for a component.
fresh_dirs() {
    local name="$1"
    COMP_BUILD="$BUILD/$name-$T"
    COMP_ROOT="$BUILD/$name-root-$T"
    rm -rf "$COMP_BUILD" "$COMP_ROOT"
    mkdir -p "$COMP_BUILD" "$COMP_ROOT"
}

# =============================================================================
# =============================================================================
# driver
# =============================================================================
# Add a component: write build_<name>() above and append <name> here.
COMPONENTS=""

if [ $# -gt 0 ]; then
    for c in "$@"; do
        case " $COMPONENTS " in
            *" $c "*) ;;
            *) fail "unknown component '$c' (known: $COMPONENTS)" ;;
        esac
    done
    COMPONENTS="$*"
fi

echo "nextbsd-contrib: building [$COMPONENTS] for $T/$TA into $DESTDIR"
mkdir -p "$DESTDIR"
for c in $COMPONENTS; do
    "build_$c"
done

echo
echo "==> staged into $DESTDIR:"
( cd "$DESTDIR" && find . -type f | sort | sed 's#^\.##' )
