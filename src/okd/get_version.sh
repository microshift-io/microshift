#!/bin/bash
set -euo pipefail

QUERY_URL_AMD64=${QUERY_URL_AMD64:-quay.io/okd}
QUERY_URL_ARM64=${QUERY_URL_ARM64:-ghcr.io/microshift-io/okd}

function usage() {
    echo "Usage: $(basename "$0") <latest-amd64 | latest-arm64>" >&2
    echo "" >&2
    echo "Get the latest OKD version tag based on the specified 'latest-amd64'" >&2
    echo "or 'latest-arm64' command line argument." >&2
    exit 1
}

function get_amd64_version_tags() {
    local -r query_file="$1"

    if ! skopeo list-tags "docker://${QUERY_URL_AMD64}/scos-release" | jq -r .Tags[] >> "${query_file}" ; then
        echo "ERROR: Failed to get the OKD version tags from '${QUERY_URL_AMD64}/scos-release'" >&2
        exit 1
    fi
}

function get_arm64_version_tags() {
    local -r query_file="$1"

    if ! skopeo list-tags "docker://${QUERY_URL_ARM64}/okd-release-arm64" | jq -r .Tags[] >> "${query_file}" ; then
        echo "ERROR: Failed to get the OKD version tags from '${QUERY_URL_ARM64}/okd-release-arm64'" >&2
        exit 1
    fi
}

#
# Main
#
if [ $# -ne 1 ]; then
    usage
fi
OKD_TAG=""

query_file="$(mktemp /tmp/okd-query-XXXXXX)"
version_file="$(mktemp /tmp/okd-version-XXXXXX)"
trap 'rm -f "${query_file}" "${version_file}"' EXIT

# Read all version tags from the repositories
case "$1" in
    latest-amd64)
        get_amd64_version_tags "${query_file}"
        ;;
    latest-arm64)
        get_arm64_version_tags "${query_file}"
        ;;
    *)
        usage
        ;;
esac

# Compute the latest OKD x.y base version
OKD_XY="$(cat "${query_file}" | sort -V | tail -1)"
OKD_XY="${OKD_XY%.*}"

# Filter the version tags for the latest OKD x.y base version
grep "^${OKD_XY}" "${query_file}" | sort -V > "${version_file}" || true

# Get the latest version tag giving priority to the released versions
OKD_TAG="$(grep -Ev '\.rc\.|\.ec\.' "${version_file}" | tail -1 || true)"
if [ -z "${OKD_TAG}" ]; then
    # If no released version tag is found, use the latest version tag
    OKD_TAG="$(tail -1 "${version_file}")"
fi

# If no OKD version tag was found, exit with an error
if [ -z "${OKD_TAG}" ]; then
    echo "ERROR: No OKD version tag found for the latest OKD base version '${OKD_XY}'" >&2
    exit 1
fi
echo "${OKD_TAG}"
