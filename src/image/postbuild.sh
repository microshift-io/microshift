#!/bin/bash 
set -euo pipefail
set -x

# Variables
BUILDER_RPM_REPO_PATH="$1"

# Delete unsupported RPMs, which are built unconditionally.
# To add support for an RPM, undo the file removal and add a presubmit test for it.
rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-ai-model-serving*.rpm
rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-cert-manager*.rpm
rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-gateway-api*.rpm
rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-low-latency*.rpm
rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-multus*.rpm
rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-observability*.rpm

# Create a local RPM repository and add SRPMs on top of it
mkdir -p "${BUILDER_RPM_REPO_PATH}/srpms"
createrepo -v "${BUILDER_RPM_REPO_PATH}"
cp -r "${BUILDER_RPM_REPO_PATH}/../SRPMS/." "${BUILDER_RPM_REPO_PATH}/srpms/"
