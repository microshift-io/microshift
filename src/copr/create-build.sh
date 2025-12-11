#!/usr/bin/env bash
set -euo pipefail

out="$(copr-cli --config /run/secrets/copr-cfg build --nowait "${COPR_REPO_NAME}" /srpms/microshift*.src.rpm)"
echo "${out}"
build=$(echo "${out}" | grep "Created builds" | cut -d: -f2 | xargs)
if [[ -z "${build}" ]]; then
    echo "ERROR: Failed to extract build ID from copr-cli output"
    exit 1
fi
echo "${build}" > /srpms/build.txt
