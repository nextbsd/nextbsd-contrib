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
# sudo (nextbsd/nextbsd-userland#247) — see src/sudo/NEXTBSD.md
# =============================================================================
# Only sudo and visudo are built and staged: the helper libs, the sudoers policy
# (linked in: --enable-static-sudoers), visudo, sudo and their two man pages.
# Upstream's `make all` is not used. The package ships no /etc; /etc/sudoers
# and /etc/pam.d/sudo come from nextbsd-overlays.
build_sudo() {
    comp "sudo [autoconf cross]"
    fresh_dirs sudo
    local ar ranlib strip mt
    ar=$(llvm_tool llvm-ar); ranlib=$(llvm_tool llvm-ranlib); strip=$(llvm_tool llvm-strip)
    note "archiver: $ar"
    (
        cd "$COMP_BUILD"
        CC="$CROSS_CC --sysroot=$SYSROOT" \
        CFLAGS="-O2 -pipe" \
        CPPFLAGS="-I$SYSROOT/usr/include" \
        LDFLAGS="-L$SYSROOT/usr/lib" \
        AR="$ar" RANLIB="$ranlib" STRIP="$strip" \
        sudo_cv_func_fnmatch=yes \
        sudo_cv_working_pie=yes \
        ac_cv_have_working_snprintf=yes \
        ac_cv_have_working_vsnprintf=yes \
        sudo_cv_var_mantype=mdoc \
        "$SRC/sudo/dist/configure" \
            --build="$BUILD_TRIPLE" --host="$CROSS_TRIPLE" \
            --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/libexec \
            --localstatedir=/var --mandir=/usr/share/man --docdir=/usr/share/doc/sudo \
            --with-rundir=/var/run/sudo --with-vardir=/var/db/sudo \
            --with-pam --with-logfac=authpriv \
            --with-editor=/usr/bin/vi --with-env-editor \
            --enable-zlib=system \
            --disable-log-server --disable-log-client --disable-openssl \
            --disable-nls --without-sendmail \
            --enable-static-sudoers --disable-shared-libutil \
            --without-noexec --disable-intercept
        make $JOBS -C lib/util
        make $JOBS -C lib/eventlog
        make $JOBS -C lib/iolog
        make $JOBS -C lib/protobuf-c
        make $JOBS -C plugins/sudoers sudoers.la visudo
        make $JOBS -C src sudo
        mt=$(sed -n 's/^mantype = //p' docs/Makefile)
        make -C docs "sudo.$mt" "visudo.$mt"
        mkdir -p "$COMP_ROOT/usr/bin" "$COMP_ROOT/usr/sbin" "$COMP_ROOT/usr/share/man/man8"
        ./libtool --mode=install install -m 0755 src/sudo "$COMP_ROOT/usr/bin/sudo"
        ./libtool --mode=install install -m 0755 plugins/sudoers/visudo "$COMP_ROOT/usr/sbin/visudo"
        install -m 0444 "docs/sudo.$mt"   "$COMP_ROOT/usr/share/man/man8/sudo.8"
        install -m 0444 "docs/visudo.$mt" "$COMP_ROOT/usr/share/man/man8/visudo.8"
    )
    # Stage as Darwin ships them: sudo 4511, visudo 0111, man pages 0444. libsudo_util and the sudoers policy
    # are static, so there is no /usr/libexec/sudo.
    mkdir -p "$DESTDIR/usr/bin" "$DESTDIR/usr/sbin" "$DESTDIR/usr/share/man/man8"
    install -m 0755 "$COMP_ROOT/usr/bin/sudo"    "$DESTDIR/usr/bin/sudo"
    install -m 0111 "$COMP_ROOT/usr/sbin/visudo" "$DESTDIR/usr/sbin/visudo"
    install -m 0444 "$COMP_ROOT/usr/share/man/man8/sudo.8"   "$DESTDIR/usr/share/man/man8/sudo.8"
    install -m 0444 "$COMP_ROOT/usr/share/man/man8/visudo.8" "$DESTDIR/usr/share/man/man8/visudo.8"
    needed_check "$DESTDIR/usr/bin/sudo" "libpam"
    [ -e "$DESTDIR/usr/libexec/sudo" ] && fail "/usr/libexec/sudo was staged; sudoers must be static"
    # setuid root, 4511 as on Darwin. The file's owner may set the bit without
    # privilege; it is a later chown that clears it (Linux clears setuid on
    # chown even as root, FreeBSD keeps it on files already owned by 0:0).
    chmod 4511 "$DESTDIR/usr/bin/sudo"
    note "$(stat -c '%A %n' "$DESTDIR/usr/bin/sudo" 2>/dev/null || stat -f '%Sp %N' "$DESTDIR/usr/bin/sudo")"
    return 0
}

# =============================================================================
# pico (nextbsd/nextbsd-userland#261) — see src/pico/NEXTBSD.md
# =============================================================================
# Alpine's pico, built the way FreeBSD's editors/pico-alpine port builds it,
# minus pilot and minus the c-client library: pico links exactly one c-client
# object (utf8.o), which is compiled by hand from the headers and tables kept
# in dist/, so the imap tree is never built. Alpine's sources include the
# c-client and pith headers by relative path from the source tree, so the
# build runs on a copy of dist/ (never in src/). Shipped as Darwin ships it:
# /usr/bin/pico with /usr/bin/nano linked to it, and their man pages.
build_pico() {
    comp "pico [autoconf cross]"
    fresh_dirs pico
    local ar ranlib strip f
    ar=$(llvm_tool llvm-ar); ranlib=$(llvm_tool llvm-ranlib); strip=$(llvm_tool llvm-strip)
    cp -R "$SRC/pico/dist/." "$COMP_BUILD/"
    (
        cd "$COMP_BUILD"
        # What the imap build would have put in c-client/: the c-client
        # headers, utf8.c and the charset tables it #includes, the FreeBSD
        # osdep headers with os_bsf.h as osdep.h, and an empty linkage.h (it
        # lists the mail drivers and authenticators linked into a c-client
        # program; pico links none).
        mkdir c-client
        for f in imap/src/c-client/*.h imap/src/c-client/utf8.c imap/src/charset/*.c \
                 imap/src/osdep/unix/env_unix.h imap/src/osdep/unix/tcp_unix.h; do
            ln -s "../$f" c-client/
        done
        ln -s ../imap/src/osdep/unix/os_bsf.h c-client/osdep.h
        : > c-client/linkage.h
        # Three configure checks run a test program; their FreeBSD answers are
        # supplied. The rest of configure's cross fallbacks are compile-only.
        # -Wno-error=incompatible-function-pointer-types: browse.c passes a
        # (const char *, const char *) comparator to qsort(), an error since
        # clang 16; FreeBSD's ports build it the same way.
        CC="$CROSS_CC --sysroot=$SYSROOT" \
        CFLAGS="-O2 -pipe -Wno-error=incompatible-function-pointer-types" \
        CPPFLAGS="-I$SYSROOT/usr/include" \
        LDFLAGS="-L$SYSROOT/usr/lib" \
        AR="$ar" RANLIB="$ranlib" STRIP="$strip" \
        ac_cv_func_strcoll_works=yes \
        ac_cv_func_fork_works=yes \
        ac_cv_func_vfork_works=yes \
        ./configure \
            --build="$BUILD_TRIPLE" --host="$CROSS_TRIPLE" \
            --prefix=/usr --mandir=/usr/share/man \
            --without-ssl --without-krb5 --without-ldap --without-tcl \
            --disable-nls --disable-dependency-tracking
        # pith/helptext.h is generated from pine.hlp by a host tool, as
        # pith/Makefile does; its output is arch-neutral.
        cc -o pith/help_h_gen pith/help_h_gen.c
        pith/help_h_gen < pith/pine.hlp > pith/helptext.h
        # The one c-client object, with the flags the c-client build uses.
        (cd c-client && $CROSS_CC --sysroot="$SYSROOT" -O2 -pipe -Wno-pointer-sign \
            -DCHUNKSIZE=65536 -I. -c utf8.c -o utf8.o)
        make $JOBS -C pith/osdep libpithosd.a
        make $JOBS -C pith/charconv libpithcc.a
        make $JOBS -C pico/osdep libpicoosd.a
        make $JOBS -C pico pico
        mkdir -p "$COMP_ROOT/usr/bin" "$COMP_ROOT/usr/share/man/man1"
        ./libtool --mode=install install -m 0555 pico/pico "$COMP_ROOT/usr/bin/pico"
        "$strip" "$COMP_ROOT/usr/bin/pico"
        install -m 0444 doc/man1/pico.1 "$COMP_ROOT/usr/share/man/man1/pico.1"
    )
    # Stage: pico 0555, nano -> pico, pico.1 0444, nano.1 -> pico.1 (so
    # `man nano` works, as on Darwin). pilot is not built or shipped.
    mkdir -p "$DESTDIR/usr/bin" "$DESTDIR/usr/share/man/man1"
    install -m 0555 "$COMP_ROOT/usr/bin/pico" "$DESTDIR/usr/bin/pico"
    ln -sfn pico "$DESTDIR/usr/bin/nano"
    install -m 0444 "$COMP_ROOT/usr/share/man/man1/pico.1" "$DESTDIR/usr/share/man/man1/pico.1"
    ln -sfn pico.1 "$DESTDIR/usr/share/man/man1/nano.1"
    # pico uses the terminfo/termcap API only, so it links libtinfow (the
    # terminfo half of base ncursesw); -ltinfo is a symlink to it.
    needed_check "$DESTDIR/usr/bin/pico" "libtinfow"
    [ "$(readlink "$DESTDIR/usr/bin/nano")" = pico ] || fail "/usr/bin/nano does not resolve to pico"
    [ -e "$DESTDIR/usr/bin/pilot" ] && fail "pilot was staged; only pico ships"
    return 0
}

# =============================================================================
# driver
# =============================================================================
# Add a component: write build_<name>() above and append <name> here.
COMPONENTS="sudo pico"

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
