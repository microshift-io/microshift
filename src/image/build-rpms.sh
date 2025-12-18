#!/usr/bin/env bash
set -euo pipefail

# Primary purpose of this script is to build the MicroShift RPMs and SRPMs
# with adjusted version string.
# Using `make {rpm,srpm}` it would hardcode a meaningless version string based on downstream git variables
# which would not provide good information to identify the build and trace back its contents.
# Following script overrides the version to include information about the downstream version and commit, and OKD tag.

usage() {
    echo "Usage: $(basename "$0") <all | rpm | srpm>"
    echo ""
    echo "Script expects to be run from the root of the MicroShift repository"
    echo "Following env vars are required: USHIFT_GITREF, OKD_VERSION_TAG"
    exit 1
}

if [[ "${#}" -ne 1 ]]; then
    usage
fi

target="${1}"

case "${target}" in
    all) :;;
    rpm) :;;
    srpm) :;;
    *)
        echo -e "ERROR: Unknown command: ${target}\n"
        usage
        ;;
esac

if [[ -z "${USHIFT_GITREF}" ]]; then
    echo "ERROR: USHIFT_GITREF is not set"
    usage
fi

if [[ -z "${OKD_VERSION_TAG}" ]]; then
    echo "ERROR: OKD_VERSION_TAG is not set"
    usage
fi

SOURCE_GIT_COMMIT="$(git rev-parse --short 'HEAD^{commit}')"

# MICROSHIFT_VERSION must start with X.Y.Z for the internals to correctly parse the version.
# If USHIFT_GITREF is a tag, use it. Otherwise parse the version from Makefile.version.*.var file.
if [[ $(git tag -l "${USHIFT_GITREF}") ]]; then
    MICROSHIFT_VERSION="${USHIFT_GITREF}"
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
SOURCE_GIT_TAG="${MICROSHIFT_VERSION}"
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
    echo "${MICROSHIFT_VERSION}" > _output/rpmbuild/RPMS/version.txt
fi

if [[ "${target}" == "all" || "${target}" == "srpm" ]]; then
    ./packaging/rpm/make-rpm.sh srpm local
    echo "${MICROSHIFT_VERSION}" > _output/rpmbuild/SRPMS/version.txt
fi

