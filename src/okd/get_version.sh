#!/bin/bash
set -euo pipefail

TARGET_REGISTRY=${TARGET_REGISTRY:-ghcr.io/microshift-io/okd}

function usage() {
    echo "Usage: $(basename "$0") [-no-arm64] <x.y | latest>" >&2
    echo "" >&2
    echo "Get the latest OKD version tag based on the specified 'x.y' or 'latest'" >&2
    echo "command line argument. The returned version must be available on both" >&2
    echo "x86_64 and aarch64 platforms unless '-no-arm64' is specified." >&2
    exit 1
}

function get_okd_version_tags() {
    local -r query_file="$1"

    local npage=1
    local more_pages=true

    while [ "${more_pages}" = "true" ]; do
        local query_url="https://quay.io/api/v1/repository/okd/scos-release/tag/?limit=100&page=${npage}"
        local query_response

        if ! query_response="$(curl -s --max-time 60 "${query_url}")" ; then
            echo "ERROR: Failed to query the OKD version tags from '${query_url}'" >&2
            exit 1
        fi

        # Save the current page content to the query file
        if ! echo "${query_response}" | jq -r ".tags[].name" >> "${query_file}" ; then
            echo "ERROR: Failed to save the current page content to '${query_file}'" >&2
            exit 1
        fi
        # Check if there are more pages to query
        if ! more_pages="$(echo "${query_response}" | jq -r '.has_additional')" ; then
            echo "ERROR: Failed to check if there are more pages to query from '${query_url}'" >&2
            exit 1
        fi
        # Increment the page number
        npage=$(( npage + 1 ))
    done
}

function pop_latest_version_tag() {
    local -r version_file="$1"

    local latest_version_tag="$(grep -Ev '\.rc\.|\.ec\.' "${version_file}" | tail -1 || true)"
    if [ -z "${latest_version_tag}" ]; then
        latest_version_tag="$(tail -1 "${version_file}")"
    fi
    # Delete the version tag from the version file so that it is not considered again
    sed -i "/${latest_version_tag}/d" "${version_file}"
    # Return the latest version tag
    echo "${latest_version_tag}"
}

check_arm64_release_image_exists() {
    local -r okd_version="$1"
    local -r release_image="${TARGET_REGISTRY}/okd-release-arm64:${okd_version}"

    # Check if the release image exists, hardcoding the architecture to amd64 as
    # the source release image is only available for the amd64 architecture
    if skopeo inspect \
        --override-os="linux" \
        --override-arch="amd64" \
        --format "Digest: {{.Digest}}" "docker://${release_image}" &>/dev/null ; then
        return 0
    fi
    return 1
}

#
# Main
#
if [ $# -ne 1 ] && [ $# -ne 2 ]; then
    usage
fi
if [ $# -eq 2 ] && [ "$1" != "-no-arm64" ]; then
    usage
fi

OKD_XY="$1"
NO_ARM64=false
if [ "$1" = "-no-arm64" ]; then
    NO_ARM64=true
    OKD_XY="$2"
fi

version_file="$(mktemp /tmp/okd-version-XXXXXX)"
query_file="$(mktemp /tmp/okd-query-XXXXXX)"
trap 'rm -f "${version_file}" "${query_file}"' EXIT

# Read all version tags from the Quay repository
get_okd_version_tags "${query_file}"

# Compute the latest OKD x.y base version if 'latest' is specified
if [ "${OKD_XY}" = "latest" ]; then
    OKD_XY="$(cat "${query_file}" | sort -V | tail -1)"
    OKD_XY="${OKD_XY%.*}"
fi

# Filter the version tags for the specified 'x.y' base version
grep "^${OKD_XY}" "${query_file}" | sort -V > "${version_file}" || true
if [ ! -s "${version_file}" ]; then
    echo "ERROR: No OKD version tag found for the '${OKD_XY}' version" >&2
    exit 1
fi

# Try up to 3 times to get the latest version tag with both x86_64 and aarch64 release images available
OKD_TAG=""
for _ in {1..3}; do
    cur_tag="$(pop_latest_version_tag "${version_file}")"
    if [ "${NO_ARM64}" = "true" ] || check_arm64_release_image_exists "${cur_tag}" ; then
        OKD_TAG="${cur_tag}"
        break
    fi
done

# If no OKD version tag was found, exit with an error
if [ -z "${OKD_TAG}" ]; then
    echo "ERROR: No OKD version tag found for the '${OKD_XY}' version on both x86_64 and aarch64 architectures" >&2
    exit 1
fi
echo "${OKD_TAG}"
