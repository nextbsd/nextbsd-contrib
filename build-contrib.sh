#!/usr/bin/env bash
# =============================================================================
# build-contrib.sh — cross-build driver for nextbsd-contrib
# =============================================================================
#
# Builds the third-party programs NextBSD ships in base (sudo, pico, zsh and its
# plugins, pkg) for ONE architecture into $DESTDIR (pkg into $PKG_DESTDIR), from
# their unmodified upstream trees under src/<name>/dist/ (plus, for pkg only, the
# NextBSD patches in src/pkg/patches/, applied to a build copy).
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
#   Inside the nextbsd-toolchain container, with compat's `continuous`
#   base extracted into $SYSROOT. The image's pinned LLVM 19.1.7 tools live in
#   $CROSS_BINDIR.
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
# pkg(8) is staged apart from the rest: nextbsd-pkg packages it as its own
# `pkg` package (nextbsd/nextbsd-pkg#19), not inside NextBSD-contrib.
: "${PKG_DESTDIR:=${DESTDIR%/}-pkg}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/src"
BUILD="$ROOT/.build"

fail() { echo "FAIL: $*" >&2; exit 1; }

# The target triple carries the FreeBSD release the sysroot's kernel and libc
# API come from (x86_64-unknown-freebsd15.1), as the native compiler's default
# triple does. clang derives __FreeBSD__ from it, and with no version it falls
# back to 8: pkg compiles __FreeBSD__ in as OSMAJOR and warns "Major OS version
# upgrade detected" on every run when it differs from the running system's ABI
# major (src/pkg/NEXTBSD.md, "Build").
OSVERSION=$(sed -n 's/^#define[[:space:]]*__FreeBSD_version[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
    "$SYSROOT/usr/include/sys/param.h" 2>/dev/null | head -n 1)
case "$OSVERSION" in
    [1-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *) fail "no __FreeBSD_version in $SYSROOT/usr/include/sys/param.h (got '${OSVERSION}')" ;;
esac
# A FreeBSD sysroot's triple release is its own __FreeBSD_version (1501000 ->
# 15.1). A NextBSD sysroot's __FreeBSD_version carries the NextBSD kernel major
# (2700000 for 27.0.0) but keeps the releng/15.1 kernel and libc API, so its
# triple stays freebsd15.1 on purpose, and so does everything derived from it
# below: __FreeBSD__, pkg's OSMAJOR and INDEX-15 (FreeBSD's ports INDEX name).
# Each NextBSD major names its base here; one that is not listed fails.
SYS_MAJOR=$((OSVERSION / 100000))
case "$SYS_MAJOR" in
    27) OSMAJOR=15; OSMINOR=1 ;;           # NextBSD 27.x: releng/15.1
    2[89]|[3-9][0-9])
        fail "sysroot __FreeBSD_version $OSVERSION is NextBSD major $SYS_MAJOR, which names no FreeBSD base release here" ;;
    *)  OSMAJOR=$SYS_MAJOR; OSMINOR=$((OSVERSION / 1000 % 100)) ;;
esac
case "$T" in
    amd64) CROSS_TRIPLE=x86_64-unknown-freebsd$OSMAJOR.$OSMINOR ;;
    arm64) CROSS_TRIPLE=aarch64-unknown-freebsd$OSMAJOR.$OSMINOR ;;
    *)     CROSS_TRIPLE="${TA}-unknown-freebsd$OSMAJOR.$OSMINOR" ;;
esac
CROSS_CC="$CROSS_BINDIR/clang --target=$CROSS_TRIPLE --ld-path=$CROSS_BINDIR/ld.lld"
# The cross compiler must agree with the sysroot: __FreeBSD__ is the triple's
# FreeBSD major for this sysroot (not clang's fallback 8 for a versionless
# triple).
CROSS_FREEBSD=$($CROSS_CC --sysroot="$SYSROOT" -dM -E -x c /dev/null </dev/null \
    | sed -n 's/^#define __FreeBSD__ //p')
[ "$CROSS_FREEBSD" = "$OSMAJOR" ] \
    || fail "$CROSS_TRIPLE defines __FreeBSD__ '$CROSS_FREEBSD', but the sysroot's __FreeBSD_version $OSVERSION needs FreeBSD major $OSMAJOR"
BUILD_TRIPLE="$(uname -m)-pc-linux-gnu"
JOBS=-j"$(nproc 2>/dev/null || echo 2)"

export SYSROOT DESTDIR PKG_DESTDIR CROSS_BINDIR

# ---- helpers -----------------------------------------------------------------
comp() { echo; echo "==> [$T/$TA] $*"; }
note() { echo "    - $*"; }

# libtool needs a target-aware archiver. The toolchain image ships the pinned
# llvm-ar/llvm-ranlib/llvm-strip in $CROSS_BINDIR (and /usr/bin/<tool>-19).
llvm_tool() {
    local t
    for t in "$CROSS_BINDIR/$1" "$(command -v "$1-19" 2>/dev/null)" "$(command -v "$1" 2>/dev/null)"; do
        [ -n "$t" ] && [ -x "$t" ] && { echo "$t"; return 0; }
    done
    fail "$1 not found (looked in $CROSS_BINDIR and PATH)"
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
# zsh (nextbsd/nextbsd-userland#248) — see src/zsh/NEXTBSD.md
# =============================================================================
# The shell as Darwin ships it: /bin/zsh with dynamic modules under
# /usr/lib/zsh/<version>/zsh, functions and completions under
# /usr/share/zsh/<version>/functions, run-help files, and the man pages that
# are pre-generated in the release (no yodl, no texinfo). Upstream's top-level
# `make` is not used: only Src is built, and the install targets that run with
# host sh and awk do the rest. /etc/zshenv, zprofile and zshrc come from
# nextbsd-overlays (U8); nothing here touches /etc.
build_zsh() {
    comp "zsh [autoconf cross]"
    fresh_dirs zsh
    local strip ver dist="$SRC/zsh/dist"
    strip=$(llvm_tool llvm-strip)
    ver=$(sed -n 's/^VERSION=//p' "$dist/Config/version.mk")
    [ -n "$ver" ] || fail "zsh: no VERSION in Config/version.mk"
    note "zsh $ver"
    (
        cd "$COMP_BUILD"
        # Cache variables: every configure check that would execute a test
        # program, answered with FreeBSD facts (listed with their reasons in
        # NEXTBSD.md), plus the file-system probes that would otherwise look at
        # the build host: the utmp paths and the RLIMIT_* header, which the
        # rlimits module parses with awk to build its table.
        CC="$CROSS_CC --sysroot=$SYSROOT" \
        CFLAGS="-O2 -pipe" \
        CPPFLAGS="-I$SYSROOT/usr/include" \
        LDFLAGS="-L$SYSROOT/usr/lib" \
        zsh_cv_long_is_64_bit=yes \
        zsh_cv_off_t_is_64_bit=yes \
        zsh_cv_ino_t_is_64_bit=yes \
        zsh_cv_printf_has_lld=yes \
        zsh_cv_rlim_t_is_longer=no \
        zsh_cv_rlim_t_is_quad_t=no \
        zsh_cv_type_rlim_t_is_unsigned=no \
        zsh_cv_getcwd_malloc=yes \
        zsh_cv_func_realpath_accepts_null=yes \
        zsh_cv_func_tgetent_accepts_null=yes \
        zsh_cv_func_tgetent_zero_success=no \
        zsh_cv_sys_fifo=yes \
        zsh_cv_sys_lseek=yes \
        zsh_cv_sys_link=yes \
        zsh_cv_c_broken_wcwidth=no \
        zsh_cv_c_broken_isprint=no \
        zsh_cv_sys_elf=yes \
        zsh_cv_func_dlsym_needs_underscore=no \
        zsh_cv_shared_environ=yes \
        zsh_cv_shared_tgetent=yes \
        zsh_cv_shared_tigetstr=yes \
        zsh_cv_sys_dynamic_clash_ok=yes \
        zsh_cv_sys_dynamic_rtld_global=yes \
        zsh_cv_sys_dynamic_execsyms=yes \
        zsh_cv_sys_dynamic_strip_exe=yes \
        zsh_cv_sys_dynamic_strip_lib=yes \
        ac_cv_func_strcoll_works=yes \
        ac_cv_func_mmap_fixed_mapped=yes \
        ac_cv_c_stack_direction=-1 \
        ac_cv_header_sys_capability_h=no \
        zsh_cv_sys_path_dev_fd=no \
        zsh_cv_path_utmp=no \
        zsh_cv_path_wtmp=no \
        zsh_cv_path_utmpx=/var/run/utx.active \
        zsh_cv_path_wtmpx=no \
        zsh_cv_path_rlimit_h="$SYSROOT/usr/include/sys/resource.h" \
        "$dist/configure" \
            --build="$BUILD_TRIPLE" --host="$CROSS_TRIPLE" \
            --prefix=/usr --bindir=/bin --mandir=/usr/share/man \
            --sysconfdir=/etc --enable-etcdir=/etc \
            --with-tcsetpgrp --enable-multibyte --enable-unicode9 \
            --enable-max-function-depth=700 \
            --enable-dynamic --with-term-lib=ncursesw \
            --disable-gdbm --disable-pcre
        # The shell and its modules. Upstream marks the build jobs-unsafe.
        make -C Src
        # Binary and modules, then functions and completions (Config/installfns.sh,
        # host sh + sed). No Doc targets: they would try to regenerate. The
        # top-level Makefile remakes itself through config.status, whose rule
        # would rerun autoconf from configure.ac and aclocal.m4, which are not
        # vendored; -o marks configure as old so that chain is never followed.
        make -C Src install.bin install.modules DESTDIR="$COMP_ROOT"
        make -o "$dist/configure" install.fns DESTDIR="$COMP_ROOT"
        # As Darwin: only /bin/zsh, not the versioned copy it is hard-linked to,
        # and no newuser script (Scripts/ is not vendored, so nothing landed).
        rm -f "$COMP_ROOT/bin/zsh-$ver"
        # Man pages and run-help files, pre-generated in the release.
        mkdir -p "$COMP_ROOT/usr/share/man/man1" "$COMP_ROOT/usr/share/zsh/$ver/help"
        for m in "$dist"/Doc/*.1; do
            install -m 0444 "$m" "$COMP_ROOT/usr/share/man/man1/$(basename "$m")"
        done
        for h in "$dist"/Doc/help/*; do
            install -m 0444 "$h" "$COMP_ROOT/usr/share/zsh/$ver/help/$(basename "$h")"
        done
        while read -r from to; do
            [ -n "$to" ] || continue
            ln -sf "$from" "$COMP_ROOT/usr/share/zsh/$ver/help/$to"
        done < "$dist/Doc/help.txt"
    )
    # Stage, then strip the shell and its modules with the target strip.
    (cd "$COMP_ROOT" && tar -cf - .) | (cd "$DESTDIR" && tar -xf -)
    "$strip" "$DESTDIR/bin/zsh"
    find "$DESTDIR/usr/lib/zsh/$ver" -name '*.so' -exec "$strip" {} +
    test -x "$DESTDIR/bin/zsh" || fail "/bin/zsh was not staged"
    [ "$(find "$DESTDIR/usr/lib/zsh/$ver/zsh" -name '*.so' | wc -l)" -gt 0 ] \
        || fail "no zsh modules staged under /usr/lib/zsh/$ver/zsh"
    test -f "$DESTDIR/usr/share/zsh/$ver/functions/compinit" || fail "compinit not staged"
    test -f "$DESTDIR/usr/share/zsh/$ver/functions/run-help" || fail "run-help not staged"
    test -f "$DESTDIR/usr/share/man/man1/zshall.1" || fail "zsh man pages not staged"
    needed_check "$DESTDIR/bin/zsh" "libncursesw"
    note "modules: $(find "$DESTDIR/usr/lib/zsh/$ver/zsh" -name '*.so' | wc -l), functions: $(find "$DESTDIR/usr/share/zsh/$ver/functions" -type f | wc -l)"
    return 0
}

# =============================================================================
# zsh-autosuggestions (nextbsd/nextbsd-userland#248) — see src/zsh-autosuggestions/NEXTBSD.md
# =============================================================================
# Nothing to compile: the release ships the assembled plugin. /etc/zshrc (U8)
# sources it from /usr/share/zsh/plugins/zsh-autosuggestions.
build_zsh_autosuggestions() {
    comp "zsh-autosuggestions [install]"
    local dist="$SRC/zsh-autosuggestions/dist" d="$DESTDIR/usr/share/zsh/plugins/zsh-autosuggestions"
    note "zsh-autosuggestions $(cat "$dist/VERSION")"
    mkdir -p "$d"
    install -m 0444 "$dist/zsh-autosuggestions.zsh"        "$d/zsh-autosuggestions.zsh"
    install -m 0444 "$dist/zsh-autosuggestions.plugin.zsh" "$d/zsh-autosuggestions.plugin.zsh"
    test -s "$d/zsh-autosuggestions.zsh" || fail "zsh-autosuggestions.zsh was not staged"
    return 0
}

# =============================================================================
# zsh-completions (nextbsd/nextbsd-userland#248) — see src/zsh-completions/NEXTBSD.md
# =============================================================================
# Installed into zsh's site-functions directory, which is first in the default
# fpath. A completion that zsh itself ships (under Completion/) is skipped, so
# the copy maintained with the shell is the one that loads.
build_zsh_completions() {
    comp "zsh-completions [install]"
    local dist="$SRC/zsh-completions/dist" d="$DESTDIR/usr/share/zsh/site-functions"
    local f n skipped="" count=0
    mkdir -p "$d"
    for f in "$dist"/src/_*; do
        n=$(basename "$f")
        if [ -n "$(find "$SRC/zsh/dist/Completion" -type f -name "$n" -print -quit)" ]; then
            skipped="$skipped $n"
            continue
        fi
        install -m 0444 "$f" "$d/$n"
        count=$((count + 1))
    done
    [ "$count" -gt 0 ] || fail "no zsh-completions files staged"
    note "installed $count completions; zsh ships its own:$skipped"
    return 0
}

# =============================================================================
# zsh-syntax-highlighting (nextbsd/nextbsd-contrib#4) — see
# src/zsh-syntax-highlighting/NEXTBSD.md
# =============================================================================
# Nothing to compile. /etc/zshrc (U8, nextbsd/nextbsd-overlays#11) sources the
# entry point from /usr/share/zsh/plugins/zsh-syntax-highlighting and selects
# the main and brackets highlighters.
#
# .version and .revision-hash are installed because they are read at load
# time, not for documentation: the entry point does $(<${0:A:h}/.version) and
# the same for .revision-hash before anything else runs. The highlighters must
# sit in a directory beside the entry point, which is where it looks for them.
build_zsh_syntax_highlighting() {
    comp "zsh-syntax-highlighting [install]"
    local dist="$SRC/zsh-syntax-highlighting/dist"
    local d="$DESTDIR/usr/share/zsh/plugins/zsh-syntax-highlighting"
    local f rel count=0
    note "zsh-syntax-highlighting $(cat "$dist/.version")"
    mkdir -p "$d/highlighters"
    install -m 0444 "$dist/zsh-syntax-highlighting.zsh"        "$d/zsh-syntax-highlighting.zsh"
    install -m 0444 "$dist/zsh-syntax-highlighting.plugin.zsh" "$d/zsh-syntax-highlighting.plugin.zsh"
    install -m 0444 "$dist/.version"                           "$d/.version"
    install -m 0444 "$dist/.revision-hash"                     "$d/.revision-hash"
    for f in "$dist"/highlighters/*/*-highlighter.zsh; do
        rel=${f#"$dist"/highlighters/}
        mkdir -p "$d/highlighters/$(dirname "$rel")"
        install -m 0444 "$f" "$d/highlighters/$rel"
        count=$((count + 1))
    done
    test -s "$d/zsh-syntax-highlighting.zsh" || fail "zsh-syntax-highlighting.zsh was not staged"
    test -s "$d/.version" || fail ".version was not staged (the plugin reads it at load time)"
    test -s "$d/highlighters/main/main-highlighter.zsh" || fail "the main highlighter was not staged"
    test -s "$d/highlighters/brackets/brackets-highlighter.zsh" || fail "the brackets highlighter was not staged"
    note "installed $count highlighters"
    return 0
}

# =============================================================================
# pkg (nextbsd/nextbsd-contrib#7) — see src/pkg/NEXTBSD.md
# =============================================================================
# freebsd/pkg, frozen at the version in src/pkg/nextbsd-trim.sh, with the
# NextBSD patches in src/pkg/patches/series applied to a copy of dist/:
#   0001  pkg and pkg-devel are taken only from the repository named NextBSD;
#   0002  pkg.conf is /private/etc/pkg.conf, REPOS_DIR starts at /private/etc/pkg/;
#   0003  a ${MACHINE} config variable (amd64, arm64, ...) from the ABI arch;
#   0004  packages not from NextBSD may only install under /usr/local/ and /var/;
#   0005  on NextBSD the ABI is NextBSD:<major>:<arch> (NextBSD:27:amd64).
#   (0001 also refuses pkg from a package file without org.nextbsd.origin=NextBSD.)
# Built with pkg's own POSIX-sh configure and makefiles, as FreeBSD's
# ports-mgmt/pkg builds it, but installed in base: /usr/sbin/pkg and
# pkg-static, /usr/lib/libpkg.so.4, /usr/include, /usr/libdata/pkgconfig,
# /usr/share/man. pkg's compiled-in PREFIX stays /usr/local: it names the
# local administrator's directories (user-added repositories in
# /usr/local/etc/pkg/repos/, plugins, local triggers, the shared-library
# backup directory), as it does for a ports-built pkg; only the install
# directories are base ones.
#
# This replaces FreeBSD's /usr/sbin/pkg bootstrap shim, which compat's base
# drops (nextbsd-freebsd-compat scripts/superseded, with pkg.7 and the
# pkg.freebsd.org key). Until compat's `continuous` base is rebuilt without
# it, the base-collision check accepts exactly $PKG_BASE_SUPERSEDED and says
# so; any other clash with a base file fails.
#
# pkg bundles sqlite, libucl, lua, picosat, linenoise, yxml, blake2, libder,
# libecc and its own libfetch under external/ and links them statically. From
# the base it takes libarchive, libssl/libcrypto, libmd, libutil, libelf,
# libjail, libm and libthr; pkg-static also takes libz, libbz2, liblzma and
# libprivatezstd for libarchive. Staged into $PKG_DESTDIR, not $DESTDIR.
PKG_BASE_SUPERSEDED="usr/sbin/pkg"
PKG_STRING_FILTER="NextBSD: ignoring %s-%s from repository %s: pkg comes only from the NextBSD repository"
PKG_STRING_PKGFILE="NextBSD: refusing to install %s-%s from a package file that is not a NextBSD package (no org.nextbsd.origin=NextBSD annotation): pkg comes only from NextBSD"
PKG_STRING_SIP_REPO="NextBSD: refusing to install %s-%s from repository %s: it installs %s; packages not from the NextBSD repository may only install under /usr/local/ and /var/"
PKG_STRING_SIP_FILE="NextBSD: refusing to install %s-%s from a package file: it installs %s; package files without the org.nextbsd.origin=NextBSD annotation may only install under /usr/local/ and /var/"

# apply_patches <name> <tree>: src/<name>/patches/series lists the patches in
# order, one per line (# comments allowed). Every *.patch in the directory must
# be listed, and every patch must say where it came from in an `Origin:` header
# line (DEP-3 style; "NextBSD" for our own), as in the nextbsd-xlibs layout.
apply_patches() {
    local name="$1" tree="$2" dir="$SRC/$1/patches" p n=0
    [ -d "$dir" ] || return 0
    [ -f "$dir/series" ] || fail "src/$name/patches has no series file"
    for p in "$dir"/*.patch; do
        [ -e "$p" ] || continue
        grep -qx "$(basename "$p")" "$dir/series" || fail "src/$name/patches/$(basename "$p") is not listed in series"
    done
    while read -r p; do
        case "$p" in ''|'#'*) continue ;; esac
        [ -f "$dir/$p" ] || fail "src/$name/patches/series lists missing $p"
        grep -q '^Origin:' "$dir/$p" || fail "src/$name/patches/$p has no Origin: line"
        patch -d "$tree" -p1 --forward --batch --quiet < "$dir/$p" || fail "src/$name/patches/$p does not apply"
        note "patch $p"
        n=$((n + 1))
    done < "$dir/series"
    note "$n patch(es) applied"
}

# has_string <file> <string>: <string> occurs in the file (binary-safe).
has_string() {
    LC_ALL=C grep -qaF -- "$2" "$1"
}

# has_cstring_ere <file> <ERE>: some NUL-terminated string in the file ends
# with a match for <ERE> (anchor the start yourself, e.g. with (^|[^e])).
has_cstring_ere() {
    LC_ALL=C tr '\0' '\n' < "$1" | LC_ALL=C grep -qaE -- "$2\$"
}

build_pkg() {
    comp "pkg [configure cross]"
    fresh_dirs pkg
    local ar ranlib strip readelf ver f s
    local src="$COMP_BUILD/src" obj="$COMP_BUILD/obj" d="$PKG_DESTDIR"
    ar=$(llvm_tool llvm-ar); ranlib=$(llvm_tool llvm-ranlib); strip=$(llvm_tool llvm-strip)
    readelf=$(llvm_tool llvm-readelf)
    mkdir -p "$src" "$obj"
    cp -R "$SRC/pkg/dist/." "$src/"
    apply_patches pkg "$src"
    ver=$(sed -n 's/^VERSION=//p' "$SRC/pkg/nextbsd-trim.sh")
    note "pkg $ver"
    # configure takes the host from $srcdir/config.guess (or else the build
    # machine's uname) and has no --host; its FreeBSD branches key on
    # *-freebsd*. This stands in for config.guess in the build copy only.
    printf '#!/bin/sh\necho %s\n' "$CROSS_TRIPLE" > "$src/config.guess"
    chmod +x "$src/config.guess"
    (
        cd "$obj"
        # The same flags reach configure's link tests and make. The prefix
        # maps keep the build tree out of assert() and __FILE__ strings.
        export CC="$CROSS_CC --sysroot=$SYSROOT"
        export CFLAGS="-O2 -pipe -ffile-prefix-map=$src/= -ffile-prefix-map=$obj/="
        export CPPFLAGS="-I$SYSROOT/usr/include"
        export LDFLAGS="-L$SYSROOT/usr/lib"
        export AR="$ar" RANLIB="$ranlib" STRIP="$strip"
        # pkgconf searches only the sysroot (the test suite's atf-c probe).
        export PKG_CONFIG_LIBDIR="$SYSROOT/usr/libdata/pkgconfig" PKG_CONFIG_PATH="" \
               PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
        "$src/configure" --prefix=/usr/local \
            --sbindir=/usr/sbin --libdir=/usr/lib --includedir=/usr/include \
            --mandir=/usr/share/man --pkgconfigdir=/usr/libdata/pkgconfig
        make $JOBS
        # Only the programs, libpkg, headers, pkg.pc and the man pages. The
        # top-level install would also put the periodic scripts and the bash
        # completion in /usr/local/etc: NextBSD runs no periodic(8) (launchd,
        # no /etc/periodic) and has no bash in base, so neither ships.
        make -C src install DESTDIR="$COMP_ROOT"
        make -C libpkg install DESTDIR="$COMP_ROOT"
        make -C docs install DESTDIR="$COMP_ROOT"
        # libpkg.a: nothing in NextBSD links libpkg statically (pkg and
        # pkg-static embed libpkg_flat.a at build time).
        rm -f "$COMP_ROOT/usr/lib/libpkg.a"
        # pkg.pc.in hard-codes libdir=${prefix}/lib and includedir=
        # ${prefix}/include, so its prefix is the install prefix, /usr.
        sed -i 's#^prefix=.*#prefix=/usr#' "$COMP_ROOT/usr/libdata/pkgconfig/pkg.pc"
        # The zsh completion, where NextBSD's zsh looks first
        # (/usr/share/zsh/site-functions, as zsh-completions). It names
        # %prefix%/sbin/pkg, so it is made by upstream's rule with PREFIX=/usr.
        # (Not with make -B: that would also remake scripts/Makefile from its
        # .in through the same suffix rule.)
        rm -f scripts/completion/_pkg
        make -C scripts PREFIX=/usr completion/_pkg
        install -d -m 0755 "$COMP_ROOT/usr/share/zsh/site-functions"
        install -m 0444 scripts/completion/_pkg "$COMP_ROOT/usr/share/zsh/site-functions/_pkg"
        # The port puts the sample in ${PREFIX}/etc; pkg.conf is
        # /private/etc/pkg.conf now (patch 0002), so it sits with the examples.
        install -d -m 0755 "$COMP_ROOT/usr/share/examples/pkg"
        install -m 0444 "$src/src/pkg.conf.sample" "$COMP_ROOT/usr/share/examples/pkg/pkg.conf.sample"
    )
    # Stage and strip with the target strip.
    mkdir -p "$d"
    (cd "$COMP_ROOT" && tar -cf - .) | (cd "$d" && tar -xf -)
    "$strip" "$d/usr/sbin/pkg" "$d/usr/sbin/pkg-static"
    "$strip" --strip-unneeded "$d/usr/lib/libpkg.so.4"

    # --- checks ---------------------------------------------------------------
    for f in usr/sbin/pkg usr/sbin/pkg-static usr/lib/libpkg.so.4 usr/lib/libpkg.so \
             usr/include/pkg.h usr/include/pkg/vec.h usr/libdata/pkgconfig/pkg.pc \
             usr/share/man/man8/pkg.8.gz usr/share/man/man5/pkg.conf.5.gz \
             usr/share/zsh/site-functions/_pkg usr/share/examples/pkg/pkg.conf.sample; do
        test -e "$d/$f" || fail "pkg: /$f was not staged"
    done
    [ "$(readlink "$d/usr/lib/libpkg.so")" = libpkg.so.4 ] || fail "pkg: /usr/lib/libpkg.so does not point at libpkg.so.4"
    # Everything under /usr, nothing under /usr/local or /etc.
    f=$(cd "$d" && find . -mindepth 1 -maxdepth 1 ! -path ./usr)
    [ -z "$f" ] || fail "pkg: staged outside /usr: $f"
    [ ! -e "$d/usr/local" ] || fail "pkg: staged under /usr/local: $(cd "$d" && find usr/local ! -type d)"
    [ -z "$(find "$d" -name '*.a')" ] || fail "pkg: static archive staged: $(find "$d" -name '*.a')"
    # Nothing over a file the base already has, apart from the bootstrap shim
    # during the swap (see PKG_BASE_SUPERSEDED above).
    while IFS= read -r f; do
        if [ -e "$SYSROOT/$f" ] || [ -L "$SYSROOT/$f" ]; then
            case " $PKG_BASE_SUPERSEDED " in
                *" $f "*) note "replaces /$f, which the base still ships (superseded in nextbsd-freebsd-compat; gone once its base is rebuilt)" ;;
                *) fail "pkg: /$f would replace a file of the NextBSD base" ;;
            esac
        fi
    done <<EOF
$(cd "$d" && find . ! -type d | sed 's#^\./##')
EOF
    [ "$("$readelf" -d "$d/usr/lib/libpkg.so.4" | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p')" = libpkg.so.4 ] \
        || fail "pkg: libpkg.so.4 does not carry SONAME libpkg.so.4"
    note "SONAME ok: libpkg.so.4"
    # pkg links libpkg statically (as upstream does); the base libraries it
    # takes are shared.
    for s in libarchive libssl libcrypto libelf; do
        needed_check "$d/usr/sbin/pkg" "$s"
    done
    "$readelf" -d "$d/usr/sbin/pkg" | grep -q 'NEEDED.*libpkg' \
        && fail "pkg: /usr/sbin/pkg links libpkg.so; it should embed it"
    "$readelf" -lW "$d/usr/sbin/pkg-static" | grep -q INTERP \
        && fail "pkg: pkg-static has a program interpreter; it must be static"
    "$readelf" -d "$d/usr/sbin/pkg-static" | grep -q NEEDED \
        && fail "pkg: pkg-static has DT_NEEDED entries; it must be static"
    note "pkg-static is static"
    # No build paths in anything staged (binaries, .pc, completion, pages).
    for s in "$ROOT" "$BUILD" "$SYSROOT"; do
        f=$(grep -rlaF -- "$s" "$d" || true)
        [ -z "$f" ] || fail "pkg: build path $s in: $f"
    done
    grep -q '/usr/sbin/pkg' "$d/usr/share/zsh/site-functions/_pkg" || fail "pkg: the zsh completion does not run /usr/sbin/pkg"
    grep -q '^prefix=/usr$' "$d/usr/libdata/pkgconfig/pkg.pc" || fail "pkg: pkg.pc prefix is not /usr"
    if grep -n -F /usr/local "$d/usr/libdata/pkgconfig/pkg.pc"; then fail "pkg: pkg.pc names /usr/local"; fi
    grep -q "^Version: $ver\$" "$d/usr/libdata/pkgconfig/pkg.pc" || fail "pkg: pkg.pc does not say Version: $ver"
    # The NextBSD patches are compiled in: the reponame filter's message, and
    # the /private/etc defaults instead of upstream's.
    for f in usr/sbin/pkg usr/sbin/pkg-static usr/lib/libpkg.so.4; do
        has_string "$d/$f" "$PKG_STRING_FILTER" \
            || fail "pkg: /$f lacks the NextBSD reponame filter (patch 0001)"
        has_string "$d/$f" "$PKG_STRING_PKGFILE" \
            || fail "pkg: /$f lacks the package-file rule for pkg (patch 0001)"
        has_string "$d/$f" "$PKG_STRING_SIP_REPO" \
            || fail "pkg: /$f lacks the /usr/local/ and /var/ rule for other repositories (patch 0004)"
        has_string "$d/$f" "$PKG_STRING_SIP_FILE" \
            || fail "pkg: /$f lacks the /usr/local/ and /var/ rule for package files (patch 0004)"
        has_string "$d/$f" "/private/etc/pkg.conf" \
            || fail "pkg: /$f does not read /private/etc/pkg.conf (patch 0002)"
        has_string "$d/$f" "/private/etc/pkg/,/usr/local/etc/pkg/repos/" \
            || fail "pkg: /$f lacks REPOS_DIR /private/etc/pkg/ (patch 0002)"
        if has_cstring_ere "$d/$f" '(^|[^a-z])/usr/local/etc/pkg\.conf'; then
            fail "pkg: /$f still has upstream's /usr/local/etc/pkg.conf"
        fi
        if has_cstring_ere "$d/$f" '(^|[^e])/etc/pkg/,/usr/local/etc/pkg/repos/'; then
            fail "pkg: /$f still has upstream's REPOS_DIR /etc/pkg/"
        fi
    done
    # pkg compiles __FreeBSD__ in as OSMAJOR and compares it with the running
    # system's major on every command ("Major OS version upgrade detected").
    # Its default INDEXFILE is "INDEX-" OSMAJOR, so that string shows the
    # compiled-in value: it must be the triple's FreeBSD major for this
    # sysroot (15, also for a NextBSD 27xxxxx sysroot), and the only one.
    for f in usr/sbin/pkg usr/sbin/pkg-static usr/lib/libpkg.so.4; do
        s=$(LC_ALL=C grep -aoE 'INDEX-[0-9]+' "$d/$f" | sort -u | tr '\n' ' ')
        [ "$s" = "INDEX-$OSMAJOR " ] \
            || fail "pkg: /$f has OSMAJOR '${s% }', not INDEX-$OSMAJOR (FreeBSD major for the sysroot's __FreeBSD_version $OSVERSION)"
    done
    note "OSMAJOR compiled in: $OSMAJOR (INDEX-$OSMAJOR), for the sysroot's __FreeBSD_version $OSVERSION"
    note "NextBSD patches compiled in: reponame filter, pkg-file rule, /private/etc/pkg.conf, REPOS_DIR /private/etc/pkg/, /usr/local/ + /var/ rule"
    # Where the 0001/0004 checks sit: before extraction in pkg_jobs_execute()
    # (install and upgrade) and pkg_add_common() (pkg add, and every job item).
    grep -qF 'retcode = nextbsd_check_jobs(j);' "$src/libpkg/pkg_jobs.c" \
        || fail "pkg: pkg_jobs_execute() does not call nextbsd_check_jobs() (patch 0001)"
    grep -qF 'if (nextbsd_check_install(pkg, remote) != EPKG_OK) {' "$src/libpkg/pkg_add.c" \
        || fail "pkg: pkg_add_common() does not call nextbsd_check_install() (patch 0001)"
    # Patch 0004's path rule, run on the build host against the patch's
    # header (the table and function libpkg uses).
    local sipc="$COMP_BUILD/nextbsd-check-sip"
    cc -O1 -Wall -I"$src/libpkg/private" -o "$sipc" "$SRC/pkg/nextbsd-check-sip.c" \
        || fail "pkg: could not build the /usr/local/ + /var/ host check"
    "$sipc" > "$COMP_BUILD/nextbsd-check-sip.out" \
        || { sed 's/^/    /' "$COMP_BUILD/nextbsd-check-sip.out"; fail "pkg: the /usr/local/ + /var/ rule gives a wrong answer (patch 0004)"; }
    note "/usr/local/ + /var/ rule: $(grep -c allowed "$COMP_BUILD/nextbsd-check-sip.out") allowed, $(grep -c refused "$COMP_BUILD/nextbsd-check-sip.out") refused, as expected"
    # Patch 0003: ${MACHINE}. libpkg registers it from the computed ABI arch
    # (the mapping's powerpcspe entry exists nowhere else in pkg, so finding it
    # shows the mapping is linked in). The target pkg cannot run here, so the
    # expansion is checked on the build host: src/pkg/nextbsd-check-machine.c,
    # built with the host cc against the build copy's libucl and the patch's
    # header, parses NextBSD.conf's url for both ABIs.
    grep -qF 'nextbsd_machine(pkg_arch_to_string(ctx.abi.os, ctx.abi.arch))' "$src/libpkg/pkg_config.c" \
        || fail "pkg: pkg_config.c does not register MACHINE from the ABI arch (patch 0003)"
    for f in usr/sbin/pkg usr/sbin/pkg-static usr/lib/libpkg.so.4; do
        has_string "$d/$f" powerpcspe || fail "pkg: /$f lacks the MACHINE mapping (patch 0003)"
    done
    local ucl="$src/external/libucl" mc="$COMP_BUILD/nextbsd-check-machine" abi want
    cc -O1 -w -I"$ucl/include" -I"$ucl/uthash" -I"$ucl/klib" -I"$ucl/src" -I"$src/libpkg/private" \
        -o "$mc" "$SRC/pkg/nextbsd-check-machine.c" \
        "$ucl"/src/ucl_emitter_streamline.c "$ucl"/src/ucl_emitter_utils.c "$ucl"/src/ucl_emitter.c \
        "$ucl"/src/ucl_hash.c "$ucl"/src/ucl_msgpack.c "$ucl"/src/ucl_parser.c \
        "$ucl"/src/ucl_schema.c "$ucl"/src/ucl_sexp.c "$ucl"/src/ucl_util.c -lm \
        || fail "pkg: could not build the \${MACHINE} host check"
    for abi in FreeBSD:15:amd64=amd64 FreeBSD:15:aarch64=arm64; do
        want="https://github.com/nextbsd/nextbsd-pkg/releases/download/continuous-${abi#*=}"
        "$mc" "${abi%=*}" "$want" | sed 's/^/    - ${MACHINE}: /' \
            || fail "pkg: \${MACHINE} for ABI ${abi%=*} does not give continuous-${abi#*=} (patch 0003)"
    done
    return 0
}

# =============================================================================
# driver
# =============================================================================
# Add a component: write build_<name>() above (hyphens in the name become
# underscores in the function) and append <name> here.
COMPONENTS="sudo pico zsh zsh-autosuggestions zsh-completions zsh-syntax-highlighting pkg"

if [ $# -gt 0 ]; then
    for c in "$@"; do
        case " $COMPONENTS " in
            *" $c "*) ;;
            *) fail "unknown component '$c' (known: $COMPONENTS)" ;;
        esac
    done
    COMPONENTS="$*"
fi

echo "nextbsd-contrib: building [$COMPONENTS] for $T/$TA into $DESTDIR (pkg into $PKG_DESTDIR)"
echo "nextbsd-contrib: target $CROSS_TRIPLE (sysroot __FreeBSD_version $OSVERSION, __FreeBSD__ $CROSS_FREEBSD)"
mkdir -p "$DESTDIR"
for c in $COMPONENTS; do
    "build_$(printf '%s' "$c" | tr - _)"
done

echo
echo "==> staged into $DESTDIR:"
( cd "$DESTDIR" && find . -type f | sort | sed 's#^\.##' )
if [ -d "$PKG_DESTDIR" ]; then
    echo
    echo "==> staged into $PKG_DESTDIR (pkg):"
    ( cd "$PKG_DESTDIR" && find . ! -type d | sort | sed 's#^\.##' )
fi
