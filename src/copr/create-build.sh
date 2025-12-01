#!/usr/bin/env bash
set -euo pipefail

out="$(copr-cli --config /run/secrets/copr-cfg build --nowait "${COPR_REPO_NAME}" /srpms/microshift*.src.rpm)"
echo "${out}"
build=$(echo "${out}" | grep "Created builds" | cut -d: -f2 | xargs)
echo "${build}" > /srpms/build.txt
