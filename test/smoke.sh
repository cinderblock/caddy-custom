#!/bin/bash
# Smoke-test a built caddy-custom image.
#
# Usage: test/smoke.sh <image>
#
# 1. `caddy version` is the CADDY_VERSION the Dockerfile pins.
# 2. Every plugin the Dockerfile adds (`--with <module>@<version>`) is in the
#    binary's build info, at that version.
# 3. `caddy validate` accepts test/Caddyfile, which uses FrankenPHP and the
#    other plugins. validate provisions every module, which is where a
#    FrankenPHP minor that changed its config once failed.
set -euo pipefail

image="${1:?usage: $0 <image>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dockerfile="${root}/Dockerfile"

caddy() {
	docker run --rm --entrypoint caddy "$@"
}

want=$(sed -nE 's/^ARG CADDY_VERSION=(.+)$/\1/p' "$dockerfile")
got=$(caddy "$image" version)
echo "caddy version: ${got}"
case "$got" in
"v${want} "* | "v${want}") ;;
*)
	echo "::error::image runs Caddy '${got}', the Dockerfile pins ${want}" >&2
	exit 1
	;;
esac

info=$(caddy "$image" build-info)
missing=0
while read -r module version; do
	if grep -qE "^dep[[:space:]]+${module}[[:space:]]+${version}([[:space:]]|$)" <<<"$info"; then
		echo "ok: ${module} ${version}"
	else
		echo "::error::${module} ${version} is not in the binary's build info" >&2
		missing=1
	fi
done < <(sed -nE 's/^[[:space:]]*--with ([^@[:space:]]+)@([^[:space:]\\]+).*/\1 \2/p' "$dockerfile")
[ "$missing" -eq 0 ]

caddy -v "${root}/test:/test:ro" "$image" validate --config /test/Caddyfile --adapter caddyfile
echo "Smoke test passed: ${image}"
