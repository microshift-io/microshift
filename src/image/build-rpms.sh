#!/usr/bin/env bash
set -xeuo pipefail

# if [[ "$#" -ne 1 || ("${1}" != "rpm" && "${1}" != "srpm") ]]; then
#     echo "Script requires exactly one argument: rpm or srpm"
#     exit 1
# fi

cd "${HOME}/microshift"

MICROSHIFT_VERSION="${USHIFT_BRANCH}-${OKD_VERSION_TAG}"
RPM_RELEASE="1"
SOURCE_GIT_COMMIT="$(git rev-parse --short 'HEAD^{commit}')"
SOURCE_GIT_TAG="$(git describe --long --tags --abbrev=7 --match 'v[0-9]*' || echo "v0.0.0-unknown-${SOURCE_GIT_COMMIT}")"
SOURCE_GIT_TREE_STATE=clean
MICROSHIFT_VARIANT=community

export MICROSHIFT_VERSION
export RPM_RELEASE
export SOURCE_GIT_TAG
export SOURCE_GIT_COMMIT
export SOURCE_GIT_TREE_STATE
export MICROSHIFT_VARIANT

./packaging/rpm/make-rpm.sh rpm local
./packaging/rpm/make-rpm.sh srpm local
