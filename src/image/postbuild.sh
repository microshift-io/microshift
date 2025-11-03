#!/bin/bash 
set -euo pipefail
set -x

# Variables
BUILDER_RPM_REPO_PATH="$1"

# Create a local RPM repository and add SRPMs on top of it
mkdir -p "${BUILDER_RPM_REPO_PATH}/srpms"
createrepo -v "${BUILDER_RPM_REPO_PATH}"
cp -r "${BUILDER_RPM_REPO_PATH}/../SRPMS/." "${BUILDER_RPM_REPO_PATH}/srpms/"
