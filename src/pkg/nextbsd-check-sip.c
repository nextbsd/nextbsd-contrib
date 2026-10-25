/*
 * nextbsd-check-sip.c: build-time check for NextBSD patch 0004.
 *
 * Built and run on the build host by build_pkg (build-contrib.sh) against the
 * patch's libpkg/private/nextbsd_sip.h, the one table and function libpkg's
 * nextbsd_check_install() uses to decide where a package that is not a
 * NextBSD package may install. Exits non-zero on any wrong answer.
 */
#include <stdio.h>
#include "nextbsd_sip.h"

static const struct {
	const char *path;
	int allowed;
} cases[] = {
	{ "/usr/local/bin/git",			1 },
	{ "/usr/local/share/doc/git/",		1 },
	{ "/usr/local",				1 },
	{ "/usr/local/",			1 },
	{ "/var/db/git",			1 },
	{ "/var",				1 },
	{ "/usr/bin/uname",			0 },	/* FreeBSD-runtime */
	{ "/etc/rc.conf",			0 },
	{ "/boot/kernel/kernel",		0 },	/* FreeBSD-kernel-generic */
	{ "/boot/modules/i915kms.ko",		0 },	/* drm-kmod */
	{ "/usr/lib/libc.so.7",			0 },
	{ "/sbin/init",				0 },
	{ "/usr/localx/bin/x",			0 },
	{ "/variable/x",			0 },
	{ "/usr/local/../../etc/passwd",	0 },
	{ "/var/..",				0 },
	{ "usr/local/bin/x",			0 },	/* not absolute */
	{ "/compat/linux/bin/sh",		0 },	/* not (yet) allowed */
};

int
main(void)
{
	int bad = 0;

	for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
		int got = nextbsd_sip_path_allowed(cases[i].path);

		printf("%-32s %s%s\n", cases[i].path,
		    got ? "allowed" : "refused",
		    got != cases[i].allowed ? "  <-- WRONG" : "");
		if (got != cases[i].allowed)
			bad = 1;
	}
	return (bad);
}
