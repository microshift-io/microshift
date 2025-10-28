#!/usr/bin/env bash
set -xeuo pipefail

# Primary purpose of this script is to build the MicroShift RPMs and SRPMs
# with adjusted version string.
# Using `make {rpm,srpm}` it would hardcode a meaningless version string based on downstream git variables
# which would not provide good information to identify the build and trace back its contents.
# Following script overrides the version to include information about the downstream version and commit, and OKD tag.

target=all
if [[ "$#" -eq 1 ]]; then
    if [[ "${1}" != "all" && "${1}" != "rpm" && "${1}" != "srpm" ]]; then
        echo "Script accepts at most one argument: all, rpm or srpm"
        echo "If no argument is provided, the default is 'all'"
        exit 1
    fi
    target="${1}"
fi

cd "${HOME}/microshift"

SOURCE_GIT_COMMIT="$(git rev-parse --short 'HEAD^{commit}')"

# MICROSHIFT_VERSION must start with X.Y.Z for the internals to correctly parse the version.
# If USHIFT_BRANCH is a tag, use it. Otherwise parse the version from Makefile.version.*.var file.
if [[ $(git tag -l "${USHIFT_BRANCH}") ]]; then
    MICROSHIFT_VERSION="${USHIFT_BRANCH}"
else
    MICROSHIFT_VERSION="$(awk -F'[=.-]' '{print $2 "." $3 "." $4}' Makefile.version.aarch64.var | sed -e 's/ //g')"
fi
# Example results:
# - 4.21.0_ga9cd00b34_4.21.0_okd_scos.ec.5                for build against HEAD of main which was 4.21 at the time.
# - 4.20.0-202510201126.p0-g1c4675ace_4.20.0-okd-scos.6   for build against a specific tag.
MICROSHIFT_VERSION="${MICROSHIFT_VERSION}-g${SOURCE_GIT_COMMIT}-${OKD_VERSION_TAG}"
# MicroShift's make-rpm.sh makes this substitution. Although we don't use the script,
# let's do it as well for keeping the version consistent with existing downstream RPMs.
# Version is also used for release.md file.
MICROSHIFT_VERSION=${MICROSHIFT_VERSION//-/_}

RPM_RELEASE="1"
SOURCE_GIT_TAG="$(git describe --long --tags --abbrev=7 --match 'v[0-9]*' || echo "v0.0.0-unknown-${SOURCE_GIT_COMMIT}")"
SOURCE_GIT_TREE_STATE=clean # Because we're updating downstream specfile, but that shouldn't be a reason to have -dirty suffix.
MICROSHIFT_VARIANT=community

export MICROSHIFT_VERSION
export RPM_RELEASE
export SOURCE_GIT_TAG
export SOURCE_GIT_COMMIT
export SOURCE_GIT_TREE_STATE
export MICROSHIFT_VARIANT

if [[ "${target}" == "all" || "${target}" == "rpm" ]]; then
    ./packaging/rpm/make-rpm.sh rpm local
fi

if [[ "${target}" == "all" || "${target}" == "srpm" ]]; then
    ./packaging/rpm/make-rpm.sh srpm local
fi

echo "${MICROSHIFT_VERSION}" > "${HOME}/microshift/_output/rpmbuild/version.txt"
