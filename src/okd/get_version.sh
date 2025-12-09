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

function get_okd_version_tags() {
    local -r query_url="$1"
    skopeo list-tags "docker://${query_url}" | jq -r '.Tags[]' | sort -V
}

#
# Main
#
if [ $# -ne 1 ]; then
    usage
fi
TAG_LIST=""
TAG_LATEST=""

# Read all version tags from the repositories
case "$1" in
    latest-amd64)
        TAG_LIST="$(get_okd_version_tags "${QUERY_URL_AMD64}/scos-release")"
        ;;
    latest-arm64)
        TAG_LIST="$(get_okd_version_tags "${QUERY_URL_ARM64}/okd-release-arm64")"
        ;;
    *)
        usage
        ;;
esac

if [ -z "${TAG_LIST}" ]; then
    echo "ERROR: No OKD version tags found" >&2
    exit 1
fi

# Compute the latest OKD x.y base version
OKD_XY="$(echo "${TAG_LIST}" | tail -1)"
OKD_XY="${OKD_XY%.*}"

# Update the list to only include the latest OKD x.y base version
TAG_LIST="$(echo "${TAG_LIST}" | grep -E "^${OKD_XY}")"

# Get the latest version tag giving priority to the released versions
TAG_LATEST="$(echo "${TAG_LIST}" | grep -Ev '\.rc\.|\.ec\.' | tail -1 || true)"
if [ -z "${TAG_LATEST}" ]; then
    # If no released version tag is found, use the latest version tag
    TAG_LATEST="$(echo "${TAG_LIST}" | tail -1)"
fi

# If no OKD version tag was found, exit with an error
if [ -z "${TAG_LATEST}" ]; then
    echo "ERROR: No OKD version tag found for the latest OKD base version '${OKD_XY}'" >&2
    exit 1
fi
echo "${TAG_LATEST}"
