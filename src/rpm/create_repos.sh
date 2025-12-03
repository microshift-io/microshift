#!/bin/bash
set -euo pipefail

USHIFT_LOCAL_REPO_FILE=/etc/yum.repos.d/microshift-local.repo
OCP_MIRROR_REPO_FILE=/etc/yum.repos.d/openshift-mirror-beta.repo

function usage() {
    echo "Usage: $(basename "$0") [-create <repo_path>] | [-deps-only <version>] | [-delete]"
    exit 1
}

function create_deps_repo() {
    local -r repo_version=$1
    cat > "${OCP_MIRROR_REPO_FILE}" <<EOF
[openshift-mirror-beta]
name=OpenShift Mirror Beta Repository
baseurl=https://mirror.openshift.com/pub/openshift-v4/$(uname -m)/dependencies/rpms/${repo_version}-el9-beta/
enabled=1
gpgcheck=0
skip_if_unavailable=0
EOF
}

function create_repos() {
    local -r repo_path=$1
    local -r repo_version=$2

    cat > "${USHIFT_LOCAL_REPO_FILE}" <<EOF
[microshift-local]
name=MicroShift Local Repository
baseurl=${repo_path}
enabled=1
gpgcheck=0
skip_if_unavailable=0
EOF

    create_deps_repo "${repo_version}"
}

function delete_repos() {
    rm -vf /etc/yum.repos.d/microshift-local.repo
    rm -vf /etc/yum.repos.d/openshift-mirror-beta.repo
}

if [ $# -lt 1 ] ; then
    usage
fi

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

case $1 in
-create)
    repo_path="$2"
    if [ ! -d "${repo_path}" ] ; then
        echo "ERROR: The RPM repository path '${repo_path}' does not exist"
        exit 1
    fi

    repo_version="$(dnf --quiet --disablerepo="*" \
        --repofrompath=ushift,file://"${repo_path}" \
        --enablerepo=ushift repoquery --qf "%{VERSION}" microshift | cut -d. -f1,2)"
    if [ -z "${repo_version:-}" ] ; then
        echo "ERROR: Could not determine the MicroShift version from the RPM repository at '${repo_path}'"
        exit 1
    fi
    create_repos "${repo_path}" "${repo_version}"
    ;;

-deps-only)
    repo_version="$2"
    create_deps_repo "${repo_version}"
    ;;

-delete)
    delete_repos
    ;;

*)
    usage
esac
