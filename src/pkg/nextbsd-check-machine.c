/*
 * nextbsd-check-machine.c: build-time check for NextBSD patch 0003.
 *
 * Built and run on the build host by build_pkg (build-contrib.sh), against the
 * patched build copy: pkg's own libucl (external/libucl) and the patch's
 * libpkg/private/nextbsd_machine.h. The target pkg cannot run on the runner,
 * so this parses a NextBSD.conf-style url with the variables registered the
 * way patched libpkg registers them (pkg_config.c, config_parser_vars_register:
 * ARCH = pkg_arch_to_string() of the computed ABI, MACHINE =
 * nextbsd_machine() of the same string) and checks the expansion.
 *
 * usage: nextbsd-check-machine <ABI> <expected url>
 * The ABI's last field is ARCH: pkg_abi_to_string() builds the ABI from
 * pkg_arch_to_string(), e.g. FreeBSD:15:aarch64 -> aarch64.
 */
#include <stdio.h>
#include <string.h>
#include <ucl.h>
#include "nextbsd_machine.h"

int
main(int argc, char **argv)
{
	/* argv[1]: ABI (FreeBSD:15:aarch64); argv[2]: expected url */
	char arch[64];
	const char *abi = argv[1], *p = strrchr(abi, ':');
	const char *conf = "NextBSD: { url: \"https://github.com/nextbsd/nextbsd-pkg/releases/download/continuous-${MACHINE}\" }";
	struct ucl_parser *parser;
	const ucl_object_t *u;
	ucl_object_t *top;

	if (argc != 3 || p == NULL)
		return (2);
	snprintf(arch, sizeof(arch), "%s", p + 1);
	parser = ucl_parser_new(0);
	ucl_parser_register_variable(parser, "ARCH", arch);
	ucl_parser_register_variable(parser, "MACHINE", nextbsd_machine(arch));
	if (!ucl_parser_add_string(parser, conf, 0)) {
		fprintf(stderr, "parse: %s\n", ucl_parser_get_error(parser));
		return (1);
	}
	top = ucl_parser_get_object(parser);
	u = ucl_object_lookup_path(top, "NextBSD.url");
	printf("%s -> %s\n", abi, u ? ucl_object_tostring(u) : "(none)");
	return (u != NULL && strcmp(ucl_object_tostring(u), argv[2]) == 0 ? 0 : 1);
}
