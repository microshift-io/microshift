#!/bin/bash
set -euo pipefail

QUERY_URL_AMD64=${QUERY_URL_AMD64:-quay.io/okd}
QUERY_URL_ARM64=${QUERY_URL_ARM64:-ghcr.io/microshift-io/okd}

function usage() {
    echo "Usage: $(basename "$0") <latest-amd64 | latest-arm64> [x.y]" >&2
    echo "" >&2
    echo "Get the latest OKD version tag based on the specified 'latest-amd64'" >&2
    echo "or 'latest-arm64' command line argument." >&2
    echo "" >&2
    echo "The optional second argument restricts the lookup to a specific OKD" >&2
    echo "x.y stream (e.g. '4.22'). Without it, the highest available stream" >&2
    echo "is used, which follows the OKD release train." >&2
    exit 1
}

function get_okd_version_tags() {
    local -r query_url="$1"
    skopeo list-tags "docker://${query_url}" | jq -r '.Tags[]' | sort -V
}

#
# Main
#
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
fi
OKD_STREAM="${2:-}"
# The stream ends up in a regular expression below, so anything but a plain x.y
# value is rejected: '4.22|5.0' would silently match more than one stream.
if [ -n "${OKD_STREAM}" ] && ! [[ "${OKD_STREAM}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: OKD stream must use the x.y format, got '${OKD_STREAM}'" >&2
    exit 1
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

if [ -n "${OKD_STREAM}" ]; then
    # Only consider tags of the requested OKD x.y stream. This is what allows
    # building a MicroShift release branch against the matching OKD payload
    # instead of the newest one.
    OKD_XY="${OKD_STREAM}"
    TAG_LIST="$(echo "${TAG_LIST}" | grep -E "^${OKD_STREAM//./\\.}\\." || true)"
else
    # Compute the latest OKD x.y base version
    OKD_XY="$(echo "${TAG_LIST}" | tail -1)"
    OKD_XY="${OKD_XY%.*}"

    # Update the list to only include the latest OKD x.y base version
    TAG_LIST="$(echo "${TAG_LIST}" | grep -E "^${OKD_XY}")"
fi

# Get the latest version tag giving priority to the released versions
TAG_LATEST="$(echo "${TAG_LIST}" | grep -Ev '\.rc\.|\.ec\.' | tail -1 || true)"
if [ -z "${TAG_LATEST}" ]; then
    # If no released version tag is found, use the latest version tag
    TAG_LATEST="$(echo "${TAG_LIST}" | tail -1)"
fi

# If no OKD version tag was found, exit with an error
if [ -z "${TAG_LATEST}" ]; then
    echo "ERROR: No OKD version tag found for the OKD base version '${OKD_XY}'" >&2
    exit 1
fi
echo "${TAG_LATEST}"
