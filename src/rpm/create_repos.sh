#!/bin/bash
set -euo pipefail

YUM_REPOS_D=/etc/yum.repos.d
USHIFT_LOCAL_REPO_FILE=microshift-local.repo
OCP_MIRROR_REPO_FILE_PREFIX=microshift-deps

function usage() {
    echo "Usage: $(basename "$0") [-create <repo_path>] | [-rhocp-mirror] | [-delete]"
    exit 1
}

function create_rhocp_repo() {
    local -r repo_version=$1

    local -r file="${YUM_REPOS_D}/${OCP_MIRROR_REPO_FILE_PREFIX}-${repo_version}.repo"
    cat > "${file}" <<EOF
[openshift-mirror-beta]
name=OpenShift Mirror Beta Repository
baseurl=https://mirror.openshift.com/pub/openshift-v4/$(uname -m)/dependencies/rpms/${repo_version}-el9-beta/
enabled=1
gpgcheck=0
skip_if_unavailable=0
EOF
}

function create_local_microshift_repo() {
    local -r repo_path=$1

    cat > "${YUM_REPOS_D}/${USHIFT_LOCAL_REPO_FILE}" <<EOF
[microshift-local]
name=MicroShift Local Repository
baseurl=${repo_path}
enabled=1
gpgcheck=0
skip_if_unavailable=0
EOF
}

function delete_repos() {
    rm -vf "${YUM_REPOS_D}/${USHIFT_LOCAL_REPO_FILE}"
    find "${YUM_REPOS_D}/" -iname "${OCP_MIRROR_REPO_FILE_PREFIX}*" -delete -print
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
    create_local_microshift_repo "${repo_path}"

    repo_version="$(dnf --quiet --disablerepo="*" \
        --repofrompath=ushift,file://"${repo_path}" \
        --enablerepo=ushift repoquery --qf "%{VERSION}" microshift | cut -d. -f1,2)"
    if [ -z "${repo_version:-}" ] ; then
        echo "ERROR: Could not determine the MicroShift version from the RPM repository at '${repo_path}'"
        exit 1
    fi
    create_rhocp_repo "${repo_version}"
    ;;

-rhocp-mirror)
    repo_version=$(dnf repoquery --qf '%{VERSION}' --latest-limit=1 microshift 2>/dev/null | cut -d. -f1,2)
    if [ -z "${repo_version}" ] ; then
        echo "ERROR: Failed to find version of MicroShift available in the repositories"
        usage
    fi
    create_rhocp_repo "${repo_version}"
    ;;

-delete)
    delete_repos
    ;;

*)
    usage
esac
