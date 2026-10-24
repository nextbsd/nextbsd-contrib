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
# Libraries and the squashfs tools (nextbsd/nextbsd-contrib#9)
# =============================================================================
# squashfs-tools-ng and squashfuse, for AppImage desktop integration, with the
# three libraries they need that the compat base does not provide publicly:
# zstd and lz4 (base has zstd only as the private libprivatezstd, lz4 not at
# all) and libfuse3 (base has the kernel side and /sbin/mount_fusefs only).
# zlib, liblzma and libbz2 come from the base.
#
# The three libraries are staged into $DESTDIR first; squashfs-tools-ng and
# squashfuse then compile against $DESTDIR/usr/include and link
# $DESTDIR/usr/lib, next to the sysroot. So they must be built in COMPONENTS
# order (dep_check says which one is missing). They link nothing from
# nextbsd-userland, so rule 3 still holds.
#
# Each ships what base ships for a library: the shared object, its links,
# the headers and the .pc file in /usr/libdata/pkgconfig (so Gershwin and
# others can build against them), no static archive and no libtool archive.

# Fail early when a library a later component links has not been staged.
dep_check() {
    local comp="$1"; shift
    local lib
    for lib in "$@"; do
        [ -e "$DESTDIR/usr/lib/$lib" ] \
            || fail "$comp needs $DESTDIR/usr/lib/$lib; build its component first (COMPONENTS order)"
    done
}

# Copy a component's install root into $DESTDIR the way base ships libraries
# and programs: no static or libtool archives, .pc files in
# /usr/libdata/pkgconfig, shared objects and programs stripped with the target
# strip, programs 0555 and everything else 0444.
stage_root() {
    local root="$1" strip
    strip=$(llvm_tool llvm-strip)
    find "$root" \( -name '*.la' -o -name '*.a' \) -delete
    # meson decides the .pc directory from the build host, not the target.
    if [ -d "$root/usr/lib/pkgconfig" ]; then
        mkdir -p "$root/usr/libdata/pkgconfig"
        mv "$root/usr/lib/pkgconfig/"*.pc "$root/usr/libdata/pkgconfig/"
        rmdir "$root/usr/lib/pkgconfig"
    fi
    find "$root" -type f -name '*.so.*' -exec "$strip" --strip-unneeded {} +
    find "$root" -type d -exec chmod 0755 {} +
    find "$root" -type f -exec chmod 0444 {} +
    if [ -d "$root/usr/bin" ]; then
        find "$root/usr/bin" -type f -exec "$strip" {} +
        find "$root/usr/bin" -type f -exec chmod 0555 {} +
    fi
    (cd "$root" && tar -cf - .) | (cd "$DESTDIR" && tar -xf -)
    return 0
}

# Copy an autotools release into the build directory and give every file one
# mtime. A git checkout writes files in no particular order, and without
# AM_MAINTAINER_MODE automake's rebuild rules would rerun aclocal and automake
# whenever configure.ac or a Makefile.am landed newer than what was generated
# from it. The contents are untouched.
copy_release() {
    local dist="$1"
    cp -R "$dist/." "$COMP_BUILD/"
    find "$COMP_BUILD" -exec touch -h -r "$COMP_BUILD/configure" {} +
}

# =============================================================================
# zstd (nextbsd/nextbsd-contrib#9) — see src/zstd/NEXTBSD.md
# =============================================================================
# The library only, with upstream's lib/Makefile: libzstd.so.1 (multithreaded,
# as upstream builds the shared library), zstd.h, zstd_errors.h, zdict.h,
# libzstd.pc. Not the zstd programs: base already has /usr/bin/zstd, built on
# its private copy. The Makefile picks the platform from `uname`, which is the
# Linux runner here, so UNAME=FreeBSD is passed: that gives the FreeBSD
# soname flags and puts libzstd.pc in /usr/libdata/pkgconfig. The Makefile
# builds inside its own tree, so it runs on a copy of dist/.
build_zstd() {
    comp "zstd [library, upstream Makefile]"
    fresh_dirs zstd
    cp -R "$SRC/zstd/dist/." "$COMP_BUILD/"
    local mk
    mk=(-C "$COMP_BUILD/lib" UNAME=FreeBSD
        CC="$CROSS_CC --sysroot=$SYSROOT"
        PREFIX=/usr DESTDIR="$COMP_ROOT")
    make $JOBS "${mk[@]}" libzstd-release libzstd.pc
    make "${mk[@]}" install-shared install-includes install-pc
    stage_root "$COMP_ROOT"
    test -f "$DESTDIR/usr/include/zstd.h" || fail "zstd.h was not staged"
    test -f "$DESTDIR/usr/libdata/pkgconfig/libzstd.pc" || fail "libzstd.pc was not staged"
    test -L "$DESTDIR/usr/lib/libzstd.so" || fail "libzstd.so link was not staged"
    needed_check "$DESTDIR/usr/lib/libzstd.so.1" "libthr"
    return 0
}

# =============================================================================
# lz4 (nextbsd/nextbsd-contrib#9) — see src/lz4/NEXTBSD.md
# =============================================================================
# The library only, with upstream's lib/Makefile: liblz4.so.1, lz4.h,
# lz4hc.h, lz4frame.h, liblz4.pc. TARGET_OS=FreeBSD for the same reason as
# zstd's UNAME; BUILD_STATIC=no so no liblz4.a is built. The lz4 program is
# GPL-2.0 and is neither vendored nor built.
build_lz4() {
    comp "lz4 [library, upstream Makefile]"
    fresh_dirs lz4
    cp -R "$SRC/lz4/dist/." "$COMP_BUILD/"
    local mk
    mk=(-C "$COMP_BUILD/lib" TARGET_OS=FreeBSD BUILD_STATIC=no
        CC="$CROSS_CC --sysroot=$SYSROOT"
        PREFIX=/usr DESTDIR="$COMP_ROOT")
    make $JOBS "${mk[@]}" lib-release
    make "${mk[@]}" install
    stage_root "$COMP_ROOT"
    test -f "$DESTDIR/usr/include/lz4.h" || fail "lz4.h was not staged"
    test -f "$DESTDIR/usr/libdata/pkgconfig/liblz4.pc" || fail "liblz4.pc was not staged"
    test -e "$DESTDIR/usr/lib/liblz4.so.1" || fail "liblz4.so.1 was not staged"
    return 0
}

# =============================================================================
# libfuse (nextbsd/nextbsd-contrib#9) — see src/libfuse/NEXTBSD.md
# =============================================================================
# libfuse3 with upstream's meson build, cross: libfuse3.so.4, the fuse3/
# headers, fuse3.pc. On FreeBSD meson.build never builds the helper programs
# (fusermount3, mount.fuse3); libfuse mounts by running base's
# /sbin/mount_fusefs. Examples, tests and io_uring are switched off.
build_libfuse() {
    comp "libfuse [meson cross]"
    fresh_dirs libfuse
    command -v meson >/dev/null || fail "meson not found (CI installs meson and ninja-build)"
    local ar strip cpu
    ar=$(llvm_tool llvm-ar); strip=$(llvm_tool llvm-strip)
    case "$TA" in
        amd64) cpu=x86_64 ;;
        *)     cpu="$TA" ;;
    esac
    # The linker is named with c_ld (meson passes -fuse-ld=lld, and clang
    # takes ld.lld from its own directory) rather than --ld-path in the
    # compiler command: meson runs its compile-only checks with
    # -Werror=unused-command-line-argument, so a linker flag there makes every
    # one of them fail and libfuse is configured as if the libc had nothing.
    cat > "$COMP_BUILD/cross.ini" <<EOC
[binaries]
c = ['$CROSS_BINDIR/clang', '--target=$CROSS_TRIPLE', '--sysroot=$SYSROOT']
c_ld = 'lld'
ar = '$ar'
strip = '$strip'

[host_machine]
system = 'freebsd'
cpu_family = '$cpu'
cpu = '$cpu'
endian = 'little'
EOC
    meson setup "$COMP_BUILD/build" "$SRC/libfuse/dist" \
        --cross-file "$COMP_BUILD/cross.ini" \
        --prefix=/usr --libdir=lib --includedir=include \
        --buildtype=release \
        -Dutils=false -Dexamples=false -Dtests=false \
        -Denable-io-uring=false
    meson compile -C "$COMP_BUILD/build"
    meson install -C "$COMP_BUILD/build" --destdir "$COMP_ROOT"
    stage_root "$COMP_ROOT"
    test -f "$DESTDIR/usr/include/fuse3/fuse.h" || fail "fuse3/fuse.h was not staged"
    test -f "$DESTDIR/usr/libdata/pkgconfig/fuse3.pc" || fail "fuse3.pc was not staged"
    test -e "$DESTDIR/usr/lib/libfuse3.so.4" || fail "libfuse3.so.4 was not staged"
    needed_check "$DESTDIR/usr/lib/libfuse3.so.4" "libthr"
    return 0
}

# =============================================================================
# squashfs-tools-ng (nextbsd/nextbsd-contrib#9) — see src/squashfs-tools-ng/NEXTBSD.md
# =============================================================================
# libsquashfs (LGPL-3.0-or-later), which Gershwin's Workspace and
# make_services use to read AppImage icons and .desktop files without
# mounting, and the five tools (GPL-3.0-or-later): gensquashfs, rdsquashfs,
# sqfs2tar, sqfsdiff, tar2sqfs. Every compressor squashfs uses except LZO:
# gzip, xz, lz4 and zstd; bzip2 too, which tar2sqfs and sqfs2tar use for
# tarballs. The libraries' flags are given directly (pkg-config is not used
# when cross compiling here), which configure accepts in place of a pkg-config
# lookup. No configure check runs a test program.
build_squashfs_tools_ng() {
    comp "squashfs-tools-ng [autoconf cross]"
    dep_check squashfs-tools-ng libzstd.so liblz4.so
    fresh_dirs squashfs-tools-ng
    local ar ranlib strip
    ar=$(llvm_tool llvm-ar); ranlib=$(llvm_tool llvm-ranlib); strip=$(llvm_tool llvm-strip)
    copy_release "$SRC/squashfs-tools-ng/dist"
    (
        cd "$COMP_BUILD"
        CC="$CROSS_CC --sysroot=$SYSROOT" \
        CFLAGS="-O2 -pipe" \
        CPPFLAGS="-I$DESTDIR/usr/include -I$SYSROOT/usr/include" \
        LDFLAGS="-L$DESTDIR/usr/lib -L$SYSROOT/usr/lib" \
        AR="$ar" RANLIB="$ranlib" STRIP="$strip" \
        PKG_CONFIG_LIBDIR="$SYSROOT/usr/libdata/pkgconfig" \
        PKG_CONFIG_SYSROOT_DIR="$SYSROOT" \
        ZLIB_CFLAGS="-I$SYSROOT/usr/include" ZLIB_LIBS="-lz" \
        XZ_CFLAGS="-I$SYSROOT/usr/include" XZ_LIBS="-llzma" \
        BZIP2_CFLAGS="-I$SYSROOT/usr/include" BZIP2_LIBS="-lbz2" \
        LZ4_CFLAGS="-I$DESTDIR/usr/include" LZ4_LIBS="-L$DESTDIR/usr/lib -llz4" \
        ZSTD_CFLAGS="-I$DESTDIR/usr/include" ZSTD_LIBS="-L$DESTDIR/usr/lib -lzstd" \
        ./configure \
            --build="$BUILD_TRIPLE" --host="$CROSS_TRIPLE" \
            --prefix=/usr --mandir=/usr/share/man \
            --with-pkgconfigdir=/usr/libdata/pkgconfig \
            --enable-shared --disable-static \
            --with-gzip --with-xz --with-lz4 --with-zstd --with-bzip2 \
            --without-lzo --without-selinux \
            --disable-doxygen-doc --disable-dependency-tracking
        make $JOBS
        make install DESTDIR="$COMP_ROOT"
    )
    stage_root "$COMP_ROOT"
    local t
    for t in gensquashfs rdsquashfs sqfs2tar sqfsdiff tar2sqfs; do
        test -x "$DESTDIR/usr/bin/$t" || fail "/usr/bin/$t was not staged"
        test -f "$DESTDIR/usr/share/man/man1/$t.1" || fail "$t.1 was not staged"
    done
    test -f "$DESTDIR/usr/include/sqfs/predef.h" || fail "sqfs/predef.h was not staged"
    test -f "$DESTDIR/usr/libdata/pkgconfig/libsquashfs1.pc" || fail "libsquashfs1.pc was not staged"
    test -e "$DESTDIR/usr/lib/libsquashfs.so" || fail "libsquashfs.so was not staged"
    needed_check "$DESTDIR/usr/bin/rdsquashfs" "libsquashfs"
    needed_check "$DESTDIR/usr/lib/libsquashfs.so.1" "libzstd"
    needed_check "$DESTDIR/usr/lib/libsquashfs.so.1" "liblz4"
    needed_check "$DESTDIR/usr/lib/libsquashfs.so.1" "liblzma"
    return 0
}

# =============================================================================
# squashfuse (nextbsd/nextbsd-contrib#9) — see src/squashfuse/NEXTBSD.md
# =============================================================================
# The two FUSE drivers: squashfuse (high-level API) and squashfuse_ll
# (low-level, multithreaded, faster), with their man pages. Both link
# squashfuse's own code statically (upstream's convenience libraries), so
# libsquashfuse and its headers are not shipped; nothing here uses them.
# Every decompressor except LZO. The libraries' flags are given directly as
# the pkgconfig_* variables configure documents for overriding pkg-config;
# fuse3 found that way makes configure select the FUSE 3.2 API. No configure
# check runs a test program.
build_squashfuse() {
    comp "squashfuse [autoconf cross]"
    dep_check squashfuse libzstd.so liblz4.so libfuse3.so
    fresh_dirs squashfuse
    local ar ranlib strip p
    ar=$(llvm_tool llvm-ar); ranlib=$(llvm_tool llvm-ranlib); strip=$(llvm_tool llvm-strip)
    copy_release "$SRC/squashfuse/dist"
    (
        cd "$COMP_BUILD"
        CC="$CROSS_CC --sysroot=$SYSROOT" \
        CFLAGS="-O2 -pipe" \
        CPPFLAGS="-I$DESTDIR/usr/include -I$SYSROOT/usr/include" \
        LDFLAGS="-L$DESTDIR/usr/lib -L$SYSROOT/usr/lib" \
        AR="$ar" RANLIB="$ranlib" STRIP="$strip" \
        PKG_CONFIG_LIBDIR="$SYSROOT/usr/libdata/pkgconfig" \
        PKG_CONFIG_SYSROOT_DIR="$SYSROOT" \
        pkgconfig_ZLIB_CFLAGS="-I$SYSROOT/usr/include" pkgconfig_ZLIB_LIBS="-lz" \
        pkgconfig_XZ_CFLAGS="-I$SYSROOT/usr/include" pkgconfig_XZ_LIBS="-llzma" \
        pkgconfig_LZ4_CFLAGS="-I$DESTDIR/usr/include" pkgconfig_LZ4_LIBS="-L$DESTDIR/usr/lib -llz4" \
        pkgconfig_ZSTD_CFLAGS="-I$DESTDIR/usr/include" pkgconfig_ZSTD_LIBS="-L$DESTDIR/usr/lib -lzstd" \
        pkgconfig_fuse3_CFLAGS="-I$DESTDIR/usr/include/fuse3" \
        pkgconfig_fuse3_LIBS="-L$DESTDIR/usr/lib -lfuse3 -lpthread" \
        ./configure \
            --build="$BUILD_TRIPLE" --host="$CROSS_TRIPLE" \
            --prefix=/usr --mandir=/usr/share/man \
            --with-pkgconfigdir=/usr/libdata/pkgconfig \
            --enable-shared --disable-static \
            --disable-demo --without-lzo \
            --disable-dependency-tracking
        make $JOBS
        mkdir -p "$COMP_ROOT/usr/bin" "$COMP_ROOT/usr/share/man/man1"
        for p in squashfuse squashfuse_ll; do
            ./libtool --mode=install install -m 0555 "$p" "$COMP_ROOT/usr/bin/$p"
            install -m 0444 "$p.1" "$COMP_ROOT/usr/share/man/man1/$p.1"
        done
    )
    stage_root "$COMP_ROOT"
    for p in squashfuse squashfuse_ll; do
        test -x "$DESTDIR/usr/bin/$p" || fail "/usr/bin/$p was not staged"
        needed_check "$DESTDIR/usr/bin/$p" "libfuse3"
        needed_check "$DESTDIR/usr/bin/$p" "libzstd"
    done
    return 0
}

# =============================================================================
# driver
# =============================================================================
# Add a component: write build_<name>() above (hyphens in the name become
# underscores in the function) and append <name> here. zstd, lz4 and libfuse
# must come before squashfs-tools-ng and squashfuse, which link them.
COMPONENTS="sudo pico zsh zsh-autosuggestions zsh-completions zsh-syntax-highlighting zstd lz4 libfuse squashfs-tools-ng squashfuse"

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
    "build_$(printf '%s' "$c" | tr - _)"
done

echo
echo "==> staged into $DESTDIR:"
( cd "$DESTDIR" && find . -type f | sort | sed 's#^\.##' )
