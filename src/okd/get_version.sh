#!/bin/bash
set -euo pipefail

function usage() {
    echo "Usage: $(basename "$0") <x.y | latest>" >&2
    echo "" >&2
    echo "Get the latest OKD version tag based on the specified 'x.y' or 'latest' command line argument" >&2
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

#
# Main
#
if [ $# -ne 1 ]; then
    usage
fi
OKD_XY="$1"

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
cat "${query_file}" | grep "^${OKD_XY}" | sort -V > "${version_file}" || true
if [ ! -s "${version_file}" ]; then
    echo "ERROR: No OKD version tags found for the specified '${OKD_XY}' base version" >&2
    exit 1
fi

# Get the latest version tag giving priority to the released versions
OKD_TAG="$(grep -Ev '\.rc\.|\.ec\.' "${version_file}" | tail -1 || true)"
# If no released version tag is found, use the latest version tag
if [ -z "${OKD_TAG}" ]; then
    OKD_TAG="$(tail -1 "${version_file}")"
fi

echo "${OKD_TAG}"
