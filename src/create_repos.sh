#!/bin/bash
set -euo pipefail

USHIFT_LOCAL_REPO_FILE=/etc/yum.repos.d/microshift-local.repo
OCP_MIRROR_REPO_FILE=/etc/yum.repos.d/openshift-mirror-beta.repo

function usage() {
    echo "Usage: $(basename "$0") [-create <repo_path>] | [-delete]"
    exit 1
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

    cat > "${OCP_MIRROR_REPO_FILE}" <<EOF
[openshift-mirror-beta]
name=OpenShift Mirror Beta Repository
baseurl=https://mirror.openshift.com/pub/openshift-v4/$(uname -m)/dependencies/rpms/${repo_version}-el9-beta/
enabled=1
gpgcheck=0
skip_if_unavailable=0
EOF
}

function delete_repos() {
    rm -vf /etc/yum.repos.d/microshift-local.repo
    rm -vf /etc/yum.repos.d/openshift-mirror-beta.repo
}

if [ $# -lt 1 ] ; then
    usage
fi

case $1 in
-create)
    repo_path="$2"
    repo_version="$(dnf --quiet --disablerepo="*" --repofrompath=ushift,file://"${repo_path}" --enablerepo=ushift repoquery --qf "%{VERSION}" microshift | cut -d. -f1,2)"
    create_repos "${repo_path}" "${repo_version}"
    ;;
-delete)
    delete_repos
    ;;
*)
    usage
esac
